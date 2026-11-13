import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceDrag {
    static let railType = UTType(exportedAs: "app.nexa.workspace-rail")
    static let widgetType = UTType(exportedAs: "app.nexa.home-widget")
    static func provider(_ module: ModuleID, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(Data(module.rawValue.utf8), nil); return nil
        }
        return provider
    }
    static func read(_ providers: [NSItemProvider], type: UTType, action: @escaping @MainActor (ModuleID) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            guard let data, data.count < 64, let raw = String(data: data, encoding: .utf8), let module = ModuleID(rawValue: raw) else { return }
            Task { @MainActor in action(module) }
        }
        return true
    }
}

struct WorkspaceRail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: NexaMotion { NexaMotion(preferences: preferences.value, systemReduceMotion: reduceMotion) }
    var body: some View {
        GeometryReader { geometry in
            let modules = Array(WorkspaceLayout.rail(preferences.value).prefix(geometry.size.width < 500 ? 5 : 7))
            HStack(spacing: 3) {
                ForEach(modules) { module in
                    Button { model.selected = module } label: {
                        VStack(spacing: 3) {
                            Image(systemName: module.icon).font(.system(size: 14, weight: .medium))
                            if geometry.size.width >= 500 { Text(module.title).font(.system(size: 9, weight: .medium)).lineLimit(1) }
                        }.foregroundStyle(model.selected == module ? Color.white : Color.white.opacity(0.58))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background { if model.selected == module { Capsule().fill(preferences.value.accent.color.opacity(0.23)).overlay(Capsule().strokeBorder(.white.opacity(0.16))).matchedGeometryEffect(id: "selection", in: selection) } }
                    }.buttonStyle(NotchButtonStyle()).help(module.title).accessibilityLabel(module.title)
                        .accessibilityAddTraits(model.selected == module ? .isSelected : [])
                        .accessibilityIdentifier("module.\(module.rawValue)")
                        .onDrag { WorkspaceDrag.provider(module, type: WorkspaceDrag.railType) }
                        .onDrop(of: [WorkspaceDrag.railType], isTargeted: nil) { providers in
                            WorkspaceDrag.read(providers, type: WorkspaceDrag.railType) { source in preferences.value.railModules = WorkspaceLayout.move(source, before: module, in: preferences.value.railModules) }
                        }
                        .contextMenu {
                            Button("Hide from rail") { preferences.value.railModules.removeAll { $0 == module } }
                            Button("Move first") { preferences.value.railModules.removeAll { $0 == module }; preferences.value.railModules.insert(module, at: 0) }
                        }
                }
                Menu {
                    ForEach(model.modules.filter { !modules.contains($0) }) { module in
                        Button { model.selected = module } label: { Label(module.title, systemImage: module.icon) }
                    }
                    Divider()
                    Button("Edit Workspace…") { model.selected = .home; model.editingWorkspace = true }
                    Button("Customize rail…") { model.showSettings?() }
                } label: {
                    VStack(spacing: 3) { Image(systemName: "ellipsis").font(.system(size: 14)); if geometry.size.width >= 500 { Text("More").font(.system(size: 9)) } }
                        .frame(width: 50, height: 42)
                        .background { if !modules.contains(model.selected) { Capsule().fill(preferences.value.accent.color.opacity(0.23)).matchedGeometryEffect(id: "selection", in: selection) } }
                }.menuStyle(.borderlessButton).fixedSize().help("More workspaces")
            }.padding(5).background(NexaGlassBackground(preferences: preferences.value, radius: 26))
                .clipShape(Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.18))).clipped()
                .animation(motion.moduleAnimation, value: model.selected)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .environment(\.nexaMotion, motion)
            .allowsHitTesting(model.presentation == .workspace && preferences.value.showWorkspaceRail)
            .accessibilityElement(children: .contain)
    }
}

struct PeekView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("AT A GLANCE").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(preferences.value.accent.color); Spacer(); Button("Open workspace") { model.setPresentation?(.workspace) }.font(.system(size: 11)) }
            if let banner = model.banner {
                Label { VStack(alignment: .leading, spacing: 5) { Text(banner.title).font(.headline); Text(banner.detail).font(.caption).foregroundStyle(NexaStyle.secondary).lineLimit(2) } } icon: { Image(systemName: banner.icon).foregroundStyle(preferences.value.accent.color) }
            } else {
                PeekContext(media: model.media, live: model.live, timers: model.timers, system: model.system, preferences: preferences)
            }
        }.padding(.horizontal, 25).padding(.vertical, 16)
    }
}

private struct PeekContext: View {
    @ObservedObject var media: NowPlayingService
    @ObservedObject var live: LiveActivityStore
    @ObservedObject var timers: TimerService
    @ObservedObject var system: SystemService
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        HStack(spacing: 14) {
            if let activity = live.items.first(where: { $0.ongoing && $0.module != .timers }) {
                Image(systemName: activity.icon).font(.system(size: 24)).foregroundStyle(preferences.value.accent.color)
                VStack(alignment: .leading, spacing: 5) { Text(activity.title).font(.system(size: 14, weight: .medium)); Text(activity.detail).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineLimit(2) }
                Spacer()
            } else if timers.running {
                Image(systemName: "timer").font(.system(size: 26)).foregroundStyle(preferences.value.accent.color)
                VStack(alignment: .leading, spacing: 4) { Text(timers.remaining.clockString).font(.system(size: 27, weight: .light)).monospacedDigit(); Text("Focus timer").font(.caption).foregroundStyle(NexaStyle.secondary) }
                Spacer(); Button("Pause") { timers.toggle() }.buttonStyle(CapsuleButtonStyle(accent: preferences.value.accent.color))
            } else if !media.track.appID.isEmpty {
                MediaArtwork(service: media, accent: preferences.value.accent.color).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) { Text(media.track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); Text(media.track.artist).font(.caption).foregroundStyle(NexaStyle.secondary).lineLimit(1) }
                Spacer(); IconButton(symbol: media.track.playing ? "pause.fill" : "play.fill", help: media.track.playing ? "Pause" : "Play") { media.command("playpause") }.disabled(media.demo)
            } else {
                Image(systemName: system.battery == nil ? "waveform" : "battery.75percent").font(.system(size: 24)).foregroundStyle(preferences.value.accent.color)
                VStack(alignment: .leading, spacing: 5) { Text(system.battery.map { "\($0)% battery" } ?? "A little space for your day.").font(.system(size: 15, weight: .medium)); Text(system.charging ? "Connected to power" : "Music, tasks and your next step.").font(.caption).foregroundStyle(NexaStyle.secondary) }
                Spacer()
            }
        }
    }
}
