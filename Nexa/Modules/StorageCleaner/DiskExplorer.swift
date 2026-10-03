import Foundation
import AppKit
import Combine
import Darwin

/// Inventory only. These values are deliberately not cleanup capabilities or StorageItems.
struct DiskEntry: Identifiable, Sendable {
    let path: String
    let parent: String?
    let directory: Bool
    let hidden: Bool
    var bytes: Int64 = 0
    var allocated: Int64 = 0
    var files = 0
    var skipped = 0
    var note: String?
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent.isEmpty ? "/" : URL(fileURLWithPath: path).lastPathComponent }
}

struct DiskAnalysis: Sendable {
    let root: String
    let date: Date
    let entries: [String: DiskEntry]
    let children: [String: [String]]
    let fileOrder: [String]
    let total: Int64
    let free: Int64
    let limited: Bool
    var measured: DiskEntry { entries[root]! }
    func contents(of path: String) -> [DiskEntry] {
        (children[path] ?? []).compactMap { entries[$0] }.sorted {
            $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated
        }
    }
    func breadcrumbs(to path: String) -> [DiskEntry] {
        var result: [DiskEntry] = [], current: String? = path
        while let key = current, let node = entries[key] {
            result.append(node); current = node.parent
        }
        return result.reversed()
    }
}

enum DiskExplorerScanner {
    private struct Identity: Hashable { let device: Int32; let inode: UInt64 }
    static func scan(root: URL, limit: Int = 250_000, maxDepth: Int = 64,
                     progress: @Sendable (Int) -> Void = { _ in }) throws -> DiskAnalysis {
        try Task.checkCancellation()
        try StoragePathPolicy(home: root).validateSyntax(root.path)
        let fd = try SecureStorageFS.directory(root.path); defer { close(fd) }
        var rootInfo = stat()
        guard fstat(fd, &rootInfo) == 0 else { throw SecureStorageFS.failure("Inspect selected location") }
        let capacity = SecureStorageFS.capacity(at: root)
        var entries: [String: DiskEntry] = [:], children: [String: [String]] = [:]
        var seen = Set<Identity>(), visited = 0, limited = false
        // Never enumerate credential stores. Other data is measured using metadata, never read.
        let privateNames: Set<String> = [".ssh", ".gnupg", ".aws", ".azure", "Keychains"]
        func walk(_ path: String, parent: String?, info: stat, directoryFD: Int32?, depth: Int, inheritedHidden: Bool) throws -> DiskEntry {
            try Task.checkCancellation()
            let name = URL(fileURLWithPath: path).lastPathComponent
            let isDirectory = info.st_mode & S_IFMT == S_IFDIR
            var node = DiskEntry(path: path, parent: parent, directory: isDirectory,
                                 hidden: inheritedHidden || name.hasPrefix(".") || info.st_flags & UInt32(UF_HIDDEN) != 0 || name == "Library")
            func skipped(_ note: String) -> DiskEntry {
                node.skipped = 1; node.note = note; entries[path] = node; return node
            }
            guard info.st_dev == rootInfo.st_dev else { return skipped("Another volume · not followed") }
            guard isDirectory || info.st_mode & S_IFMT == S_IFREG else { return skipped("Link or special file · not followed") }
            guard !privateNames.contains(name) else { return skipped("Credential store · contents not inspected") }
            // Dataless iCloud placeholders must not be downloaded just to calculate a size.
            guard info.st_flags & 0x40000000 == 0 else { return skipped("Cloud placeholder · not downloaded") }
            guard seen.insert(Identity(device: info.st_dev, inode: info.st_ino)).inserted else { return skipped("Shared hard link · allocation counted once") }
            if !isDirectory {
                node.bytes = max(0, info.st_size); node.allocated = max(0, Int64(info.st_blocks) * 512); node.files = 1
            } else {
                guard depth < maxDepth else { limited = true; return skipped("Depth limit reached · partial size") }
                guard let directoryFD else { return skipped("Permission denied or directory changed · size unavailable") }
                let copy = dup(directoryFD)
                guard copy >= 0 else { return skipped("Cannot open directory inventory") }
                guard let stream = fdopendir(copy) else { close(copy); return skipped("Cannot read directory inventory") }
                defer { closedir(stream) }
                while true {
                    try Task.checkCancellation()
                    errno = 0
                    guard let entry = readdir(stream) else {
                        if errno != 0 { node.skipped += 1; node.note = "Directory could not be read completely" }
                        break
                    }
                    let childName = withUnsafePointer(to: &entry.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
                    }
                    if childName == "." || childName == ".." { continue }
                    guard visited < limit else { limited = true; node.skipped += 1; node.note = "Entry limit reached · choose a smaller folder"; break }
                    visited += 1
                    if visited % 500 == 0 { progress(visited) }
                    let childPath = URL(fileURLWithPath: path).appendingPathComponent(childName).path
                    var childInfo = stat()
                    guard fstatat(directoryFD, childName, &childInfo, AT_SYMLINK_NOFOLLOW) == 0 else {
                        let missing = DiskEntry(path: childPath, parent: path, directory: false, hidden: node.hidden || childName.hasPrefix("."), skipped: 1, note: "Unavailable or changed during scan")
                        entries[childPath] = missing; children[path, default: []].append(childPath); node.skipped += 1; continue
                    }
                    var childFD: Int32?
                    if childInfo.st_mode & S_IFMT == S_IFDIR && childInfo.st_dev == rootInfo.st_dev && !privateNames.contains(childName) && childInfo.st_flags & 0x40000000 == 0 {
                        let opened = openat(directoryFD, childName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                        if opened >= 0 {
                            var held = stat()
                            if fstat(opened, &held) == 0 && held.st_dev == childInfo.st_dev && held.st_ino == childInfo.st_ino { childFD = opened }
                            else { close(opened) }
                        }
                    }
                    let child: DiskEntry
                    do { child = try walk(childPath, parent: path, info: childInfo, directoryFD: childFD, depth: depth + 1, inheritedHidden: node.hidden) }
                    catch { if let childFD { close(childFD) }; throw error }
                    if let childFD { close(childFD) }
                    children[path, default: []].append(childPath)
                    node.bytes += child.bytes; node.allocated += child.allocated; node.files += child.files; node.skipped += child.skipped
                }
            }
            entries[path] = node; return node
        }
        let hiddenAncestor = root.path.split(separator: "/").dropLast().contains { $0.hasPrefix(".") || $0 == "Library" }
        _ = try walk(root.path, parent: nil, info: rootInfo, directoryFD: fd, depth: 0, inheritedHidden: hiddenAncestor)
        try Task.checkCancellation()
        let fileOrder = entries.values.filter { !$0.directory && $0.files > 0 }.sorted { $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated }.map(\.path)
        return DiskAnalysis(root: root.path, date: Date(), entries: entries, children: children, fileOrder: fileOrder, total: capacity.total, free: capacity.free, limited: limited)
    }
}

struct DiskSnapshot: Identifiable, Sendable {
    let id: String
    let name: String
    let purgeable: Bool?
    let volume: String
}

enum DiskSnapshots {
    static func parse(_ data: Data, volume: String = "Data") throws -> [DiskSnapshot] {
        guard let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let snapshots = object["Snapshots"] as? [[String: Any]] else { throw StorageFailure.blocked("Snapshot information is unavailable.") }
        return try snapshots.map { value in
            guard let name = value["SnapshotName"] as? String, !name.isEmpty else { throw StorageFailure.blocked("Snapshot response is incomplete.") }
            return DiskSnapshot(id: volume + ":" + (value["SnapshotUUID"] as? String ?? name), name: name, purgeable: value["Purgeable"] as? Bool, volume: volume)
        }
    }
    static func read() throws -> [DiskSnapshot] {
        let data = try parse(StorageProcess.run("/usr/sbin/diskutil", ["apfs", "listSnapshots", "/System/Volumes/Data", "-plist"], timeout: 15))
        let system = try parse(StorageProcess.run("/usr/sbin/diskutil", ["apfs", "listSnapshots", "/", "-plist"], timeout: 15), volume: "System")
        return data + system
    }
}

/// Only recognized safe categories can be opened for a *new* cleanup scan and review.
enum DiskCleanupGuide {
    static func canonical(_ path: String) -> String {
        let prefix = "/System/Volumes/Data"
        return path.hasPrefix(prefix + "/") ? String(path.dropFirst(prefix.count)) : path
    }
    static func category(for path: String, home: URL) -> StorageCategory? {
        let path = canonical(path)
        let roots = StorageScanner.roots(home: home, settings: StorageSettings())
        if let root = roots.first(where: { $0.cleanable && ($0.category != .temporary || !StoragePathPolicy.contains(home.path, path)) && StoragePathPolicy.contains($0.url.path, path) }) { return root.category }
        if StoragePathPolicy.contains(home.appendingPathComponent("Downloads").path, path) { return .downloads }
        if StoragePathPolicy.contains(home.appendingPathComponent(".ollama").path, path) { return .models }
        if StoragePathPolicy.contains(home.appendingPathComponent(".docker").path, path) { return .docker }
        return nil
    }
    static func explanation(for path: String, home: URL, policy: StoragePathPolicy) -> String {
        let path = canonical(path)
        if path.contains("/MobileSync/Backup") { return "iPhone or iPad backups · manage backups in Finder. These can be your only recovery copy." }
        if path.contains("/CoreSimulator/") { return "Simulator data · manage devices in Xcode. App data may be stored here." }
        if path.contains("/SourcePackages/") || path.split(separator: "/").contains(".git") { return "Project or repository data · inspect it in your development tools." }
        if path.contains("/Application Support/") || path.contains("/Containers/") || path.contains("/Group Containers/") { return "Application data · can include documents, databases and saved sessions. Manage it in the owning app." }
        if policy.isProtected(path) { return "Protected location · inspection only. System and personal data are not cleanup targets here." }
        if let category = category(for: path, home: home) { return "Open \(category.title) for a fresh scan and exact-item review. This inventory does not select or remove files." }
        if StorageScanner.focus(path: path, directory: true, home: home) != nil { return "This folder contains supported cleanup locations. Review removable files to scan only those known locations; unknown app data is excluded." }
        return "Size alone does not make a file disposable. Reveal it in Finder to identify the owner and purpose."
    }
}

@MainActor final class DiskExplorerService: ObservableObject {
    @Published private(set) var result: DiskAnalysis?
    @Published private(set) var busy = false
    @Published private(set) var status = "Hidden files included. Nothing selected for deletion."
    @Published private(set) var snapshots: [DiskSnapshot]?
    @Published private(set) var snapshotNotice: String?
    @Published var current: String?
    @Published var selected: String?
    @Published var error: String?
    private var worker: Task<DiskAnalysis, Error>?
    private var generation = UUID()
    let home: URL
    init(home: URL) { self.home = home }
    var folder: DiskEntry? { guard let result else { return nil }; return result.entries[current ?? result.root] }
    var selectedEntry: DiskEntry? { guard let selected else { return nil }; return result?.entries[selected] }
    func navigate(_ path: String) {
        guard result?.entries[path]?.directory == true else { return }
        current = path; selected = nil
    }
    func start(_ root: URL, useCache: Bool = false) {
        guard !busy else { return }
        if useCache, let result, result.root == root.path, Date().timeIntervalSince(result.date) < 600 { current = result.root; return }
        let token = UUID(); generation = token; busy = true; error = nil; result = nil; selected = nil; current = nil; snapshots = nil; snapshotNotice = nil
        status = "Measuring files and hidden folders…"
        let progress: @Sendable (Int) -> Void = { [weak self] count in
            Task { @MainActor in guard let self, self.generation == token else { return }; self.status = "\(count.formatted()) entries inspected · hidden files included" }
        }
        let worker = Task.detached(priority: .utility) { try DiskExplorerScanner.scan(root: root, progress: progress) }
        self.worker = worker
        Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self, self.generation == token else { return }
                self.result = result; self.current = result.root; self.busy = false; self.worker = nil
                self.status = "\(result.measured.files.formatted()) files measured · \(result.measured.skipped.formatted()) skipped or shared entries"
            } catch {
                guard let self, self.generation == token else { return }
                self.busy = false; self.worker = nil; self.error = error.localizedDescription; self.status = "Analysis stopped"
            }
        }
    }
    func cancel() { generation = UUID(); worker?.cancel(); worker = nil; busy = false; status = "Analysis canceled · no files changed" }
    func invalidate() { cancel(); result = nil; selected = nil; current = nil; status = "Storage changed · analyze again for current folder sizes" }
    func clear() {
        cancel(); result = nil; selected = nil; current = nil; snapshots = nil; snapshotNotice = nil
        status = "Scan results cleared · no files changed"
    }
    func chooseFolder() {
        guard !busy else { return }
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.showsHiddenFiles = true
        picker.message = "Choose a folder or drive to inspect, including hidden folders. This scan never deletes files."
        if picker.runModal() == .OK, let url = picker.url { start(url) }
    }
    func loadSnapshots() {
        guard snapshotNotice != "Reading snapshot information…" else { return }
        snapshotNotice = "Reading snapshot information…"
        Task {
            do { let values = try await Task.detached(priority: .utility) { try DiskSnapshots.read() }.value; snapshots = values; snapshotNotice = nil }
            catch { snapshots = nil; snapshotNotice = error.localizedDescription }
        }
    }
    func loadFixture(_ result: DiskAnalysis) { self.result = result; current = result.root; status = "Generated QA files · no personal data" }
}
