import SwiftUI
import Combine

enum ModuleID: String, CaseIterable, Codable, Identifiable {
    case home, music, files, notes, todos, shortcuts, mirror, clipboard, calendar, reminders, timers, controls, system, storage, bluetooth, weather, ai, live
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Nexa"
        case .notes: return "Notes"
        case .todos: return "Tasks"
        case .shortcuts: return "Shortcuts"
        case .mirror: return "Mirror"
        case .music: return "Music"
        case .files: return "Files"
        case .clipboard: return "Clipboard"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .timers: return "Timers"
        case .controls: return "Quick Controls"
        case .system: return "System"
        case .storage: return "Storage Cleaner"
        case .bluetooth: return "Bluetooth"
        case .weather: return "Weather"
        case .ai: return "AI"
        case .live: return "Live"
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
        case .live: return "bolt.horizontal.circle"
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

enum MotionPreset: String, Codable, CaseIterable, Identifiable {
    case subtle, balanced, playful
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum VisualizerStyle: String, Codable, CaseIterable, Identifiable {
    case bars, wave, minimal
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppPreferences: Codable, Equatable {
    var workspaceRevision = 1
    var workspaceShortcuts: [WorkspaceShortcut] = []
    var appearanceMode = NexaAppearance.liquidGlass
    var glassStyle = NexaGlassStyle.balanced
    var glassTintStrength = 0.35
    var blueReflection = true
    var specularHighlight = true
    var interactiveGlass = true
    var showWorkspaceRail = true
    var rememberWorkspace = false
    var defaultWorkspace = ModuleID.home
    var lastWorkspace = ModuleID.home
    var railModules: [ModuleID] = [.home, .music, .calendar, .files, .todos, .ai, .live]
    var homeWidgets = HomeWidget.defaults
    var swipeGestures = true
    var enabledDisplayIDs: [String] = []
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
    var motionPreset = MotionPreset.balanced
    var reduceMotion = false
    var energySaving = false
    var visualizerStyle = VisualizerStyle.bars
    var visualizerBrightness = 0.8
    var ambientBlueGlow = true
    var glowIntensity = 0.35
    var notchWidth = 0.0
    var horizontalOffset = 0.0
    var opacity = 0.96
    var blur = 0.8
    var cornerRadius = 26.0
    var layout = "Normal"
    var shadow = true
    var border = true
    var accent = Accent.blue
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
    var homeHeight: CGFloat { expandedHeight }
    var expandedHeight: CGFloat { layout == "Compact" ? 390 : layout == "Large" ? 490 : 440 }
}

@MainActor final class PreferencesStore: ObservableObject {
    @Published var recordingShortcut = false
    @Published var value: AppPreferences { didSet { persist() } }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Merge saved keys over defaults so new settings never reset existing choices.
        let base = (try? JSONEncoder().encode(AppPreferences())).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let saved = defaults.data(forKey: "preferences.v1").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var merged = base.merging(saved) { _, old in old }
        // Recover an unknown future enum independently instead of resetting all
        // preferences, permissions, and module choices during decoding.
        if let raw = merged["motionPreset"] as? String, MotionPreset(rawValue: raw) == nil { merged["motionPreset"] = base["motionPreset"] }
        if let raw = merged["visualizerStyle"] as? String, VisualizerStyle(rawValue: raw) == nil { merged["visualizerStyle"] = base["visualizerStyle"] }
        for (key, known) in [
            ("appearanceMode", Set(NexaAppearance.allCases.map(\.rawValue))),
            ("glassStyle", Set(NexaGlassStyle.allCases.map(\.rawValue))),
            ("defaultWorkspace", Set(ModuleID.allCases.map(\.rawValue))),
            ("lastWorkspace", Set(ModuleID.allCases.map(\.rawValue)))
        ] { if let raw = merged[key] as? String, !known.contains(raw) { merged[key] = base[key] } }
        if let rail = merged["railModules"] as? [String] {
            var seen = Set<String>()
            merged["railModules"] = rail.filter { ModuleID(rawValue: $0) != nil && seen.insert($0).inserted }
        }
        if let widgets = merged["homeWidgets"] as? [[String: Any]] {
            var seen = Set<String>()
            merged["homeWidgets"] = Array(widgets.compactMap { raw -> [String: Any]? in
                guard let module = raw["module"] as? String, ModuleID(rawValue: module) != nil, seen.insert(module).inserted else { return nil }
                let size = (raw["size"] as? String).flatMap(HomeWidget.Size.init(rawValue:)) ?? .regular
                return ["module": module, "size": size.rawValue]
            }.prefix(8))
        } else { merged["homeWidgets"] = base["homeWidgets"] }
        if let shortcuts = merged["workspaceShortcuts"] as? [[String: Any]] {
            var actions = Set<String>()
            merged["workspaceShortcuts"] = shortcuts.filter { raw in
                guard let action = raw["action"] as? String, WorkspaceAction(rawValue: action) != nil,
                      let code = raw["keyCode"] as? Int, (0...127).contains(code),
                      let modifiers = raw["modifiers"] as? Int, (0...65535).contains(modifiers),
                      raw["label"] is String else { return false }
                return actions.insert(action).inserted
            }
        } else { merged["workspaceShortcuts"] = [] }
        for (key, range) in [("animationSpeed", 0.5...2.0), ("visualizerBrightness", 0.1...1.0), ("glowIntensity", 0.0...1.0), ("glassTintStrength", 0.0...1.0)] {
            if let number = merged[key] as? Double { merged[key] = number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : base[key] }
        }
        for key in ["repositoryURL", "updateFeedURL"] where saved[key] as? String == "" { merged[key] = base[key] }
        if saved["motionRevision"] == nil {
            // Upgrade only the previous defaults, preserving custom gesture timing.
            if saved["hoverDelay"] as? Double == 0.25 { merged["hoverDelay"] = 0.14 }
            if saved["collapseDelay"] as? Double == 0.65 { merged["collapseDelay"] = 0.42 }
        }
        if let modules = saved["enabledModules"] as? [String] {
            let newModules = saved["centerWidget"] == nil ? ["home", "mirror", "notes", "todos", "shortcuts"] : saved["workspaceRevision"] == nil ? ["home", "live"] : ["home"]
            merged["enabledModules"] = Array(Set(modules.filter { ModuleID(rawValue: $0) != nil } + newModules))
        }
        if saved["homeWidgets"] == nil, let center = saved["centerWidget"] as? String {
            let migrated: ModuleID = ["Calendar": .calendar, "Shortcuts": .shortcuts, "Notes": .notes, "To-dos": .todos, "Timer": .timers][center] ?? .calendar
            var widgets = HomeWidget.defaults
            if let index = widgets.firstIndex(where: { $0.module == .calendar }) { widgets[index].module = migrated }
            var seen = Set<ModuleID>(); widgets = widgets.filter { seen.insert($0.module).inserted }
            merged["homeWidgets"] = (try? JSONEncoder().encode(widgets)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
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
