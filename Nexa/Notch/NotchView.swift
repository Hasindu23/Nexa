import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    var hardwareHeight: CGFloat = 0
    var hardwareWidth: CGFloat = 170
    var hasNotch = false
    var expandedPresentation = false
    var toggle: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { preferences.value.accent.color }
    private var cameraWidth: CGFloat { preferences.value.notchWidth > 0 ? max(120, preferences.value.notchWidth).rounded() : hardwareWidth }
    var body: some View {
        VStack(spacing: 0) {
            if expandedPresentation {
                expandedContent
            } else if let banner = model.banner, !model.paused {
                VStack(spacing: 0) {
                    if hasNotch { Color.clear.frame(height: hardwareHeight) }
                    HStack(spacing: 12) {
                        Image(systemName: banner.icon).foregroundStyle(accent).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 3) { Text(banner.title).font(.system(size: 12, weight: .semibold)); Text(banner.detail).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineLimit(1) }
                        Spacer()
                    }.padding(.horizontal, 20).frame(maxHeight: .infinity)
                }.onTapGesture { model.setExpanded?(true) }
            } else {
                CollapsedView(media: model.media, timers: model.timers, system: model.system, accent: accent, hasNotch: hasNotch, cameraWidth: cameraWidth, paused: model.paused, timerEnabled: preferences.value.enabledModules.contains(.timers))
                    .contentShape(Rectangle()).onTapGesture { if preferences.value.clickToOpen { toggle() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white).tint(accent).preferredColorScheme(.dark)
        .allowsHitTesting(expandedPresentation == model.expanded)
        .disabled(model.paused || expandedPresentation != model.expanded)
        .contextMenu {
            if preferences.value.rightClickMenu {
                Button(model.expanded ? "Collapse" : "Open Nexa") { toggle() }
                Button("Settings…") { model.showSettings?() }
                Button(model.paused ? "Resume Nexa" : "Pause Nexa") { model.togglePause() }
                Divider(); Button("Quit Nexa") { NSApp.terminate(nil) }
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .image], isTargeted: $model.dropTarget, perform: acceptDrop)
        .background {
            if expandedPresentation && model.expanded { SharePicker(items: model.sharingItems, presented: $model.showShare).frame(width: 1, height: 1) }
        }
        .accessibilityIdentifier("nexa.notch")
    }
    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    headerTab(.home, label: "Nexa")
                    if preferences.value.enabledModules.contains(.files) { headerTab(.files, label: "Tray") }
                    Spacer(minLength: 0)
                }.padding(.leading, 27).frame(maxWidth: .infinity)
                if hasNotch { Color.clear.frame(width: cameraWidth).accessibilityHidden(true) }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(model.modules.filter { $0 != .home && $0 != .files }) { module in
                            Button { model.selected = module } label: { Label(module.title, systemImage: module.icon) }
                        }
                    } label: { Image(systemName: "square.grid.2x2").font(.system(size: 12)) }.menuStyle(.borderlessButton).fixedSize().help("All widgets")
                    IconButton(symbol: "gearshape.fill", help: "Open Settings", size: 24) { model.showSettings?() }
                    IconButton(symbol: "chevron.up", help: "Collapse Nexa", size: 24) { model.setExpanded?(false) }
                }.padding(.trailing, 27).frame(maxWidth: .infinity)
            }.frame(height: max(44, hardwareHeight + 7))
            ZStack(alignment: .top) {
                if model.selected == .home {
                    HomeView(model: model, preferences: preferences)
                        .frame(height: preferences.value.homeHeight - max(44, hardwareHeight + 7)).transition(.opacity)
                } else {
                    detailContent.id(model.selected)
                        .frame(height: preferences.value.expandedHeight - max(44, hardwareHeight + 7)).transition(.opacity)
                }
            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18 / max(0.5, min(2, preferences.value.animationSpeed))), value: model.selected)
        }
    }
    private var detailContent: some View {
        VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(model.modules.filter { $0 != .home && $0 != .files }) { module in
                        Button { model.selected = module } label: {
                            Image(systemName: module.icon).font(.system(size: 13, weight: model.selected == module ? .semibold : .regular))
                                .foregroundStyle(model.selected == module ? accent : .white.opacity(0.35)).frame(maxWidth: .infinity).frame(height: 32)
                                .background(model.selected == module ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(NotchButtonStyle()).help(module.title).accessibilityLabel(module.title).accessibilityIdentifier("module.\(module.rawValue)")
                    }
                }.padding(.horizontal, 29).padding(.top, 3).padding(.bottom, 9)
                ScrollView {
                    moduleContent.padding(.horizontal, 30).padding(.top, 7).padding(.bottom, 18)
                }.scrollIndicators(.hidden)
                HStack { Text(model.selected.title.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.5); Spacer(); if let banner = model.banner { Label(banner.title, systemImage: banner.icon).font(.system(size: 10)).foregroundStyle(accent) } }
                    .foregroundStyle(.white.opacity(0.3)).padding(.horizontal, 32).frame(height: 27)
        }
    }
    private func headerTab(_ module: ModuleID, label: String) -> some View {
        Button { model.selected = module } label: {
            HStack(spacing: 5) { Image(systemName: module == .home ? "waveform" : "tray"); Text(label) }
                .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(model.selected == module ? .white : .white.opacity(0.45))
                .background(model.selected == module ? .white.opacity(0.12) : .clear, in: Capsule())
        }.buttonStyle(NotchButtonStyle()).animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.selected).accessibilityIdentifier("module.\(module.rawValue)")
    }
    @ViewBuilder private var moduleContent: some View {
        switch model.selected {
        case .home: HomeView(model: model, preferences: preferences)
        case .mirror: MirrorView(service: model.mirror, preferences: preferences)
        case .notes: NotesView(service: model.notebook, accent: accent)
        case .todos: TodosView(service: model.notebook, accent: accent)
        case .shortcuts: ShortcutsView(service: model.shortcuts, accent: accent)
        case .music: NowPlayingView(service: model.media, controls: model.controls, preferences: preferences)
        case .files: FileShelfView(service: model.files, dropTarget: model.dropTarget, accent: accent)
        case .clipboard: ClipboardView(service: model.clipboard, preferences: preferences)
        case .calendar: CalendarModuleView(service: model.calendar, accent: accent)
        case .reminders: RemindersView(service: model.calendar, accent: accent)
        case .timers: TimersView(service: model.timers, accent: accent)
        case .controls: ControlsView(service: model.controls, accent: accent)
        case .system: SystemStatsView(service: model.system, accent: accent)
        case .bluetooth: BluetoothView(service: model.bluetooth)
        case .weather: WeatherView(service: model.weather, preferences: preferences, settings: { model.showSettings?() })
        case .ai: AIPanelView(service: model.ai, preferences: preferences)
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
    @ObservedObject var timers: TimerService
    @ObservedObject var system: SystemService
    let accent: Color
    let hasNotch: Bool
    let cameraWidth: CGFloat
    let paused: Bool
    let timerEnabled: Bool
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
            if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 5)) }
            else { Image(systemName: paused ? "pause" : "waveform").font(.system(size: 12)).foregroundStyle(accent) }
        }
    }
    private var trailingIndicator: some View {
        Group {
            if timers.running && timerEnabled { Circle().trim(from: 0, to: max(0.05, timers.progress)).stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 13, height: 13) }
            else if media.track.playing && !paused { PlaybackPulse(playing: true, accent: accent).frame(width: 18, height: 18) }
            else { Circle().fill(paused ? .gray : accent).frame(width: 5, height: 5) }
        }
    }
}
