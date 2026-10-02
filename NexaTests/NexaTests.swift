import XCTest
import AppKit
@testable import Nexa

final class NexaTests: XCTestCase {
    func temporaryStore() throws -> LocalStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nexa-test-\(UUID().uuidString)")
        let store = LocalStore(root: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return store
    }
    @MainActor func testPrivacyDefaultsAndPersistence() async throws {
        let name = "nexa-test-\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertTrue(preferences.value.localOnly)
        XCTAssertFalse(preferences.value.clipboardEnabled)
        XCTAssertFalse(preferences.value.mediaConnected)
        XCTAssertFalse(preferences.value.enabledModules.contains(.ai))
        preferences.value.accent = .violet
        XCTAssertEqual(PreferencesStore(defaults: defaults).value.accent, .violet)
    }
    @MainActor func testShelfNeverDeletesOriginalAndPersists() async throws {
        let store = try temporaryStore(); let file = store.root.appendingPathComponent("original.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let shelf = FileShelfService(store: store); shelf.add([file, file])
        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertEqual(FileShelfService(store: store).items.count, 1)
        shelf.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileShelfService(store: store).items.isEmpty)
    }
    @MainActor func testShelfExpiryAndSessionOnly() async throws {
        let store = try temporaryStore(); let file = store.root.appendingPathComponent("expiry.txt")
        try Data([1]).write(to: file)
        let shelf = FileShelfService(store: store); shelf.expiryHours = 1
        let now = Date(); shelf.add([file], now: now); shelf.prune(now: now.addingTimeInterval(3601))
        XCTAssertTrue(shelf.items.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        shelf.configure(persistent: false, expiryHours: 0); shelf.add([file])
        XCTAssertEqual(shelf.items.count, 1); XCTAssertTrue(FileShelfService(store: store).items.isEmpty)
    }
    @MainActor func testClipboardConcealedPauseDedupeAndRecopy() async throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let clipboard = ClipboardService(store: try temporaryStore(), pasteboard: board)
        board.clearContents(); board.setString("secret", forType: .string); board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")); clipboard.capture()
        XCTAssertTrue(clipboard.items.isEmpty)
        board.clearContents(); board.setString("A useful thought", forType: .string); clipboard.capture()
        XCTAssertEqual(clipboard.items.count, 1)
        clipboard.pin(clipboard.items[0])
        board.clearContents(); board.setString("A useful thought", forType: .string); clipboard.capture()
        XCTAssertEqual(clipboard.items.count, 1); XCTAssertTrue(clipboard.items[0].pinned)
        clipboard.copy(clipboard.items[0]); clipboard.capture(); XCTAssertEqual(clipboard.items.count, 1)
        clipboard.paused = true; board.clearContents(); board.setString("private", forType: .string); clipboard.capture()
        clipboard.paused = false; clipboard.capture(); XCTAssertEqual(clipboard.items.count, 1)
    }
    @MainActor func testClipboardHistoryLimitPreservesPinned() async throws {
        let clipboard = ClipboardService(store: try temporaryStore(), pasteboard: .withUniqueName()); clipboard.limit = 10
        for i in 0..<20 { clipboard.insert(ClipItem(id: UUID(), kind: .text, text: "\(i)", data: nil, createdAt: Date(), pinned: i == 0)) }
        XCTAssertEqual(clipboard.items.count, 10); XCTAssertTrue(clipboard.items.contains { $0.text == "0" && $0.pinned })
        clipboard.clear(); XCTAssertTrue(clipboard.items.isEmpty)
    }
    @MainActor func testClipboardURLsAndFilesPreserveTypes() async throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let clipboard = ClipboardService(store: try temporaryStore(), pasteboard: board)
        board.clearContents(); board.setString("https://example.com/test", forType: .string); clipboard.capture()
        XCTAssertEqual(clipboard.items.first?.kind, .url)
        let file = URL(fileURLWithPath: "/tmp/example-file.txt"); board.clearContents(); board.writeObjects([file as NSURL]); clipboard.capture()
        XCTAssertEqual(clipboard.items.first?.kind, .files)
        clipboard.copy(clipboard.items[0]); XCTAssertNotNil(board.string(forType: .fileURL))
    }
    @MainActor func testTimerPauseResumeDeadlineAndSingleCompletion() async throws {
        let timer = TimerService(); let now = Date(); var finishes = 0; timer.onFinish = { finishes += 1 }
        timer.startTimer(seconds: 60, now: now); timer.tick(now: now.addingTimeInterval(20)); XCTAssertEqual(timer.remaining, 40, accuracy: 0.01)
        timer.toggle(now: now.addingTimeInterval(20)); timer.tick(now: now.addingTimeInterval(80)); XCTAssertEqual(timer.remaining, 40, accuracy: 0.01)
        timer.toggle(now: now.addingTimeInterval(80)); timer.tick(now: now.addingTimeInterval(150)); timer.tick(now: now.addingTimeInterval(160))
        XCTAssertEqual(finishes, 1); XCTAssertEqual(timer.remaining, 0); XCTAssertFalse(timer.running)
    }
    @MainActor func testStopwatchPauseResetAndDisable() async throws {
        let timer = TimerService(); let now = Date(); timer.toggleStopwatch(now: now); timer.tick(now: now.addingTimeInterval(12)); XCTAssertEqual(timer.stopwatch, 12)
        timer.toggleStopwatch(now: now.addingTimeInterval(12)); timer.tick(now: now.addingTimeInterval(100)); XCTAssertEqual(timer.stopwatch, 12)
        timer.resetStopwatch(); XCTAssertEqual(timer.stopwatch, 0)
        timer.startTimer(seconds: 30); timer.suspend(); XCTAssertFalse(timer.running)
    }
    func testNotchPlacementAcrossDisplaysAndCollapsedHitArea() {
        let geometry = NotchGeometry(frame: NSRect(x: -1920, y: 240, width: 1920, height: 1080), hardwareWidth: 180, hardwareHeight: 32)
        let preferences = AppPreferences(); let collapsed = geometry.frame(expanded: false, banner: false, preferences: preferences); let expanded = geometry.frame(expanded: true, banner: false, preferences: preferences)
        XCTAssertEqual(collapsed.midX, -960); XCTAssertEqual(collapsed.maxY, 1320); XCTAssertEqual(collapsed.height, 32)
        XCTAssertEqual(expanded.maxY, 1320); XCTAssertEqual(expanded.width, 740)
        let pill = NotchGeometry(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), hardwareWidth: 170, hardwareHeight: 0)
        var position = preferences; position.horizontalOffset = 4000
        XCTAssertEqual(pill.frame(expanded: true, banner: false, preferences: position).maxX, 1280)
    }
    func testCameraCutoutCenterOverridesDisplayMidpoint() {
        let geometry = NotchGeometry(frame: NSRect(x: 0, y: 0, width: 1710, height: 1112), hardwareWidth: 209, hardwareHeight: 38, hardwareCenterX: 855.5)
        for expanded in [false, true] {
            for banner in [false, true] {
                let frame = geometry.frame(expanded: expanded, banner: banner, preferences: AppPreferences())
                XCTAssertEqual(frame.midX, 855.5, accuracy: 0.001)
                XCTAssertEqual(frame.maxY, 1112, accuracy: 0.001)
            }
        }
        let collapsed = geometry.frame(expanded: false, banner: false, preferences: AppPreferences())
        XCTAssertEqual(collapsed.minX + 32, 751)
        XCTAssertEqual(collapsed.maxX - 32, 960)
    }
    @MainActor func testNativePanelStaysAtPhysicalTopAfterOrderingAndResize() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)
        let geometry = NotchGeometry(screen: screen)
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        defer { panel.close() }
        for expanded in [false, true, false] {
            let expected = geometry.frame(expanded: expanded, banner: false, preferences: AppPreferences())
            panel.setFrame(expected, display: true); panel.orderFrontRegardless()
            XCTAssertEqual(panel.frame.maxY, expected.maxY, accuracy: 0.001)
            XCTAssertEqual(panel.frame.midX, expected.midX, accuracy: 0.001)
            XCTAssertEqual(panel.level, .statusBar)
        }
    }
    @MainActor func testNetworkFeaturesRejectLocalOnlyBeforeSending() async throws {
        let ai = AIService(); ai.input = "Never send this"
        ai.send(action: "Summarize", model: "test", allowed: false)
        XCTAssertNotNil(ai.error); XCTAssertFalse(ai.busy)
        let weather = WeatherService(); weather.fetch(preferences: AppPreferences()); XCTAssertNotNil(weather.error); XCTAssertFalse(weather.busy)
        let updates = UpdateService(); updates.check(feed: "https://example.com", allowed: false); XCTAssertFalse(updates.busy); XCTAssertTrue(updates.message.contains("Local-only"))
    }
    func testResponsesParseAllOutputItemsAndRefusals() throws {
        let json = Data(#"{"output":[{"type":"reasoning"},{"content":[{"type":"output_text","text":"First"},{"type":"output_text","text":"Second"}]},{"content":[{"type":"refusal","refusal":"Cannot do that"}]}]}"#.utf8)
        let response = try JSONDecoder().decode(AIService.Response.self, from: json)
        XCTAssertEqual(response.output.flatMap { $0.content ?? [] }.compactMap { $0.text ?? $0.refusal }, ["First", "Second", "Cannot do that"])
    }
    @MainActor func testUpgradeKeepsExistingPreferences() throws {
        let name = "nexa-migration-\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let old: [String: Any] = ["mediaConnected": true, "clipboardEnabled": true, "localOnly": false, "accent": "rose", "enabledModules": ["music", "files", "unknown-future-module"]]
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: "preferences.v1")
        let store = PreferencesStore(defaults: defaults)
        XCTAssertTrue(store.value.mediaConnected); XCTAssertTrue(store.value.clipboardEnabled); XCTAssertFalse(store.value.localOnly)
        XCTAssertEqual(store.value.accent, .rose); XCTAssertTrue(store.value.enabledModules.contains(.mirror)); XCTAssertFalse(store.value.enabledModules.contains(.calendar))
    }
    @MainActor func testBrowserMediaDecodeAndClearAndCommands() throws {
        let now = Date(timeIntervalSince1970: 2000)
        let payload: [String: Any] = ["bundleIdentifier": "com.browser.helper", "parentApplicationBundleIdentifier": "com.brave.Browser", "title": "Video", "playing": true, "durationMicros": 300_000_000, "elapsedTimeMicros": 5_000_000, "timestampEpochMicros": 1_998_000_000]
        let browser = try XCTUnwrap(SystemMediaBridge.decode(payload, now: now))
        XCTAssertEqual(browser.appID, "com.brave.Browser"); XCTAssertEqual(browser.position, 7, accuracy: 0.01)
        XCTAssertEqual(browser.duration, 300); XCTAssertEqual(browser.artist, "")
        XCTAssertNil(SystemMediaBridge.decode([:]))
        let bridge = TestMediaBridge()
        let media = NowPlayingService(bridge: bridge); media.start()
        bridge.onTrack?(MediaTrack(title: "Paused song", playing: false, appID: "com.apple.Music"))
        bridge.onTrack?(browser)
        XCTAssertEqual(media.track.title, "Video"); XCTAssertTrue(media.track.playing)
        media.command("playpause"); media.seek(99)
        XCTAssertEqual(bridge.commands, [["send", "2"], ["seek", "99000000"]])
        media.stop(); bridge.onTrack?(browser)
        XCTAssertTrue(media.track.appID.isEmpty); XCTAssertTrue(bridge.stopped)
    }
    @MainActor func testNotebookPersistsAndArchiveIsRecoverable() throws {
        let store = try temporaryStore(), notesStore = try temporaryStore()
        let notebook = NotebookService(store: notesStore)
        let id = notebook.addNote(); notebook.update(id, text: "A private note"); notebook.pin(id); notebook.save()
        let savedNotes = NotebookService(store: notesStore)
        XCTAssertEqual(savedNotes.notes.first?.text, "A private note"); XCTAssertEqual(savedNotes.notes.first?.pinned, true)
        let local = NotebookService(store: store); XCTAssertTrue(local.notes.isEmpty)
        local.addTask("Finish draft"); let task = try XCTUnwrap(local.tasks.first)
        local.favorite(task.id); local.complete(task.id, now: Date(timeIntervalSince1970: 10))
        let restored = NotebookService(store: store)
        XCTAssertTrue(restored.tasks[0].favorite); XCTAssertTrue(restored.archived(restored.tasks[0], now: Date(timeIntervalSince1970: 86411)))
        restored.complete(task.id); XCTAssertNil(restored.tasks[0].completedAt)
        XCTAssertFalse(restored.archived(restored.tasks[0]))
    }
    @MainActor func testMirrorNeverStartsOnInitialization() {
        let mirror = MirrorService(); XCTAssertFalse(mirror.active); XCTAssertFalse(mirror.starting); XCTAssertFalse(mirror.session.isRunning)
        mirror.stop(); XCTAssertFalse(mirror.active)
    }
    func testHomeIsShallowAndRetainsCameraCenterAcrossSizes() {
        let geometry = NotchGeometry(frame: NSRect(x: 0, y: 0, width: 1710, height: 1112), hardwareWidth: 209, hardwareHeight: 38, hardwareCenterX: 855.5)
        for size in ["Compact", "Normal", "Large"] {
            var preferences = AppPreferences(); preferences.layout = size
            let home = geometry.frame(expanded: true, banner: false, preferences: preferences, home: true)
            XCTAssertLessThan(home.height, 240); XCTAssertEqual(home.maxY, 1112); XCTAssertEqual(home.midX, 855.5)
        }
    }

    @MainActor private func motionFixture() throws -> (AppModel, NotchWindowController) {
        let name = "nexa-motion-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(preferences: PreferencesStore(defaults: defaults), store: try temporaryStore(), testing: true)
        model.preferences.value.hoverToOpen = false; model.preferences.value.hapticFeedback = false
        let controller = NotchWindowController(model: model); controller.pinnedOpen = true; controller.show()
        return (model, controller)
    }
    @MainActor func testRapidAnimationReversalSettlesWithoutStaleCompletion() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        controller.expand(true); try await Task.sleep(for: .milliseconds(65))
        controller.expand(false); try await Task.sleep(for: .milliseconds(45))
        controller.expand(true); try await Task.sleep(for: .milliseconds(520))
        let window = try XCTUnwrap(controller.window)
        let geometry = NotchGeometry(screen: try XCTUnwrap(window.screen))
        XCTAssertFalse(controller.transitionInFlight)
        XCTAssertEqual(window.frame, geometry.frame(expanded: true, banner: false, preferences: model.preferences.value, home: true))
        controller.expand(false); try await Task.sleep(for: .milliseconds(420))
        XCTAssertEqual(window.frame, geometry.frame(expanded: false, banner: false, preferences: model.preferences.value))
        XCTAssertFalse(controller.transitionInFlight)
    }
    @MainActor func testWidgetsDoNotRelayoutAtIntermediateWindowWidths() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        controller.expand(true)
        let window = try XCTUnwrap(controller.window)
        let surface = try XCTUnwrap(window.contentView as? NotchSurfaceView)
        let width = surface.expandedHost.frame.width, targetFrame = window.frame
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(surface.expandedHost.frame.width, width)
        XCTAssertEqual(window.frame, targetFrame)
        XCTAssertGreaterThan(width, 600)
        try await Task.sleep(for: .milliseconds(420))
        XCTAssertEqual(controller.hostingInstallCount, 1)
    }
    @MainActor func testAppearanceChangePreservesHostingTree() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        let content = controller.window?.contentView
        controller.expand(true)
        model.preferences.value.accent = .violet; model.preferences.value.opacity = 0.85
        try await Task.sleep(for: .milliseconds(560))
        XCTAssertTrue(controller.window?.contentView === content)
        XCTAssertEqual(controller.hostingInstallCount, 1)
        XCTAssertFalse(controller.transitionInFlight)
    }
    @MainActor func testGeometryExitDoesNotCollapseUnderPointer() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        controller.expand(true); try await Task.sleep(for: .milliseconds(450))
        controller.pinnedOpen = false; model.preferences.value.collapseDelay = 0.05
        let frame = try XCTUnwrap(controller.window).frame
        controller.pointerLocation = { NSPoint(x: frame.midX, y: frame.midY) }
        controller.hover(false); try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(model.expanded)
        controller.pointerLocation = { NSPoint(x: frame.minX - 100, y: frame.minY - 100) }
        controller.hover(false); try await Task.sleep(for: .milliseconds(420))
        XCTAssertFalse(model.expanded); XCTAssertFalse(controller.transitionInFlight)
    }

    @MainActor func testMenuOpenKeepsAnimationAndInactiveHostCannotReceiveClicks() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        controller.expand(true); controller.show()
        let surface = try XCTUnwrap(controller.window?.contentView as? NotchSurfaceView)
        XCTAssertTrue(controller.transitionInFlight)
        XCTAssertFalse(surface.compactHost.acceptsInteraction)
        XCTAssertNil(surface.compactHost.hitTest(NSPoint(x: 10, y: 10)))
        controller.expand(false); controller.expand(true)
        try await Task.sleep(for: .milliseconds(440))
        XCTAssertTrue(model.expanded); XCTAssertFalse(controller.transitionInFlight)
        XCTAssertEqual(surface.expandedHost.layer?.opacity, 1)
        XCTAssertEqual(surface.compactHost.layer?.opacity, 0)
        XCTAssertTrue(surface.compactHost.isHidden)
    }

    @MainActor func testReduceMotionSettlesAnInterruptedTransitionImmediately() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        controller.expand(true)
        controller.reduceMotion = { true }; controller.expand(false)
        let surface = try XCTUnwrap(controller.window?.contentView as? NotchSurfaceView)
        XCTAssertFalse(controller.transitionInFlight)
        XCTAssertFalse(surface.compactHost.isHidden); XCTAssertTrue(surface.expandedHost.isHidden)
        XCTAssertEqual(surface.compactHost.layer?.opacity, 1)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(model.expanded); XCTAssertFalse(controller.transitionInFlight)
        XCTAssertEqual(controller.window?.frame.height, ceil(max(30, controller.window?.screen?.safeAreaInsets.top ?? 0)))
    }

    @MainActor func testBannersAndSlowAnimationRetargetWithoutMovingCameraCenter() async throws {
        let (model, controller) = try motionFixture()
        defer { model.shutdown(); controller.window?.close() }
        let center = try XCTUnwrap(controller.window).frame.midX
        model.preferences.value.animationSpeed = 0.5
        model.banner = ActivityBanner(title: "Ready", detail: "Test", icon: "checkmark")
        controller.layout(animated: true)
        controller.expand(true); try await Task.sleep(for: .milliseconds(65))
        model.selected = .files; model.preferences.value.layout = "Large"
        try await Task.sleep(for: .milliseconds(100))
        controller.expand(false); model.banner = nil
        try await Task.sleep(for: .milliseconds(800))
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.frame.midX, center)
        XCTAssertEqual(window.frame.height, ceil(max(30, window.screen?.safeAreaInsets.top ?? 0)))
        XCTAssertFalse(controller.transitionInFlight)
    }

    @MainActor func testMotionPreferenceUpgradePreservesCustomTiming() throws {
        let name = "nexa-motion-upgrade-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONSerialization.data(withJSONObject: ["hoverDelay": 0.25, "collapseDelay": 0.65]), forKey: "preferences.v1")
        let upgraded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(upgraded.value.hoverDelay, 0.14); XCTAssertEqual(upgraded.value.collapseDelay, 0.42)
        defaults.set(try JSONSerialization.data(withJSONObject: ["hoverDelay": 0.6, "collapseDelay": 1.1]), forKey: "preferences.v1")
        let custom = PreferencesStore(defaults: defaults)
        XCTAssertEqual(custom.value.hoverDelay, 0.6); XCTAssertEqual(custom.value.collapseDelay, 1.1)
        defaults.removeObject(forKey: "preferences.v1")
    }

    @MainActor func testDeviceReadsRunOffMainAndStoppedResultsAreDiscarded() async throws {
        let began = expectation(description: "Device read began away from the UI thread")
        let completed = expectation(description: "Device read completed")
        let gate = DispatchSemaphore(value: 0)
        let controls = QuickControlsService {
            XCTAssertFalse(Thread.isMainThread); began.fulfill()
            _ = gate.wait(timeout: .now() + 2)
            completed.fulfill()
            return ControlsSnapshot(volume: 0.75, volumeAvailable: true, wifi: "On")
        }
        controls.refresh()
        await fulfillment(of: [began], timeout: 2)
        controls.stop(); gate.signal()
        await fulfillment(of: [completed], timeout: 2)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controls.volume, 0); XCTAssertFalse(controls.volumeAvailable)
    }

    @MainActor func testUnchangedMediaKeepsArtworkAndSourceClearsOnStop() throws {
        let bridge = TestMediaBridge()
        let media = NowPlayingService(bridge: bridge); media.start()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let track = MediaTrack(title: "Sample", appID: "com.apple.Music", artworkData: data)
        bridge.onTrack?(track)
        let artwork = try XCTUnwrap(media.artwork)
        bridge.onTrack?(track); media.refresh()
        XCTAssertTrue(media.artwork === artwork); XCTAssertEqual(media.sourceName, "Apple Music")
        media.stop(); bridge.onFailure?()
        XCTAssertNil(media.artwork); XCTAssertNil(media.sourceIcon); XCTAssertEqual(media.sourceName, "Now Playing")
        XCTAssertTrue(media.systemAvailable)
    }

    func testBrowserPlaybackRateAndInvalidNumbers() throws {
        let payload: [String: Any] = ["bundleIdentifier": "com.browser.player", "parentApplicationBundleIdentifier": "", "playing": true, "playbackRate": 2.0, "elapsedTimeMicros": 5_000_000, "timestampEpochMicros": 1_998_000_000, "durationMicros": Double.nan]
        let media = try XCTUnwrap(SystemMediaBridge.decode(payload, now: Date(timeIntervalSince1970: 2000)))
        XCTAssertEqual(media.appID, "com.browser.player"); XCTAssertEqual(media.position, 9); XCTAssertEqual(media.playbackRate, 2); XCTAssertEqual(media.duration, 0)
    }

    @MainActor func testMacMiniPanelUsesFloatingPillAndPreservesPositionAcrossLayouts() async throws {
        let (model, original) = try motionFixture(); original.window?.close()
        let screen = try XCTUnwrap(NSScreen.main)
        let geometry = NotchGeometry(frame: screen.frame, hardwareWidth: 170, hardwareHeight: 0)
        let controller = NotchWindowController(model: model, geometryOverride: geometry)
        defer { model.shutdown(); controller.window?.close() }
        controller.pinnedOpen = true; controller.reduceMotion = { true }; controller.show()
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 170, height: 30))
        XCTAssertEqual(controller.window?.frame.maxY, screen.frame.maxY - 6)
        controller.expand(true)
        XCTAssertEqual(controller.window?.frame.height, model.preferences.value.homeHeight)
        model.preferences.value.layout = "Large"; model.preferences.value.horizontalOffset = 70
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(controller.geometry.hasNotch)
        XCTAssertEqual(controller.window?.frame.midX, screen.frame.midX + 70)
        XCTAssertEqual(controller.window?.frame.width, 820)
        controller.expand(false)
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 170, height: 30))
    }

    func testFloatingPillHasRoundedTopCornersAndFullCenter() {
        let path = NotchSilhouette(radius: 14, shoulder: 0, detached: true).path(in: CGRect(x: 0, y: 0, width: 170, height: 30))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 169, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 85, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 85, y: 15)))
    }

    func testFractionalCutoutHeightPreservesThePhysicalTopEdge() {
        let geometry = NotchGeometry(frame: NSRect(x: 0, y: 0, width: 1710, height: 1112), hardwareWidth: 208, hardwareHeight: 37.5)
        let frame = geometry.frame(expanded: false, banner: false, preferences: AppPreferences())
        XCTAssertEqual(frame.height, 38)
        XCTAssertEqual(frame.minY, 1074)
        XCTAssertEqual(frame.maxY, 1112)
        XCTAssertEqual(frame.midX, 855)
    }

}

@MainActor private final class TestMediaBridge: MediaBridgeProtocol {
    var onTrack: ((MediaTrack?) -> Void)?
    var onFailure: (() -> Void)?
    var commands: [[String]] = []
    var stopped = false
    func start() {}
    func stop() { stopped = true }
    func send(_ command: [String], completion: @escaping (Bool) -> Void) { commands.append(command); completion(true) }
}
