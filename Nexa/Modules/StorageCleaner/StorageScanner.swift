import Foundation
import Darwin
import CoreServices

enum StorageScanner {
    static func roots(home: URL, settings: StorageSettings) -> [ScanRoot] {
        func root(_ relative: String, _ category: StorageCategory, _ group: String, _ risk: StorageRisk = .review, _ recommended: Bool = false, _ cleanable: Bool = true) -> ScanRoot {
            ScanRoot(url: home.appendingPathComponent(relative), category: category, group: group, risk: risk, cleanable: cleanable, recommendation: recommended)
        }
        var roots = [
            root("Library/Caches/com.spotify.client", .caches, "Spotify", .safe, true),
            root("Library/Caches/com.hnc.Discord", .caches, "Discord", .safe, true),
            root("Library/Caches/Google/Chrome", .browser, "Chrome · Cache", .safe, true),
            root("Library/Caches/Microsoft Edge", .browser, "Edge · Cache", .safe, true),
            root("Library/Caches/com.apple.Safari", .browser, "Safari · Cache", .safe, true),
            root("Library/Caches/Firefox/Profiles", .browser, "Firefox · Cache", .safe, true),
            root("Library/Developer/Xcode/DerivedData", .developer, "Xcode · DerivedData", .safe, true),
            root("Library/Developer/Xcode/Archives", .developer, "Xcode · Archives", .sensitive),
            root("Library/Developer/Xcode/iOS DeviceSupport", .developer, "Xcode · DeviceSupport"),
            root("Library/Developer/CoreSimulator/Devices", .developer, "Xcode · Simulator data", .sensitive, false, false),
            root(".Trash", .trash, "User Trash", .sensitive)
        ]
        if settings.scanDownloads { roots.append(root("Downloads", .downloads, "Downloads")) }
        if settings.scanDesktop { roots.append(root("Desktop", .screenshots, "Desktop · Protected", .review, false, false)) }
        roots.append(ScanRoot(url: SecureStorageFS.temporaryDirectory, category: .temporary, group: "Temporary files", risk: .safe, recommendation: true))
        roots += settings.selectedFolders.map { ScanRoot(url: URL(fileURLWithPath: $0), category: .largeFiles, group: URL(fileURLWithPath: $0).lastPathComponent) }
        return roots
    }
    static func scan(roots: [ScanRoot], policy: StoragePathPolicy, running: Set<String> = [], limit: Int = 150_000,
                     progress: @Sendable (String, Int) -> Void = { _, _ in }) throws -> StorageScan {
        let fm = FileManager.default, capacity = SecureStorageFS.capacity(at: policy.home)
        var scan = StorageScan(id: UUID(), date: Date(), items: [], issues: [], totalCapacity: capacity.total, availableCapacity: capacity.free)
        var seen = Set<String>(), visited = 0
        for root in roots {
            try Task.checkCancellation()
            guard fm.fileExists(atPath: root.url.path) else { continue }
            do { let fd = try SecureStorageFS.directory(root.url.path); close(fd) }
            catch { scan.issues.append("\(root.group): \(error.localizedDescription)"); scan.complete = false; continue }
            progress(root.group, scan.items.count)
            let rootDevice = (try? fm.attributesOfItem(atPath: root.url.path)[.systemNumber] as? NSNumber)?.int32Value
            guard let walker = fm.enumerator(at: root.url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .isPackageKey, .isUbiquitousItemKey], options: [.skipsPackageDescendants], errorHandler: { url, error in
                if scan.issues.count < 100 { scan.issues.append("\(url.path): \(error.localizedDescription)") }
                scan.complete = false; return true
            }) else { scan.issues.append("\(root.group): permission denied or unavailable."); scan.complete = false; continue }
            for case let url as URL in walker {
                try Task.checkCancellation(); visited += 1
                if visited > limit { scan.complete = false; scan.issues.append("Scan reached its \(limit)-entry limit. Choose a smaller folder for a complete scan."); break }
                if visited % 250 == 0 { progress(root.group, scan.items.count) }
                if policy.ignored.contains(where: { StoragePathPolicy.contains($0, url.path) }) { walker.skipDescendants(); continue }
                do {
                    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .isPackageKey, .isUbiquitousItemKey])
                    if values.isSymbolicLink == true || values.isUbiquitousItem == true { walker.skipDescendants(); continue }
                    if values.isPackage == true {
                        walker.skipDescendants()
                        if root.group == "Xcode · Archives" {
                            scan.items.append(StorageItem(id: url.path, path: url.path, root: root.url.path, category: .developer, group: root.group,
                                bytes: 0, allocated: 0, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
                                accessed: nil, created: nil, stamp: nil, risk: .sensitive, eligible: false,
                                reason: "Release archive · size not scanned. Manage this bundle in Xcode Organizer; partial archive deletion is disabled.", recommended: false))
                        }
                        continue
                    }
                    if values.isDirectory == true {
                        // Do not cross mount points, including mounted system volumes.
                        let device = (try fm.attributesOfItem(atPath: url.path)[.systemNumber] as? NSNumber)?.int32Value
                        if device != rootDevice { walker.skipDescendants() }
                        // Never enumerate secrets, system trees or nested user-selected symlinks.
                        if ["Keychains", ".ssh", ".gnupg", "Mail", "Messages"].contains(url.lastPathComponent) { walker.skipDescendants() }
                        continue
                    }
                    guard values.isRegularFile == true, seen.insert(url.path).inserted else { continue }
                    let stamp = try SecureStorageFS.stamp(url.path)
                    guard stamp.device == rootDevice else { continue }
                    let attributes = try fm.attributesOfItem(atPath: url.path)
                    let metadata = try? url.resourceValues(forKeys: [.contentAccessDateKey, .creationDateKey])
                    let modified = (attributes[.modificationDate] as? Date) ?? .distantFuture
                    let age = Date().timeIntervalSince(modified) / 86400
                    let ext = url.pathExtension.lowercased(), lower = url.lastPathComponent.lowercased()
                    var category = root.category == .screenshots ? StorageCategory.largeFiles : root.category, group = root.group, risk = root.risk
                    var eligible = root.cleanable && !policy.isProtected(url.path) && stamp.links == 1
                    var recommended = root.recommendation && age >= 7
                    var reason = "Review before removing."
                    if root.category == .temporary {
                        guard ext == "tmp", age >= 7 else { continue }
                    }
                    if root.category == .browser && group.hasPrefix("Firefox") && !url.path.contains("/cache2/") { continue }
                    // Databases are not included in broad cache or temporary rules.
                    if [.caches, .temporary, .browser].contains(category), ["sqlite", "sqlite3", "db", "db-wal", "db-shm", "db-journal", "sqlite-wal", "sqlite-shm", "sqlite-journal", "sqlite3-wal", "sqlite3-shm", "sqlite3-journal"].contains(ext) { eligible = false; recommended = false; reason = "Database excluded from cache cleanup." }
                    if category == .downloads {
                        if ["dmg", "pkg", "iso", "exe", "msi"].contains(ext) {
                            category = .installers; group = "Installers"; recommended = age >= 30; reason = "Recognized installer extension; associated application is not verified."
                        } else if ["zip", "rar", "7z"].contains(ext) { group = "Archives"; reason = "Archive contents may include personal work." }
                    }
                    if [.downloads, .largeFiles, .screenshots].contains(category),
                       lower.hasPrefix("screenshot") || lower.hasPrefix("screen shot") || lower.hasPrefix("screen recording") {
                        category = .screenshots
                        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: modified), to: Calendar.current.startOfDay(for: Date())).day ?? 0
                        group = days == 0 ? "Today" : days <= 7 ? "Last 7 days" : days <= 30 ? "Last 30 days" : "Older"
                        recommended = false
                    }
                    if root.category == .screenshots && category != .screenshots { continue }
                    if category == .developer {
                        reason = group.contains("DerivedData") ? "Rebuildable output; next build may be slower." : group.contains("Archives") ? "Release archives and debugging symbols may be irreplaceable." : group.contains("Simulator") ? "Manage simulator devices in Xcode; direct cleanup is disabled." : "Device debugging support; may need downloading again."
                        if group.contains("DerivedData"), url.path.contains("/SourcePackages/") || ["swift", "m", "mm", "h", "c", "cpp", "rs", "py", "js", "ts"].contains(ext) {
                            eligible = false; reason = "Package checkout or source file · excluded from cleanup."
                        }
                    }
                    if policy.isProtected(url.path) { eligible = false; reason = "Protected path · reveal and preview only." }
                    if stamp.links > 1 { eligible = false; reason = "Hard-linked file · manual review required." }
                    if isRunning(group: group, running: running) { eligible = false; reason = "Close the application, then scan again." }
                    if root.category == .trash { recommended = false; risk = .sensitive; reason = "Permanent deletion requires an additional confirmation." }
                    if !eligible { recommended = false }
                    scan.items.append(StorageItem(id: url.path, path: url.path, root: root.url.path, category: category, group: group, bytes: stamp.bytes, allocated: stamp.allocated, modified: modified, accessed: metadata?.contentAccessDate, created: metadata?.creationDate, stamp: stamp, risk: risk, eligible: eligible, reason: reason, recommended: recommended))
                    var folder = url.deletingLastPathComponent()
                    while StoragePathPolicy.contains(root.url.path, folder.path) {
                        scan.folderSizes[folder.path, default: 0] += stamp.bytes
                        if folder.path == root.url.path { break }; folder.deleteLastPathComponent()
                    }
                } catch {
                    if scan.issues.count < 100 { scan.issues.append("\(url.path): \(error.localizedDescription)") }
                    scan.complete = false
                }
            }
            if visited > limit { break }
        }
        scan.items.sort { $0.bytes > $1.bytes }
        return scan
    }
    static func isRunning(group: String, running: Set<String>) -> Bool {
        let mapping: [(String, String)] = [("Chrome", "com.google.Chrome"), ("Edge", "com.microsoft.edgemac"), ("Safari", "com.apple.Safari"), ("Firefox", "org.mozilla.firefox"), ("Spotify", "com.spotify.client"), ("Discord", "com.hnc.Discord"), ("Xcode", "com.apple.dt.Xcode")]
        return mapping.contains { group.hasPrefix($0.0) && running.contains($0.1) }
    }
    static func duplicates(_ original: StorageScan, progress: @Sendable (String, Int) -> Void = { _, _ in }) throws -> StorageScan {
        var scan = original
        for i in scan.items.indices { scan.items[i].duplicateHash = nil }
        let candidates = scan.items.indices.filter { scan.items[$0].stamp != nil && scan.items[$0].bytes > 0 && scan.items[$0].stamp?.links == 1 && [.downloads, .installers, .screenshots, .largeFiles].contains(scan.items[$0].category) }
        let sizes = Dictionary(grouping: candidates) { scan.items[$0].bytes }
        var count = 0
        for group in sizes.values where group.count > 1 {
            try Task.checkCancellation()
            var samples: [String: [Int]] = [:]
            for index in group {
                try Task.checkCancellation()
                do { samples[try SecureStorageFS.digest(scan.items[index], sample: true), default: []].append(index) }
                catch is CancellationError { throw CancellationError() }
                catch { scan.issues.append("Duplicate check skipped \(scan.items[index].name): \(error.localizedDescription)") }
            }
            for matches in samples.values where matches.count > 1 {
                var hashes: [String: [Int]] = [:]
                for index in matches {
                    try Task.checkCancellation(); count += 1; progress("Verifying duplicates with SHA-256", count)
                    do { hashes[try SecureStorageFS.digest(scan.items[index]), default: []].append(index) }
                    catch is CancellationError { throw CancellationError() }
                    catch { scan.issues.append("Duplicate verification skipped \(scan.items[index].name): \(error.localizedDescription)") }
                }
                for (hash, indices) in hashes where indices.count > 1 {
                    for index in indices { scan.items[index].duplicateHash = hash; scan.items[index].recommended = false }
                }
            }
        }
        scan.duplicateComplete = true
        return scan
    }
    static func applications(home: URL) throws -> [StorageItem] {
        var result: [StorageItem] = []
        for folder in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in entries where url.pathExtension == "app" {
                try Task.checkCancellation()
                let metadata = try? url.resourceValues(forKeys: [.creationDateKey, .contentAccessDateKey, .contentModificationDateKey])
                var bytes: Int64 = 0
                if let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileAllocatedSizeKey, .isSymbolicLinkKey, .isDirectoryKey], options: []) {
                    for case let file as URL in walk {
                        try Task.checkCancellation()
                        let v = try? file.resourceValues(forKeys: [.fileAllocatedSizeKey, .isSymbolicLinkKey, .isDirectoryKey])
                        if v?.isSymbolicLink == true { walk.skipDescendants(); continue }
                        if v?.isDirectory != true { bytes += Int64(v?.fileAllocatedSize ?? 0) }
                    }
                }
                let lastOpened: Date? = MDItemCreate(kCFAllocatorDefault, url.path as CFString).flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
                let opened = lastOpened.map { "Last opened: \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "Last opened unavailable."
                result.append(StorageItem(id: url.path, path: url.path, root: folder.path, category: .applications, group: "Installed applications", bytes: bytes, allocated: bytes, modified: metadata?.contentModificationDate ?? .distantPast, accessed: lastOpened, created: metadata?.creationDate, stamp: nil, risk: .review, eligible: false, reason: "\(opened) Install date unverified. Use the developer’s uninstaller or Finder.", recommended: false))
            }
        }
        return result
    }
    static func leftovers(home: URL) throws -> [StorageItem] {
        var installed = Set<String>()
        for folder in ["/Applications", "/System/Applications", home.appendingPathComponent("Applications").path] {
            for url in (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? [] {
                if let id = Bundle(url: url)?.bundleIdentifier { installed.insert(id) }
            }
        }
        var items: [StorageItem] = []
        for relative in ["Library/Application Support", "Library/Preferences", "Library/Caches"] {
            let root = home.appendingPathComponent(relative)
            for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [] {
                try Task.checkCancellation()
                let id = url.pathExtension == "plist" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
                guard id.hasPrefix("com."), !id.hasPrefix("com.apple."), !installed.contains(id) else { continue }
                let metadata = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                items.append(StorageItem(id: "leftover:" + url.path, path: url.path, root: root.path, category: .leftovers, group: "Possible leftover", bytes: Int64(metadata?.fileSize ?? 0), allocated: 0, modified: metadata?.contentModificationDate ?? .distantPast, accessed: nil, created: nil, stamp: nil, risk: .sensitive, eligible: false, reason: "Possible leftover · confidence is insufficient. An app may be installed elsewhere. Size is entry metadata, not recursive folder size.", recommended: false))
            }
        }
        return items
    }
}
