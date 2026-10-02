import SwiftUI
import AppKit

private let diskColors: [Color] = [.blue, .cyan, .indigo, .mint, .purple, .orange, .teal, .pink]

struct DiskExplorerView: View {
    @ObservedObject var explorer: DiskExplorerService
    @ObservedObject var storage: StorageService
    @State private var search = ""
    @State private var hiddenOnly = false
    @State private var largestFiles = false
    @State private var minimumMB = "0"
    private var contents: [DiskEntry] {
        guard let result = explorer.result, let folder = explorer.folder else { return [] }
        let items = largestFiles
            ? result.fileOrder.compactMap { result.entries[$0] }.filter { StoragePathPolicy.contains(folder.path, $0.path) }
            : result.contents(of: folder.path)
        let minimum = max(0, Double(minimumMB) ?? 0) * 1_000_000
        return items.filter {
            (!hiddenOnly || $0.hidden) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && Double($0.allocated) >= minimum
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("See what’s taking space.").font(.system(size: 28, weight: .semibold))
                    Text("Explore your SSD, including the folders Finder usually hides.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Label("INSPECT FIRST", systemImage: "eye").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.cyan).padding(10).background(.cyan.opacity(0.09), in: Capsule())
            }
            HStack(spacing: 10) {
                Button("Analyze Home") { explorer.start(explorer.home) }.buttonStyle(CapsuleButtonStyle(accent: .blue, filled: true))
                Button("Analyze startup data") { explorer.start(URL(fileURLWithPath: "/System/Volumes/Data")) }.buttonStyle(CapsuleButtonStyle())
                Button("Choose folder or drive…") { explorer.chooseFolder() }.buttonStyle(CapsuleButtonStyle())
                Spacer()
            }.disabled(explorer.busy || storage.busy)
            if explorer.busy {
                HStack { ProgressView().controlSize(.small); Text(explorer.status).font(.caption); Spacer(); Button("Cancel analysis") { explorer.cancel() } }
            } else { HStack { Text(explorer.status); Spacer(); if let result = explorer.result { Text(result.date.formatted(date: .abbreviated, time: .shortened)) } }.font(.caption).foregroundStyle(.secondary) }
            if let error = explorer.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let result = explorer.result, let folder = explorer.folder {
                if result.limited {
                    Label("Scan limit reached · these are partial totals. Open a smaller folder and choose Analyze this folder for a fresh measurement.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                capacity(result)
                breadcrumbs(result, folder)
                folderMap(result, folder)
                if folder.skipped > 0 || result.limited {
                    Label("Partial measurement · \(folder.skipped.formatted()) skipped or shared entries. Permission restrictions, links, cloud placeholders and scan limits are shown in the list.", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                selectionCard(folder)
                fileList
            } else if !explorer.busy {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Find the space you don’t usually see", systemImage: "internaldrive").font(.headline)
                        Text("Home includes Library, application support, developer tools and dot folders. Startup data also inspects system-owned data and other user folders that macOS permits you to read. Choose a drive to inspect external storage.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        Text("Deep analysis runs only when you request it. Results remain in memory. File contents are never read or uploaded.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }
            snapshotCard
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Hidden doesn’t mean disposable", systemImage: "lock.shield").font(.headline)
                    Text("App support may hold your documents or databases. iPhone backups, virtual machines, photos, model files and system data need their own review. The explorer never deletes folders. Recognized caches open a separate scan with the existing review and confirmation steps.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    HStack {
                        Button("Review app caches") { storage.reviewFromExplorer(.caches) }.disabled(storage.busy || explorer.busy)
                        Button("Review developer data") { storage.reviewFromExplorer(.developer) }.disabled(storage.busy || explorer.busy)
                        Spacer()
                        Link("macOS storage settings ↗", destination: URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
                    }.font(.caption)
                }.padding(5)
            }
        }
        .onChange(of: explorer.current) { _, _ in search = ""; hiddenOnly = false }
    }
    private func capacity(_ result: DiskAnalysis) -> some View {
        HStack(spacing: 12) {
            metric("Volume used", storageBytes(max(0, result.total - result.free)), "Capacity reported by macOS")
            metric("Files measured", storageBytes(result.measured.allocated), "Allocated estimate in this scan")
            metric("Volume free", storageBytes(result.free), "Available filesystem space")
        }
    }
    private func metric(_ title: String, _ amount: String, _ caption: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(amount).font(.system(size: 22, weight: .semibold, design: .rounded)); Text(caption).font(.system(size: 10)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func breadcrumbs(_ result: DiskAnalysis, _ folder: DiskEntry) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(result.breadcrumbs(to: folder.path)) { node in
                    Button(node.path == result.root ? "Scan root" : node.name) { explorer.navigate(node.path) }.buttonStyle(.plain).foregroundStyle(node.path == folder.path ? .white : .cyan)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }.font(.system(size: 12, weight: .medium))
        }
    }
    private func folderMap(_ result: DiskAnalysis, _ folder: DiskEntry) -> some View {
        let children = result.contents(of: folder.path).filter { $0.allocated > 0 }
        let top = Array(children.prefix(8))
        let total = max(1, folder.allocated)
        return Surface {
            HStack(spacing: 25) {
                ZStack {
                    Circle().stroke(.white.opacity(0.06), lineWidth: 42).padding(21)
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, item in
                        let start = Double(top.prefix(index).reduce(Int64(0)) { $0 + $1.allocated }) / Double(total)
                        let end = start + Double(item.allocated) / Double(total)
                        DiskWedge(start: start, end: end).fill(diskColors[index % diskColors.count])
                            .contentShape(DiskWedge(start: start, end: end))
                            .onTapGesture { open(item) }.help("\(item.name) · \(storageBytes(item.allocated))")
                            .accessibilityLabel("\(item.name), \(storageBytes(item.allocated))").accessibilityAddTraits(.isButton)
                    }
                    VStack(spacing: 6) {
                        Text(storageBytes(folder.allocated)).font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text(folder.path == result.root ? "Selected location" : folder.name).font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 135)
                        Text("ALLOCATED ESTIMATE").font(.system(size: 7, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    }
                }.frame(width: 240, height: 240).padding(10)
                VStack(alignment: .leading, spacing: 13) {
                    Text("Click a folder to explore").font(.system(size: 15, weight: .semibold))
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, entry in
                        Button { open(entry) } label: {
                            HStack(spacing: 9) {
                                Circle().fill(diskColors[index % diskColors.count]).frame(width: 7, height: 7)
                                Text(entry.name).lineLimit(1).truncationMode(.middle)
                                if entry.hidden { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
                                Spacer()
                                Text(storageBytes(entry.allocated)).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: entry.directory ? "chevron.right" : "doc").font(.system(size: 9))
                            }.font(.system(size: 11))
                        }.buttonStyle(.plain)
                    }
                    if children.count > top.count { Text("Other entries: \(storageBytes(folder.allocated - top.reduce(0) { $0 + $1.allocated }))").font(.caption).foregroundStyle(.secondary) }
                    if top.isEmpty { Text("No allocated file data measured here.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Folder totals include inspected regular files. APFS shared blocks, snapshots, inaccessible locations and filesystem metadata prevent an exact match with used space. Measured size is not a promise of recoverable storage.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 8)
        }
    }
    private func selectionCard(_ folder: DiskEntry) -> some View {
        let item = explorer.selectedEntry ?? folder
        let category = DiskCleanupGuide.category(for: item.path, home: storage.home)
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(item.name, systemImage: item.directory ? "folder" : "doc").font(.headline); Spacer(); Text("INSPECTION ONLY").font(.system(size: 8, weight: .bold)).foregroundStyle(.cyan) }
                Text(item.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Text(DiskCleanupGuide.explanation(for: item.path, home: storage.home, policy: storage.policy)).font(.system(size: 12)).foregroundStyle(.secondary)
                if let note = item.note { Text(note).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                    if item.directory && explorer.current != item.path { Button("Explore folder") { explorer.navigate(item.path) } }
                    if item.directory && item.path != explorer.result?.root {
                        Button("Analyze this folder") { explorer.start(URL(fileURLWithPath: item.path)) }.disabled(storage.busy || explorer.busy)
                    }
                    Spacer()
                    if let category { Button("Review \(category.title)…") { storage.reviewFromExplorer(category) }.buttonStyle(.borderedProminent).disabled(storage.busy || explorer.busy) }
                }.font(.caption)
            }
        }
    }
    private var fileList: some View {
        let items = contents
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("View", selection: $largestFiles) { Text("Folders & files").tag(false); Text("Largest files below here").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 320)
                Spacer()
                Toggle("Hidden only", isOn: $hiddenOnly).toggleStyle(.checkbox).font(.caption)
            }
            HStack { TextField("Search names in this view", text: $search).textFieldStyle(.roundedBorder); Text("At least").font(.caption); TextField("0", text: $minimumMB).textFieldStyle(.roundedBorder).frame(width: 60); Text("MB allocated").font(.caption).foregroundStyle(.secondary) }
            Text("\(items.count.formatted()) entries · largest first\(items.count > 200 ? " · showing first 200; narrow your search" : "")").font(.caption).foregroundStyle(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(Array(items.prefix(200))) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.directory ? "folder.fill" : "doc.fill").foregroundStyle(item.directory ? .blue : .secondary).frame(width: 18)
                        Button { explorer.selected = item.path } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1); if item.hidden { Text("HIDDEN").font(.system(size: 7, weight: .bold)).foregroundStyle(.cyan) } }
                                Text(item.note ?? (item.skipped > 0 ? "Partial size · \(item.skipped) skipped or shared entries" : item.directory ? "\(item.files.formatted()) measured files" : "File size \(storageBytes(item.bytes))"))
                                    .font(.system(size: 10)).foregroundStyle(item.skipped > 0 ? .orange : .secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Text(item.allocated == 0 && item.skipped > 0 ? "Unmeasured" : storageBytes(item.allocated)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        if item.directory { Button { explorer.navigate(item.path) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).help("Explore folder") }
                    }.padding(12).background(explorer.selected == item.path ? .blue.opacity(0.12) : .white.opacity(0.02))
                    Divider().opacity(0.2)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    private var snapshotCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label("Snapshots & System Data", systemImage: "clock.arrow.circlepath").font(.headline); Spacer(); Button("Check startup snapshots") { explorer.loadSnapshots() }.disabled(explorer.snapshotNotice == "Reading snapshot information…") }
                Text("Snapshots retain earlier versions of files. Time Machine manages its local snapshots automatically. Snapshot space is separate from this folder map; Nexa does not count it as reclaimable or delete it.").font(.system(size: 12)).foregroundStyle(.secondary)
                if let notice = explorer.snapshotNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
                if let snapshots = explorer.snapshots {
                    Text(snapshots.isEmpty ? "No snapshots reported on the startup volumes." : "\(snapshots.count) snapshots on the startup volumes · size not available from this inventory").font(.caption).foregroundStyle(.cyan)
                    ForEach(Array(snapshots.prefix(10))) { item in Text(item.volume + " · " + item.name).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                    if snapshots.count > 10 { Text("Showing the first 10. View the full list in Disk Utility.").font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    Button("Open Disk Utility") { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.DiskUtility") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } }
                    Spacer()
                    Link("About local snapshots ↗", destination: URL(string: "https://support.apple.com/en-us/102154")!)
                }.font(.caption)
            }
        }
    }
    private func open(_ entry: DiskEntry) { if entry.directory { explorer.navigate(entry.path) } else { explorer.selected = entry.path } }
}

private struct DiskWedge: Shape {
    let start: Double
    let end: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2
        let a = Angle.degrees(start * 360 - 90 + 0.5), b = Angle.degrees(max(start * 360 - 90 + 0.5, end * 360 - 90 - 0.5))
        return Path { p in
            p.addArc(center: center, radius: radius, startAngle: a, endAngle: b, clockwise: false)
            p.addArc(center: center, radius: radius * 0.65, startAngle: b, endAngle: a, clockwise: true)
            p.closeSubpath()
        }
    }
}
