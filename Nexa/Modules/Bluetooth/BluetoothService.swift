import IOBluetooth
import Foundation
import Combine

struct BluetoothAccessory: Identifiable {
    let id: String
    let name: String
    let connected: Bool
    var symbol: String { name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones" }
}

@MainActor final class BluetoothService: NSObject, ObservableObject, ModuleLifecycle {
    @Published private(set) var devices: [BluetoothAccessory] = []
    @Published private(set) var powerOn = false
    private var connectedIDs = Set<String>()
    private var initialized = false
    var onDisconnected: ((String) -> Void)?
    var onConnected: ((String) -> Void)?
    private var connectionObserver: IOBluetoothUserNotification?
    private var disconnectionObservers: [IOBluetoothUserNotification] = []
    func start() {
        guard connectionObserver == nil else { return }
        refresh()
        connectionObserver = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connectionChanged(_:device:)))
    }
    func stop() {
        connectionObserver?.unregister(); connectionObserver = nil
        disconnectionObservers.forEach { $0.unregister() }; disconnectionObservers.removeAll()
    }
    @objc private func connectionChanged(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) { refresh() }
    func refresh() {
        powerOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        disconnectionObservers.forEach { $0.unregister() }; disconnectionObservers.removeAll()
        for device in paired where device.isConnected() {
            if let observer = device.register(forDisconnectNotification: self, selector: #selector(connectionChanged(_:device:))) { disconnectionObservers.append(observer) }
        }
        let previousDevices = devices
        devices = paired.map { BluetoothAccessory(id: $0.addressString ?? UUID().uuidString, name: $0.name ?? "Bluetooth device", connected: $0.isConnected()) }.sorted { $0.connected && !$1.connected }
        let current = Set(devices.filter(\.connected).map(\.id))
        if initialized, let id = current.subtracting(connectedIDs).first, let device = devices.first(where: { $0.id == id }) { onConnected?(device.name) }
        if initialized, let id = connectedIDs.subtracting(current).first, let device = previousDevices.first(where: { $0.id == id }) { onDisconnected?(device.name) }
        connectedIDs = current; initialized = true
    }
}
