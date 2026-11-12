import XCTest
@testable import Nexa

final class Appearance31Tests: XCTestCase {
    @MainActor func testLegacyPreferencesGainAppearanceWithoutLosingChoices() throws {
        let suite = "app.nexa.appearance-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = AppPreferences()
        old.accent = .rose; old.animationSpeed = 1.7; old.hoverToOpen = false
        old.mediaConnected = true; old.localOnly = true; old.centerWidget = "Notes"
        old.enabledModules = [.home, .notes, .music, .storage]
        old.preferredDisplay = "Studio Display"; old.completedOnboarding = true
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["motionPreset", "reduceMotion", "energySaving", "visualizerStyle", "visualizerBrightness", "ambientBlueGlow", "glowIntensity"] { encoded.removeValue(forKey: key) }
        defaults.set(try JSONSerialization.data(withJSONObject: encoded), forKey: "preferences.v1")
        let restored = PreferencesStore(defaults: defaults)
        XCTAssertEqual(restored.value, old)
        XCTAssertEqual(restored.value.motionPreset, .balanced)
        XCTAssertEqual(restored.value.visualizerStyle, .bars)
        XCTAssertFalse(restored.value.reduceMotion)
    }

    @MainActor func testAppearanceChoicesSurviveRelaunch() throws {
        let suite = "app.nexa.appearance-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        store.value.motionPreset = .playful
        store.value.visualizerStyle = .wave
        store.value.animationSpeed = 1.25
        store.value.visualizerBrightness = 0.4
        store.value.ambientBlueGlow = false
        store.value.glowIntensity = 0.75
        store.value.reduceMotion = true
        store.value.energySaving = true
        XCTAssertEqual(PreferencesStore(defaults: defaults).value, store.value)
    }

    @MainActor func testUnknownAppearanceEnumsDoNotResetPrivateSettings() throws {
        let suite = "app.nexa.appearance-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved: [String: Any] = ["motionPreset": "future", "visualizerStyle": "future", "animationSpeed": 20,
                                    "visualizerBrightness": -1, "glowIntensity": 5, "accent": "violet",
                                    "completedOnboarding": true, "mediaConnected": false, "localOnly": true]
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "preferences.v1")
        let value = PreferencesStore(defaults: defaults).value
        XCTAssertEqual(value.motionPreset, .balanced); XCTAssertEqual(value.visualizerStyle, .bars)
        XCTAssertEqual(value.animationSpeed, 2); XCTAssertEqual(value.visualizerBrightness, 0.1)
        XCTAssertEqual(value.glowIntensity, 1); XCTAssertEqual(value.accent, .violet)
        XCTAssertTrue(value.completedOnboarding); XCTAssertFalse(value.mediaConnected); XCTAssertTrue(value.localOnly)
    }
}
