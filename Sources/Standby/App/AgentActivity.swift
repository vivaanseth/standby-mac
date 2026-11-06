import AppKit

/// Notices an AI agent or other automation using the screen, with no special
/// permissions, from three signals:
///
/// - ScreenCaptureKit: every grab goes through the system's `replayd` service,
///   which uses no CPU at all otherwise.
/// - The `screencapture` command, which doesn't go through `replayd`.
/// - Synthetic mouse input: each mouse event records the process that posted
///   it, and hardware events have none. (Watching the keyboard this way would
///   need a permission, but agents take screenshots between keystrokes anyway.)
///
/// Older in-process capture APIs leave no trace, but those screenshots still
/// see past Standby because its windows are excluded from capture.
final class AgentActivity {
    private var replayd: pid_t = 0
    private var lastCPU: UInt64?
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
        return captureHappened() || syntheticInputSeen
    }

    private func inspect(_ event: NSEvent) {
        guard !syntheticInputSeen, let field = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) else { return }
        let poster = pid_t(truncatingIfNeeded: field)
        if poster > 0, poster != getpid(), !PowerSource.isSystemProcess(poster) {
            syntheticInputSeen = true
        }
    }

    private func captureHappened() -> Bool {
        let scan = scanProcesses()
        if scan.replayd != replayd {
            // replayd starting up counts as activity, unless it was already
            // there when Standby launched.
            let started = scan.replayd != 0 && lastCPU != nil
            replayd = scan.replayd
            lastCPU = replayd == 0 ? lastCPU : Self.cpuTime(replayd)
            return scan.screencapture || started
        }
        guard replayd != 0, let cpu = Self.cpuTime(replayd) else {
            if lastCPU == nil { lastCPU = 0 }
            return scan.screencapture
        }
        defer { lastCPU = cpu }
        return scan.screencapture || cpu > (lastCPU ?? cpu) + 500_000 // half a millisecond
    }

    /// One sysctl for the whole process table, far cheaper than asking each
    /// process for its name.
    private func scanProcesses() -> (replayd: pid_t, screencapture: Bool) {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else { return (replayd, false) }
        var found: pid_t = 0
        var capturing = false
        for i in 0..<(size / MemoryLayout<kinfo_proc>.stride) {
            let name = withUnsafeBytes(of: &processes[i].kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if name == "replayd" { found = processes[i].kp_proc.p_pid }
            if name == "screencapture" { capturing = true }
        }
        return (found, capturing)
    }

    private static func cpuTime(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? info.ri_user_time + info.ri_system_time : nil
    }
}
