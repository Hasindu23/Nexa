import AppKit
import Combine
import CoreAudio
import AudioToolbox
import CoreWLAN
import IOKit.pwr_mgt
import ServiceManagement
import ApplicationServices

@MainActor final class QuickControlsService: ObservableObject {
    @Published var volume: Double = 0
    @Published var volumeAvailable = false
    @Published var muted = false
    @Published var awake = false
    @Published var wifi = "—"
    @Published var error: String?
    @Published var loginEnabled = false
    private var assertion: IOPMAssertionID = 0
    private var device = AudioDeviceID(0)
    private let queryQueue = DispatchQueue(label: "app.nexa.device-query", qos: .userInitiated)
    private let readSnapshot: () -> ControlsSnapshot
    private var queryGeneration = 0
    private var refreshing = false
    init(readSnapshot: @escaping () -> ControlsSnapshot = { ControlsSnapshot.read() }) { self.readSnapshot = readSnapshot }
    func refresh() {
        guard !refreshing else { return }
        refreshing = true; queryGeneration += 1
        let generation = queryGeneration, read = readSnapshot
        queryQueue.async { [weak self] in
            let snapshot = read()
            DispatchQueue.main.async {
                guard let self else { return }; self.refreshing = false
                guard generation == self.queryGeneration else { return }
                self.device = snapshot.device
                if self.volumeAvailable != snapshot.volumeAvailable { self.volumeAvailable = snapshot.volumeAvailable }
                if self.volume != snapshot.volume { self.volume = snapshot.volume }
                if self.muted != snapshot.muted { self.muted = snapshot.muted }
                if self.wifi != snapshot.wifi { self.wifi = snapshot.wifi }
                if self.loginEnabled != snapshot.loginEnabled { self.loginEnabled = snapshot.loginEnabled }
            }
        }
    }
    func setVolume(_ newValue: Double) {
        queryGeneration += 1
        var value = Float32(min(1, max(0, newValue)))
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value) == noErr { volume = Double(value) }
        else { error = "This output device manages its own volume." }
    }
    func toggleMute() {
        queryGeneration += 1
        var value: UInt32 = muted ? 0 : 1
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value) == noErr { muted.toggle() }
        else { error = "Mute is not available for this output device." }
    }
    func toggleAwake() {
        if awake { IOPMAssertionRelease(assertion); awake = false }
        else {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Nexa keep awake" as CFString, &assertion)
            if result == kIOReturnSuccess { awake = true } else { error = "macOS could not enable Keep Awake." }
        }
    }
    func stop() { queryGeneration += 1; if awake { toggleAwake() } }
    func login(_ enabled: Bool) {
        queryGeneration += 1
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { self.error = "Launch at login could not be updated. Move Nexa to Applications and try again. \(error.localizedDescription)" }
    }
    func settings(_ section: String = "") { if let url = URL(string: "x-apple.systempreferences:\(section)") { NSWorkspace.shared.open(url) } }
    func screenshot() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screencaptureui") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
        else { error = "Press ⇧⌘5 to open the macOS screenshot toolbar." }
    }
    func lock() {
        guard AXIsProcessTrusted() else { error = "Press ⌃⌘Q to lock your Mac. To use this button, enable Nexa in System Settings → Privacy & Security → Accessibility."; return }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false)
        down?.flags = [.maskControl, .maskCommand]; up?.flags = [.maskControl, .maskCommand]
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
}

struct ControlsSnapshot {
    var device = AudioDeviceID(0)
    var volume = 0.0
    var volumeAvailable = false
    var muted = false
    var wifi = "Unavailable"
    var loginEnabled = false
    static func read() -> ControlsSnapshot {
        var result = ControlsSnapshot()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &result.device) == noErr {
            address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var value: Float32 = 0; size = UInt32(MemoryLayout<Float32>.size)
            result.volumeAvailable = AudioObjectGetPropertyData(result.device, &address, 0, nil, &size, &value) == noErr
            result.volume = value.isFinite ? min(1, max(0, Double(value))) : 0
            address.mSelector = kAudioDevicePropertyMute; var mute: UInt32 = 0; size = 4
            if AudioObjectGetPropertyData(result.device, &address, 0, nil, &size, &mute) == noErr { result.muted = mute != 0 }
        }
        if let interface = CWWiFiClient.shared().interface() { result.wifi = interface.powerOn() ? "On" : "Off" }
        result.loginEnabled = SMAppService.mainApp.status == .enabled
        return result
    }
}
