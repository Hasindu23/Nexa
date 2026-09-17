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
    private var lastExpanded = false
    private var lastModule = ModuleID.home
    private var lastRadius: CGFloat = 0
    private(set) var transitionInFlight = false
    private(set) var hostingInstallCount = 0
    var pinnedOpen = false
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    init(model: AppModel, geometryOverride: NotchGeometry? = nil) {
        self.model = model
        self.geometryOverride = geometryOverride
        let screen = NSScreen.screens.first(where: { $0.localizedName == model.preferences.value.preferredDisplay }) ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        geometry = geometryOverride ?? NotchGeometry(screen: screen)
        let panel = NotchPanel(contentRect: geometry.frame(expanded: false, banner: false, preferences: model.preferences.value), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        // isFloatingPanel sets the level to .floating, so set our level last.
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false; panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none; panel.title = "Nexa Notch"
        installContent()
        model.setExpanded = { [weak self] in self?.expand($0) }
        model.$selected.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout(animated: true) } }.store(in: &subscriptions)
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
                    if self.model.preferences.value.enabledModules.contains(.files) { self.model.selected = .files }
                    self.expand(true)
                }
            }
        }.store(in: &subscriptions)
        model.preferences.$value.dropFirst().debounce(for: .milliseconds(40), scheduler: RunLoop.main).sink { [weak self] _ in self?.screenChanged() }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.screenChanged() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.window?.orderFrontRegardless() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.timers.tick(); self?.model.calendar.refresh(); self?.screenChanged() } }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.layout(animated: false) } }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .swipe]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .swipe {
                if abs(event.deltaY) > abs(event.deltaX) { self.expand(event.deltaY < 0) }
                else if self.model.preferences.value.enabledModules.contains(.music) { self.model.media.command(event.deltaX > 0 ? "previous track" : "next track") }
                return nil
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
            self.expand(inside)
        }; hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? model.preferences.value.hoverDelay : model.preferences.value.collapseDelay), execute: work)
    }
    func expand(_ expanded: Bool) {
        hoverWork?.cancel(); guard !model.paused || !expanded else { return }
        guard expanded != model.expanded else { return }
        model.expanded = expanded
        if model.preferences.value.hapticFeedback { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if !expanded { window?.resignKey(); model.dropTarget = false }
        layout(animated: true); model.refreshVisible()
    }
    func layout(animated: Bool) {
        guard let window, let surface else { return }
        let config = model.preferences.value
        let behavior: NSWindow.CollectionBehavior = config.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
        let target = geometry.frame(expanded: model.expanded, banner: model.banner != nil && !model.paused, preferences: config, home: model.selected == .home)
        let changed = target != lastTarget || model.expanded != lastExpanded || model.selected != lastModule || config.cornerRadius != lastRadius
        guard changed || !animated else {
            surface.updateAppearance(expanded: model.expanded, hasNotch: geometry.hasNotch, preferences: config)
            if !transitionInFlight { window.hasShadow = config.shadow && (model.expanded || model.banner != nil || !geometry.hasNotch) }
            return
        }
        lastTarget = target; lastExpanded = model.expanded; lastModule = model.selected; lastRadius = config.cornerRadius
        transitionGeneration += 1; let generation = transitionGeneration
        let duration = animated && !reduceMotion() ? (model.expanded ? 0.34 : 0.28) / max(0.5, min(2, config.animationSpeed)) : 0
        transitionInFlight = duration > 0
        let canvasSize = duration > 0 ? CGSize(width: max(window.frame.width, target.width), height: max(window.frame.height, target.height)) : target.size
        let canvas = NSRect(x: target.midX - canvasSize.width / 2, y: target.maxY - canvasSize.height, width: canvasSize.width, height: canvasSize.height)
        window.hasShadow = false
        if window.frame != canvas { window.setFrame(canvas, display: false) }
        let expandedSize = geometry.frame(expanded: true, banner: false, preferences: config, home: model.selected == .home).size
        let compactSize = geometry.frame(expanded: false, banner: model.banner != nil && !model.paused, preferences: config).size
        surface.render(canvas: canvasSize, target: target.size, expandedSize: expandedSize, compactSize: compactSize,
                       expanded: model.expanded, hasNotch: geometry.hasNotch, preferences: config, module: model.selected, duration: duration) { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            let currentConfig = self.model.preferences.value
            self.transitionInFlight = false
            self.surface.finish(expanded: self.model.expanded)
            if window.frame != target {
                window.setFrame(target, display: false)
                self.surface.render(canvas: target.size, target: target.size, expandedSize: expandedSize, compactSize: compactSize,
                                    expanded: self.model.expanded, hasNotch: self.geometry.hasNotch, preferences: currentConfig, module: self.model.selected, duration: 0, completion: {})
            }
            window.hasShadow = currentConfig.shadow && (self.model.expanded || self.model.banner != nil || !self.geometry.hasNotch)
            window.invalidateShadow()
        }
    }
    private func screenChanged() {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == model.preferences.value.preferredDisplay }) ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let updated = geometryOverride ?? NotchGeometry(screen: screen)
        if geometry != updated {
            geometry = updated; installContent(); layout(animated: false)
        } else { layout(animated: true) }
    }
    private func installContent() {
        hostingInstallCount += 1
        func root(expanded: Bool) -> NotchView {
            NotchView(model: model, preferences: model.preferences, hardwareHeight: geometry.hardwareHeight, hardwareWidth: geometry.hardwareWidth, hasNotch: geometry.hasNotch, expandedPresentation: expanded, toggle: { [weak self] in self?.expand(!(self?.model.expanded ?? false)) })
        }
        surface = NotchSurfaceView(expanded: root(expanded: true), compact: root(expanded: false))
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
