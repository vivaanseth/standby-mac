import AppKit
import Combine
import SwiftUI

/// Commands another process can send to the running app.
enum StandbyCommand: String, CaseIterable {
    case show, hide, toggle

    static let notification = Notification.Name("local.standby.mac.command")

    func post() {
        DistributedNotificationCenter.default().postNotificationName(Self.notification, object: rawValue, userInfo: nil, deliverImmediately: true)
    }
}

/// Watches input, decides when the built-in display counts as unused, and
/// shows or dismisses StandBy.
///
/// With an external display, the built-in display is "in use" when the pointer
/// moves, clicks, or scrolls on it, or when you type into a window that sits on
/// it. Without one, it falls back to whole-system idle time, like a screen saver.
@MainActor
final class StandbyController: ObservableObject {
    @Published private(set) var statusText = ""
    @Published private(set) var pausedUntil: Date?

    let store: ConfigStore
    let nav: StandbyNavigator
    let overlay: OverlayController
    let companion: CompanionController
    let weather: WeatherService
    let calendar: CalendarService
    let photos: PhotoRotator
    let power: PowerService

    var isShowing: Bool { overlay.isVisible || companion.isVisible }

    private let tickInterval: TimeInterval = 0.25
    private var timer: Timer?
    private var lastTick = Date()
    private var lastPointer: CGPoint?
    private var lastBuiltInActivity = Date()
    private var wakeGraceUntil = Date.distantPast
    private var pointerTravel: CGFloat = 0
    private var assertionCheck: (date: Date, blocked: Bool)?
    private var shownMode: StandbyMode?
    private var shownWithoutBuiltIn = false
    private var shownAt = Date()
    private var lastMinute = 0
    private var lastLoadSample = Date.distantPast
    private var companionGraceUntil = Date.distantPast
    private var companionTravel: CGFloat = 0
    /// Input only wakes the external display once this is set: after you've
    /// let go of the mouse and keyboard for a moment since it appeared.
    private var companionArmed = false
    private var companionWakeTravel: CGFloat = 30
    private var anyAssertionCheck: (date: Date, blocked: Bool)?
    private var lastStatusUpdate = Date.distantPast
    private let awake = DisplayAwakeAssertion()
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    init(store: ConfigStore, nav: StandbyNavigator, weather: WeatherService, calendar: CalendarService, photos: PhotoRotator, power: PowerService) {
        self.store = store
        self.nav = nav
        self.weather = weather
        self.calendar = calendar
        self.photos = photos
        self.power = power
        overlay = OverlayController(store: store, nav: nav) { root in
            AnyView(root
                .environmentObject(weather)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(power))
        }
        companion = CompanionController(store: store) { root in
            AnyView(root
                .environmentObject(weather)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(power))
        }
        overlay.onWake = { [weak self] in self?.dismiss() }
        nav.onPhotoStep = { [weak photos] delta in photos?.step(delta) }
    }

    func start() {
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetIdle() }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissAll(animated: false) }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(animated: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: StandbyCommand.notification, object: nil, queue: .main) { [weak self] note in
            let command = (note.object as? String).flatMap(StandbyCommand.init(rawValue:))
            MainActor.assumeIsolated {
                switch command {
                case .show: if self?.isShowing == false { self?.startNow() }
                case .hide: self?.dismissAll()
                case .toggle: self?.toggle()
                case nil: break
                }
            }
        })

        store.$config
            .sink { [weak self] config in self?.configChanged(config) }
            .store(in: &cancellables)
    }

    // MARK: Commands

    /// Starts StandBy everywhere at once: the built-in display (or the main
    /// display with the lid closed) and, if enabled, the external displays.
    func startNow() {
        if let ctx = DisplayLocator.current() {
            shownWithoutBuiltIn = false
            show(ctx, manual: true)
        } else {
            // Lid closed: show on the main display instead.
            shownWithoutBuiltIn = true
            show(DisplayLocator.mainDisplay(), manual: true)
        }
        let config = store.config
        guard config.externalEnabled else { return }
        let externals = DisplayLocator.externalDisplays().filter {
            CGDisplayIsAsleep($0) == 0 && !(overlay.isVisible && $0 == overlay.displayID)
        }
        if !externals.isEmpty { showCompanion(on: externals, config: config, manual: true) }
    }

    func toggle() {
        isShowing ? dismissAll() : startNow()
    }

    func pause(for duration: TimeInterval?) {
        pausedUntil = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        updateStatus(force: true)
    }

    func resume() {
        pausedUntil = nil
        resetIdle()
        updateStatus(force: true)
    }

    /// Takes StandBy down everywhere: built-in and external displays.
    func dismissAll(animated: Bool = true) {
        dismiss(animated: animated)
        hideCompanion(animated: animated)
    }

    func dismiss(animated: Bool = true) {
        guard overlay.isVisible else { return }
        overlay.hide(animated: animated)
        syncAwake()
        if !companion.isVisible { photos.stop() }
        shownMode = nil
        shownWithoutBuiltIn = false
        resetIdle()
        var config = store.config
        config.lastPage = nav.currentPage
        let styles = config.enabledClockStyles
        config.lastClockStyle = styles[min(nav.clockIndex, styles.count - 1)]
        store.config = config
        updateStatus(force: true)
    }

    // MARK: Tick

    private func tick() {
        let now = Date()
        let dt = min(max(now.timeIntervalSince(lastTick), tickInterval), 2) + 0.05
        lastTick = now
        let pointer = InputActivity.pointer()
        let previous = lastPointer ?? pointer
        lastPointer = pointer
        let movement = hypot(pointer.x - previous.x, pointer.y - previous.y)
        let config = store.config

        if let until = pausedUntil, until <= now { pausedUntil = nil }

        companionTick(now: now, dt: dt, movement: movement, config: config)

        var located = DisplayLocator.current()
        if located == nil, overlay.isVisible, shownWithoutBuiltIn {
            located = DisplayLocator.mainDisplay()
        }
        guard let ctx = located,
              CGDisplayIsAsleep(ctx.displayID) == 0,
              !InputActivity.isScreenLocked() else {
            // Lid closed, display asleep, or locked.
            if overlay.isVisible { dismiss(animated: false) }
            lastBuiltInActivity = now
            updateStatus()
            return
        }

        if overlay.isVisible {
            visibleTick(ctx, pointer: pointer, previous: previous, movement: movement, dt: dt, now: now)
            updateStatus()
            return
        }

        let idle: TimeInterval
        switch ctx.mode {
        case .solo:
            idle = InputActivity.secondsSinceAnyInput()
        case .dual:
            if builtInActivity(ctx, pointer: pointer, previous: previous, movement: movement, dt: dt) {
                lastBuiltInActivity = now
            }
            idle = now.timeIntervalSince(lastBuiltInActivity)
        }
        updateStatus(ctx: ctx, idle: idle)

        guard config.enabled, pausedUntil == nil else { return }
        let modeEnabled = ctx.mode == .solo ? config.soloEnabled : config.dualEnabled
        let delay = ctx.mode == .solo ? config.soloIdleDelay : config.dualIdleDelay
        guard modeEnabled, idle >= delay else { return }
        if config.onlyWhenCharging && !PowerSource.read().onAC { return }
        if config.respectDisplaySleepAssertions && blockedByAssertions(ctx, now: now) { return }
        show(ctx, manual: false)
    }

    private func builtInActivity(_ ctx: DisplayContext, pointer: CGPoint, previous: CGPoint, movement: CGFloat, dt: TimeInterval) -> Bool {
        let onBuiltIn = ctx.bounds.contains(pointer)
        if movement > 0.5 && (onBuiltIn || ctx.bounds.contains(previous)) { return true }
        if onBuiltIn {
            for type in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel] where InputActivity.happened(type, within: dt) {
                return true
            }
        }
        if InputActivity.happened(.keyDown, within: dt),
           let frame = WindowInspector.frontmostWindowFrame(),
           WindowInspector.overlap(frame, ctx.bounds) > 0.5 {
            return true
        }
        return false
    }

    private func visibleTick(_ ctx: DisplayContext, pointer: CGPoint, previous: CGPoint, movement: CGFloat, dt: TimeInterval, now: Date) {
        let config = store.config
        if ctx.displayID != overlay.displayID, let screen = DisplayLocator.screen(for: ctx.displayID) {
            overlay.move(to: screen, displayID: ctx.displayID)
        }
        refreshLiveData(now: now)
        if config.uses(.macStats), now.timeIntervalSince(lastLoadSample) >= 2 {
            lastLoadSample = now
            power.refreshLoad()
        }
        guard now >= wakeGraceUntil else { return }

        let onDisplay = ctx.bounds.contains(pointer)
        let wakeOnPointer = ctx.mode == .solo ? config.wakeOnPointerSolo : config.wakeOnPointerDual
        if wakeOnPointer && onDisplay && movement > 0 && !overlay.pressInside {
            pointerTravel += movement
            if pointerTravel > (ctx.mode == .solo ? 30 : 60) { return dismiss() }
        } else if !onDisplay {
            pointerTravel = 0
        }

        switch ctx.mode {
        case .dual:
            // Dragging a window (or file) onto the built-in display.
            if onDisplay && !overlay.pressInside && InputActivity.happened(.leftMouseDragged, within: dt) {
                return dismiss()
            }
            // Typing into a window that lives on the built-in display, e.g.
            // after Command-Tab.
            if !NSApp.isActive, InputActivity.happened(.keyDown, within: dt),
               let frame = WindowInspector.frontmostWindowFrame(),
               WindowInspector.overlap(frame, ctx.bounds) > 0.5 {
                return dismiss()
            }
        case .solo:
            // Normally keys arrive at the overlay itself; this covers the case
            // where another app grabbed focus.
            if !NSApp.isActive && InputActivity.happened(.keyDown, within: dt) {
                return dismiss()
            }
        }
    }

    // MARK: Show

    private func show(_ ctx: DisplayContext, manual: Bool) {
        guard let screen = DisplayLocator.screen(for: ctx.displayID) else { return }
        let config = store.config
        if !overlay.isVisible {
            nav.prepareForShow(config)
            shownAt = Date()
            lastMinute = 0
            refreshLiveData(now: Date(), force: true)
            if config.uses(.photo) || config.showPhotos {
                photos.configure(folder: config.photoFolder, shuffle: config.photoShuffle)
                photos.start(interval: config.photoInterval)
            }
        }
        shownMode = ctx.mode
        pointerTravel = 0
        wakeGraceUntil = Date().addingTimeInterval(manual ? 1.5 : 0.5)
        overlay.show(on: screen, displayID: ctx.displayID, takeFocus: ctx.mode == .solo)
        syncAwake()
        if ctx.mode == .solo || ctx.bounds.contains(InputActivity.pointer()) {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        updateStatus(force: true)
    }

    private func refreshLiveData(now: Date, force: Bool = false) {
        let minute = Int(now.timeIntervalSince1970 / 60)
        guard force || minute != lastMinute else { return }
        lastMinute = minute
        let config = store.config
        power.refresh()
        weather.refresh(config: config)
        if config.uses(.upNext) { calendar.refresh() }
        if !force, config.smartRotate,
           now.timeIntervalSince(nav.lastInteraction) > 60,
           Int(now.timeIntervalSince(shownAt) / 60) % max(config.smartRotateMinutes, 1) == 0 {
            nav.rotateStacks()
        }
        if !force, config.smartRotate, companion.isVisible, minute % max(config.smartRotateMinutes, 1) == 0 {
            companion.nav.rotateStacks()
        }
    }

    // MARK: External displays

    /// External displays get their own screen once nothing at all is being
    /// used: no input anywhere for `externalIdleDelay`. With the lid closed
    /// that makes them a screen saver. Any input takes them down again; the
    /// built-in display keeps its own StandBy until it is used itself.
    private func companionTick(now: Date, dt: TimeInterval, movement: CGFloat, config: StandbyConfig) {
        let builtIn = DisplayLocator.current()
        let externals = DisplayLocator.externalDisplays().filter {
            CGDisplayIsAsleep($0) == 0 && !(overlay.isVisible && $0 == overlay.displayID)
        }
        let locked = InputActivity.isScreenLocked()

        if companion.isVisible {
            if externals.isEmpty || locked || !config.enabled { return hideCompanion(animated: !locked) }
            if externals != companion.displayIDs { companion.show(on: externals, config: config) }
            refreshLiveData(now: now)
            if config.uses(.macStats), config.externalStyle == .widgets, now.timeIntervalSince(lastLoadSample) >= 2 {
                lastLoadSample = now
                power.refreshLoad()
            }
            guard now >= companionGraceUntil else { return }
            if !companionArmed {
                // Still moving from starting it by hand: wait until you settle.
                if InputActivity.secondsSinceAnyInput() >= 0.8 { companionArmed = true }
                return
            }
            companionTravel += movement
            let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            if companionTravel > companionWakeTravel || types.contains(where: { InputActivity.happened($0, within: dt) }) {
                hideCompanion()
            }
            return
        }

        guard config.enabled, config.externalEnabled, pausedUntil == nil, !externals.isEmpty, !locked else { return }
        if builtIn == nil && !config.clamshellEnabled { return }
        guard InputActivity.secondsSinceAnyInput() >= config.externalIdleDelay else { return }
        if config.onlyWhenCharging && !PowerSource.read().onAC { return }
        if config.respectDisplaySleepAssertions && anyDisplayAssertion(now: now) { return }
        showCompanion(on: externals, config: config)
    }

    private func showCompanion(on ids: [CGDirectDisplayID], config: StandbyConfig, manual: Bool = false) {
        let wasVisible = companion.isVisible
        companion.show(on: ids, config: config)
        // A manual start (menu or shortcut) gets longer, so the hand that
        // just triggered it doesn't immediately take it down again.
        companionGraceUntil = Date().addingTimeInterval(manual ? 1.5 : 0.6)
        companionTravel = 0
        if !wasVisible {
            companionArmed = false
            companionWakeTravel = manual ? 80 : 30
        }
        if !wasVisible {
            refreshLiveData(now: Date(), force: !overlay.isVisible)
            let wantsPhotos = config.externalStyle == .photos || (config.externalStyle == .widgets && config.uses(.photo))
            if wantsPhotos && !overlay.isVisible {
                photos.configure(folder: config.photoFolder, shuffle: config.photoShuffle)
                photos.start(interval: config.photoInterval)
            }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        syncAwake()
        updateStatus(force: true)
    }

    private func hideCompanion(animated: Bool = true) {
        guard companion.isVisible else { return }
        companion.hide(animated: animated)
        if !overlay.isVisible { photos.stop() }
        syncAwake()
        updateStatus(force: true)
    }

    private func anyDisplayAssertion(now: Date) -> Bool {
        if let c = anyAssertionCheck, now.timeIntervalSince(c.date) < 5 { return c.blocked }
        let blocked = !PowerSource.displaySleepAssertionPIDs().isEmpty
        anyAssertionCheck = (now, blocked)
        return blocked
    }

    /// Holds the keep-awake assertion while anything is showing, if enabled.
    private func syncAwake() {
        let showing = overlay.isVisible || companion.isVisible
        showing && store.config.keepDisplayAwake ? awake.acquire() : awake.release()
    }

    // MARK: Events

    private func resetIdle() {
        lastBuiltInActivity = Date()
        lastPointer = nil
    }

    private func screensChanged() {
        resetIdle()
        guard overlay.isVisible else { return }
        if let ctx = DisplayLocator.current(), let screen = DisplayLocator.screen(for: ctx.displayID) {
            overlay.move(to: screen, displayID: ctx.displayID)
        }
    }

    private var lastConfig: StandbyConfig?

    private func configChanged(_ config: StandbyConfig) {
        defer { lastConfig = config }
        nav.apply(config)
        let old = lastConfig
        if old?.weatherPlace != config.weatherPlace || old?.temperatureUnit != config.temperatureUnit {
            weather.refresh(config: config, force: true)
        }
        if config.uses(.upNext) && calendar.status == .notDetermined {
            calendar.requestAccess()
        }
        if old?.photoFolder != config.photoFolder || old?.photoShuffle != config.photoShuffle {
            if old != nil || overlay.isVisible { photos.configure(folder: config.photoFolder, shuffle: config.photoShuffle) }
        }
        if overlay.isVisible || companion.isVisible {
            if old?.photoInterval != config.photoInterval { photos.start(interval: config.photoInterval) }
        }
        if old?.keepDisplayAwake != config.keepDisplayAwake { syncAwake() }
        if !config.enabled { dismissAll() }
        updateStatus(force: true)
    }

    private func blockedByAssertions(_ ctx: DisplayContext, now: Date) -> Bool {
        if let c = assertionCheck, now.timeIntervalSince(c.date) < 5 { return c.blocked }
        let pids = PowerSource.displaySleepAssertionPIDs()
        let blocked: Bool
        switch ctx.mode {
        case .solo: blocked = !pids.isEmpty
        case .dual: blocked = pids.contains { WindowInspector.hasWindow(pid: $0, mostlyOn: ctx.bounds) }
        }
        assertionCheck = (now, blocked)
        return blocked
    }

    // MARK: Status

    private func updateStatus(ctx: DisplayContext? = nil, idle: TimeInterval? = nil, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastStatusUpdate) >= 1 else { return }
        lastStatusUpdate = now
        let config = store.config
        let text: String
        if overlay.isVisible && companion.isVisible {
            text = "Showing on all displays"
        } else if overlay.isVisible {
            text = shownMode == .dual ? "Showing on the built-in display" : "Showing"
        } else if companion.isVisible {
            text = "Showing on the external display"
        } else if !config.enabled {
            text = "Standby is off"
        } else if let until = pausedUntil {
            text = until == .distantFuture ? "Paused" : "Paused until \(TimeText.format(until, "jmm"))"
        } else if let ctx = ctx ?? DisplayLocator.current() {
            let idle = idle ?? 0
            switch ctx.mode {
            case .dual where !config.dualEnabled:
                text = "Off while an external display is connected"
            case .solo where !config.soloEnabled:
                text = "Off when the built-in display is the only display"
            case .dual:
                text = "Built-in display unused for \(Self.duration(idle)) of \(Self.duration(config.dualIdleDelay))"
            case .solo:
                text = "Idle for \(Self.duration(idle)) of \(Self.duration(config.soloIdleDelay))"
            }
        } else {
            text = "Built-in display is closed or asleep"
        }
        if text != statusText { statusText = text }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
