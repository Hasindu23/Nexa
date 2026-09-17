import SwiftUI

struct WeatherView: View {
    @ObservedObject var service: WeatherService
    @ObservedObject var preferences: PreferencesStore
    let settings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text(service.temperature == nil ? preferences.value.weatherLocation : service.location).font(.system(size: 20, weight: .medium)); Spacer(); Button { service.fetch(preferences: preferences.value) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(service.busy).help("Fetch current weather") }
            if let temperature = service.temperature {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text("\(Int(temperature.rounded()))°").font(.system(size: 65, weight: .ultraLight)); Text(service.condition).font(.system(size: 14)); Text("H: \(Int((service.high ?? temperature).rounded()))°   L: \(Int((service.low ?? temperature).rounded()))°").font(.system(size: 12)).foregroundStyle(NexaStyle.secondary) }
                    Spacer(); Image(systemName: service.symbol).font(.system(size: 70, weight: .ultraLight)).foregroundStyle(preferences.value.accent.color).padding(22)
                }
                if let date = service.updatedAt { Text("Updated \(date.formatted(date: .omitted, time: .shortened)) · \(service.fahrenheit ? "°F" : "°C")").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary) }
            } else {
                EmptyModule(icon: "cloud.sun", title: "A glance outside.", detail: "Add a location in Settings. Weather only requests your chosen coordinates when you refresh.")
                HStack { Button("Set location", action: settings); Button("Get weather") { service.fetch(preferences: preferences.value) }.disabled(service.busy) }.buttonStyle(CapsuleButtonStyle(accent: preferences.value.accent.color)).frame(maxWidth: .infinity)
            }
            InlineError(text: service.error)
            Link("Weather data by Open-Meteo ↗", destination: URL(string: "https://open-meteo.com/")!).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
        }
    }
}
