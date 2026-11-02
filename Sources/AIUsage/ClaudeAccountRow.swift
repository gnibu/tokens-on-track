import AppKit
import SwiftUI

struct ClaudeAccountsGroup: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Group {
            groupTitle("Claude accounts")
            DividedRows {
                ForEach(entries) { entry in
                    ClaudeAccountRow(entry: entry, report: store.report)
                }
                addRow
            }
        }
    }

    private var entries: [ClaudeProfile.Entry] {
        preferences.claudeSettingsEntries(discoveredPaths: store.discoveredClaudePaths)
    }

    private var addRow: some View {
        HStack {
            Text("Add profile folder")
                .font(.system(size: 13))
            Spacer()
            GlassButton(label: "Choose folder…") { chooseFolder() }
        }
    }

    private func chooseFolder() {
        MenuBarItem.shared.performModalPanel {
            let panel = NSOpenPanel()
            panel.title = "Add Claude Code profile"
            panel.message = "Select the folder used as CLAUDE_CONFIG_DIR for a second Claude Code login. Tokens on Track only reads the matching Keychain item; it never changes your login."
            panel.prompt = "Add Profile"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.showsHiddenFiles = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            #if APP_STORE
            do {
                let path = try ClaudeAccountAccess.shared.select(url)
                preferences.addClaudeProfile(path: path)
            } catch {
                return
            }
            #else
            preferences.addClaudeProfile(path: url.path)
            #endif
            store.connectionsChanged()
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Glass.ink(0.42))
            .textCase(.uppercase)
            .padding(.bottom, 2)
    }
}

/// Same controls as the OpenRouter key: the token is written straight to the
/// app's Keychain item and the field never shows a saved value.
private struct ClaudeSetupTokenField: View {
    let account: String
    @EnvironmentObject private var store: UsageStore
    @State private var hasToken = false
    @State private var editing = false
    @State private var token = ""
    @State private var error: String?

    var body: some View {
        SettingRow(title: "Setup token", subtitle: error ?? subtitle) {
            if editing {
                VStack(alignment: .trailing, spacing: 6) {
                    SecureField("sk-ant-oat…", text: $token)
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
                            editing = false
                            token = ""
                            error = nil
                        }
                        GlassButton(label: "Save", enabled: !ClaudeSetupTokenKeychain.normalized(token).isEmpty) {
                            save()
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    if hasToken {
                        GlassLink(title: "Remove") { remove() }
                    }
                    GlassButton(label: hasToken ? "Replace…" : "Add token…") {
                        editing = true
                        error = nil
                    }
                }
            }
        }
        .onAppear { hasToken = ClaudeSetupTokenKeychain.read(account: account) != nil }
    }

    private var subtitle: String {
        hasToken
            ? "used instead of the Claude Code login; each refresh sends Haiku a short message"
            : "from claude setup-token; each refresh then sends Haiku a short message"
    }

    private func save() {
        guard ClaudeSetupTokenKeychain.save(token, account: account) else {
            error = "Could not save the token in Keychain"
            return
        }
        hasToken = true
        editing = false
        token = ""
        error = nil
        store.connectionsChanged()
    }

    private func remove() {
        guard ClaudeSetupTokenKeychain.remove(account: account) else {
            error = "Could not remove the token from Keychain"
            return
        }
        hasToken = false
        error = nil
        store.connectionsChanged()
    }
}

private struct ClaudeAccountRow: View {
    let entry: ClaudeProfile.Entry
    let report: Report?
    @ObservedObject private var preferences = Preferences.shared
    @EnvironmentObject private var store: UsageStore
    @State private var labelText: String = ""
    @State private var committedLabelText: String = ""
    @State private var removeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountNicknameField(
                text: $labelText,
                plan: liveProvider?.plan,
                hasChanges: labelText != committedLabelText,
                onCommit: commitLabel
            )
            .onAppear { syncLabel() }
            Text(removeError ?? statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
            ClaudeSetupTokenField(account: entry.id)
            GlassLink(title: "Remove") {
                guard ClaudeSetupTokenKeychain.remove(account: entry.id) else {
                    removeError = "Could not remove the token from Keychain"
                    return
                }
                preferences.removeClaudeProfile(path: entry.normalizedPath)
                store.connectionsChanged()
            }
        }
    }

    private var liveProvider: Provider? {
        report?.providers.first { $0.id == entry.keychainService }
    }

    private var statusLine: String {
        #if APP_STORE
        let appStore = true
        #else
        let appStore = false
        #endif
        if let provider = liveProvider {
            if let error = provider.error, !provider.ok {
                return error
            }
            if provider.loggedIn, provider.ok {
                return entry.normalizedPath
            }
        }
        let hasCredential = liveProvider?.loggedIn == true
        return ClaudeProfile.settingsDetail(entry: entry, hasCredential: hasCredential, appStore: appStore)
    }

    private func syncLabel() {
        let label = preferences.claudeLabel(for: entry.normalizedPath)
            ?? liveProvider?.name
            ?? ClaudeProfile.defaultLabel(
                subscriptionType: nil,
                customLabel: nil,
                profilePath: entry.normalizedPath
            )
        labelText = label
        committedLabelText = label
    }

    private func commitLabel() {
        guard labelText != committedLabelText else { return }
        preferences.setClaudeLabel(labelText, for: entry.normalizedPath)
        let label = preferences.claudeLabel(for: entry.normalizedPath)
            ?? ClaudeProfile.defaultLabel(
                subscriptionType: liveProvider?.plan,
                customLabel: nil,
                profilePath: entry.normalizedPath
            )
        labelText = label
        committedLabelText = label
        store.connectionsChanged()
    }
}
