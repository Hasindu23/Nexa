import EventKit
import AppKit
import Combine

@MainActor final class CalendarService: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var reminders: [EKReminder] = []
    @Published var calendarAccess = false
    @Published var reminderAccess = false
    @Published var error: String?
    let store = EKEventStore()
    var calendarEnabled = true
    var remindersEnabled = true
    private var observer: NSObjectProtocol?
    private var reminderGeneration = 0
    private let scriptingQueue = DispatchQueue(label: "app.nexa.calendar-navigation", qos: .userInitiated)
    init() {
        calendarAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func requestCalendar() async {
        do { calendarAccess = try await store.requestFullAccessToEvents(); if !calendarAccess { error = "Calendar access is off. You can change this in System Settings → Privacy & Security." }; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func requestReminders() async {
        do { reminderAccess = try await store.requestFullAccessToReminders(); if !reminderAccess { error = "Reminders access is off. You can change this in System Settings → Privacy & Security." }; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func refresh() {
        calendarAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        if calendarAccess && calendarEnabled {
            let now = Date()
            events = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 86400), calendars: nil))
                .filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }
        } else { events = [] }
        reminderGeneration += 1; let generation = reminderGeneration
        if reminderAccess && remindersEnabled {
            store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { [weak self] values in
                Task { @MainActor in
                    guard let self, self.remindersEnabled, generation == self.reminderGeneration else { return }
                    self.reminders = (values ?? []).sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                }
            }
        } else { reminders = [] }
    }
    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do { try store.save(reminder, commit: true); reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier } }
        catch { reminder.isCompleted = false; self.error = error.localizedDescription }
    }
    func createReminder(_ title: String, dueToday: Bool) {
        guard reminderAccess, let calendar = store.defaultCalendarForNewReminders() else { error = "Choose a default Reminders list in the Reminders app first."; return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        let reminder = EKReminder(eventStore: store); reminder.title = title; reminder.calendar = calendar
        if dueToday { reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date()) }
        do { try store.save(reminder, commit: true); refresh() } catch { self.error = error.localizedDescription }
    }
    func open(_ event: EKEvent) {
        guard let uid = event.calendarItemExternalIdentifier else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
            return
        }
        let quoted = uid.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        scriptingQueue.async { [weak self] in
            // Use Calendar's documented scripting dictionary rather than an iOS-only URL scheme.
            let script = """
            with timeout of 5 seconds
                tell application id "com.apple.iCal"
                    activate
                    repeat with c in calendars
                        set matches to (every event of c whose uid is "\(quoted)")
                        if (count of matches) > 0 then
                            show (item 1 of matches)
                            return true
                        end if
                    end repeat
                    return false
                end tell
            end timeout
            """
            var failure: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&failure)
            let denied = failure != nil; let found = result?.booleanValue ?? false
            DispatchQueue.main.async {
                if denied { self?.error = "Allow Calendar automation in Privacy & Security → Automation to open an event." }
                else if !found { self?.error = "Calendar opened. This event could not be selected; it may have moved or changed." }
            }
        }
    }
}
