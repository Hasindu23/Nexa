import Foundation

/// Local, event-driven Now Playing bridge. The vendored BSD adapter runs in a
/// separate process; it never reads browser pages, records audio, or uses a port.
@MainActor protocol MediaBridgeProtocol: AnyObject {
    var onTrack: ((MediaTrack?) -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    func start()
    func stop()
    func send(_ command: [String], completion: @escaping (Bool) -> Void)
}

@MainActor final class SystemMediaBridge: MediaBridgeProtocol {
    var onTrack: ((MediaTrack?) -> Void)?
    var onFailure: (() -> Void)?
    private var process: Process?
    private var commands: [UUID: Process] = [:]
    private var reader: MediaLineReader?
    private var generation = 0
    private var arguments: [String]? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        return [script.path, frameworks.appendingPathComponent("MediaRemoteAdapter.framework").path]
    }
    func start() {
        guard process == nil else { return }
        guard let arguments else { onFailure?(); return }
        generation += 1; let token = generation
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = arguments + ["stream", "--no-diff", "--micros", "--debounce=100", "--allow-missing-title"]
        task.standardOutput = output; task.standardError = FileHandle.nullDevice
        let reader = MediaLineReader { [weak self] track in
            Task { @MainActor in
                guard let self, token == self.generation else { return }
                self.onTrack?(track)
            }
        }
        self.reader = reader
        output.fileHandleForReading.readabilityHandler = { handle in reader.receive(handle.availableData) }
        task.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, token == self.generation else { return }
                self.process = nil; self.reader = nil; self.onFailure?()
            }
        }
        do { try task.run(); process = task } catch { output.fileHandleForReading.readabilityHandler = nil; self.reader = nil; onFailure?() }
    }
    func stop() {
        generation += 1
        if let pipe = process?.standardOutput as? Pipe { pipe.fileHandleForReading.readabilityHandler = nil }
        process?.terminate(); process = nil; reader = nil
        commands.values.forEach { if $0.isRunning { $0.terminate() } }; commands.removeAll()
    }
    func send(_ command: [String], completion: @escaping (Bool) -> Void) {
        guard let arguments else { completion(false); return }
        let task = Process(), id = UUID()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl"); task.arguments = arguments + command
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] process in Task { @MainActor in self?.commands[id] = nil; completion(process.terminationStatus == 0) } }
        do {
            try task.run(); commands[id] = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in if let process = self?.commands[id], process.isRunning { process.terminate() } }
        } catch { completion(false) }
    }
    nonisolated static func decode(_ payload: [String: Any], now: Date = Date()) -> MediaTrack? {
        guard let rawID = payload["bundleIdentifier"] as? String, !rawID.isEmpty else { return nil }
        let id = (payload["parentApplicationBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? rawID
        var track = MediaTrack()
        track.appID = id
        track.title = (payload["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Now playing"
        track.artist = payload["artist"] as? String ?? ""
        track.album = payload["album"] as? String ?? ""
        track.playing = payload["playing"] as? Bool ?? false
        func seconds(_ key: String) -> Double {
            let number = (payload[key] as? NSNumber)?.doubleValue ?? 0
            return number.isFinite ? max(0, number / 1_000_000) : 0
        }
        track.duration = seconds("durationMicros")
        let elapsed = seconds("elapsedTimeMicros"), timestamp = seconds("timestampEpochMicros")
        let rate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        track.playbackRate = rate.isFinite ? max(0, rate) : 1
        let delta = track.playing && timestamp > 0 && rate.isFinite ? max(0, now.timeIntervalSince1970 - timestamp) * max(0, rate) : 0
        track.position = track.duration > 0 ? min(track.duration, elapsed + delta) : elapsed + delta
        if let base64 = payload["artworkData"] as? String, base64.utf8.count < 12_000_000 { track.artworkData = Data(base64Encoded: base64) }
        return track
    }
}

private final class MediaLineReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.nexa.media.lines", qos: .utility)
    private var buffer = Data()
    private let emit: (MediaTrack?) -> Void
    init(emit: @escaping (MediaTrack?) -> Void) { self.emit = emit }
    func receive(_ data: Data) {
        queue.async {
            self.buffer.append(data)
            guard self.buffer.count < 20_000_000 else { self.buffer.removeAll(); return }
            while let newline = self.buffer.firstIndex(of: 10) {
                let line = Data(self.buffer[..<newline]); self.buffer.removeSubrange(...newline)
                // JSON and base64 artwork decoding can be large. Keep both off
                // the main run loop so media events do not interrupt the notch.
                guard let envelope = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let payload = envelope["payload"] as? [String: Any] else { continue }
                self.emit(SystemMediaBridge.decode(payload))
            }
        }
    }
}
