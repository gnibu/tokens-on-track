import AppKit
import Combine
import SwiftUI

/// The menu bar item and the panel it drops down, owned outright rather than
/// left to `MenuBarExtra(.window)`.
///
/// SwiftUI's menu bar window draws a hairline of its own *over* whatever it
/// hosts — measured at 173 luminance against a pane of 50, and a 3pt red test
/// stroke came back with a white edge on top of it, so it is composited above
/// the content and cannot be covered from inside the view tree. That line is
/// the whole reason the dropdown never matched the card. A panel of our own has
/// no chrome, so the pane's own rim is the only edge there is.
@MainActor
final class MenuBarItem {
    static let shared = MenuBarItem()

    private var item: NSStatusItem?
    private var panel: NSPanel?
    private var watches: Set<AnyCancellable> = []
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var isPresentingModalPanel = false

    /// Clear of the menu bar, and clear of the shadow the panel casts upwards.
    private let dropGap: CGFloat = 6
    /// How close the panel may come to the screen edge when the item sits near
    /// the corner and the panel would otherwise hang off it.
    private let screenInset: CGFloat = 8

    private init() {}

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = UsageStore.shared.statusImage
        item.button?.toolTip = UsageStore.shared.statusTooltip
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item

        UsageStore.shared.$statusImage
            .sink { [weak self] image in self?.item?.button?.image = image }
            .store(in: &watches)

        UsageStore.shared.$statusTooltip
            .sink { [weak self] text in self?.item?.button?.toolTip = text }
            .store(in: &watches)
    }

    // ----------------------------------------------------------------- //

    @objc private func toggle() {
        if panel != nil {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let content = PanelView()
            .environmentObject(UsageStore.shared)
        let hosting = NSHostingController(rootView: content)
        // The panel is two tabs of different heights, and the settings one
        // grows as the list does.
        hosting.sizingOptions = [.preferredContentSize]

        let panel = DropdownPanel(
            contentRect: NSRect(origin: .zero, size: hosting.view.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.panel = panel

        // As with the card: the hosting controller only publishes its size on
        // the next pass, and the panel has to be placed at its real size now or
        // it lands as if it were zero wide.
        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)
        place(panel)

        panel.makeKeyAndOrderFront(nil)

        // A nonactivating panel leaves whichever app was already frontmost in
        // that state. Close when another app becomes frontmost, which covers a
        // keyboard app switch without interfering with the status item's own
        // click-to-toggle action.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }

        // A menu also closes when you click away from it. The activation
        // observer alone does not cover a click on our own desktop card, which
        // never takes key.
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
            // The item's own window is left to the button action, which
            // toggles: closing here first would have it reopen on the same
            // click and the dropdown could never be clicked shut.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let ours = event.window === panel || event.window === self.item?.button?.window
                    if !ours { self.close() }
                }
                return event
            },
        ].compactMap { $0 }

        item?.button?.highlight(true)
    }

    /// Keep Settings alive while its system folder chooser takes focus.
    func performModalPanel(_ action: () -> Void) {
        isPresentingModalPanel = true
        let previousLevel = panel?.level
        panel?.level = .normal
        defer {
            isPresentingModalPanel = false
            if let previousLevel { panel?.level = previousLevel }
            panel?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        action()
    }

    private func close() {
        guard !isPresentingModalPanel else { return }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        item?.button?.highlight(false)
    }

    /// Hung under the menu bar item, left edges aligned the way a menu is, and
    /// pulled back onto the screen when the item is close enough to the corner
    /// that the panel would otherwise overhang it.
    private func place(_ panel: NSPanel) {
        guard let button = item?.button, let barWindow = button.window else { return }
        let item = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = barWindow.screen ?? NSScreen.main
        let size = panel.frame.size

        var x = item.minX
        if let visible = screen?.visibleFrame {
            x = min(x, visible.maxX - size.width - screenInset)
            x = max(x, visible.minX + screenInset)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: item.minY - dropGap - size.height))
    }
}

// --------------------------------------------------------------------- //

/// A borderless panel refuses key by default, which would leave the settings
/// tab's switches and sliders dead to the keyboard and the first click.
private final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
