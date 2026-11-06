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

/// A borderless, above-everything window covering one display, with the
/// StandBy entrance and exit: the screen eases to black, then the content
/// settles in from slightly smaller; on the way out it drifts forward and
/// dissolves. Everything runs in Core Animation, so it stays smooth even while
/// SwiftUI builds the first frame.
@MainActor
final class TransitionWindow {
    /// Leaves these windows out of screenshots and screen recordings, so a
    /// capture shows what's really on the screen underneath.
    static var hiddenFromCapture = true

    let panel: OverlayPanel
    private(set) var isVisible = false
    /// Called once the exit animation has finished and the window is gone.
    var onHidden: (() -> Void)?

    private let container: NSView
    private let host: NSView
    private var fadeToken = 0

    init(content: AnyView) {
        panel = OverlayPanel(contentRect: NSScreen.main?.frame ?? .zero,
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

        container = NSView(frame: panel.contentLayoutRect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        let host = FirstMouseHostingView(rootView: content)
        host.wantsLayer = true
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.alphaValue = 0
        container.addSubview(host)
        panel.contentView = container
        self.host = host
    }

    func present(on frame: NSRect) {
        fadeToken += 1
        panel.sharingType = Self.hiddenFromCapture ? .none : .readOnly
        panel.ignoresMouseEvents = false
        panel.setFrame(frame, display: true)
        let entering = !isVisible
        isVisible = true
        if entering {
            panel.alphaValue = 0
            host.alphaValue = 0
        }
        panel.orderFrontRegardless()
        guard entering else {
            panel.alphaValue = 1
            host.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
            panel.animator().alphaValue = 1
        }
        animateContent(visible: true, delay: 0.5)
    }

    func setFrame(_ frame: NSRect) {
        guard isVisible else { return }
        panel.setFrame(frame, display: true)
    }

    func dismiss(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        fadeToken += 1
        let token = fadeToken
        let finish = { [weak self] in
            guard let self, self.fadeToken == token else { return }
            self.panel.orderOut(nil)
            self.container.layer?.removeAllAnimations()
            self.container.layer?.sublayerTransform = CATransform3DIdentity
            self.host.layer?.removeAllAnimations()
            self.host.alphaValue = 0
            self.onHidden?()
        }
        guard animated else { return finish() }
        // Clicks go straight through to whatever is underneath while it fades.
        panel.ignoresMouseEvents = true
        animateContent(visible: false, delay: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.65
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.2, 1)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }

    private func animateContent(visible: Bool, delay: CFTimeInterval) {
        guard let containerLayer = container.layer, let hostLayer = host.layer else { return }
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
}
