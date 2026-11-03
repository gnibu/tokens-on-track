import AppKit
import Foundation
import SwiftUI

@MainActor
enum SettingsTests {
    static func run() {
        testWindowReopensWithoutLosingState()
        testDiscoveryFiltersAndDeduplicatesProfiles()
        testAccountConnectionStatuses()
        testAccountCatalogRetainsDisconnectedProviders()
    }

    private static func testWindowReopensWithoutLosingState() {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.prohibited)
        defer { app.setActivationPolicy(previousPolicy) }
        let settings = SettingsWindow { AnyView(Text("Settings regression fixture")) }
        settings.show()
        guard let first = app.windows.first(where: { $0.title == "Tokens on Track Settings" }) else {
            fail("Settings must open a regular window")
        }
        let frame = NSRect(x: 120, y: 140, width: 950, height: 620)
        first.setFrame(frame, display: false)
        first.close()
        settings.show()
        let windows = app.windows.filter { $0.title == "Tokens on Track Settings" }
        check(windows.count == 1, "Reopening settings must not create duplicate windows")
        check(windows[0] === first, "Reopening must retain the window and its navigation state")
        check(first.frame == frame, "Reopening must preserve the resized window frame")
        check(first.minSize.width >= 900 && first.minSize.height >= 560, "The window must fit account details at its minimum size")
        first.close()
    }

    private static func testDiscoveryFiltersAndDeduplicatesProfiles() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let claude = root.appendingPathComponent("claude")
            let codex = root.appendingPathComponent("codex")
            let missingAuth = root.appendingPathComponent("empty-codex")
            for directory in [claude, codex, missingAuth] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let auth = codex.appendingPathComponent("auth.json")
            let contents = Data("fixture: discovery must not parse or rewrite credentials".utf8)
            try contents.write(to: auth)
            let found = AccountDiscovery.profiles(
                claudePaths: [claude.path, claude.path + "/./", auth.path, root.appendingPathComponent("absent").path],
                codexPaths: [codex.path, codex.path + "/./", missingAuth.path]
            )
            check(found.count == 2, "Discovery must find both profile types once and skip invalid folders")
            check(found.map(\.id) == [ClaudeProfile.keychainService(for: claude.path), CodexProfile.providerID(for: codex.path)],
                  "Discovered identities must match account catalog identities")
            check(try Data(contentsOf: auth) == contents, "Discovery must leave auth files unchanged")
            check(AccountDiscovery.profiles(claudePaths: [], codexPaths: []).isEmpty, "Empty discovery must produce no candidates")
        } catch { fail("Discovery fixture failed: \(error)") }
    }

    private static func testAccountConnectionStatuses() {
        func account(_ provider: Provider?) -> SettingsAccount {
            SettingsAccount(id: "Codex", kind: "codex", brand: "Codex", name: "Work", provider: provider,
                            connection: .codex(.init(normalizedPath: "/fixture/codex", providerID: "Codex", source: .configured, preferenceRank: 1)))
        }
        var provider = Provider(name: "Codex")
        check(account(nil).status == "Not connected", "Missing providers need setup status")
        check(account(provider).status == "Not connected", "A profile without a login is not connected")
        provider.loggedIn = true
        check(account(provider).status == "Needs attention", "Rejected logins need actionable status")
        provider.stale = true
        check(account(provider).status == "Stale reading", "Carried readings must be identified")
        provider.ok = true
        provider.stale = false
        check(account(provider).status == "Connected", "Successful accounts must show connected")
    }

    private static func testAccountCatalogRetainsDisconnectedProviders() {
        let catalog = SettingsAccount.catalog(report: nil, preferences: .shared)
        for id in [Fetcher.openCodeGoID, Fetcher.openRouterID, Fetcher.cursorID] {
            let account = catalog.first { $0.id == id }
            check(account != nil && account?.status == "Not connected", "\(id) must remain configurable before login")
        }
        check(Set(catalog.map(\.id)).count == catalog.count, "Account list identities must be unique")
    }

    private static func check(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }
    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
