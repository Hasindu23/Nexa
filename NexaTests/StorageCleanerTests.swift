import XCTest
import Foundation
@testable import Nexa

final class StorageCleanerTests: XCTestCase {
    struct Fixture {
        let home: URL
        let downloads: URL
        let trash: URL
        let store: LocalStore
        var policy: StoragePathPolicy { StoragePathPolicy(home: home) }
        var grant: StorageAgentGrant { StorageAgentGrant(deviceID: "fixture", scopes: ["CLEAN_STORAGE"], connected: true, expires: Date().addingTimeInterval(600)) }
        func file(_ name: String, contents: String = "fixture contents", days: Double = 100) throws -> URL {
            let url = downloads.appendingPathComponent(name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
            return url
        }
        func scan() throws -> StorageScan { try StorageScanner.scan(roots: [ScanRoot(url: downloads, category: .downloads, group: "Downloads")], policy: policy) }
        func engine(active: @escaping ([String]) throws -> Set<String> = { _ in [] }) -> StorageEngine {
            StorageEngine(policy: policy, store: store, deviceID: "fixture", trashHandler: { url in
                let destination = trash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination); return destination
            }, activeFileCheck: active)
        }
    }
    func fixture() throws -> Fixture {
        let home = SecureStorageFS.temporaryDirectory.appendingPathComponent("NexaStorageTest-\(UUID().uuidString)")
        let downloads = home.appendingPathComponent("Downloads"), trash = home.appendingPathComponent(".Trash")
        for folder in [downloads, trash, home.appendingPathComponent("Documents")] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: downloads.path); try? FileManager.default.removeItem(at: home) }
        return Fixture(home: home, downloads: downloads, trash: trash, store: LocalStore(root: home.appendingPathComponent("State")))
    }
    func assertBlocked(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected action to be blocked", file: file, line: line) } catch {}
    }
    func testProtectedPathsTraversalAndBoundary() throws {
        let f = try fixture()
        for path in ["/", "/System/Library/cache", "/Library/cache", f.home.path, f.home.appendingPathComponent("Documents/personal.txt").path, f.home.appendingPathComponent("Library/Keychains/login.keychain").path, "/Volumes/SystemClone/System/file"] { XCTAssertTrue(f.policy.isProtected(path), path) }
        XCTAssertFalse(f.policy.isProtected(f.downloads.appendingPathComponent("a.dmg").path))
        XCTAssertTrue(f.policy.isProtected(f.home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/History").path))
        XCTAssertTrue(f.policy.isProtected(f.home.appendingPathComponent("Library/Application Support/Firefox/Profiles/profile/cookies.sqlite").path))
        XCTAssertFalse(StoragePathPolicy.contains("/safe", "/safe-other/a"))
        XCTAssertThrowsError(try f.policy.validateSyntax("/safe/../Documents/a"))
        XCTAssertThrowsError(try f.policy.validateSyntax("relative/a"))
        XCTAssertThrowsError(try f.policy.validateSyntax("/safe/\0a"))
    }
    func testSymlinksAreNeverScannedOrFollowed() throws {
        let f = try fixture(), outside = f.home.appendingPathComponent("Documents/important.txt")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        let link = f.downloads.appendingPathComponent("installer.dmg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: f.downloads.appendingPathComponent("escape"), withDestinationURL: outside.deletingLastPathComponent())
        XCTAssertTrue(try f.scan().items.isEmpty)
        XCTAssertThrowsError(try SecureStorageFS.stamp(link.path))
        XCTAssertThrowsError(try SecureStorageFS.directory(f.downloads.appendingPathComponent("escape").path))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "private")
    }
    func testDuplicateDetectionUsesContentAndKeepsDifferentSameSizeFiles() throws {
        let f = try fixture()
        _ = try f.file("one.zip", contents: "AAAA"); _ = try f.file("unrelated-name.bin", contents: "AAAA"); _ = try f.file("one-copy.zip", contents: "BBBB")
        let scan = try StorageScanner.duplicates(f.scan())
        XCTAssertEqual(scan.items.filter { $0.duplicateHash != nil }.count, 2)
        XCTAssertNil(scan.items.first { $0.name == "one-copy.zip" }?.duplicateHash)
        XCTAssertTrue(scan.duplicateComplete)
    }
    func testRecommendationsDoNotIncludePersonalDownloadsOrRecentInstallers() throws {
        let f = try fixture()
        _ = try f.file("my-photos.zip"); _ = try f.file("old.dmg"); _ = try f.file("recent.pkg", days: 1); _ = try f.file("report.pdf")
        let scan = try f.scan()
        XCTAssertEqual(scan.items.filter(\.recommended).map(\.name), ["old.dmg"])
        XCTAssertEqual(scan.items.first { $0.name == "my-photos.zip" }?.category, .downloads)
        _ = try f.file("database.sqlite-wal")
        let cache = try StorageScanner.scan(roots: [ScanRoot(url: f.downloads, category: .caches, group: "Fixture cache", risk: .safe, recommendation: true)], policy: f.policy)
        XCTAssertEqual(cache.items.first { $0.name == "database.sqlite-wal" }?.eligible, false)
        _ = try f.file("Source.swift")
        let developer = try StorageScanner.scan(roots: [ScanRoot(url: f.downloads, category: .developer, group: "Xcode · DerivedData", risk: .safe, recommendation: true)], policy: f.policy)
        XCTAssertEqual(developer.items.first { $0.name == "Source.swift" }?.eligible, false)
    }
    func testHardLinksNeverBecomeCleanupCandidates() throws {
        let f = try fixture(), original = try f.file("first.dmg")
        try FileManager.default.linkItem(at: original, to: f.downloads.appendingPathComponent("second.dmg"))
        XCTAssertTrue(try f.scan().items.allSatisfy { !$0.eligible && !$0.recommended })
    }
    func testProtectedSelectedFolderIsReadOnly() throws {
        let f = try fixture(), docs = f.home.appendingPathComponent("Documents")
        try "private".write(to: docs.appendingPathComponent("file.pdf"), atomically: true, encoding: .utf8)
        let scan = try StorageScanner.scan(roots: [ScanRoot(url: docs, category: .largeFiles, group: "Documents")], policy: f.policy)
        XCTAssertEqual(scan.items.count, 1); XCTAssertEqual(scan.items.first?.eligible, false)
    }
    func testReviewDoesNotMutateAndRequiresConfirmation() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine(), scan = try f.scan()
        await engine.accept(scan)
        let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await assertBlocked { _ = try await engine.execute(planID: plan.id, confirmed: false, permanentPhrase: "", grant: f.grant) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testMoveTrashZeroReclaimedUndoAndReplayPrevention() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan())
        let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertEqual(receipt.succeeded.count, 1); XCTAssertEqual(receipt.reclaimedBytes, 0); XCTAssertEqual(receipt.recovery.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        await assertBlocked { _ = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant) }
        _ = try await engine.undo(receiptID: receipt.id)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "fixture contents")
        let history = try String(contentsOf: f.store.root.appendingPathComponent("storage-history.json"), encoding: .utf8)
        XCTAssertFalse(history.contains("fixture contents"))
    }
    func testPermanentDeletionRequiresAdditionalPhrase() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan())
        let plan = try await engine.prepare(ids: [url.path], action: .permanent, grant: f.grant)
        await assertBlocked { _ = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "DELETE", grant: f.grant)
        XCTAssertEqual(receipt.succeeded.count, 1); XCTAssertTrue(receipt.recovery.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)); XCTAssertLessThanOrEqual(receipt.reclaimedBytes, plan.allocatedBytes)
    }
    func testChangedFileAndSymlinkSwapFailClosed() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan())
        let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        try FileManager.default.removeItem(at: url)
        let outside = f.home.appendingPathComponent("Documents/private")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertEqual(receipt.failures.count, 1); XCTAssertEqual(receipt.reclaimedBytes, 0)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "private")
    }
    func testParentSymlinkSwapFailsClosed() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let moved = f.home.appendingPathComponent("RenamedDownloads")
        try FileManager.default.moveItem(at: f.downloads, to: moved)
        try FileManager.default.createSymbolicLink(at: f.downloads, withDestinationURL: moved)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("a.dmg").path))
    }
    func testPartialFailureCountsOnlySuccessfulMoves() async throws {
        let f = try fixture(), first = try f.file("active.dmg"), second = try f.file("inactive.pkg")
        let engine = f.engine(active: { _ in [first.path] })
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [first.path, second.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertEqual(receipt.succeeded, [second.path]); XCTAssertEqual(receipt.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path)); XCTAssertEqual(receipt.reclaimedBytes, 0)
    }
    func testPermissionDeniedDoesNotCountAsRemoved() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.downloads.path)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertEqual(receipt.reclaimedBytes, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testTrashFailureRestoresOriginal() async throws {
        let f = try fixture(), url = try f.file("a.dmg")
        let engine = StorageEngine(policy: f.policy, store: f.store, deviceID: "fixture", trashHandler: { _ in throw StorageFailure.blocked("Trash unavailable") }, activeFileCheck: { _ in [] })
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testUndoNeverOverwritesReplacement() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        try "replacement".write(to: url, atomically: true, encoding: .utf8)
        let undone = try await engine.undo(receiptID: receipt.id)
        XCTAssertEqual(undone.recovery.count, 1); XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "replacement")
    }
    func testCannotDeleteEveryDuplicateAndChangedKeeperIsSkipped() async throws {
        let f = try fixture(), one = try f.file("one.zip", contents: "AAAA"), two = try f.file("two.zip", contents: "AAAA"), engine = f.engine()
        await engine.accept(try StorageScanner.duplicates(f.scan()))
        await assertBlocked { _ = try await engine.prepare(ids: [one.path, two.path], action: .trash, grant: f.grant) }
        let plan = try await engine.prepare(ids: [two.path], action: .trash, grant: f.grant)
        try "BBBB".write(to: one, atomically: true, encoding: .utf8)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: two.path))
    }
    func testDisconnectedWrongScopeWrongDeviceAndUnknownItemRejected() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan())
        for grant in [StorageAgentGrant(deviceID: "fixture", scopes: ["CLEAN_STORAGE"], connected: false, expires: .distantFuture), StorageAgentGrant(deviceID: "fixture", scopes: ["FILES"], connected: true, expires: .distantFuture), StorageAgentGrant(deviceID: "other", scopes: ["CLEAN_STORAGE"], connected: true, expires: .distantFuture), StorageAgentGrant(deviceID: "fixture", scopes: ["CLEAN_STORAGE"], connected: true, expires: .distantPast)] {
            await assertBlocked { _ = try await engine.prepare(ids: [url.path], action: .trash, grant: grant) }
        }
        await assertBlocked { _ = try await engine.prepare(ids: ["/arbitrary/file"], action: .trash, grant: f.grant) }
        await assertBlocked { _ = try await engine.prepare(ids: [url.path], action: .cache, grant: f.grant) }
    }
    func testExpiredAndReprotectedPlansRejected() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant, now: Date().addingTimeInterval(-301))
        await assertBlocked { _ = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant) }
        var policy = f.policy; policy.additional.append(url.path)
        await engine.updatePolicy(policy)
        await assertBlocked { _ = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant) }
    }
    func testCanceledScanAndScanLimit() async throws {
        let f = try fixture()
        for index in 0..<20 { _ = try f.file("\(index).txt") }
        let job = Task.detached { try Task.checkCancellation(); return try f.scan() }
        job.cancel()
        do { _ = try await job.value; XCTFail("Canceled scan should not complete") } catch {}
        let limited = try StorageScanner.scan(roots: [ScanRoot(url: f.downloads, category: .downloads, group: "Downloads")], policy: f.policy, limit: 2)
        XCTAssertFalse(limited.complete); XCTAssertFalse(limited.issues.isEmpty)
    }
    func testDockerInventoryUnknownVolumesAreNotEligibleAndSharedImageBytesExcluded() {
        let items = StorageIntegrations.dockerItems([
            "Images": [["Id": "sha256:abc", "Containers": 0, "Size": 1000, "SharedSize": 800, "RepoTags": ["sample:latest"]]],
            "Volumes": [["Name": "important", "UsageData": ["RefCount": -1, "Size": 900]], ["Name": "unused", "UsageData": ["RefCount": 0, "Size": 50]]],
            "Containers": [["Id": "active", "State": "running", "SizeRw": 30]],
            "BuildCache": [["ID": "cache", "Size": 100]]
        ])
        XCTAssertEqual(items.first { $0.resourceKind == "docker-image" }?.bytes, 200)
        XCTAssertFalse(items.first { $0.path == "important" }!.eligible)
        XCTAssertEqual(items.first { $0.path == "unused" }?.risk, .sensitive)
        XCTAssertFalse(items.first { $0.resourceKind == "docker-container" }!.eligible)
        XCTAssertFalse(items.first { $0.resourceKind == "docker-build" }!.eligible)
        XCTAssertTrue(items.allSatisfy { !$0.recommended })
    }
    func testRealMacOSTrashPermissionBoundaryWithGeneratedFile() async throws {
        let f = try fixture(), url = try f.file("Nexa-generated-trash-check-\(UUID().uuidString).txt")
        let engine = StorageEngine(policy: f.policy, store: f.store, deviceID: "fixture", activeFileCheck: { _ in [] })
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertEqual(receipt.reclaimedBytes, 0)
        if receipt.succeeded.isEmpty {
            XCTAssertTrue(receipt.failures.contains { $0.contains("macOS denied access to Trash") }, receipt.failures.joined(separator: "\n"))
        } else { _ = try await engine.undo(receiptID: receipt.id) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testReadOnlyMountedFixtureCannotBeCleaned() async throws {
        let f = try fixture(); _ = try f.file("readonly.dmg")
        let image = f.home.appendingPathComponent("fixture.dmg"), mount = f.home.appendingPathComponent("ReadOnlyFixture")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try StorageProcess.run("/usr/bin/hdiutil", ["create", "-size", "20m", "-fs", "HFS+", "-volname", "Nexa QA", "-srcfolder", f.downloads.path, image.path], timeout: 40)
        _ = try StorageProcess.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, image.path], timeout: 30)
        defer { _ = try? StorageProcess.run("/usr/bin/hdiutil", ["detach", mount.path], timeout: 20) }
        let tree = try DiskExplorerScanner.scan(root: f.home)
        XCTAssertEqual(tree.entries[mount.path]?.skipped, 1)
        XCTAssertEqual(tree.entries[mount.path]?.note, "Another volume · not followed")
        XCTAssertNil(tree.entries[mount.appendingPathComponent("readonly.dmg").path])
        let readOnlyTree = try DiskExplorerScanner.scan(root: mount)
        XCTAssertEqual(readOnlyTree.measured.files, 1)
        let scan = try StorageScanner.scan(roots: [ScanRoot(url: mount, category: .downloads, group: "Read-only fixture")], policy: f.policy)
        XCTAssertEqual(scan.items.count, 1, scan.issues.joined(separator: "\n"))
        guard let item = scan.items.first else { return }
        let engine = f.engine(); await engine.accept(scan)
        let plan = try await engine.prepare(ids: [item.id], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertEqual(receipt.reclaimedBytes, 0)
        XCTAssertTrue(receipt.failures.contains { $0.contains("Read-only drive") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
    }
    func testMaximumLengthFilenamePreservedThroughTrashAndUndo() async throws {
        let f = try fixture(), name = String(repeating: "a", count: 251) + ".txt"
        let url = try f.file(name), engine = f.engine()
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertEqual(receipt.succeeded.count, 1, receipt.failures.joined(separator: "\n"))
        XCTAssertEqual(receipt.recovery.first.map { URL(fileURLWithPath: $0.trash).lastPathComponent }, name)
        _ = try await engine.undo(receiptID: receipt.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testHistorySaveFailureDoesNotHideSuccessfulCleanup() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), engine = f.engine()
        try FileManager.default.createDirectory(at: f.store.root.appendingPathComponent("storage-history.json"), withIntermediateDirectories: true)
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertEqual(receipt.succeeded, [url.path]); XCTAssertEqual(receipt.recovery.count, 1)
        XCTAssertTrue(receipt.failures.contains { $0.contains("history could not be saved") })
        XCTAssertEqual(StorageEngine.loadHistory(f.store).first?.id, receipt.id)
        XCTAssertEqual(StorageEngine.loadHistory(f.store).first?.recovery.count, 1)
    }
    func testRecoveryJournalPreservedWhenRollbackCannotOverwriteNewFile() async throws {
        let f = try fixture(), url = try f.file("a.dmg")
        let engine = StorageEngine(policy: f.policy, store: f.store, deviceID: "fixture", trashHandler: { _ in
            try "new replacement".write(to: url, atomically: true, encoding: .utf8)
            throw StorageFailure.blocked("Simulated Trash failure")
        }, activeFileCheck: { _ in [] })
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertTrue(receipt.failures.contains { $0.contains("File preserved at") })
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new replacement")
        let area = f.store.root.appendingPathComponent("StorageRecovery")
        let journals = try FileManager.default.contentsOfDirectory(at: area, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertEqual(journals.count, 1)
        let record = try JSONDecoder().decode(StorageRecoveryJournal.self, from: Data(contentsOf: XCTUnwrap(journals.first)))
        XCTAssertEqual(record.original, url.path)
        XCTAssertEqual(try String(contentsOfFile: record.staged, encoding: .utf8), "fixture contents")
    }
    func testUnverifiableTrashMoveReportsDestinationAndRetainsJournal() async throws {
        let f = try fixture(), url = try f.file("a.dmg"), reported = f.trash.appendingPathComponent("missing.txt")
        let engine = StorageEngine(policy: f.policy, store: f.store, deviceID: "fixture", trashHandler: { staged in
            try FileManager.default.moveItem(at: staged, to: f.trash.appendingPathComponent("actual.txt"))
            return reported
        }, activeFileCheck: { _ in [] })
        await engine.accept(try f.scan()); let plan = try await engine.prepare(ids: [url.path], action: .trash, grant: f.grant)
        let receipt = try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: "", grant: f.grant)
        XCTAssertTrue(receipt.succeeded.isEmpty); XCTAssertEqual(receipt.reclaimedBytes, 0)
        XCTAssertTrue(receipt.failures.contains { $0.contains(reported.path) && $0.contains("recovery record") })
    }
    @MainActor func testGroupSelectionIsCompleteAndBounded() async throws {
        let f = try fixture(), service = StorageService(store: f.store, home: f.home, testing: true)
        _ = try f.file("one.dmg")
        let item = try XCTUnwrap(f.scan().items.first)
        let items = (0..<5001).map { i in StorageItem(id: "fixture-\(i)", path: item.path, root: item.root, category: item.category, group: item.group, bytes: item.bytes, allocated: item.allocated, modified: item.modified, accessed: nil, created: nil, stamp: item.stamp, risk: item.risk, eligible: true, reason: "Fixture", recommended: false) }
        service.select(items)
        XCTAssertEqual(service.selection.count, 5000); XCTAssertNotNil(service.error)
        service.selection.removeAll(); service.select(Array(items.prefix(300)))
        XCTAssertEqual(service.selection.count, 300)
    }
}
