import AppKit
import Combine
import IOKit.ps
import Darwin

@MainActor final class SystemService: ObservableObject {
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var cpu = 0.0
    @Published private(set) var memory = 0.0
    @Published private(set) var freeStorage = "—"
    @Published private(set) var thermal = "Nominal"
    private var previous: host_cpu_load_info?
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?
    var onPowerChanged: ((Bool, Int?) -> Void)?
    var onLowBattery: (() -> Void)?
    private var lowBatteryNotified = false
    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<SystemService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.refreshBattery() }
        }, context)?.takeRetainedValue() {
            powerSource = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        refreshBattery()
    }
    func setVisible(_ visible: Bool) {
        timer?.invalidate(); timer = nil
        guard visible else { return }; sample()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.sample() } }
        timer.tolerance = 2; RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let hadBattery = battery != nil; let wasCharging = charging
            let current = values[kIOPSCurrentCapacityKey] as? Int ?? 0; let maximum = values[kIOPSMaxCapacityKey] as? Int ?? 100
            battery = maximum > 0 ? Int(Double(current) / Double(maximum) * 100) : nil
            charging = (values[kIOPSIsChargingKey] as? Bool ?? false) || values[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if hadBattery && wasCharging != charging { onPowerChanged?(charging, battery) }
            if let battery, battery <= 15 && !charging { if !lowBatteryNotified { lowBatteryNotified = true; onLowBattery?() } }
            else { lowBatteryNotified = false }
        }
    }
    func sample() {
        var load = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if result == KERN_SUCCESS {
            if let previous {
                let now = [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3]
                let before = [previous.cpu_ticks.0, previous.cpu_ticks.1, previous.cpu_ticks.2, previous.cpu_ticks.3]
                let diffs = zip(now, before).map { Double($0 &- $1) }; let total = diffs.reduce(0, +)
                cpu = total > 0 ? (1 - diffs[2] / total) * 100 : 0
            }
            previous = load
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) } }
        if vmResult == KERN_SUCCESS {
            let used = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            memory = Double(used * UInt64(vm_kernel_page_size)) / Double(ProcessInfo.processInfo.physicalMemory) * 100
        }
        if let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()), let free = values[.systemFreeSize] as? Int64 { freeStorage = ByteCountFormatter.string(fromByteCount: free, countStyle: .file) }
        switch ProcessInfo.processInfo.thermalState { case .nominal: thermal = "Nominal"; case .fair: thermal = "Warm"; case .serious: thermal = "Hot"; case .critical: thermal = "Critical"; @unknown default: thermal = "Unknown" }
    }
}
