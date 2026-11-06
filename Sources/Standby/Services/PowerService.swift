import AppKit
import IOKit.ps
import IOKit.pwr_mgt

struct BatteryInfo: Equatable {
    var hasBattery: Bool
    var level: Double
    var isCharging: Bool
    var onAC: Bool
}

enum PowerSource {
    static func read() -> BatteryInfo {
        var result = BatteryInfo(hasBattery: false, level: 1, isCharging: false, onAC: true)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return result }
        if let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            result.onAC = (providing as String) == "AC Power"
        }
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return result }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc["Type"] as? String) == "InternalBattery" else { continue }
            let current = (desc["Current Capacity"] as? NSNumber)?.doubleValue ?? 0
            let max = (desc["Max Capacity"] as? NSNumber)?.doubleValue ?? 100
            result.hasBattery = true
            result.level = max > 0 ? min(current / max, 1) : 0
            result.isCharging = (desc["Is Charging"] as? NSNumber)?.boolValue ?? false
        }
        return result
    }

    struct KeepAwakeHolder {
        var pid: pid_t
        var name: String
        /// Keeping the display on (a video, a call, a presentation), rather
        /// than only the Mac.
        var keepsDisplayOn: Bool
    }

    /// Apps deliberately keeping the Mac or its display awake: caffeinate,
    /// Amphetamine, an app doing long-running work, a video. Playing audio
    /// doesn't count, nor do the system's own background services.
    static func keepAwakeHolders() -> [KeepAwakeHolder] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let dict = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        let systemTypes: Set<String> = ["PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep"]
        var holders: [KeepAwakeHolder] = []
        for (number, assertions) in dict {
            let pid = number.int32Value
            guard pid != getpid(), !isSystemProcess(pid) else { continue }
            var display = false, system = false
            for assertion in assertions {
                let type = assertion["AssertType"] as? String ?? ""
                let name = (assertion["AssertName"] as? String ?? "").lowercased()
                if name.contains("audio") { continue }
                if displayTypes.contains(type) { display = true }
                if systemTypes.contains(type), !name.contains("video") { system = true }
            }
            guard display || system else { continue }
            // An app that also keeps the Mac itself awake isn't just showing
            // a video, so it isn't tied to the display its window is on.
            holders.append(KeepAwakeHolder(pid: pid, name: processName(pid), keepsDisplayOn: display && !system))
        }
        return holders
    }

    static func isSystemProcess(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(cString: buffer)
        return ["/usr/libexec/", "/usr/sbin/", "/System/"].contains { path.hasPrefix($0) }
    }

    private static func processName(_ pid: pid_t) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, 256)
        return String(cString: buffer)
    }
}

/// Holds a display-sleep assertion while StandBy is up, if the user wants it.
final class DisplayAwakeAssertion {
    private var id: IOPMAssertionID = 0

    var isHeld: Bool { id != 0 }

    func acquire() {
        guard id == 0 else { return }
        IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Standby is showing" as CFString,
                                    &id)
    }

    func release() {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
}

/// CPU and memory load from the Mach host statistics (no permissions needed).
enum SystemLoad {
    struct CPUTicks { var busy: UInt64; var total: UInt64 }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Fraction of physical memory in use (app, wired, and compressed).
    static func memoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = Double(pages * UInt64(vm_kernel_page_size))
        return min(used / Double(ProcessInfo.processInfo.physicalMemory), 1)
    }
}

@MainActor
final class PowerService: ObservableObject {
    @Published private(set) var battery = PowerSource.read()
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    private var lastTicks: SystemLoad.CPUTicks?

    /// Samples CPU since the previous call; call every couple of seconds.
    func refreshLoad() {
        if let ticks = SystemLoad.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }
        memory = SystemLoad.memoryUsed()
    }

    func setPreviewLoad(cpu: Double, memory: Double) {
        self.cpu = cpu
        self.memory = memory
    }

    func refresh() {
        let latest = PowerSource.read()
        if latest != battery { battery = latest }
    }

    func setPreview(_ info: BatteryInfo) { battery = info }
}
