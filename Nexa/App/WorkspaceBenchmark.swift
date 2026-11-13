import AppKit
import Darwin

extension AppDelegate {
    /// Isolated, deterministic UI scenarios: no network, capture or cleanup actions.
    func runWorkspaceBenchmark(output: URL) {
        let suite = "app.nexa.benchmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: scratch), testing: true)
        model.preferences.value.hapticFeedback = false
        setup(); notch.pinnedOpen = true
        Task { @MainActor [self] in
            var rows: [[String: Any]] = []
            let modes = ["collapsed", "peek", "workspace", "music-paused", "visualizer-playing", "drag-target", "ai-workspace", "calendar", "switching"]
            for mode in modes {
                model.media.loadDemo(playing: mode == "visualizer-playing")
                model.dropTarget = false; model.banner = nil
                notch.expand(mode != "collapsed")
                if mode == "peek" { notch.present(.peek) }
                model.selected = mode == "music-paused" || mode == "visualizer-playing" ? .music : mode == "drag-target" ? .files : mode == "ai-workspace" ? .ai : mode == "calendar" ? .calendar : .home
                if mode == "drag-target" { model.dropTarget = true }
                notch.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(for: .seconds(2))
                var switching: Timer?
                if mode == "switching" {
                    var index = 0
                    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.model.selected = [ModuleID.home, .music, .calendar, .files][index % 4]; index += 1 }
                    }
                    RunLoop.main.add(timer, forMode: .common); switching = timer
                }
                let started = ProcessInfo.processInfo.systemUptime, cpu = Self.workspaceCPUTime(), memory = MemorySnapshot.footprint(pid: getpid())
                try? await Task.sleep(for: .seconds(12))
                let elapsed = ProcessInfo.processInfo.systemUptime - started, cpuEnd = Self.workspaceCPUTime()
                switching?.invalidate()
                var row: [String: Any] = ["scenario": mode, "seconds": elapsed, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"]
                if let cpu, let cpuEnd { row["cpuPercentOfOneCore"] = (cpuEnd - cpu) / elapsed * 100 }
                if let memory { row["footprintStartBytes"] = memory }
                if let end = MemorySnapshot.footprint(pid: getpid()) { row["footprintEndBytes"] = end }
                row["windowVisible"] = notch.window?.occlusionState.contains(.visible) == true
                row["visualizerRepeatingAnimations"] = notch.window?.contentView.map { Self.fluidRenderers(in: $0).reduce(0) { $0 + $1.repeatingAnimationCount } } ?? 0
                row["scope"] = "Isolated UI; sample media, no connected AI session, no real drag or network activity. Not display FPS."
                rows.append(row)
                if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output) }
            }
            model.shutdown(); defaults.removeObject(forKey: "preferences.v1"); try? FileManager.default.removeItem(at: scratch); NSApp.terminate(nil)
        }
    }
    private static func workspaceCPUTime() -> Double? {
        var usage = rusage(); guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
