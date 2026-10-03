import AppKit
import Combine
import Darwin

struct MemorySnapshot: Sendable {
    let date: Date
    let total: UInt64
    let free: UInt64
    let wired: UInt64
    let compressed: UInt64
    let swap: UInt64?
    let pressure: Int32?
    var pressureName: String {
        switch pressure { case 1: return "Normal"; case 2: return "Elevated"; case 4: return "Critical"; default: return "Unavailable" }
    }
    static func read() throws -> MemorySnapshot {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self(); defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { throw StorageFailure.blocked("macOS memory statistics are unavailable.") }
        var pressure: Int32 = 0, pressureSize = MemoryLayout<Int32>.size
        let pressureResult = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0)
        var swap = xsw_usage(), swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        let page = UInt64(vm_kernel_page_size), total = ProcessInfo.processInfo.physicalMemory
        return MemorySnapshot(date: Date(), total: total, free: min(total, UInt64(vm.free_count) * page),
                              wired: UInt64(vm.wire_count) * page, compressed: UInt64(vm.compressor_page_count) * page,
                              swap: swapResult == 0 ? swap.xsu_used : nil, pressure: pressureResult == 0 ? pressure : nil)
    }
    static func footprint(pid: pid_t) -> UInt64? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }
}

struct MemoryApp: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let bundleID: String?
    let bundlePath: String?
    let launched: Date?
    let regular: Bool
    let owned: Bool
    let bytes: UInt64?
    var id: pid_t { pid }
    var canQuit: Bool {
        regular && owned && pid > 1 && pid != getpid() && launched != nil && bundlePath != nil &&
        bundleID != nil && !["com.apple.finder", "app.nexa.mac"].contains(bundleID!)
    }
    func sameInstance(as other: MemoryApp) -> Bool {
        pid == other.pid && launched == other.launched && bundleID == other.bundleID && bundlePath == other.bundlePath
    }
    @MainActor static func capture(_ app: NSRunningApplication) -> MemoryApp {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let read = proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        return MemoryApp(pid: app.processIdentifier, name: app.localizedName ?? "Application", bundleID: app.bundleIdentifier,
                         bundlePath: app.bundleURL?.path, launched: app.launchDate, regular: app.activationPolicy == .regular,
                         owned: read == size && info.pbi_uid == getuid(), bytes: MemorySnapshot.footprint(pid: app.processIdentifier))
    }
}

enum MemoryQuitGate {
    /// No signals or force-quit API. Re-resolve the process immediately before a normal quit.
    static func request(_ target: MemoryApp, confirmed: Bool, current: MemoryApp?, send: () -> Bool) throws {
        guard confirmed else { throw StorageFailure.blocked("Confirm the selected app before asking it to quit.") }
        guard target.canQuit, let current, current.canQuit, target.sameInstance(as: current) else {
            throw StorageFailure.blocked("This app changed or cannot be quit here. Refresh and review again.")
        }
        guard send() else { throw StorageFailure.blocked("The app did not accept the quit request. Save your work and quit it from its own menu.") }
    }
}

@MainActor final class MemoryService: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var apps: [MemoryApp] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Refresh to inspect RAM and running applications."
    @Published var error: String?
    @Published var pendingQuit: MemoryApp?
    private var worker: Task<Void, Never>?
    func refresh() {
        guard !busy else { return }
        do {
            snapshot = try MemorySnapshot.read(); error = nil
            apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
                .map(MemoryApp.capture).sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
            status = "Updated \(snapshot!.date.formatted(date: .omitted, time: .standard)) · refreshes only on request"
        } catch { snapshot = nil; self.error = error.localizedDescription }
    }
    func reviewQuit(_ app: MemoryApp) { guard !busy, app.canQuit else { return }; pendingQuit = app }
    func confirmQuit() {
        guard !busy, let target = pendingQuit else { return }; pendingQuit = nil; error = nil
        do {
            let running = NSRunningApplication(processIdentifier: target.pid)
            try MemoryQuitGate.request(target, confirmed: true, current: running.map(MemoryApp.capture)) { running?.terminate() == true }
            busy = true; status = "Quit requested for \(target.name). Complete any save dialog in that app."
            worker = Task { [weak self] in
                for _ in 0..<12 {
                    guard !Task.isCancelled else { return }
                    if running?.isTerminated != false { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard let self, !Task.isCancelled else { return }
                let ended = running?.isTerminated != false
                self.busy = false; self.refresh(); self.worker = nil
                self.status = ended ? "\(target.name) closed. RAM refreshed; macOS decides how released memory is reused." : "\(target.name) is still open. Save your work or finish its dialog, then refresh. Nothing was force-quit."
            }
        } catch { self.error = error.localizedDescription }
    }
    func cancel() { worker?.cancel(); worker = nil; busy = false; pendingQuit = nil }
    func loadFixture(_ snapshot: MemorySnapshot, apps: [MemoryApp]) {
        self.snapshot = snapshot; self.apps = apps; status = "Generated QA display · no personal apps selected"
    }
}
