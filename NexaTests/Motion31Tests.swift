import XCTest
import AppKit
@testable import Nexa

final class Motion31Tests: XCTestCase {
    @MainActor func testCameraDiscoveryNeverBlocksModuleTransitionOrStartsCapture() async {
        let discovered = expectation(description: "Camera discovery ran off the interface thread")
        let mirror = MirrorService(discover: {
            XCTAssertFalse(Thread.isMainThread)
            discovered.fulfill()
            return []
        })
        mirror.refreshDevices()
        await fulfillment(of: [discovered], timeout: 2)
        XCTAssertFalse(mirror.active); XCTAssertFalse(mirror.starting); XCTAssertFalse(mirror.session.isRunning)
        mirror.stop()
    }
    func testPresetTimingsAndAccessibilityPriority() {
        for preset in MotionPreset.allCases {
            var preferences = AppPreferences(); preferences.motionPreset = preset
            let motion = NexaMotion(preferences: preferences)
            XCTAssertTrue((0.28...0.38).contains(motion.expansionDuration))
            XCTAssertTrue((0.22...0.30).contains(motion.collapseDuration))
            XCTAssertTrue((0.18...0.25).contains(motion.moduleDuration))
            XCTAssertEqual(NexaMotion(preferences: preferences, systemReduceMotion: true).expansionDuration, 0)
            preferences.reduceMotion = true
            XCTAssertNil(NexaMotion(preferences: preferences).moduleAnimation)
        }
    }
    func testSpringRetargetPreservesPositionAndVelocity() {
        let opening = NexaSpring(start: 170, velocity: 0, target: 740, duration: 0.34, damping: 0.98)
        let interrupted = opening.sample(0.083)
        let reverse = NexaSpring(start: interrupted.value, velocity: interrupted.velocity, target: 170, duration: 0.26, damping: 0.98)
        XCTAssertEqual(reverse.sample(0).value, interrupted.value, accuracy: 0.000001)
        XCTAssertEqual(reverse.sample(0).velocity, interrupted.velocity, accuracy: 0.000001)
        let dt = 0.0000001
        XCTAssertEqual((reverse.sample(dt).value - reverse.sample(0).value) / dt, interrupted.velocity, accuracy: 0.1)
        XCTAssertEqual(reverse.sample(0.26).value, 170)
        XCTAssertEqual(reverse.sample(0.26).velocity, 0)
    }
    func testSpringOvershootIsSmallAndFinalRestIsContinuous() {
        for damping in [1.0, 0.98, 0.86] {
            let spring = NexaSpring(start: 170, velocity: 0, target: 740, duration: 0.34, damping: damping)
            let values = (0...1000).map { spring.sample(Double($0) * 0.00034).value }
            XCTAssertGreaterThanOrEqual(values.min()!, 169.999)
            XCTAssertLessThan(values.max()!, 752)
            XCTAssertEqual(spring.sample(0.339999).value, 740, accuracy: 0.00001)
            XCTAssertEqual(spring.sample(0.339999).velocity, 0, accuracy: 0.01)
        }
    }
    func testRapidReversalsRemainFiniteAndSettleExactly() {
        var value = 170.0, velocity = 0.0
        for index in 0..<100 {
            let curve = NexaSpring(start: value, velocity: velocity, target: index % 2 == 0 ? 740 : 170, duration: 0.34, damping: 0.98)
            let next = curve.sample(0.035)
            XCTAssertTrue(next.value.isFinite && next.velocity.isFinite)
            XCTAssertGreaterThan(next.value, 0); XCTAssertLessThan(next.value, 900)
            value = next.value; velocity = next.velocity
        }
        let final = NexaSpring(start: value, velocity: velocity, target: 170, duration: 0.26, damping: 0.98).sample(1)
        XCTAssertEqual(final.value, 170); XCTAssertEqual(final.velocity, 0)
    }
    func testDetachedDisplayClearsMenuBarAndClampsSmallScreens() {
        let geometry = NotchGeometry(frame: NSRect(x: -600, y: 300, width: 600, height: 400), hardwareWidth: 170, hardwareHeight: 0, menuBarHeight: 28)
        var preferences = AppPreferences(); preferences.layout = "Large"; preferences.horizontalOffset = 4000
        let frame = geometry.frame(expanded: true, banner: false, preferences: preferences)
        XCTAssertEqual(frame.maxY, 666)
        XCTAssertGreaterThanOrEqual(frame.minX, -600); XCTAssertLessThanOrEqual(frame.maxX, 0)
        XCTAssertGreaterThanOrEqual(frame.minY, 300)
    }
    @MainActor func testCustomReducedMotionSettlesInFlightWithoutReplacingHosts() async throws {
        let name = "app.nexa.motion31.\(UUID().uuidString)", defaults = UserDefaults(suiteName: "app.nexa.motion31.\(UUID().uuidString)")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let preferences = PreferencesStore(defaults: defaults)
        let model = AppModel(preferences: preferences, store: LocalStore(root: root), testing: true)
        let controller = NotchWindowController(model: model); controller.pinnedOpen = true
        defer { model.shutdown(); controller.window?.close(); defaults.removeObject(forKey: "preferences.v1"); try? FileManager.default.removeItem(at: root) }
        let host = controller.window?.contentView
        controller.expand(true)
        preferences.value.reduceMotion = true
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(controller.transitionInFlight)
        XCTAssertTrue(controller.window?.contentView === host)
        controller.expand(false)
        XCTAssertFalse(controller.transitionInFlight)
        XCTAssertEqual(controller.window?.frame, controller.geometry.frame(expanded: false, banner: false, preferences: preferences.value))
    }
}
