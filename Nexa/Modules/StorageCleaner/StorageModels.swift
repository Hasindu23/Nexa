import Foundation

enum StorageCategory: String, Codable, CaseIterable, Identifiable {
    case downloads, caches, temporary, browser, developer, installers, screenshots, largeFiles, trash, leftovers, applications, docker, models
    var id: String { rawValue }
    var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .caches: return "Application caches"
        case .temporary: return "Temporary files"
        case .browser: return "Browser cleanup"
        case .developer: return "Developer data"
        case .installers: return "Old installers"
        case .screenshots: return "Screenshots & recordings"
        case .largeFiles: return "Large files"
        case .trash: return "Trash"
        case .leftovers: return "Application leftovers"
        case .applications: return "Applications"
        case .docker: return "Docker"
        case .models: return "AI models"
        }
    }
    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .caches: return "square.stack.3d.up"
        case .temporary: return "clock.arrow.circlepath"
        case .browser: return "globe"
        case .developer: return "hammer"
        case .installers: return "shippingbox"
        case .screenshots: return "photo.on.rectangle"
        case .largeFiles: return "externaldrive"
        case .trash: return "trash"
        case .leftovers: return "puzzlepiece.extension"
        case .applications: return "app.dashed"
        case .docker: return "shippingbox.fill"
        case .models: return "sparkles"
        }
    }
    var explanation: String {
        switch self {
        case .downloads: return "Your downloaded files. Age and access dates are clues, not proof that a file is unnecessary. Nothing is selected automatically."
        case .caches: return "Only recognized cache locations are eligible. Close the application first. Caches may be rebuilt or downloaded again. Unknown cache directories are left alone."
        case .temporary: return "Old .tmp files in the current user temporary directory. Only files older than seven days are eligible. Active files are skipped where detectable."
        case .browser: return "Only cache is eligible here. Cookies, site data, saved sessions and download history are managed in the browser’s own settings, where you can explicitly select them."
        case .developer: return "DerivedData can be rebuilt; the next build may take longer. Archives may contain irreplaceable release builds and symbols. DeviceSupport may need downloading again. Simulator data is inventory only; manage devices in Xcode."
        case .installers: return "Recognized installer extensions. ZIP, RAR and 7z files stay in Downloads because an archive may contain personal work. Review every installer before removing it."
        case .screenshots: return "Detected by filename in selected locations. Use Quick Look to preview. Protected folders stay read-only."
        case .largeFiles: return "Choose a folder or drive to inspect. Files in protected locations can be viewed but cannot be cleaned. Folder totals include only scanned regular files."
        case .trash: return "Files already in your user Trash. Emptying selected items is permanent and requires an additional typed confirmation. Other drives’ Trash is not included."
        case .leftovers: return "Possible leftovers only: a bundle identifier without a matching installed app is not proof. Reveal and investigate these files; Nexa does not clean uncertain support data."
        case .applications: return "Installed application inventory. Last opened and installation dates are shown only when macOS provides them. Reveal, open, or follow the app’s uninstall instructions."
        case .docker: return "Local Docker Engine inventory. Select stopped containers, unused images or unused volumes individually. Volumes can contain databases. Build cache is inventory only; use Docker Desktop for prune operations."
        case .models: return "Models reported by the local Ollama service. Last used is unavailable from this API. Removing a model is permanent; shared model layers may remain on disk. Running models cannot be removed here."
        }
    }
}

enum StorageRisk: String, Codable { case safe = "Safe", review = "Review Recommended", sensitive = "Sensitive" }
enum CleanupAction: String, Codable, CaseIterable, Identifiable {
    case trash = "Move to Trash", cache = "Delete Cache", permanent = "Permanent Delete"
    var id: String { rawValue }
    var irreversible: Bool { self != .trash }
}

struct FileStamp: Codable, Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let bytes: Int64
    let allocated: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    let links: UInt16
}

struct StorageItem: Identifiable, Codable, Sendable {
    let id: String
    let path: String
    let root: String
    let category: StorageCategory
    let group: String
    let bytes: Int64
    let allocated: Int64
    let modified: Date
    let accessed: Date?
    let created: Date?
    let stamp: FileStamp?
    var risk: StorageRisk
    var eligible: Bool
    var reason: String
    var recommended: Bool
    var duplicateHash: String?
    var resourceKind: String?
    var resourceVersion: String?
    var name: String { resourceKind == nil ? URL(fileURLWithPath: path).lastPathComponent : path }
    var isResource: Bool { resourceKind != nil }
}

struct ScanRoot: Sendable {
    let url: URL
    let category: StorageCategory
    let group: String
    var risk: StorageRisk = .review
    var cleanable = true
    var recommendation = false
}

struct StorageScan: Sendable {
    let id: UUID
    let date: Date
    var items: [StorageItem]
    var issues: [String]
    let totalCapacity: Int64
    let availableCapacity: Int64
    var canceled = false
    var complete = true
    var duplicateComplete = false
    var folderSizes: [String: Int64] = [:]
    var estimatedBytes: Int64 { items.filter(\.eligible).reduce(0) { $0 + $1.allocated } }
}

struct CleanupPlan: Identifiable, Codable, Sendable {
    let id: UUID
    let scanID: UUID
    let created: Date
    let items: [StorageItem]
    let action: CleanupAction
    let deviceID: String
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var allocatedBytes: Int64 { items.reduce(0) { $0 + $1.allocated } }
}

struct CleanupReceipt: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let device: String
    let categories: [String]
    let action: CleanupAction
    var succeeded: [String]
    var failures: [String]
    var removedBytes: Int64
    var reclaimedBytes: Int64
    var freeSpaceChange: Int64
    var recovery: [RecoveryItem]
    var note: String
}
struct RecoveryItem: Codable, Sendable {
    let original: String
    let trash: String
    let stamp: FileStamp
}

struct StorageRecoveryJournal: Codable {
    let original: String
    let staged: String
    let action: CleanupAction
    var stamp: FileStamp
    var trash: String?
}

struct StorageMutationResult {
    let recovery: RecoveryItem?
    let journal: URL
}

struct StorageSettings: Codable {
    var protectedPaths: [String] = []
    var ignoredPaths: [String] = []
    var selectedFolders: [String] = []
    var scanDownloads = false
    var scanDesktop = false
    var includeDocker = false
    var includeOllama = false
    var scheduleDays = 0
    var lastScheduledScan: Date?
}

enum StorageFailure: LocalizedError {
    case blocked(String)
    var errorDescription: String? { switch self { case .blocked(let message): return message } }
}
func storageBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
}

/// A CLEAN_STORAGE grant does not authorize raw paths or arbitrary remote commands.
struct StorageAgentGrant: Sendable {
    let deviceID: String
    let scopes: Set<String>
    let connected: Bool
    let expires: Date
    func validate(device: String, now: Date = Date()) throws {
        guard connected else { throw StorageFailure.blocked("Device disconnected. No cleanup was sent.") }
        guard device == deviceID, scopes.contains("CLEAN_STORAGE"), expires > now else {
            throw StorageFailure.blocked("This device does not have a current CLEAN_STORAGE permission.")
        }
    }
}
