import SwiftUI
import EventKit

struct CalendarModuleView: View {
    @ObservedObject var service: CalendarService
    let accent: Color
    @State private var selectedDate = Date()
    @Environment(\.nexaMotion) private var motion
    private var calendar: Calendar { .current }
    private var dayEvents: [CalendarEvent] {
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return service.monthEvents.filter { $0.startDate < end && $0.endDate > start }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("A little ahead of your day.").font(.system(size: 24, weight: .medium)).tracking(-0.5); Spacer(); IconButton(symbol: "arrow.clockwise", help: "Refresh calendar") { service.refresh() } }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { schedule.frame(minWidth: 245); monthGrid.frame(width: 280) }
                VStack(alignment: .leading, spacing: 20) { monthGrid; schedule }
            }
            InlineError(text: service.error)
        }.onAppear { service.loadMonth(selectedDate) }
    }
    private var schedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.system(size: 15, weight: .semibold))
            if !service.calendarAccess {
                EmptyModule(icon: "calendar", title: "Your day, at a glance.", detail: "Connect Calendar to read your events locally.")
                Button("Connect Calendar") { Task { await service.requestCalendar() } }.buttonStyle(CapsuleButtonStyle(accent: accent, filled: true))
            } else if dayEvents.isEmpty {
                EmptyModule(icon: "sun.horizon", title: "A little breathing room.", detail: "No events on this date.")
            } else {
                ForEach(dayEvents) { event in
                    Button { service.open(event) } label: {
                        HStack(spacing: 11) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(event.color)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.title ?? "Untitled event").font(.system(size: 13, weight: .medium)).lineLimit(2)
                                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened) + " – " + event.endDate.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(12).frame(minHeight: 62).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).animation(motion.moduleAnimation, value: selectedDate)
    }
    private var monthGrid: some View {
        VStack(spacing: 14) {
            HStack {
                Text(selectedDate.formatted(.dateTime.month(.wide).year())).font(.system(size: 14, weight: .semibold))
                Spacer()
                IconButton(symbol: "chevron.left", help: "Previous month", size: 22) { changeMonth(-1) }
                IconButton(symbol: "chevron.right", help: "Next month", size: 22) { changeMonth(1) }
            }
            let days = CalendarMonth.days(containing: selectedDate, calendar: calendar)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 5) {
                ForEach(0..<7) { offset in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7]).font(.system(size: 9, weight: .semibold)).foregroundStyle(NexaStyle.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button { selectedDate = date } label: {
                            Text(date.formatted(.dateTime.day())).font(.system(size: 12, weight: calendar.isDateInToday(date) ? .bold : .regular))
                                .frame(maxWidth: .infinity).frame(height: 29)
                                .background(calendar.isDate(date, inSameDayAs: selectedDate) ? accent.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(calendar.isDateInToday(date) ? accent.opacity(0.7) : .clear))
                        }.buttonStyle(NotchButtonStyle()).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                            .accessibilityAddTraits(calendar.isDate(date, inSameDayAs: selectedDate) ? .isSelected : [])
                    } else { Color.clear.frame(height: 29) }
                }
            }
            Button("Today") { selectedDate = Date(); service.loadMonth(selectedDate) }.buttonStyle(CapsuleButtonStyle(accent: accent))
        }.padding(17).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private func changeMonth(_ offset: Int) {
        guard let date = calendar.date(byAdding: .month, value: offset, to: selectedDate) else { return }
        selectedDate = date; service.loadMonth(date)
    }
}

enum CalendarMonth {
    static func days(containing date: Date, calendar: Calendar) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date), let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let padding = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: padding) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month.start) }
    }
}
