import SwiftUI
import QuartzCore

struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    @Environment(\.nexaMotion) private var motion
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        GeometryReader { geometry in
            let mirrorWidth: CGFloat = preferences.value.layout == "Compact" ? 92 : 108
            let flexible = geometry.size.width - mirrorWidth - 54
            HStack(spacing: 13) {
                CompactMediaView(service: model.media, preferences: preferences, enabled: preferences.value.enabledModules.contains(.music)) { model.selected = .music }
                    .frame(width: flexible * 0.62)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 9) {
                    Menu {
                        ForEach(["Calendar", "Shortcuts", "Notes", "To-dos", "Timer"], id: \.self) { name in Button(name) { preferences.value.centerWidget = name } }
                    } label: { HStack(spacing: 5) { Text(preferences.value.centerWidget.uppercased()).tracking(1.4); Image(systemName: "chevron.down").font(.system(size: 7)) }.font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.4)) }.menuStyle(.borderlessButton).fixedSize()
                    ZStack(alignment: .topLeading) { centerWidget.id(preferences.value.centerWidget).transition(.opacity) }
                        .animation(motion.moduleAnimation, value: preferences.value.centerWidget)
                }.frame(width: flexible * 0.38, alignment: .topLeading)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(.vertical, 6)
                if preferences.value.enabledModules.contains(.mirror) { MirrorWidget(service: model.mirror, preferences: preferences, size: mirrorWidth - 6).frame(width: mirrorWidth) }
                else { Button { model.showSettings?() } label: { Label("Widgets", systemImage: "square.grid.2x2").font(.system(size: 11)).foregroundStyle(.gray) }.buttonStyle(.plain).frame(width: mirrorWidth) }
            }.frame(maxHeight: .infinity, alignment: .center)
        }.padding(.horizontal, 30).padding(.top, 4).padding(.bottom, 19)
    }
    @ViewBuilder private var centerWidget: some View {
        switch preferences.value.centerWidget {
        case "Shortcuts": HomeShortcuts(service: model.shortcuts, enabled: preferences.value.enabledModules.contains(.shortcuts), accent: accent) { model.selected = .shortcuts }
        case "Notes": HomeNotes(service: model.notebook, todos: false, accent: accent) { model.selected = .notes }
        case "To-dos": HomeNotes(service: model.notebook, todos: true, accent: accent) { model.selected = .todos }
        case "Timer": HomeTimer(service: model.timers, enabled: preferences.value.enabledModules.contains(.timers), accent: accent) { model.selected = .timers }
        default: HomeCalendar(service: model.calendar, enabled: preferences.value.enabledModules.contains(.calendar), accent: accent) { model.selected = .calendar }
        }
    }
}

struct CompactMediaView: View {
    @ObservedObject var service: NowPlayingService
    @ObservedObject var preferences: PreferencesStore
    let enabled: Bool
    var open: () -> Void
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        HStack(spacing: 13) {
            Button(action: open) {
                MediaArtwork(service: service, accent: accent).frame(width: preferences.value.layout == "Compact" ? 80 : 98, height: preferences.value.layout == "Compact" ? 92 : 110)
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
                    if service.track.duration > 0 { MediaScrubber(service: service, accent: accent, labels: false).padding(.top, 2) }
                    if service.demo { Text("INTERFACE PREVIEW").font(.system(size: 6, weight: .semibold)).tracking(1).foregroundStyle(.gray) }
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
