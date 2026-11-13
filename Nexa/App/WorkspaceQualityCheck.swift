import AppKit
import SwiftUI

extension AppDelegate {
    func runWorkspaceQA(output: URL) {
        let suite = "app.nexa.qa.workspace.\(UUID().uuidString)"
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
                model.media.loadDemo(playing: false)
                model.notebook.addTask("Review the Nexa workspace", dueDate: Date())
                let capture: (String) async throws -> Void = { name in
                    try await Task.sleep(for: .milliseconds(600))
                    try self.verifyNotchPlacement()
                    try self.snapshot(self.notch.window!, to: output.appendingPathComponent(name + ".png"))
                }
                try await capture("ambient")
                notch.present(.peek); try await capture("peek")
                notch.present(.workspace); notch.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                try await capture("home")
                let surface = notch.window!.contentView!
                for module in ModuleID.allCases {
                    model.selected = module
                    try await capture("workspace-\(module.rawValue)")
                    guard notch.window!.contentView === surface else { throw NexaError.message("Workspace switch replaced the shell") }
                }
                checks.append("PASS: all workspaces render inside the same native shell")
                for _ in 0..<8 {
                    notch.present(.ambient); try await Task.sleep(for: .milliseconds(380))
                    notch.present(.workspace); try await Task.sleep(for: .milliseconds(450))
                }
                for index in 0..<24 { notch.present(index % 2 == 0 ? .ambient : .workspace); try await Task.sleep(for: .milliseconds(35)) }
                notch.present(.workspace); try await Task.sleep(for: .milliseconds(550))
                for index in 0..<20 { model.selected = ModuleID.allCases[index % ModuleID.allCases.count]; try await Task.sleep(for: .milliseconds(40)) }
                for _ in 0..<10 {
                    notch.present(.peek); try await Task.sleep(for: .milliseconds(50))
                    notch.present(.workspace); try await Task.sleep(for: .milliseconds(50))
                }
                try await Task.sleep(for: .milliseconds(550))
                guard !notch.transitionInFlight, notch.hostingInstallCount == 1 else { throw NexaError.message("Motion did not settle with persistent hosts") }
                checks.append("PASS: 8 cycles, 24 reversals, 20 switches and 10 Peek/Workspace pairs settle without replacing hosts")
                for appearance in NexaAppearance.allCases {
                    model.preferences.value.appearanceMode = appearance; model.selected = .home
                    try await capture("appearance-\(appearance.rawValue)")
                }
                model.preferences.value.appearanceMode = .liquidGlass
                for style in NexaGlassStyle.allCases { model.preferences.value.glassStyle = style; try await capture("glass-\(style.rawValue)") }
                model.preferences.value.glassStyle = .balanced; model.preferences.value.energySaving = true
                try await capture("energy-saving")
                model.preferences.value.energySaving = false; model.preferences.value.reduceMotion = true
                notch.present(.peek); notch.present(.workspace)
                guard !notch.transitionInFlight else { throw NexaError.message("Reduced Motion did not settle") }
                try await capture("reduce-motion")
                checks.append("PASS: glass styles, Classic Black, Energy Saving and Reduced Motion render")
                model.preferences.value.reduceMotion = false
                NexaAccessibility.qaReduceTransparency = true; notch.layout(animated: false)
                try await capture("reduce-transparency-simulated")
                NexaAccessibility.qaReduceTransparency = nil; NexaAccessibility.qaIncreaseContrast = true; notch.layout(animated: false)
                try await capture("increase-contrast-simulated")
                NexaAccessibility.qaIncreaseContrast = nil
                for name in [NSAppearance.Name.aqua, .darkAqua] {
                    NSApp.appearance = NSAppearance(named: name); notch.layout(animated: false)
                    try await capture("system-appearance-\(name.rawValue)")
                    guard notch.window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua else {
                        throw NexaError.message("System appearance changed the charcoal workspace material")
                    }
                }
                checks.append("PASS: the charcoal workspace keeps its dark native material in Light and Dark system appearance")
                NSApp.appearance = nil
                model.preferences.value.reduceMotion = false; model.selected = .home; model.editingWorkspace = true
                try await capture("edit-workspace")
                model.editingWorkspace = false
                showSettings(); try await Task.sleep(for: .milliseconds(450))
                try snapshot(settingsWindow!, to: output.appendingPathComponent("settings.png")); settingsWindow?.close()
                guard !model.mirror.active && !model.mirror.session.isRunning else { throw NexaError.message("Camera activated without consent") }
                checks.append("PASS: Mirror workspace discovery did not start camera capture")
                try (checks.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("workspace-checks.txt"), atomically: true, encoding: .utf8)
            } catch { try? ("FAIL: \(error.localizedDescription)\n" + checks.joined(separator: "\n")).write(to: output.appendingPathComponent("workspace-checks.txt"), atomically: true, encoding: .utf8) }
            NexaAccessibility.qaReduceTransparency = nil; NexaAccessibility.qaIncreaseContrast = nil
            if CommandLine.arguments.contains("--qa-hold") { model.selected = .home; return }
            model.shutdown(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: scratch)
            NSApp.terminate(nil)
        }
    }
}
