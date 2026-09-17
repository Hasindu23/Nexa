import SwiftUI

struct BluetoothView: View {
    @ObservedObject var service: BluetoothService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("A familiar connection.").font(.system(size: 22, weight: .medium)).tracking(-0.5); Spacer(); IconButton(symbol: "arrow.clockwise", help: "Refresh Bluetooth") { service.refresh() } }
            if service.devices.isEmpty { EmptyModule(icon: "headphones", title: service.powerOn ? "Nothing connected yet." : "Bluetooth is off.", detail: "Paired accessories appear here when macOS makes them available.") }
            ForEach(service.devices) { device in
                Surface {
                    HStack(spacing: 15) { Image(systemName: device.symbol).font(.system(size: 27, weight: .light)); VStack(alignment: .leading, spacing: 5) { Text(device.name).font(.system(size: 13, weight: .medium)); Text(device.connected ? "Connected" : "Not connected").font(.system(size: 11)).foregroundStyle(device.connected ? Accent.mint.color : NexaStyle.secondary) }; Spacer(); Circle().fill(device.connected ? Accent.mint.color : .gray).frame(width: 6, height: 6) }
                }
            }
            Text("Left, right and case battery levels aren’t available through the supported APIs used by Nexa. Connection changes use system notifications while enabled.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary).lineSpacing(3)
        }
    }
}
