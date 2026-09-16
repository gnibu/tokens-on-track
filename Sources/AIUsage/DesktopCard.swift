import AppKit
import Combine
import SwiftUI

/// The always-visible card, as a borderless panel rather than a WidgetKit
/// widget: a widget extension runs sandboxed and so could reach neither the
/// Keychain nor ~/.codex/auth.json, and it would be pinned to the widget grid.
/// A panel drags anywhere and needs neither.
@MainActor
final class DesktopCard {
    static let shared = DesktopCard()

    private var panel: NSPanel?
    private var watches: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var isRepositioning = false

    private let width: CGFloat = 460
    private let inset: CGFloat = 30

    private init() {}

    /// Called once at launch; from then on preference changes drive it.
    func start() {
        let preferences = Preferences.shared

        preferences.$showDesktopCard
            .removeDuplicates()
            .sink { [weak self] visible in
                if visible { self?.show() } else { self?.hide() }
            }
            .store(in: &watches)

        preferences.$desktopCardFloats
            .removeDuplicates()
            .sink { [weak self] floats in
                self?.panel?.level = Self.level(floating: floats)
            }
            .store(in: &watches)
    }

    // ----------------------------------------------------------------- //

    private func show() {
        if panel != nil { return }

        let content = CardWindowView()
            .environmentObject(UsageStore.shared)
            .frame(width: width)
        let hosting = NSHostingController(rootView: content)
        // Let the panel follow the card: it grows a row taller the moment a
        // provider starts reporting an error instead of windows.
        hosting.sizingOptions = [.preferredContentSize]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.view.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = Self.level(floating: Preferences.shared.desktopCardFloats)
        // Present on every Space, never in the ⌘-tab or Exposé rotations.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        self.panel = panel

        // `preferredContentSize` only reaches the window on the next pass, and
        // first-run placement needs the real width now — otherwise the card is
        // positioned as if it were zero wide and hangs off the screen edge.
        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)

        anchor(panel, to: savedAnchor(for: panel.frame.size))
        panel.orderFrontRegardless()

        observers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main
            ) { note in
                guard let moved = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    // Every move we make ourselves also lands here. Only a drag
                    // should redefine where the user wants the card.
                    guard !self.isRepositioning else { return }
                    Preferences.shared.desktopCardAnchor =
                        NSPoint(x: moved.frame.minX, y: moved.frame.maxY)
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: panel, queue: .main
            ) { note in
                guard let resized = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    guard let top = Preferences.shared.desktopCardAnchor else { return }
                    // Keep the top edge put; only the bottom should move.
                    self.reposition(resized, topLeft: top)
                }
            },
        ]
    }

    private func hide() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        panel?.orderOut(nil)
        panel = nil
    }

    private func anchor(_ panel: NSPanel, to top: NSPoint) {
        reposition(panel, topLeft: top)
        Preferences.shared.desktopCardAnchor = top
    }

    /// Place the card by its top left corner, without the move being mistaken
    /// for a drag and written back over the remembered position.
    private func reposition(_ window: NSWindow, topLeft: NSPoint) {
        isRepositioning = true
        window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
        isRepositioning = false
    }

    /// Desktop level sits above the wallpaper and the icons but below every
    /// window. Floating keeps the card in front of everything instead.
    private static func level(floating: Bool) -> NSWindow.Level {
        if floating { return .floating }
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    /// Remembered top left corner, or the top right of the main screen on a
    /// first run. A remembered spot on a screen that is no longer attached is
    /// discarded rather than leaving the card somewhere unreachable.
    private func savedAnchor(for size: NSSize) -> NSPoint {
        if let saved = Preferences.shared.desktopCardAnchor {
            let frame = NSRect(x: saved.x, y: saved.y - size.height, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
                return saved
            }
        }
        guard let screen = NSScreen.main else { return NSPoint(x: inset, y: inset + size.height) }
        return NSPoint(x: screen.visibleFrame.maxX - size.width - inset, y: screen.visibleFrame.maxY - inset)
    }
}

// --------------------------------------------------------------------- //

/// The card plus the chrome that only makes sense free-standing on the desktop.
///
/// The pane goes red from the inside once the worst window is in trouble — the
/// card is glanced at, not read, so the state has to survive peripheral vision.
private struct CardWindowView: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        let timing = Pace.Timing(schedule: preferences.workSchedule)
        let display = store.report?.displaying(
            hiding: preferences.hiddenProviders,
            hidingSpark: preferences.hiddenSpark
        )
        let hot = Pace.verdict(display, timing: timing).hot

        DesktopUsageCard(timing: timing)
            .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
            // The drop shadow is the panel's own: a SwiftUI one would be
            // clipped by the window it is drawn inside.
            .glassPane(
                radius: Glass.cardRadius,
                tint: hot ? Color(red: 1, green: 0.471, blue: 0.471) : nil,
                shadow: false
            )
            .contextMenu {
                Button("Refresh now") {
                    Task { await store.refresh() }
                }
                Button("Hide card") {
                    Preferences.shared.showDesktopCard = false
                }
                Divider()
                Button("Quit Tokens on Track") {
                    NSApplication.shared.terminate(nil)
                }
            }
    }
}
