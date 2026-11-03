import AppKit
import SwiftUI

enum AccountProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case codex = "Codex"
    case openCodeGo = "OpenCode Go"
    case openRouter = "OpenRouter"
    case cursor = "Cursor"
    var id: String { rawValue }
}

/// Folder access is granted by the system picker, never by a typed path.
enum AccountFolderPicker {
    @MainActor
    static func choose(for provider: AccountProvider) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add \(provider.rawValue) profile"
        panel.message = provider == .codex
            ? "Choose a CODEX_HOME folder containing auth.json. Use ⇧⌘G to enter a path."
            : "Choose the folder used as CLAUDE_CONFIG_DIR. Use ⇧⌘G to enter a path."
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func save(_ url: URL, for provider: AccountProvider) throws -> String {
        #if APP_STORE
        return try provider == .codex
            ? CodexAccountAccess.shared.select(url)
            : ClaudeAccountAccess.shared.select(url)
        #else
        if provider == .codex,
           !FileManager.default.isReadableFile(atPath: url.appendingPathComponent("auth.json").path) {
            throw ProviderFolderAccess.AccessError.wrongFolder("auth.json")
        }
        return ClaudeProfile.normalizedPath(url.path)
        #endif
    }
}

struct AddAccountSheet: View {
    let onAdded: (String) -> Void
    @EnvironmentObject private var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider: AccountProvider = .claude
    @State private var useSetupToken = false
    @State private var folder: URL?
    @State private var nickname = ""
    @State private var credential = ""
    @State private var error: String?
    @State private var saving = false

    private var usesFolder: Bool {
        provider == .codex || (provider == .claude && !useSetupToken)
    }
    private var ready: Bool {
        usesFolder ? folder != nil : !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var hasSavedKey: Bool {
        switch provider {
        case .openCodeGo: return store.hasSavedOpenCodeGoKey
        case .openRouter: return store.hasSavedOpenRouterKey
        case .cursor: return store.hasSavedCursorKey
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add account").font(.system(size: 20, weight: .semibold))
                Text("Connect an existing login or add a supported credential.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider").font(.system(size: 12, weight: .medium))
                Picker("Provider", selection: $provider) {
                    ForEach(AccountProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
                .onChange(of: provider) { _, _ in
                    folder = nil
                    credential = ""
                    error = nil
                    useSetupToken = false
                }
            }
            if provider == .claude {
                Picker("Connection method", selection: $useSetupToken) {
                    Text("Profile folder").tag(false)
                    Text("Setup token").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: useSetupToken) { _, _ in credential = ""; error = nil }
            }
            connectionInput
            if provider == .claude || provider == .codex {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account name").font(.system(size: 12, weight: .medium))
                    TextField("e.g. Work or Personal", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Account name")
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { credential = ""; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(hasSavedKey ? "Replace key" : "Add account") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
                if saving { ProgressView().controlSize(.small) }
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color(white: 0.17))
        .environment(\.colorScheme, .dark)
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .onDisappear { credential = "" }
    }

    @ViewBuilder
    private var connectionInput: some View {
        if usesFolder {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Profile folder", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Choose folder…") {
                        if let selected = AccountFolderPicker.choose(for: provider) {
                            folder = selected
                            error = nil
                        }
                    }
                }
                Text(folder?.path ?? (provider == .codex ? "Choose a CODEX_HOME folder containing auth.json." : "Choose your Claude Code profile folder."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Text(provider == .claude ? "Setup token" : provider == .cursor ? "API key or session token" : "API key")
                    .font(.system(size: 12, weight: .medium))
                SecureField(provider == .claude ? "sk-ant-oat…" : "Paste your key", text: $credential)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(provider == .claude ? "Setup token" : "API key")
                Text(credentialHelp)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if hasSavedKey {
                    Text("This replaces the saved \(provider.rawValue) key. One key connection is supported for this provider.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var credentialHelp: String {
        switch provider {
        case .claude:
            return "From claude setup-token. Saved in Keychain. Each refresh sends Haiku a short message that counts as usage."
        case .cursor:
            return "Use a session token or team Admin API key. A personal user/agent key cannot read usage. Saved in Keychain."
        default:
            return "Saved in this Mac’s Keychain. The saved key is never displayed."
        }
    }

    private func save() {
        guard ready, !saving else { return }
        error = nil
        let preferences = Preferences.shared
        if usesFolder, let folder {
            do {
                let path = try AccountFolderPicker.save(folder, for: provider)
                let id: String
                if provider == .claude {
                    preferences.addClaudeProfile(path: path)
                    if !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        preferences.setClaudeLabel(nickname, for: path)
                    }
                    id = ClaudeProfile.keychainService(for: path)
                } else {
                    preferences.addCodexProfile(path: path)
                    if !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        preferences.setCodexLabel(nickname, for: path)
                    }
                    id = CodexProfile.providerID(for: path)
                }
                finish(id)
            } catch {
                self.error = error.localizedDescription
            }
            return
        }
        if provider == .claude {
            // A token-only account needs a stable identity, not a real CLI folder.
            // Reuse the existing per-profile Keychain and catalog mechanism.
            let path = UsageStore.stateDirectory.appendingPathComponent("accounts/\(UUID().uuidString)").path
            let id = ClaudeProfile.keychainService(for: path)
            guard ClaudeSetupTokenKeychain.save(credential, account: id) else {
                error = "Could not save the token in Keychain"
                return
            }
            preferences.addClaudeProfile(path: path)
            preferences.setClaudeLabel(nickname.isEmpty ? "Claude" : nickname, for: path)
            finish(id)
            return
        }
        saving = true
        Task { @MainActor in
            let saved: Bool
            let id: String
            switch provider {
            case .openCodeGo:
                id = Fetcher.openCodeGoID
                saved = await store.saveOpenCodeGoKey(credential)
            case .openRouter:
                id = Fetcher.openRouterID
                saved = await store.saveOpenRouterKey(credential)
            case .cursor:
                id = Fetcher.cursorID
                saved = await store.saveCursorKey(credential)
            default:
                saved = false
                id = ""
            }
            saving = false
            if saved { finish(id) }
            else { error = "Could not save the key in Keychain" }
        }
    }

    private func finish(_ id: String) {
        credential = ""
        onAdded(id)
        store.connectionsChanged()
        dismiss()
    }
}

struct DetectAccountsSheet: View {
    let existingIDs: Set<String>
    let onAdded: (String) -> Void
    @EnvironmentObject private var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [Candidate] = []
    @State private var selected: Set<String> = []
    @State private var scanning = true

    private struct Candidate: Identifiable {
        let provider: AccountProvider
        let path: String
        var id: String {
            provider == .claude ? ClaudeProfile.keychainService(for: path) : CodexProfile.providerID(for: path)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Detected accounts").font(.system(size: 20, weight: .semibold))
            #if APP_STORE
            Text("Choose a profile folder to grant access. The App Store edition cannot scan other apps’ folders or processes.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Add Claude folder…") { chooseFolder(.claude) }
                Button("Add Codex folder…") { chooseFolder(.codex) }
            }
            #else
            Text("Local Claude Code and Codex profiles. Select the ones to track.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if scanning {
                ProgressView("Looking for local profiles…").controlSize(.small)
            } else if candidates.isEmpty {
                Text("No local profiles found. Start Claude Code or Codex with your profile, then try again, or use Add account to choose a folder.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(candidates) { candidate in
                            HStack(spacing: 12) {
                                Toggle(isOn: Binding(
                                    get: { selected.contains(candidate.id) },
                                    set: { value in
                                        if value { selected.insert(candidate.id) }
                                        else { selected.remove(candidate.id) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(candidate.provider.rawValue).font(.system(size: 12, weight: .medium))
                                        Text(candidate.path).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(existingIDs.contains(candidate.id))
                                if existingIDs.contains(candidate.id) {
                                    Text("Already added").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 270)
            }
            Text("Profiles are found from default folders and running CLI sessions. Other providers use their existing automatic detection when you refresh usage.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            #endif
            if let folderError {
                Text(folderError).font(.system(size: 12)).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                #if !APP_STORE
                Button("Add selected") { addSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || scanning)
                #endif
            }
        }
        .padding(28)
        .frame(width: 500)
        .background(Color(white: 0.17))
        .environment(\.colorScheme, .dark)
        .task { await scan() }
    }

    @State private var folderError: String?

    private func chooseFolder(_ provider: AccountProvider) {
        guard let url = AccountFolderPicker.choose(for: provider) else { return }
        do {
            let path = try AccountFolderPicker.save(url, for: provider)
            if provider == .claude { Preferences.shared.addClaudeProfile(path: path) }
            else { Preferences.shared.addCodexProfile(path: path) }
            let candidate = Candidate(provider: provider, path: path)
            onAdded(candidate.id)
            store.connectionsChanged()
            dismiss()
        } catch { folderError = error.localizedDescription }
    }

    private func scan() async {
        #if !APP_STORE
        let preferences = Preferences.shared
        let knownClaude = preferences.claudeConfiguredPaths + Array(preferences.claudeRememberedPaths)
            + Array(preferences.claudeIgnoredPaths) + store.discoveredClaudePaths
        let knownCodex = preferences.codexConfiguredPaths + Array(preferences.codexRememberedPaths)
            + Array(preferences.codexIgnoredPaths) + store.discoveredCodexPaths
        let result = await Task.detached(priority: .utility) {
            let claude = Set(([ClaudeProfile.defaultNormalizedPath] + knownClaude + Fetcher.discoveredClaudeConfigDirs())
                .map(ClaudeProfile.normalizedPath)).sorted().filter { path in
                    var directory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
                }.map { Candidate(provider: .claude, path: $0) }
            let codex = Set(([CodexProfile.defaultNormalizedPath] + knownCodex + Fetcher.discoveredCodexHomes())
                .map(CodexProfile.normalizedPath)).sorted().filter {
                    FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: $0).appendingPathComponent("auth.json").path)
                }.map { Candidate(provider: .codex, path: $0) }
            return claude + codex
        }.value
        guard !Task.isCancelled else { return }
        candidates = result
        selected = Set(result.map(\.id)).subtracting(existingIDs)
        #endif
        scanning = false
    }

    private func addSelected() {
        for candidate in candidates where selected.contains(candidate.id) {
            if candidate.provider == .claude { Preferences.shared.addClaudeProfile(path: candidate.path) }
            else { Preferences.shared.addCodexProfile(path: candidate.path) }
            onAdded(candidate.id)
        }
        store.connectionsChanged()
        dismiss()
    }
}
