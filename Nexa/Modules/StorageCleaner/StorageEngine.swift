import Foundation

actor StorageEngine {
    private var scan: StorageScan?
    private var plans: [UUID: CleanupPlan] = [:]
    private var policy: StoragePathPolicy
    private let store: LocalStore
    private let deviceID: String
    private let integrations: StorageIntegrations
    private let trashHandler: (URL) throws -> URL
    private let activeFileCheck: ([String]) throws -> Set<String>
    private var history: [CleanupReceipt]
    init(policy: StoragePathPolicy, store: LocalStore, deviceID: String,
         trashHandler: @escaping (URL) throws -> URL = SecureStorageFS.systemTrash,
         activeFileCheck: @escaping ([String]) throws -> Set<String> = StorageProcess.openFiles) {
        self.policy = policy; self.store = store; self.deviceID = deviceID
        self.integrations = StorageIntegrations(home: policy.home)
        self.trashHandler = trashHandler; self.activeFileCheck = activeFileCheck
        history = Self.loadHistory(store)
    }
    nonisolated static func loadHistory(_ store: LocalStore) -> [CleanupReceipt] {
        var history = store.read([CleanupReceipt].self, name: "storage-history.json") ?? []
        if var interrupted = store.read(CleanupReceipt.self, name: "storage-last-operation.json"), !history.contains(where: { $0.id == interrupted.id }) {
            interrupted.note = "Recovered an interrupted cleanup record. Only the recorded successful items are listed. Inspect scan notices and the recovery area before retrying."
            history.insert(interrupted, at: 0)
        }
        return Array(history.prefix(200))
    }
    func accept(_ scan: StorageScan) { self.scan = scan; plans.removeAll() }
    func discardScan() { scan = nil; plans.removeAll() }
    func updatePolicy(_ value: StoragePathPolicy) { policy = value; plans.removeAll(); scan = nil }
    func receipts() -> [CleanupReceipt] { history }
    func prepare(ids: Set<String>, action: CleanupAction, grant: StorageAgentGrant, now: Date = Date()) throws -> CleanupPlan {
        try grant.validate(device: deviceID, now: now)
        guard let scan, !scan.canceled, now.timeIntervalSince(scan.date) < 1800 else { throw StorageFailure.blocked("Scan results expired. Scan again before reviewing.") }
        guard !ids.isEmpty, ids.count <= 5000 else { throw StorageFailure.blocked("Select between 1 and 5,000 items per review.") }
        let items = scan.items.filter { ids.contains($0.id) }
        guard items.count == ids.count else { throw StorageFailure.blocked("Selection includes items outside this scan.") }
        for item in items {
            guard item.eligible else { throw StorageFailure.blocked("\(item.name) is protected or in use.") }
            if item.isResource {
                guard action == .permanent else { throw StorageFailure.blocked("Docker resources and AI models require Permanent Delete.") }
            } else {
                try policy.validate(item)
                if item.category == .trash && action != .permanent { throw StorageFailure.blocked("Trash items require Permanent Delete.") }
                if action == .cache && !Self.isCache(item) { throw StorageFailure.blocked("Delete Cache cannot delete personal files or sensitive data.") }
            }
        }
        let groups = Dictionary(grouping: scan.items.filter { $0.duplicateHash != nil }) { $0.duplicateHash! }
        for copies in groups.values where copies.contains(where: { ids.contains($0.id) }) {
            guard copies.contains(where: { !ids.contains($0.id) }) else { throw StorageFailure.blocked("Keep at least one copy in every duplicate group.") }
        }
        let plan = CleanupPlan(id: UUID(), scanID: scan.id, created: now, items: items, action: action, deviceID: deviceID)
        plans = [plan.id: plan]; return plan
    }
    static func isCache(_ item: StorageItem) -> Bool {
        [.caches, .temporary, .browser].contains(item.category) || (item.category == .developer && item.group == "Xcode · DerivedData")
    }
    func execute(planID: UUID, confirmed: Bool, permanentPhrase: String, grant: StorageAgentGrant,
                 running: Set<String> = [], now: Date = Date()) throws -> CleanupReceipt {
        try grant.validate(device: deviceID, now: now)
        guard confirmed, let plan = plans[planID], plan.deviceID == deviceID,
              now.timeIntervalSince(plan.created) < 300, plan.scanID == scan?.id else { throw StorageFailure.blocked("This review expired or was not confirmed. Review again.") }
        guard !plan.action.irreversible || permanentPhrase == "DELETE" else { throw StorageFailure.blocked("Additional permanent-deletion confirmation is required.") }
        plans.removeValue(forKey: planID) // Single-use: retries cannot replay a cleanup.
        try Task.checkCancellation()
        let staging = store.root.appendingPathComponent("StorageRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Written before any mutation. If interrupted, keep the reviewed manifest for recovery.
        try store.write(plan, name: "storage-pending.json")
        let active = try activeFileCheck(plan.items.filter { !$0.isResource }.map(\.path))
        let before = SecureStorageFS.capacity(at: policy.home).free
        var receipt = CleanupReceipt(id: UUID(), date: Date(), device: deviceID, categories: Array(Set(plan.items.map { $0.category.title })).sorted(), action: plan.action,
                                     succeeded: [], failures: [], removedBytes: 0, reclaimedBytes: 0, freeSpaceChange: 0, recovery: [], note: "")
        var removedAllocated: Int64 = 0
        for item in plan.items {
            if Task.isCancelled { receipt.failures.append("Canceled. Remaining items were not processed."); break }
            var committedJournal: URL?
            do {
                try grant.validate(device: deviceID)
                guard !active.contains(item.path), !StorageScanner.isRunning(group: item.group, running: running) else { throw StorageFailure.blocked("File or application is active.") }
                if let hash = item.duplicateHash {
                    let selectedIDs = Set(plan.items.map(\.id))
                    guard let keeper = scan?.items.first(where: { $0.duplicateHash == hash && !selectedIDs.contains($0.id) }),
                          try SecureStorageFS.digest(keeper) == hash, try SecureStorageFS.digest(item) == hash else {
                        throw StorageFailure.blocked("Duplicate keeper unavailable.")
                    }
                }
                if item.isResource { try integrations.remove(item) }
                else {
                    let result = try SecureStorageFS.mutate(item, action: plan.action, policy: policy, staging: staging, trash: trashHandler)
                    if let recovery = result.recovery { receipt.recovery.append(recovery) }
                    committedJournal = result.journal
                }
                receipt.succeeded.append(item.path); receipt.removedBytes += item.bytes; removedAllocated += item.allocated
            } catch { receipt.failures.append("\(item.name): \(error.localizedDescription)") }
            // Preserve progress after each item so a partial failure is recoverable.
            do {
                try store.write(receipt, name: "storage-last-operation.json")
                if let committedJournal { try? FileManager.default.removeItem(at: committedJournal) }
            }
            catch { receipt.failures.append("History could not be saved. Cleanup stopped: \(error.localizedDescription)"); break }
        }
        let after = SecureStorageFS.capacity(at: policy.home).free
        receipt.freeSpaceChange = after - before
        receipt.reclaimedBytes = plan.action == .trash ? 0 : min(removedAllocated, max(0, after - before))
        receipt.note = plan.action == .trash
            ? "Moved to Trash; 0 bytes reclaimed. Restore with Undo while the items remain in Trash. Emptying Trash is a separate permanent action."
            : "Reclaimed is the observed increase in free space, capped at the allocation of successfully removed items. APFS snapshots, shared blocks, Docker disk images and other disk activity affect this measurement. Resource and file sizes are not a promise of free space."
        history.insert(receipt, at: 0); history = Array(history.prefix(200))
        do { try store.write(history, name: "storage-history.json") }
        catch {
            receipt.failures.append("Cleanup results are shown, but history could not be saved: \(error.localizedDescription)")
            history[0] = receipt; try? store.write(receipt, name: "storage-last-operation.json")
        }
        scan = nil; plans.removeAll()
        return receipt
    }
    func undo(receiptID: UUID) throws -> CleanupReceipt {
        guard let index = history.firstIndex(where: { $0.id == receiptID }) else { throw StorageFailure.blocked("Recovery history is unavailable.") }
        var receipt = history[index], remaining: [RecoveryItem] = [], failures: [String] = []
        for (position, recovery) in receipt.recovery.enumerated() {
            if Task.isCancelled {
                remaining += receipt.recovery[position...]; failures.append("Undo canceled. Remaining items stay in Trash."); break
            }
            do { try SecureStorageFS.restore(recovery, policy: policy) }
            catch { remaining.append(recovery); failures.append("\(recovery.original): \(error.localizedDescription)") }
        }
        let restored = receipt.recovery.count - remaining.count
        receipt.recovery = remaining; receipt.note += " Restored \(restored) items with Undo."
        receipt.failures += failures; history[index] = receipt
        do { try store.write(history, name: "storage-history.json") }
        catch { receipt.failures.append("Recovery completed, but history could not be saved: \(error.localizedDescription)"); history[index] = receipt }
        scan = nil; plans.removeAll(); return receipt
    }
}
