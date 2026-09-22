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
    @Published private(set) var hasSavedOpenCodeGoKey = OpenCodeGoKeychain.read() != nil
    @Published private(set) var hasSavedCursorKey = CursorKeychain.read() != nil
    @Published private(set) var statusImage: NSImage = StatusIcon.image(segments: [])
    /// Spells out both readings for whatever the item is drawn as, since the
    /// icon has room for one number and no room at all to label it.
    @Published private(set) var statusTooltip: String = "Tokens on Track — no reading yet"
    /// Last process-discovery pass for Claude profiles. Settings reads this
    /// instead of spawning `ps` on every row redraw.
    @Published private(set) var discoveredClaudePaths: [String] = []
    /// Last process-discovery pass for non-default CODEX_HOME profiles.
    @Published private(set) var discoveredCodexPaths: [String] = []

    nonisolated static var stateDirectory: URL {
        #if APP_STORE
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokens on Track", isDirectory: true)
        #else
        if let override = ProcessInfo.processInfo.environment["AI_USAGE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: ("~/.local/share/ai-usage" as NSString).expandingTildeInPath)
        #endif
    }

    nonisolated static var cacheURL: URL { stateDirectory.appendingPathComponent("usage.json") }

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
    /// The local token expiry each provider was last polled with. A rejected
    /// token stays rejected until the CLI mints a new one, which shows up here
    /// as a changed expiry — the cue to poll again. Only tracked for providers
    /// whose token was rejected, so a healthy poll reads no extra credentials.
    private var polledTokenExpiry: [String: Double?] = [:]
    private var refreshTimer: Timer?
    private var refreshAfterConnectionChange = false
    /// At most one process scan per launch, plus whenever Settings changes.
    private var remainingSessionClaudeScans = 1
    private var remainingSessionCodexScans = 1
    /// Claude profiles resolved on the last full refresh. Scheduling reads this
    /// so the minute wake never shells out to `security` on the main thread.
    private var claudeTargets: [ClaudeProfile.Entry] = []
    private var codexTargets: [CodexProfile.Entry] = []
    private var scheduleBoundaryTimer: Timer?
    private var workSchedule = WorkSchedule.disabled
    private var preferenceWatches: Set<AnyCancellable> = []
    private var clockObservers: [NSObjectProtocol] = []

    private init() {
        let preferences = Preferences.shared
        workSchedule = preferences.workSchedule
        loadCache()
        preferences.rememberModelLimits(report?.scopedModelLimits ?? [])
        report = report?.rebudgetingOpenRouter(
            monthlyBudget: preferences.openRouterMonthlyBudget
        ).rebudgetingCursor(
            monthlyBudget: preferences.cursorMonthlyBudget
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

        preferences.$cursorMonthlyBudget
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] budget in self?.cursorBudgetChanged(budget) }
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

    private func pollingContext(discoveredPaths: [String]) -> ClaudePollingContext {
        var context = Preferences.shared.claudePollingContext
        context.discoveredPaths = discoveredPaths
        return context
    }

    private func codexPollingContext(discoveredPaths: [String]) -> CodexPollingContext {
        var context = Preferences.shared.codexPollingContext
        context.discoveredPaths = discoveredPaths
        return context
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
        // provider or model-specific rows clears them from the menu bar too.
        return report.displaying(
            hiding: preferences.hiddenProviders,
            hidingModels: preferences.hiddenModelLimits
        ).busiestWindows(
            limit: limit,
            fairShare: preferences.menuBarFairShare,
            timing: timing
        )
    }

    /// Ask every provider now: the refresh button, wake, launch, and the
    /// normal interval.
    func refresh() async {
        await refresh(ids: nil, full: true)
    }

    /// A grant can change while the startup poll is still running. Queue one
    /// fresh poll so a just-connected provider need not wait for the timer.
    func connectionsChanged() {
        remainingSessionClaudeScans = 1
        remainingSessionCodexScans = 1
        if isRefreshing {
            refreshAfterConnectionChange = true
        } else {
            Task { await refresh() }
        }
    }

    /// The timer's job: ask only the providers whose own cadence has come due,
    /// so an unreachable one is retried every minute while the rest keep the
    /// user's interval and are not hammered alongside it.
    private func refreshDue() async {
        let now = Date()
        let due = dueNames(at: now)
        // Everyone due this round is the normal interval, so it stamps the
        // report's clock; a lone retry of a provider in trouble does not. Decide
        // this before holding a rejected provider back below — it was still
        // attended to (by a local token check), so a stale token must not freeze
        // "updated …" while the others keep refreshing.
        let all = Fetcher.pollTargetIDs(
            claudeTargets: claudeTargets,
            codexTargets: codexTargets
        )
        let full = due.count == all.count
        // A provider whose token was rejected will 401 again until the CLI
        // writes a fresh one. Rather than re-poll blind, watch the token's local
        // expiry and ask again only when it moves — the sign a new token landed.
        // Until then the minute wake is a local read, not an API call.
        let toPoll = due.filter { id in
            guard staleToken(id),
                  withinCarryWindow(id, now: now),
                  Fetcher.localTokenExpiry(id, codexTargets: codexTargets) == polledTokenExpiry[id] ?? nil
            else { return true }
            lastAttempt[id] = now  // attended: recheck in a minute, don't spin
            return false
        }
        guard !toPoll.isEmpty else {
            scheduleTimer()
            return
        }
        await refresh(ids: toPoll, full: full)
    }

    private func refresh(ids: [String]?, full: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshAfterConnectionChange {
                refreshAfterConnectionChange = false
                Task { await refresh() }
            }
        }

        let preferences = Preferences.shared
        let shouldScan = full && (
            remainingSessionClaudeScans > 0
                || !preferences.claudeConfiguredPaths.isEmpty
        )
        if shouldScan {
            let paths = await Task.detached(priority: .utility) {
                Fetcher.discoveredClaudeConfigDirs()
            }.value
            discoveredClaudePaths = paths
            if remainingSessionClaudeScans > 0 {
                remainingSessionClaudeScans -= 1
            }
        }

        let shouldScanCodex = full && (
            remainingSessionCodexScans > 0
                || !preferences.codexConfiguredPaths.isEmpty
        )
        if shouldScanCodex {
            let paths = await Task.detached(priority: .utility) {
                Fetcher.discoveredCodexHomes()
            }.value
            discoveredCodexPaths = paths
            if remainingSessionCodexScans > 0 {
                remainingSessionCodexScans -= 1
            }
        }

        let context = pollingContext(discoveredPaths: discoveredClaudePaths)
        if full || claudeTargets.isEmpty {
            let resolved = await Task.detached(priority: .userInitiated) {
                Fetcher.claudePollTargets(context: context)
            }.value
            claudeTargets = resolved.targets
            for path in resolved.loggedInPaths {
                preferences.rememberClaudeProfile(path)
            }
        }
        let codexContext = codexPollingContext(discoveredPaths: discoveredCodexPaths)
        if full || codexTargets.isEmpty {
            let resolved = await Task.detached(priority: .userInitiated) {
                Fetcher.codexPollTargets(context: codexContext)
            }.value
            codexTargets = resolved.targets
            for path in resolved.loggedInPaths {
                preferences.rememberCodexProfile(path)
            }
        }
        let allIDs = Fetcher.pollTargetIDs(
            claudeTargets: claudeTargets,
            codexTargets: codexTargets
        )
        // Resolved here, on the main actor, so the fetch tasks never read Preferences.
        var claudeLabels: [String: String] = [:]
        for entry in claudeTargets {
            claudeLabels[entry.id] = context.label(entry.normalizedPath)
        }
        var codexLabels: [String: String] = [:]
        for entry in codexTargets {
            codexLabels[entry.id] = codexContext.label(entry.normalizedPath)
        }
        let toFetch = ids ?? allIDs

        // Charge each poll from when it started, so a slow timeout cannot push
        // the next try out past its cadence.
        let started = Date()
        for id in toFetch { lastAttempt[id] = started }

        let fetched = await Fetcher.fetch(
            ids: toFetch,
            claudeTargets: claudeTargets,
            claudeLabels: claudeLabels,
            codexTargets: codexTargets,
            codexLabels: codexLabels,
            openRouterMonthlyBudget: preferences.openRouterMonthlyBudget,
            cursorMonthlyBudget: preferences.cursorMonthlyBudget
        )
        let merged = merging(fetched, full: full, at: Date(), allIDs: allIDs)
        Preferences.shared.rememberModelLimits(merged.scopedModelLimits)
        report = merged
        // Remember the expiry of any token just rejected, so the next wake can
        // tell a freshly-minted token apart from the same stale one.
        for provider in merged.providers where provider.staleToken {
            polledTokenExpiry[provider.id] = Fetcher.localTokenExpiry(
                provider.id,
                codexTargets: codexTargets
            )
        }
        write(merged)
        redrawIcon()
        scheduleTimer()
        Notifier.evaluate(merged)
    }

    /// Fold a poll into the reading we already have. A full poll stamps the
    /// report's clock; a partial one keeps it, since the providers it did not
    /// ask are still only as fresh as that clock says.
    private func merging(
        _ fetched: [Provider],
        full: Bool,
        at now: Date,
        allIDs: [String]
    ) -> Report {
        let previous = report
        var providers = previous?.providers ?? []
        for provider in fetched {
            if let index = providers.firstIndex(where: { $0.id == provider.id }) {
                providers[index] = provider
            } else {
                providers.append(provider)
            }
        }
        let targets = allIDs
        let order = Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($1, $0) })
        let active = Set(targets)
        providers.removeAll { $0.kind == "claude" && !active.contains($0.id) }
        providers.removeAll { $0.kind == "codex" && !active.contains($0.id) }
        for id in targets
        where !providers.contains(where: { $0.id == id }) {
            if let entry = codexTargets.first(where: { $0.id == id }) {
                providers.append(Provider(
                    id: entry.id,
                    kind: "codex",
                    name: Preferences.shared.codexLabel(for: entry.normalizedPath)
                        ?? CodexProfile.defaultLabel(
                            planType: nil,
                            customLabel: nil,
                            profilePath: entry.normalizedPath
                        ),
                    profilePath: entry.normalizedPath
                ))
            } else if id == Fetcher.openCodeGoID {
                providers.append(Fetcher.openCodeGoProvider())
            } else if id == Fetcher.openRouterID {
                providers.append(Provider(name: "OpenRouter"))
            } else if id == Fetcher.cursorID {
                providers.append(Provider(name: "Cursor"))
            }
        }
        providers.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }

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

    @discardableResult
    func saveOpenCodeGoKey(_ key: String) async -> Bool {
        let saved = OpenCodeGoKeychain.save(key)
        hasSavedOpenCodeGoKey = OpenCodeGoKeychain.read() != nil
        if saved { await refresh() }
        return saved
    }

    @discardableResult
    func removeOpenCodeGoKey() async -> Bool {
        let removed = OpenCodeGoKeychain.remove()
        hasSavedOpenCodeGoKey = OpenCodeGoKeychain.read() != nil
        if removed { await refresh() }
        return removed
    }

    @discardableResult
    func saveCursorKey(_ key: String) async -> Bool {
        let saved = CursorKeychain.save(key)
        hasSavedCursorKey = CursorKeychain.read() != nil
        if saved { await refresh() }
        return saved
    }

    @discardableResult
    func removeCursorKey() async -> Bool {
        let removed = CursorKeychain.remove()
        hasSavedCursorKey = CursorKeychain.read() != nil
        if removed { await refresh() }
        return removed
    }

    // ----------------------------------------------------------------- //

    /// Each provider's own cadence: a minute while it is unreachable or waiting
    /// on a fresh token, the user's interval otherwise. The stale-token minute
    /// is spent reading the token locally, not the API — see `refreshDue`.
    private func cadence(for id: String, configured: TimeInterval) -> TimeInterval {
        let provider = report?.providers.first { $0.id == id }
        let fast = provider?.unreachable == true || provider?.staleToken == true
        return fast ? min(configured, Self.offlineRetryInterval) : configured
    }

    private func staleToken(_ id: String) -> Bool {
        report?.providers.first { $0.id == id }?.staleToken ?? false
    }

    /// Whether a rejected provider's carried reading is still young enough to be
    /// worth holding back for. Once it ages past the carry limit the reading
    /// must be dropped, and only re-polling gets it there — the carry runs when
    /// a poll lands as not-ok, which a held-back provider never does. Nil
    /// timestamp means nothing is being carried, so there is nothing to expire.
    private func withinCarryWindow(_ id: String, now: Date) -> Bool {
        guard let measured = report?.providers.first(where: { $0.id == id })?.measuredAt else {
            return true
        }
        return now.timeIntervalSince1970 - Double(measured) < Report.carryLimit
    }

    private func dueNames(at now: Date) -> [String] {
        let configured = max(60, Preferences.shared.refreshMinutes * 60)
        return Fetcher.pollTargetIDs(
            claudeTargets: claudeTargets,
            codexTargets: codexTargets
        ).filter { id in
            let last = lastAttempt[id] ?? .distantPast
            return now >= last.addingTimeInterval(cadence(for: id, configured: configured))
        }
    }

    private func nextDelay(now: Date = Date()) -> TimeInterval {
        let configured = max(60, Preferences.shared.refreshMinutes * 60)
        let soonest = Fetcher.pollTargetIDs(
            claudeTargets: claudeTargets,
            codexTargets: codexTargets
        ).map { id -> TimeInterval in
            let last = lastAttempt[id] ?? .distantPast
            return last
                .addingTimeInterval(cadence(for: id, configured: configured))
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
                provider: $0.provider.kind,
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
                showsCost: $0.provider.kind == "cursor"
                    ? preferences.showCursorCosts
                    : $0.provider.kind == "openrouter" && preferences.showOpenRouterCosts,
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

    private func cursorBudgetChanged(_ budget: Double?) {
        guard let current = report else { return }
        let updated = current.rebudgetingCursor(monthlyBudget: budget)
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
