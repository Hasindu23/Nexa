import SwiftUI
import AppKit
import Quartz

private enum CleanerStyle {
    static let blue = Color(red: 0.32, green: 0.58, blue: 1)
    static let background = Color(red: 0.035, green: 0.047, blue: 0.074)
    static let muted = Color(red: 0.54, green: 0.60, blue: 0.71)
}

struct StorageCleanerView: View {
    @ObservedObject var service: StorageService
    private var page: String { get { service.destination } nonmutating set { service.destination = newValue } }
    @State private var search = ""
    @State private var age = 0
    @State private var customAge = "180"
    @State private var minimumMB = "0"
    @State private var useAccessDate = false
    @State private var shown = 200
    @State private var preview: StorageItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var category: StorageCategory? { StorageCategory(rawValue: page) }
    private var filtered: [StorageItem] {
        let days = age == -1 ? max(0, Int(customAge) ?? 0) : age
        let size = max(0, Double(minimumMB) ?? 0) * 1_000_000
        return (service.scan?.items ?? []).filter { item in
            let matchesPage = page == "focused" ? true : page == "duplicates" ? item.duplicateHash != nil : page == "recommended" ? item.recommended : item.category == category
            let date = useAccessDate ? item.accessed : item.modified
            return matchesPage && (search.isEmpty || item.path.localizedCaseInsensitiveContains(search) || item.group.localizedCaseInsensitiveContains(search)) &&
                Double(item.bytes) >= size && (days == 0 || (date != nil && Date().timeIntervalSince(date!) >= Double(days) * 86400))
        }.sorted { $0.bytes > $1.bytes }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let error = service.error { notice(error, icon: "exclamationmark.triangle", color: .orange) }
                        if page != "memory", let receipt = service.lastReceipt { resultCard(receipt) }
                        if page == "overview" { overview }
                        else if page == "explorer" { DiskExplorerView(explorer: service.explorer, storage: service) }
                        else if page == "memory" { MemoryView(service: service.memory, canClearScans: !service.busy && !service.explorer.busy, clearScans: { Task { await service.clearScanResults() } }) }
                        else if page == "history" { history }
                        else if page == "safety" { safety }
                        else if page == "devices" { devices }
                        else { detail }
                    }.padding(28)
                }
                if !["explorer", "memory"].contains(page) { footer }
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .background(CleanerStyle.background)
        .foregroundStyle(.white).tint(CleanerStyle.blue).preferredColorScheme(.dark)
        .sheet(item: $service.plan) { plan in StorageReviewView(plan: plan, cancel: { service.plan = nil }, confirm: { service.confirm(phrase: $0) }) }
        .sheet(item: $preview) { item in
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text(item.name).font(.headline); Spacer(); Button("Done") { preview = nil } }
                CleanerQuickLook(url: URL(fileURLWithPath: item.path)).frame(width: 700, height: 480)
                Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(22)
        }
        .onAppear { if !["explorer", "memory"].contains(page) { service.opened() } }
        .onChange(of: page) { _, _ in search = ""; age = 0; minimumMB = page == "largeFiles" ? "100" : "0"; shown = 200; useAccessDate = false }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) { BrandMark(size: 32, accent: CleanerStyle.blue); VStack(alignment: .leading, spacing: 2) { Text("NEXA HUB").font(.system(size: 13, weight: .bold)).tracking(1.8); Text("A little more space.").font(.system(size: 10)).foregroundStyle(CleanerStyle.muted) } }.padding(.horizontal, 21).padding(.top, 25).padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    nav("overview", "Overview", "square.grid.2x2")
                    nav("recommended", "Recommended", "sparkle")
                    nav("explorer", "Disk space explorer", "chart.pie")
                    nav("memory", "Memory & apps", "memorychip")
                    if service.focus != nil { nav("focused", "Removal review", "checklist") }
                    sidebarLabel("STORAGE")
                    ForEach(StorageCategory.allCases.filter { ![.leftovers, .applications].contains($0) }) { item in nav(item.rawValue, item.title, item.icon) }
                    nav("duplicates", "Duplicate finder", "square.on.square")
                    nav("applications", "Applications", "app.dashed")
                    nav("leftovers", "App leftovers", "puzzlepiece.extension")
                    sidebarLabel("MANAGE")
                    nav("history", "Cleanup history", "clock.arrow.circlepath")
                    nav("safety", "Protection & scans", "checkmark.shield")
                    nav("devices", "Paired devices", "desktopcomputer")
                }.padding(.horizontal, 11)
            }.scrollIndicators(.hidden)
            HStack(spacing: 8) { Circle().fill(.green.opacity(0.8)).frame(width: 6, height: 6); Text("Local on this Mac").font(.system(size: 11)); Spacer(); Image(systemName: "lock.shield").foregroundStyle(CleanerStyle.blue) }.foregroundStyle(CleanerStyle.muted).padding(22)
        }.frame(width: 214).background(.white.opacity(0.022)).overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
    }
    private func sidebarLabel(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(CleanerStyle.muted.opacity(0.75)).padding(.leading, 13).padding(.top, 22).padding(.bottom, 8) }
    private func nav(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { page = id } label: {
            HStack(spacing: 11) { Image(systemName: icon).font(.system(size: 13)).frame(width: 19); Text(title).font(.system(size: 12, weight: page == id ? .semibold : .regular)); Spacer(minLength: 0); if id == "recommended" && !service.recommendations.isEmpty { Circle().fill(CleanerStyle.blue).frame(width: 5, height: 5) } }
                .foregroundStyle(page == id ? .white : CleanerStyle.muted).padding(.horizontal, 12).padding(.vertical, 9)
                .background(page == id ? CleanerStyle.blue.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityIdentifier("storage.nav.\(id)")
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) { Text("Storage Cleaner").font(.system(size: 23, weight: .semibold)); Text("LOCAL").font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(CleanerStyle.blue).padding(.horizontal, 7).padding(.vertical, 4).background(CleanerStyle.blue.opacity(0.12), in: Capsule()) }
                Text("Make room for what matters.").font(.system(size: 12)).foregroundStyle(CleanerStyle.muted)
            }
            Spacer()
            if service.busy { ProgressView().controlSize(.small); Button("Cancel") { service.cancel() }.buttonStyle(CapsuleButtonStyle()) }
            else if !["explorer", "memory"].contains(page) { Button { service.startScan(focus: page == "focused" ? service.focus : nil) } label: { Label("Scan storage", systemImage: "arrow.clockwise") }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue)).accessibilityIdentifier("storage.scan") }
        }.padding(.horizontal, 29).padding(.top, 24).padding(.bottom, 20)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Your storage, clearly.").font(.system(size: 28, weight: .semibold)); Spacer(); Text(service.scan?.date.formatted(date: .omitted, time: .shortened) ?? "Not scanned yet").font(.caption).foregroundStyle(CleanerStyle.muted) }
            HStack(alignment: .top, spacing: 18) {
                Surface {
                    HStack(spacing: 25) {
                        storageRing
                        VStack(alignment: .leading, spacing: 13) {
                            Label("\(service.deviceID) · Startup disk", systemImage: "internaldrive").font(.system(size: 12, weight: .medium))
                            if let scan = service.scan, scan.totalCapacity > 0 {
                                Text("\(storageBytes(scan.totalCapacity - scan.availableCapacity)) used").font(.system(size: 24, weight: .semibold))
                                Text("of \(storageBytes(scan.totalCapacity)) · \(storageBytes(scan.availableCapacity)) available").font(.system(size: 11)).foregroundStyle(CleanerStyle.muted)
                            } else { Text("A fresh view of your disk").font(.system(size: 20, weight: .medium)); Text("Usage appears after your first scan.").font(.caption).foregroundStyle(CleanerStyle.muted) }
                            Label("Files stay on your device", systemImage: "lock").font(.system(size: 10)).foregroundStyle(CleanerStyle.muted)
                        }; Spacer(minLength: 0)
                    }.padding(10).frame(minHeight: 150)
                }.frame(maxWidth: .infinity)
            }
            Surface {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: "sparkles").font(.system(size: 23)).foregroundStyle(CleanerStyle.blue).frame(width: 52, height: 52).background(CleanerStyle.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommended cleanup").font(.system(size: 17, weight: .semibold))
                        Text("Low-risk candidates. Every item is yours to approve.").font(.system(size: 11)).foregroundStyle(CleanerStyle.muted)
                        Text("\(service.recommendations.count.formatted()) \(service.recommendations.count == 1 ? "item" : "items") · \(storageBytes(service.recommendations.reduce(0) { $0 + $1.allocated })) potential").font(.system(size: 12, weight: .medium)).foregroundStyle(CleanerStyle.blue)
                    }
                    Spacer()
                    Button("Review items") { service.recommend(); page = "recommended" }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue, filled: true)).disabled(service.busy || service.recommendations.isEmpty)
                }.padding(8)
            }
            HStack { Text("Explore your storage").font(.system(size: 16, weight: .semibold)); Spacer(); Text("Measured scan results").font(.system(size: 10)).foregroundStyle(CleanerStyle.muted) }
            Button { page = "explorer" } label: {
                HStack(spacing: 16) { Image(systemName: "chart.pie.fill").font(.title2); VStack(alignment: .leading, spacing: 4) { Text("Explore hidden SSD storage").font(.system(size: 15, weight: .semibold)); Text("Library, app data, hidden folders and large files. See what’s using space before you clean.").font(.system(size: 11)).foregroundStyle(CleanerStyle.muted) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(20).foregroundStyle(CleanerStyle.blue).frame(maxWidth: .infinity, alignment: .leading).background(CleanerStyle.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach([StorageCategory.caches, .downloads, .developer, .docker, .models, .largeFiles]) { category in categoryCard(category) }
            }
            scannedBreakdown
            notice("Nothing is deleted during a scan. Moving files to Trash keeps them recoverable and does not free disk space until Trash is emptied.", icon: "checkmark.shield", color: CleanerStyle.muted)
            if let scan = service.scan, !scan.issues.isEmpty { issues(scan) }
        }
    }
    private var scannedBreakdown: some View {
        let labels = ["Applications", "Documents", "Photos", "Videos", "Developer Data", "Docker", "AI Models", "Caches", "Downloads", "Other"]
        var totals: [String: Int64] = [:]
        for item in service.scan?.items ?? [] where item.category != .leftovers {
            let name: String
            switch item.category {
            case .applications: name = "Applications"
            case .developer: name = "Developer Data"
            case .docker: name = "Docker"
            case .models: name = "AI Models"
            case .caches, .browser, .temporary: name = "Caches"
            case .downloads, .installers: name = "Downloads"
            default:
                let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "heic", "gif", "raw", "tiff"].contains(ext) { name = "Photos" }
                else if ["mov", "mp4", "mkv", "avi", "webm"].contains(ext) { name = "Videos" }
                else if ["pdf", "doc", "docx", "txt", "pages", "xlsx", "pptx", "md"].contains(ext) { name = "Documents" }
                else { name = "Other" }
            }
            totals[name, default: 0] += item.bytes
        }
        let total = max(1, totals.values.reduce(0, +))
        return Surface {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scanned storage breakdown").font(.system(size: 15, weight: .semibold))
                Text("Only inspected locations are represented. This is not a full-disk accounting; shared data can overlap. Add folders to inspect documents, photos and videos.").font(.system(size: 11)).foregroundStyle(CleanerStyle.muted)
                ForEach(labels, id: \.self) { label in
                    HStack(spacing: 18) {
                        Text(label).font(.system(size: 11)).frame(width: 110, alignment: .leading)
                        GeometryReader { geometry in Capsule().fill(.white.opacity(0.045)).overlay(alignment: .leading) { Capsule().fill(CleanerStyle.blue.opacity(0.65)).frame(width: geometry.size.width * Double(totals[label] ?? 0) / Double(total)) } }.frame(height: 5)
                        Text(totals[label] == nil ? "Not measured" : storageBytes(totals[label]!)).font(.system(size: 10)).foregroundStyle(CleanerStyle.muted).frame(width: 100, alignment: .trailing)
                    }
                }
            }.padding(5)
        }
    }
    private var storageRing: some View {
        let scan = service.scan
        let fraction = scan == nil || scan!.totalCapacity == 0 ? 0 : min(1, max(0, Double(scan!.totalCapacity - scan!.availableCapacity) / Double(scan!.totalCapacity)))
        return ZStack {
            Circle().stroke(.white.opacity(0.065), lineWidth: 11)
            Circle().trim(from: 0, to: fraction).stroke(AngularGradient(colors: [CleanerStyle.blue.opacity(0.6), Color.cyan, CleanerStyle.blue], center: .center), style: StrokeStyle(lineWidth: 11, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 4) { Text(scan == nil ? "—" : "\(Int(fraction * 100))%").font(.system(size: 29, weight: .medium, design: .rounded)); Text("USED").font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(CleanerStyle.muted) }
        }.frame(width: 131, height: 131).padding(9).accessibilityLabel("Disk used: \(Int(fraction * 100)) percent")
    }
    private func categoryCard(_ category: StorageCategory) -> some View {
        let items = service.scan?.items.filter { $0.category == category } ?? []
        let risk: StorageRisk = [.caches].contains(category) ? .safe : [.models].contains(category) ? .sensitive : .review
        return Button { page = category.rawValue } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Image(systemName: category.icon).font(.system(size: 19)).foregroundStyle(CleanerStyle.blue); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(CleanerStyle.muted) }
                VStack(alignment: .leading, spacing: 5) { Text(category.title).font(.system(size: 12, weight: .medium)); Text(items.isEmpty ? "Explore" : storageBytes(items.reduce(0) { $0 + $1.bytes })).font(.system(size: 23, weight: .medium, design: .rounded)) }
                riskLabel(risk)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.065)))
        }.buttonStyle(.plain)
    }
    private var detail: some View {
        let visibleItems = filtered
        return VStack(alignment: .leading, spacing: 18) {
            Text(page == "focused" ? "Review removable files" : page == "duplicates" ? "Duplicate finder" : page == "recommended" ? "Recommended cleanup" : category?.title ?? "Storage").font(.system(size: 27, weight: .semibold))
            Text(page == "duplicates" ? "Candidates are grouped by size, compared using a small sample, then verified with SHA-256. Choose the copy to keep. Filename alone is never enough." : page == "recommended" ? "Only recognized caches, temporary files and old installer candidates appear here. Review the exact files before continuing. No personal documents or sensitive resources are preselected." : category?.explanation ?? "").font(.system(size: 12)).foregroundStyle(CleanerStyle.muted).lineSpacing(4)
            if page == "focused", let focus = service.focus {
                Surface { VStack(alignment: .leading, spacing: 9) {
                    Text(focus.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text("Only recognized cleanup locations inside this selection are scanned. Unknown app data stays outside this review. Select the exact files, choose Move to Trash or Delete Cache, then review and confirm. Delete Cache is permanent and needs an additional typed confirmation.").font(.system(size: 12)).foregroundStyle(CleanerStyle.muted)
                    let eligible = visibleItems.filter(\.eligible)
                    Text("\(eligible.count.formatted()) removable \(eligible.count == 1 ? "candidate" : "candidates") · \(storageBytes(eligible.reduce(0) { $0 + $1.allocated })) allocated estimate").font(.system(size: 12, weight: .semibold)).foregroundStyle(CleanerStyle.blue)
                    Text("Reclaimable space can be lower. Trash does not free space until it is emptied.").font(.caption).foregroundStyle(CleanerStyle.muted)
                } }
            } else { scopeControls }
            filters
            if page == "duplicates" && service.scan?.duplicateComplete != true {
                Surface { HStack { Label("Hashing runs only when requested.", systemImage: "checkmark.seal"); Spacer(); Button("Verify duplicates") { service.findDuplicates() }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue, filled: true)).disabled(service.scan == nil || service.busy) }.font(.system(size: 12)) }
            }
            if category == .largeFiles, let scan = service.scan, !scan.folderSizes.isEmpty {
                DisclosureGroup("Largest scanned folders") {
                    VStack(spacing: 10) { ForEach(Array(scan.folderSizes.sorted { $0.value > $1.value }.prefix(10)), id: \.key) { folder in HStack { Text(folder.key).lineLimit(1).truncationMode(.middle).textSelection(.enabled); Spacer(); Text(storageBytes(folder.value)).monospacedDigit() }.font(.system(size: 11)).foregroundStyle(CleanerStyle.muted) } }.padding(.top, 12)
                }.padding(16).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text("\(visibleItems.count.formatted()) \(visibleItems.count == 1 ? "item" : "items") · \(storageBytes(visibleItems.reduce(0) { $0 + $1.bytes }))").font(.system(size: 12, weight: .medium))
                Spacer()
                if category == .trash { Button("Empty reviewed Trash…") { service.selection = Set(visibleItems.filter(\.eligible).prefix(5000).map(\.id)); service.action = .permanent; service.review() }.disabled(service.busy || !visibleItems.contains(where: \.eligible)) }
                else if page != "duplicates" { Button("Select visible") { service.select(Array(visibleItems.prefix(shown))) }.disabled(service.busy); Button("Clear") { service.selection.removeAll() }.disabled(service.busy) }
            }
            if visibleItems.isEmpty {
                Surface { EmptyModule(icon: service.busy ? "externaldrive" : "checkmark.circle", title: service.busy ? "Taking a closer look" : "No matching items", detail: service.busy ? service.status : "Scan a relevant location or adjust your filters. Unavailable and protected locations are reported below.") }
            } else if page == "duplicates" { duplicateList }
            else {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(Array(Set(visibleItems.prefix(shown).map(\.group))).sorted(), id: \.self) { group in
                        let items = visibleItems.prefix(shown).filter { $0.group == group }
                        let entireGroup = visibleItems.filter { $0.group == group }
                        VStack(spacing: 0) {
                            HStack { Text(group).font(.system(size: 12, weight: .semibold)); Spacer(); Text(storageBytes(entireGroup.reduce(0) { $0 + $1.bytes })).font(.system(size: 11)).foregroundStyle(CleanerStyle.muted); Button("Select group") { service.select(entireGroup) }.font(.system(size: 10)).disabled(service.busy) }.padding(14).background(.white.opacity(0.025))
                            ForEach(Array(items)) { item in fileRow(item) }
                        }.background(.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.055)))
                    }
                }
                if visibleItems.count > shown { HStack { Text("Showing \(shown.formatted()) of \(visibleItems.count.formatted()) \(visibleItems.count == 1 ? "item" : "items")").font(.caption).foregroundStyle(CleanerStyle.muted); Spacer(); Button("Show next 200 items") { shown += 200 }.buttonStyle(CapsuleButtonStyle()) } }
            }
            if let scan = service.scan, !scan.issues.isEmpty { issues(scan) }
        }
    }
    @ViewBuilder private var scopeControls: some View {
        if category == .downloads || category == .installers || page == "duplicates" {
            HStack { Button(service.settings.scanDownloads ? "Rescan Downloads" : "Include Downloads") { service.configure { $0.scanDownloads = true }; service.startScan() }; Button("Choose folder…") { service.chooseFolder() } }.disabled(service.busy)
        }
        if category == .screenshots {
            HStack { Button("Scan Desktop (read-only)") { service.configure { $0.scanDesktop = true }; service.startScan() }; Button("Choose screenshots folder…") { service.chooseFolder() } }.disabled(service.busy)
        }
        if category == .largeFiles { Button("Choose folder or drive…") { service.chooseFolder() }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue)).disabled(service.busy) }
        if category == .docker || category == .models {
            Button(category == .docker ? "Connect local Docker & scan" : "Connect local Ollama & scan") { service.configure { if category == .docker { $0.includeDocker = true } else { $0.includeOllama = true } }; service.startScan() }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue)).disabled(service.busy)
            Text("Local connection only. No remote credentials or account connection.").font(.caption).foregroundStyle(CleanerStyle.muted)
        }
        if category == .applications || category == .leftovers { Button("Inspect applications & possible leftovers") { service.startScan(inventory: true) }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue)).disabled(service.busy) }
        if category == .browser {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Cookies · Site data · Download history").font(.system(size: 12, weight: .medium)); Spacer(); riskLabel(.sensitive) }
                    Text("Deleting cookies or site data may sign you out. Saved sessions and profiles are never cleaned here. Select these categories explicitly in your browser settings.").font(.system(size: 11)).foregroundStyle(CleanerStyle.muted)
                    HStack { browserButton("Safari", "com.apple.Safari", "https://support.apple.com/guide/safari/clear-your-browsing-history-sfri47acf5d6/mac"); browserButton("Chrome", "com.google.Chrome", "chrome://settings/clearBrowserData"); browserButton("Edge", "com.microsoft.edgemac", "edge://settings/clearBrowserData"); browserButton("Firefox", "org.mozilla.firefox", "about:preferences#privacy") }
                }
            }
        }
    }
    private func browserButton(_ title: String, _ bundleID: String, _ path: String) -> some View {
        Button("Open \(title)") {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), let url = URL(string: path) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in if let error { Task { @MainActor in service.error = error.localizedDescription } } }
            } else { service.error = "\(title) is not installed." }
        }.font(.system(size: 11))
    }
    private var filters: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(CleanerStyle.muted)
                TextField("Search files or applications", text: $search).textFieldStyle(.plain)
                Picker("Older than", selection: $age) { Text("Any age").tag(0); Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90); Text("Custom").tag(-1) }.frame(width: 180)
                if age == -1 { TextField("Days", text: $customAge).frame(width: 50) }
                Text("Min MB").foregroundStyle(CleanerStyle.muted); TextField("0", text: $minimumMB).frame(width: 60)
            }
            if [.downloads, .installers, .largeFiles].contains(category) {
                HStack { Toggle("Filter by access date (when available)", isOn: $useAccessDate).toggleStyle(.checkbox); Spacer(); Text("Access dates can be approximate.").foregroundStyle(CleanerStyle.muted) }.font(.system(size: 10))
            }
        }.font(.system(size: 11)).padding(13).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
    private func fileRow(_ item: StorageItem, duplicate: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("Select \(item.name)", isOn: Binding(get: { service.selection.contains(item.id) }, set: { _ in service.toggle(item) })).labelsHidden().toggleStyle(.checkbox).disabled(!item.eligible || service.busy)
            Image(systemName: item.category.icon).font(.system(size: 16)).foregroundStyle(CleanerStyle.blue.opacity(0.8)).frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1); if !item.eligible { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(CleanerStyle.muted) } }
                Text(item.isResource ? item.reason : item.path).font(.system(size: 10)).foregroundStyle(CleanerStyle.muted).lineLimit(1).truncationMode(.middle).help(item.path + "\n" + item.reason)
                Text(item.reason).font(.system(size: 9)).foregroundStyle(item.eligible ? CleanerStyle.muted : .orange.opacity(0.75)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) { Text(storageBytes(item.bytes)).font(.system(size: 12, weight: .medium)).monospacedDigit(); Text(item.modified > .distantPast ? item.modified.formatted(date: .abbreviated, time: .omitted) : "Date unavailable").font(.system(size: 9)).foregroundStyle(CleanerStyle.muted) }.frame(width: 90, alignment: .trailing)
            if duplicate { Button("Keep this") { service.keepDuplicate(item) }.font(.system(size: 10)).disabled(service.busy) }
            Menu {
                if !item.isResource {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                    Button("Quick Look") { preview = item }
                    if item.category == .applications { Button("Open application") { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) } }
                    Divider()
                    Button("Ignore path") { service.ignore(item) }.disabled(service.busy)
                    Button("Add to protected list") { service.protect(item) }.disabled(service.busy)
                    if item.eligible && item.category != .trash { Button("Review Move to Trash…") { service.selection = [item.id]; service.action = .trash; service.review() }.disabled(service.busy) }
                }
                Button("Show details") { service.error = "\(item.name)\n\(item.reason)\n\(item.path)\nModified: \(item.modified.formatted())\nLast accessed: \(item.accessed?.formatted() ?? "Unavailable")\nCreated: \(item.created?.formatted() ?? "Unavailable")\nAllocated: \(storageBytes(item.allocated))\nRisk: \(item.risk.rawValue)" }
            } label: { Image(systemName: "ellipsis").frame(width: 20) }.menuStyle(.borderlessButton).fixedSize()
        }.padding(.horizontal, 14).padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.04)).frame(height: 1) }
    }
    private var duplicateList: some View {
        let groups = Dictionary(grouping: filtered) { $0.duplicateHash ?? "" }
        return LazyVStack(spacing: 16) {
            ForEach(Array(groups.keys).sorted(), id: \.self) { hash in
                let items = groups[hash] ?? []
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Image(systemName: "checkmark.seal.fill").foregroundStyle(CleanerStyle.blue); Text("\(items.count) identical files · \(storageBytes(items.reduce(0) { $0 + $1.bytes })) total"); Spacer(); Text("SHA-256 verified").foregroundStyle(CleanerStyle.muted) }.font(.system(size: 11)).padding(14)
                    ForEach(items) { item in fileRow(item, duplicate: true) }
                }.background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 5) { Text(service.selection.isEmpty ? service.status : "\(service.selection.count.formatted()) selected · \(storageBytes(service.selectedBytes))").font(.system(size: 11, weight: .medium)).lineLimit(1); Text("Scan → Review → Confirm → Verify").font(.system(size: 9)).foregroundStyle(CleanerStyle.muted) }
            Spacer()
            Picker("Action", selection: $service.action) { ForEach(CleanupAction.allCases) { action in Text(action.rawValue).tag(action) } }.labelsHidden().frame(width: 165).disabled(service.busy)
            Button("Review selected…") { service.review() }.buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue, filled: true)).disabled(service.busy || service.selection.isEmpty).accessibilityIdentifier("storage.review")
        }.padding(.horizontal, 27).padding(.vertical, 17).background(.white.opacity(0.025)).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }
    private func riskLabel(_ risk: StorageRisk) -> some View {
        let color: Color = risk == .safe ? .mint : risk == .review ? .orange : .pink
        return HStack(spacing: 5) { Circle().fill(color).frame(width: 4, height: 4); Text(risk.rawValue.uppercased()).font(.system(size: 8, weight: .medium)).tracking(0.8) }.foregroundStyle(color.opacity(0.9))
    }
    private func notice(_ text: String, icon: String, color: Color) -> some View { HStack(alignment: .top, spacing: 10) { Image(systemName: icon); Text(text).textSelection(.enabled).lineSpacing(4); Spacer(minLength: 0) }.font(.system(size: 11)).foregroundStyle(color).padding(15).background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 10)) }
    private func issues(_ scan: StorageScan) -> some View {
        DisclosureGroup("\(scan.issues.count) skipped locations or scan notices") { VStack(alignment: .leading, spacing: 9) { ForEach(Array(scan.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.system(size: 10)).foregroundStyle(CleanerStyle.muted).textSelection(.enabled) } }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12) }.font(.system(size: 11)).padding(15).background(.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
    private func resultCard(_ receipt: CleanupReceipt) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 11) {
                HStack { Label(receipt.failures.isEmpty ? "Cleanup verified" : "Cleanup finished with issues", systemImage: receipt.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle").font(.system(size: 14, weight: .semibold)); Spacer(); Button { service.lastReceipt = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                Text("\(receipt.succeeded.count) \(receipt.succeeded.count == 1 ? "item" : "items") · \(storageBytes(receipt.removedBytes)) \(receipt.action == .trash ? "moved to Trash" : "removed") · \(storageBytes(receipt.reclaimedBytes)) observed reclaimed").font(.system(size: 12)).foregroundStyle(CleanerStyle.blue)
                Text(receipt.note).font(.system(size: 11)).foregroundStyle(CleanerStyle.muted)
                if !receipt.recovery.isEmpty { Button("Undo move to Trash") { service.undo(receipt) }.disabled(service.busy) }
                if !receipt.failures.isEmpty { DisclosureGroup("\(receipt.failures.count) issues") { ForEach(Array(receipt.failures.enumerated()), id: \.offset) { _, error in Text(error).font(.caption).textSelection(.enabled) } } }
            }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cleanup history").font(.system(size: 27, weight: .semibold))
            Text("Stored locally. Includes dates, device, actions, paths and verified results. No file contents.").font(.system(size: 12)).foregroundStyle(CleanerStyle.muted)
            if service.history.isEmpty { EmptyModule(icon: "clock.arrow.circlepath", title: "A clean slate", detail: "Your first confirmed cleanup will appear here.") }
            ForEach(service.history) { receipt in
                Surface { VStack(alignment: .leading, spacing: 12) { HStack { Text(receipt.date.formatted()).font(.system(size: 12, weight: .semibold)); Spacer(); Text(receipt.action.rawValue).font(.system(size: 11)).foregroundStyle(CleanerStyle.blue) }; Text(receipt.device + " · " + receipt.categories.joined(separator: ", ")).font(.caption).foregroundStyle(CleanerStyle.muted); Text("\(receipt.succeeded.count) \(receipt.succeeded.count == 1 ? "item" : "items") · \(storageBytes(receipt.reclaimedBytes)) observed reclaimed").font(.system(size: 13)); DisclosureGroup("Files and result") { VStack(alignment: .leading, spacing: 8) { Text(receipt.note); ForEach(receipt.succeeded, id: \.self) { Text($0) }; ForEach(Array(receipt.failures.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(.orange) } }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }; if !receipt.recovery.isEmpty { Button("Undo move to Trash") { service.undo(receipt) }.disabled(service.busy) } } }
            }
        }
    }
    private var safety: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Protection & scans").font(.system(size: 27, weight: .semibold))
            notice("Nexa never recursively removes a protected directory. Symlinks, changed files, hard links and mounted system trees are excluded from cleanup. Read-only or unavailable locations are reported.", icon: "checkmark.shield", color: CleanerStyle.blue)
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Protected paths").font(.headline); Spacer(); Button("Protect a folder…") { service.chooseFolder(protect: true) }.disabled(service.busy) }
                    ForEach(["/ (directory itself)"] + service.policy.protectedPaths, id: \.self) { Text($0).font(.system(size: 10, design: .monospaced)).foregroundStyle(CleanerStyle.muted).textSelection(.enabled) }
                    Text("Default protection cannot be removed here.").font(.caption).foregroundStyle(CleanerStyle.muted)
                    ForEach(service.settings.protectedPaths, id: \.self) { path in HStack { Text(path).font(.caption); Spacer(); Button("Remove custom protection") { service.configure { $0.protectedPaths.removeAll { $0 == path } } }.disabled(service.busy) } }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Scan schedule").font(.headline)
                    Picker("Automatic scans", selection: Binding(get: { service.settings.scheduleDays }, set: { value in service.configure { $0.scheduleDays = value; $0.lastScheduledScan = Date() } })) { Text("Off").tag(0); Text("Weekly").tag(7); Text("Monthly (30 days)").tag(30) }.disabled(service.busy)
                    Text("Scan only, while Nexa is running. Checks once an hour; no background disk polling. Scheduled scans never delete files. Auto-clean is not enabled in this build.").font(.system(size: 11)).foregroundStyle(CleanerStyle.muted)
                    Toggle("Include Downloads", isOn: Binding(get: { service.settings.scanDownloads }, set: { value in service.configure { $0.scanDownloads = value } })).disabled(service.busy)
                    Toggle("Connect local Docker", isOn: Binding(get: { service.settings.includeDocker }, set: { value in service.configure { $0.includeDocker = value } })).disabled(service.busy)
                    Toggle("Connect local Ollama", isOn: Binding(get: { service.settings.includeOllama }, set: { value in service.configure { $0.includeOllama = value } })).disabled(service.busy)
                }.font(.system(size: 12))
            }
            Surface { VStack(alignment: .leading, spacing: 12) { HStack { Text("Additional scan locations").font(.headline); Spacer(); Button("Add folder…") { service.chooseFolder() }.disabled(service.busy) }; ForEach(service.settings.selectedFolders, id: \.self) { path in HStack { Text(path).font(.caption).textSelection(.enabled); Spacer(); Button("Remove") { service.configure { $0.selectedFolders.removeAll { $0 == path } } }.disabled(service.busy) } }; if service.settings.selectedFolders.isEmpty { Text("No additional folders selected.").font(.caption).foregroundStyle(CleanerStyle.muted) } } }
            Surface { VStack(alignment: .leading, spacing: 12) { Text("Ignored paths").font(.headline); ForEach(service.settings.ignoredPaths, id: \.self) { path in HStack { Text(path).font(.caption).textSelection(.enabled); Spacer(); Button("Stop ignoring") { service.configure { $0.ignoredPaths.removeAll { $0 == path } } }.disabled(service.busy) } }; if service.settings.ignoredPaths.isEmpty { Text("Nothing ignored yet.").font(.caption).foregroundStyle(CleanerStyle.muted) } } }
        }
    }
    private var devices: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Paired devices").font(.system(size: 27, weight: .semibold))
            Surface { HStack(spacing: 18) { Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(CleanerStyle.blue); VStack(alignment: .leading, spacing: 6) { Text(service.deviceID).font(.headline); Text("This Mac · Local storage access").font(.caption).foregroundStyle(CleanerStyle.muted) }; Spacer(); Text("CONNECTED").font(.system(size: 9, weight: .semibold)).foregroundStyle(.mint) } }
            notice("This Nexa project has no pairing service or Windows Agent. Remote scans and cleanup are unavailable. The included permission contract requires a connected device, a current CLEAN_STORAGE grant and a device-issued review for exact scanned items.", icon: "network", color: CleanerStyle.muted)
            Text("Drive health: unavailable from this module. Capacity readings are not a drive health diagnosis.").font(.system(size: 12)).foregroundStyle(CleanerStyle.muted)
        }
    }
}

struct StorageReviewView: View {
    let plan: CleanupPlan
    let cancel: () -> Void
    let confirm: (String) -> Void
    @State private var finalStep = false
    @State private var phrase = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack { Image(systemName: plan.action.irreversible ? "exclamationmark.shield" : "trash").font(.title).foregroundStyle(plan.action.irreversible ? .orange : CleanerStyle.blue); VStack(alignment: .leading, spacing: 5) { Text(finalStep ? "Confirm permanent deletion" : "Review exact items").font(.title2.bold()); Text("\(plan.items.count.formatted()) \(plan.items.count == 1 ? "item" : "items") · \(storageBytes(plan.bytes)) · \(plan.deviceID)").font(.caption).foregroundStyle(.secondary) }; Spacer() }
            Text(plan.action.rawValue).font(.headline)
            Text(plan.action == .trash ? "These exact files will move to macOS Trash. No disk space is reclaimed until Trash is emptied. Undo is available while the files remain in Trash." : "These exact files or resources will be permanently removed. This bypasses Trash and cannot be undone. Caches may rebuild; Docker volumes may contain personal databases. Shared layers and snapshots may reduce recovered space.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(plan.items) { item in VStack(alignment: .leading, spacing: 4) { HStack { Text(item.name).font(.system(size: 12, weight: .semibold)); Spacer(); Text(storageBytes(item.bytes)).font(.caption).monospacedDigit() }; Text(item.path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled); Text(item.risk.rawValue + " · " + item.reason).font(.system(size: 10)).foregroundStyle(item.risk == .sensitive ? .orange : .secondary); Divider() } } }.padding(12) }.frame(height: finalStep ? 180 : 310).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            if finalStep { Text("Type DELETE to confirm permanent removal.").font(.system(size: 12, weight: .medium)); TextField("DELETE", text: $phrase).textFieldStyle(.roundedBorder).accessibilityIdentifier("storage.permanentPhrase") }
            Text("Review expires after 5 minutes. Every item is rechecked before removal. Changed, active or protected files are skipped.").font(.system(size: 10)).foregroundStyle(.secondary)
            HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); if plan.action.irreversible && !finalStep { Button("Continue to confirmation") { finalStep = true }.buttonStyle(.borderedProminent) } else { Button(plan.action.irreversible ? "Permanently delete reviewed items" : "Confirm Move to Trash") { confirm(phrase) }.buttonStyle(.borderedProminent).tint(plan.action.irreversible ? .red : CleanerStyle.blue).disabled(plan.action.irreversible && phrase != "DELETE").accessibilityIdentifier("storage.confirm") } }
        }.padding(28).frame(width: 700).background(CleanerStyle.background).preferredColorScheme(.dark)
    }
}

private struct CleanerQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = true; view.previewItem = url as NSURL; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

struct StorageLauncherView: View {
    let open: () -> Void
    var body: some View {
        VStack(spacing: 17) { EmptyModule(icon: "externaldrive.badge.checkmark", title: "A little more space", detail: "Scan, review and safely clean storage in a dedicated window. Nothing is deleted without your confirmation."); Button("Open Storage Cleaner", action: open).buttonStyle(CapsuleButtonStyle(accent: CleanerStyle.blue, filled: true)) }
    }
}
