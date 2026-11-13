import SwiftUI
import Combine

struct ActivityBanner: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
    var progress: Double? = nil
}

@MainActor final class AppModel: ObservableObject {
    let live = LiveActivityStore()
    var keyboard: WorkspaceShortcutManager?
    let preferences: PreferencesStore
    let storage: StorageService
    var showStorage: (() -> Void)?
    let imageExport = ImageExportService()
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
    var islandVisible = true
    @Published var presentation = IslandPresentation.ambient
    @Published var editingWorkspace = false
    @Published var expanded = false
    @Published var paused = false
    @Published var selected = ModuleID.home
    @Published var banner: ActivityBanner?
    @Published var dropTarget = false
    @Published var sharingItems: [Any] = []
    @Published var showShare = false
    var setPresentation: ((IslandPresentation) -> Void)?
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
    init(preferences: PreferencesStore? = nil, store: LocalStore = LocalStore(), testing: Bool = false, storageHome: URL? = nil) {
        let preferences = preferences ?? PreferencesStore()
        self.preferences = preferences; self.testing = testing
        storage = StorageService(store: store, home: storageHome ?? FileManager.default.homeDirectoryForCurrentUser, testing: testing)
        notebook = NotebookService(store: store); shortcuts = ShortcutsService(store: store, testing: testing)
        files = FileShelfService(store: store); clipboard = ClipboardService(store: store)
        if testing { calendar.calendarEnabled = false; calendar.remindersEnabled = false; calendar.calendarAccess = false; calendar.reminderAccess = false }
        imageExport.activity = { [weak self] state, detail in
            self?.live.put(id: "image-export", title: "Image export", detail: detail, icon: "photo", module: .files, state: state)
        }
        selected = WorkspaceLayout.initialModule(preferences.value)
        files.onAdded = { [weak self] count in
            self?.notify("Ready when you are", detail: "\(count) file references added to your shelf", icon: "tray.and.arrow.down", priority: true)
            self?.live.put(id: "files-\(UUID().uuidString)", title: "Files added", detail: "\(count) references saved. Originals stay in place.", icon: "tray", module: .files, state: .completed)
        }
        clipboard.onCopy = { [weak self] in self?.notify("Copied", detail: "Back on your clipboard", icon: "checkmark", priority: true) }
        timers.onFinish = { [weak self] in
            self?.live.put(id: "timer", title: "Timer finished", detail: "Time for a pause.", icon: "timer", module: .timers, state: .completed, priority: .important)
            self?.notify("Time’s up", detail: "A little pause. You’ve earned it.", icon: "timer", priority: true)
            if self?.preferences.value.soundEffects == true { NSSound(named: "Glass")?.play() }
        }
        controls.onVolumeChanged = { [weak self] value in self?.notify("Volume", detail: "\(Int((value * 100).rounded()))%", icon: "speaker.wave.2", priority: true, progress: value) }
        system.onLowBattery = { [weak self] in self?.notify("Running low", detail: "Your Mac has 15% battery or less", icon: "battery.25percent") }
        system.onPowerChanged = { [weak self] connected, battery in self?.notify(connected ? "Power connected" : "On battery", detail: battery.map { "\($0)% battery" } ?? "Power source changed", icon: connected ? "battery.100percent.bolt" : "battery.75percent") }
        bluetooth.onDisconnected = { [weak self] name in self?.notify("Disconnected", detail: name, icon: "headphones") }
        bluetooth.onConnected = { [weak self] name in self?.notify("Connected", detail: name, icon: "headphones") }
        preferences.$value.dropFirst().removeDuplicates { a, b in
            a.enabledModules == b.enabledModules && a.clipboardEnabled == b.clipboardEnabled && a.historyLimit == b.historyLimit && a.persistentShelf == b.persistentShelf && a.shelfExpiryHours == b.shelfExpiryHours && a.localOnly == b.localOnly && a.mediaConnected == b.mediaConnected
        }.debounce(for: .milliseconds(150), scheduler: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        $selected.dropFirst().sink { [weak self] module in
            self?.preferences.value.lastWorkspace = module
            DispatchQueue.main.async { self?.refreshVisible() }
        }.store(in: &subscriptions)
        timers.objectWillChange.debounce(for: .milliseconds(20), scheduler: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if self.timers.running || (self.timers.remaining > 0 && self.timers.remaining < self.timers.duration) {
                self.live.put(id: "timer", title: "Focus timer", detail: self.timers.remaining.clockString + " remaining", icon: "timer", module: .timers, state: self.timers.running ? .active : .paused)
            } else if self.timers.remaining == self.timers.duration, self.live.items.contains(where: { $0.id == "timer" && $0.ongoing }) {
                self.live.put(id: "timer", title: "Timer reset", detail: "Ready for your next session", icon: "timer", module: .timers, state: .dismissed)
            }
        }.store(in: &subscriptions)
        storage.objectWillChange.debounce(for: .milliseconds(80), scheduler: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if self.storage.busy {
                self.live.put(id: "storage", title: self.storage.cleaning ? "Reviewed cleanup" : "Storage operation", detail: self.storage.status, icon: "externaldrive", module: .storage, state: .active)
            } else if self.live.items.contains(where: { $0.id == "storage" && $0.ongoing }) {
                self.live.put(id: "storage", title: "Storage operation ended", detail: self.storage.error ?? self.storage.status, icon: "externaldrive", module: .storage, state: self.storage.error != nil ? .failed : self.storage.scan == nil ? .dismissed : .completed)
            }
        }.store(in: &subscriptions)
        ai.$busy.removeDuplicates().dropFirst().sink { [weak self] busy in
            DispatchQueue.main.async {
                guard let self else { return }
                self.live.put(id: "nexa-ai", title: "Nexa Assistant", detail: busy ? "Working on your explicit request" : self.ai.error ?? (self.ai.output.isEmpty ? "Request canceled" : "Response ready"), icon: "sparkles", module: .ai, state: busy ? .active : self.ai.error != nil ? .failed : self.ai.output.isEmpty ? .dismissed : .completed)
            }
        }.store(in: &subscriptions)
        calendar.$events.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.scheduleCalendarAlert() } }.store(in: &subscriptions)
        if !testing {
            keyboard = WorkspaceShortcutManager(model: self)
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
        media.visible = islandVisible && expanded && (selected == .music || selected == .home) && !paused
        if !islandVisible || !expanded || paused || !preferences.value.enabledModules.contains(.mirror) || (selected != .home && selected != .mirror) { mirror.stop() }
        if !islandVisible || !expanded || ![ModuleID.system, .home].contains(selected) || paused { system.setVisible(false) }
        guard islandVisible && expanded && !paused else { return }
        // Keep synchronous device, EventKit and disk queries off the opening frame.
        let destination = selected
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.islandVisible, self.expanded, !self.paused, self.selected == destination else { return }
            if destination == .controls || destination == .music { self.controls.refresh() }
            if destination == .calendar || destination == .reminders || (destination == .home && Date().timeIntervalSince(self.lastCalendarRefresh) > 30) {
                self.calendar.refresh(); self.lastCalendarRefresh = Date()
            }
            if destination == .bluetooth { self.bluetooth.refresh() }
            if destination == .files { self.files.prune() }
            if (destination == .system || destination == .home && self.preferences.value.homeWidgets.contains(where: { $0.module == .system })) && self.preferences.value.enabledModules.contains(.system) { self.system.setVisible(true) }
        }
        visibleRefresh = work
        let motion = NexaMotion(preferences: preferences.value, systemReduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        DispatchQueue.main.asyncAfter(deadline: .now() + motion.expansionDuration + 0.10, execute: work)
    }
    func togglePause() { paused.toggle(); if paused { setExpanded?(false) }; configure() }
    func notify(_ title: String, detail: String, icon: String, priority: Bool = false, progress: Double? = nil) {
        guard !paused, priority || Date().timeIntervalSince(lastBannerTime) > 30 else { return }
        lastBannerTime = Date(); bannerDismiss?.cancel(); banner = ActivityBanner(title: title, detail: detail, icon: icon, progress: progress)
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
    func shutdown() { imageExport.cancel(); keyboard?.stop(); live.stop(); storage.stop(); visibleRefresh?.cancel(); mirror.stop(); notebook.save(); shortcuts.cancel(); media.stop(); clipboard.stop(); timers.stop(); system.setVisible(false); controls.stop(); bluetooth.stop(); weather.cancel(); ai.cancel(); updater.cancel(); housekeeping?.invalidate(); calendarAlert?.cancel() }
}
