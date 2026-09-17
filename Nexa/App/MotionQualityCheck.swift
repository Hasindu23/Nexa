import AppKit
import SwiftUI

extension AppDelegate {
    func runMotionQA(output: URL) {
        let suite = "app.nexa.motion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: scratch), testing: true)
        model.preferences.value.completedOnboarding = true
        model.preferences.value.hapticFeedback = false
        model.media.loadDemo(); setup(); notch.pinnedOpen = true
        Task { @MainActor in
            var intervals: [Double] = [], last = CACurrentMediaTime(), resizes = 0
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in let now = CACurrentMediaTime(); intervals.append(now - last); last = now }
            let observation = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: notch.window, queue: .main) { _ in resizes += 1 }
            do {
                // Warm up font/layout caches before measuring steady interaction.
                notch.expand(true); try await Task.sleep(for: .milliseconds(600)); notch.expand(false); try await Task.sleep(for: .milliseconds(600))
                resizes = 0; last = CACurrentMediaTime(); RunLoop.main.add(timer, forMode: .common)
                for _ in 0..<8 { notch.expand(true); try await Task.sleep(for: .milliseconds(480)); notch.expand(false); try await Task.sleep(for: .milliseconds(480)) }
                for index in 0..<24 { notch.expand(index % 2 == 0); try await Task.sleep(for: .milliseconds(35)) }
                notch.expand(true); try await Task.sleep(for: .milliseconds(500))
                for index in 0..<12 { model.selected = index % 2 == 0 ? .files : .home; try await Task.sleep(for: .milliseconds(55)) }
                model.selected = .home; notch.expand(false); try await Task.sleep(for: .milliseconds(650))
                let geometry = NotchGeometry(screen: notch.window!.screen!)
                let expected = geometry.frame(expanded: false, banner: false, preferences: model.preferences.value)
                let actual = notch.window!.frame
                guard abs(actual.width - expected.width) < 0.5, abs(actual.height - expected.height) < 0.5, abs(actual.midX - expected.midX) < 0.5, abs(actual.maxY - expected.maxY) < 0.5 else { throw NexaError.message("Rapid interruption left the panel in the wrong frame: \(actual)") }
                timer.invalidate(); NotificationCenter.default.removeObserver(observation)
                let sorted = intervals.sorted(), p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                let report = "PASS: 8 full open/close cycles, 24 rapid reversals, 12 widget changes settled into the exact collapsed camera frame.\nNative window resize notifications: \(resizes)\nMain-loop heartbeat samples: \(intervals.count)\nHeartbeat p95 interval: \(String(format: "%.2f", p95 * 1000)) ms\nLongest main-loop heartbeat interval: \(String(format: "%.2f", (sorted.last ?? 0) * 1000)) ms\nHeartbeat intervals over 33.3 ms: \(intervals.filter { $0 > 1.0 / 30 }.count)\nMeasurement is main-loop responsiveness, not rendered display FPS. No private data, camera or playback commands used.\n"
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try report.write(to: output, atomically: true, encoding: .utf8)
            } catch { timer.invalidate(); NotificationCenter.default.removeObserver(observation); try? "FAIL: \(error.localizedDescription)".write(to: output, atomically: true, encoding: .utf8) }
            defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: scratch); NSApp.terminate(nil)
        }
    }
}
