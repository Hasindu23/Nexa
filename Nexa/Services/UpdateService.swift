import Foundation
import AppKit
import Combine

@MainActor final class UpdateService: ObservableObject {
    @Published var message = "No update feed configured. This build never checks automatically."
    @Published var releaseURL: URL?
    @Published var busy = false
    private var task: Task<Void, Never>?
    struct Release: Decodable { let version: String; let url: URL }
    func cancel() { task?.cancel(); task = nil; busy = false }
    func check(feed: String, allowed: Bool) {
        guard allowed else { message = "Turn off Local-only mode to check for updates."; return }
        guard let url = URL(string: feed), url.scheme == "https", url.host != nil else { message = "Add an HTTPS release feed URL first."; return }
        cancel(); busy = true; releaseURL = nil
        task = Task { [weak self] in
            do {
                let (data, response) = try await NetworkClient.session.data(from: url)
                try Task.checkCancellation(); try NetworkClient.checked(response)
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard release.url.scheme == "https" else { throw NexaError.message("The release link must use HTTPS.") }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                if release.version.compare(current, options: .numeric) == .orderedDescending { self?.message = "Version \(release.version) is available."; self?.releaseURL = release.url }
                else { self?.message = "You’re up to date (\(current))." }
                self?.busy = false
            } catch { guard !Task.isCancelled else { return }; self?.message = error.localizedDescription; self?.busy = false }
        }
    }
}
