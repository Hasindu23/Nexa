import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    @State private var confirmClear = false
    var body: some View {
        VStack(spacing: 20) {
            SettingsGroup(title: "PRIVATE BY DEFAULT") {
                settingToggle("Local-only mode", detail: "Blocks AI, weather, remote artwork and update requests.", value: $preferences.value.localOnly)
                settingToggle("Capture clipboard history", detail: "Off by default. Stored only in your local app folder.", value: $preferences.value.clipboardEnabled)
                HStack { Text("History limit").font(.system(size: 12)); Spacer(); Stepper("\(preferences.value.historyLimit) items", value: $preferences.value.historyLimit, in: 10...500, step: 10).font(.system(size: 11)).frame(width: 155) }
                HStack { Label("No analytics. No license server. No tracking.", systemImage: "checkmark.shield").font(.system(size: 11)).foregroundStyle(preferences.value.accent.color); Spacer() }
                Text("Clipboard history may contain personal information. Nexa skips standard concealed and transient clipboard types, but cannot recognize every secret. Pause capture before copying sensitive information. History is not separately encrypted; your Mac’s account and FileVault protect local files.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary).lineSpacing(3)
                Button("Clear clipboard database…", role: .destructive) { confirmClear = true }.font(.system(size: 11))
            }
            SettingsGroup(title: "FILE SHELF") {
                settingToggle("Keep shelf between launches", value: $preferences.value.persistentShelf)
                HStack { Text("Remove references after").font(.system(size: 12)); Spacer(); Picker("Expiry", selection: $preferences.value.shelfExpiryHours) { Text("1 hour").tag(1.0); Text("24 hours").tag(24.0); Text("7 days").tag(168.0); Text("Never").tag(0.0) }.labelsHidden().frame(width: 150) }
                Text("The shelf stores references. Removing or expiring an item never deletes the original file.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
                Button("Clear file shelf") { model.files.clear() }.font(.system(size: 11))
            }
            SettingsGroup(title: "MEDIA & MIRROR") {
                settingToggle("Connect Now Playing", detail: "Follows media reported by apps and websites to macOS.", value: $preferences.value.mediaConnected)
                Text("Mirror starts only when clicked, stops when Nexa closes, and never records audio or video. System media is read locally, including in Local-only mode.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
                Button("Turn camera off") { model.mirror.stop() }.font(.system(size: 11))
            }
            SettingsGroup(title: "PERMISSIONS") {
                Text("Camera, Calendar, Reminders, Music automation and Bluetooth access are requested only when you choose to connect them. Accessibility is optional for the lock-screen button. Screen Recording and Full Disk Access are not required.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineSpacing(4)
                Button("Open Privacy & Security ↗") { model.controls.settings("com.apple.settings.PrivacySecurity.extension") }.font(.system(size: 11))
            }
        }.confirmationDialog("Clear all clipboard history, including pinned items?", isPresented: $confirmClear) { Button("Clear History", role: .destructive) { model.clipboard.clear() }; Button("Cancel", role: .cancel) {} }
    }
}

struct AssistantSettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @State private var key = ""
    @State private var message: String?
    var body: some View {
        SettingsGroup(title: "BRING YOUR OWN KEY") {
            SecureField("OpenAI API key", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save to Keychain") { do { try KeychainService.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; message = "Saved securely in this Mac’s Keychain." } catch { message = error.localizedDescription } }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove saved key", role: .destructive) { KeychainService.delete(); message = "Saved key removed." }
            }.font(.system(size: 11))
            TextField("Model ID", text: $preferences.value.aiModel).textFieldStyle(.roundedBorder)
            Text("Enable Assistant in Modules and turn off Local-only mode. Paste or type the text you want help with, review it, then press Send. Only that text is sent to OpenAI. No selection monitoring or automatic clipboard uploads.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineSpacing(4)
            Text("API usage is billed to your OpenAI account. Responses use store: false; OpenAI’s own retention and account policies still apply. Nexa does not save prompts or responses to disk.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary).lineSpacing(3)
            if let message { Text(message).font(.system(size: 11)).foregroundStyle(preferences.value.accent.color) }
        }
    }
}

struct AboutSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 20) { BrandMark(size: 76, accent: preferences.value.accent.color); VStack(alignment: .leading, spacing: 6) { Text("Nexa").font(.system(size: 29, weight: .semibold, design: .rounded)); Text("Version 0.4.2 · Native for macOS 15+").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary); Text("A little less in your way.").font(.system(size: 12)).foregroundStyle(preferences.value.accent.color) } }.padding(.vertical, 15)
            SettingsGroup(title: "OPEN BY DESIGN") {
                Text("Original Swift, SwiftUI and AppKit implementation. No proprietary assets. Includes the BSD-licensed MediaRemote Adapter by Jonas van den Berg and contributors for system-wide media. Source is included with this build under the MIT license. Apple system symbols remain subject to Apple’s terms.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineSpacing(4)
                TextField("Repository URL (optional)", text: $preferences.value.repositoryURL).textFieldStyle(.roundedBorder)
                if let url = URL(string: preferences.value.repositoryURL), url.scheme == "https" { Link("Open repository ↗", destination: url).font(.system(size: 11)) }
                Text("Source code and release downloads are available on GitHub. Updates are checked only when you ask.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            }
            UpdateSettingsView(service: model.updater, preferences: preferences)
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var service: UpdateService
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        SettingsGroup(title: "UPDATES, WHEN YOU CHOOSE") {
            TextField("HTTPS release feed URL (optional)", text: $preferences.value.updateFeedURL).textFieldStyle(.roundedBorder)
            HStack { Button("Check for updates") { service.check(feed: preferences.value.updateFeedURL, allowed: !preferences.value.localOnly) }.disabled(service.busy); if let url = service.releaseURL { Link("View release ↗", destination: url) } }.font(.system(size: 11))
            Text(service.message).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            Text("Updates are downloaded and installed by you. Nexa never replaces its own executable.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
        }
    }
}
