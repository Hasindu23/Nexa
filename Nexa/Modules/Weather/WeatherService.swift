import Foundation
import Combine

@MainActor final class WeatherService: ObservableObject {
    @Published private(set) var temperature: Double?
    @Published private(set) var high: Double?
    @Published private(set) var low: Double?
    @Published private(set) var condition = "Ready when you are"
    @Published private(set) var symbol = "cloud.sun"
    @Published private(set) var updatedAt: Date?
    @Published private(set) var location = ""
    @Published private(set) var fahrenheit = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel(); task = nil; busy = false }
    func fetch(preferences: AppPreferences) {
        guard !preferences.localOnly, preferences.enabledModules.contains(.weather) else { error = "Weather needs network access. Turn off Local-only mode in Privacy."; return }
        guard let latitude = Double(preferences.weatherLatitude), let longitude = Double(preferences.weatherLongitude), (-90...90).contains(latitude), (-180...180).contains(longitude) else { error = "Add valid latitude and longitude in Settings → Weather."; return }
        cancel(); error = nil; busy = true
        guard var components = URLComponents(string: preferences.weatherEndpoint), components.scheme == "https", components.host != nil else { error = "Use an HTTPS Open-Meteo-compatible forecast endpoint."; busy = false; return }
        components.queryItems = [URLQueryItem(name: "latitude", value: String(latitude)), URLQueryItem(name: "longitude", value: String(longitude)), URLQueryItem(name: "current", value: "temperature_2m,weather_code"), URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"), URLQueryItem(name: "temperature_unit", value: preferences.fahrenheit ? "fahrenheit" : "celsius"), URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "1")]
        task = Task { [weak self] in
            do {
                let (data, response) = try await NetworkClient.session.data(from: components.url!)
                try Task.checkCancellation(); try NetworkClient.checked(response)
                let weather = try JSONDecoder().decode(Forecast.self, from: data)
                self?.temperature = weather.current.temperature_2m; self?.high = weather.daily.temperature_2m_max.first; self?.low = weather.daily.temperature_2m_min.first
                let value = Self.describe(weather.current.weather_code); self?.condition = value.0; self?.symbol = value.1
                self?.updatedAt = Date(); self?.busy = false
                self?.location = preferences.weatherLocation; self?.fahrenheit = preferences.fahrenheit
            } catch { guard !Task.isCancelled else { return }; self?.error = "Weather is unavailable. \(error.localizedDescription)"; self?.busy = false }
        }
    }
    static func describe(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("Clear skies", "sun.max")
        case 1...3: return ("Partly cloudy", "cloud.sun")
        case 45, 48: return ("Foggy", "cloud.fog")
        case 51...67, 80...82: return ("Rain", "cloud.rain")
        case 71...77, 85, 86: return ("Snow", "cloud.snow")
        case 95...99: return ("Thunderstorms", "cloud.bolt.rain")
        default: return ("Conditions unavailable", "cloud")
        }
    }
    struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Current; let daily: Daily
    }
}
