import SwiftUI

enum IslandPresentation: String, CaseIterable {
    case ambient, peek, workspace
    var isOpen: Bool { self != .ambient }
}

enum NexaAppearance: String, Codable, CaseIterable, Identifiable {
    case liquidGlass, classicBlack
    var id: String { rawValue }
    var title: String { self == .liquidGlass ? "Liquid Glass" : "Classic Black" }
}

enum NexaGlassStyle: String, Codable, CaseIterable, Identifiable {
    case automatic, clear, balanced, tinted
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct HomeWidget: Codable, Equatable, Identifiable {
    enum Size: String, Codable, CaseIterable { case compact, regular, wide }
    var module: ModuleID
    var size: Size = .regular
    var id: ModuleID { module }
    static let defaults: [HomeWidget] = [HomeWidget(module: .music), HomeWidget(module: .system, size: .compact), HomeWidget(module: .calendar), HomeWidget(module: .todos, size: .compact)]
}

enum WorkspaceLayout {
    static let railHeight: CGFloat = 52
    static let railGap: CGFloat = 9
    static func railExtent(_ preferences: AppPreferences, presentation: IslandPresentation) -> CGFloat {
        presentation == .workspace && preferences.showWorkspaceRail ? railHeight + railGap : 0
    }
    static func rail(_ preferences: AppPreferences) -> [ModuleID] {
        var seen = Set<ModuleID>()
        return preferences.railModules.filter { preferences.enabledModules.contains($0) && seen.insert($0).inserted }
    }
    static func initialModule(_ preferences: AppPreferences) -> ModuleID {
        let requested = preferences.rememberWorkspace ? preferences.lastWorkspace : preferences.defaultWorkspace
        return preferences.enabledModules.contains(requested) ? requested : .home
    }
    static func move(_ module: ModuleID, before target: ModuleID, in list: [ModuleID]) -> [ModuleID] {
        guard module != target, list.contains(module), list.contains(target) else { return list }
        var result = list.filter { $0 != module }
        result.insert(module, at: result.firstIndex(of: target)!)
        return result
    }
}
