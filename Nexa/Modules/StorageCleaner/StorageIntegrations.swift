import Foundation
import CryptoKit

enum StorageProcess {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 12, accepted: Set<Int32> = [0]) throws -> Data {
        try Task.checkCancellation()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("nexa-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent("output"), errors = scratch.appendingPathComponent("errors")
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errors.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: errors)
        defer { try? out.close(); try? err.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
        try process.run(); let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() > deadline {
                process.terminate()
                throw StorageFailure.blocked(Task.isCancelled ? "Operation canceled." : "Local service timed out. Rescan before retrying.")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard accepted.contains(process.terminationStatus) else {
            let detail = String(data: (try? Data(contentsOf: errors)) ?? Data(), encoding: .utf8) ?? "Local service unavailable."
            throw StorageFailure.blocked(String(detail.prefix(500)))
        }
        let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= 20_000_000 else { throw StorageFailure.blocked("Service response exceeds the safe response limit.") }
        return try Data(contentsOf: output)
    }
    static func openFiles(_ paths: [String]) throws -> Set<String> {
        var result = Set<String>()
        for offset in stride(from: 0, to: paths.count, by: 100) {
            let batch = Array(paths[offset..<min(paths.count, offset + 100)])
            let data = try run("/usr/sbin/lsof", ["-n", "-P", "-F", "n", "--"] + batch, accepted: [0, 1])
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.hasPrefix("n/") { result.insert(String(line.dropFirst())) }
        }
        return result
    }
}

struct StorageIntegrations: Sendable {
    let home: URL
    var dockerSocket: String? {
        let candidates = [home.appendingPathComponent(".docker/run/docker.sock").path, home.appendingPathComponent(".docker/desktop/docker.sock").path]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
    func dockerRequest(_ path: String, method: String = "GET") throws -> Data {
        guard let socket = dockerSocket else { throw StorageFailure.blocked("Docker Desktop’s local socket is unavailable. Start Docker Desktop, then scan again.") }
        // Fixed local Unix socket: no Docker contexts, environment hosts, TCP endpoints or remote commands.
        return try StorageProcess.run("/usr/bin/curl", ["-q", "--silent", "--show-error", "--fail", "--max-time", "10", "--noproxy", "*", "--unix-socket", socket, "-X", method, "http://localhost/v1.47" + path])
    }
    func ollamaRequest(_ path: String, method: String = "GET", body: Data? = nil) throws -> Data {
        var args = ["-q", "--silent", "--show-error", "--fail", "--max-time", "10", "--noproxy", "*", "-X", method, "-H", "Content-Type: application/json"]
        if let body { args += ["--data-binary", String(decoding: body, as: UTF8.self)] }
        args.append("http://127.0.0.1:11434/api/" + path)
        return try StorageProcess.run("/usr/bin/curl", args)
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StorageFailure.blocked("Unsupported local service response.") }; return object
    }
    static func signature(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func docker() throws -> [StorageItem] {
        let response = try Self.object(dockerRequest("/system/df"))
        return Self.dockerItems(response)
    }
    static func dockerItems(_ response: [String: Any]) -> [StorageItem] {
        var result: [StorageItem] = []
        func add(_ raw: [String: Any], kind: String, id: String, name: String, size: Int64, eligible: Bool, group: String, version: [String: Any]) {
            guard !id.isEmpty else { return }
            result.append(StorageItem(id: "docker:\(kind):\(id)", path: name, root: "local-docker", category: .docker, group: group,
                                      bytes: max(0, size), allocated: max(0, size), modified: Date(timeIntervalSince1970: (raw["Created"] as? NSNumber)?.doubleValue ?? 0), accessed: nil, created: nil, stamp: nil,
                                      risk: kind == "volume" ? .sensitive : .review, eligible: eligible,
                                      reason: kind == "build" ? "Inventory only. Review and prune in Docker Desktop." : eligible ? "Permanent resource removal. Host disk recovery may differ from Docker’s estimate." : "In use or usage unknown; cannot remove.",
                                      recommended: false, resourceKind: "docker-" + kind, resourceVersion: signature(version)))
        }
        for raw in response["Containers"] as? [[String: Any]] ?? [] {
            let id = raw["Id"] as? String ?? "", state = raw["State"] as? String ?? ""
            let size = (raw["SizeRw"] as? NSNumber)?.int64Value ?? 0
            let stopped = ["exited", "dead", "created"].contains(state)
            add(raw, kind: "container", id: id, name: (raw["Names"] as? [String])?.first ?? String(id.prefix(12)), size: size, eligible: stopped, group: stopped ? "Stopped containers" : "Active containers", version: ["id": id, "state": state, "size": size])
        }
        for raw in response["Images"] as? [[String: Any]] ?? [] {
            let id = raw["Id"] as? String ?? "", refs = (raw["Containers"] as? NSNumber)?.intValue ?? -1
            let total = (raw["Size"] as? NSNumber)?.int64Value ?? -1, shared = (raw["SharedSize"] as? NSNumber)?.int64Value ?? -1
            let size = total < 0 || shared < 0 ? 0 : max(0, total - shared)
            let tags = raw["RepoTags"] as? [String] ?? [], dangling = tags.isEmpty || tags == ["<none>:<none>"]
            add(raw, kind: "image", id: id, name: dangling ? String(id.prefix(20)) : tags.joined(separator: ", "), size: size, eligible: refs == 0, group: refs != 0 ? "Images in use or unknown" : dangling ? "Dangling images" : "Unused images", version: ["id": id, "refs": refs, "tags": tags, "size": size])
        }
        for raw in response["Volumes"] as? [[String: Any]] ?? [] {
            let id = raw["Name"] as? String ?? "", usage = raw["UsageData"] as? [String: Any] ?? [:]
            let refs = (usage["RefCount"] as? NSNumber)?.intValue ?? -1, size = (usage["Size"] as? NSNumber)?.int64Value ?? -1
            add(raw, kind: "volume", id: id, name: id, size: size, eligible: refs == 0 && size >= 0, group: refs == 0 ? "Unused volumes" : "Volumes in use or unknown", version: ["name": id, "refs": refs, "size": size, "created": raw["CreatedAt"] as? String ?? "", "driver": raw["Driver"] as? String ?? ""])
        }
        for raw in response["BuildCache"] as? [[String: Any]] ?? [] {
            add(raw, kind: "build", id: raw["ID"] as? String ?? "", name: raw["Description"] as? String ?? "Build cache", size: (raw["Size"] as? NSNumber)?.int64Value ?? 0, eligible: false, group: "Build cache", version: raw)
        }
        return result
    }
    func models() throws -> [StorageItem] {
        let tags = try Self.object(ollamaRequest("tags")), ps = try Self.object(ollamaRequest("ps"))
        let running = Set((ps["models"] as? [[String: Any]] ?? []).compactMap { $0["digest"] as? String })
        return (tags["models"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let name = raw["name"] as? String, let digest = raw["digest"] as? String, let size = (raw["size"] as? NSNumber)?.int64Value else { return nil }
            let active = running.contains(digest)
            return StorageItem(id: "ollama:" + name, path: name, root: "local-ollama", category: .models, group: "Installed models", bytes: size, allocated: size,
                               modified: ISO8601DateFormatter().date(from: raw["modified_at"] as? String ?? "") ?? .distantPast, accessed: nil, created: nil, stamp: nil, risk: .sensitive, eligible: !active,
                               reason: active ? "Model is running. Stop it in Ollama before removing." : "Last used unavailable. Modified date is not a last-use date. Shared layers may remain.", recommended: false, resourceKind: "ollama-model", resourceVersion: digest)
        }
    }
    func remove(_ item: StorageItem) throws {
        let current = try item.category == .docker ? docker() : models()
        guard let fresh = current.first(where: { $0.id == item.id }), fresh.eligible, fresh.resourceVersion == item.resourceVersion, fresh.bytes == item.bytes else {
            throw StorageFailure.blocked("Resource changed, became active, or disconnected. Scan and review again.")
        }
        if item.category == .docker {
            let prefix = "docker:" + (item.resourceKind ?? "").replacingOccurrences(of: "docker-", with: "") + ":"
            let id = String(item.id.dropFirst(prefix.count))
            guard !id.isEmpty, id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$", options: .regularExpression) != nil else { throw StorageFailure.blocked("Invalid Docker resource identifier.") }
            let endpoint: String
            switch item.resourceKind {
            case "docker-container": endpoint = "/containers/\(id)?force=false&v=false"
            case "docker-image": endpoint = "/images/\(id)?force=false&noprune=true"
            case "docker-volume": endpoint = "/volumes/\(id)?force=false"
            default: throw StorageFailure.blocked("This resource cannot be pruned safely from an exact-item preview.")
            }
            _ = try dockerRequest(endpoint, method: "DELETE")
            guard try !docker().contains(where: { $0.id == item.id }) else { throw StorageFailure.blocked("Docker did not verify removal. Rescan.") }
        } else {
            _ = try ollamaRequest("delete", method: "DELETE", body: JSONSerialization.data(withJSONObject: ["model": item.path]))
            guard try !models().contains(where: { $0.id == item.id }) else { throw StorageFailure.blocked("Ollama did not verify removal. Rescan.") }
        }
    }
}
