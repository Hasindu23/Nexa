import SwiftUI

struct ControlsView: View {
    @ObservedObject var service: QuickControlsService
    let accent: Color
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Small controls. More flow.").font(.system(size: 22, weight: .medium)).tracking(-0.5)
            HStack(spacing: 12) { Button { service.toggleMute() } label: { Image(systemName: service.muted ? "speaker.slash" : "speaker.wave.2").frame(width: 24) }.buttonStyle(.plain).help("Toggle mute"); Slider(value: Binding(get: { service.volume }, set: { service.setVolume($0) }), in: 0...1).disabled(!service.volumeAvailable); Text(service.volumeAvailable ? "\(Int(service.volume * 100))%" : "External").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).frame(width: 48) }.padding(13).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            LazyVGrid(columns: columns, spacing: 9) {
                control("Keep awake", detail: service.awake ? "On · click to stop" : "Off", icon: "cup.and.saucer", active: service.awake) { service.toggleAwake() }
                control("Wi-Fi", detail: service.wifi, icon: "wifi") { service.settings("com.apple.wifi-settings-extension") }
                control("Bluetooth", detail: "Open settings", icon: "antenna.radiowaves.left.and.right") { service.settings("com.apple.BluetoothSettings") }
                control("Brightness", detail: "Display settings", icon: "sun.max") { service.settings("com.apple.Displays-Settings.extension") }
                control("Focus", detail: "Open settings", icon: "moon") { service.settings("com.apple.Focus-Settings.extension") }
                control("Screenshot", detail: "Open toolbar", icon: "viewfinder") { service.screenshot() }
            }
            HStack { Button("Lock screen  ⌃⌘Q") { service.lock() }; Spacer(); Button("System Settings ↗") { service.settings() } }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            InlineError(text: service.error)
        }
    }
    private func control(_ title: String, detail: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) { Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(active ? accent : .white.opacity(0.8)); Text(title).font(.system(size: 11, weight: .medium)); Text(detail).font(.system(size: 9)).foregroundStyle(NexaStyle.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(active ? accent.opacity(0.10) : NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}
