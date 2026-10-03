import AppKit
import Combine

@MainActor final class StorageService: ObservableObject {
    @Published private(set) var scan: StorageScan?
    @Published private(set) var busy = false
    @Published private(set) var cleaning = false
    @Published private(set) var status = "Ready when you are"
    @Published private(set) var settings: StorageSettings
    @Published private(set) var history: [CleanupReceipt] = []
    @Published var selection = Set<String>()
    @Published var error: String?
    @Published var plan: CleanupPlan?
    @Published var lastReceipt: CleanupReceipt?
    @Published var action: CleanupAction = .trash
    @Published var destination = "overview"
    @Published private(set) var focus: StorageFocus?
    let home: URL
    let deviceID: String
    let engine: StorageEngine
    let explorer: DiskExplorerService
    let memory = MemoryService()
    private let store: LocalStore
    private var worker: Task<StorageScan, Error>?
    private var cleanupWorker: Task<CleanupReceipt, Error>?
    private var generation = UUID()
    private var scheduler: Timer?
    private let testing: Bool
    var policy: StoragePathPolicy { StoragePathPolicy(home: home, additional: settings.protectedPaths, ignored: settings.ignoredPaths) }
    var grant: StorageAgentGrant { StorageAgentGrant(deviceID: deviceID, scopes: ["CLEAN_STORAGE"], connected: true, expires: Date().addingTimeInterval(600)) }
    var selectedItems: [StorageItem] { scan?.items.filter { selection.contains($0.id) } ?? [] }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var recommendations: [StorageItem] { scan?.items.filter { $0.recommended && $0.eligible && $0.duplicateHash == nil } ?? [] }
    init(store: LocalStore, home: URL = FileManager.default.homeDirectoryForCurrentUser, testing: Bool = false) {
        self.store = store; self.home = home; self.testing = testing
        explorer = DiskExplorerService(home: home)
        deviceID = testing ? "QA Mac" : Host.current().localizedName ?? "This Mac"
        let settings = store.read(StorageSettings.self, name: "storage-settings.json") ?? StorageSettings()
        self.settings = settings
        history = StorageEngine.loadHistory(store)
        engine = StorageEngine(policy: StoragePathPolicy(home: home, additional: settings.protectedPaths, ignored: settings.ignoredPaths), store: store, deviceID: deviceID)
        if !testing {
            let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.scheduledScanIfDue() } }
            timer.tolerance = 120; RunLoop.main.add(timer, forMode: .common); scheduler = timer
        }
    }
    func opened() {
        guard !testing, !busy else { return }
        if scan == nil || Date().timeIntervalSince(scan!.date) > 600 { startScan(focus: focus) }
    }
    func configure(_ edit: (inout StorageSettings) -> Void) {
        guard !cleaning else { return }
        cancel(); edit(&settings)
        settings.protectedPaths = Array(Set(settings.protectedPaths)).sorted()
        settings.ignoredPaths = Array(Set(settings.ignoredPaths)).sorted()
        settings.selectedFolders = Array(Set(settings.selectedFolders)).sorted()
        // Changes to scope/protection always invalidate existing cleanup capabilities.
        scan = nil; plan = nil; focus = nil; selection.removeAll(); saveSettings()
        let policy = policy; Task { await engine.updatePolicy(policy) }
    }
    private func saveSettings() { do { try store.write(settings, name: "storage-settings.json") } catch { self.error = error.localizedDescription } }
    func startScan(inventory: Bool = false, focus: StorageFocus? = nil) {
        guard !busy else { return }
        self.focus = focus
        if focus == nil && destination == "focused" { destination = "overview" }
        error = nil; plan = nil; selection.removeAll(); busy = true; status = "Preparing scan…"
        let token = UUID(); generation = token
        let roots = focus?.roots ?? StorageScanner.roots(home: home, settings: settings), policy = policy, home = home, settings = settings
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let progress: @Sendable (String, Int) -> Void = { [weak self] name, count in
            Task { @MainActor in guard let self, self.generation == token else { return }; self.status = "\(name) · \(count.formatted()) files" }
        }
        let worker = Task.detached(priority: .utility) {
            var result = try StorageScanner.scan(roots: roots, policy: policy, running: running, progress: progress)
            if let focus, !focus.directory { result.items.removeAll { $0.path != focus.path } }
            if inventory {
                progress("Inspecting applications", result.items.count)
                result.items += try StorageScanner.applications(home: home)
                result.items += try StorageScanner.leftovers(home: home)
            }
            let integration = StorageIntegrations(home: home)
            if focus == nil && settings.includeDocker {
                do { progress("Reading local Docker storage", result.items.count); result.items += try integration.docker() }
                catch { result.issues.append("Docker: \(error.localizedDescription)"); result.complete = false }
            }
            if focus == nil && settings.includeOllama {
                do { progress("Reading local Ollama models", result.items.count); result.items += try integration.models() }
                catch { result.issues.append("Ollama: \(error.localizedDescription)"); result.complete = false }
            }
            try Task.checkCancellation(); return result
        }
        self.worker = worker
        Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self, self.generation == token else { return }
                await self.engine.updatePolicy(policy); await self.engine.accept(result)
                guard self.generation == token else { return }
                self.scan = result; self.busy = false; self.worker = nil
                self.status = result.complete ? "Scan complete · \(result.items.count.formatted()) \(result.items.count == 1 ? "item" : "items")" : "Partial scan · review skipped locations"
            } catch {
                guard let self, self.generation == token else { return }
                self.busy = false; self.worker = nil; self.status = "Scan stopped"; self.error = error.localizedDescription
            }
        }
    }
    func findDuplicates() {
        guard !busy, let original = scan else { return }
        busy = true; selection.removeAll(); plan = nil; error = nil
        let token = UUID(); generation = token
        let progress: @Sendable (String, Int) -> Void = { [weak self] name, count in
            Task { @MainActor in guard let self, self.generation == token else { return }; self.status = "\(name) · \(count) files" }
        }
        let worker = Task.detached(priority: .utility) { try StorageScanner.duplicates(original, progress: progress) }
        self.worker = worker
        Task {
            do {
                let result = try await worker.value; guard generation == token else { return }
                await engine.accept(result); guard generation == token else { return }
                scan = result; status = "Duplicate verification complete"; busy = false; self.worker = nil
            } catch { guard generation == token else { return }; busy = false; self.worker = nil; self.error = error.localizedDescription }
        }
    }
    func cancel() {
        if cleaning { cleanupWorker?.cancel(); status = "Stopping after the current item…"; return }
        generation = UUID(); worker?.cancel(); worker = nil; busy = false; plan = nil
        scan = nil; selection.removeAll(); status = "Scan canceled · no cleanup performed"
    }
    func toggle(_ item: StorageItem) {
        guard !busy, item.eligible else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { select([item]) }
    }
    func select(_ items: [StorageItem]) {
        guard !busy else { return }
        let eligible = items.filter { $0.eligible && !selection.contains($0.id) }
        let room = max(0, 5000 - selection.count)
        selection.formUnion(eligible.prefix(room).map(\.id))
        if eligible.count > room { error = "Selected the first 5,000 items. Clean in batches so each review stays manageable." }
    }
    func recommend() { guard !busy else { return }; selection = Set(recommendations.prefix(5000).map(\.id)); action = .trash }
    func keepDuplicate(_ keeper: StorageItem) {
        guard !busy, let hash = keeper.duplicateHash else { return }
        let copies = scan?.items.filter { $0.duplicateHash == hash } ?? []
        for item in copies { selection.remove(item.id) }
        select(copies.filter { $0.id != keeper.id })
        action = .trash
    }
    func review() {
        guard !busy, scan != nil else { return }
        busy = true; error = nil
        let ids = selection, action = action, grant = grant, token = generation
        Task {
            do { let prepared = try await engine.prepare(ids: ids, action: action, grant: grant); guard token == generation else { return }; plan = prepared }
            catch { guard token == generation else { return }; self.error = error.localizedDescription }
            busy = false
        }
    }
    func confirm(phrase: String) {
        guard !busy, let plan else { return }
        self.plan = nil; busy = true; cleaning = true; error = nil; status = "Cleaning reviewed items…"
        let grant = grant, running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)), engine = engine
        let task = Task.detached(priority: .utility) { try await engine.execute(planID: plan.id, confirmed: true, permanentPhrase: phrase, grant: grant, running: running) }
        cleanupWorker = task
        Task {
            do { lastReceipt = try await task.value; history = await engine.receipts() }
            catch { self.error = error.localizedDescription }
            cleanupWorker = nil; cleaning = false; busy = false; selection.removeAll(); scan = nil
            // A fresh filesystem inventory follows every attempted operation.
            explorer.invalidate()
            let operationError = self.error; startScan(focus: focus); if let operationError { self.error = operationError }
        }
    }
    func undo(_ receipt: CleanupReceipt) {
        guard !busy, !receipt.recovery.isEmpty else { return }; busy = true; cleaning = true
        let engine = engine
        let task = Task.detached(priority: .utility) { try await engine.undo(receiptID: receipt.id) }
        cleanupWorker = task
        Task {
            do { lastReceipt = try await task.value; history = await engine.receipts() }
            catch { self.error = error.localizedDescription }
            cleanupWorker = nil; cleaning = false; busy = false; scan = nil
            explorer.invalidate()
            let recoveryError = self.error; startScan(focus: focus); if let recoveryError { self.error = recoveryError }
        }
    }
    func ignore(_ item: StorageItem) { configure { $0.ignoredPaths.append(item.path) }; startScan() }
    func protect(_ item: StorageItem) { guard !item.isResource else { return }; configure { $0.protectedPaths.append(item.path) }; startScan() }
    func chooseFolder(protect: Bool = false) {
        guard !busy else { return }
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = !protect
        picker.message = protect ? "Files in this folder will be protected from cleanup." : "Choose a folder to scan. Protected locations stay read-only."
        if picker.runModal() == .OK {
            configure { settings in
                for url in picker.urls {
                    if protect { if !settings.protectedPaths.contains(url.path) { settings.protectedPaths.append(url.path) } }
                    else if url.path != "/" && url.path != home.path && !settings.selectedFolders.contains(url.path) { settings.selectedFolders.append(url.path) }
                }
            }
            if !protect { startScan() }
        }
    }
    func scheduledScanIfDue(now: Date = Date()) {
        guard !testing, !busy, settings.scheduleDays > 0,
              now.timeIntervalSince(settings.lastScheduledScan ?? now) >= Double(settings.scheduleDays) * 86400 else { return }
        settings.lastScheduledScan = now; saveSettings(); startScan()
    }
    func reviewFromExplorer(_ category: StorageCategory) {
        guard !busy, !explorer.busy else { return }
        configure {
            if category == .downloads { $0.scanDownloads = true }
            if category == .docker { $0.includeDocker = true }
            if category == .models { $0.includeOllama = true }
        }
        destination = category.rawValue; action = .trash; startScan()
    }
    func reviewFromExplorer(_ entry: DiskEntry) {
        guard !busy, !explorer.busy, let focus = StorageScanner.focus(path: entry.path, directory: entry.directory, home: home) else { return }
        destination = "focused"; action = .trash; startScan(focus: focus)
    }
    func clearScanResults() async {
        guard !busy, !explorer.busy else { return }
        cancel(); focus = nil; explorer.clear(); busy = true
        await engine.discardScan()
        busy = false; status = "Scan results cleared · scan again before cleaning"
        memory.refresh()
    }
    func stop() { memory.cancel(); explorer.cancel(); worker?.cancel(); cleanupWorker?.cancel(); scheduler?.invalidate() }
    func loadFixture(_ result: StorageScan) async { await engine.accept(result); scan = result; status = "QA fixture · no personal files" }
}
