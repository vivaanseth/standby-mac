import Foundation
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

    /// Processes currently asking the system to keep the display on — video
    /// players, video calls, presentations.
    static func displaySleepAssertionPIDs() -> Set<pid_t> {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let dict = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        let types: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        var pids = Set<pid_t>()
        for (pid, assertions) in dict where assertions.contains(where: { types.contains($0["AssertType"] as? String ?? "") }) {
            pids.insert(pid.int32Value)
        }
        pids.remove(getpid())
        return pids
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
