import AppKit
import SwiftUI

/// The interactive StandBy window on the built-in display (or, as a screen
/// saver, the only display).
@MainActor
final class OverlayController {
    var isVisible: Bool { window.isVisible }
    private(set) var displayID: CGDirectDisplayID = 0
    /// True while the mouse button is held inside the overlay (a click-drag
    /// swipe), so that drag isn't mistaken for a window being dragged in.
    private(set) var pressInside = false

    var onWake: (() -> Void)?

    private let nav: StandbyNavigator
    private var window: TransitionWindow!
    private var monitor: Any?
    private var previousApp: NSRunningApplication?

    /// `environment` adds the data sources the StandBy views read.
    init(store: ConfigStore, nav: StandbyNavigator, environment: @escaping (OverlayRootView) -> AnyView) {
        self.nav = nav
        // Built up front so the first appearance doesn't wait on window setup.
        window = TransitionWindow(content: environment(OverlayRootView(store: store, nav: nav) { [weak self] in
            self?.onWake?()
        }))
        window.onHidden = { [weak nav] in nav?.isActive = false }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    func show(on screen: NSScreen, displayID: CGDirectDisplayID, takeFocus: Bool) {
        self.displayID = displayID
        nav.isActive = true
        window.panel.allowsKey = takeFocus
        window.present(on: screen.frame)
        if takeFocus {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != getpid() { previousApp = front }
            NSApp.activate()
            window.panel.makeKey()
        }
    }

    func move(to screen: NSScreen, displayID: CGDirectDisplayID) {
        guard isVisible else { return }
        self.displayID = displayID
        window.setFrame(screen.frame)
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        pressInside = false
        window.dismiss(animated: animated)
        let panel = window.panel
        if panel.allowsKey {
            panel.allowsKey = false
            if let previousApp, !previousApp.isTerminated {
                previousApp.activate()
            } else {
                NSApp.hide(nil)
            }
        }
        previousApp = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let panel = window.panel
        guard isVisible, event.window === panel else { return false }
        switch event.type {
        case .scrollWheel:
            nav.handleScroll(event, size: panel.frame.size)
            return true
        case .keyDown:
            let size = panel.frame.size
            let mouse = panel.mouseLocationOutsideOfEventStream
            if !nav.handleKey(event, pointer: CGPoint(x: mouse.x, y: size.height - mouse.y), size: size) { onWake?() }
            return true
        case .leftMouseDown:
            pressInside = true
        case .leftMouseUp:
            pressInside = false
        default:
            break
        }
        return false
    }
}
