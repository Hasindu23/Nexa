import SwiftUI
import QuartzCore

struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    @Environment(\.nexaMotion) private var motion
    @State private var availableWidth: CGFloat = 680
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your Mac. In the moment.").font(.system(size: 25, weight: .medium)).tracking(-0.6)
                    Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day()).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
                }
                Spacer()
                if model.editingWorkspace {
                    Menu("Add widget") {
                        ForEach(model.modules.filter { ![ModuleID.home, .ai, .storage, .reminders, .controls, .clipboard, .weather, .bluetooth, .files].contains($0) && !preferences.value.homeWidgets.map(\.module).contains($0) }) { module in
                            Button(module.title) { if preferences.value.homeWidgets.count < 8 { preferences.value.homeWidgets.append(HomeWidget(module: module)) } }
                        }
                    }.disabled(preferences.value.homeWidgets.count >= 8)
                    Button("Reset") { preferences.value.homeWidgets = HomeWidget.defaults }
                }
            }
            if model.editingWorkspace { Text("Drag widgets to reorder. Choose Compact, Regular or Wide from a widget’s menu. Up to eight widgets.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary) }
            let widgets = preferences.value.homeWidgets.filter { preferences.value.enabledModules.contains($0.module) }
            let columns = availableWidth < 520 ? 1 : availableWidth >= 760 ? 3 : 2
            let rows = HomeWidgetGrid.rows(widgets, columns: columns)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { widget in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(widget.module.title.uppercased(), systemImage: widget.module.icon).font(.system(size: 9, weight: .semibold)).tracking(0.7).foregroundStyle(accent)
                                Spacer()
                                if model.editingWorkspace {
                                    Menu {
                                        ForEach(HomeWidget.Size.allCases, id: \.self) { size in Button(size.rawValue.capitalized) { if let index = preferences.value.homeWidgets.firstIndex(where: { $0.id == widget.id }) { preferences.value.homeWidgets[index].size = size } } }
                                        Button("Hide widget") { preferences.value.homeWidgets.removeAll { $0.id == widget.id } }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                } else { Button { model.selected = widget.module } label: { Image(systemName: "arrow.up.right").font(.system(size: 9)) }.buttonStyle(.plain).help("Open \(widget.module.title)") }
                            }
                            widgetContent(widget)
                        }.padding(15).frame(maxWidth: .infinity, minHeight: row.allSatisfy { $0.size == .compact } ? 100 : 132, alignment: .topLeading)
                            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
                            .onDrag { WorkspaceDrag.provider(widget.module, type: WorkspaceDrag.widgetType) }
                            .onDrop(of: [WorkspaceDrag.widgetType], isTargeted: nil) { providers in
                                guard model.editingWorkspace else { return false }
                                return WorkspaceDrag.read(providers, type: WorkspaceDrag.widgetType) { source in
                                    let ids = WorkspaceLayout.move(source, before: widget.module, in: preferences.value.homeWidgets.map(\.module))
                                    preferences.value.homeWidgets = ids.compactMap { id in preferences.value.homeWidgets.first(where: { $0.module == id }) }
                                }
                            }
                    }
                }
            }
            if widgets.isEmpty { EmptyModule(icon: "square.grid.2x2", title: "Make this space yours", detail: "Choose Edit Workspace to add your first widget.") }
        }.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
    @ViewBuilder private func widgetContent(_ widget: HomeWidget) -> some View {
        switch widget.module {
        case .music: CompactMediaView(service: model.media, preferences: preferences, enabled: true, compact: widget.size != .wide) { model.selected = .music }
        case .system: HomeMetrics(service: model.system)
        case .calendar: HomeCalendar(service: model.calendar, enabled: true, accent: accent) { model.selected = .calendar }
        case .timers: HomeTimer(service: model.timers, enabled: true, accent: accent) { model.selected = .timers }
        case .todos, .notes: HomeNotes(service: model.notebook, todos: widget.module == .todos, accent: accent) { model.selected = widget.module }
        case .shortcuts: HomeShortcuts(service: model.shortcuts, enabled: true, accent: accent) { model.selected = .shortcuts }
        case .mirror: Button("Open Mirror") { model.selected = .mirror }.buttonStyle(CapsuleButtonStyle(accent: accent))
        case .live: HomeActivity(service: model.live)
        default: Button("Open \(widget.module.title)") { model.selected = widget.module }
        }
    }
}

struct HomeWidgetGrid {
    static func rows(_ widgets: [HomeWidget], columns: Int) -> [[HomeWidget]] {
        var rows: [[HomeWidget]] = [], row: [HomeWidget] = []
        for widget in widgets.prefix(8) {
            if widget.size == .wide {
                if !row.isEmpty { rows.append(row); row = [] }
                rows.append([widget])
            } else {
                row.append(widget)
                if row.count >= max(1, columns) { rows.append(row); row = [] }
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

private struct HomeMetrics: View {
    @ObservedObject var service: SystemService
    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 6) { Text(service.cpuAvailable ? String(format: "%.0f%%", service.cpu) : "—").font(.system(size: 27, weight: .light)).monospacedDigit(); Text("CPU").font(.system(size: 9)).foregroundStyle(NexaStyle.secondary) }
            VStack(alignment: .leading, spacing: 6) { Text(service.memoryAvailable ? String(format: "%.0f%%", service.memory) : "—").font(.system(size: 27, weight: .light)).monospacedDigit(); Text("MEMORY IN USE").font(.system(size: 9)).foregroundStyle(NexaStyle.secondary) }
        }
        Text(service.battery.map { "Battery \($0)%" } ?? "\(service.freeStorage) available").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
    }
}
private struct HomeActivity: View {
    @ObservedObject var service: LiveActivityStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.items.first?.title ?? "All quiet").font(.system(size: 15, weight: .medium))
            Text(service.items.first?.detail ?? "Your next Nexa activity will appear here.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineLimit(3)
        }
    }
}

struct CompactMediaView: View {
    @ObservedObject var service: NowPlayingService
    @ObservedObject var preferences: PreferencesStore
    let enabled: Bool
    var compact = false
    var open: () -> Void
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        HStack(spacing: 13) {
            Button(action: open) {
                MediaArtwork(service: service, accent: accent).frame(width: compact ? 56 : preferences.value.layout == "Compact" ? 80 : 98, height: compact ? 76 : preferences.value.layout == "Compact" ? 92 : 110)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomTrailing) {
                        if let icon = service.sourceIcon {
                            Image(nsImage: icon).resizable().frame(width: 23, height: 23).padding(3).background(.black, in: RoundedRectangle(cornerRadius: 8)).offset(x: 4, y: 4)
                        }
                    }
            }.buttonStyle(NotchButtonStyle()).help("Open Now Playing")
            VStack(alignment: .leading, spacing: 6) {
                if service.track.appID.isEmpty {
                    Text("Your soundtrack,\nright here.").font(.system(size: 15, weight: .semibold)).tracking(-0.3)
                    Text(enabled ? "Apps. Videos. Music." : "Enable Now Playing in Settings.").font(.system(size: 10)).foregroundStyle(.gray)
                    Button(service.connected ? "Now Playing" : "Connect media") { if service.connected { open() } else { preferences.value.mediaConnected = true } }.font(.system(size: 10, weight: .semibold)).buttonStyle(CapsuleButtonStyle(accent: accent)).disabled(!enabled).padding(.top, 3)
                } else {
                    Button(action: open) { Text(service.track.title).font(.system(size: 14, weight: .semibold)).tracking(-0.3).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    Text(service.track.artist.isEmpty ? service.sourceName : service.track.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    HStack(spacing: 8) {
                        transport("backward.end.fill", "Previous", "previous track")
                        transport(service.track.playing ? "pause.fill" : "play.fill", service.track.playing ? "Pause" : "Play", "playpause")
                        transport("forward.end.fill", "Next", "next track")
                        Spacer(minLength: 0)
                        PlaybackPulse(playing: service.track.playing, preferences: preferences).frame(width: 19, height: 16)
                    }.padding(.top, 2)
                    if !compact && service.track.duration > 0 { MediaScrubber(service: service, accent: accent, labels: false).padding(.top, 2) }
                    if service.demo && !compact { Text("INTERFACE PREVIEW").font(.system(size: 6, weight: .semibold)).tracking(1).foregroundStyle(.gray) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func transport(_ icon: String, _ title: String, _ command: String) -> some View {
        Button { service.command(command) } label: { Image(systemName: icon).font(.system(size: 12)).frame(width: 22, height: 24) }.buttonStyle(NotchButtonStyle()).help(title).accessibilityLabel(title).disabled(service.demo)
    }
}

struct MediaArtwork: View {
    @ObservedObject var service: NowPlayingService
    let accent: Color
    var body: some View {
        ZStack {
            if let artwork = service.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
            else {
                LinearGradient(colors: [accent.opacity(0.3), Color(red: 0.06, green: 0.11, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(accent.opacity(0.15), lineWidth: 1).padding(14)
                Circle().stroke(accent.opacity(0.1), lineWidth: 1).padding(24)
                Image(systemName: "waveform").font(.system(size: 27, weight: .light)).foregroundStyle(accent)
            }
        }.clipped()
    }
}

struct MediaScrubber: View {
    @ObservedObject var service: NowPlayingService
    let accent: Color
    var labels = true
    @State private var dragging: Double?
    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { dragging ?? service.track.position }, set: { dragging = $0 }), in: 0...max(1, service.track.duration), onEditingChanged: { editing in if !editing, let position = dragging { service.seek(position); dragging = nil } })
                .controlSize(.mini).tint(accent).disabled(service.demo || service.track.duration <= 0).accessibilityLabel("Playback position")
            if labels { HStack { Text((dragging ?? service.track.position).clockString); Spacer(); Text(service.track.duration.clockString) }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray) }
        }
    }
}

private struct HomeCalendar: View {
    @ObservedObject var service: CalendarService
    let enabled: Bool
    let accent: Color
    var open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            let today = Date()
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(today.formatted(.dateTime.month(.abbreviated))).font(.system(size: 21, weight: .semibold)); Text(today.formatted(.dateTime.day())).font(.system(size: 21, weight: .semibold)).foregroundStyle(accent) }
            HStack(spacing: 0) {
                ForEach(0..<7) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index, to: Calendar.current.startOfDay(for: today)) ?? today
                    VStack(spacing: 4) { Text(date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 7, weight: .medium)); Text(date.formatted(.dateTime.day())).font(.system(size: 10, weight: .semibold)) }.foregroundStyle(index == 0 ? accent : .white.opacity(0.35)).frame(maxWidth: .infinity)
                }
            }
            Button { if !service.calendarAccess && enabled { Task { await service.requestCalendar() } } else if enabled { open() } } label: {
                HStack(spacing: 5) { Image(systemName: "calendar"); Text(!enabled ? "Calendar is off" : !service.calendarAccess ? "Connect calendar" : service.events.first?.title ?? "Nothing coming up").lineLimit(1) }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }.buttonStyle(.plain).padding(.top, 2).disabled(!enabled)
        }
    }
}

private struct HomeShortcuts: View {
    @ObservedObject var service: ShortcutsService
    let enabled: Bool
    let accent: Color
    var open: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            if service.favorites.isEmpty || !enabled { Button(action: open) { Label("Choose shortcuts", systemImage: "sparkles").font(.system(size: 11)).frame(maxWidth: .infinity).padding(.vertical, 14).background(.white.opacity(0.09), in: Capsule()) }.buttonStyle(.plain).disabled(!enabled) }
            ForEach(Array(service.favorites.prefix(2)), id: \.self) { name in
                Button { service.run(name) } label: { HStack(spacing: 6) { Image(systemName: "sparkles").foregroundStyle(accent); Text(service.running == name ? "Running…" : name).lineLimit(1) }.font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 13).background(.white.opacity(0.09), in: Capsule()) }.buttonStyle(.plain).disabled(service.running != nil || !enabled)
            }
        }
    }
}

private struct HomeNotes: View {
    @ObservedObject var service: NotebookService
    let todos: Bool
    let accent: Color
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: todos ? "checkmark.circle" : "note.text").font(.system(size: 22, weight: .light)).foregroundStyle(accent)
                Text(todos ? service.tasks.first(where: { $0.completedAt == nil })?.title ?? "One small next step." : service.notes.first(where: { $0.pinned })?.text ?? service.notes.first?.text ?? "A thought for later.").font(.system(size: 11)).lineLimit(3).multilineTextAlignment(.leading)
                Text(todos ? "OPEN TO-DOS" : "OPEN NOTES").font(.system(size: 7, weight: .semibold)).tracking(1).foregroundStyle(.gray)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }
}

private struct HomeTimer: View {
    @ObservedObject var service: TimerService
    let enabled: Bool
    let accent: Color
    var open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.remaining.clockString).font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(accent)
            HStack { Button(service.running ? "Pause" : "Start 25 min") { if service.running { service.toggle() } else { service.startTimer(seconds: 25 * 60) } }.disabled(!enabled); Button("Open", action: open) }.font(.system(size: 10))
        }
    }
}

struct NotchSilhouette: Shape {
    var radius: CGFloat
    var shoulder: CGFloat
    var detached = false
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, shoulder) }
        set { radius = newValue.first; shoulder = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.height / 3), r = min(radius, (rect.height - s) / 2), w = rect.width, h = rect.height
        if detached {
            // A display without a cutout gets a floating panel, rounded on all
            // four corners. Keep the same segment structure while it morphs.
            return Path { p in
                p.move(to: CGPoint(x: r, y: 0)); p.addLine(to: CGPoint(x: w - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: h - r))
                p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: r, y: h))
                p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero); p.closeSubpath()
            }
        }
        return Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: 0))
            p.addQuadCurve(to: CGPoint(x: w - s, y: s), control: CGPoint(x: w - s, y: 0))
            p.addLine(to: CGPoint(x: w - s, y: h - r))
            p.addQuadCurve(to: CGPoint(x: w - s - r, y: h), control: CGPoint(x: w - s, y: h))
            p.addLine(to: CGPoint(x: s + r, y: h))
            p.addQuadCurve(to: CGPoint(x: s, y: h - r), control: CGPoint(x: s, y: h))
            p.addLine(to: CGPoint(x: s, y: s))
            p.addQuadCurve(to: .zero, control: CGPoint(x: s, y: 0)); p.closeSubpath()
        }
    }
}
