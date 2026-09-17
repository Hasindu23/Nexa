import SwiftUI

struct QuickNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var modified = Date()
    var pinned = false
}
struct QuickTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var favorite = false
    var completedAt: Date?
}
@MainActor final class NotebookService: ObservableObject {
    @Published private(set) var notes: [QuickNote]
    @Published private(set) var tasks: [QuickTask]
    @Published var error: String?
    private let store: LocalStore
    private var saveWork: DispatchWorkItem?
    init(store: LocalStore) { self.store = store; notes = store.read([QuickNote].self, name: "notes.json") ?? []; tasks = store.read([QuickTask].self, name: "tasks.json") ?? [] }
    @discardableResult func addNote() -> UUID { let note = QuickNote(); notes.insert(note, at: 0); save(); return note.id }
    func update(_ id: UUID, text: String) { guard let i = notes.firstIndex(where: { $0.id == id }) else { return }; notes[i].text = String(text.prefix(100_000)); notes[i].modified = Date(); saveWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.save() }; saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work) }
    func pin(_ id: UUID) { guard let i = notes.firstIndex(where: { $0.id == id }) else { return }; notes[i].pinned.toggle(); save() }
    func removeNote(_ id: UUID) { notes.removeAll { $0.id == id }; save() }
    func addTask(_ title: String) { let text = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; tasks.insert(QuickTask(title: String(text.prefix(1000))), at: 0); save() }
    func complete(_ id: UUID, now: Date = Date()) { guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }; tasks[i].completedAt = tasks[i].completedAt == nil ? now : nil; save() }
    func favorite(_ id: UUID) { guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }; tasks[i].favorite.toggle(); save() }
    func removeTask(_ id: UUID) { tasks.removeAll { $0.id == id }; save() }
    func archived(_ task: QuickTask, now: Date = Date()) -> Bool { task.completedAt.map { now.timeIntervalSince($0) >= 86400 } ?? false }
    func save() { do { try store.write(notes, name: "notes.json"); try store.write(tasks, name: "tasks.json") } catch { self.error = "Couldn’t save your notebook: \(error.localizedDescription)" } }
}

struct NotesView: View {
    @ObservedObject var service: NotebookService
    let accent: Color
    @State private var selected: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("A thought worth keeping.").font(.system(size: 21, weight: .medium)); Spacer(); IconButton(symbol: "plus", help: "New note") { selected = service.addNote() } }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(service.notes.sorted { $0.pinned && !$1.pinned }) { note in
                            Button { selected = note.id } label: { HStack { if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)) }; Text(note.text.isEmpty ? "Untitled" : String(note.text.prefix(60))).lineLimit(2); Spacer() }.font(.system(size: 11)).padding(10).background(selected == note.id ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
                                .contextMenu { Button(note.pinned ? "Unpin" : "Pin") { service.pin(note.id) }; Button("Delete note", role: .destructive) { service.removeNote(note.id); if selected == note.id { selected = service.notes.first?.id } } }
                        }
                    }
                }.frame(width: 150)
                if let id = selected, service.notes.contains(where: { $0.id == id }) {
                    TextEditor(text: Binding(get: { service.notes.first(where: { $0.id == id })?.text ?? "" }, set: { service.update(id, text: $0) })).font(.system(size: 13)).scrollContentBackground(.hidden).padding(10).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                } else { EmptyModule(icon: "note.text", title: "A blank page", detail: "Add a note. It saves on your Mac as you type.") }
            }.frame(height: 235)
            InlineError(text: service.error)
        }.onAppear { if selected == nil { selected = service.notes.first?.id } }.onDisappear { service.save() }
    }
}

struct TodosView: View {
    @ObservedObject var service: NotebookService
    let accent: Color
    @State private var draft = ""
    @State private var archived = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("One thing at a time.").font(.system(size: 21, weight: .medium)); Spacer(); Toggle("Archive", isOn: $archived).toggleStyle(.button).font(.system(size: 11)) }
            HStack { TextField("Add a to-do", text: $draft).textFieldStyle(.roundedBorder).onSubmit(add); Button("Add", action: add).buttonStyle(CapsuleButtonStyle(accent: accent)) }
            ForEach(service.tasks.filter { service.archived($0) == archived }.sorted { $0.favorite && !$1.favorite }) { task in
                HStack(spacing: 10) {
                    Button { service.complete(task.id) } label: { Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(task.completedAt == nil ? .gray : accent) }.buttonStyle(.plain).help(task.completedAt == nil ? "Complete to-do" : "Restore to-do")
                    Text(task.title).font(.system(size: 12)).strikethrough(task.completedAt != nil).foregroundStyle(task.completedAt == nil ? .white : .gray)
                    Spacer(); Button { service.favorite(task.id) } label: { Image(systemName: task.favorite ? "star.fill" : "star").foregroundStyle(task.favorite ? accent : .gray) }.buttonStyle(.plain).help("Favorite")
                }.padding(12).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 11)).contextMenu { Button("Delete to-do", role: .destructive) { service.removeTask(task.id) } }
            }
            Text("Completed to-dos move to Archive after 24 hours. You can restore them anytime.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            InlineError(text: service.error)
        }
    }
    private func add() { service.addTask(draft); draft = "" }
}
