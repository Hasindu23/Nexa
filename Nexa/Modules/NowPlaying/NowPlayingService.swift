import AppKit
import Combine

struct MediaTrack: Equatable {
    var title = "Nothing playing"
    var artist = "A little space for your soundtrack."
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var playing = false
    var playbackRate: Double = 1
    var appID = ""
    var artworkURL: URL?
    var artworkData: Data?
    var source: String {
        if appID == "com.spotify.client" { return "Spotify" }
        if appID == "com.apple.Music" { return "Apple Music" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) { return url.deletingPathExtension().lastPathComponent }
        return appID.isEmpty ? "Now Playing" : appID.split(separator: ".").last.map(String.init) ?? "Media"
    }
}

@MainActor final class NowPlayingService: ObservableObject, ModuleLifecycle {
    @Published private(set) var track = MediaTrack()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var sourceIcon: NSImage?
    @Published private(set) var sourceName = "Now Playing"
    private var artworkSourceID = ""
    @Published var error: String?
    @Published private(set) var connected = false
    @Published var preferredSource = "" { didSet { if preferredSource != oldValue { generation += 1; refresh() } } }
    @Published private(set) var systemAvailable = true
    private let bridge: MediaBridgeProtocol
    init(bridge: MediaBridgeProtocol? = nil) { self.bridge = bridge ?? SystemMediaBridge() }
    private var systemTrack: MediaTrack?
    private var systemDate = Date()
    private var usingSystem = false
    private var ticks = 0
    var sourceOptions: [(String, String)] {
        var choices = [("", "Follow current playback")]
        if let systemTrack { choices.append((systemTrack.appID, systemTrack.source)) }
        for id in ["com.apple.Music", "com.spotify.client"] where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty && !choices.contains(where: { $0.0 == id }) {
            var value = MediaTrack(); value.appID = id; choices.append((id, value.source))
        }
        return choices
    }
    private var observers: [NSObjectProtocol] = []
    private var ticker: Timer?
    private var busy = false
    private var generation = 0
    private let queue = DispatchQueue(label: "app.nexa.media", qos: .utility)
    private var artworkTask: Task<Void, Never>?
    var allowNetwork = false {
        didSet {
            guard allowNetwork != oldValue else { return }
            if allowNetwork && connected { loadArtwork() }
            else { artworkTask?.cancel() }
        }
    }
    var visible = false { didSet { if visible != oldValue { scheduleTimer() } } }
    var demo = false
    func start() {
        guard !connected else { return }; connected = true
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        bridge.onTrack = { [weak self] track in
            guard let self, self.connected else { return }
            if !self.systemAvailable { self.systemAvailable = true }; self.systemTrack = track; self.systemDate = Date(); self.refresh()
        }
        bridge.onFailure = { [weak self] in guard let self, self.connected else { return }; self.systemAvailable = false; self.systemTrack = nil; self.refresh() }
        bridge.start(); scheduleTimer()
    }
    func stop() {
        bridge.stop(); systemTrack = nil; usingSystem = false
        connected = false; generation += 1; ticker?.invalidate(); ticker = nil; artworkTask?.cancel()
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }; observers.removeAll()
        apply(MediaTrack())
    }
    private func scheduleTimer() {
        ticker?.invalidate(); ticker = nil
        guard connected && visible && !demo else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.ticks += 1
            if self.usingSystem || self.ticks % 3 == 0 { self.refresh() }
        } }
        timer.tolerance = 0.15; RunLoop.main.add(timer, forMode: .common); ticker = timer
    }
    func refresh() {
        guard connected, !demo else { return }
        if var current = systemTrack, preferredSource.isEmpty || preferredSource == current.appID {
            usingSystem = true
            if current.playing {
                current.position += max(0, Date().timeIntervalSince(systemDate)) * current.playbackRate
                if current.duration > 0 { current.position = min(current.duration, current.position) }
            }
            apply(current)
            if error != nil { error = nil }
            return
        }
        usingSystem = false
        guard !busy else { return }
        let applications = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let ids = ["com.spotify.client", "com.apple.Music"].filter { applications.contains($0) && (preferredSource.isEmpty || preferredSource == $0) }
        guard !ids.isEmpty else { apply(MediaTrack()); return }
        busy = true
        let requestGeneration = generation
        queue.async { [weak self] in
            var best: MediaTrack?
            var message: String?
            for id in ids {
                let spotify = id == "com.spotify.client"
                let artworkExpression = spotify ? "artwork url of current track" : "\"\""
                let source = """
                with timeout of 3 seconds
                    tell application id "\(id)"
                        if player state is stopped then return {}
                        return {name of current track, artist of current track, album of current track, duration of current track, player position, (player state is playing), \(artworkExpression)}
                    end tell
                end timeout
                """
                var scriptError: NSDictionary?
                guard let result = NSAppleScript(source: source)?.executeAndReturnError(&scriptError), scriptError == nil else {
                    message = "Allow Nexa to control Music or Spotify in System Settings → Privacy & Security → Automation."
                    continue
                }
                guard result.numberOfItems >= 6 else { continue }
                var value = MediaTrack()
                value.title = result.atIndex(1)?.stringValue ?? "Unknown track"
                value.artist = result.atIndex(2)?.stringValue ?? "Unknown artist"
                value.album = result.atIndex(3)?.stringValue ?? ""
                // Spotify reports milliseconds despite the wording in its scripting dictionary.
                value.duration = (result.atIndex(4)?.doubleValue ?? 0) / (spotify ? 1000 : 1)
                value.position = result.atIndex(5)?.doubleValue ?? 0
                value.playing = result.atIndex(6)?.booleanValue ?? false
                value.appID = id
                if spotify { value.artworkURL = result.atIndex(7)?.stringValue.flatMap(URL.init(string:)) }
                else {
                    var artworkError: NSDictionary?
                    value.artworkData = NSAppleScript(source: "with timeout of 2 seconds\n tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track\nend timeout")?.executeAndReturnError(&artworkError).data
                }
                if best == nil || value.playing { best = value }
                if value.playing { break }
            }
            let finished = best ?? MediaTrack(); let finalMessage = message
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                guard self.connected else { return }
                guard requestGeneration == self.generation else { self.refresh(); return }
                guard !self.usingSystem else { return }
                self.apply(finished); self.error = best == nil ? finalMessage : nil
            }
        }
    }
    func command(_ command: String) {
        guard ["playpause", "next track", "previous track"].contains(command), !track.appID.isEmpty, !demo else { return }
        if usingSystem {
            let code = command == "playpause" ? 2 : command == "next track" ? 4 : 5
            bridge.send(["send", String(code)]) { [weak self] success in if !success { self?.error = "This player did not accept the control." } }
            return
        }
        let id = track.appID
        queue.async { [weak self] in
            var error: NSDictionary?
            _ = NSAppleScript(source: "with timeout of 3 seconds\n tell application id \"\(id)\" to \(command)\nend timeout")?.executeAndReturnError(&error)
            let failed = error != nil
            DispatchQueue.main.async { if failed { self?.error = "Playback control was denied." } else { self?.refresh() } }
        }
    }
    func seek(_ seconds: Double) {
        guard !demo, seconds.isFinite, track.duration > 0 else { return }
        let position = min(track.duration, max(0, seconds))
        if usingSystem { bridge.send(["seek", String(Int64(position * 1_000_000))]) { [weak self] success in if !success { self?.error = "Seeking is unavailable for this player." } } }
        else if ["com.apple.Music", "com.spotify.client"].contains(track.appID) {
            let id = track.appID
            queue.async { _ = NSAppleScript(source: "with timeout of 3 seconds\n tell application id \"\(id)\" to set player position to \(position)\nend timeout")?.executeAndReturnError(nil) }
        }
    }
    func skip(_ seconds: Double) { seek(track.position + seconds) }
    private func apply(_ current: MediaTrack) {
        let artworkChanged = track.artworkData != current.artworkData || track.artworkURL != current.artworkURL || track.appID != current.appID
        if track != current { track = current }
        if artworkChanged { loadArtwork() }
    }
    private func loadArtwork() {
        artworkTask?.cancel(); artworkTask = nil
        if artworkSourceID != track.appID {
            artworkSourceID = track.appID
            sourceName = track.source
            sourceIcon = track.appID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.appID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        if let data = track.artworkData, let image = NSImage(data: data) { artwork = image; return }
        guard allowNetwork, let url = track.artworkURL, url.scheme == "https" else { artwork = nil; return }
        artwork = nil
        artworkTask = Task { [weak self] in
            do {
                let (data, response) = try await NetworkClient.session.data(from: url)
                guard !Task.isCancelled, data.count < 8_000_000, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                self?.artwork = NSImage(data: data)
            } catch { /* Artwork is optional; playback remains usable offline. */ }
        }
    }
    func loadDemo(playing: Bool = false) {
        demo = true
        track = MediaTrack(title: "A quieter kind of focus", artist: "Nexa Sessions · Interface preview", album: "Still", duration: 248, position: 87, playing: playing, appID: "com.apple.Music")
        sourceName = "Apple Music"
    }
}
