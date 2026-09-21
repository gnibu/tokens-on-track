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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Label", text: $labelText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onAppear { syncLabel() }
                    .onSubmit { commitLabel() }
                Spacer(minLength: 8)
                if let plan = liveProvider?.plan, !plan.isEmpty {
                    Text(plan.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Glass.ink(0.5))
                }
            }
            Text(statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
            if entry.normalizedPath != ClaudeProfile.defaultNormalizedPath {
                GlassLink(title: "Remove") {
                    preferences.removeClaudeProfile(path: entry.normalizedPath)
                    store.connectionsChanged()
                }
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
        labelText = preferences.claudeLabel(for: entry.normalizedPath)
            ?? liveProvider?.name
            ?? ClaudeProfile.defaultLabel(
                subscriptionType: nil,
                customLabel: nil,
                profilePath: entry.normalizedPath
            )
    }

    private func commitLabel() {
        preferences.setClaudeLabel(labelText, for: entry.normalizedPath)
        store.connectionsChanged()
    }
}
