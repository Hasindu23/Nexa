import SwiftUI

struct ClipboardView: View {
    @ObservedObject var service: ClipboardService
    @ObservedObject var preferences: PreferencesStore
    @State private var query = ""
    @State private var confirmClear = false
    private var filtered: [ClipItem] { service.items.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pick up where you copied.").font(.system(size: 20, weight: .medium)).tracking(-0.5)
                Spacer()
                if preferences.value.clipboardEnabled { IconButton(symbol: service.paused ? "play" : "pause", help: service.paused ? "Resume capture" : "Privacy pause") { service.paused.toggle() } }
                IconButton(symbol: "trash", help: "Clear history") { confirmClear = true }
            }
            if !preferences.value.clipboardEnabled {
                EmptyModule(icon: "lock.doc", title: "Your clipboard stays yours.", detail: "Capture is off. Turn it on to save text, links, images and file paths locally on this Mac.")
                Button("Enable clipboard history") { preferences.value.clipboardEnabled = true }.buttonStyle(CapsuleButtonStyle(accent: preferences.value.accent.color, filled: true)).frame(maxWidth: .infinity)
            } else {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(NexaStyle.secondary); TextField("Find something you copied", text: $query).textFieldStyle(.plain); if service.paused { Text("PAUSED").font(.system(size: 8, weight: .semibold)).foregroundStyle(.orange) } }.font(.system(size: 12)).padding(11).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                if filtered.isEmpty { Text(query.isEmpty ? "Your next copy will appear here." : "No matching clips.").font(.system(size: 12)).foregroundStyle(NexaStyle.secondary).padding(.vertical, 22) }
                ForEach(filtered) { item in
                    HStack(spacing: 10) {
                        if let data = item.data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32) }
                        else { Image(systemName: item.kind == .url ? "link" : item.kind == .files ? "doc" : "text.alignleft").foregroundStyle(preferences.value.accent.color).frame(width: 24) }
                        Button { service.copy(item) } label: { Text(item.title).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).help("Copy again")
                        IconButton(symbol: item.pinned ? "pin.fill" : "pin", help: item.pinned ? "Unpin" : "Pin", size: 25) { service.pin(item) }
                        IconButton(symbol: "xmark", help: "Delete clip", size: 25) { service.delete(item) }
                    }.padding(10).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            InlineError(text: service.error)
        }.confirmationDialog("Clear all clipboard history, including pinned items?", isPresented: $confirmClear) { Button("Clear History", role: .destructive) { service.clear() }; Button("Cancel", role: .cancel) {} }
    }
}
