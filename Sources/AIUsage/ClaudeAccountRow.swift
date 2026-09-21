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

private struct ClaudeAccountRow: View {
    let entry: ClaudeProfile.Entry
    let report: Report?
    @ObservedObject private var preferences = Preferences.shared
    @EnvironmentObject private var store: UsageStore
    @State private var labelText: String = ""
    @State private var committedLabelText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountNicknameField(
                text: $labelText,
                plan: liveProvider?.plan,
                onCommit: commitLabel
            )
            .onAppear { syncLabel() }
            Text(statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
            GlassLink(title: "Remove") {
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
