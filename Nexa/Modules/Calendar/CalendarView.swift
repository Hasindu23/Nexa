import SwiftUI
import EventKit

struct CalendarModuleView: View {
    @ObservedObject var service: CalendarService
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("A little ahead of your day.").font(.system(size: 21, weight: .medium)).tracking(-0.5); Spacer(); IconButton(symbol: "arrow.clockwise", help: "Refresh calendar") { service.refresh() } }
            if !service.calendarAccess {
                EmptyModule(icon: "calendar", title: "Your day, at a glance.", detail: "Connect Calendar to see upcoming events. Nexa reads events locally and never uploads them.")
                Button("Connect Calendar") { Task { await service.requestCalendar() } }.buttonStyle(CapsuleButtonStyle(accent: accent, filled: true)).frame(maxWidth: .infinity)
            } else if service.events.isEmpty { EmptyModule(icon: "sun.horizon", title: "A little breathing room.", detail: "No upcoming events in the next seven days.") }
            else {
                ForEach(Array(service.events.prefix(20)), id: \.calendarItemIdentifier) { event in
                    Button { service.open(event) } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 5) { Text(event.title ?? "Untitled event").font(.system(size: 13, weight: .medium)).lineLimit(1); Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary) }
                            Spacer()
                            if event.startDate > Date() && !event.isAllDay { Text(event.startDate, style: .relative).font(.system(size: 10)).foregroundStyle(accent) }
                            Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
                        }.padding(13).frame(minHeight: 64).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            InlineError(text: service.error)
        }
    }
}
