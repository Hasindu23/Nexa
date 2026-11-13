import AppKit
import SwiftUI
import Combine

/// One persistent workspace, with lightweight entry points on selected displays.
@MainActor final class DisplayEntryCoordinator {
    let model: AppModel
    let primary: NotchWindowController
    private var entries: [String: NSPanel] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var dragMonitor: Any?
    private var localDragMonitor: Any?
    private var lastDrag = -1
    init(model: AppModel, primary: NotchWindowController) {
        self.model = model; self.primary = primary
        model.preferences.$value.map { [$0.preferredDisplay] + $0.enabledDisplayIDs }.removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.dragged() }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in self?.dragged(); return event }
        update()
    }
    private var selectedScreens: [NSScreen] {
        let selected = NSScreen.screens.filter { screen in model.preferences.value.enabledDisplayIDs.contains(where: { NexaDisplays.matches(screen, preference: $0) }) }
        return selected.isEmpty ? [NexaDisplays.resolve(model.preferences.value.preferredDisplay)].compactMap { $0 } : selected
    }
    func update() {
        let screens = selectedScreens
        let selected = Set(screens.map(NexaDisplays.identifier))
        if !selected.contains(primary.activeDisplayID ?? ""), let screen = screens.first { primary.move(to: screen, presentation: model.presentation) }
        for id in Array(entries.keys) where !selected.contains(id) { entries.removeValue(forKey: id)?.close() }
        for screen in screens {
            let id = NexaDisplays.identifier(screen), geometry = NotchGeometry(screen: screen)
            if entries[id] == nil {
                let panel = NotchPanel(contentRect: geometry.frame(expanded: false, banner: false, preferences: model.preferences.value), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.isReleasedWhenClosed = false
                panel.hidesOnDeactivate = false; panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                let view = NSHostingView(rootView: DisplayEntryView(preferences: model.preferences, geometry: geometry) { [weak self, weak screen] state in
                    guard let self, let screen, !self.model.paused else { return }
                    self.primary.move(to: screen, presentation: state); self.update()
                })
                view.safeAreaRegions = []; view.sizingOptions = []; panel.contentView = view; entries[id] = panel
            }
            entries[id]?.setFrame(geometry.frame(expanded: false, banner: false, preferences: model.preferences.value), display: true)
            if id == primary.activeDisplayID { entries[id]?.orderOut(nil) } else { entries[id]?.orderFrontRegardless() }
        }
    }
    private func dragged() {
        guard model.preferences.value.dragAndDrop, !model.paused else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != lastDrag, board.types?.contains(.fileURL) == true else { return }
        let point = NSEvent.mouseLocation
        guard let screen = selectedScreens.first(where: { DragActivation.contains(point, geometry: NotchGeometry(screen: $0)) }) else { return }
        lastDrag = board.changeCount
        primary.move(to: screen, presentation: .workspace)
        if model.preferences.value.enabledModules.contains(.files) { model.selected = .files }
        update()
    }
    func stop() { entries.values.forEach { $0.close() }; entries.removeAll(); if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }; if let localDragMonitor { NSEvent.removeMonitor(localDragMonitor) }; dragMonitor = nil; localDragMonitor = nil }
    deinit { if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }; if let localDragMonitor { NSEvent.removeMonitor(localDragMonitor) } }
}

enum DragActivation {
    static func contains(_ point: NSPoint, geometry: NotchGeometry) -> Bool {
        let top = geometry.screenFrame.maxY - (geometry.hasNotch ? 0 : geometry.detachedTopInset)
        return abs(point.x - geometry.hardwareCenterX) <= max(160, geometry.hardwareWidth / 2 + 80)
            && point.y <= geometry.screenFrame.maxY && point.y >= top - 100
    }
}

private struct DisplayEntryView: View {
    @ObservedObject var preferences: PreferencesStore
    let geometry: NotchGeometry
    var activate: (IslandPresentation) -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(preferences.value.accent.color)
            if geometry.hasNotch { Color.clear.frame(width: geometry.hardwareWidth) }
            else { Text("nexa").font(.system(size: 11, weight: .semibold, design: .rounded)); Spacer() }
            Circle().fill(preferences.value.accent.color).frame(width: 4, height: 4)
        }.padding(.horizontal, 10).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black).clipShape(NotchSilhouette(radius: 14, shoulder: 0, detached: !geometry.hasNotch))
            .contentShape(Rectangle()).onTapGesture { if preferences.value.clickToOpen { activate(.workspace) } }
            .onHover { inside in if inside && preferences.value.hoverToOpen { activate(.peek) } }
            .accessibilityLabel("Open Nexa on this display").accessibilityAddTraits(.isButton)
    }
}
