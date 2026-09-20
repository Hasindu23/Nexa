import SwiftUI
import Combine

enum ModuleID: String, CaseIterable, Codable, Identifiable {
    case home, music, files, notes, todos, shortcuts, mirror, clipboard, calendar, reminders, timers, controls, system, storage, bluetooth, weather, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .notes: return "Notes"
        case .todos: return "To-dos"
        case .shortcuts: return "Shortcuts"
        case .mirror: return "Mirror"
        case .music: return "Now Playing"
        case .files: return "File Shelf"
        case .clipboard: return "Clipboard"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .timers: return "Timers"
        case .controls: return "Quick Controls"
        case .system: return "System"
        case .storage: return "Storage Cleaner"
        case .bluetooth: return "Bluetooth"
        case .weather: return "Weather"
        case .ai: return "Assistant"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .notes: return "note.text"
        case .todos: return "checkmark.circle"
        case .shortcuts: return "command"
        case .mirror: return "web.camera"
        case .music: return "waveform"
        case .files: return "tray"
        case .clipboard: return "doc.on.clipboard"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .timers: return "timer"
        case .controls: return "slider.horizontal.3"
        case .system: return "chart.bar.xaxis"
        case .storage: return "externaldrive"
        case .bluetooth: return "headphones"
        case .weather: return "cloud.sun"
        case .ai: return "sparkles"
        }
    }
}

enum Accent: String, Codable, CaseIterable {
    case mint, blue, violet, amber, rose
    var color: Color {
        switch self {
        case .mint: return Color(red: 0.60, green: 0.94, blue: 0.79)
        case .blue: return Color(red: 0.50, green: 0.74, blue: 1)
        case .violet: return Color(red: 0.75, green: 0.65, blue: 1)
        case .amber: return Color(red: 1, green: 0.79, blue: 0.47)
        case .rose: return Color(red: 1, green: 0.60, blue: 0.70)
        }
    }
}

struct AppPreferences: Codable, Equatable {
    var completedOnboarding = false
    var showMenuBar = true
    var hoverToOpen = true
    var clickToOpen = true
    var rightClickMenu = true
    var dragAndDrop = true
    var scrollCyclesModules = false
    var allSpaces = true
    var motionRevision = 1
    var hoverDelay = 0.14
    var collapseDelay = 0.42
    var animationSpeed = 1.0
    var notchWidth = 0.0
    var horizontalOffset = 0.0
    var opacity = 0.96
    var blur = 0.8
    var cornerRadius = 26.0
    var layout = "Normal"
    var shadow = true
    var border = true
    var accent = Accent.mint
    var soundEffects = false
    var enabledModules = Set(ModuleID.allCases.filter { $0 != .ai && $0 != .weather && $0 != .bluetooth })
    var clipboardEnabled = false
    var historyLimit = 80
    var persistentShelf = true
    var shelfExpiryHours = 24.0
    var localOnly = true
    var mediaConnected = false
    var centerWidget = "Calendar"
    var hapticFeedback = true
    var cameraDeviceID = ""
    var preferredDisplay = "Automatic"
    var weatherLatitude = ""
    var weatherLongitude = ""
    var weatherLocation = "My location"
    var weatherEndpoint = "https://api.open-meteo.com/v1/forecast"
    var fahrenheit = false
    var aiModel = "gpt-4.1-mini"
    var repositoryURL = "https://github.com/Hasindu23/Nexa"
    var updateFeedURL = "https://raw.githubusercontent.com/Hasindu23/Nexa/main/release.json"
    var expandedWidth: CGFloat { layout == "Compact" ? 660 : layout == "Large" ? 820 : 740 }
    var homeHeight: CGFloat { layout == "Compact" ? 192 : layout == "Large" ? 230 : 208 }
    var expandedHeight: CGFloat { layout == "Compact" ? 370 : layout == "Large" ? 460 : 414 }
}

@MainActor final class PreferencesStore: ObservableObject {
    @Published var value: AppPreferences { didSet { persist() } }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Merge saved keys over defaults so new settings never reset existing choices.
        let base = (try? JSONEncoder().encode(AppPreferences())).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let saved = defaults.data(forKey: "preferences.v1").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var merged = base.merging(saved) { _, old in old }
        for key in ["repositoryURL", "updateFeedURL"] where saved[key] as? String == "" { merged[key] = base[key] }
        if saved["motionRevision"] == nil {
            // Upgrade only the previous defaults, preserving custom gesture timing.
            if saved["hoverDelay"] as? Double == 0.25 { merged["hoverDelay"] = 0.14 }
            if saved["collapseDelay"] as? Double == 0.65 { merged["collapseDelay"] = 0.42 }
        }
        if let modules = saved["enabledModules"] as? [String] {
            let newModules = saved["centerWidget"] == nil ? ["home", "mirror", "notes", "todos", "shortcuts"] : ["home"]
            merged["enabledModules"] = Array(Set(modules.filter { ModuleID(rawValue: $0) != nil } + newModules))
        }
        value = (try? JSONSerialization.data(withJSONObject: merged)).flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences.v1") }
    }
    func toggle(_ module: ModuleID, enabled: Bool) {
        if enabled { value.enabledModules.insert(module) } else { value.enabledModules.remove(module) }
    }
}
