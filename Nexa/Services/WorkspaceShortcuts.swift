import AppKit
import SwiftUI
import Carbon
import Combine

enum WorkspaceAction: String, Codable, CaseIterable, Identifiable {
    case open, close, toggle, music, calendar, files, tasks, ai, clipboard, quickCapture
    var id: String { rawValue }
    var title: String {
        switch self { case .open: return "Open Nexa"; case .close: return "Close Nexa"; case .toggle: return "Toggle Nexa"; case .quickCapture: return "Quick Capture"; default: return rawValue.capitalized }
    }
    var module: ModuleID? {
        switch self { case .music: return .music; case .calendar: return .calendar; case .files: return .files; case .tasks: return .todos; case .ai: return .ai; case .clipboard: return .clipboard; case .quickCapture: return .notes; default: return nil }
    }
}
struct WorkspaceShortcut: Codable, Equatable {
    var action: WorkspaceAction
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    var valid: Bool { keyCode <= 127 && modifiers & UInt32(cmdKey) != 0 && modifiers & UInt32(optionKey | controlKey) != 0 }
}

private func nexaHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == 0x4E585332 else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<WorkspaceShortcutManager>.fromOpaque(context).takeUnretainedValue()
    let value = id.id
    Task { @MainActor [weak manager] in manager?.invoke(value) }
    return noErr
}

@MainActor final class WorkspaceShortcutManager: ObservableObject {
    @Published private(set) var failures: [WorkspaceAction: String] = [:]
    private unowned let model: AppModel
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var subscriptions = Set<AnyCancellable>()
    init(model: AppModel) {
        self.model = model
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), nexaHotKeyHandler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        model.preferences.$value.map(\.workspaceShortcuts).removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        model.preferences.$recordingShortcut.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
    }
    private func configure() {
        registrations.forEach { UnregisterEventHotKey($0) }; registrations.removeAll(); failures.removeAll()
        guard !model.preferences.recordingShortcut else { return }
        for binding in model.preferences.value.workspaceShortcuts {
            guard binding.valid, let index = WorkspaceAction.allCases.firstIndex(of: binding.action) else { failures[binding.action] = "Use Command with Option or Control."; continue }
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x4E585332, id: UInt32(index)), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { registrations.append(ref) }
            else { failures[binding.action] = "This shortcut is unavailable. Choose another combination." }
        }
    }
    func invoke(_ id: UInt32) {
        guard WorkspaceAction.allCases.indices.contains(Int(id)) else { return }
        let action = WorkspaceAction.allCases[Int(id)]
        if action == .close { model.setPresentation?(.ambient); return }
        if action == .toggle { model.setPresentation?(model.presentation == .ambient ? .workspace : .ambient); return }
        guard !model.paused else { return }
        if let module = action.module {
            guard model.preferences.value.enabledModules.contains(module) else { return }
            model.setPresentation?(.workspace); model.selected = module
            if action == .quickCapture { model.notebook.addNote() }
        } else { model.setPresentation?(.workspace) }
    }
    func stop() { registrations.forEach { UnregisterEventHotKey($0) }; registrations.removeAll(); if let handler { RemoveEventHandler(handler) }; handler = nil }
    deinit { registrations.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
}

struct ShortcutRecorder: NSViewRepresentable {
    var label: String
    var changed: (UInt32, UInt32, String) -> Void
    var recording: (Bool) -> Void
    func makeNSView(context: Context) -> ShortcutRecordButton { let button = ShortcutRecordButton(); button.bezelStyle = .rounded; return button }
    func updateNSView(_ button: ShortcutRecordButton, context: Context) { button.savedLabel = label; if !button.recording { button.title = label }; button.changed = changed; button.onRecording = recording }
}
final class ShortcutRecordButton: NSButton {
    var savedLabel = "Record…"
    var recording = false
    var changed: ((UInt32, UInt32, String) -> Void)?
    var onRecording: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { recording = true; title = "Press shortcut…"; onRecording?(true); window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let flags = event.modifierFlags
        guard flags.contains(.command), flags.contains(.option) || flags.contains(.control) else { title = "Use ⌘ with ⌥ or ⌃"; return }
        var modifiers = UInt32(cmdKey)
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let label = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + "⌘" + (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        changed?(UInt32(event.keyCode), modifiers, label); savedLabel = label; finish()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event) }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    private func finish() { recording = false; title = savedLabel; onRecording?(false) }
}
