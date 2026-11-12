import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var service: NowPlayingService
    @ObservedObject var controls: QuickControlsService
    @ObservedObject var preferences: PreferencesStore
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(service.track.appID.isEmpty ? "GOOD TO HAVE YOU HERE" : service.demo ? "INTERFACE PREVIEW" : service.sourceName.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(accent)
                Spacer()
                if service.connected {
                    Menu { ForEach(service.sourceOptions, id: \.0) { choice in Button(choice.1) { service.preferredSource = choice.0 } } } label: { Label("Source", systemImage: "airplay.audio") }.menuStyle(.borderlessButton).fixedSize()
                    Button { service.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }.buttonStyle(.plain).help("Refresh Now Playing") }
            }
            HStack(spacing: 22) {
                artwork
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.track.appID.isEmpty ? "Your soundtrack.\nA little closer." : service.track.title).font(.system(size: service.track.appID.isEmpty ? 25 : 22, weight: .medium)).tracking(-0.7).lineLimit(2)
                    Text(service.track.artist).font(.system(size: 12)).foregroundStyle(NexaStyle.secondary).lineLimit(2)
                    if service.track.appID.isEmpty {
                        Button(service.connected ? "Open Music" : "Connect media") {
                            if service.connected { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } }
                            else { preferences.value.mediaConnected = true }
                        }.buttonStyle(CapsuleButtonStyle(accent: accent)).padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !service.track.appID.isEmpty {
                HStack(spacing: 12) {
                    PlaybackPulse(playing: service.track.playing, preferences: preferences).frame(width: 108, height: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ELECTRIC BLUE").font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(Color(ElectricBluePalette.waveform))
                        Text("Decorative playback animation").font(.system(size: 9)).foregroundStyle(NexaStyle.secondary)
                    }
                    Spacer()
                }.padding(.vertical, 3)
                MediaScrubber(service: service, accent: accent)
                HStack {
                    Image(systemName: "speaker.wave.1").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
                    Slider(value: Binding(get: { controls.volume }, set: { controls.setVolume($0) }), in: 0...1).frame(width: 75).controlSize(.mini).disabled(!controls.volumeAvailable)
                    Spacer()
                    IconButton(symbol: "backward.end.fill", help: "Previous track", size: 30) { service.command("previous track") }
                    Button { service.command("playpause") } label: { Image(systemName: service.track.playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(.black).frame(width: 42, height: 42).background(accent, in: Circle()) }.buttonStyle(NotchButtonStyle()).accessibilityLabel(service.track.playing ? "Pause" : "Play")
                    IconButton(symbol: "forward.end.fill", help: "Next track", size: 30) { service.command("next track") }
                    Spacer()
                    Text(service.demo ? "DEMO" : service.track.playing ? "PLAYING" : "PAUSED").font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(NexaStyle.secondary).frame(width: 90, alignment: .trailing)
                }.disabled(service.demo)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(accent.opacity(0.8))
                    Text("Permission is yours to give. Connect when you’re ready.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if service.connected && !service.systemAvailable { Text("System media is unavailable. Music and Spotify fallback is active.").font(.system(size: 10)).foregroundStyle(.orange) }
            InlineError(text: service.error)
        }
    }
    private var artwork: some View {
        ZStack {
            if let artwork = service.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
            else {
                LinearGradient(colors: [Color(ElectricBluePalette.royal).opacity(0.5), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(accent.opacity(0.12), lineWidth: 1).frame(width: 112).offset(x: 28, y: -25)
                Circle().stroke(accent.opacity(0.18), lineWidth: 1).frame(width: 86).offset(x: 28, y: -25)
                Circle().stroke(accent.opacity(0.3), lineWidth: 1).frame(width: 60).offset(x: 28, y: -25)
                Image(systemName: "waveform").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(accent).offset(y: 9)
                VStack { Spacer(); HStack { Text("N / 01").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(2); Spacer() }.padding(12) }.foregroundStyle(accent.opacity(0.5))
            }
        }.frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.07)))
    }
}
