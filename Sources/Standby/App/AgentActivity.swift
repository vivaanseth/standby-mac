import AppKit

/// Notices an AI agent or other automation using the screen, with no special
/// permissions, from two signals:
///
/// - The `screencapture` command running.
/// - Synthetic mouse input: each mouse event records the process that posted
///   it, and hardware events have none. (Watching the keyboard this way would
///   need a permission.)
///
/// ScreenCaptureKit grabs can't be told apart from background noise: `replayd`
/// has idle CPU blips as large as a real grab. Those screenshots still see past
/// Standby, because its windows are excluded from capture.
final class AgentActivity {
    private var processes = [kinfo_proc](repeating: kinfo_proc(), count: 2048)
    private var syntheticInputSeen = false
    private var monitors: [Any] = []

    init() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel]
        // The global monitor misses events aimed at Standby's own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.inspect($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in
            self?.inspect($0)
            return $0
        }) {
            monitors.append(local)
        }
    }

    /// Call once per tick. True if anything was seen since the last call.
    func detected() -> Bool {
        defer { syntheticInputSeen = false }
        return screencaptureRunning() || syntheticInputSeen
    }

    private func inspect(_ event: NSEvent) {
        guard !syntheticInputSeen, let field = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) else { return }
        let poster = pid_t(truncatingIfNeeded: field)
        if poster > 0, poster != getpid(), !PowerSource.isSystemProcess(poster) {
            syntheticInputSeen = true
        }
    }

    /// One sysctl for the whole process table, far cheaper than asking each
    /// process for its name.
    private func screencaptureRunning() -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else { return false }
        for i in 0..<(size / MemoryLayout<kinfo_proc>.stride) {
            let name = withUnsafeBytes(of: &processes[i].kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if name == "screencapture" { return true }
        }
        return false
    }
}
