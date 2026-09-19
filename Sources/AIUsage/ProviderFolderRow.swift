import AppKit
import SwiftUI

struct ProviderFolderRow: View {
    let folder: ProviderFolder
    @EnvironmentObject private var store: UsageStore
    @State private var status = ""
    @State private var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(folder.name).font(.system(size: 13))
                Spacer()
                if selected {
                    GlassLink(title: "Remove") {
                        ProviderFolderAccess.shared.remove(folder)
                        updateStatus()
                        store.connectionsChanged()
                    }
                    .accessibilityLabel("Remove \(folder.name) folder access")
                }
                GlassButton(label: selected ? "Choose again…" : "Choose folder…") { chooseFolder() }
                    .accessibilityLabel("Choose \(folder.name) folder")
            }
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { updateStatus() }
        .onChange(of: store.isRefreshing) { _, refreshing in
            if !refreshing { updateStatus() }
        }
    }

    private func updateStatus() {
        selected = ProviderFolderAccess.shared.isSelected(folder)
        status = selected ? ProviderFolderAccess.shared.status(folder) : "Select \(folder.suggestedPath)"
    }

    private func chooseFolder() {
        MenuBarItem.shared.performModalPanel {
            let panel = NSOpenPanel()
            panel.title = "Connect \(folder.name)"
            panel.message = "Select \(folder.suggestedPath). Tokens on Track only reads \(folder.fileName); it never changes your login. Use ⌘⇧G to enter the folder path."
            panel.prompt = "Allow Read Access"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.showsHiddenFiles = true
            // The system panel resolves ~ against the real home; the app's
            // NSHomeDirectory points inside its sandbox container.
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try ProviderFolderAccess.shared.select(url, for: folder)
                updateStatus()
                store.connectionsChanged()
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

struct ProviderConnectionInfo: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(size: 13))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
