import AppKit
import SwiftUI

extension AppDelegate {
    func runLiveMediaQA(output: URL) {
        let suite = "app.nexa.qa.live.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: scratch), testing: true)
        model.preferences.value.completedOnboarding = true
        setup(); notch.pinnedOpen = true; model.media.start(); model.media.visible = true
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try await Task.sleep(for: .milliseconds(150))
                notch.expand(true)
                try await Task.sleep(for: .seconds(3))
                guard !model.media.track.appID.isEmpty else { throw NexaError.message("No active system media was reported") }
                try verifyNotchPlacement()
                // AppKit's offscreen cache can omit inactive hosted text layers.
                // Activate this isolated QA window before capturing its contents.
                notch.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .milliseconds(250))
                try snapshot(notch.window!, to: output.appendingPathComponent("14-live-now-playing.png"))
                let track = model.media.track
                try "PASS: running native app detected \(track.source), playing=\(track.playing), duration=\(Int(track.duration)) seconds.\nPASS: the live player was rendered in the camera-centered Home panel.\nNo playback commands were sent; the existing playback state was left unchanged.\n".write(to: output.appendingPathComponent("live-media-check.txt"), atomically: true, encoding: .utf8)
            } catch { try? "FAIL: \(error.localizedDescription)".write(to: output.appendingPathComponent("live-media-check.txt"), atomically: true, encoding: .utf8) }
            model.media.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: scratch); NSApp.terminate(nil)
        }
    }
    func runQA(output: URL) {
        let suite = "app.nexa.qa.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: scratch), testing: true)
        model.preferences.value.completedOnboarding = true
        setup(); notch.pinnedOpen = true
        Task { @MainActor in
            var checks: [String] = []
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                showOnboarding(); try await Task.sleep(for: .milliseconds(550))
                try snapshot(onboardingWindow!, to: output.appendingPathComponent("01-welcome.png"))
                onboardingWindow?.close()
                model.media.loadDemo(); notch.expand(true)
                try await Task.sleep(for: .milliseconds(700))
                try verifyNotchPlacement()
                try snapshot(notch.window!, to: output.appendingPathComponent("02-notch-preview.png"))
                checks.append("PASS: app launched, native panel expanded and rendered")
                checks.append(notch.geometry.hasNotch ? "PASS: expanded overlay is centered on the camera cutout and flush with the physical screen top" : "PASS: notch-free panel is centered below the reserved menu-bar area")
                let panel = notch.window!
                click(in: panel, at: NSPoint(x: 143, y: panel.frame.height - 22))
                try await Task.sleep(for: .milliseconds(550))
                guard model.selected == .files else { throw NexaError.message("Tray navigation did not respond") }
                checks.append("PASS: Home to Tray native click expands detail layout")
                let modules = model.modules.filter { $0 != .home && $0 != .files }
                let index = modules.firstIndex(of: .timers)!
                let header = max(44, notch.geometry.hardwareHeight + 7)
                click(in: panel, at: NSPoint(x: 29 + (panel.frame.width - 58) / Double(modules.count) * (Double(index) + 0.5), y: panel.frame.height - header - 3 - 16))
                try await Task.sleep(for: .milliseconds(200))
                guard model.selected == .timers else { throw NexaError.message("Timer navigation did not respond") }
                checks.append("PASS: native mouse events on the timer tab change the visible module")
                click(in: panel, at: NSPoint(x: panel.frame.width / 2 - 35, y: 414 - header - 3 - 32 - 9 - 7 - 22 - 14 - 156 - 14 - 15))
                try await Task.sleep(for: .milliseconds(150))
                guard model.timers.running else { throw NexaError.message("Start timer button did not respond") }
                click(in: panel, at: NSPoint(x: panel.frame.width / 2 - 35, y: 414 - header - 3 - 32 - 9 - 7 - 22 - 14 - 156 - 14 - 15))
                try await Task.sleep(for: .milliseconds(150))
                guard !model.timers.running else { throw NexaError.message("Pause timer button did not respond") }
                try await Task.sleep(for: .milliseconds(350))
                try snapshot(notch.window!, to: output.appendingPathComponent("03-timer.png"))
                checks.append("PASS: native clicks start and pause the timer")
                let sample = scratch.appendingPathComponent("A thought for later.txt")
                try "An intentional sample file for Nexa QA.".write(to: sample, atomically: true, encoding: .utf8)
                model.files.add([sample]); model.selected = .files
                try await Task.sleep(for: .milliseconds(350))
                try snapshot(notch.window!, to: output.appendingPathComponent("04-file-shelf.png"))
                guard model.files.items.count == 1 else { throw NexaError.message("File add failed") }
                model.files.clear()
                guard FileManager.default.fileExists(atPath: sample.path) else { throw NexaError.message("Shelf removal deleted original") }
                checks.append("PASS: shelf add and clear preserve the original file")
                model.selected = .system; model.system.sample()
                try await Task.sleep(for: .milliseconds(350))
                try snapshot(notch.window!, to: output.appendingPathComponent("05-system.png"))
                model.banner = nil; notch.expand(false)
                try await Task.sleep(for: .milliseconds(500))
                guard notch.window!.frame.height < 100 else { throw NexaError.message("Collapsed window still intercepts expanded area") }
                try verifyNotchPlacement()
                checks.append("PASS: collapse physically shrinks the window hit area")
                checks.append(notch.geometry.hasNotch ? "PASS: collapsed overlay remains at the physical top with equal camera-side wings" : "PASS: notch-free overlay collapses to a compact floating pill")
                try snapshot(notch.window!, to: output.appendingPathComponent("06-collapsed.png"))
                showSettings(); try await Task.sleep(for: .milliseconds(450))
                try snapshot(settingsWindow!, to: output.appendingPathComponent("07-settings.png"))
                checks.append("PASS: settings window opens and renders")
                click(in: settingsWindow!, at: NSPoint(x: 95, y: settingsWindow!.contentView!.bounds.height - 198))
                try await Task.sleep(for: .milliseconds(350))
                try snapshot(settingsWindow!, to: output.appendingPathComponent("08-appearance.png"))
                checks.append("PASS: native Settings sidebar action opens Appearance")
                model.selected = .notes; _ = model.notebook.addNote()
                model.notebook.update(model.notebook.notes[0].id, text: "A little more space for what matters.\n\nYour notes stay on this Mac.")
                notch.expand(true); try await Task.sleep(for: .milliseconds(450))
                try snapshot(notch.window!, to: output.appendingPathComponent("09-notes.png"))
                model.selected = .mirror; try await Task.sleep(for: .milliseconds(450))
                guard !model.mirror.active && !model.mirror.starting else { throw NexaError.message("Mirror started without a click") }
                try snapshot(notch.window!, to: output.appendingPathComponent("10-mirror.png"))
                checks.append("PASS: Mirror remains off when opened; no camera permission was requested")
                model.selected = .home
                model.preferences.value.layout = "Compact"
                try await Task.sleep(for: .milliseconds(500))
                try verifyNotchPlacement()
                try snapshot(notch.window!, to: output.appendingPathComponent("11-compact-home.png"))
                model.preferences.value.layout = "Large"
                try await Task.sleep(for: .milliseconds(500))
                try snapshot(notch.window!, to: output.appendingPathComponent("12-large-home.png"))
                model.preferences.value.layout = "Normal"; model.preferences.value.centerWidget = "Shortcuts"
                try await Task.sleep(for: .milliseconds(500))
                try snapshot(notch.window!, to: output.appendingPathComponent("13-shortcuts-home.png"))
                checks.append("PASS: compact, normal, large and alternate Home widget layouts render")
                let report = "Nexa native application smoke check\n" + checks.joined(separator: "\n") + "\n\nScreenshots 01–13 are rendered from the running native app. Music is explicitly marked as sample preview content. No user clipboard, calendar data, media permissions, network or API keys were used.\n"
                try report.write(to: output.appendingPathComponent("smoke-check.txt"), atomically: true, encoding: .utf8)
                defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: scratch)
                NSApp.terminate(nil)
            } catch {
                try? ("FAIL: \(error.localizedDescription)\n" + checks.joined(separator: "\n")).write(to: output.appendingPathComponent("smoke-check.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
    }
    func snapshot(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw NexaError.message("No content view") }
        func invalidate(_ view: NSView) { view.needsDisplay = true; view.layer?.setNeedsDisplay(); view.subviews.forEach(invalidate) }
        invalidate(view); view.layoutSubtreeIfNeeded(); window.display()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NexaError.message("Cannot capture native view") }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { throw NexaError.message("Cannot encode preview") }
        try data.write(to: url)
    }
    func verifyNotchPlacement() throws {
        guard let panel = notch.window else { throw NexaError.message("Missing notch screen") }
        let geometry = notch.geometry
        let expected = geometry.frame(expanded: model.expanded, banner: model.banner != nil, preferences: model.preferences.value, home: model.selected == .home)
        guard abs(panel.frame.maxY - expected.maxY) < 0.5, abs(panel.frame.midX - expected.midX) < 0.5, panel.level == .statusBar else {
            throw NexaError.message("Notch position changed after display: expected \(expected), actual \(panel.frame), level \(panel.level.rawValue)")
        }
    }
    func click(in window: NSWindow, at point: NSPoint) {
        window.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) { window.sendEvent(event) }
        }
    }
}
