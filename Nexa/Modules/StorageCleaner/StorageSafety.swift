import Foundation
import Darwin
import CryptoKit

struct StoragePathPolicy: Sendable {
    let home: URL
    var additional: [String] = []
    var ignored: [String] = []
    var protectedPaths: [String] {
        ["/System", "/Library", "/Applications", "/bin", "/sbin", "/usr", "/etc", "/private/etc", "/private/var/db", "/dev"] +
        ["Documents", "Desktop", "Pictures", "Movies", "Music", "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Application Support/Nexa",
         "Library/Safari", "Library/Containers/com.apple.Safari", "Library/Application Support/Google/Chrome", "Library/Application Support/Microsoft Edge", "Library/Application Support/Firefox"].map { home.appendingPathComponent($0).path } + additional
    }
    static func contains(_ parent: String, _ child: String) -> Bool { child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/") }
    func validateSyntax(_ path: String) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0), !path.split(separator: "/").contains(".."), !path.split(separator: "/").contains(".") else {
            throw StorageFailure.blocked("Invalid or traversing path.")
        }
    }
    func isProtected(_ path: String) -> Bool {
        if path == "/" || path == home.path || path == home.appendingPathComponent("Downloads").path { return true }
        if protectedPaths.contains(where: { Self.contains($0, path) }) { return true }
        // Mounted copies of macOS and application bundles are never cleanup targets.
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".backupdb") }) { return true }
        if parts.first == "Volumes", parts.count >= 3, ["System", "Library", "Applications", "usr", "private"].contains(parts[2]) { return true }
        return false
    }
    func validate(_ item: StorageItem) throws {
        try validateSyntax(item.path); try validateSyntax(item.root)
        guard item.eligible, !item.isResource, item.path != item.root, Self.contains(item.root, item.path),
              !isProtected(item.path), !ignored.contains(where: { Self.contains($0, item.path) }) else {
            throw StorageFailure.blocked("Protected, ignored, or outside the approved scan scope.")
        }
        // Never treat a system root or an entire home directory as a cleanup capability.
        guard item.root != "/", item.root != home.path else { throw StorageFailure.blocked("Root and home cleanup are prohibited.") }
        let actual = try SecureStorageFS.stamp(item.path)
        guard actual == item.stamp else { throw StorageFailure.blocked("File changed after the scan. Scan and review again.") }
        guard actual.links == 1 else { throw StorageFailure.blocked("Hard-linked files require manual review.") }
    }
}

enum SecureStorageFS {
    /// Only for the OS-provided temporary directory, never for a user-supplied cleanup path.
    static var temporaryDirectory: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let path = FileManager.default.temporaryDirectory.path
        guard realpath(path, &buffer) != nil else { return FileManager.default.temporaryDirectory }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }
    static func failure(_ operation: String) -> StorageFailure { .blocked("\(operation): \(String(cString: strerror(errno)))") }
    static func fromStat(_ value: stat) -> FileStamp {
        FileStamp(device: value.st_dev, inode: value.st_ino, bytes: value.st_size, allocated: Int64(value.st_blocks) * 512,
                  modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanos: Int64(value.st_mtimespec.tv_nsec),
                  changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanos: Int64(value.st_ctimespec.tv_nsec), links: value.st_nlink)
    }
    /// Walk each component with O_NOFOLLOW. Holding descriptors prevents parent symlink substitution.
    static func directory(_ path: String) throws -> Int32 {
        guard path.hasPrefix("/"), !path.utf8.contains(0), !path.split(separator: "/").contains("..") else { throw StorageFailure.blocked("Unsafe path.") }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Open root") }
        for part in path.split(separator: "/") {
            let next = openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw failure("Open directory without symlinks") }
            fd = next
        }
        return fd
    }
    static func stamp(_ path: String) throws -> FileStamp {
        let url = URL(fileURLWithPath: path)
        let parent = try directory(url.deletingLastPathComponent().path); defer { close(parent) }
        var value = stat()
        guard fstatat(parent, url.lastPathComponent, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("Read file") }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_uid == getuid() else { throw StorageFailure.blocked("Only regular files owned by you can be cleaned.") }
        return fromStat(value)
    }
    static func digest(_ item: StorageItem, sample: Bool = false) throws -> String {
        try Task.checkCancellation()
        let url = URL(fileURLWithPath: item.path)
        let parent = try directory(url.deletingLastPathComponent().path); defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw failure("Open duplicate candidate") }; defer { close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, fromStat(value) == item.stamp else { throw StorageFailure.blocked("Duplicate candidate changed.") }
        var hasher = SHA256(); var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        while true {
            try Task.checkCancellation()
            let count = read(fd, &buffer, sample ? 4096 : buffer.count)
            guard count >= 0 else { throw failure("Read duplicate candidate") }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
            if sample { break }
        }
        guard fstat(fd, &value) == 0, fromStat(value) == item.stamp else { throw StorageFailure.blocked("Duplicate candidate changed during hashing.") }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func capacity(at url: URL) -> (total: Int64, free: Int64) {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: url.path) else { return (0, 0) }
        return ((values[.systemSize] as? NSNumber)?.int64Value ?? 0, (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
    }

    /// Stage exactly one regular file on the same volume before giving Foundation a stable private path.
    /// No recursive delete, shell interpolation, forced overwrite, or fallback to permanent deletion.
    static func mutate(_ item: StorageItem, action: CleanupAction, policy: StoragePathPolicy, staging: URL,
                       trash: (URL) throws -> URL = systemTrash) throws -> StorageMutationResult {
        try policy.validate(item)
        let source = URL(fileURLWithPath: item.path)
        let parent = try directory(source.deletingLastPathComponent().path); defer { close(parent) }
        var volume = statfs()
        guard fstatfs(parent, &volume) == 0, volume.f_flags & UInt32(MNT_RDONLY) == 0 else { throw StorageFailure.blocked("Read-only drive.") }
        guard faccessat(parent, ".", W_OK, 0) == 0 else { throw failure("Write permission") }
        let stagingRootFD = try directory(staging.path); defer { close(stagingRootFD) }
        var stageInfo = stat()
        guard fstat(stagingRootFD, &stageInfo) == 0, stageInfo.st_uid == getuid(), stageInfo.st_mode & 0o077 == 0,
              stageInfo.st_dev == item.stamp?.device else { throw StorageFailure.blocked("A private recovery area on this volume is required. Use Finder for this item.") }
        var original = stat()
        guard fstatat(parent, source.lastPathComponent, &original, AT_SYMLINK_NOFOLLOW) == 0, fromStat(original) == item.stamp else { throw StorageFailure.blocked("File changed before cleanup.") }
        let folderName = UUID().uuidString
        guard mkdirat(stagingRootFD, folderName, 0o700) == 0 else { throw failure("Create private recovery folder") }
        let stageFD = openat(stagingRootFD, folderName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stageFD >= 0 else { throw failure("Open private recovery folder") }
        defer { close(stageFD); _ = unlinkat(stagingRootFD, folderName, AT_REMOVEDIR) }
        // A separate folder preserves the original name, including 255-byte filenames.
        let stagedName = source.lastPathComponent
        let stagedURL = staging.appendingPathComponent(folderName).appendingPathComponent(stagedName)
        let journalURL = staging.appendingPathComponent(folderName + ".json")
        var journal = StorageRecoveryJournal(original: item.path, staged: stagedURL.path, action: action, stamp: fromStat(original))
        func saveJournal() throws {
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        }
        try saveJournal()
        guard renameatx_np(parent, source.lastPathComponent, stageFD, stagedName, UInt32(RENAME_EXCL)) == 0 else { throw failure("Move to private recovery area") }
        var trashDestination: URL?
        do {
            var captured = stat()
            guard fstatat(stageFD, stagedName, &captured, AT_SYMLINK_NOFOLLOW) == 0,
                  captured.st_mode & S_IFMT == S_IFREG, captured.st_dev == original.st_dev, captured.st_ino == original.st_ino,
                  captured.st_uid == original.st_uid, captured.st_nlink == original.st_nlink,
                  captured.st_size == original.st_size, captured.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
                  captured.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec else {
                throw StorageFailure.blocked("File was replaced during cleanup.")
            }
            journal.stamp = fromStat(captured); try saveJournal()
            if action == .trash {
                let destination = try trash(stagedURL)
                trashDestination = destination; journal.trash = destination.path; try saveJournal()
                let moved = try stamp(destination.path)
                guard moved.device == item.stamp?.device, moved.inode == item.stamp?.inode else { throw StorageFailure.blocked("Trash verification failed. Inspect \(destination.path).") }
                journal.stamp = moved; try saveJournal()
                return StorageMutationResult(recovery: RecoveryItem(original: item.path, trash: destination.path, stamp: moved), journal: journalURL)
            }
            guard unlinkat(stageFD, stagedName, 0) == 0 else { throw failure("Delete reviewed file") }
            return StorageMutationResult(recovery: nil, journal: journalURL)
        } catch {
            if let trashDestination {
                throw StorageFailure.blocked("macOS moved the file to \(trashDestination.path), but verification failed: \(error.localizedDescription). No reclaimed space is reported. The recovery record is \(journalURL.path).")
            }
            // Restore without overwriting a new file at the original path.
            if renameatx_np(stageFD, stagedName, parent, source.lastPathComponent, UInt32(RENAME_EXCL)) != 0,
               FileManager.default.fileExists(atPath: stagedURL.path) {
                throw StorageFailure.blocked("\(error.localizedDescription) File preserved at \(stagedURL.path); restore manually.")
            }
            if FileManager.default.fileExists(atPath: item.path) { try? FileManager.default.removeItem(at: journalURL) }
            throw error
        }
    }
    static func systemTrash(_ url: URL) throws -> URL {
        // macOS may allow a move to Trash while denying subsequent inspection/recovery.
        // Verify access first so such a move cannot leave an unverified cleanup result.
        do {
            let fd = try directory(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path)
            close(fd)
        } catch {
            throw StorageFailure.blocked("macOS denied access to Trash. Allow Nexa access in System Settings → Privacy & Security → Full Disk Access, then scan again. The original file is preserved.")
        }
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        guard let destination else { throw StorageFailure.blocked("macOS did not return a Trash destination.") }
        return destination as URL
    }
    static func restore(_ recovery: RecoveryItem, policy: StoragePathPolicy) throws {
        try policy.validateSyntax(recovery.original)
        guard !policy.isProtected(recovery.original), try stamp(recovery.trash) == recovery.stamp else {
            throw StorageFailure.blocked("Recovery file changed or original folder is now protected.")
        }
        let original = URL(fileURLWithPath: recovery.original), source = URL(fileURLWithPath: recovery.trash)
        let from = try directory(source.deletingLastPathComponent().path); defer { close(from) }
        let to = try directory(original.deletingLastPathComponent().path); defer { close(to) }
        var held = stat()
        guard fstatat(from, source.lastPathComponent, &held, AT_SYMLINK_NOFOLLOW) == 0, fromStat(held) == recovery.stamp else {
            throw StorageFailure.blocked("The recovery file changed before Undo. Nothing was overwritten.")
        }
        guard renameatx_np(from, source.lastPathComponent, to, original.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw failure("Restore without overwriting") }
        var restored = stat()
        guard fstatat(to, original.lastPathComponent, &restored, AT_SYMLINK_NOFOLLOW) == 0,
              restored.st_dev == held.st_dev, restored.st_ino == held.st_ino, restored.st_mode & S_IFMT == S_IFREG else {
            _ = renameatx_np(to, original.lastPathComponent, from, source.lastPathComponent, UInt32(RENAME_EXCL))
            throw StorageFailure.blocked("Recovery file was replaced during Undo. Inspect the original and Trash paths.")
        }
    }
}
