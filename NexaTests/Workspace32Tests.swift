import XCTest
import AppKit
import Carbon
import ImageIO
import UniformTypeIdentifiers
@testable import Nexa

final class Workspace32Tests: XCTestCase {
    @MainActor private func fixture() -> (AppModel, NotchWindowController) {
        let name = "app.nexa.workspace-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: root), testing: true)
        model.preferences.value.hapticFeedback = false
        let controller = NotchWindowController(model: model); controller.pinnedOpen = true
        addTeardownBlock { await MainActor.run { model.shutdown(); controller.window?.close(); UserDefaults(suiteName: name)?.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) } }
        return (model, controller)
    }
    @MainActor func testThreeStatesKeepHostsAndDisableInactiveInteraction() async throws {
        let (model, controller) = fixture()
        let surface = try XCTUnwrap(controller.window?.contentView as? NotchSurfaceView)
        let rail = surface.railHost
        controller.reduceMotion = { true }
        for state in [IslandPresentation.peek, .workspace, .peek, .ambient] {
            controller.present(state)
            XCTAssertEqual(model.presentation, state)
            XCTAssertEqual(model.expanded, state.isOpen)
            XCTAssertEqual(surface.peekHost.acceptsInteraction, state == .peek)
            XCTAssertEqual(surface.expandedHost.acceptsInteraction, state == .workspace)
            XCTAssertEqual(surface.compactHost.acceptsInteraction, state == .ambient)
            XCTAssertFalse(controller.transitionInFlight)
            XCTAssertTrue(surface.railHost === rail)
            XCTAssertEqual(controller.window?.frame, controller.geometry.frame(presentation: state, banner: false, preferences: model.preferences.value))
        }
        XCTAssertEqual(controller.hostingInstallCount, 1)
    }
    @MainActor func testWorkspaceSwitchingDoesNotCollapseOrRebuildRail() async throws {
        let (model, controller) = fixture(); controller.reduceMotion = { true }; controller.expand(true)
        let surface = try XCTUnwrap(controller.window?.contentView as? NotchSurfaceView)
        let frame = controller.window?.frame, rail = surface.railHost
        for module in ModuleID.allCases { model.selected = module; controller.layout(animated: false); XCTAssertEqual(controller.window?.frame, frame); XCTAssertEqual(model.presentation, .workspace); XCTAssertTrue(surface.railHost === rail) }
    }
    @MainActor func testPeekWorkspaceRapidReversalSettles() async throws {
        let (model, controller) = fixture()
        for i in 0..<20 { controller.present(i.isMultiple(of: 2) ? .peek : .workspace); try await Task.sleep(for: .milliseconds(15)) }
        controller.present(.peek); try await Task.sleep(for: .milliseconds(550))
        XCTAssertFalse(controller.transitionInFlight); XCTAssertEqual(model.presentation, .peek)
        XCTAssertEqual(controller.window?.frame, controller.geometry.frame(presentation: .peek, banner: false, preferences: model.preferences.value))
        XCTAssertEqual(controller.hostingInstallCount, 1)
    }
    @MainActor func testGlassWindowStaysDarkWhenSystemAppearanceChanges() throws {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let (_, controller) = fixture()
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: name)
            controller.present(.workspace)
            controller.layout(animated: false)
            let window = try XCTUnwrap(controller.window)
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            XCTAssertEqual(window.contentView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        }
    }
    func testGlassFallbackAndAccessibilityOverrideEveryStyle() {
        for style in NexaGlassStyle.allCases {
            var p = AppPreferences(); p.glassStyle = style
            XCTAssertEqual(NexaGlassEnvironment(preferences: p, nativeAvailable: false, reduceTransparency: false, increaseContrast: false).backend, .visualEffect)
            XCTAssertEqual(NexaGlassEnvironment(preferences: p, nativeAvailable: true, reduceTransparency: false, increaseContrast: false).backend, .native)
            let accessible = NexaGlassEnvironment(preferences: p, nativeAvailable: true, reduceTransparency: true, increaseContrast: true)
            XCTAssertEqual(accessible.backend, .opaque); XCTAssertEqual(accessible.tintAlpha, 1); XCTAssertGreaterThan(accessible.borderAlpha, 0.5); XCTAssertFalse(accessible.interactive)
            p.energySaving = true
            XCTAssertEqual(NexaGlassEnvironment(preferences: p, nativeAvailable: true, reduceTransparency: false, increaseContrast: false).backend, .opaque)
        }
    }
    func testRailReorderOverflowAndDisabledModules() {
        var p = AppPreferences(); p.railModules = [.music, .home, .music, .ai, .calendar]
        XCTAssertEqual(WorkspaceLayout.rail(p), [.music, .home, .calendar])
        XCTAssertEqual(WorkspaceLayout.move(.calendar, before: .music, in: [.home, .music, .calendar]), [.home, .calendar, .music])
        XCTAssertEqual(WorkspaceLayout.move(.ai, before: .home, in: [.home, .music]), [.home, .music])
        p.showWorkspaceRail = false; XCTAssertEqual(WorkspaceLayout.railExtent(p, presentation: .workspace), 0)
        p.showWorkspaceRail = true; XCTAssertEqual(WorkspaceLayout.railExtent(p, presentation: .peek), 0)
    }
    @MainActor func testOldPreferencesMigrateWithoutLosingPrivacyOrCustomChoices() throws {
        let name = "app.nexa.migration32.\(UUID().uuidString)", defaults = UserDefaults(suiteName: "app.nexa.migration32.\(UUID().uuidString)")!
        defer { defaults.removeObject(forKey: "preferences.v1") }
        let old: [String: Any] = ["accent": "violet", "clipboardEnabled": false, "mediaConnected": true, "localOnly": true, "centerWidget": "Notes", "preferredDisplay": "External", "enabledModules": ["home", "notes", "music"], "motionPreset": "playful"]
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: "preferences.v1")
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.value.accent, .violet); XCTAssertEqual(store.value.motionPreset, .playful)
        XCTAssertTrue(store.value.localOnly); XCTAssertFalse(store.value.clipboardEnabled); XCTAssertTrue(store.value.mediaConnected)
        XCTAssertEqual(store.value.preferredDisplay, "External"); XCTAssertTrue(store.value.homeWidgets.contains(where: { $0.module == .notes }))
        XCTAssertFalse(store.value.enabledModules.contains(.ai)); XCTAssertTrue(store.value.enabledModules.contains(.live))
        store.value.railModules = [.notes, .home]; store.value.rememberWorkspace = true; store.value.lastWorkspace = .notes
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.value.railModules, [.notes, .home]); XCTAssertEqual(WorkspaceLayout.initialModule(reloaded.value), .notes)
        XCTAssertFalse(name.isEmpty)
    }
    @MainActor func testUnknownNewPreferencesDoNotResetExistingChoices() throws {
        let defaults = UserDefaults(suiteName: "app.nexa.future32.\(UUID().uuidString)")!
        defer { defaults.removeObject(forKey: "preferences.v1") }
        defaults.set(try JSONSerialization.data(withJSONObject: ["accent": "rose", "glassStyle": "future", "appearanceMode": "future", "railModules": ["future", "music", "music"], "homeWidgets": [["module": "future", "size": "wide"], ["module": "notes", "size": "future"]]]), forKey: "preferences.v1")
        let p = PreferencesStore(defaults: defaults).value
        XCTAssertEqual(p.accent, .rose); XCTAssertEqual(p.glassStyle, .balanced)
        XCTAssertEqual(p.railModules, [.music]); XCTAssertEqual(p.homeWidgets, [HomeWidget(module: .notes)])
    }
    @MainActor func testLiveActivityDedupePriorityAndExpiry() {
        let store = LiveActivityStore(), now = Date()
        defer { store.stop() }
        store.put(id: "scan", title: "Scan", detail: "Scanning", icon: "externaldrive", module: .storage, state: .active, now: now)
        store.put(id: "timer", title: "Timer", detail: "Finished", icon: "timer", module: .timers, state: .completed, priority: .important, now: now)
        store.put(id: "scan", title: "Scan", detail: "Paused", icon: "externaldrive", module: .storage, state: .paused, now: now)
        XCTAssertEqual(store.items.count, 2); XCTAssertEqual(store.items.first?.id, "timer")
        store.dismiss("scan"); XCTAssertEqual(store.items.count, 2)
        store.expire(now: now.addingTimeInterval(301)); XCTAssertEqual(store.items.map(\.id), ["scan"])
        store.put(id: "scan", title: "Scan", detail: "Permission denied", icon: "externaldrive", module: .storage, state: .failed, now: now)
        store.dismiss("scan"); XCTAssertTrue(store.items.isEmpty)
    }
    func testCalendarMonthLeapYearAndWeekStart() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 12)))
        let days = CalendarMonth.days(containing: date, calendar: calendar)
        XCTAssertEqual(days.compactMap { $0 }.count, 29); XCTAssertEqual(days.prefix(while: { $0 == nil }).count, 3)
    }
    func testSelectedDisplayGeometryAndDragZoneStayWithinScreen() {
        let geometry = NotchGeometry(frame: NSRect(x: -1200, y: 100, width: 1200, height: 700), hardwareWidth: 170, hardwareHeight: 0, menuBarHeight: 24)
        for state in IslandPresentation.allCases {
            let frame = geometry.frame(presentation: state, banner: false, preferences: AppPreferences())
            XCTAssertTrue(geometry.screenFrame.contains(frame)); XCTAssertEqual(frame.maxY, 770)
        }
        XCTAssertTrue(DragActivation.contains(NSPoint(x: -600, y: 730), geometry: geometry))
        XCTAssertFalse(DragActivation.contains(NSPoint(x: -900, y: 730), geometry: geometry))
        XCTAssertFalse(DragActivation.contains(NSPoint(x: -600, y: 400), geometry: geometry))
    }
    @MainActor func testTaskMigrationDueDateFocusAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root)
        let id = UUID()
        let old = try JSONSerialization.data(withJSONObject: [["id": id.uuidString, "title": "Old task", "favorite": false]])
        try old.write(to: root.appendingPathComponent("tasks.json"))
        let notebook = NotebookService(store: store)
        XCTAssertEqual(notebook.tasks.first?.id, id); XCTAssertNil(notebook.tasks.first?.dueDate)
        notebook.focus(id); notebook.schedule(id, date: Date(timeIntervalSince1970: 12345))
        let reloaded = NotebookService(store: store)
        XCTAssertEqual(reloaded.tasks.first?.focused, true)
        XCTAssertEqual(reloaded.tasks.first?.dueDate, Date(timeIntervalSince1970: 12345))
        reloaded.complete(id); XCTAssertNotNil(reloaded.tasks.first?.completedAt)
    }
    @MainActor func testAIInstancesNeverShareInputOrOutput() {
        let first = AIService(), second = AIService()
        first.input = "Private input"; first.send(action: "Summarize", model: "unused", allowed: false)
        XCTAssertNotNil(first.error); XCTAssertFalse(first.busy); XCTAssertTrue(second.input.isEmpty); XCTAssertNil(second.error)
        first.clear(); XCTAssertTrue(first.input.isEmpty); XCTAssertNil(first.startedAt)
    }
    func testKeyboardShortcutsRequireDeliberateModifiers() {
        XCTAssertFalse(WorkspaceShortcut(action: .open, keyCode: 0, modifiers: UInt32(cmdKey), label: "A").valid)
        XCTAssertTrue(WorkspaceShortcut(action: .open, keyCode: 0, modifiers: UInt32(cmdKey | optionKey), label: "A").valid)
        XCTAssertFalse(WorkspaceShortcut(action: .open, keyCode: 200, modifiers: UInt32(cmdKey | optionKey), label: "A").valid)
    }
    @MainActor func testDisabledLiveModuleStaysDisabledOnRelaunch() {
        let name = "app.nexa.disabled-live.\(UUID().uuidString)", defaults = UserDefaults(suiteName: "app.nexa.disabled-live.\(UUID().uuidString)")!
        defer { defaults.removeObject(forKey: "preferences.v1") }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.toggle(.live, enabled: false)
        XCTAssertFalse(PreferencesStore(defaults: defaults).value.enabledModules.contains(.live))
        XCTAssertFalse(name.isEmpty)
    }
    @MainActor func testClearingPocketCancelsPendingImportsWithoutDeletingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("original.txt"); try Data("original".utf8).write(to: file)
        let shelf = FileShelfService(store: store)
        shelf.add([file]); shelf.clear(); await shelf.waitForImports()
        XCTAssertTrue(shelf.items.isEmpty); XCTAssertEqual(try Data(contentsOf: file), Data("original".utf8))
    }
    func testImageExportPreservesOriginalAndRefusesOverwriteOrAlias() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png"), target = root.appendingPathComponent("export.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.5)); context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        let image = try XCTUnwrap(context.makeImage()), data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: source)
        try ImageExport.write(source: source, destination: target, type: .jpeg)
        XCTAssertEqual(try Data(contentsOf: source), data as Data)
        let result = try XCTUnwrap(CGImageSourceCreateWithURL(target as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(result) as String?, UTType.jpeg.identifier)
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(result, 0, nil)); XCTAssertEqual(exported.width, 12); XCTAssertEqual(exported.height, 8)
        let originalExport = try Data(contentsOf: target)
        XCTAssertThrowsError(try ImageExport.write(source: source, destination: target, type: .jpeg))
        XCTAssertEqual(try Data(contentsOf: target), originalExport)
        let alias = root.appendingPathComponent("alias.png"); try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertThrowsError(try ImageExport.write(source: source, destination: alias, type: .png))
        XCTAssertEqual(try Data(contentsOf: source), data as Data)
    }

    @MainActor func testWorkspaceSwitchNeverResizesNativeWindow() async throws {
        let (model, controller) = fixture()
        controller.reduceMotion = { true }; controller.expand(true)
        var resizes = 0
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: controller.window, queue: .main) { _ in resizes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for module in [ModuleID.music, .calendar, .ai, .files, .home] { model.selected = module; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(resizes, 0); XCTAssertFalse(controller.transitionInFlight)
    }

    @MainActor func testReopenCanCreateMissingWorkspaceController() {
        let (model, fixtureController) = fixture(); fixtureController.window?.close()
        let app = AppDelegate(); app.model = model
        XCTAssertNil(app.notch)
        app.openNotch()
        XCTAssertNotNil(app.notch); XCTAssertEqual(model.presentation, .workspace)
        app.notch?.window?.close()
    }

}
