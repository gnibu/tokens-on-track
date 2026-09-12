import AppKit
import Combine
import SwiftUI

/// Owns the current reading: loads the cache at launch, refreshes on a timer,
/// on wake, and on demand, and writes `usage.json` so a reading survives a
/// restart and the app has something to draw before the first fetch lands.
@MainActor
final class UsageStore: ObservableObject {
    /// One reading for the whole app: the menu bar scene and the AppKit-owned
    /// desktop card both need it, and only one of them can own it.
    static let shared = UsageStore()

    @Published private(set) var report: Report?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusImage: NSImage = StatusIcon.image(segments: [])
    /// Spells out both readings for whatever the item is drawn as, since the
    /// icon has room for one number and no room at all to label it.
    @Published private(set) var statusTooltip: String = "Tokens on Track — no reading yet"

    static var stateDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["AI_USAGE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: ("~/.local/share/ai-usage" as NSString).expandingTildeInPath)
    }

    static var cacheURL: URL { stateDirectory.appendingPathComponent("usage.json") }

    private var refreshTimer: Timer?
    private var scheduleBoundaryTimer: Timer?
    private var workSchedule = WorkSchedule.disabled
    private var preferenceWatches: Set<AnyCancellable> = []
    private var clockObservers: [NSObjectProtocol] = []

    private init() {
        let preferences = Preferences.shared
        workSchedule = preferences.workSchedule
        loadCache()
        redrawIcon()

        preferences.$refreshMinutes
            .removeDuplicates()
            .sink { [weak self] minutes in self?.scheduleTimer(minutes: minutes) }
            .store(in: &preferenceWatches)

        Publishers.CombineLatest4(
            preferences.$workingHoursEnabled,
            preferences.$workingWeekdays,
            preferences.$workingStartMinute,
            preferences.$workingEndMinute
        )
        .map { enabled, weekdays, start, end in
            WorkSchedule(
                enabled: enabled,
                weekdays: weekdays,
                startMinute: start,
                endMinute: end
            )
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] schedule in
            self?.workScheduleChanged(schedule)
        }
        .store(in: &preferenceWatches)

        clockObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.clockContextChanged()
                    self?.refreshIfStale(olderThan: 300)
                }
            },
            NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.clockContextChanged() }
            },
            NotificationCenter.default.addObserver(
                forName: .NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.clockContextChanged() }
            },
        ]

        scheduleNextBoundary()
        Task { await refresh() }
    }

    // ----------------------------------------------------------------- //

    /// The window in the most trouble, which is what the menu bar leads with.
    var worstWindow: (provider: Provider, window: UsageWindow)? {
        menuBarWindows(limit: 1).first
    }

    /// What the menu bar speaks for.
    func menuBarWindows(
        limit: Int,
        timing: Pace.Timing? = nil
    ) -> [(provider: Provider, window: UsageWindow)] {
        guard let report else { return [] }
        let timing = timing ?? Pace.Timing(schedule: workSchedule)
        let preferences = Preferences.shared
        // The bar draws from the same filtered set as the card, so hiding a
        // provider or the spark rows clears them from the menu bar too.
        return report.displaying(
            hiding: preferences.hiddenProviders,
            hideSpark: preferences.hideCodexSpark
        ).busiestWindows(
            limit: limit,
            fairShare: preferences.menuBarFairShare,
            timing: timing
        )
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let merged = (await Fetcher.fetchAll()).carryingOver(from: report)
        report = merged
        write(merged)
        redrawIcon()
        Notifier.evaluate(merged)
    }

    func refreshIfStale(olderThan seconds: TimeInterval) {
        let age = Date().timeIntervalSince1970 - Double(report?.updatedAt ?? 0)
        guard age > seconds else { return }
        Task { await refresh() }
    }

    // ----------------------------------------------------------------- //

    private func scheduleTimer(minutes: Double) {
        refreshTimer?.invalidate()
        let interval = max(60, minutes * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // Let the system coalesce the wake-up; a minute either way is fine.
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func redrawIcon() {
        let preferences = Preferences.shared
        let timing = Pace.Timing(schedule: workSchedule)
        let shown = menuBarWindows(limit: preferences.menuBarSlots, timing: timing)
        let segments = shown.map {
            StatusIcon.Segment(
                provider: $0.provider.name,
                window: $0.window.label,
                percent: $0.window.percent,
                text: Pace.reading(
                    $0.window,
                    mode: preferences.percentMode,
                    timing: timing
                ).text,
                color: Pace.color($0.window, timing: timing)
            )
        }

        // One line per segment drawn, in the order they appear in the bar, and
        // the sentence explaining the target once at the end rather than on each.
        let lines = shown.map {
            Pace.tooltip(
                source: "\($0.provider.name) \($0.window.label)",
                window: $0.window,
                explains: false,
                timing: timing
            )
        }
        statusTooltip = lines.isEmpty
            ? "Tokens on Track — no reading yet"
            : (lines + [Pace.targetExplainer]).joined(separator: "\n")

        var parts: StatusIcon.Parts = []
        if preferences.showLogoInMenuBar { parts.insert(.mark) }
        if preferences.showGaugeInMenuBar { parts.insert(.gauge) }
        if preferences.showPercentInMenuBar { parts.insert(.percent) }
        if preferences.showWindowInMenuBar { parts.insert(.window) }

        statusImage = StatusIcon.image(segments: segments, parts: parts)
    }

    /// Re-render after a preference change that only affects the icon.
    func iconPreferenceChanged() {
        redrawIcon()
    }

    /// Preference edits update every surface immediately but never manufacture
    /// a notification. Only an actual clock boundary or provider refresh is an
    /// alert evaluation point.
    private func workScheduleChanged(_ schedule: WorkSchedule) {
        workSchedule = schedule
        redrawIcon()
        scheduleNextBoundary()
    }

    private func clockContextChanged() {
        redrawIcon()
        if let report {
            Notifier.evaluate(report, evaluateUsage: false)
        }
        scheduleNextBoundary()
    }

    private func scheduleNextBoundary() {
        scheduleBoundaryTimer?.invalidate()
        scheduleBoundaryTimer = nil
        guard let boundary = workSchedule.nextBoundary(after: Date()) else { return }

        let timer = Timer(fire: boundary, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.redrawIcon()
                if let report = self.report {
                    Notifier.evaluate(report, evaluateUsage: false)
                }
                self.scheduleNextBoundary()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        scheduleBoundaryTimer = timer
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode(Report.self, from: data)
        else { return }
        report = cached
    }

    private func write(_ report: Report) {
        do {
            try FileManager.default.createDirectory(
                at: Self.stateDirectory, withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(report)
            let temporary = Self.cacheURL.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(Self.cacheURL, withItemAt: temporary)
        } catch {
            // The cache is a convenience for the other surfaces, never fatal.
            NSLog("ai-usage: could not write cache: \(error)")
        }
    }
}
