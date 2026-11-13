import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let bookmark: Data?
    let addedAt: Date
    var resolvedURL: URL {
        guard let bookmark else { return url }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &stale)) ?? url
    }
}

@MainActor final class FileShelfService: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var error: String?
    @Published private(set) var importing = false
    @Published private(set) var resolved: [UUID: URL] = [:]
    @Published private(set) var details: [UUID: String] = [:]
    @Published private(set) var availability: [UUID: Bool] = [:]
    private var pendingImports = 0
    private var importTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var generation = UUID()
    private let store: LocalStore
    var persistent = true
    var expiryHours = 24.0
    var onAdded: ((Int) -> Void)?
    init(store: LocalStore) { self.store = store; items = store.read([ShelfItem].self, name: "shelf.json") ?? []; refreshMetadata() }
    func configure(persistent: Bool, expiryHours: Double) {
        self.persistent = persistent; self.expiryHours = expiryHours; prune(); save()
    }
    /// Serial imports keep bookmarks and metadata reads away from the UI thread.
    func add(_ urls: [URL], now: Date = Date()) {
        let previous = importTask, token = generation
        pendingImports += 1; importing = true
        importTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            defer {
                if self.generation == token { self.pendingImports = max(0, self.pendingImports - 1); self.importing = self.pendingImports > 0 }
            }
            let candidates = await Task.detached(priority: .userInitiated) {
                urls.prefix(100).filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }.map { url in
                    ShelfItem(id: UUID(), url: url, bookmark: try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), addedAt: now)
                }
            }.value
            guard !Task.isCancelled, self.generation == token else { return }
            var known = Set(self.items.map { (self.resolved[$0.id] ?? $0.url).standardizedFileURL })
            let added = candidates.filter { known.insert($0.url.standardizedFileURL).inserted }
            self.items = Array((added + self.items).prefix(100))
            for item in added { self.resolved[item.id] = item.url; self.availability[item.id] = true }
            self.save(); self.refreshMetadata()
            if !added.isEmpty { self.onAdded?(added.count) }
        }
    }
    func waitForImports() async { await importTask?.value }
    func displayURL(_ item: ShelfItem) -> URL { resolved[item.id] ?? item.url }
    func refreshMetadata() {
        metadataTask?.cancel(); let snapshot = items
        metadataTask = Task { [weak self] in
            let values = await Task.detached(priority: .utility) {
                snapshot.map { item in
                    let url = item.resolvedURL
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    let type = values?.isDirectory == true ? "Folder" : url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased()
                    let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
                    return (item.id, url, FileManager.default.fileExists(atPath: url.path), type + (size.map { " · " + $0 } ?? ""))
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            for (id, url, exists, detail) in values where self.items.contains(where: { $0.id == id }) { self.resolved[id] = url; self.availability[id] = exists; self.details[id] = detail }
        }
    }
    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id }; save() }
    func clear() { generation = UUID(); importTask?.cancel(); pendingImports = 0; importing = false; items.removeAll(); resolved.removeAll(); availability.removeAll(); save() }
    func prune(now: Date = Date()) {
        if expiryHours > 0 { items.removeAll { now.timeIntervalSince($0.addedAt) > expiryHours * 3600 } }
        save()
    }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([displayURL(item)]) }
    func pasteFiles() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty { error = "Copy files in Finder, then paste them here." } else { error = nil; add(urls) }
    }
    func copyFiles(_ urls: [URL]) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls as [NSURL]) }
    func airDrop(_ items: [Any]) {
        guard !items.isEmpty, let sharing = NSSharingService(named: .sendViaAirDrop), sharing.canPerform(withItems: items) else { error = "AirDrop is not available for these items."; return }
        error = nil; sharing.perform(withItems: items)
    }
    func acceptAirDrop(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            var items: [Any] = []
            for provider in providers.prefix(100) {
                let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL : provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? .url : .utf8PlainText
                let value: NSSecureCoding? = await withCheckedContinuation { continuation in provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { object, _ in continuation.resume(returning: object) } }
                if let url = value as? URL { items.append(url) }
                else if let data = value as? Data, type != .utf8PlainText, let url = URL(dataRepresentation: data, relativeTo: nil) { items.append(url) }
                else if let text = value as? String { items.append(text) }
                else if let data = value as? Data, let text = String(data: data, encoding: .utf8) { items.append(text) }
            }
            airDrop(items)
        }
    }
    private func save() {
        do { try store.write(persistent ? items : [], name: "shelf.json") }
        catch { self.error = "The shelf could not be saved: \(error.localizedDescription)" }
    }
}
