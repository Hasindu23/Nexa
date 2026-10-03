import AppKit
import SwiftUI

extension AppDelegate {
    /// Isolated native-window QA. All files are generated fixtures, never user data.
    func runStorageQA(output: URL) {
        let suite = "app.nexa.qa.storage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = SecureStorageFS.temporaryDirectory.appendingPathComponent(suite)
        model = AppModel(preferences: PreferencesStore(defaults: defaults), store: LocalStore(root: scratch.appendingPathComponent("State")), testing: true, storageHome: scratch)
        model.preferences.value.completedOnboarding = true
        Task { @MainActor in
            var checks: [String] = []
            do {
                let fixtures = scratch.appendingPathComponent("Downloads")
                try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                for (name, size) in [("Old installer.dmg", 2_000_000), ("Design archive.zip", 1_000_000), ("Design archive copy.zip", 1_000_000), ("Screen Recording.mov", 500_000)] {
                    try Data(repeating: name.hasSuffix("zip") ? 42 : 7, count: size).write(to: fixtures.appendingPathComponent(name))
                    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-95 * 86400)], ofItemAtPath: fixtures.appendingPathComponent(name).path)
                }
                var result = try StorageScanner.scan(roots: [ScanRoot(url: fixtures, category: .downloads, group: "QA Downloads")], policy: StoragePathPolicy(home: scratch))
                result = try StorageScanner.duplicates(result)
                guard result.items.count == 4, result.items.filter({ $0.duplicateHash != nil }).count == 2 else { throw StorageFailure.blocked("Fixture scan or duplicate verification failed.") }
                checks.append("PASS: temporary fixtures scanned and SHA-256 duplicate group verified")
                await model.storage.loadFixture(result)
                showStorage()
                guard let window = storageWindow else { throw StorageFailure.blocked("Storage window did not open.") }
                try await Task.sleep(for: .milliseconds(600))
                try storageSnapshot(window, output.appendingPathComponent("storage-overview.png"))
                checks.append("PASS: full native Storage Cleaner window rendered")
                let installer = result.items.first { $0.category == .installers }!
                model.storage.selection = [installer.id]; model.storage.action = .trash; model.storage.review()
                try await Task.sleep(for: .milliseconds(600))
                guard model.storage.plan?.items.count == 1, FileManager.default.fileExists(atPath: installer.path) else { throw StorageFailure.blocked("Review was not generated or changed original file.") }
                if let sheet = window.sheets.first { try storageSnapshot(sheet, output.appendingPathComponent("storage-review.png")) }
                checks.append("PASS: exact-item review opens and original remains untouched")
                model.storage.plan = nil
                try await Task.sleep(for: .milliseconds(700))
                // Exercise native sidebar hit testing, without private accessibility permissions.
                storageClick(window, NSPoint(x: 94, y: window.contentView!.bounds.height - 327))
                try await Task.sleep(for: .milliseconds(350))
                guard model.storage.destination == "downloads" else { throw StorageFailure.blocked("Native sidebar click did not navigate to Downloads.") }
                try storageSnapshot(window, output.appendingPathComponent("storage-category.png"))
                checks.append("PASS: native category navigation renders after a mouse event")
                model.storage.action = .permanent; model.storage.review()
                try await Task.sleep(for: .milliseconds(600))
                guard let sheet = window.sheets.first else { throw StorageFailure.blocked("Permanent review did not open.") }
                storageClick(sheet, NSPoint(x: sheet.frame.width - 130, y: 42))
                try await Task.sleep(for: .milliseconds(400))
                try storageSnapshot(sheet, output.appendingPathComponent("storage-permanent-confirmation.png"))
                guard FileManager.default.fileExists(atPath: installer.path) else { throw StorageFailure.blocked("Permanent review changed the original without typed confirmation.") }
                checks.append("PASS: second permanent-deletion confirmation renders; original remains untouched")
                model.storage.plan = nil
                try await Task.sleep(for: .milliseconds(600))
                window.close()
                _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                try await Task.sleep(for: .milliseconds(250))
                guard window.isVisible, storageWindow === window else { throw StorageFailure.blocked("App-icon reopen did not restore the existing main window.") }
                window.miniaturize(nil)
                showPrimaryWindow()
                try await Task.sleep(for: .milliseconds(300))
                guard !window.isMiniaturized, window.isVisible else { throw StorageFailure.blocked("App-icon reopen did not restore the minimized window.") }
                window.setFrameOrigin(NSPoint(x: 50000, y: 50000))
                showPrimaryWindow()
                guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) else { throw StorageFailure.blocked("Main window remained outside all displays.") }
                checks.append("PASS: app-icon reopen restores closed, minimized and off-screen windows")
                for (path, size) in [(".npm/_cacache/content-v2/cache", 8_000_000), ("Library/Application Support/Creative App/projects.db", 12_000_000), ("Library/Application Support/MobileSync/Backup/Fixture/backup.bin", 6_000_000), (".ollama/models/blobs/model", 10_000_000), ("Library/Developer/Xcode/DerivedData/Build/objects.bin", 4_000_000), ("Movies/Project.mov", 16_000_000)] {
                    let url = scratch.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(repeating: 37, count: size).write(to: url)
                }
                let disk = try await Task.detached(priority: .utility) { try DiskExplorerScanner.scan(root: scratch) }.value
                model.storage.selection.removeAll()
                model.storage.explorer.loadFixture(disk); model.storage.destination = "explorer"
                try await Task.sleep(for: .milliseconds(700))
                try storageSnapshot(window, output.appendingPathComponent("disk-explorer-overview.png"))
                guard disk.measured.files >= 10, disk.entries[scratch.appendingPathComponent(".npm").path]?.hidden == true else { throw StorageFailure.blocked("Hidden folder inventory is incomplete.") }
                storageClick(window, NSPoint(x: 620, y: window.contentView!.bounds.height - 586))
                try await Task.sleep(for: .milliseconds(350))
                guard model.storage.explorer.current == scratch.appendingPathComponent("Library").path else { throw StorageFailure.blocked("Native explorer folder click did not drill down.") }
                model.storage.explorer.navigate(scratch.appendingPathComponent(".npm/_cacache").path)
                try await Task.sleep(for: .milliseconds(400))
                try storageSnapshot(window, output.appendingPathComponent("disk-explorer-folder.png"))
                guard model.storage.explorer.folder?.name == "_cacache", model.storage.plan == nil, model.storage.selection.isEmpty, FileManager.default.fileExists(atPath: scratch.appendingPathComponent(".npm/_cacache/content-v2/cache").path) else { throw StorageFailure.blocked("Explorer changed a file or failed to drill into a folder.") }
                checks.append("PASS: hidden SSD explorer renders, measures hidden folders, handles a native folder click and drills into a cache without selecting or deleting files")
                let cachePath = scratch.appendingPathComponent(".npm/_cacache/content-v2/cache").path
                model.storage.reviewFromExplorer(disk.entries[scratch.appendingPathComponent(".npm/_cacache").path]!)
                for _ in 0..<200 { if !model.storage.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard !model.storage.busy, model.storage.scan?.items.count == 1, model.storage.selection.isEmpty,
                      let cache = model.storage.scan?.items.first, cache.path == cachePath, cache.eligible else {
                    throw StorageFailure.blocked("Focused review did not preserve the exact cache scope.")
                }
                try await Task.sleep(for: .milliseconds(400))
                try storageSnapshot(window, output.appendingPathComponent("focused-removal-review.png"))
                model.storage.select([cache]); model.storage.action = .cache; model.storage.review()
                for _ in 0..<100 { if !model.storage.busy { break }; try await Task.sleep(for: .milliseconds(30)) }
                try await Task.sleep(for: .milliseconds(500))
                guard let cacheSheet = window.sheets.first, model.storage.plan?.items.count == 1 else { throw StorageFailure.blocked("Cache confirmation did not open.") }
                storageClick(cacheSheet, NSPoint(x: cacheSheet.frame.width - 130, y: 42))
                try await Task.sleep(for: .milliseconds(300))
                try storageSnapshot(cacheSheet, output.appendingPathComponent("cache-permanent-confirmation.png"))
                guard FileManager.default.fileExists(atPath: cachePath) else { throw StorageFailure.blocked("Cache changed before typed confirmation.") }
                model.storage.confirm(phrase: "DELETE") // Generated fixture only, never a personal cache.
                for _ in 0..<300 { if !model.storage.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard !model.storage.busy, model.storage.lastReceipt?.succeeded == [cachePath],
                      model.storage.lastReceipt?.failures.isEmpty == true, model.storage.scan?.items.isEmpty == true,
                      !FileManager.default.fileExists(atPath: cachePath),
                      FileManager.default.fileExists(atPath: scratch.appendingPathComponent("Library/Application Support/Creative App/projects.db").path),
                      model.storage.explorer.result == nil else { throw StorageFailure.blocked("Confirmed cache removal or rescan verification failed.") }
                try await Task.sleep(for: .milliseconds(400))
                try storageSnapshot(window, output.appendingPathComponent("cleanup-result.png"))
                checks.append("PASS: focused cache review requires confirmation, removes only the generated cache, preserves app data, records success and rescans")
                let sample = MemorySnapshot(date: Date(), total: 16_000_000_000, free: 4_000_000_000, wired: 2_000_000_000,
                                            compressed: 1_000_000_000, swap: 0, pressure: 1)
                var helperApp = MemoryApp(pid: 2_000_000, name: "Example Editor · QA fixture", bundleID: "app.fixture.editor",
                                          bundlePath: "/Applications/Fixture.app", launched: Date(), regular: true, owned: true, bytes: 640_000_000)
                var helper: NSRunningApplication?
                if CommandLine.arguments.contains("--qa-memory-helper") {
                    helper = NSRunningApplication.runningApplications(withBundleIdentifier: "app.nexa.qa.memoryhelper").first {
                        $0.bundleURL?.resolvingSymlinksInPath().path.hasPrefix(SecureStorageFS.temporaryDirectory.resolvingSymlinksInPath().path + "/NexaMemoryQA-") == true
                    }
                    guard let helper else { throw StorageFailure.blocked("Isolated memory QA helper is not running.") }
                    helperApp = MemoryApp.capture(helper)
                    guard helperApp.canQuit else { throw StorageFailure.blocked("QA helper cannot be safely quit.") }
                }
                model.storage.memory.loadFixture(sample, apps: [helperApp]); model.storage.destination = "memory"
                try await Task.sleep(for: .milliseconds(500))
                try storageSnapshot(window, output.appendingPathComponent("memory-overview.png"))
                model.storage.memory.reviewQuit(helperApp)
                try await Task.sleep(for: .milliseconds(500))
                guard let memorySheet = window.sheets.first else { throw StorageFailure.blocked("Memory quit review did not open.") }
                try storageSnapshot(memorySheet, output.appendingPathComponent("memory-quit-review.png"))
                model.storage.memory.pendingQuit = nil
                guard helper?.isTerminated != true else { throw StorageFailure.blocked("Review canceled but helper quit.") }
                checks.append("PASS: memory dashboard and app-quit review render; canceling review leaves the app running")
                if let helper {
                    model.storage.memory.reviewQuit(helperApp); model.storage.memory.confirmQuit()
                    for _ in 0..<200 { if !model.storage.memory.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                    guard helper.isTerminated, model.storage.memory.error == nil else { throw StorageFailure.blocked("Confirmed normal quit of isolated helper failed.") }
                    checks.append("PASS: explicit confirmation sends a normal quit to the isolated QA helper and refreshes real memory measurements")
                }
                let report = "Nexa Storage Cleaner native smoke check\n" + checks.joined(separator: "\n") + "\nScreenshots use a labeled QA fixture of generated temporary files. No real user file was cleaned.\n"
                try report.write(to: output.appendingPathComponent("storage-smoke-check.txt"), atomically: true, encoding: .utf8)
            } catch { try? ("FAIL: \(error.localizedDescription)\n" + checks.joined(separator: "\n")).write(to: output.appendingPathComponent("storage-smoke-check.txt"), atomically: true, encoding: .utf8) }
            storageWindow?.close(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: scratch); NSApp.terminate(nil)
        }
    }
    private func storageSnapshot(_ window: NSWindow, _ url: URL) throws {
        guard let view = window.contentView else { throw StorageFailure.blocked("No native content view.") }
        view.layoutSubtreeIfNeeded(); window.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw StorageFailure.blocked("Cannot capture native view.") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw StorageFailure.blocked("Cannot encode screenshot.") }
        try data.write(to: url)
    }
    private func storageClick(_ window: NSWindow, _ point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) { window.sendEvent(event) }
        }
    }
}
