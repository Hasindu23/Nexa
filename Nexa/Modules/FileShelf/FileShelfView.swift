import SwiftUI
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var service: FileShelfService
    @ObservedObject var exporter: ImageExportService
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
                if !service.items.isEmpty { Button("Clear Pocket") { service.clear() }.font(.caption) }
                IconButton(symbol: "plus", help: "Add files") { pickFiles() }
            }
            if service.importing { Label("Preparing file references…", systemImage: "tray.and.arrow.down").font(.caption).foregroundStyle(accent) }
            if service.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(accent)
                    Text(dropTarget ? "Let go. It’s here." : "Drop something here").font(.system(size: 14, weight: .medium))
                    Text("Pocket holds references to your originals. No duplicate files.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
                }.frame(maxWidth: .infinity).frame(height: 155).background(accent.opacity(dropTarget ? 0.1 : 0.025), in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(accent.opacity(dropTarget ? 0.7 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 5])))
            } else {
                ForEach(service.items) { item in
                    HStack(spacing: 10) {
                        Button { if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) } } label: { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(item.id) ? accent : .gray) }.buttonStyle(.plain).help("Select file")
                        FileThumbnail(url: service.displayURL(item)).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.displayURL(item).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(service.availability[item.id] == false ? "Original moved or unavailable" : service.details[item.id] ?? "Checking metadata…").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
                        }
                        Spacer()
                        if let type = UTType(filenameExtension: service.displayURL(item).pathExtension), type.conforms(to: .image) {
                            Menu { Button("Export PNG…") { exporter.chooseOutput(for: service.displayURL(item), type: .png) }; Button("Export JPEG…") { exporter.chooseOutput(for: service.displayURL(item), type: .jpeg) } } label: { Image(systemName: "arrow.triangle.2.circlepath") }.menuStyle(.borderlessButton).fixedSize().help("Export a new image").disabled(exporter.busy)
                        }
                        IconButton(symbol: "eye", help: "Quick Look", size: 27) { preview = service.displayURL(item) }
                        ShareLink(item: service.displayURL(item)) { Image(systemName: "square.and.arrow.up").font(.system(size: 12)).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Share with AirDrop, Messages or Mail")
                        IconButton(symbol: "folder", help: "Reveal in Finder", size: 27) { service.reveal(item) }
                        IconButton(symbol: "xmark", help: "Remove from shelf", size: 24) { service.remove(item) }
                    }.padding(10).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .onDrag { NSItemProvider(object: service.displayURL(item) as NSURL) }
                        .contextMenu { Button("Quick Look") { preview = service.displayURL(item) }; Button("AirDrop") { service.airDrop([service.displayURL(item)]) }; Button("Reveal in Finder") { service.reveal(item) }; Button("Remove from Shelf") { service.remove(item) } }
                }
            }
            HStack {
                Button { let urls = service.items.filter { selected.isEmpty || selected.contains($0.id) }.map { service.displayURL($0) }; service.airDrop(urls) } label: { Label(selected.isEmpty ? "AirDrop all" : "AirDrop \(selected.count)", systemImage: "square.and.arrow.up") }.disabled(service.items.isEmpty)
                if !selected.isEmpty { Button("Copy selected") { service.copyFiles(service.items.filter { selected.contains($0.id) }.map { service.displayURL($0) }) }; Button("Clear selection") { selected.removeAll() } }
                Spacer()
                Text("Drop here to AirDrop").foregroundStyle(NexaStyle.secondary)
            }.font(.system(size: 10)).padding(12).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [.fileURL, .url, .utf8PlainText], isTargeted: nil) { providers in service.acceptAirDrop(providers); return true }
            Text("Pocket keeps file references for the shelf duration in Settings. Clearing it never deletes your originals. PNG/JPEG export saves a new image; JPEG uses a white background for transparency.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            if exporter.busy { HStack { ProgressView().controlSize(.small); Text("Exporting image…"); Button("Cancel") { exporter.cancel() } }.font(.caption) }
            if let result = exporter.result { Button("Reveal exported image") { NSWorkspace.shared.activateFileViewerSelecting([result]) }.font(.caption) }
            InlineError(text: exporter.error)
            InlineError(text: service.error)
        }.onAppear { service.refreshMetadata() }.sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
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
        Group {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else { Image(systemName: "doc").resizable().scaledToFit().padding(5).foregroundStyle(.secondary) }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .all)
                if let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request), !Task.isCancelled { thumbnail = result.nsImage }
            }
    }
}
