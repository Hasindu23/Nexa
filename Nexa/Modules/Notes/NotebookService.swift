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
    var dueDate: Date?
    var focused: Bool?
    var completedAt: Date?
}
@MainActor final class NotebookService: ObservableObject {
    @Published private(set) var focusedNoteID: UUID?
    @Published private(set) var notes: [QuickNote]
    @Published private(set) var tasks: [QuickTask]
    @Published var error: String?
    private let store: LocalStore
    private var saveWork: DispatchWorkItem?
    init(store: LocalStore) { self.store = store; notes = store.read([QuickNote].self, name: "notes.json") ?? []; tasks = store.read([QuickTask].self, name: "tasks.json") ?? [] }
    @discardableResult func addNote() -> UUID { let note = QuickNote(); notes.insert(note, at: 0); focusedNoteID = note.id; save(); return note.id }
    func update(_ id: UUID, text: String) { guard let i = notes.firstIndex(where: { $0.id == id }) else { return }; notes[i].text = String(text.prefix(100_000)); notes[i].modified = Date(); saveWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.save() }; saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work) }
    func pin(_ id: UUID) { guard let i = notes.firstIndex(where: { $0.id == id }) else { return }; notes[i].pinned.toggle(); save() }
    func removeNote(_ id: UUID) { notes.removeAll { $0.id == id }; save() }
    func addTask(_ title: String, dueDate: Date? = nil) { let text = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; tasks.insert(QuickTask(title: String(text.prefix(1000)), dueDate: dueDate), at: 0); save() }
    func complete(_ id: UUID, now: Date = Date()) { guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }; tasks[i].completedAt = tasks[i].completedAt == nil ? now : nil; save() }
    func focus(_ id: UUID) {
        let wasFocused = tasks.first(where: { $0.id == id })?.focused == true
        for index in tasks.indices { tasks[index].focused = !wasFocused && tasks[index].id == id }
        save()
    }
    func schedule(_ id: UUID, date: Date?) { guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }; tasks[i].dueDate = date; save() }
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
        }.onAppear { if selected == nil { selected = service.focusedNoteID ?? service.notes.first?.id } }.onChange(of: service.focusedNoteID) { _, id in selected = id }.onDisappear { service.save() }
    }
}

struct TodosView: View {
    @ObservedObject var service: NotebookService
    let accent: Color
    @State private var draft = ""
    @State private var filter = "Today"
    @State private var dueToday = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("One thing at a time.").font(.system(size: 21, weight: .medium)); Spacer(); Picker("Task view", selection: $filter) { ForEach(["Today", "Upcoming", "All", "Completed"], id: \.self) { Text($0) } }.frame(width: 170) }
            HStack { TextField("Add a task", text: $draft).textFieldStyle(.roundedBorder).onSubmit(add); Toggle("Today", isOn: $dueToday).toggleStyle(.button).font(.caption); Button("Add", action: add).buttonStyle(CapsuleButtonStyle(accent: accent)) }
            ForEach(service.tasks.filter { task in
                if filter == "Completed" { return task.completedAt != nil }
                guard task.completedAt == nil else { return false }
                if filter == "Today" { return task.dueDate == nil || Calendar.current.startOfDay(for: task.dueDate!) <= Calendar.current.startOfDay(for: Date()) }
                if filter == "Upcoming" { return task.dueDate.map { Calendar.current.startOfDay(for: $0) > Calendar.current.startOfDay(for: Date()) } ?? false }
                return true
            }.sorted { $0.focused == true && $1.focused != true || $0.focused == $1.focused && $0.favorite && !$1.favorite }) { task in
                HStack(spacing: 10) {
                    Button { service.complete(task.id) } label: { Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(task.completedAt == nil ? .gray : accent) }.buttonStyle(.plain).help(task.completedAt == nil ? "Complete to-do" : "Restore to-do")
                    VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 12)).strikethrough(task.completedAt != nil).foregroundStyle(task.completedAt == nil ? .white : .gray)
                    if let due = task.dueDate { Text(due.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary) }
                    }
                    Spacer()
                    Button { service.focus(task.id) } label: { Image(systemName: task.focused == true ? "scope" : "circle.dashed").foregroundStyle(task.focused == true ? accent : .gray) }.buttonStyle(.plain).help("Focus on this task").disabled(task.completedAt != nil)
                    Button { service.favorite(task.id) } label: { Image(systemName: task.favorite ? "star.fill" : "star").foregroundStyle(task.favorite ? accent : .gray) }.buttonStyle(.plain).help("Favorite")
                }.padding(12).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 11)).contextMenu { Button("Today") { service.schedule(task.id, date: Date()) }; Button("Tomorrow") { service.schedule(task.id, date: Calendar.current.date(byAdding: .day, value: 1, to: Date())) }; Button("No due date") { service.schedule(task.id, date: nil) }; Button("Delete to-do", role: .destructive) { service.removeTask(task.id) } }
            }
            Text("Tasks stay on your Mac. Completed tasks can be restored anytime.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            InlineError(text: service.error)
        }
    }
    private func add() { service.addTask(draft, dueDate: dueToday ? Date() : nil); draft = "" }
}
