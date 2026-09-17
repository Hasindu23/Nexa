import AppKit
import SwiftUI
import Combine

@main enum NexaMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var model: AppModel!
    var notch: NotchWindowController!
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        if let index = CommandLine.arguments.firstIndex(of: "--qa-motion"), CommandLine.arguments.count > index + 1 {
            runMotionQA(output: URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--qa-live-media"), CommandLine.arguments.count > index + 1 {
            runLiveMediaQA(output: URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--qa-output"), CommandLine.arguments.count > index + 1 {
            runQA(output: URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        // Launching another mounted copy must not add a second notch overlay.
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.nexa.mac").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            existing.activate(); NSApp.terminate(nil); return
        }
        model = AppModel(); setup()
        if !model.preferences.value.completedOnboarding { showOnboarding() }
        else if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--expanded") {
            // Give the initially hidden SwiftUI hosts their first display pass.
            // Opening in the launch callback can leave unchanged subviews blank.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.notch.expand(true) }
        }
    }
    func setup() {
        let simulatedDisplay = model.testing && CommandLine.arguments.contains("--qa-no-notch") ? NSScreen.main.map { NotchGeometry(frame: $0.frame, hardwareWidth: 170, hardwareHeight: 0) } : nil
        notch = NotchWindowController(model: model, geometryOverride: simulatedDisplay); notch.show()
        model.showSettings = { [weak self] in self?.showSettings() }
        model.showOnboarding = { [weak self] in self?.showOnboarding() }
        configureStatusItem()
        model.preferences.$value.map(\.showMenuBar).removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.configureStatusItem() } }.store(in: &subscriptions)
        buildMainMenu()
    }
    func configureStatusItem() {
        guard model.preferences.value.showMenuBar else { if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }; statusItem = nil; return }
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem?.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Nexa")
        let menu = NSMenu(); menu.delegate = self; statusItem?.menu = menu; rebuildMenu(menu)
    }
    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(menu) }
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Open Nexa", action: #selector(openNotch), key: "", menu: menu)
        add(model.paused ? "Resume Nexa" : "Pause Nexa", action: #selector(pause), key: "", menu: menu)
        let awake = add("Keep Awake", action: #selector(keepAwake), key: "", menu: menu); awake.state = model.controls.awake ? .on : .off
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",", menu: menu)
        add("Quit Nexa", action: #selector(quit), key: "q", menu: menu)
    }
    @discardableResult private func add(_ title: String, action: Selector, key: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    private func buildMainMenu() {
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu; menu.addItem(appItem)
        add("Settings…", action: #selector(showSettings), key: ",", menu: appMenu); appMenu.addItem(.separator()); add("Quit Nexa", action: #selector(quit), key: "q", menu: appMenu)
        let edit = NSMenuItem(); edit.title = "Edit"; let submenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { submenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        edit.submenu = submenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
    @objc func openNotch() { if model.paused { model.togglePause() }; notch.show(); notch.expand(true) }
    @objc func pause() { model.togglePause() }
    @objc func keepAwake() { model.controls.toggleAwake() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Nexa Settings", width: 860, height: 720)
            settingsWindow?.minSize = NSSize(width: 820, height: 610)
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(model: model, preferences: model.preferences))
            if !model.testing { settingsWindow?.setFrameAutosaveName("Nexa.Settings") }
        }
        model.controls.refresh(); settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: "Welcome to Nexa", width: 600, height: 630, resizable: false)
            onboardingWindow?.contentView = NSHostingView(rootView: OnboardingView(model: model, preferences: model.preferences, finish: { [weak self] in
                guard let self else { return }; self.model.preferences.value.completedOnboarding = true; self.onboardingWindow?.close(); self.onboardingWindow = nil; self.notch.expand(true)
            }))
        }
        onboardingWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func makeWindow(title: String, width: CGFloat, height: CGFloat, resizable: Bool = true) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: resizable ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.backgroundColor = NSColor(NexaStyle.canvas); window.center(); return window
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}
