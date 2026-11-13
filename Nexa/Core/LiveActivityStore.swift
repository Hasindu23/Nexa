import SwiftUI

struct LiveActivity: Identifiable, Equatable {
    enum State: String { case queued, active, paused, completed, failed, dismissed }
    enum Priority: Int { case background, normal, important }
    var id: String
    var title: String
    var detail: String
    var icon: String
    var module: ModuleID
    var state: State
    var priority: Priority = .normal
    var updated = Date()
    var expires: Date?
    var ongoing: Bool { [.queued, .active, .paused].contains(state) }
}

/// In-memory metadata about Nexa-owned operations. No file contents or AI input.
@MainActor final class LiveActivityStore: ObservableObject {
    @Published private(set) var items: [LiveActivity] = []
    private var expiryWork: DispatchWorkItem?
    func put(id: String, title: String, detail: String, icon: String, module: ModuleID, state: LiveActivity.State,
             priority: LiveActivity.Priority = .normal, now: Date = Date()) {
        let ongoing = [.queued, .active, .paused].contains(state)
        let activity = LiveActivity(id: id, title: title, detail: detail, icon: icon, module: module, state: state,
            priority: priority, updated: now, expires: ongoing ? nil : now.addingTimeInterval(300))
        if let index = items.firstIndex(where: { $0.id == id }) { items[index] = activity }
        else { items.insert(activity, at: 0) }
        items.sort { $0.priority != $1.priority ? $0.priority.rawValue > $1.priority.rawValue : $0.updated > $1.updated }
        items = Array(items.prefix(40)); scheduleExpiry(now: now)
    }
    func dismiss(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].ongoing else { return }
        items.remove(at: index); scheduleExpiry(now: Date())
    }
    func expire(now: Date = Date()) { items.removeAll { $0.expires.map { $0 <= now } ?? false }; scheduleExpiry(now: now) }
    private func scheduleExpiry(now: Date) {
        expiryWork?.cancel()
        guard let next = items.compactMap(\.expires).min() else { return }
        let work = DispatchWorkItem { [weak self] in self?.expire() }; expiryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, next.timeIntervalSince(now)), execute: work)
    }
    func stop() { expiryWork?.cancel(); expiryWork = nil }
    deinit { expiryWork?.cancel() }
}

struct LiveActivitiesView: View {
    @ObservedObject var service: LiveActivityStore
    var open: (ModuleID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Happening in Nexa").font(.system(size: 24, weight: .medium))
            Text("Your timers, file shelf, storage operations and connected AI requests.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
            if service.items.isEmpty { EmptyModule(icon: "bolt.horizontal.circle", title: "All quiet", detail: "Real Nexa activity appears here. Completed items expire after five minutes.") }
            ForEach(service.items) { activity in
                HStack(spacing: 12) {
                    Image(systemName: activity.icon).font(.system(size: 20)).foregroundStyle(activity.state == .failed ? .orange : Color.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(activity.title).font(.system(size: 13, weight: .semibold))
                        Text(activity.detail).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineLimit(2)
                    }
                    Spacer()
                    Text(activity.state.rawValue.capitalized).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
                    Button("Open") { open(activity.module) }.buttonStyle(CapsuleButtonStyle(accent: .blue))
                    if !activity.ongoing { IconButton(symbol: "xmark", help: "Dismiss activity", size: 24) { service.dismiss(activity.id) } }
                }.padding(14).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }
}
