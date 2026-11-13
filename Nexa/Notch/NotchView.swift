import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    var hardwareHeight: CGFloat = 0
    var hardwareWidth: CGFloat = 170
    var hasNotch = false
    var presentation = IslandPresentation.ambient
    private var expandedPresentation: Bool { presentation == .workspace }
    var toggle: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var moduleSelection
    private var motion: NexaMotion { NexaMotion(preferences: preferences.value, systemReduceMotion: reduceMotion) }
    private var accent: Color { preferences.value.accent.color }
    private var cameraWidth: CGFloat { preferences.value.notchWidth > 0 ? max(120, preferences.value.notchWidth).rounded() : hardwareWidth }
    var body: some View {
        VStack(spacing: 0) {
            if expandedPresentation {
                expandedContent
            } else if presentation == .peek {
                VStack(spacing: 0) {
                    if hasNotch { Color.clear.frame(height: hardwareHeight) }
                    PeekView(model: model, preferences: preferences)
                }
            } else if let banner = model.banner, !model.paused {
                VStack(spacing: 0) {
                    if hasNotch { Color.clear.frame(height: hardwareHeight) }
                    HStack(spacing: 12) {
                        Image(systemName: banner.icon).foregroundStyle(accent).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 3) { Text(banner.title).font(.system(size: 12, weight: .semibold)); Text(banner.detail).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineLimit(1); if let progress = banner.progress { ProgressView(value: progress).tint(accent) } }
                        Spacer()
                    }.padding(.horizontal, 20).frame(maxHeight: .infinity)
                }.onTapGesture { model.setExpanded?(true) }
            } else {
                CollapsedView(media: model.media, live: model.live, timers: model.timers, system: model.system, accent: accent, hasNotch: hasNotch, cameraWidth: cameraWidth, paused: model.paused, timerEnabled: preferences.value.enabledModules.contains(.timers), preferences: preferences)
                    .contentShape(Rectangle()).onTapGesture { if preferences.value.clickToOpen { toggle() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white).tint(accent).preferredColorScheme(.dark)
        .allowsHitTesting(presentation == model.presentation)
        .disabled(model.paused || presentation != model.presentation)
        .contextMenu {
            if preferences.value.rightClickMenu {
                Button(model.expanded ? "Collapse" : "Open Nexa") { toggle() }
                Button("Edit Workspace…") { model.setPresentation?(.workspace); model.selected = .home; model.editingWorkspace = true }
                Menu("Display") {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                        Button(screen.localizedName) { preferences.value.preferredDisplay = NexaDisplays.identifier(screen) }
                    }
                }
                Toggle("Energy Saving", isOn: $preferences.value.energySaving)
                Button("Settings…") { model.showSettings?() }
                Button(model.paused ? "Resume Nexa" : "Pause Nexa") { model.togglePause() }
                Divider(); Button("Quit Nexa") { NSApp.terminate(nil) }
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .image], isTargeted: $model.dropTarget, perform: acceptDrop)
        .background {
            if expandedPresentation && model.expanded { SharePicker(items: model.sharingItems, presented: $model.showShare).frame(width: 1, height: 1) }
        }
        .environment(\.nexaMotion, motion)
        .accessibilityElement(children: .contain)
    }
    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) { Image(systemName: "waveform").foregroundStyle(accent); Text(model.selected == .home ? "nexa" : model.selected.title).font(.system(size: 12, weight: .semibold, design: .rounded)) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasNotch { Color.clear.frame(width: cameraWidth).accessibilityHidden(true) }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if model.selected == .home { IconButton(symbol: model.editingWorkspace ? "checkmark" : "slider.horizontal.3", help: model.editingWorkspace ? "Done editing" : "Edit Workspace", size: 25) { model.editingWorkspace.toggle() } }
                    Menu { ForEach(model.modules) { module in Button { model.selected = module } label: { Label(module.title, systemImage: module.icon) } } } label: { Image(systemName: "square.grid.2x2") }.menuStyle(.borderlessButton).fixedSize().help("Workspaces")
                    IconButton(symbol: "gearshape", help: "Settings", size: 25) { model.showSettings?() }
                    IconButton(symbol: "chevron.up", help: "Collapse Nexa", size: 25) { model.setExpanded?(false) }
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 29).frame(height: max(46, hardwareHeight + 10))
            ScrollView {
                ZStack(alignment: .top) { moduleContent.id(model.selected).transition(.opacity) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 22)
            }.scrollIndicators(.hidden).animation(motion.moduleAnimation, value: model.selected)
            HStack { Text("NEXA WORKSPACE").font(.system(size: 8, weight: .semibold)).tracking(1.5); Spacer(); if let banner = model.banner { Label(banner.title, systemImage: banner.icon).font(.system(size: 10)).foregroundStyle(accent) } }
                .foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 30).frame(height: 25)
        }
    }
    @ViewBuilder private var moduleContent: some View {
        switch model.selected {
        case .home: HomeView(model: model, preferences: preferences)
        case .mirror: MirrorView(service: model.mirror, preferences: preferences)
        case .notes: NotesView(service: model.notebook, accent: accent)
        case .todos: TodosView(service: model.notebook, accent: accent)
        case .shortcuts: ShortcutsView(service: model.shortcuts, accent: accent)
        case .music: NowPlayingView(service: model.media, controls: model.controls, preferences: preferences)
        case .files: FileShelfView(service: model.files, exporter: model.imageExport, dropTarget: model.dropTarget, accent: accent)
        case .clipboard: ClipboardView(service: model.clipboard, preferences: preferences)
        case .calendar: CalendarModuleView(service: model.calendar, accent: accent)
        case .reminders: RemindersView(service: model.calendar, accent: accent)
        case .timers: TimersView(service: model.timers, accent: accent)
        case .controls: ControlsView(service: model.controls, accent: accent)
        case .storage: StorageLauncherView(open: { model.showStorage?() })
        case .system: SystemStatsView(service: model.system, accent: accent)
        case .bluetooth: BluetoothView(service: model.bluetooth)
        case .weather: WeatherView(service: model.weather, preferences: preferences, settings: { model.showSettings?() })
        case .ai: AIPanelView(service: model.ai, preferences: preferences)
        case .live: LiveActivitiesView(service: model.live) { module in model.selected = module }
        }
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard preferences.value.dragAndDrop else { return false }
        for provider in providers.prefix(100) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), preferences.value.enabledModules.contains(.files) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                    let url: URL?
                    if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) } else { url = value as? URL }
                    if let url { Task { @MainActor in model.files.add([url]); model.selected = .files } }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in if let image { Task { @MainActor in model.sharingItems = [image]; model.showShare = true } } }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in if let text = object as? String { Task { @MainActor in model.sharingItems = [text]; model.showShare = true } } }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { object, _ in
                    if let url = object as? URL { Task { @MainActor in model.sharingItems = [url]; model.showShare = true } }
                }
            }
        }
        return true
    }
}

private struct CollapsedView: View {
    @ObservedObject var media: NowPlayingService
    @ObservedObject var live: LiveActivityStore
    @ObservedObject var timers: TimerService
    @ObservedObject var system: SystemService
    let accent: Color
    let hasNotch: Bool
    let cameraWidth: CGFloat
    let paused: Bool
    let timerEnabled: Bool
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        Group {
            if hasNotch {
                HStack(spacing: 0) {
                    leadingIndicator.frame(width: 32)
                    Color.clear.frame(width: cameraWidth).accessibilityHidden(true)
                    trailingIndicator.frame(width: 32)
                }
            } else {
                HStack(spacing: 8) {
                    leadingIndicator
                    Text("nexa").font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer(minLength: 20)
                    trailingIndicator
                }.padding(.horizontal, 13)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var leadingIndicator: some View {
        Group {
            if let activity = live.items.first(where: { $0.ongoing }) { Image(systemName: activity.icon).font(.system(size: 12)).foregroundStyle(accent).accessibilityLabel(activity.title) }
            else if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 5)) }
            else { Image(systemName: paused ? "pause" : "waveform").font(.system(size: 12)).foregroundStyle(accent) }
        }
    }
    private var trailingIndicator: some View {
        Group {
            if timers.running && timerEnabled { Circle().trim(from: 0, to: max(0.05, timers.progress)).stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 13, height: 13) }
            else if !media.track.appID.isEmpty && !paused { PlaybackPulse(playing: media.track.playing, preferences: preferences).frame(width: 18, height: 18) }
            else { Circle().fill(paused ? .gray : accent).frame(width: 5, height: 5) }
        }
    }
}
