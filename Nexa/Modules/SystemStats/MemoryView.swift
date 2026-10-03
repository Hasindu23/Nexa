import SwiftUI
import AppKit

struct MemoryView: View {
    @ObservedObject var service: MemoryService
    let canClearScans: Bool
    let clearScans: () -> Void
    private func amount(_ bytes: UInt64?) -> String { bytes.map { storageBytes(Int64(clamping: $0)) } ?? "Unavailable" }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { VStack(alignment: .leading, spacing: 7) { Text("Memory & running apps").font(.system(size: 28, weight: .semibold)); Text("See what is using RAM. Close only the apps you choose.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button("Refresh memory") { service.refresh() }.buttonStyle(.borderedProminent).disabled(service.busy) }
            if let error = service.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            Text(service.status).font(.caption).foregroundStyle(.secondary)
            if let sample = service.snapshot {
                Surface {
                    HStack(spacing: 16) {
                        Image(systemName: "memorychip").font(.system(size: 28)).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Memory pressure: \(sample.pressureName)").font(.title3.bold())
                            Text(sample.pressure == 1 ? "macOS reports normal memory pressure. A small free-RAM number alone does not mean your Mac needs cleaning." : [2, 4].contains(sample.pressure ?? 0) ? "Save your work and consider quitting an app you are not using. Activity Monitor provides a fuller view." : "Memory pressure is unavailable from this system. Open Activity Monitor for the system's own memory view.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }; Spacer()
                    }
                }
                HStack(spacing: 12) {
                    metric("Physical RAM", amount(sample.total), "Installed memory")
                    metric("Free RAM", amount(sample.free), "Free pages reported by macOS")
                    metric("Compressed", amount(sample.compressed), "RAM holding compressed data")
                    metric("Swap on SSD", amount(sample.swap), "Managed by macOS")
                }
                Text("Wired RAM: \(amount(sample.wired)). Cached memory can be reused by macOS. Free RAM, compressed memory and swap are different measurements; disk cleanup does not directly free RAM.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Running applications").font(.headline); Spacer(); Text("MAIN PROCESS MEMORY").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                    Text("Memory is the main process's physical footprint. Browser tabs, extensions and helper processes may use additional RAM. Missing measurements are shown as unavailable.").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(service.apps) { app in
                        HStack(spacing: 14) {
                            Image(systemName: "app").foregroundStyle(.blue)
                            Text(app.name).font(.system(size: 12, weight: .medium)); Spacer()
                            Text(amount(app.bytes)).monospacedDigit().font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("Review quit…") { service.reviewQuit(app) }.disabled(!app.canQuit || service.busy)
                        }.padding(.vertical, 7)
                        Divider().opacity(0.3)
                    }
                    if service.apps.isEmpty { Text("No application inventory loaded.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Free memory by closing work you no longer need").font(.headline)
                    Text("Save your work, close unused browser tabs, or review an app above. Nexa sends a normal quit request only after confirmation. It never force-quits apps, purges RAM, deletes swap files, or promises a fixed amount of freed memory.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    HStack {
                        Button("Open Activity Monitor") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
                        }
                        Spacer()
                        Link("How macOS uses memory ↗", destination: URL(string: "https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac")!)
                    }.font(.caption)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Release Nexa's scan data").font(.headline)
                    Text("Clears the storage inventories and pending cleanup review held in Nexa's memory. Your files and cleanup history stay on disk. Run a new scan before cleaning again. The amount of RAM reused by macOS can vary.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Clear Nexa scan results") { clearScans() }.disabled(!canClearScans || service.busy)
                }
            }
        }
        .onAppear { if service.snapshot == nil { service.refresh() } }
        .sheet(item: $service.pendingQuit) { app in
            VStack(alignment: .leading, spacing: 20) {
                Label("Quit \(app.name)?", systemImage: "app.badge.checkmark").font(.title2.bold())
                Text("Save your work first. Nexa will ask this app to quit normally. The app may ask you to save changes or refuse to close. Background helpers may remain open.").font(.body)
                Text("Current main-process footprint: \(amount(app.bytes)). This is not a promise of freed RAM.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Cancel") { service.pendingQuit = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Ask app to quit") { service.confirmQuit() }.buttonStyle(.borderedProminent) }
            }.padding(28).frame(width: 490).preferredColorScheme(.dark)
        }
    }
    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        Surface { VStack(alignment: .leading, spacing: 9) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)); Text(detail).font(.system(size: 9)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
    }
}
