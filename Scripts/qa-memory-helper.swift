// Isolated visible helper for the memory-quit smoke test. Never distributed in the app.
import AppKit
final class MemoryQADelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let bytes = Data(repeating: 37, count: 64_000_000)
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Nexa Memory QA Helper"
        window.contentView = NSTextField(labelWithString: "Generated test app. No documents or personal data.")
        window.makeKeyAndOrderFront(nil); self.window = window
    }
}
let app = NSApplication.shared
let delegate = MemoryQADelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
withExtendedLifetime(delegate) {}
