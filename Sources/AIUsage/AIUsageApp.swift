import AppKit
import SwiftUI

/// Plain AppKit rather than a SwiftUI `App`: the only scene this ever had was a
/// `MenuBarExtra`, and that window comes with chrome we cannot turn off — see
/// `MenuBarItem`. Without it there is no scene left to declare.
@main
enum AIUsageApp {
    static func main() {
        // Launched by a coding agent as its MCP server rather than by the user:
        // answer on stdio and never bring up the menu bar item.
        if CommandLine.arguments.dropFirst().contains(AgentServer.flag) {
            AgentServer.run(cacheURL: UsageStore.cacheURL) {
                Preferences.storedWorkSchedule()
            }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { MenuBarItem.shared.showSettings() }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock tile, no menu bar of its own — LSUIElement covers this too,
        // but setting it here keeps an unbundled debug run honest.
        NSApp.setActivationPolicy(.accessory)
        // No main menu means macOS has nowhere to match ⌘X/⌘C/⌘V/⌘A key
        // equivalents, so those shortcuts never reach cut:/copy:/paste:/… on
        // the focused text field. A minimal Edit menu restores them.
        NSApp.mainMenu = Self.makeMainMenu()
        MainActor.assumeIsolated {
            Notifier.requestAuthorization()
            MenuBarItem.shared.start()
            DesktopCard.shared.start()
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        MainActor.assumeIsolated { MenuBarItem.shared.showSettings() }
    }

    /// Accessory apps still use menu key equivalents for settings, editing,
    /// and closing a regular window, even without a visible app menu bar.
    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Tokens on Track", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        mainMenu.addItem(editItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return mainMenu
    }
}
