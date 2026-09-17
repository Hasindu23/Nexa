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
    private let store: LocalStore
    var persistent = true
    var expiryHours = 24.0
    var onAdded: ((Int) -> Void)?
    init(store: LocalStore) { self.store = store; items = store.read([ShelfItem].self, name: "shelf.json") ?? [] }
    func configure(persistent: Bool, expiryHours: Double) {
        self.persistent = persistent; self.expiryHours = expiryHours; prune(); save()
    }
    func add(_ urls: [URL], now: Date = Date()) {
        var count = 0
        for url in urls where url.isFileURL && FileManager.default.fileExists(atPath: url.path) {
            guard !items.contains(where: { $0.resolvedURL.standardizedFileURL == url.standardizedFileURL }) else { continue }
            let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            items.insert(ShelfItem(id: UUID(), url: url, bookmark: bookmark, addedAt: now), at: 0)
            count += 1
        }
        items = Array(items.prefix(100)); save()
        if count > 0 { onAdded?(count) }
    }
    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id }; save() }
    func clear() { items.removeAll(); save() }
    func prune(now: Date = Date()) {
        if expiryHours > 0 { items.removeAll { now.timeIntervalSince($0.addedAt) > expiryHours * 3600 } }
        save()
    }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL]) }
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
