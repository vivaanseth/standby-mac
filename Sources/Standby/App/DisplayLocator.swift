import AppKit
import CoreGraphics

enum StandbyMode {
    /// The built-in display plus at least one independent external display:
    /// StandBy covers only the built-in one.
    case dual
    /// The built-in display is the only one (or is mirrored): StandBy acts
    /// like a screen saver.
    case solo
}

struct DisplayContext: Equatable {
    /// The display StandBy draws on.
    var displayID: CGDirectDisplayID
    /// Its bounds in global CoreGraphics coordinates (origin top-left).
    var bounds: CGRect
    var mode: StandbyMode
}

enum DisplayLocator {
    /// nil when the built-in display is off — lid closed, or clamshell mode.
    static func current() -> DisplayContext? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        guard let builtIn = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }

        let master = CGDisplayMirrorsDisplay(builtIn)
        let target = master != kCGNullDirectDisplay ? master : builtIn
        let independentOthers = ids.filter { $0 != builtIn && CGDisplayIsInMirrorSet($0) == 0 }
        let mirrored = CGDisplayIsInMirrorSet(builtIn) != 0
        let mode: StandbyMode = (mirrored || independentOthers.isEmpty) ? .solo : .dual
        return DisplayContext(displayID: target, bounds: CGDisplayBounds(target), mode: mode)
    }

    /// Used for a manual start when the built-in display is closed.
    static func mainDisplay() -> DisplayContext {
        let id = CGMainDisplayID()
        return DisplayContext(displayID: id, bounds: CGDisplayBounds(id), mode: .solo)
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Window geometry from the window server. Bounds and owner are readable
/// without Screen Recording permission.
enum WindowInspector {
    static func frontmostWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
        return windows(of: app.processIdentifier).first
    }

    static func hasWindow(pid: pid_t, mostlyOn bounds: CGRect) -> Bool {
        windows(of: pid).contains { overlap($0, bounds) > 0.5 }
    }

    static func overlap(_ frame: CGRect, _ bounds: CGRect) -> CGFloat {
        let i = frame.intersection(bounds)
        guard !i.isNull, frame.width * frame.height > 0 else { return 0 }
        return (i.width * i.height) / (frame.width * frame.height)
    }

    /// On-screen, normal-level windows of a process, front to back.
    private static func windows(of pid: pid_t) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width > 40, rect.height > 40 else { return nil }
            return rect
        }
    }
}

enum InputActivity {
    private static let anyInput = CGEventType(rawValue: ~0)!

    static func secondsSinceAnyInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    static func happened(_ type: CGEventType, within seconds: TimeInterval) -> Bool {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type) < seconds
    }

    static func pointer() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if (dict["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
        if let onConsole = dict["kCGSessionOnConsoleKey"] as? Bool, !onConsole { return true }
        return false
    }
}
