import SwiftUI
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var service: FileShelfService
    let dropTarget: Bool
    let accent: Color
    @State private var selected = Set<UUID>()
    @State private var preview: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Between here and there.").font(.system(size: 22, weight: .medium)).tracking(-0.6); Text("A resting place for the things you’re moving.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary) }
                Spacer()
                IconButton(symbol: "doc.on.clipboard", help: "Paste files into Tray") { service.pasteFiles() }
                IconButton(symbol: "plus", help: "Add files") { pickFiles() }
            }
            if service.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(accent)
                    Text(dropTarget ? "Let go. It’s here." : "Drop something here").font(.system(size: 14, weight: .medium))
                    Text("Files, images, folders. Always the original.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
                }.frame(maxWidth: .infinity).frame(height: 155).background(accent.opacity(dropTarget ? 0.1 : 0.025), in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(accent.opacity(dropTarget ? 0.7 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 5])))
            } else {
                ForEach(service.items) { item in
                    HStack(spacing: 10) {
                        Button { if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) } } label: { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(item.id) ? accent : .gray) }.buttonStyle(.plain).help("Select file")
                        FileThumbnail(url: item.resolvedURL).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.resolvedURL.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(FileManager.default.fileExists(atPath: item.resolvedURL.path) ? item.addedAt.formatted(date: .omitted, time: .shortened) : "Original moved or unavailable").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
                        }
                        Spacer()
                        IconButton(symbol: "eye", help: "Quick Look", size: 27) { preview = item.resolvedURL }
                        ShareLink(item: item.resolvedURL) { Image(systemName: "square.and.arrow.up").font(.system(size: 12)).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Share with AirDrop, Messages or Mail")
                        IconButton(symbol: "folder", help: "Reveal in Finder", size: 27) { service.reveal(item) }
                        IconButton(symbol: "xmark", help: "Remove from shelf", size: 24) { service.remove(item) }
                    }.padding(10).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .onDrag { NSItemProvider(object: item.resolvedURL as NSURL) }
                        .contextMenu { Button("Quick Look") { preview = item.resolvedURL }; Button("AirDrop") { service.airDrop([item.resolvedURL]) }; Button("Reveal in Finder") { service.reveal(item) }; Button("Remove from Shelf") { service.remove(item) } }
                }
            }
            HStack {
                Button { let urls = service.items.filter { selected.isEmpty || selected.contains($0.id) }.map(\.resolvedURL); service.airDrop(urls) } label: { Label(selected.isEmpty ? "AirDrop all" : "AirDrop \(selected.count)", systemImage: "airdrop") }.disabled(service.items.isEmpty)
                if !selected.isEmpty { Button("Copy selected") { service.copyFiles(service.items.filter { selected.contains($0.id) }.map(\.resolvedURL)) }; Button("Clear selection") { selected.removeAll() } }
                Spacer()
                Text("Drop here to AirDrop").foregroundStyle(NexaStyle.secondary)
            }.font(.system(size: 10)).padding(12).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [.fileURL, .url, .utf8PlainText], isTargeted: nil) { providers in service.acceptAirDrop(providers); return true }
            InlineError(text: service.error)
        }.sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let url = preview {
                VStack(spacing: 0) {
                    HStack { Text(url.lastPathComponent).font(.headline); Spacer(); Button("Done") { preview = nil }.keyboardShortcut(.cancelAction) }.padding(16)
                    FileQuickLook(url: url).frame(width: 620, height: 420)
                }
            }
        }
            .onChange(of: service.items) { _, items in selected.formIntersection(Set(items.map(\.id))) }
    }
    private func pickFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        panel.begin { result in if result == .OK { service.add(panel.urls) } }
    }
}

private struct FileQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = true; view.previewItem = url as NSURL; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

struct FileThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .all)
                if let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail = result.nsImage }
            }
    }
}
