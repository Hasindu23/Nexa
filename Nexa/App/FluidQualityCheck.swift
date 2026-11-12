import AppKit
import SwiftUI
import Darwin

extension AppDelegate {
    /// Uses a disposable preferences suite and sample media; never controls a player's audio.
    func runFluidQA(output: URL) {
        let suite = "app.nexa.qa.fluid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: scratch), testing: true)
        model.preferences.value.completedOnboarding = true
        model.preferences.value.hapticFeedback = false
        setup(); notch.pinnedOpen = true
        Task { @MainActor in
            var checks: [String] = []
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                model.media.loadDemo(playing: true)
                model.selected = .music; notch.expand(true)
                notch.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .milliseconds(650))
                try verifyNotchPlacement()
                let renderers = Self.fluidRenderers(in: notch.window!.contentView!)
                guard !renderers.isEmpty else { throw NexaError.message("Now Playing has no native visualizer") }
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    guard renderers.contains(where: { $0.repeatingAnimationCount > 0 }) else { throw NexaError.message("Visible playing visualizer did not animate") }
                }
                for style in VisualizerStyle.allCases {
                    model.preferences.value.visualizerStyle = style
                    try await Task.sleep(for: .milliseconds(450))
                    try snapshot(notch.window!, to: output.appendingPathComponent("visualizer-\(style.rawValue).png"))
                }
                checks.append("PASS: Bars, Wave and Minimal render in the native Now Playing module with labeled sample media")
                model.media.loadDemo(playing: false)
                try await Task.sleep(for: .milliseconds(300))
                guard Self.fluidRenderers(in: notch.window!.contentView!).allSatisfy({ $0.repeatingAnimationCount == 0 }) else { throw NexaError.message("Paused visualizer still has repeating animations") }
                model.media.loadDemo(playing: true); model.preferences.value.energySaving = true
                try await Task.sleep(for: .milliseconds(300))
                guard Self.fluidRenderers(in: notch.window!.contentView!).allSatisfy({ $0.repeatingAnimationCount == 0 }) else { throw NexaError.message("Energy-saving mode did not stop animations") }
                model.preferences.value.energySaving = false
                checks.append("PASS: actual native visualizers stop all repeating animations on pause and in energy-saving mode")
                for preset in MotionPreset.allCases {
                    model.preferences.value.motionPreset = preset
                    try await Task.sleep(for: .milliseconds(100))
                    for index in 0..<12 {
                        notch.expand(index % 2 == 0)
                        if index % 3 == 0 { model.selected = index % 2 == 0 ? .home : .music }
                        try await Task.sleep(for: .milliseconds(35))
                    }
                    model.selected = .home; notch.expand(true)
                    try await Task.sleep(for: .milliseconds(650))
                    try verifyNotchPlacement()
                    guard !notch.transitionInFlight else { throw NexaError.message("Preset \(preset.rawValue) did not settle") }
                }
                checks.append("PASS: all three presets settle after rapid reversals and module switches")
                model.preferences.value.reduceMotion = true
                try await Task.sleep(for: .milliseconds(100))
                notch.expand(false); notch.expand(true)
                guard !notch.transitionInFlight else { throw NexaError.message("Custom Reduced Motion left an active transition") }
                checks.append("PASS: the custom Reduced Motion setting disables geometry animation")
                model.preferences.value.reduceMotion = false
                model.preferences.value.motionPreset = .balanced
                model.preferences.value.visualizerStyle = .bars
                // Render every existing module, with integration services inactive.
                let moduleImages = output.appendingPathComponent("Modules")
                try FileManager.default.createDirectory(at: moduleImages, withIntermediateDirectories: true)
                for module in ModuleID.allCases {
                    model.selected = module
                    try await Task.sleep(for: .milliseconds(450))
                    guard notch.window?.contentView != nil else { throw NexaError.message("Missing module host: \(module.title)") }
                    try snapshot(notch.window!, to: moduleImages.appendingPathComponent("\(module.rawValue).png"))
                }
                checks.append("PASS: all \(ModuleID.allCases.count) existing module views render; permissioned integrations were not activated")
                model.selected = .home
                showSettings()
                try await Task.sleep(for: .milliseconds(450))
                click(in: settingsWindow!, at: NSPoint(x: 95, y: settingsWindow!.contentView!.bounds.height - 198))
                try await Task.sleep(for: .milliseconds(450))
                try snapshot(settingsWindow!, to: output.appendingPathComponent("appearance-motion.png"))
                checks.append("PASS: native Settings window renders Appearance & Motion")
                settingsWindow?.close()
                model.media.loadDemo(playing: false)
                notch.expand(false)
                try await Task.sleep(for: .milliseconds(500))
                model.notify("A little more flow", detail: "Nexa 3.1 notification preview", icon: "sparkles", priority: true)
                try await Task.sleep(for: .milliseconds(500))
                try snapshot(notch.window!, to: output.appendingPathComponent("notification.png"))
                model.banner = nil
                try await Task.sleep(for: .milliseconds(500))
                try verifyNotchPlacement()
                let startCPU = Self.fluidCPUTime()
                let startMemory = MemorySnapshot.footprint(pid: getpid())
                let start = ProcessInfo.processInfo.systemUptime
                try await Task.sleep(for: .seconds(60))
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let endCPU = Self.fluidCPUTime()
                let endMemory = MemorySnapshot.footprint(pid: getpid())
                if let startCPU, let endCPU {
                    checks.append(String(format: "MEASURED: isolated paused/closed island idle CPU %.3f%% of one core over %.1f seconds", (endCPU - startCPU) / elapsed * 100, elapsed))
                }
                if let startMemory, let endMemory {
                    checks.append("MEASURED: physical memory footprint before/after idle \(startMemory) / \(endMemory) bytes")
                }
                checks.append("LIMIT: resource sample is this isolated test process; live integrations, 120 Hz rendering, full-screen Spaces and physical multiple displays need hardware testing")
                try (checks.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("fluid-smoke-check.txt"), atomically: true, encoding: .utf8)
            } catch {
                try? ("FAIL: \(error.localizedDescription)\n" + checks.joined(separator: "\n")).write(to: output.appendingPathComponent("fluid-smoke-check.txt"), atomically: true, encoding: .utf8)
            }
            model.shutdown(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: scratch)
            NSApp.terminate(nil)
        }
    }

    private static func fluidCPUTime() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    private static func fluidRenderers(in view: NSView) -> [ElectricBlueVisualizerView] {
        (view as? ElectricBlueVisualizerView).map { [$0] } ?? view.subviews.flatMap { fluidRenderers(in: $0) }
    }
}
