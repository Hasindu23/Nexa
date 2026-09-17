import SwiftUI

struct RemindersView: View {
    @ObservedObject var service: CalendarService
    let accent: Color
    @State private var title = ""
    @State private var today = true
    @State private var onlyToday = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("One thing at a time.").font(.system(size: 22, weight: .medium)).tracking(-0.5); Spacer(); if service.reminderAccess { Toggle("Due today", isOn: $onlyToday).toggleStyle(.checkbox).font(.system(size: 11)) } }
            if !service.reminderAccess {
                EmptyModule(icon: "checklist", title: "Room for what matters.", detail: "Connect Reminders to view your lists, complete tasks and capture a quick thought.")
                Button("Connect Reminders") { Task { await service.requestReminders() } }.buttonStyle(CapsuleButtonStyle(accent: accent, filled: true)).frame(maxWidth: .infinity)
            } else {
                HStack { TextField("Add a quick reminder…", text: $title).textFieldStyle(.plain).onSubmit(add); Toggle("Today", isOn: $today).toggleStyle(.checkbox).font(.system(size: 10)); IconButton(symbol: "plus", help: "Create reminder", size: 27, action: add).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(11).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 11))
                let reminders = service.reminders.filter { !onlyToday || ($0.dueDateComponents?.date.map { Calendar.current.isDateInToday($0) } ?? false) }
                if reminders.isEmpty { Text("All clear. Enjoy the space.").foregroundStyle(NexaStyle.secondary).font(.system(size: 12)).padding(.vertical, 25) }
                ForEach(Array(reminders.prefix(30)), id: \.calendarItemIdentifier) { reminder in
                    HStack(spacing: 12) {
                        Button { service.complete(reminder) } label: { Image(systemName: "circle").font(.system(size: 19, weight: .light)).foregroundStyle(accent) }.buttonStyle(.plain).help("Mark complete")
                        VStack(alignment: .leading, spacing: 4) { Text(reminder.title ?? "Untitled").font(.system(size: 12)).lineLimit(2); if let due = reminder.dueDateComponents?.date { Text(due.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary) } }
                        Spacer()
                    }.padding(.vertical, 9)
                    Divider().overlay(NexaStyle.line)
                }
            }
            InlineError(text: service.error)
        }
    }
    private func add() { guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }; service.createReminder(title, dueToday: today); if service.error == nil { title = "" } }
}
