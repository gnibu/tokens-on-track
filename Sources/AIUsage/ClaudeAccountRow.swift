import AppKit
import SwiftUI

/// Same controls as the OpenRouter key: the token is written straight to the
/// app's Keychain item and the field never shows a saved value.
private struct ClaudeSetupTokenField: View {
    let account: String
    var allowsRemoval = true
    var onTokenChanged: (Bool) -> Void = { _ in }
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
                    if hasToken && allowsRemoval {
                        GlassLink(title: "Remove") { remove() }
                    }
                    GlassButton(label: hasToken ? "Replace…" : "Add token…") {
                        editing = true
                        error = nil
                    }
                }
            }
        }
        .onAppear {
            hasToken = ClaudeSetupTokenKeychain.read(account: account) != nil
            onTokenChanged(hasToken)
        }
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
        onTokenChanged(true)
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
        onTokenChanged(false)
        error = nil
        store.connectionsChanged()
    }
}

struct ClaudeAccountRow: View {
    let entry: ClaudeProfile.Entry
    let report: Report?
    @ObservedObject private var preferences = Preferences.shared
    @EnvironmentObject private var store: UsageStore
    @State private var labelText: String = ""
    @State private var committedLabelText: String = ""
    @State private var removeError: String?
    @State private var confirmingRemoval = false
    @State private var hasSetupToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountNicknameField(
                text: $labelText,
                plan: liveProvider?.plan,
                hasChanges: labelText != committedLabelText,
                onCommit: commitLabel
            )
            .onAppear {
                syncLabel()
                hasSetupToken = ClaudeSetupTokenKeychain.read(account: entry.id) != nil
            }
            Text(removeError ?? statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
            ClaudeSetupTokenField(account: entry.id, allowsRemoval: !isTokenOnly) { hasSetupToken = $0 }
            GlassLink(title: "Remove account…") { confirmingRemoval = true }
        }
        .onChange(of: store.isRefreshing) { _, refreshing in
            if !refreshing { hasSetupToken = ClaudeSetupTokenKeychain.read(account: entry.id) != nil }
        }
        .confirmationDialog("Remove this account from Tokens on Track?", isPresented: $confirmingRemoval) {
            Button("Remove account", role: .destructive) {
                guard ClaudeSetupTokenKeychain.remove(account: entry.id) else {
                    removeError = "Could not remove the token from Keychain"
                    return
                }
                preferences.removeClaudeProfile(path: entry.normalizedPath)
                store.connectionsChanged()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its saved setup token, if any, is removed from this app. Your Claude Code login is unchanged.")
        }
    }

    private var liveProvider: Provider? {
        report?.providers.first { $0.id == entry.keychainService }
    }

    private var isTokenOnly: Bool {
        ClaudeProfile.isTokenOnlyPath(entry.normalizedPath, stateDirectory: UsageStore.stateDirectory)
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
            if provider.loggedIn, provider.ok, !hasSetupToken {
                return entry.normalizedPath == ClaudeProfile.defaultNormalizedPath ? ClaudeProfile.defaultRelativePath : entry.normalizedPath
            }
        }
        if hasSetupToken { return "Setup token saved in this Mac’s Keychain" }
        if isTokenOnly { return "Add a setup token to reconnect this account" }
        let hasCredential = liveProvider?.loggedIn == true
        return ClaudeProfile.settingsDetail(entry: entry, hasCredential: hasCredential, appStore: appStore)
    }

    private func syncLabel() {
        let label = preferences.claudeLabel(for: entry.normalizedPath)
            ?? (isTokenOnly ? "Claude" : liveProvider?.name)
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
        preferences.setClaudeLabel(isTokenOnly ? ClaudeProfile.tokenAccountLabel(labelText) : labelText, for: entry.normalizedPath)
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
