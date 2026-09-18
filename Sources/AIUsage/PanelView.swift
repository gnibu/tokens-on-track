import AppKit
import SwiftUI

/// The dropdown behind the menu bar item, in two tabs. Settings used to push
/// the reading off the bottom of the screen when opened; as a tab it costs one
/// click and keeps the panel a constant height instead.
struct PanelView: View {
    enum Tab: Hashable {
        case usage
        case settings
    }

    @EnvironmentObject private var store: UsageStore
    @State private var tab: Tab = .usage

    var body: some View {
        VStack(spacing: 0) {
            header

            switch tab {
            case .usage:
                VStack(alignment: .leading, spacing: 16) {
                    MenuUsageView()
                    usageFooter
                }
                .padding(EdgeInsets(top: 4, leading: 18, bottom: 18, trailing: 18))

            case .settings:
                SettingsTab()
            }
        }
        .frame(width: 430)
        // The desktop card's pane exactly, rim included: the panel this hangs
        // in is ours now, so its edge is the only one on screen.
        // The shadow is the panel's own, as with the card: a SwiftUI one would
        // be clipped by the window it is drawn inside.
        .glassPane(radius: Glass.panelRadius, dim: 0.75, tone: 0.7, shadow: false)
        .environment(\.colorScheme, .dark)
        .onAppear { store.refreshIfStale(olderThan: 300) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            GlassSegmented(
                options: [.init(.usage, "Usage"), .init(.settings, "Settings")],
                selection: $tab
            )

            if tab == .usage {
                GlassButton(
                    label: "",
                    systemImage: "arrow.clockwise",
                    enabled: !store.isRefreshing,
                    spinning: store.isRefreshing
                ) {
                    Task { await store.refresh() }
                }
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var usageFooter: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if store.isOffline {
                    GlassSpinner(size: 11)
                }
                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.ink(0.4))
            }
            Spacer(minLength: 8)
            GlassLink(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var footerText: String {
        let every = store.retryCadenceLabel
        guard let report = store.report else { return "No reading yet · retrying \(every)" }
        if store.isRefreshing { return "Refreshing… · \(every)" }
        if report.hasNoReading { return "No reading yet · retrying \(every)" }
        let stale = report.isStale ? " (stale)" : ""
        return "Updated \(report.updatedLabel)\(stale) · \(every)"
    }
}

// --------------------------------------------------------------------- //

/// Settings as inset groups rather than one flat run of checkboxes: switches
/// for the on/off knobs, segmented controls for the either/or ones, and
/// sliders for the thresholds that used to be ±5 arithmetic on a stepper.
private struct SettingsTab: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared
    @State private var opensAtLogin = Preferences.shared.opensAtLogin
    @State private var editingOpenRouterKey = false
    @State private var openRouterKey = ""
    @State private var openRouterKeyError: String?
    @State private var openRouterBudgetError: String?
    @State private var openRouterBudgetText = Preferences.shared.openRouterMonthlyBudget
        .map(SettingsTab.editableBudget)
        ?? ""
    @State private var editingCursorKey = false
    @State private var cursorKey = ""
    @State private var cursorKeyError: String?
    @State private var cursorBudgetError: String?
    @State private var cursorBudgetText = Preferences.shared.cursorMonthlyBudget
        .map(SettingsTab.editableBudget)
        ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Capped and scrolled rather than allowed to grow: the whole point
            // of the tab is that the dropdown stays a predictable height.
            CappedScroll(maxHeight: Self.cap) {
                VStack(alignment: .leading, spacing: 14) {
                    menuBarGroup
                    displayGroup
                    openRouterGroup
                    cursorGroup
                    providersGroup
                    workingHoursGroup
                    alertsGroup
                    refreshGroup
                }
                .padding(EdgeInsets(top: 4, leading: 18, bottom: 14, trailing: 18))
            }

            // Quit stays put instead of hiding at the bottom of the scroll.
            footer
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 18, trailing: 18))
        }
    }

    /// How tall the settings list is allowed to get before it starts scrolling.
    /// Measured against the screen rather than fixed, so a large display shows
    /// nearly the whole list while a laptop still leaves room for the header,
    /// the footer and the menu bar the panel hangs from.
    private static var cap: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - 180
        return min(640, max(320, available))
    }

    // ----------------------------------------------------------------- //

    private var menuBarGroup: some View {
        Group {
            groupTitle("Menu bar")

            DividedRows {
                SettingRow(title: "Provider logo") {
                    partSwitch($preferences.showLogoInMenuBar)
                }
                SettingRow(title: "Usage gauge") {
                    partSwitch($preferences.showGaugeInMenuBar)
                }
                SettingRow(title: "Percentage") {
                    partSwitch($preferences.showPercentInMenuBar)
                }
                SettingRow(
                    title: "Window initial in the gauge",
                    subtitle: "rides inside the ring, so it widens nothing",
                    enabled: preferences.showGaugeInMenuBar
                ) {
                    GlassSwitch(isOn: $preferences.showWindowInMenuBar, enabled: preferences.showGaugeInMenuBar)
                        .onChange(of: preferences.showWindowInMenuBar) { _, _ in
                            store.iconPreferenceChanged()
                        }
                }
                SettingRow(title: "Windows shown") {
                    GlassSegmented(
                        options: (1...4).map { .init($0, "\($0)") },
                        selection: $preferences.menuBarSlots,
                        fontSize: 11,
                        verticalPadding: 4
                    )
                    .frame(width: 132)
                    .onChange(of: preferences.menuBarSlots) { _, _ in
                        store.iconPreferenceChanged()
                    }
                }
                SettingRow(
                    title: "Keep every provider on screen",
                    subtitle: "even when one provider owns the busiest windows",
                    enabled: preferences.menuBarSlots > 1
                ) {
                    GlassSwitch(isOn: $preferences.menuBarFairShare, enabled: preferences.menuBarSlots > 1)
                        .onChange(of: preferences.menuBarFairShare) { _, _ in
                            store.iconPreferenceChanged()
                        }
                }
            }
        }
    }

    private var displayGroup: some View {
        Group {
            groupTitle("Display")

            DividedRows {
                SettingRow(
                    title: "Percentages show"
                ) {
                    GlassSegmented(
                        options: [.init(Pace.PercentMode.budget, "Used"), .init(.target, "Vs target")],
                        selection: $preferences.percentMode,
                        fontSize: 11,
                        verticalPadding: 4
                    )
                    .frame(width: 160)
                    .onChange(of: preferences.percentMode) { _, _ in
                        store.iconPreferenceChanged()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target is where usage should be now to spend the quota evenly before reset.")
                        .foregroundStyle(Glass.ink(0.62))
                    Text("Gauges always show quota used. Working hours affect the target when active.")
                        .foregroundStyle(Glass.ink(0.42))
                }
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                SettingRow(title: "Card on desktop") {
                    GlassSwitch(isOn: $preferences.showDesktopCard)
                }
                SettingRow(title: "Card layer", enabled: preferences.showDesktopCard) {
                    GlassSegmented(
                        options: [.init(false, "Desktop"), .init(true, "Floating")],
                        selection: $preferences.desktopCardFloats,
                        fontSize: 11,
                        verticalPadding: 4,
                        enabled: preferences.showDesktopCard
                    )
                    .frame(width: 160)
                }
                SettingRow(title: "Open at login") {
                    GlassSwitch(isOn: $opensAtLogin)
                        .onChange(of: opensAtLogin) { _, wanted in
                            let actual = preferences.setOpensAtLogin(wanted)
                            if actual != wanted { opensAtLogin = actual }
                        }
                }
            }
        }
    }

    private var openRouterGroup: some View {
        Group {
            groupTitle("OpenRouter")

            DividedRows {
                SettingRow(
                    title: "Connection",
                    subtitle: openRouterConnectionSubtitle
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(openRouterConnectionColor)
                            .frame(width: 6, height: 6)
                        Text(openRouterConnectionLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Glass.ink(0.72))
                    }
                }

                SettingRow(
                    title: "API key",
                    subtitle: openRouterKeyError ?? (store.hasSavedOpenRouterKey
                        ? "saved in this Mac's Keychain"
                        : "add a key for reliable tracking")
                ) {
                    if editingOpenRouterKey {
                        VStack(alignment: .trailing, spacing: 6) {
                            SecureField("sk-or-…", text: $openRouterKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11).monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(width: 150)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.black.opacity(0.25))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.14))
                                )

                            HStack(spacing: 10) {
                                GlassLink(title: "Cancel") {
                                    editingOpenRouterKey = false
                                    openRouterKey = ""
                                    openRouterKeyError = nil
                                }
                                GlassButton(label: "Save", enabled: !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                    saveOpenRouterKey()
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            if store.hasSavedOpenRouterKey {
                                GlassLink(title: "Remove") {
                                    Task {
                                        if await store.removeOpenRouterKey() {
                                            openRouterKeyError = nil
                                        } else {
                                            openRouterKeyError = "Could not remove the key from Keychain"
                                        }
                                    }
                                }
                            }
                            GlassButton(label: store.hasSavedOpenRouterKey ? "Replace…" : "Add key…") {
                                editingOpenRouterKey = true
                                openRouterKeyError = nil
                            }
                        }
                    }
                }

                SettingRow(
                    title: "Monthly budget",
                    subtitle: openRouterBudgetError ?? "USD · daily allowance is derived automatically"
                ) {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 12))
                            .foregroundStyle(Glass.ink(0.55))
                        TextField("20", text: $openRouterBudgetText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .onChange(of: openRouterBudgetText) { _, value in
                                setOpenRouterBudget(value)
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14))
                    )
                }

                SettingRow(
                    title: "Dollar values",
                    subtitle: "show spend and allowance below each usage row"
                ) {
                    GlassSwitch(isOn: $preferences.showOpenRouterCosts)
                        .onChange(of: preferences.showOpenRouterCosts) { _, _ in
                            store.iconPreferenceChanged()
                        }
                }
            }
        }
    }

    private var openRouterProvider: Provider? {
        store.report?.providers.first(where: { $0.name == "OpenRouter" })
    }

    /// A remembered credential source outlives the key it names — the carry
    /// keeps it so the card can point back to Conductor. So "we have a source"
    /// is not "we are connected": a live "not connected" means the credential is
    /// gone now, whatever produced the last reading.
    private var isOpenRouterConnected: Bool {
        guard let provider = openRouterProvider, provider.credentialSource != nil else {
            return false
        }
        return provider.error != OpenRouterBudget.notConnectedMessage
    }

    private var openRouterConnectionLabel: String {
        guard isOpenRouterConnected else { return "Not connected" }
        if openRouterProvider?.error?.contains("rejected") == true { return "Rejected" }
        return "Connected"
    }

    private var openRouterConnectionSubtitle: String {
        guard let provider = openRouterProvider else { return "Add an OpenRouter API key below" }
        var parts: [String] = []
        if let source = provider.credentialSource { parts.append(source.rawValue) }
        if let error = provider.error, error != OpenRouterBudget.missingBudgetMessage {
            parts.append(error)
        }
        return parts.isEmpty ? "Add an OpenRouter API key below" : parts.joined(separator: " · ")
    }

    private var openRouterConnectionColor: Color {
        guard isOpenRouterConnected else { return Color.white.opacity(0.3) }
        return openRouterProvider?.error?.contains("rejected") == true ? Pace.warn : Pace.good
    }

    private func saveOpenRouterKey() {
        let key = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await store.saveOpenRouterKey(key) {
                editingOpenRouterKey = false
                openRouterKey = ""
                openRouterKeyError = nil
            } else {
                openRouterKeyError = "Could not save the key in Keychain"
            }
        }
    }

    /// The field is an input, not a readout: seed it with the value exactly as
    /// stored so the next keystroke cannot persist a display-rounded budget.
    private static func editableBudget(_ value: Double) -> String {
        var text = String(value)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text
    }

    private func setOpenRouterBudget(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            preferences.openRouterMonthlyBudget = nil
            openRouterBudgetError = nil
            return
        }
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard let budget = Double(normalized), budget.isFinite, budget > 0 else {
            openRouterBudgetError = "Enter a positive USD amount"
            return
        }
        openRouterBudgetError = nil
        preferences.openRouterMonthlyBudget = budget
    }

    private var cursorGroup: some View {
        Group {
            groupTitle("Cursor")

            DividedRows {
                SettingRow(
                    title: "Connection",
                    subtitle: cursorConnectionSubtitle
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(cursorConnectionColor)
                            .frame(width: 6, height: 6)
                        Text(cursorConnectionLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Glass.ink(0.72))
                    }
                }

                SettingRow(
                    title: "API key",
                    subtitle: cursorKeyError ?? (store.hasSavedCursorKey
                        ? "saved in this Mac's Keychain"
                        : "team Admin key, session token, or leave empty for the Cursor app")
                ) {
                    if editingCursorKey {
                        VStack(alignment: .trailing, spacing: 6) {
                            SecureField("crsr_…", text: $cursorKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11).monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(width: 150)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.black.opacity(0.25))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.14))
                                )

                            HStack(spacing: 10) {
                                GlassLink(title: "Cancel") {
                                    editingCursorKey = false
                                    cursorKey = ""
                                    cursorKeyError = nil
                                }
                                GlassButton(label: "Save", enabled: !cursorKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                    saveCursorKey()
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            if store.hasSavedCursorKey {
                                GlassLink(title: "Remove") {
                                    Task {
                                        if await store.removeCursorKey() {
                                            cursorKeyError = nil
                                        } else {
                                            cursorKeyError = "Could not remove the key from Keychain"
                                        }
                                    }
                                }
                            }
                            GlassButton(label: store.hasSavedCursorKey ? "Replace…" : "Add key…") {
                                editingCursorKey = true
                                cursorKeyError = nil
                            }
                        }
                    }
                }

                SettingRow(
                    title: "Monthly budget",
                    subtitle: cursorBudgetError ?? "USD · only needed for a team Admin key without a spend limit"
                ) {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 12))
                            .foregroundStyle(Glass.ink(0.55))
                        TextField("20", text: $cursorBudgetText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .onChange(of: cursorBudgetText) { _, value in
                                setCursorBudget(value)
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14))
                    )
                }

                SettingRow(
                    title: "Dollar values",
                    subtitle: "show spend and allowance below each usage row"
                ) {
                    GlassSwitch(isOn: $preferences.showCursorCosts)
                        .onChange(of: preferences.showCursorCosts) { _, _ in
                            store.iconPreferenceChanged()
                        }
                }
            }
        }
    }

    private var cursorProvider: Provider? {
        store.report?.providers.first(where: { $0.name == "Cursor" })
    }

    private var isCursorConnected: Bool {
        guard let provider = cursorProvider, provider.credentialSource != nil else {
            return false
        }
        return provider.error != CursorBudget.notConnectedMessage
    }

    private var cursorConnectionLabel: String {
        guard isCursorConnected else { return "Not connected" }
        if cursorProvider?.error?.contains("rejected") == true
            || cursorProvider?.error == CursorBudget.userKeyMessage
        {
            return "Rejected"
        }
        return "Connected"
    }

    private var cursorConnectionSubtitle: String {
        guard let provider = cursorProvider else {
            return "Uses the signed-in Cursor app, or add a key below"
        }
        var parts: [String] = []
        if let source = provider.credentialSource { parts.append(source.rawValue) }
        if let error = provider.error, error != CursorBudget.missingBudgetMessage {
            parts.append(error)
        }
        return parts.isEmpty
            ? "Uses the signed-in Cursor app, or add a key below"
            : parts.joined(separator: " · ")
    }

    private var cursorConnectionColor: Color {
        guard isCursorConnected else { return Color.white.opacity(0.3) }
        if cursorProvider?.error?.contains("rejected") == true
            || cursorProvider?.error == CursorBudget.userKeyMessage
        {
            return Pace.warn
        }
        return Pace.good
    }

    private func saveCursorKey() {
        let key = cursorKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await store.saveCursorKey(key) {
                editingCursorKey = false
                cursorKey = ""
                cursorKeyError = nil
            } else {
                cursorKeyError = "Could not save the key in Keychain"
            }
        }
    }

    private func setCursorBudget(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            preferences.cursorMonthlyBudget = nil
            cursorBudgetError = nil
            return
        }
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard let budget = Double(normalized), budget.isFinite, budget > 0 else {
            cursorBudgetError = "Enter a positive USD amount"
            return
        }
        cursorBudgetError = nil
        preferences.cursorMonthlyBudget = budget
    }

    /// Show/hide each set-up provider and its model-specific rows. Only the
    /// providers we actually have credentials for get a switch — there is no
    /// sense offering to hide one that was never installed.
    @ViewBuilder
    private var providersGroup: some View {
        let known = (store.report?.providers ?? []).filter(\.loggedIn)
        let knownProviders = Set(known.map(\.name))
        let scopedModels = preferences.knownModelLimits.filter {
            knownProviders.contains($0.provider)
        }

        if !known.isEmpty {
            Group {
                groupTitle("Providers")

                DividedRows {
                    ForEach(known) { provider in
                        SettingRow(title: "Show \(provider.name)") {
                            GlassSwitch(isOn: Binding(
                                get: { !preferences.hiddenProviders.contains(provider.name) },
                                set: { shown in
                                    preferences.setProvider(provider.name, hidden: !shown)
                                    store.iconPreferenceChanged()
                                }
                            ))
                        }
                    }

                    ForEach(scopedModels) { model in
                        SettingRow(
                            title: "Show \(model.provider) \(model.displayName) limits",
                            subtitle: "the model-specific usage rows"
                        ) {
                            GlassSwitch(isOn: Binding(
                                get: { !preferences.hiddenModelLimits.contains(model.id) },
                                set: { shown in
                                    preferences.setModelLimit(
                                        provider: model.provider,
                                        model: model.model,
                                        hidden: !shown
                                    )
                                    store.iconPreferenceChanged()
                                }
                            ))
                        }
                    }
                }
            }
        }
    }

    private var alertsGroup: some View {
        Group {
            groupTitle("Alerts")

            VStack(alignment: .leading, spacing: 16) {
                threshold(
                    title: "Alert past",
                    value: String(format: "%.0f%%", preferences.usageThreshold),
                    isOn: $preferences.usageAlertsEnabled,
                    slider: $preferences.usageThreshold,
                    range: 50...100,
                    step: 5,
                    colors: [Pace.warn, Color(red: 1, green: 0.549, blue: 0.235)],
                    bounds: ("50%", "100%")
                )

                threshold(
                    title: "Alert above target",
                    value: String(format: "%.1f×", preferences.paceThreshold),
                    isOn: $preferences.paceAlertsEnabled,
                    slider: $preferences.paceThreshold,
                    range: 1.1...4,
                    step: 0.1,
                    colors: [Pace.warn, Pace.bad],
                    bounds: ("1.1×", "4×")
                )
            }
            .glassGroup()
        }
    }

    private var workingHoursGroup: some View {
        let schedule = preferences.workSchedule

        return Group {
            groupTitle("Working hours")

            DividedRows {
                SettingRow(
                    title: "Use working hours for target",
                    subtitle: "spreads each quota across your selected hours"
                ) {
                    GlassSwitch(isOn: $preferences.workingHoursEnabled)
                }

                SettingRow(title: "Days", enabled: preferences.workingHoursEnabled) {
                    WorkdayPicker(
                        selected: preferences.workingWeekdays,
                        enabled: preferences.workingHoursEnabled
                    ) { day, selected in
                        preferences.setWorkingDay(day, enabled: selected)
                    }
                }

                SettingRow(title: "Hours", enabled: preferences.workingHoursEnabled) {
                    HStack(spacing: 7) {
                        MinuteTimePicker(
                            minute: $preferences.workingStartMinute,
                            accessibilityLabel: "Working hours start",
                            enabled: preferences.workingHoursEnabled
                        )
                        Text("to")
                            .font(.system(size: 11))
                            .foregroundStyle(Glass.ink(preferences.workingHoursEnabled ? 0.45 : 0.3))
                        MinuteTimePicker(
                            minute: $preferences.workingEndMinute,
                            accessibilityLabel: "Working hours end",
                            enabled: preferences.workingHoursEnabled
                        )
                    }
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(workingStatusColor(schedule))
                        .frame(width: 5, height: 5)
                    Text(workingStatus(schedule))
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.ink(preferences.workingHoursEnabled ? 0.58 : 0.4))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var refreshGroup: some View {
        Group {
            groupTitle("Refresh")

            VStack(alignment: .leading, spacing: 10) {
                Text("Refresh every")
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(0.92))

                GlassSegmented(
                    options: [.init(5.0, "5"), .init(10.0, "10"), .init(15.0, "15"), .init(30.0, "30"), .init(60.0, "60 min")],
                    selection: $preferences.refreshMinutes
                )
            }
            .glassGroup()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Tokens on Track · v\(Self.version)")
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.4))
            Spacer(minLength: 8)
            GlassLink(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return info?["TOTDisplayVersion"] as? String
            ?? info?["CFBundleShortVersionString"] as? String
            ?? "dev"
    }

    // ----------------------------------------------------------------- //

    private func groupTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(1.3)
            .foregroundStyle(Glass.ink(0.42))
            .padding(.leading, 4)
            .padding(.top, 2)
    }

    private func threshold(
        title: String,
        value: String,
        isOn: Binding<Bool>,
        slider: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        colors: [Color],
        bounds: (String, String)
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(isOn.wrappedValue ? 0.92 : 0.4))
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Glass.ink(isOn.wrappedValue ? 1 : 0.4))
                GlassSwitch(isOn: isOn)
            }

            GlassSlider(
                value: slider,
                range: range,
                accessibilityLabel: title,
                accessibilityValue: value,
                step: step,
                colors: colors,
                enabled: isOn.wrappedValue
            )

            HStack {
                Text(bounds.0)
                Spacer()
                Text(bounds.1)
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(Glass.ink(0.35))
        }
    }

    private func workingStatus(_ schedule: WorkSchedule) -> String {
        guard schedule.enabled else { return "Off · target uses wall clock" }
        guard schedule.isValid else {
            return "Target uses wall clock · start and end must differ"
        }
        return schedule.isActive(at: Date())
            ? "Target uses working hours"
            : "Target uses wall clock · outside working hours"
    }

    private func workingStatusColor(_ schedule: WorkSchedule) -> Color {
        schedule.enabled && schedule.isValid && schedule.isActive(at: Date())
            ? Pace.good
            : Color.white.opacity(0.35)
    }

    /// The last part standing is locked on: a menu bar item with nothing drawn
    /// in it cannot be clicked back open to undo the mistake.
    private func partSwitch(_ isOn: Binding<Bool>) -> some View {
        let enabledParts = [
            preferences.showLogoInMenuBar,
            preferences.showGaugeInMenuBar,
            preferences.showPercentInMenuBar,
        ].filter { $0 }.count
        let locked = isOn.wrappedValue && enabledParts == 1

        return GlassSwitch(isOn: isOn, enabled: !locked)
            .onChange(of: isOn.wrappedValue) { _, _ in
                store.iconPreferenceChanged()
            }
    }
}

// --------------------------------------------------------------------- //

/// Seven independent chips rather than a segmented control: several days are
/// selected at once, and the last one stays locked on.
private struct WorkdayPicker: View {
    let selected: Set<WorkSchedule.Weekday>
    let enabled: Bool
    let setSelected: (WorkSchedule.Weekday, Bool) -> Void

    @FocusState private var focusedDay: WorkSchedule.Weekday?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorkSchedule.Weekday.mondayFirst) { day in
                let chosen = selected.contains(day)
                let focused = focusedDay == day
                Button {
                    setSelected(day, !chosen)
                } label: {
                    Text(day.shortLabel)
                        .font(.system(size: 10, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(Glass.ink(chosen ? 1 : 0.55))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(
                                chosen
                                    ? Color.white.opacity(0.23)
                                    : Color.black.opacity(0.18)
                            )
                        )
                        .overlay(
                            ZStack {
                                Circle().strokeBorder(Color.white.opacity(chosen ? 0.17 : 0.08))
                                if focused {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .focused($focusedDay, equals: day)
                .focusEffectDisabled()
                .disabled(!enabled || (chosen && selected.count == 1))
                .accessibilityLabel(day.accessibilityLabel)
                .accessibilityValue(chosen ? "Selected" : "Not selected")
            }
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Native time semantics and locale formatting, with the stored value reduced
/// to minutes after midnight so its arbitrary date is never persisted.
private struct MinuteTimePicker: View {
    @Binding var minute: Int
    let accessibilityLabel: String
    let enabled: Bool

    var body: some View {
        DatePicker(
            "",
            selection: Binding(
                get: { date(for: minute) },
                set: { date in
                    let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
                    minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.field)
        .controlSize(.small)
        .fixedSize()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
    }

    private func date(for minute: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let value = min(1439, max(0, minute))
        return calendar.date(
            bySettingHour: value / 60,
            minute: value % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}

// --------------------------------------------------------------------- //

/// An inset group whose rows are separated by hairlines rather than spacing —
/// the shape macOS System Settings uses for a run of related switches.
private struct DividedRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            _VariadicView.Tree(Layout()) { content }
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
        )
    }

    private struct Layout: _VariadicView.UnaryViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            let last = children.last?.id

            ForEach(children) { child in
                VStack(spacing: 0) {
                    child.padding(.vertical, 11)
                    if child.id != last {
                        Rectangle()
                            .fill(Color.white.opacity(0.09))
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}

// --------------------------------------------------------------------- //

/// A scroll area that admits it is one.
///
/// A hard cut at the cap is indistinguishable from the end of the list, and on
/// a trackpad macOS keeps the scroller hidden until you are already scrolling —
/// so the tab looked like it simply stopped after Refresh. The clipped edge now
/// fades while there is more content past it, at whichever end is cut off, and
/// firms up once you reach it. Below the cap it does not scroll and shows no
/// fade at all.
private struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    /// Top of the content within the scroll area: 0 at rest, negative once
    /// scrolled. Paired with the two heights it says which edge is cut off.
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private let fade: CGFloat = 26
    private let space = "capped-scroll"

    private var hiddenAbove: Bool { viewportHeight > 0 && offset < -0.5 }
    private var hiddenBelow: Bool { viewportHeight > 0 && contentHeight + offset - viewportHeight > 0.5 }

    /// A ScrollView has no height of its own to offer, so `maxHeight` alone
    /// leaves the window hosting it free to settle on something far shorter —
    /// which is how the settings tab came out a third of its cap. Measuring the
    /// content and asking for exactly what it needs, up to the cap, gives the
    /// window a number it cannot argue with. Before the first measurement the
    /// cap is the better guess: too tall corrects downwards on the same pass,
    /// too short leaves the panel visibly stunted.
    private var height: CGFloat {
        contentHeight > 0 ? min(maxHeight, contentHeight) : maxHeight
    }

    var body: some View {
        ScrollView {
            content.background(
                GeometryReader { inner in
                    Color.clear.preference(
                        key: ReachKey.self,
                        value: Reach(
                            offset: inner.frame(in: .named(space)).minY,
                            height: inner.size.height
                        )
                    )
                }
            )
        }
        .coordinateSpace(name: space)
        .frame(height: height)
        // An overlay is measured without being given a say in the layout, so
        // reading the viewport back cannot feed into the height above it.
        .overlay(
            GeometryReader { viewport in
                Color.clear
                    .onAppear { viewportHeight = viewport.size.height }
                    .onChange(of: viewport.size.height) { _, height in viewportHeight = height }
            }
        )
        .onPreferenceChange(ReachKey.self) { reach in
            offset = reach.offset
            contentHeight = reach.height
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: hiddenAbove ? fade : 0)
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: hiddenBelow ? fade : 0)
            }
        )
    }
}

/// Where the scrolled content currently sits. At file scope because a generic
/// type cannot hold the static default a PreferenceKey needs.
private struct Reach: Equatable {
    var offset: CGFloat = 0
    var height: CGFloat = 0
}

private struct ReachKey: PreferenceKey {
    static let defaultValue = Reach()
    static func reduce(value: inout Reach, nextValue: () -> Reach) {
        value = nextValue()
    }
}
