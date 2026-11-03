import AppKit
import SwiftUI

/// One regular window, retained when closed so reopening preserves navigation.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow {
        AnyView(SettingsView().environmentObject(UsageStore.shared))
    }
    private var window: NSWindow?
    private let content: () -> AnyView

    init(content: @escaping () -> AnyView) {
        self.content = content
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Tokens on Track Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 560)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(calibratedWhite: 0.145, alpha: 1)
            window.contentViewController = NSHostingController(rootView: content())
            window.setFrameAutosaveName("SettingsWindow")
            if !window.setFrameUsingName("SettingsWindow") { window.center() }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case accounts = "Accounts"
    case workingHours = "Working hours"
    case alerts = "Alerts"
    case agents = "Agents"
    case about = "About & help"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "clock"
        case .appearance: return "display"
        case .accounts: return "person.2"
        case .workingHours: return "calendar"
        case .alerts: return "bell"
        case .agents: return "terminal"
        case .about: return "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "Launch and refresh preferences."
        case .appearance: return "Your menu bar and desktop card."
        case .accounts: return "Your providers, all in one place."
        case .workingHours: return "Set the hours you want your quota to cover."
        case .alerts: return "Choose when to be notified."
        case .agents: return "Share usage with your coding agents."
        case .about: return "Tokens on Track for macOS."
        }
    }
}

struct SettingsAccount: Identifiable {
    enum Connection {
        case claude(ClaudeProfile.Entry)
        case codex(CodexProfile.Entry)
        case openCodeGo, openRouter, cursor
    }

    let id: String
    let kind: String
    let brand: String
    let name: String
    let provider: Provider?
    let connection: Connection

    var status: String {
        guard let provider, provider.loggedIn else { return "Not connected" }
        if provider.stale { return "Stale reading" }
        if provider.ok { return "Connected" }
        return "Needs attention"
    }

    var statusColor: Color {
        guard let provider, provider.loggedIn else { return Glass.ink(0.35) }
        return provider.ok && !provider.stale ? Pace.good : Pace.warn
    }

    @MainActor
    static func catalog(
        report: Report?, preferences: Preferences,
        discoveredClaudePaths: [String] = [], discoveredCodexPaths: [String] = []
    ) -> [SettingsAccount] {
        let providers = report?.providers ?? []
        let claude = preferences.claudeSettingsEntries(discoveredPaths: discoveredClaudePaths).map { entry in
            let provider = providers.first { $0.id == entry.id }
            return SettingsAccount(
                id: entry.id, kind: "claude", brand: "Claude",
                name: preferences.claudeLabel(for: entry.normalizedPath)
                    ?? (ClaudeProfile.isTokenOnlyPath(entry.normalizedPath, stateDirectory: UsageStore.stateDirectory) ? "Claude" : provider?.name)
                    ?? ClaudeProfile.defaultLabel(subscriptionType: nil, customLabel: nil, profilePath: entry.normalizedPath),
                provider: provider, connection: .claude(entry)
            )
        }
        let codex = preferences.codexSettingsEntries(discoveredPaths: discoveredCodexPaths).map { entry in
            let provider = providers.first { $0.id == entry.id }
            return SettingsAccount(
                id: entry.id, kind: "codex", brand: "Codex",
                name: preferences.codexLabel(for: entry.normalizedPath) ?? provider?.name
                    ?? CodexProfile.defaultLabel(planType: nil, customLabel: nil, profilePath: entry.normalizedPath),
                provider: provider, connection: .codex(entry)
            )
        }
        let others: [(String, String, Connection)] = [
            (Fetcher.openCodeGoID, "opencode-go", .openCodeGo),
            (Fetcher.openRouterID, "openrouter", .openRouter),
            (Fetcher.cursorID, "cursor", .cursor),
        ]
        return claude + codex + others.map { id, kind, connection in
            SettingsAccount(id: id, kind: kind, brand: id, name: id,
                            provider: providers.first { $0.id == id }, connection: connection)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared
    @State private var section: SettingsSection = .accounts
    @State private var selectedAccountID: String?
    @State private var sheet: AccountSheet?

    private enum AccountSheet: String, Identifiable {
        case add, detect
        var id: String { rawValue }
    }

    private var accounts: [SettingsAccount] {
        SettingsAccount.catalog(
            report: store.report, preferences: preferences,
            discoveredClaudePaths: store.discoveredClaudePaths,
            discoveredCodexPaths: store.discoveredCodexPaths
        )
    }
    private var selectedAccount: SettingsAccount? {
        accounts.first { $0.id == selectedAccountID } ?? accounts.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.04))
                if section == .accounts {
                    accountsContent
                } else {
                    ScrollView {
                        SettingsControls(section: section)
                            .id(section)
                            .padding(28)
                    }
                }
                Divider()
                HStack {
                    Text("Changes are saved automatically")
                    Spacer()
                    Text("Settings on this Mac")
                }
                .font(.system(size: 10))
                .foregroundStyle(Glass.ink(0.4))
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: 0.145))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                AddAccountSheet { id in selectedAccountID = id }
                    .environmentObject(store)
            case .detect:
                DetectAccountsSheet(existingIDs: Set(accounts.map(\.id))) { id in
                    selectedAccountID = id
                }
                .environmentObject(store)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tokens on Track").font(.system(size: 12, weight: .semibold))
                Text("Settings").font(.system(size: 11)).foregroundStyle(Glass.ink(0.45))
            }
            .padding(.horizontal, 8)
            .padding(.top, 58)
            .padding(.bottom, 26)

            ForEach(SettingsSection.allCases.filter { $0 != .about }) { item in
                sidebarButton(item)
            }
            Spacer()
            sidebarButton(.about)
            Text("Tokens on Track")
                .font(.system(size: 10))
                .foregroundStyle(Glass.ink(0.4))
                .padding(8)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func sidebarButton(_ item: SettingsSection) -> some View {
        Button {
            section = item
        } label: {
            Label(item.rawValue, systemImage: item.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Glass.ink(section == item ? 1 : 0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(section == item ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == item ? .isSelected : [])
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(section.rawValue).font(.system(size: 21, weight: .semibold))
                Text(section.subtitle).font(.system(size: 12)).foregroundStyle(Glass.ink(0.5))
            }
            Spacer(minLength: 0)
            if section == .accounts {
                GlassButton(label: "Detect accounts", systemImage: "magnifyingglass") { sheet = .detect }
                GlassButton(label: "Add account", systemImage: "plus", prominent: true) { sheet = .add }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }

    private var accountsContent: some View {
        HStack(alignment: .top, spacing: 22) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR ACCOUNTS")
                        .font(.system(size: 10, weight: .medium))
                        .kerning(1)
                        .foregroundStyle(Glass.ink(0.45))
                        .padding(.bottom, 8)
                    ForEach(accounts) { account in
                        accountButton(account)
                    }
                }
            }
            .frame(width: 210)

            ScrollView {
                if let account = selectedAccount {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            BrandMark(provider: account.kind, size: 24)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(account.brand).font(.system(size: 15, weight: .semibold))
                                if let plan = account.provider?.plan {
                                    Text(plan).font(.system(size: 11)).foregroundStyle(Glass.ink(0.5))
                                }
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Circle().fill(account.statusColor).frame(width: 6, height: 6)
                                Text(account.status).font(.system(size: 11)).foregroundStyle(Glass.ink(0.65))
                            }
                        }
                        SettingsControls(section: .accounts, account: account)
                            .id(account.id)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
                }
                Text("Detect accounts finds existing local logins. Use Add account for another profile folder or a key.")
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.ink(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(28)
    }

    private func accountButton(_ account: SettingsAccount) -> some View {
        Button {
            selectedAccountID = account.id
        } label: {
            HStack(spacing: 10) {
                BrandMark(provider: account.kind, size: 18)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).help(account.name)
                    Text([account.brand, account.provider?.plan].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(Glass.ink(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle().fill(account.statusColor).frame(width: 6, height: 6)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(selectedAccount?.id == account.id ? 0.07 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(selectedAccount?.id == account.id ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), \(account.brand), \(account.status)")
        .accessibilityAddTraits(selectedAccount?.id == account.id ? .isSelected : [])
    }
}
