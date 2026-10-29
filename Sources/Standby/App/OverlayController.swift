import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    /// Only true in screen-saver mode. With an external display the panel must
    /// never take keyboard focus away from what you're doing there.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click land on an inactive panel instead of just focusing it.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The borderless, above-everything window that shows StandBy on one display.
@MainActor
final class OverlayController {
    private(set) var isVisible = false
    private(set) var displayID: CGDirectDisplayID = 0
    /// True while the mouse button is held inside the overlay (a click-drag
    /// swipe), so that drag isn't mistaken for a window being dragged in.
    private(set) var pressInside = false

    var onWake: (() -> Void)?

    private let nav: StandbyNavigator
    private let store: ConfigStore
    private let environment: (OverlayRootView) -> AnyView
    private var panel: OverlayPanel?
    private var container: NSView?
    private var host: NSView?
    private var monitor: Any?
    private var previousApp: NSRunningApplication?
    private var fadeToken = 0

    /// `environment` adds the data sources the StandBy views read.
    init(store: ConfigStore, nav: StandbyNavigator, environment: @escaping (OverlayRootView) -> AnyView) {
        self.store = store
        self.nav = nav
        self.environment = environment
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
        // Built up front so the first appearance doesn't wait on window setup.
        panel = makePanel()
    }

    func show(on screen: NSScreen, displayID: CGDirectDisplayID, takeFocus: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        self.displayID = displayID
        fadeToken += 1
        nav.isActive = true
        panel.allowsKey = takeFocus
        panel.setFrame(screen.frame, display: true)

        let entering = !isVisible
        isVisible = true
        if entering {
            panel.alphaValue = 0
            host?.alphaValue = 0
        }
        panel.orderFrontRegardless()
        if takeFocus {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != getpid() { previousApp = front }
            NSApp.activate()
            panel.makeKey()
        }
        guard entering else {
            panel.alphaValue = 1
            host?.alphaValue = 1
            return
        }
        // The screen eases down to black, then StandBy settles in from slightly
        // smaller. Everything runs in Core Animation, so it stays smooth even
        // while SwiftUI builds the first frame.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
            panel.animator().alphaValue = 1
        }
        animateContent(visible: true, delay: 0.5)
    }

    func move(to screen: NSScreen, displayID: CGDirectDisplayID) {
        guard let panel, isVisible else { return }
        self.displayID = displayID
        panel.setFrame(screen.frame, display: true)
    }

    func hide(animated: Bool = true) {
        guard let panel, isVisible else { return }
        isVisible = false
        pressInside = false
        fadeToken += 1
        let token = fadeToken
        let finish = { [weak self] in
            guard let self, self.fadeToken == token else { return }
            panel.orderOut(nil)
            self.nav.isActive = false
            self.container?.layer?.removeAllAnimations()
            self.container?.layer?.sublayerTransform = CATransform3DIdentity
            self.host?.layer?.removeAllAnimations()
            self.host?.alphaValue = 0
        }
        if animated {
            // StandBy drifts toward you as it dissolves, then the black lifts.
            animateContent(visible: false, delay: 0)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.65
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.2, 1)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { finish() }
            })
        } else {
            finish()
        }
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

    private func animateContent(visible: Bool, delay: CFTimeInterval) {
        guard let container, let containerLayer = container.layer, let host, let hostLayer = host.layer else { return }
        let bounds = container.bounds
        func scaled(_ s: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
            t = CATransform3DScale(t, s, s, 1)
            return CATransform3DTranslate(t, -bounds.midX, -bounds.midY, 0)
        }
        let begin = CACurrentMediaTime() + delay

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = visible ? 0 : 1
        fade.toValue = visible ? 1 : 0
        fade.duration = visible ? 0.9 : 0.4
        fade.timingFunction = visible
            ? CAMediaTimingFunction(controlPoints: 0.3, 0.1, 0.3, 1)
            : CAMediaTimingFunction(controlPoints: 0.4, 0, 0.8, 0.6)
        fade.beginTime = begin
        fade.fillMode = .backwards
        host.alphaValue = visible ? 1 : 0
        hostLayer.add(fade, forKey: "standby.fade")

        let zoom = CABasicAnimation(keyPath: "sublayerTransform")
        let from = visible ? scaled(0.93) : CATransform3DIdentity
        let to = visible ? CATransform3DIdentity : scaled(1.04)
        zoom.fromValue = NSValue(caTransform3D: from)
        zoom.toValue = NSValue(caTransform3D: to)
        zoom.duration = visible ? 1.4 : 0.5
        zoom.timingFunction = visible
            ? CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            : CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
        zoom.beginTime = begin
        zoom.fillMode = .backwards
        containerLayer.sublayerTransform = to
        containerLayer.add(zoom, forKey: "standby.zoom")
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: NSScreen.main?.frame ?? .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none

        let container = NSView(frame: panel.contentLayoutRect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        let root = OverlayRootView(store: store, nav: nav) { [weak self] in self?.onWake?() }
        let host = FirstMouseHostingView(rootView: environment(root))
        host.wantsLayer = true
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.alphaValue = 0
        container.addSubview(host)
        panel.contentView = container
        self.container = container
        self.host = host
        return panel
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard isVisible, let panel, event.window === panel else { return false }
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
