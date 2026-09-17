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
    @Published private(set) var hasSavedOpenRouterKey = OpenRouterKeychain.read() != nil
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

    /// How quickly to come back after a poll could not reach anyone. The
    /// user's interval otherwise; a minute is short enough that coming back
    /// from offline does not leave the card blank for a quarter of an hour.
    static let offlineRetryInterval: TimeInterval = 60

    /// The cadence the reader is told about: the user's interval, or a minute
    /// while every pollable provider is unreachable.
    var displayedCadence: TimeInterval {
        let configured = max(60, Preferences.shared.refreshMinutes * 60)
        guard report?.needsFastRetry == true else { return configured }
        return min(configured, Self.offlineRetryInterval)
    }

    /// True while the last poll could not reach anyone, so surfaces can show a
    /// loader next to the retry line rather than a static promise.
    var isOffline: Bool {
        report?.needsFastRetry == true
    }

    /// The same interval said for the reader: "every minute", "every 15 min".
    var retryCadenceLabel: String {
        let minutes = Int((displayedCadence / 60).rounded())
        return minutes == 1 ? "every minute" : "every \(minutes) min"
    }

    /// When each provider was last asked. Providers are polled on their own
    /// cadence, so this, not the report's clock, decides who is due.
    private var lastAttempt: [String: Date] = [:]
    private var refreshTimer: Timer?
    private var scheduleBoundaryTimer: Timer?
    private var workSchedule = WorkSchedule.disabled
    private var preferenceWatches: Set<AnyCancellable> = []
    private var clockObservers: [NSObjectProtocol] = []

    private init() {
        let preferences = Preferences.shared
        workSchedule = preferences.workSchedule
        loadCache()
        report = report?.rebudgetingOpenRouter(
            monthlyBudget: preferences.openRouterMonthlyBudget
        )
        redrawIcon()

        preferences.$refreshMinutes
            .removeDuplicates()
            .sink { [weak self] _ in self?.scheduleTimer() }
            .store(in: &preferenceWatches)

        preferences.$openRouterMonthlyBudget
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] budget in self?.openRouterBudgetChanged(budget) }
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
            hidingSpark: preferences.hiddenSpark
        ).busiestWindows(
            limit: limit,
            fairShare: preferences.menuBarFairShare,
            timing: timing
        )
    }

    /// Ask every provider now: the refresh button, wake, launch, and the
    /// normal interval.
    func refresh() async {
        await refresh(names: Fetcher.providerNames, full: true)
    }

    /// The timer's job: ask only the providers whose own cadence has come due,
    /// so an unreachable one is retried every minute while the rest keep the
    /// user's interval and are not hammered alongside it.
    private func refreshDue() async {
        let due = dueNames(at: Date())
        guard !due.isEmpty else {
            scheduleTimer()
            return
        }
        // Asking everyone is the normal interval again, so it stamps the
        // report's clock; a lone retry of a provider in trouble does not.
        let full = due.count == Fetcher.providerNames.count
        await refresh(names: due, full: full)
    }

    private func refresh(names: [String], full: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Charge each poll from when it started, so a slow timeout cannot push
        // the next try out past its cadence.
        let started = Date()
        for name in names { lastAttempt[name] = started }

        let fetched = await Fetcher.fetch(
            names: names,
            openRouterMonthlyBudget: Preferences.shared.openRouterMonthlyBudget
        )
        let merged = merging(fetched, full: full, at: Date())
        report = merged
        write(merged)
        redrawIcon()
        scheduleTimer()
        Notifier.evaluate(merged)
    }

    /// Fold a poll into the reading we already have. A full poll stamps the
    /// report's clock; a partial one keeps it, since the providers it did not
    /// ask are still only as fresh as that clock says.
    private func merging(_ fetched: [Provider], full: Bool, at now: Date) -> Report {
        let previous = report
        var providers = previous?.providers ?? []
        for provider in fetched {
            if let index = providers.firstIndex(where: { $0.name == provider.name }) {
                providers[index] = provider
            } else {
                providers.append(provider)
            }
        }
        for name in Fetcher.providerNames
        where !providers.contains(where: { $0.name == name }) {
            providers.append(Provider(name: name))
        }
        // A task group hands results back in completion order, which would let
        // the card's blocks shuffle between polls. Keep them in display order.
        let order = Dictionary(
            uniqueKeysWithValues: Fetcher.providerNames.enumerated().map { ($1, $0) }
        )
        providers.sort { (order[$0.name] ?? .max) < (order[$1.name] ?? .max) }

        var merged = Report(providers: providers, date: now).carryingOver(from: previous, now: now)
        if !full, let previous {
            merged.updatedAt = previous.updatedAt
            merged.updatedLabel = previous.updatedLabel
        }
        return merged
    }

    func refreshIfStale(olderThan seconds: TimeInterval) {
        let age = Date().timeIntervalSince1970 - Double(report?.updatedAt ?? 0)
        guard age > seconds else { return }
        Task { await refresh() }
    }

    @discardableResult
    func saveOpenRouterKey(_ key: String) async -> Bool {
        let saved = OpenRouterKeychain.save(key)
        hasSavedOpenRouterKey = OpenRouterKeychain.read() != nil
        if saved { await refresh() }
        return saved
    }

    @discardableResult
    func removeOpenRouterKey() async -> Bool {
        let removed = OpenRouterKeychain.remove()
        hasSavedOpenRouterKey = OpenRouterKeychain.read() != nil
        if removed { await refresh() }
        return removed
    }

    // ----------------------------------------------------------------- //

    /// Each provider's own cadence: a minute while it is unreachable, the
    /// user's interval otherwise.
    private func cadence(for name: String, configured: TimeInterval) -> TimeInterval {
        let provider = report?.providers.first { $0.name == name }
        return provider?.unreachable == true
            ? min(configured, Self.offlineRetryInterval)
            : configured
    }

    private func dueNames(at now: Date) -> [String] {
        let configured = max(60, Preferences.shared.refreshMinutes * 60)
        return Fetcher.providerNames.filter { name in
            let last = lastAttempt[name] ?? .distantPast
            return now >= last.addingTimeInterval(cadence(for: name, configured: configured))
        }
    }

    private func nextDelay(now: Date = Date()) -> TimeInterval {
        let configured = max(60, Preferences.shared.refreshMinutes * 60)
        let soonest = Fetcher.providerNames.map { name -> TimeInterval in
            let last = lastAttempt[name] ?? .distantPast
            return last
                .addingTimeInterval(cadence(for: name, configured: configured))
                .timeIntervalSince(now)
        }.min() ?? configured
        return max(1, soonest)
    }

    /// One poll of whatever is due, then schedule the next. A one-shot rather
    /// than a repeating timer so each provider's own cadence can take effect.
    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let delay = nextDelay()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshDue() }
        }
        // Let the system coalesce the wake-up; a little either way is fine.
        timer.tolerance = delay * 0.2
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
                showsCost: preferences.showOpenRouterCosts,
                timing: timing
            )
        }
        statusTooltip = lines.isEmpty
            ? "Tokens on Track — no reading yet · retrying \(retryCadenceLabel)"
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

    private func openRouterBudgetChanged(_ budget: Double?) {
        guard let current = report else { return }
        let updated = current.rebudgetingOpenRouter(monthlyBudget: budget)
        report = updated
        write(updated)
        redrawIcon()
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
