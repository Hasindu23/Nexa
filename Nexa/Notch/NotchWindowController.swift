import AppKit
import SwiftUI
import Combine
import QuartzCore

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // This panel intentionally occupies the menu-bar/notch area. AppKit's
    // ordinary window constraint would move it below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor final class NotchWindowController: NSWindowController {
    let model: AppModel
    private(set) var geometry: NotchGeometry
    private(set) var activeDisplayID: String?
    private var displayOverrideID: String?
    private let geometryOverride: NotchGeometry?
    private var subscriptions = Set<AnyCancellable>()
    private var hoverWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var localEvents: Any?
    private var lastScroll = Date.distantPast
    private var menuTracking = 0
    private var surface: NotchSurfaceView!
    private var transitionGeneration = 0
    private var lastTarget = NSRect.zero
    private var lastPresentation = IslandPresentation.ambient
    private var lastRadius: CGFloat = 0
    private(set) var transitionInFlight = false
    private(set) var hostingInstallCount = 0
    var pinnedOpen = false
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    init(model: AppModel, geometryOverride: NotchGeometry? = nil) {
        self.model = model
        self.geometryOverride = geometryOverride
        let screen = NexaDisplays.resolve(model.preferences.value.preferredDisplay)
        activeDisplayID = screen.map(NexaDisplays.identifier)
        geometry = geometryOverride ?? screen.map(NotchGeometry.init(screen:)) ?? NotchGeometry(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), hardwareWidth: 170, hardwareHeight: 0, menuBarHeight: 24)
        let panel = NotchPanel(contentRect: geometry.frame(expanded: false, banner: false, preferences: model.preferences.value), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        // Native glass resolves its material through the containing window.
        // Keep the charcoal surface readable when the system uses Light mode.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        // isFloatingPanel sets the level to .floating, so set our level last.
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false; panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none; panel.title = "Nexa Notch"
        installContent()
        model.setExpanded = { [weak self] in self?.expand($0) }
        model.setPresentation = { [weak self] in self?.present($0) }
        model.$selected.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout(animated: true) } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: panel).sink { [weak self] _ in
            guard let self else { return }
            self.model.islandVisible = self.window?.occlusionState.contains(.visible) == true
            self.model.refreshVisible()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] _ in self?.menuTracking += 1; self?.hoverWork?.cancel() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] _ in
            guard let self else { return }; self.menuTracking = max(0, self.menuTracking - 1)
            if self.menuTracking == 0, let window = self.window { self.hover(window.frame.contains(NSEvent.mouseLocation)) }
        }.store(in: &subscriptions)
        model.$banner.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout(animated: true) } }.store(in: &subscriptions)
        model.$dropTarget.removeDuplicates().sink { [weak self] target in
            guard let self else { return }
            self.surface.updateAppearance(expanded: self.model.expanded, hasNotch: self.geometry.hasNotch, preferences: self.model.preferences.value, dropTarget: target)
            if target && self.model.preferences.value.dragAndDrop {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.model.dropTarget else { return }
                    self.expand(true)
                    if self.model.preferences.value.enabledModules.contains(.files) { self.model.selected = .files }
                }
            }
        }.store(in: &subscriptions)
        model.preferences.$value.dropFirst().debounce(for: .milliseconds(40), scheduler: RunLoop.main).sink { [weak self] _ in self?.screenChanged() }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.screenChanged() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.window?.orderFrontRegardless() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.timers.tick(); self?.model.calendar.refresh(); self?.screenChanged() } }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.layout(animated: false) } }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .swipe]) { [weak self] event in
            guard let self, event.window === self.window, !self.model.preferences.recordingShortcut else { return event }
            if event.type == .swipe && self.model.preferences.value.swipeGestures {
                if abs(event.deltaY) > abs(event.deltaX) { self.expand(event.deltaY < 0) }
                else { self.cycleWorkspace(event.deltaX > 0 ? -1 : 1) }
                return nil
            }
            if event.type == .keyDown && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let character = event.charactersIgnoringModifiers, let number = Int(character), (1...7).contains(number) {
                let rail = WorkspaceLayout.rail(self.model.preferences.value)
                if rail.indices.contains(number - 1) { self.model.selected = rail[number - 1]; return nil }
            }
            if event.type == .keyDown && event.keyCode == 53 { self.expand(false); return nil }
            if event.type == .scrollWheel && self.model.preferences.value.scrollCyclesModules && Date().timeIntervalSince(self.lastScroll) > 0.4 && abs(event.scrollingDeltaY) > 2 {
                let modules = self.model.modules
                if let index = modules.firstIndex(of: self.model.selected), !modules.isEmpty { self.model.selected = modules[(index + (event.scrollingDeltaY < 0 ? 1 : modules.count - 1)) % modules.count] }
                self.lastScroll = Date(); return nil
            }
            return event
        }
        layout(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { window?.orderFrontRegardless(); if !transitionInFlight { layout(animated: false) } }
    func hover(_ inside: Bool) {
        hoverWork?.cancel()
        guard !model.paused else { return }
        if inside && (!model.preferences.value.hoverToOpen || model.expanded) { return }
        if !inside && (pinnedOpen || menuTracking > 0 || window?.attachedSheet != nil || model.mirror.starting) { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window, !self.model.paused else { return }
            // Tracking rectangles can change while the shell grows. Recheck the
            // pointer before acting on an exit caused by geometry rather than motion.
            guard window.frame.contains(self.pointerLocation()) == inside else { return }
            if !inside && (self.pinnedOpen || self.menuTracking > 0 || window.attachedSheet != nil || self.model.mirror.starting) { return }
            self.present(inside ? .peek : .ambient)
        }; hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? model.preferences.value.hoverDelay : model.preferences.value.collapseDelay), execute: work)
    }
    func expand(_ expanded: Bool) { present(expanded ? .workspace : .ambient) }
    func present(_ presentation: IslandPresentation) {
        hoverWork?.cancel(); guard !model.paused || presentation == .ambient else { return }
        guard presentation != model.presentation else { return }
        if presentation == .workspace && model.presentation == .ambient {
            model.selected = WorkspaceLayout.initialModule(model.preferences.value)
        }
        model.presentation = presentation
        model.expanded = presentation.isOpen
        if model.preferences.value.hapticFeedback { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if presentation == .ambient { window?.resignKey(); model.dropTarget = false }
        layout(animated: true); model.refreshVisible()
    }
    func cycleWorkspace(_ direction: Int) {
        let modules = WorkspaceLayout.rail(model.preferences.value)
        guard let index = modules.firstIndex(of: model.selected), !modules.isEmpty else { return }
        model.selected = modules[(index + direction + modules.count) % modules.count]
    }
    func layout(animated: Bool) {
        guard let window, let surface else { return }
        let config = model.preferences.value
        let behavior: NSWindow.CollectionBehavior = config.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
        let target = geometry.frame(presentation: model.presentation, banner: model.banner != nil && !model.paused, preferences: config)
        let changed = target != lastTarget || model.presentation != lastPresentation || config.cornerRadius != lastRadius
        guard changed || !animated else {
            surface.updateAppearance(expanded: model.expanded, hasNotch: geometry.hasNotch, preferences: config)
            if !transitionInFlight { window.hasShadow = config.shadow && (model.expanded || model.banner != nil || !geometry.hasNotch) }
            return
        }
        lastTarget = target; lastPresentation = model.presentation; lastRadius = config.cornerRadius
        transitionGeneration += 1; let generation = transitionGeneration
        let motion = NexaMotion(preferences: config, systemReduceMotion: reduceMotion())
        let duration = animated ? (model.expanded ? motion.expansionDuration : model.banner != nil ? motion.notificationDuration : motion.collapseDuration) : 0
        transitionInFlight = duration > 0
        let railExtent = WorkspaceLayout.railExtent(config, presentation: model.presentation)
        let bodySize = CGSize(width: target.width, height: max(1, target.height - railExtent))
        var requestedCanvas = surface.requiredCanvas(target: bodySize, expanded: model.expanded, hasNotch: geometry.hasNotch, preferences: config, duration: duration)
        requestedCanvas.height += railExtent
        let canvasSize = duration > 0 ? CGSize(width: max(window.frame.width, requestedCanvas.width), height: max(window.frame.height, requestedCanvas.height)) : target.size
        let canvas = NSRect(x: target.midX - canvasSize.width / 2, y: target.maxY - canvasSize.height, width: canvasSize.width, height: canvasSize.height)
        window.hasShadow = false
        if window.frame != canvas { window.setFrame(canvas, display: false) }
        let workspaceFrame = geometry.frame(presentation: .workspace, banner: false, preferences: config)
        let expandedSize = CGSize(width: workspaceFrame.width, height: workspaceFrame.height - WorkspaceLayout.railExtent(config, presentation: .workspace))
        let peekSize = geometry.frame(presentation: .peek, banner: false, preferences: config).size
        let compactSize = geometry.frame(expanded: false, banner: model.banner != nil && !model.paused, preferences: config).size
        surface.render(canvas: canvasSize, target: bodySize, expandedSize: expandedSize, compactSize: compactSize, peekSize: peekSize,
                       presentation: model.presentation, hasNotch: geometry.hasNotch, preferences: config, module: model.selected, duration: duration) { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            let currentConfig = self.model.preferences.value
            self.transitionInFlight = false
            self.surface.finish(presentation: self.model.presentation)
            self.surface.updateAppearance(expanded: self.model.expanded, hasNotch: self.geometry.hasNotch, preferences: currentConfig)
            if window.frame != target {
                window.setFrame(target, display: false)
                self.surface.render(canvas: target.size, target: bodySize, expandedSize: expandedSize, compactSize: compactSize, peekSize: peekSize,
                                    presentation: self.model.presentation, hasNotch: self.geometry.hasNotch, preferences: currentConfig, module: self.model.selected, duration: 0, completion: {})
            }
            window.hasShadow = currentConfig.shadow && (self.model.expanded || self.model.banner != nil || !self.geometry.hasNotch)
            window.invalidateShadow()
        }
    }
    func move(to screen: NSScreen, presentation: IslandPresentation) {
        displayOverrideID = NexaDisplays.identifier(screen); activeDisplayID = displayOverrideID
        if geometry != NotchGeometry(screen: screen) {
            geometry = NotchGeometry(screen: screen); installContent(); layout(animated: false)
        }
        present(presentation); show()
    }
    private func screenChanged() {
        guard let screen = NexaDisplays.resolve(displayOverrideID ?? model.preferences.value.preferredDisplay) else { return }
        activeDisplayID = NexaDisplays.identifier(screen)
        let updated = geometryOverride ?? NotchGeometry(screen: screen)
        if geometry != updated {
            geometry = updated; installContent(); layout(animated: false)
        } else { layout(animated: !(model.preferences.value.reduceMotion || reduceMotion())) }
    }
    private func installContent() {
        func root(_ presentation: IslandPresentation) -> NotchView {
            NotchView(model: model, preferences: model.preferences, hardwareHeight: geometry.hardwareHeight, hardwareWidth: geometry.hardwareWidth, hasNotch: geometry.hasNotch, presentation: presentation, toggle: { [weak self] in
                guard let self else { return }
                self.present(self.model.presentation == .workspace ? .ambient : .workspace)
            })
        }
        if let surface {
            surface.expandedHost.rootView = root(.workspace)
            surface.compactHost.rootView = root(.ambient)
            surface.peekHost.rootView = root(.peek)
            return
        }
        hostingInstallCount += 1
        surface = NotchSurfaceView(expanded: root(.workspace), compact: root(.ambient), peek: root(.peek), rail: WorkspaceRail(model: model, preferences: model.preferences))
        surface.onHover = { [weak self] in self?.hover($0) }
        window?.contentView = surface
    }
    deinit {
        hoverWork?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in [spaceObserver, wakeObserver, accessibilityObserver].compactMap({ $0 }) { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let localEvents { NSEvent.removeMonitor(localEvents) }
    }
}
