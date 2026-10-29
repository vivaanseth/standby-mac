import AppKit
import SwiftUI

/// Which page, widget, and clock face is showing, plus the live state of a
/// swipe in progress. Shared by drags, trackpad scrolls, and the keyboard.
@MainActor
final class StandbyNavigator: ObservableObject {
    enum VerticalTarget: Equatable { case stack(Int), clock, photos }
    private enum Axis { case horizontal, vertical }

    @Published var page = 0
    /// The widget showing in each stack.
    @Published var stackIndices = Array(repeating: 0, count: StandbyConfig.maxStacks)
    @Published var clockIndex = 0
    @Published var hOffset: CGFloat = 0
    @Published var vOffset: CGFloat = 0
    @Published var vTarget: VerticalTarget?
    @Published var lastInteraction = Date.distantPast
    /// Last time anything moved; neighboring pages are only built around then.
    @Published var lastMotion = Date.distantPast
    @Published var isActive = false

    private(set) var pageKinds: [PageKind] = [.widgets, .photos, .clock]
    private var stackCounts = [1, 1]
    private var widgetLayout: WidgetLayout = .grid
    private var clockCount = 1

    var onPhotoStep: ((Int) -> Void)?

    private var axis: Axis?
    private var scrollAccum = CGSize.zero
    private var scrollStart = CGPoint.zero
    private var lastWheelStep = Date.distantPast

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.9)

    var currentPage: PageKind { pageKinds[min(page, pageKinds.count - 1)] }

    func apply(_ config: StandbyConfig) {
        pageKinds = config.visiblePages
        stackCounts = config.visibleStacks.map { max($0.count, 1) }
        widgetLayout = config.widgetLayout
        clockCount = config.enabledClockStyles.count
        page = min(page, pageKinds.count - 1)
        clockIndex = min(clockIndex, clockCount - 1)
    }

    func prepareForShow(_ config: StandbyConfig) {
        apply(config)
        let start: PageKind
        switch config.startPage {
        case .lastUsed: start = config.lastPage
        case .widgets: start = .widgets
        case .photos: start = .photos
        case .clock: start = .clock
        }
        page = pageKinds.firstIndex(of: start) ?? 0
        clockIndex = config.enabledClockStyles.firstIndex(of: config.lastClockStyle) ?? 0
        hOffset = 0
        vOffset = 0
        vTarget = nil
        axis = nil
    }

    // MARK: Paging

    func stepPage(_ delta: Int) {
        lastInteraction = Date()
        lastMotion = Date()
        withAnimation(spring) {
            page = clamp(page + delta, pageKinds.count)
            hOffset = 0
        }
    }

    func stepVertical(_ target: VerticalTarget, _ delta: Int, wrap: Bool = false) {
        lastInteraction = Date()
        lastMotion = Date()
        vTarget = target
        if target == .photos {
            onPhotoStep?(delta)
            withAnimation(spring) { vOffset = 0 }
            return
        }
        withAnimation(spring) {
            switch target {
            case .stack(let i) where i < stackCounts.count && stackCounts[i] > 1:
                // Stacks loop around, like Smart Stacks on iPhone. The index
                // isn't wrapped here; the view takes it modulo the count.
                stackIndices[i] += delta
            case .stack: break
            case .clock: clockIndex = next(clockIndex, delta, clockCount, wrap)
            case .photos: break
            }
            vOffset = 0
        }
    }

    /// Smart Rotate: advance each stack that has more than one widget, one
    /// after another rather than all at once.
    func rotateStacks() {
        guard currentPage == .widgets else { return }
        let rotating = stackCounts.indices.filter { stackCounts[$0] > 1 }
        for (order, i) in rotating.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(order) * 0.6) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, i < self.stackCounts.count else { return }
                    self.lastMotion = Date()
                    self.vTarget = .stack(i)
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.92)) {
                        self.stackIndices[i] += 1
                    }
                }
            }
        }
    }

    // MARK: Gestures

    func dragChanged(translation t: CGSize, start: CGPoint, size: CGSize) {
        lastInteraction = Date()
        lastMotion = Date()
        if axis == nil {
            guard max(abs(t.width), abs(t.height)) > 6 else { return }
            axis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
            if axis == .vertical { vTarget = verticalTarget(at: start, size: size) }
        }
        switch axis {
        case .horizontal:
            hOffset = rubberBand(t.width, atStart: page == 0, atEnd: page >= pageKinds.count - 1)
        case .vertical:
            guard let target = vTarget, target != .photos else { return }
            if case .stack = target {
                vOffset = t.height
            } else {
                let (index, count) = state(for: target)
                vOffset = rubberBand(t.height, atStart: index == 0, atEnd: index >= count - 1)
            }
        case nil:
            break
        }
    }

    func dragEnded(translation t: CGSize, predicted p: CGSize, size: CGSize, isScroll: Bool = false) {
        defer { axis = nil }
        switch axis {
        case .horizontal:
            let threshold = isScroll ? min(size.width * 0.12, 70) : size.width * 0.15
            var delta = 0
            if t.width < -threshold || p.width < -size.width * 0.5 { delta = 1 }
            if t.width > threshold || p.width > size.width * 0.5 { delta = -1 }
            stepPage(delta)
        case .vertical:
            let threshold = isScroll ? min(size.height * 0.08, 45) : size.height * 0.08
            var delta = 0
            if t.height < -threshold || p.height < -size.height * 0.4 { delta = 1 }
            if t.height > threshold || p.height > size.height * 0.4 { delta = -1 }
            if let target = vTarget {
                stepVertical(target, delta)
            }
        case nil:
            withAnimation(spring) {
                hOffset = 0
                vOffset = 0
            }
        }
    }

    func handleScroll(_ event: NSEvent, size: CGSize) {
        lastInteraction = Date()
        // A mouse wheel: no gesture phases, so step once per notch burst.
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            guard Date().timeIntervalSince(lastWheelStep) > 0.35 else { return }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            if abs(dx) > abs(dy), abs(dx) > 0.5 {
                stepPage(dx < 0 ? 1 : -1)
            } else if abs(dy) > 0.5 {
                stepVertical(verticalTarget(at: flipped(event.locationInWindow, size), size: size), dy < 0 ? 1 : -1)
            } else {
                return
            }
            lastWheelStep = Date()
            return
        }
        // Trackpad: follow the fingers, ignore momentum after lift-off.
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            axis = nil
            scrollAccum = .zero
            scrollStart = flipped(event.locationInWindow, size)
        }
        if event.phase.contains(.began) || event.phase.contains(.changed) {
            scrollAccum.width += event.scrollingDeltaX
            scrollAccum.height += event.scrollingDeltaY
            dragChanged(translation: scrollAccum, start: scrollStart, size: size)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            dragEnded(translation: scrollAccum, predicted: scrollAccum, size: size, isScroll: true)
            scrollAccum = .zero
        }
    }

    /// Returns true if the key was a navigation key. Up and down flip the
    /// stack under the pointer.
    func handleKey(_ event: NSEvent, pointer: CGPoint, size: CGSize) -> Bool {
        switch event.keyCode {
        case 123: stepPage(-1)
        case 124: stepPage(1)
        case 125, 126:
            let delta = event.keyCode == 125 ? 1 : -1
            let target: VerticalTarget
            switch currentPage {
            case .widgets: target = verticalTarget(at: pointer, size: size)
            case .photos: target = .photos
            case .clock: target = .clock
            }
            stepVertical(target, delta)
        default:
            return false
        }
        return true
    }

    /// Whether pages beside the current one need to exist (mid-swipe or
    /// mid-transition). Otherwise only the visible page is built, so offscreen
    /// animations don't burn CPU.
    func showsNeighbors(at date: Date) -> Bool {
        hOffset != 0 || vOffset != 0 || date.timeIntervalSince(lastMotion) < 3
    }

    // MARK: Helpers

    private func verticalTarget(at point: CGPoint, size: CGSize) -> VerticalTarget {
        switch currentPage {
        case .widgets:
            // The stack under the point, or the nearest one.
            let frames = WidgetGrid.frames(count: stackCounts.count, layout: widgetLayout, in: size)
            func distance(_ r: CGRect) -> CGFloat { hypot(r.midX - point.x, r.midY - point.y) }
            let nearest = frames.indices.min { distance(frames[$0]) < distance(frames[$1]) } ?? 0
            return .stack(frames.firstIndex { $0.contains(point) } ?? nearest)
        case .photos: return .photos
        case .clock: return .clock
        }
    }

    /// Window coordinates (origin bottom-left) to view coordinates.
    private func flipped(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x, y: size.height - p.y)
    }

    private func state(for target: VerticalTarget) -> (Int, Int) {
        switch target {
        case .stack(let i) where i < stackCounts.count: (((stackIndices[i] % stackCounts[i]) + stackCounts[i]) % stackCounts[i], stackCounts[i])
        case .stack: (0, 1)
        case .clock: (clockIndex, clockCount)
        case .photos: (0, 1)
        }
    }

    private func rubberBand(_ v: CGFloat, atStart: Bool, atEnd: Bool) -> CGFloat {
        (v > 0 && atStart) || (v < 0 && atEnd) ? v * 0.3 : v
    }

    private func clamp(_ i: Int, _ count: Int) -> Int { min(max(i, 0), count - 1) }

    private func next(_ i: Int, _ delta: Int, _ count: Int, _ wrap: Bool) -> Int {
        wrap ? ((i + delta) % count + count) % count : clamp(i + delta, count)
    }
}
