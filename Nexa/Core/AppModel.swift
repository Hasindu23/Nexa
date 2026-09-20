import SwiftUI
import Combine

struct ActivityBanner: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
}

@MainActor final class AppModel: ObservableObject {
    let preferences: PreferencesStore
    let storage: StorageService
    var showStorage: (() -> Void)?
    let files: FileShelfService
    let clipboard: ClipboardService
    let mirror = MirrorService()
    let notebook: NotebookService
    let shortcuts: ShortcutsService
    let media = NowPlayingService()
    let calendar = CalendarService()
    let timers = TimerService()
    let system = SystemService()
    let controls = QuickControlsService()
    let weather = WeatherService()
    let bluetooth = BluetoothService()
    let ai = AIService()
    let updater = UpdateService()
    @Published var expanded = false
    @Published var paused = false
    @Published var selected = ModuleID.home
    @Published var banner: ActivityBanner?
    @Published var dropTarget = false
    @Published var sharingItems: [Any] = []
    @Published var showShare = false
    var setExpanded: ((Bool) -> Void)?
    var showSettings: (() -> Void)?
    var showOnboarding: (() -> Void)?
    private var subscriptions = Set<AnyCancellable>()
    private var bannerDismiss: DispatchWorkItem?
    private var calendarAlert: DispatchWorkItem?
    private var housekeeping: Timer?
    private var visibleRefresh: DispatchWorkItem?
    private var lastCalendarRefresh = Date.distantPast
    private var lastBannerTime = Date.distantPast
    private var announcedEvents = Set<String>()
    let testing: Bool
    init(preferences: PreferencesStore? = nil, store: LocalStore = LocalStore(), testing: Bool = false) {
        let preferences = preferences ?? PreferencesStore()
        self.preferences = preferences; self.testing = testing
        storage = StorageService(store: store, testing: testing)
        notebook = NotebookService(store: store); shortcuts = ShortcutsService(store: store)
        files = FileShelfService(store: store); clipboard = ClipboardService(store: store)
        files.onAdded = { [weak self] count in self?.notify("Ready when you are", detail: "\(count) \(count == 1 ? "file" : "files") added to your shelf", icon: "tray.and.arrow.down", priority: true) }
        clipboard.onCopy = { [weak self] in self?.notify("Copied", detail: "Back on your clipboard", icon: "checkmark", priority: true) }
        timers.onFinish = { [weak self] in
            self?.notify("Time’s up", detail: "A little pause. You’ve earned it.", icon: "timer", priority: true)
            if self?.preferences.value.soundEffects == true { NSSound(named: "Glass")?.play() }
        }
        system.onLowBattery = { [weak self] in self?.notify("Running low", detail: "Your Mac has 15% battery or less", icon: "battery.25percent") }
        system.onPowerChanged = { [weak self] connected, battery in self?.notify(connected ? "Power connected" : "On battery", detail: battery.map { "\($0)% battery" } ?? "Power source changed", icon: connected ? "battery.100percent.bolt" : "battery.75percent") }
        bluetooth.onDisconnected = { [weak self] name in self?.notify("Disconnected", detail: name, icon: "headphones") }
        bluetooth.onConnected = { [weak self] name in self?.notify("Connected", detail: name, icon: "headphones") }
        preferences.$value.dropFirst().removeDuplicates { a, b in
            a.enabledModules == b.enabledModules && a.clipboardEnabled == b.clipboardEnabled && a.historyLimit == b.historyLimit && a.persistentShelf == b.persistentShelf && a.shelfExpiryHours == b.shelfExpiryHours && a.localOnly == b.localOnly && a.mediaConnected == b.mediaConnected
        }.debounce(for: .milliseconds(150), scheduler: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        $selected.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.refreshVisible() } }.store(in: &subscriptions)
        calendar.$events.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.scheduleCalendarAlert() } }.store(in: &subscriptions)
        if !testing {
            configure()
            let timer = Timer(timeInterval: 900, repeats: true) { [weak self] _ in Task { @MainActor in self?.files.prune() } }
            timer.tolerance = 60; RunLoop.main.add(timer, forMode: .common); housekeeping = timer
        }
    }
    var modules: [ModuleID] { ModuleID.allCases.filter { preferences.value.enabledModules.contains($0) } }
    func configure() {
        guard !testing else { return }
        let config = preferences.value
        files.configure(persistent: config.persistentShelf, expiryHours: config.shelfExpiryHours)
        clipboard.limit = config.historyLimit; clipboard.trim()
        if config.clipboardEnabled && config.enabledModules.contains(.clipboard) && !paused { clipboard.start() } else { clipboard.stop() }
        media.allowNetwork = !config.localOnly
        if config.mediaConnected && config.enabledModules.contains(.music) && !paused { media.start() } else if media.connected { media.stop() }
        calendar.calendarEnabled = config.enabledModules.contains(.calendar) && !paused
        calendar.remindersEnabled = config.enabledModules.contains(.reminders) && !paused
        calendar.refresh()
        if !config.enabledModules.contains(.timers) { timers.suspend() }
        if config.enabledModules.contains(.bluetooth) && !paused { bluetooth.start() } else { bluetooth.stop() }
        if config.localOnly || !config.enabledModules.contains(.ai) { ai.cancel() }
        if config.localOnly || !config.enabledModules.contains(.weather) { weather.cancel() }
        if config.localOnly { updater.cancel() }
        if !modules.contains(selected), let first = modules.first { selected = first }
        refreshVisible()
    }
    func refreshVisible() {
        guard !testing else { return }
        visibleRefresh?.cancel()
        media.visible = expanded && (selected == .music || selected == .home) && !paused
        if !expanded || paused || !preferences.value.enabledModules.contains(.mirror) || (selected != .home && selected != .mirror) { mirror.stop() }
        if !expanded || selected != .system || paused { system.setVisible(false) }
        guard expanded && !paused else { return }
        // Keep synchronous device, EventKit and disk queries off the opening frame.
        let destination = selected
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.expanded, !self.paused, self.selected == destination else { return }
            if destination == .controls || destination == .music { self.controls.refresh() }
            if destination == .calendar || destination == .reminders || (destination == .home && Date().timeIntervalSince(self.lastCalendarRefresh) > 30) {
                self.calendar.refresh(); self.lastCalendarRefresh = Date()
            }
            if destination == .bluetooth { self.bluetooth.refresh() }
            if destination == .files { self.files.prune() }
            if destination == .system && self.preferences.value.enabledModules.contains(.system) { self.system.setVisible(true) }
        }
        visibleRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38 / max(0.5, min(2, preferences.value.animationSpeed)) + 0.10, execute: work)
    }
    func togglePause() { paused.toggle(); if paused { setExpanded?(false) }; configure() }
    func notify(_ title: String, detail: String, icon: String, priority: Bool = false) {
        guard !paused, priority || Date().timeIntervalSince(lastBannerTime) > 30 else { return }
        lastBannerTime = Date(); bannerDismiss?.cancel(); banner = ActivityBanner(title: title, detail: detail, icon: icon)
        let work = DispatchWorkItem { [weak self] in self?.banner = nil }; bannerDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
    func scheduleCalendarAlert() {
        calendarAlert?.cancel()
        guard preferences.value.enabledModules.contains(.calendar), !paused, let event = calendar.events.first(where: { !$0.isAllDay && $0.startDate > Date() && !announcedEvents.contains($0.eventIdentifier ?? "") }), let id = event.eventIdentifier else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.announcedEvents.insert(id)
            self?.notify("Coming up", detail: event.title ?? "Calendar event", icon: "calendar")
            self?.scheduleCalendarAlert()
        }
        calendarAlert = work; DispatchQueue.main.asyncAfter(deadline: .now() + max(0, event.startDate.timeIntervalSinceNow - 300), execute: work)
    }
    func shutdown() { storage.stop(); visibleRefresh?.cancel(); mirror.stop(); notebook.save(); shortcuts.cancel(); media.stop(); clipboard.stop(); timers.stop(); system.setVisible(false); controls.stop(); bluetooth.stop(); weather.cancel(); ai.cancel(); updater.cancel(); housekeeping?.invalidate(); calendarAlert?.cancel() }
}
