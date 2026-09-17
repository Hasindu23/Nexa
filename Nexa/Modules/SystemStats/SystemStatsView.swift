import SwiftUI

struct SystemStatsView: View {
    @ObservedObject var service: SystemService
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("A pulse on your Mac.").font(.system(size: 22, weight: .medium)).tracking(-0.5); Spacer(); Text("LIVE").font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(accent) }
            HStack(spacing: 12) {
                metric("BATTERY", value: service.battery.map { "\($0)%" } ?? "AC", detail: service.charging ? "Plugged in" : service.battery == nil ? "Desktop power" : "On battery", icon: service.charging ? "battery.100percent.bolt" : "battery.75percent", progress: Double(service.battery ?? 100) / 100)
                metric("PROCESSOR", value: String(format: "%.0f%%", service.cpu), detail: "System CPU", icon: "cpu", progress: service.cpu / 100)
                metric("MEMORY", value: String(format: "%.0f%%", service.memory), detail: "Active + wired", icon: "memorychip", progress: service.memory / 100)
            }
            Surface { HStack { Label("\(service.freeStorage) free", systemImage: "internaldrive"); Spacer(); Label(service.thermal, systemImage: "thermometer.medium") }.font(.system(size: 11)).foregroundStyle(NexaStyle.secondary) }
            Text("Updates while open. macOS thermal state; exact temperatures and battery health unavailable.").font(.system(size: 9)).foregroundStyle(NexaStyle.secondary)
        }
    }
    private func metric(_ title: String, value: String, detail: String, icon: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.system(size: 8, weight: .semibold)).tracking(1); Spacer(); Image(systemName: icon).font(.system(size: 12)).foregroundStyle(accent) }
            Text(value).font(.system(size: 29, weight: .light)).tracking(-1)
            ProgressView(value: min(1, max(0, progress))).tint(accent).scaleEffect(y: 0.7)
            Text(detail).font(.system(size: 9)).foregroundStyle(NexaStyle.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 15))
    }
}
