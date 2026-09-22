import AppKit
import SwiftUI

/// Plain AppKit rather than a SwiftUI `App`: the only scene this ever had was a
/// `MenuBarExtra`, and that window comes with chrome we cannot turn off — see
/// `MenuBarItem`. Without it there is no scene left to declare.
@main
enum AIUsageApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock tile, no menu bar of its own — LSUIElement covers this too,
        // but setting it here keeps an unbundled debug run honest.
        NSApp.setActivationPolicy(.accessory)
        // No main menu means macOS has nowhere to match ⌘X/⌘C/⌘V/⌘A key
        // equivalents, so those shortcuts never reach cut:/copy:/paste:/… on
        // the focused text field. A minimal Edit menu restores them.
        NSApp.mainMenu = Self.makeMainMenu()
        Notifier.requestAuthorization()
        MainActor.assumeIsolated {
            MenuBarItem.shared.start()
            DesktopCard.shared.start()
        }
    }

    /// A menu bar carrying only an Edit menu. `.accessory` apps show no menu
    /// bar, but the items' key equivalents still drive standard editing
    /// shortcuts in the responder chain.
    private static func makeMainMenu() -> NSMenu {
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
        mainMenu.addItem(editItem)
        return mainMenu
    }
}
