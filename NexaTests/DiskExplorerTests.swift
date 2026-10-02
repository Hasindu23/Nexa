import XCTest
import Darwin
@testable import Nexa

final class DiskExplorerTests: XCTestCase {
    func fixture() throws -> URL {
        let root = SecureStorageFS.temporaryDirectory.appendingPathComponent("NexaExplorerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    @discardableResult func file(_ root: URL, _ relative: String, _ count: Int = 8192) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: count).write(to: url)
        return url
    }
    func testHiddenHierarchyAndFolderTotalsIncludeLibraryAndDotFolders() throws {
        let root = try fixture()
        let hidden = try file(root, ".cache/nested/large.bin", 32768)
        let library = try file(root, "Library/Application Support/App/data.bin", 8192)
        let visible = try file(root, "visible.txt", 4096)
        let result = try DiskExplorerScanner.scan(root: root)
        XCTAssertEqual(result.measured.files, 3)
        XCTAssertEqual(result.measured.bytes, 45056)
        XCTAssertEqual(result.measured.allocated, try [hidden, library, visible].reduce(Int64(0)) { try $0 + SecureStorageFS.stamp($1.path).allocated })
        XCTAssertTrue(try XCTUnwrap(result.entries[hidden.path]).hidden)
        XCTAssertTrue(try XCTUnwrap(result.entries[library.path]).hidden)
        XCTAssertFalse(try XCTUnwrap(result.entries[visible.path]).hidden)
        XCTAssertEqual(result.contents(of: root.path).first?.name, ".cache")
        XCTAssertEqual(result.breadcrumbs(to: hidden.deletingLastPathComponent().path).map(\.name).suffix(2), [".cache", "nested"])
        XCTAssertEqual(result.fileOrder.first, hidden.path)
        let focused = try DiskExplorerScanner.scan(root: library.deletingLastPathComponent())
        XCTAssertTrue(focused.measured.hidden)
        XCTAssertTrue(try XCTUnwrap(focused.entries[library.path]).hidden)
    }
    func testLinksAreNotFollowedAndCannotEscapeRoot() throws {
        let root = try fixture(), outside = try fixture()
        let original = try file(outside, "private.bin", 16000)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.bin"), withDestinationURL: original)
        let result = try DiskExplorerScanner.scan(root: root)
        XCTAssertEqual(result.measured.files, 0); XCTAssertEqual(result.measured.allocated, 0); XCTAssertEqual(result.measured.skipped, 2)
        XCTAssertFalse(result.entries.keys.contains(original.path))
        XCTAssertThrowsError(try DiskExplorerScanner.scan(root: root.appendingPathComponent("escape")))
        XCTAssertEqual(try Data(contentsOf: original).count, 16000)
    }
    func testHardLinksAreCountedOnceAcrossDirectories() throws {
        let root = try fixture(), original = try file(root, "one/data.bin")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("two"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("two/copy.bin"))
        let result = try DiskExplorerScanner.scan(root: root)
        XCTAssertEqual(result.measured.bytes, 8192); XCTAssertEqual(result.measured.files, 1)
        XCTAssertEqual(result.measured.allocated, try SecureStorageFS.stamp(original.path).allocated)
        XCTAssertEqual(result.measured.skipped, 1)
    }
    func testLogicalAndAllocatedSizesUseFilesystemValuesSeparately() throws {
        let root = try fixture(), url = try file(root, "sparse.bin", 1)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 16 * 1024 * 1024); try handle.write(contentsOf: Data([1])); try handle.close()
        let result = try DiskExplorerScanner.scan(root: root)
        XCTAssertEqual(result.measured.bytes, 16 * 1024 * 1024 + 1)
        XCTAssertEqual(result.measured.allocated, try SecureStorageFS.stamp(url.path).allocated)
        XCTAssertNotEqual(result.measured.allocated, result.measured.bytes)
    }
    func testMetadataOnlyScanDoesNotReadFileContentsAndSkipsCredentials() throws {
        let root = try fixture(), file = try file(root, "Library/Application Support/database.bin")
        _ = try self.file(root, ".ssh/id_private", 4000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        let result = try DiskExplorerScanner.scan(root: root)
        XCTAssertEqual(result.measured.files, 1); XCTAssertEqual(result.measured.bytes, 8192)
        XCTAssertEqual(result.entries[root.appendingPathComponent(".ssh").path]?.skipped, 1)
        XCTAssertNil(result.entries[root.appendingPathComponent(".ssh/id_private").path])
    }
    func testPermissionDeniedDirectoryIsReportedAsUnmeasured() throws {
        let root = try fixture(); _ = try file(root, "restricted/file.bin")
        let directory = root.appendingPathComponent("restricted")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let result = try DiskExplorerScanner.scan(root: root)
        XCTAssertEqual(result.measured.files, 0); XCTAssertEqual(result.measured.skipped, 1)
        XCTAssertTrue(result.entries[directory.path]?.note?.contains("Permission denied") == true)
    }
    func testEntryAndDepthLimitsAreVisible() throws {
        let root = try fixture()
        for i in 0..<10 { _ = try file(root, "\(i).bin") }
        let limited = try DiskExplorerScanner.scan(root: root, limit: 3)
        XCTAssertTrue(limited.limited); XCTAssertEqual(limited.measured.files, 3); XCTAssertGreaterThan(limited.measured.skipped, 0)
        let shallow = try DiskExplorerScanner.scan(root: root, maxDepth: 0)
        XCTAssertTrue(shallow.limited); XCTAssertEqual(shallow.measured.files, 0)
    }
    func testCanceledAnalysisDoesNotReturnACompleteInventory() async throws {
        let root = try fixture()
        for index in 0..<600 { _ = try file(root, "sample-\(index)", 1) }
        let worker = Task.detached {
            try DiskExplorerScanner.scan(root: root) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        do { _ = try await worker.value; XCTFail("Canceled analysis should fail") } catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sample-0").path))
    }
    func testNewHiddenCachesAreNarrowAndSensitiveFilesRemainProtected() throws {
        let home = try fixture()
        let cache = try file(home, ".npm/_cacache/content-v2/cache")
        let credential = try file(home, ".npmrc")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86400)], ofItemAtPath: cache.path)
        let roots = StorageScanner.roots(home: home, settings: StorageSettings()).filter { $0.url.path.hasPrefix(home.path) }
        let result = try StorageScanner.scan(roots: roots, policy: StoragePathPolicy(home: home))
        XCTAssertEqual(result.items.first { $0.path == cache.path }?.recommended, true)
        XCTAssertFalse(result.items.contains { $0.path == credential.path })
        let policy = StoragePathPolicy(home: home)
        for path in [".ssh/key", ".docker/data.raw", ".ollama/models/data", "Library/Application Support/MobileSync/Backup/file", "Library/Containers/app/Data/file", "project/.git/config"] {
            XCTAssertTrue(policy.isProtected(home.appendingPathComponent(path).path), path)
        }
    }
    func testCleanupRoutesRequireKnownLocationsAndRespectPathBoundaries() throws {
        let home = try fixture()
        XCTAssertEqual(DiskCleanupGuide.category(for: home.appendingPathComponent(".npm/_cacache/data").path, home: home), .caches)
        XCTAssertNil(DiskCleanupGuide.category(for: home.appendingPathComponent(".npm/_cacache-other/data").path, home: home))
        XCTAssertNil(DiskCleanupGuide.category(for: home.appendingPathComponent("Library/Application Support/App/data").path, home: home))
        XCTAssertEqual(DiskCleanupGuide.canonical("/System/Volumes/Data/Users/test/Library"), "/Users/test/Library")
        XCTAssertEqual(DiskCleanupGuide.canonical("/System/Volumes/Data-other/file"), "/System/Volumes/Data-other/file")
    }
    func testSnapshotParserUsesActualDiskutilKeysAndRejectsUnknownResponse() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Snapshots": [["SnapshotName": "com.apple.TimeMachine.fixture", "SnapshotUUID": "fixture-id", "Purgeable": true]]], format: .xml, options: 0)
        let snapshots = try DiskSnapshots.parse(data)
        XCTAssertEqual(snapshots.first?.name, "com.apple.TimeMachine.fixture"); XCTAssertEqual(snapshots.first?.purgeable, true)
        let empty = try PropertyListSerialization.data(fromPropertyList: ["Snapshots": []], format: .xml, options: 0)
        XCTAssertTrue(try DiskSnapshots.parse(empty).isEmpty)
        let invalid = try PropertyListSerialization.data(fromPropertyList: ["Unrecognized": []], format: .xml, options: 0)
        XCTAssertThrowsError(try DiskSnapshots.parse(invalid))
    }
    @MainActor func testNavigatingAndCancelingNeverCreatesACleanupPlan() throws {
        let home = try fixture(); _ = try file(home, ".cache/one.bin")
        let service = StorageService(store: LocalStore(root: home.appendingPathComponent("State")), home: home, testing: true)
        service.explorer.loadFixture(try DiskExplorerScanner.scan(root: home))
        service.explorer.navigate(home.appendingPathComponent(".cache").path)
        XCTAssertEqual(service.explorer.folder?.name, ".cache")
        service.explorer.cancel()
        XCTAssertNil(service.plan); XCTAssertTrue(service.selection.isEmpty); XCTAssertNil(service.scan)
        service.explorer.invalidate(); XCTAssertNil(service.explorer.result)
    }
}
