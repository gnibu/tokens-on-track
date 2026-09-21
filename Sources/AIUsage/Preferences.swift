import AppKit
import Foundation
import ServiceManagement

/// User-visible knobs, all backed by UserDefaults so they survive a restart.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    /// The three parts a menu bar segment is built from. At least one stays on
    /// — the settings pane locks the last one rather than allow an empty item.
    @Published var showLogoInMenuBar: Bool {
        didSet { defaults.set(showLogoInMenuBar, forKey: Keys.showLogo) }
    }

    @Published var showGaugeInMenuBar: Bool {
        didSet { defaults.set(showGaugeInMenuBar, forKey: Keys.showGauge) }
    }

    @Published var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: Keys.showPercent) }
    }

    /// The window's initial, drawn inside the gauge. Pointless without one.
    @Published var showWindowInMenuBar: Bool {
        didSet { defaults.set(showWindowInMenuBar, forKey: Keys.showWindow) }
    }

    /// How many windows the menu bar speaks for at once. One is the window in
    /// the most trouble; raising it brings the next-worst ones alongside.
    @Published var menuBarSlots: Int {
        didSet { defaults.set(menuBarSlots, forKey: Keys.menuBarSlots) }
    }

    /// Hand every provider a slot before any provider gets a second one, even
    /// when that means bumping a window that is genuinely busier.
    @Published var menuBarFairShare: Bool {
        didSet { defaults.set(menuBarFairShare, forKey: Keys.menuBarFairShare) }
    }

    /// What every percentage in the app quotes — the budget spent, or that
    /// spending measured against the clock. One knob for all three surfaces:
    /// the same number meaning two different things in the menu bar and in the
    /// card below it is worse than either reading on its own.
    @Published var percentMode: Pace.PercentMode {
        didSet { defaults.set(percentMode.rawValue, forKey: Keys.percentMode) }
    }

    /// Optional local schedule used to redistribute the target while the user
    /// is currently inside it. The provider windows themselves are unchanged.
    @Published var workingHoursEnabled: Bool {
        didSet { defaults.set(workingHoursEnabled, forKey: Keys.workingHoursEnabled) }
    }

    @Published private(set) var workingWeekdays: Set<WorkSchedule.Weekday> {
        didSet { defaults.set(workSchedule.weekdayMask, forKey: Keys.workingWeekdays) }
    }

    @Published var workingStartMinute: Int {
        didSet { defaults.set(workingStartMinute, forKey: Keys.workingStartMinute) }
    }

    @Published var workingEndMinute: Int {
        didSet { defaults.set(workingEndMinute, forKey: Keys.workingEndMinute) }
    }

    var workSchedule: WorkSchedule {
        WorkSchedule(
            enabled: workingHoursEnabled,
            weekdays: workingWeekdays,
            startMinute: workingStartMinute,
            endMinute: workingEndMinute
        )
    }

    /// The free-standing card on the desktop.
    @Published var showDesktopCard: Bool {
        didSet { defaults.set(showDesktopCard, forKey: Keys.showDesktopCard) }
    }

    /// False parks the card on the desktop, behind every window. True keeps it
    /// in front of everything.
    @Published var desktopCardFloats: Bool {
        didSet { defaults.set(desktopCardFloats, forKey: Keys.desktopCardFloats) }
    }

    /// Where the user last dragged the card to, as its *top* left corner — the
    /// card grows downwards when a provider starts reporting an error, and
    /// anchoring the bottom left would make it crawl up the screen instead.
    /// Nil until the card has been moved.
    var desktopCardAnchor: NSPoint? {
        get {
            guard let raw = defaults.string(forKey: Keys.desktopCardAnchor) else { return nil }
            return NSPointFromString(raw)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Keys.desktopCardAnchor)
                return
            }
            defaults.set(NSStringFromPoint(newValue), forKey: Keys.desktopCardAnchor)
        }
    }

    /// Notify once per window when consumption crosses this mark.
    @Published var usageThreshold: Double {
        didSet { defaults.set(usageThreshold, forKey: Keys.usageThreshold) }
    }

    @Published var usageAlertsEnabled: Bool {
        didSet { defaults.set(usageAlertsEnabled, forKey: Keys.usageAlerts) }
    }

    /// Notify once per window when burn rate exceeds this multiple of even pace.
    @Published var paceThreshold: Double {
        didSet { defaults.set(paceThreshold, forKey: Keys.paceThreshold) }
    }

    @Published var paceAlertsEnabled: Bool {
        didSet { defaults.set(paceAlertsEnabled, forKey: Keys.paceAlerts) }
    }

    @Published var refreshMinutes: Double {
        didSet { defaults.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }

    /// Local display budget for OpenRouter. The API key itself never belongs
    /// in UserDefaults; it is either discovered or stored in Keychain.
    @Published var openRouterMonthlyBudget: Double? {
        didSet {
            if let value = openRouterMonthlyBudget {
                defaults.set(value, forKey: Keys.openRouterMonthlyBudget)
            } else {
                defaults.removeObject(forKey: Keys.openRouterMonthlyBudget)
            }
        }
    }

    /// Optional exact spend lines below OpenRouter's percentage rows. Off by
    /// default to keep the ordinary provider layout equally compact.
    @Published var showOpenRouterCosts: Bool {
        didSet { defaults.set(showOpenRouterCosts, forKey: Keys.showOpenRouterCosts) }
    }

    /// Local display budget for Cursor team Admin keys that do not already
    /// carry a spend limit. Personal dashboard readings ignore this.
    @Published var cursorMonthlyBudget: Double? {
        didSet {
            if let value = cursorMonthlyBudget {
                defaults.set(value, forKey: Keys.cursorMonthlyBudget)
            } else {
                defaults.removeObject(forKey: Keys.cursorMonthlyBudget)
            }
        }
    }

    /// Optional exact spend lines below Cursor's percentage rows.
    @Published var showCursorCosts: Bool {
        didSet { defaults.set(showCursorCosts, forKey: Keys.showCursorCosts) }
    }

    /// Providers the user has chosen not to see, by stable id. A never-set-up
    /// provider is hidden automatically; this is for hiding one you *do* have.
    @Published var hiddenProviders: Set<String> {
        didSet { defaults.set(Array(hiddenProviders), forKey: Keys.hiddenProviders) }
    }

    @Published private(set) var claudeConfiguredPaths: [String] {
        didSet { defaults.set(claudeConfiguredPaths, forKey: Keys.claudeConfiguredPaths) }
    }

    @Published private(set) var claudeRememberedPaths: Set<String> {
        didSet { defaults.set(Array(claudeRememberedPaths), forKey: Keys.claudeRememberedPaths) }
    }

    @Published private(set) var claudeIgnoredPaths: Set<String> {
        didSet { defaults.set(Array(claudeIgnoredPaths), forKey: Keys.claudeIgnoredPaths) }
    }

    @Published var claudeCustomLabels: [String: String] {
        didSet {
            if let encoded = try? JSONEncoder().encode(claudeCustomLabels) {
                defaults.set(encoded, forKey: Keys.claudeCustomLabels)
            }
        }
    }

    @Published private(set) var codexConfiguredPaths: [String] {
        didSet { defaults.set(codexConfiguredPaths, forKey: Keys.codexConfiguredPaths) }
    }

    @Published private(set) var codexRememberedPaths: Set<String> {
        didSet { defaults.set(Array(codexRememberedPaths), forKey: Keys.codexRememberedPaths) }
    }

    @Published private(set) var codexIgnoredPaths: Set<String> {
        didSet { defaults.set(Array(codexIgnoredPaths), forKey: Keys.codexIgnoredPaths) }
    }

    @Published var codexCustomLabels: [String: String] {
        didSet {
            if let encoded = try? JSONEncoder().encode(codexCustomLabels) {
                defaults.set(encoded, forKey: Keys.codexCustomLabels)
            }
        }
    }

    /// Provider/model pairs whose structured quota rows the user has hidden.
    /// An absent key means shown, so every newly discovered model appears by
    /// default without a migration or a hard-coded model list.
    @Published var hiddenModelLimits: Set<String> {
        didSet { defaults.set(Array(hiddenModelLimits), forKey: Keys.hiddenModelLimits) }
    }

    /// Every provider/model pair ever observed. This is intentionally
    /// append-only: APIs may omit an inactive bucket from one response, but its
    /// visibility control must remain available in Settings.
    @Published private(set) var knownModelLimits: [ScopedModelLimit] {
        didSet {
            if let encoded = try? JSONEncoder().encode(knownModelLimits) {
                defaults.set(encoded, forKey: Keys.knownModelLimits)
            }
        }
    }

    func setProvider(_ id: String, hidden: Bool) {
        if hidden { hiddenProviders.insert(id) } else { hiddenProviders.remove(id) }
    }

    func claudeLabel(for path: String) -> String? {
        claudeCustomLabels[ClaudeProfile.normalizedPath(path)]
    }

    func setClaudeLabel(_ label: String?, for path: String) {
        let key = ClaudeProfile.normalizedPath(path)
        var next = claudeCustomLabels
        if let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            next[key] = trimmed
        } else {
            next.removeValue(forKey: key)
        }
        claudeCustomLabels = next
    }

    func addClaudeProfile(path: String) {
        let normalized = ClaudeProfile.normalizedPath(path)
        guard !claudeConfiguredPaths.contains(normalized) else { return }
        claudeConfiguredPaths.append(normalized)
        var ignored = claudeIgnoredPaths
        ignored.remove(normalized)
        claudeIgnoredPaths = ignored
    }

    func removeClaudeProfile(path: String) {
        let normalized = ClaudeProfile.normalizedPath(path)
        claudeConfiguredPaths.removeAll { $0 == normalized }
        var remembered = claudeRememberedPaths
        remembered.remove(normalized)
        claudeRememberedPaths = remembered
        var ignored = claudeIgnoredPaths
        ignored.insert(normalized)
        claudeIgnoredPaths = ignored
        ClaudeAccountAccess.shared.removeBookmark(for: normalized)
        var labels = claudeCustomLabels
        labels.removeValue(forKey: normalized)
        claudeCustomLabels = labels
    }

    func rememberClaudeProfile(_ path: String) {
        let normalized = ClaudeProfile.normalizedPath(path)
        guard !claudeRememberedPaths.contains(normalized) else { return }
        var next = claudeRememberedPaths
        next.insert(normalized)
        claudeRememberedPaths = next
    }

    var claudePollingContext: ClaudePollingContext {
        ClaudePollingContext(
            configuredPaths: claudeConfiguredPaths,
            rememberedPaths: claudeRememberedPaths,
            ignoredPaths: claudeIgnoredPaths,
            label: { [self] in claudeLabel(for: $0) }
        )
    }

    func claudeSettingsEntries(discoveredPaths: [String] = []) -> [ClaudeProfile.Entry] {
        ClaudeProfile.catalog(
            configuredPaths: claudeConfiguredPaths,
            rememberedPaths: claudeRememberedPaths,
            discoveredPaths: discoveredPaths,
            ignoredPaths: claudeIgnoredPaths
        )
    }

    func codexLabel(for path: String) -> String? {
        codexCustomLabels[CodexProfile.normalizedPath(path)]
    }

    func setCodexLabel(_ label: String?, for path: String) {
        let key = CodexProfile.normalizedPath(path)
        var next = codexCustomLabels
        if let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            next[key] = trimmed
        } else {
            next.removeValue(forKey: key)
        }
        codexCustomLabels = next
    }

    func addCodexProfile(path: String) {
        let normalized = CodexProfile.normalizedPath(path)
        if !codexConfiguredPaths.contains(normalized) {
            codexConfiguredPaths.append(normalized)
        }
        var ignored = codexIgnoredPaths
        ignored.remove(normalized)
        codexIgnoredPaths = ignored
    }

    func removeCodexProfile(path: String) {
        let normalized = CodexProfile.normalizedPath(path)
        codexConfiguredPaths.removeAll { $0 == normalized }
        var remembered = codexRememberedPaths
        remembered.remove(normalized)
        codexRememberedPaths = remembered
        var ignored = codexIgnoredPaths
        ignored.insert(normalized)
        codexIgnoredPaths = ignored
        CodexAccountAccess.shared.removeBookmark(for: normalized)
        var labels = codexCustomLabels
        labels.removeValue(forKey: normalized)
        codexCustomLabels = labels
    }

    func rememberCodexProfile(_ path: String) {
        let normalized = CodexProfile.normalizedPath(path)
        guard !codexRememberedPaths.contains(normalized) else { return }
        var next = codexRememberedPaths
        next.insert(normalized)
        codexRememberedPaths = next
    }

    var codexPollingContext: CodexPollingContext {
        CodexPollingContext(
            configuredPaths: codexConfiguredPaths,
            rememberedPaths: codexRememberedPaths,
            ignoredPaths: codexIgnoredPaths,
            label: { [self] in codexLabel(for: $0) }
        )
    }

    func codexSettingsEntries(discoveredPaths: [String] = []) -> [CodexProfile.Entry] {
        CodexProfile.catalog(
            configuredPaths: codexConfiguredPaths,
            rememberedPaths: codexRememberedPaths,
            discoveredPaths: discoveredPaths,
            ignoredPaths: codexIgnoredPaths
        )
    }

    func setModelLimit(provider: String, model: String, hidden: Bool) {
        let key = ScopedModelLimit.key(provider: provider, model: model)
        if hidden { hiddenModelLimits.insert(key) } else { hiddenModelLimits.remove(key) }
    }

    func rememberModelLimits(_ discovered: [ScopedModelLimit]) {
        let merged = ModelLimitHistory.merging(
            existing: knownModelLimits,
            discovered: discovered
        )
        if merged != knownModelLimits { knownModelLimits = merged }
    }

    private enum Keys {
        static let showLogo = "showLogoInMenuBar"
        static let showGauge = "showGaugeInMenuBar"
        static let showPercent = "showPercentInMenuBar"
        static let showWindow = "showWindowInMenuBar"
        static let menuBarSlots = "menuBarSlots"
        static let menuBarFairShare = "menuBarFairShare"
        static let percentMode = "percentMode"
        static let workingHoursEnabled = "workingHoursEnabled"
        static let workingWeekdays = "workingWeekdays"
        static let workingStartMinute = "workingStartMinute"
        static let workingEndMinute = "workingEndMinute"
        static let showDesktopCard = "showDesktopCard"
        static let desktopCardFloats = "desktopCardFloats"
        static let desktopCardAnchor = "desktopCardAnchor"
        static let usageThreshold = "usageThreshold"
        static let usageAlerts = "usageAlertsEnabled"
        static let paceThreshold = "paceThreshold"
        static let paceAlerts = "paceAlertsEnabled"
        static let refreshMinutes = "refreshMinutes"
        static let openRouterMonthlyBudget = "openRouterMonthlyBudget"
        static let showOpenRouterCosts = "showOpenRouterCosts"
        static let cursorMonthlyBudget = "cursorMonthlyBudget"
        static let showCursorCosts = "showCursorCosts"
        static let hiddenProviders = "hiddenProviders"
        static let claudeConfiguredPaths = "claudeConfiguredPaths"
        static let claudeRememberedPaths = "claudeRememberedPaths"
        static let claudeIgnoredPaths = "claudeIgnoredPaths"
        static let claudeCustomLabels = "claudeCustomLabels"
        static let migratedClaudeProviderIDs = "migratedClaudeProviderIDs"
        static let codexConfiguredPaths = "codexConfiguredPaths"
        static let codexRememberedPaths = "codexRememberedPaths"
        static let codexIgnoredPaths = "codexIgnoredPaths"
        static let codexCustomLabels = "codexCustomLabels"
        static let hiddenModelLimits = "hiddenModelLimits"
        static let knownModelLimits = "knownModelLimits"
        static let migratedCodexModelLimits = "migratedCodexModelLimits"
        static let migratedKnownModelLimits = "migratedKnownModelLimits"
        /// Legacy Spark row switches. Read once into the generic per-model
        /// preference, then removed.
        static let hideSparkSession = "hideSparkSession"
        static let hideSparkWeek = "hideSparkWeek"
        /// The single spark switch this replaced. Read once to migrate, then
        /// cleared so turning one row back on is not undone at next launch.
        static let legacyHideCodexSpark = "hideCodexSpark"
    }

    private init() {
        defaults.register(defaults: [
            Keys.showLogo: true,
            Keys.showGauge: true,
            Keys.showPercent: true,
            Keys.showWindow: true,
            Keys.menuBarSlots: 1,
            Keys.menuBarFairShare: false,
            Keys.percentMode: Pace.PercentMode.budget.rawValue,
            Keys.workingHoursEnabled: false,
            Keys.workingWeekdays: WorkSchedule(
                enabled: false,
                weekdays: WorkSchedule.defaultWeekdays,
                startMinute: 9 * 60,
                endMinute: 18 * 60
            ).weekdayMask,
            Keys.workingStartMinute: 9 * 60,
            Keys.workingEndMinute: 18 * 60,
            Keys.showDesktopCard: true,
            Keys.desktopCardFloats: false,
            Keys.usageThreshold: 90.0,
            Keys.usageAlerts: true,
            Keys.paceThreshold: 1.5,
            Keys.paceAlerts: true,
            Keys.refreshMinutes: 10.0,
            Keys.showOpenRouterCosts: false,
            Keys.showCursorCosts: false,
        ])
        showLogoInMenuBar = defaults.bool(forKey: Keys.showLogo)
        showGaugeInMenuBar = defaults.bool(forKey: Keys.showGauge)
        showPercentInMenuBar = defaults.bool(forKey: Keys.showPercent)
        showWindowInMenuBar = defaults.bool(forKey: Keys.showWindow)
        menuBarSlots = max(1, defaults.integer(forKey: Keys.menuBarSlots))
        menuBarFairShare = defaults.bool(forKey: Keys.menuBarFairShare)
        percentMode = defaults.string(forKey: Keys.percentMode)
            .flatMap(Pace.PercentMode.init(rawValue:)) ?? .budget
        workingHoursEnabled = defaults.bool(forKey: Keys.workingHoursEnabled)
        workingWeekdays = WorkSchedule(
            enabled: false,
            weekdayMask: defaults.integer(forKey: Keys.workingWeekdays),
            startMinute: defaults.integer(forKey: Keys.workingStartMinute),
            endMinute: defaults.integer(forKey: Keys.workingEndMinute)
        ).weekdays
        workingStartMinute = min(1439, max(0, defaults.integer(forKey: Keys.workingStartMinute)))
        workingEndMinute = min(1439, max(0, defaults.integer(forKey: Keys.workingEndMinute)))
        showDesktopCard = defaults.bool(forKey: Keys.showDesktopCard)
        desktopCardFloats = defaults.bool(forKey: Keys.desktopCardFloats)
        usageThreshold = defaults.double(forKey: Keys.usageThreshold)
        usageAlertsEnabled = defaults.bool(forKey: Keys.usageAlerts)
        paceThreshold = defaults.double(forKey: Keys.paceThreshold)
        paceAlertsEnabled = defaults.bool(forKey: Keys.paceAlerts)
        refreshMinutes = defaults.double(forKey: Keys.refreshMinutes)
        if defaults.object(forKey: Keys.openRouterMonthlyBudget) != nil {
            let value = defaults.double(forKey: Keys.openRouterMonthlyBudget)
            openRouterMonthlyBudget = value.isFinite && value > 0 ? value : nil
        } else {
            openRouterMonthlyBudget = nil
        }
        showOpenRouterCosts = defaults.bool(forKey: Keys.showOpenRouterCosts)
        if defaults.object(forKey: Keys.cursorMonthlyBudget) != nil {
            let value = defaults.double(forKey: Keys.cursorMonthlyBudget)
            cursorMonthlyBudget = value.isFinite && value > 0 ? value : nil
        } else {
            cursorMonthlyBudget = nil
        }
        showCursorCosts = defaults.bool(forKey: Keys.showCursorCosts)
        hiddenProviders = Set(defaults.stringArray(forKey: Keys.hiddenProviders) ?? [])
        claudeConfiguredPaths = defaults.stringArray(forKey: Keys.claudeConfiguredPaths) ?? []
        claudeRememberedPaths = Set(defaults.stringArray(forKey: Keys.claudeRememberedPaths) ?? [])
        claudeIgnoredPaths = Set(defaults.stringArray(forKey: Keys.claudeIgnoredPaths) ?? [])
        claudeCustomLabels = defaults.data(forKey: Keys.claudeCustomLabels)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        codexConfiguredPaths = defaults.stringArray(forKey: Keys.codexConfiguredPaths) ?? []
        codexRememberedPaths = Set(defaults.stringArray(forKey: Keys.codexRememberedPaths) ?? [])
        codexIgnoredPaths = Set(defaults.stringArray(forKey: Keys.codexIgnoredPaths) ?? [])
        codexCustomLabels = defaults.data(forKey: Keys.codexCustomLabels)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        var hiddenModels = Set(defaults.stringArray(forKey: Keys.hiddenModelLimits) ?? [])
        var knownModels = defaults.data(forKey: Keys.knownModelLimits)
            .flatMap { try? JSONDecoder().decode([ScopedModelLimit].self, from: $0) } ?? []
        knownModels = ModelLimitHistory.merging(existing: knownModels, discovered: [])

        if !defaults.bool(forKey: Keys.migratedCodexModelLimits) {
            let domainName = Bundle.main.bundleIdentifier ?? "io.github.ai-usage"
            let persisted = defaults.persistentDomain(forName: domainName) ?? [:]
            let legacySession = persisted[Keys.hideSparkSession] as? Bool
            let legacyWeek = persisted[Keys.hideSparkWeek] as? Bool
            let legacyAll = persisted[Keys.legacyHideCodexSpark] as? Bool
            let hadPreviousReading = Self.cacheFileExists()
                || legacySession != nil || legacyWeek != nil || legacyAll != nil
            hiddenModels = ModelLimitMigration.codexSparkVisibility(
                existing: hiddenModels,
                hadPreviousReading: hadPreviousReading,
                legacySessionHidden: legacySession,
                legacyWeekHidden: legacyWeek,
                legacyAllHidden: legacyAll
            )
            defaults.set(Array(hiddenModels), forKey: Keys.hiddenModelLimits)
            defaults.set(true, forKey: Keys.migratedCodexModelLimits)
            defaults.removeObject(forKey: Keys.hideSparkSession)
            defaults.removeObject(forKey: Keys.hideSparkWeek)
            defaults.removeObject(forKey: Keys.legacyHideCodexSpark)
        }
        hiddenModelLimits = hiddenModels

        if !defaults.bool(forKey: Keys.migratedKnownModelLimits) {
            let sparkKey = ScopedModelLimit.key(
                provider: "Codex",
                model: ModelLimitMigration.codexSpark
            )
            let existingInstall = Self.cacheFileExists() || hiddenModels.contains(sparkKey)
            knownModels = ModelLimitHistory.seedingSpark(
                existing: knownModels,
                hadPreviousReading: existingInstall
            )
            defaults.set(true, forKey: Keys.migratedKnownModelLimits)
        }
        knownModelLimits = knownModels
        if let encoded = try? JSONEncoder().encode(knownModels) {
            defaults.set(encoded, forKey: Keys.knownModelLimits)
        }

        if !defaults.bool(forKey: Keys.migratedClaudeProviderIDs) {
            if hiddenProviders.remove("Claude") != nil {
                hiddenProviders.insert(ClaudeProfile.defaultKeychainService)
            }
            let defaultID = ClaudeProfile.defaultKeychainService
            hiddenModelLimits = Set(hiddenModelLimits.map { key in
                let parts = key.split(separator: "\u{1}", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[0] == "claude" else { return key }
                return ScopedModelLimit.key(provider: defaultID, model: parts[1])
            })
            knownModelLimits = knownModelLimits.map { limit in
                guard limit.provider.caseInsensitiveCompare("Claude") == .orderedSame else { return limit }
                return ScopedModelLimit(provider: defaultID, model: limit.model)
            }
            defaults.set(true, forKey: Keys.migratedClaudeProviderIDs)
        }
    }

    private static func cacheFileExists() -> Bool {
        FileManager.default.fileExists(atPath: UsageStore.cacheURL.path)
    }

    /// The last selected weekday cannot be removed: an enabled empty schedule
    /// would look configured while silently behaving like wall clock.
    func setWorkingDay(_ day: WorkSchedule.Weekday, enabled: Bool) {
        var next = workingWeekdays
        if enabled {
            next.insert(day)
        } else {
            guard next.count > 1 else { return }
            next.remove(day)
        }
        workingWeekdays = next
    }

    // ----------------------------------------------------------------- //
    // Login item — not a default, it is read back from the system.
    // ----------------------------------------------------------------- //

    var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state; registration can be refused (for instance
    /// when the app is run from a build directory rather than /Applications).
    @discardableResult
    func setOpensAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ai-usage: login item \(enabled ? "register" : "unregister") failed: \(error)")
        }
        return opensAtLogin
    }
}
