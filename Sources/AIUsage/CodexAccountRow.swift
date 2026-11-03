import AppKit
import SwiftUI

struct CodexAccountRow: View {
    let entry: CodexProfile.Entry
    let report: Report?
    @ObservedObject private var preferences = Preferences.shared
    @EnvironmentObject private var store: UsageStore
    @State private var labelText: String = ""
    @State private var committedLabelText: String = ""
    @State private var confirmingRemoval = false
    @State private var folderError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountNicknameField(
                text: $labelText,
                plan: liveProvider?.plan,
                hasChanges: labelText != committedLabelText,
                onCommit: commitLabel
            )
            .onAppear { syncLabel() }
            Text(folderError ?? statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
            #if APP_STORE
            GlassButton(label: "Choose folder again…", systemImage: "folder") {
                guard let url = AccountFolderPicker.choose(for: .codex) else { return }
                do {
                    let path = try AccountFolderPicker.save(url, for: .codex, expectedPath: entry.normalizedPath)
                    _ = DetectedAccount(provider: .codex, path: path).add()
                    folderError = nil
                    store.connectionsChanged()
                } catch { folderError = error.localizedDescription }
            }
            #endif
            GlassLink(title: "Remove account…") { confirmingRemoval = true }
        }
        .confirmationDialog("Remove this account from Tokens on Track?", isPresented: $confirmingRemoval) {
            Button("Remove account", role: .destructive) {
                preferences.removeCodexProfile(path: entry.normalizedPath)
                store.connectionsChanged()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Codex profile and login files are unchanged.")
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
            if provider.loggedIn, provider.ok {
                return entry.normalizedPath == CodexProfile.defaultNormalizedPath ? CodexProfile.defaultRelativePath : entry.normalizedPath
            }
        }
        return CodexProfile.settingsDetail(
            entry: entry,
            hasCredential: liveProvider?.loggedIn == true,
            appStore: appStore
        )
    }

    private func syncLabel() {
        let label = preferences.codexLabel(for: entry.normalizedPath)
            ?? liveProvider?.name
            ?? CodexProfile.defaultLabel(
                planType: nil,
                customLabel: nil,
                profilePath: entry.normalizedPath
            )
        labelText = label
        committedLabelText = label
    }

    private func commitLabel() {
        guard labelText != committedLabelText else { return }
        preferences.setCodexLabel(labelText, for: entry.normalizedPath)
        let label = preferences.codexLabel(for: entry.normalizedPath)
            ?? CodexProfile.defaultLabel(
                planType: liveProvider?.plan,
                customLabel: nil,
                profilePath: entry.normalizedPath
            )
        labelText = label
        committedLabelText = label
        store.connectionsChanged()
    }
}
