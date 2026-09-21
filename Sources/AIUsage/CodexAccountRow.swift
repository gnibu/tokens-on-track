import AppKit
import SwiftUI

struct CodexAccountsGroup: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Group {
            groupTitle("Codex accounts")
            DividedRows {
                ForEach(entries) { entry in
                    CodexAccountRow(entry: entry, report: store.report)
                }
                addRow
            }
        }
    }

    private var entries: [CodexProfile.Entry] {
        preferences.codexSettingsEntries(discoveredPaths: store.discoveredCodexPaths)
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
            panel.title = "Add Codex profile"
            panel.message = "Select a CODEX_HOME folder containing auth.json. Tokens on Track only reads the login; it never changes it."
            panel.prompt = "Add Profile"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.showsHiddenFiles = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            #if APP_STORE
            do {
                let path = try CodexAccountAccess.shared.select(url)
                preferences.addCodexProfile(path: path)
            } catch {
                return
            }
            #else
            preferences.addCodexProfile(path: url.path)
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

private struct CodexAccountRow: View {
    let entry: CodexProfile.Entry
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
            if entry.normalizedPath != CodexProfile.defaultNormalizedPath {
                GlassLink(title: "Remove") {
                    preferences.removeCodexProfile(path: entry.normalizedPath)
                    store.connectionsChanged()
                }
            }
        }
    }

    private var liveProvider: Provider? {
        report?.providers.first { $0.id == entry.providerID }
    }

    private var statusLine: String {
        #if APP_STORE
        let appStore = true
        #else
        let appStore = false
        #endif
        if let provider = liveProvider {
            if let error = provider.error, !provider.ok { return error }
            if provider.loggedIn, provider.ok { return entry.normalizedPath }
        }
        return CodexProfile.settingsDetail(
            entry: entry,
            hasCredential: liveProvider?.loggedIn == true,
            appStore: appStore
        )
    }

    private func syncLabel() {
        labelText = preferences.codexLabel(for: entry.normalizedPath)
            ?? liveProvider?.name
            ?? CodexProfile.defaultLabel(
                planType: nil,
                customLabel: nil,
                profilePath: entry.normalizedPath
            )
    }

    private func commitLabel() {
        preferences.setCodexLabel(labelText, for: entry.normalizedPath)
        store.connectionsChanged()
    }
}
