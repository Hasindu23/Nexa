import XCTest
import AppKit
@testable import Nexa

final class Visualizer31Tests: XCTestCase {
    func testPlaybackAndAccessibilityGateAnimation() {
        var preferences = AppPreferences()
        XCTAssertTrue(VisualizerConfiguration(playing: true, preferences: preferences).animates)
        XCTAssertFalse(VisualizerConfiguration(playing: false, preferences: preferences).animates)
        XCTAssertFalse(VisualizerConfiguration(playing: true, preferences: preferences, systemReduceMotion: true).animates)
        XCTAssertFalse(VisualizerConfiguration(playing: true, preferences: preferences, enabled: false).animates)
        preferences.reduceMotion = true
        XCTAssertFalse(VisualizerConfiguration(playing: true, preferences: preferences).animates)
        preferences.reduceMotion = false; preferences.energySaving = true
        XCTAssertFalse(VisualizerConfiguration(playing: true, preferences: preferences).animates)
    }
    @MainActor func testRendererStopsOnPauseHideEnergyReductionAndRemoval() async throws {
        for presentation in [VisualizerConfiguration.Presentation.compact, .spectrum] {
            try await checkRendererLifecycle(presentation: presentation)
        }
    }
    @MainActor private func checkRendererLifecycle(presentation: VisualizerConfiguration.Presentation) async throws {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 280, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = ElectricBlueVisualizerView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        window.contentView = view; NSApp.unhide(nil); window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
        defer { view.stopAnimations(); window.close() }
        var preferences = AppPreferences()
        view.configure(VisualizerConfiguration(playing: true, preferences: preferences, presentation: presentation))
        for _ in 0..<40 {
            if window.occlusionState.contains(.visible) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        view.layoutSubtreeIfNeeded(); view.updateActivity(force: true)
        XCTAssertGreaterThan(view.repeatingAnimationCount, 0, "Visible playing renderer must actually animate: visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), hidden=\(view.isHiddenOrHasHiddenAncestor), bounds=\(view.bounds), enabled=\(view.configuration.animates)")
        view.configure(VisualizerConfiguration(playing: false, preferences: preferences, presentation: presentation))
        XCTAssertEqual(view.repeatingAnimationCount, 0)
        view.configure(VisualizerConfiguration(playing: true, preferences: preferences, presentation: presentation))
        view.isHidden = true; view.updateActivity()
        XCTAssertEqual(view.repeatingAnimationCount, 0)
        view.isHidden = false; view.updateActivity()
        XCTAssertGreaterThan(view.repeatingAnimationCount, 0)
        preferences.energySaving = true
        view.configure(VisualizerConfiguration(playing: true, preferences: preferences, presentation: presentation))
        XCTAssertEqual(view.repeatingAnimationCount, 0)
        preferences.energySaving = false; preferences.reduceMotion = true
        view.configure(VisualizerConfiguration(playing: true, preferences: preferences, presentation: presentation))
        XCTAssertEqual(view.repeatingAnimationCount, 0)
        preferences.reduceMotion = false
        for style in VisualizerStyle.allCases {
            preferences.visualizerStyle = style
            view.configure(VisualizerConfiguration(playing: true, preferences: preferences, presentation: presentation))
            XCTAssertGreaterThan(view.repeatingAnimationCount, 0)
            XCTAssertFalse(view.bars.isEmpty)
        }
        window.orderOut(nil)
        try await Task.sleep(for: .milliseconds(150)); view.updateActivity()
        XCTAssertEqual(view.repeatingAnimationCount, 0)
        view.removeFromSuperview()
        XCTAssertEqual(view.repeatingAnimationCount, 0)
    }
}
