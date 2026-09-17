import SwiftUI

@MainActor final class ShortcutsService: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var favorites: [String]
    @Published private(set) var running: String?
    @Published var error: String?
    private let store: LocalStore
    private var listing = false
    private var process: Process?
    init(store: LocalStore) { self.store = store; favorites = store.read([String].self, name: "shortcuts.json") ?? [] }
    func refresh() {
        guard !listing else { return }; listing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process(), pipe = Pipe(); task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); task.arguments = ["list"]; task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) { if task.isRunning { task.terminate() } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
                let names = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
                Task { @MainActor in self?.names = names; self?.listing = false; if task.terminationStatus != 0 { self?.error = "Open Shortcuts once, then refresh your shortcuts." } }
            } catch { Task { @MainActor in self?.listing = false; self?.error = error.localizedDescription } }
        }
    }
    func pin(_ name: String) { if favorites.contains(name) { favorites.removeAll { $0 == name } } else { favorites.append(name) }; do { try store.write(favorites, name: "shortcuts.json") } catch { self.error = error.localizedDescription } }
    func run(_ name: String) {
        guard running == nil else { return }
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); task.arguments = ["run", name]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] task in Task { @MainActor in self?.running = nil; self?.process = nil; if task.terminationStatus != 0 { self?.error = "The shortcut stopped or needs attention in Shortcuts." } } }
        do { try task.run(); process = task; running = name; error = nil } catch { self.error = error.localizedDescription }
    }
    func cancel() { process?.terminate(); process = nil; running = nil }
}

struct ShortcutsView: View {
    @ObservedObject var service: ShortcutsService
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Your shortcuts, close by.").font(.system(size: 21, weight: .medium)); Spacer(); IconButton(symbol: "arrow.clockwise", help: "Refresh shortcuts") { service.refresh() }; Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }.font(.system(size: 11)) }
            Text("Star shortcuts to show them on Home. They run only when you click them.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
            if service.names.isEmpty { EmptyModule(icon: "command", title: "Your next small shortcut", detail: "Create a shortcut in the Shortcuts app, then refresh.") }
            ForEach(service.names, id: \.self) { name in
                HStack { Image(systemName: "command").foregroundStyle(accent); Text(name).font(.system(size: 12)); Spacer(); Button { service.pin(name) } label: { Image(systemName: service.favorites.contains(name) ? "star.fill" : "star") }.buttonStyle(.plain).help("Show on Home"); Button(service.running == name ? "Running…" : "Run") { service.run(name) }.disabled(service.running != nil) }.padding(12).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if service.running != nil { Button("Stop shortcut") { service.cancel() } }
            InlineError(text: service.error)
        }.onAppear { service.refresh() }
    }
}
