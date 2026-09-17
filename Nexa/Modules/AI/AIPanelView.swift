import SwiftUI

struct AIPanelView: View {
    @ObservedObject var service: AIService
    @ObservedObject var preferences: PreferencesStore
    @State private var action = "Summarize"
    @State private var language = "English"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("A second thought.").font(.system(size: 21, weight: .medium)); Spacer(); Button("Clear") { service.clear() }.buttonStyle(.plain).font(.system(size: 10)) }
            Text("Only the text below is sent to OpenAI when you press Send. Your API account is billed by OpenAI.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            HStack {
                Picker("Action", selection: $action) { ForEach(["Summarize", "Rewrite", "Explain", "Translate"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 135)
                if action == "Translate" { TextField("Language", text: $language).textFieldStyle(.roundedBorder) }
                Spacer()
                Button("Paste clipboard") { service.input = NSPasteboard.general.string(forType: .string) ?? "" }.font(.system(size: 10))
            }
            TextEditor(text: $service.input).font(.system(size: 12)).scrollContentBackground(.hidden).padding(8).frame(height: 75).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Label(preferences.value.localOnly ? "Local-only mode is on" : "Sent only when you choose", systemImage: "lock").font(.system(size: 9)).foregroundStyle(NexaStyle.secondary)
                Spacer()
                if service.busy { Button("Cancel") { service.cancel() }.buttonStyle(CapsuleButtonStyle()) }
                else { Button("Send  ↑") { service.send(action: action == "Translate" ? "Translate to \(language)." : "\(action) the supplied text.", model: preferences.value.aiModel, allowed: !preferences.value.localOnly && preferences.value.enabledModules.contains(.ai)) }.buttonStyle(CapsuleButtonStyle(accent: preferences.value.accent.color, filled: true)).disabled(service.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preferences.value.localOnly) }
            }
            if !service.output.isEmpty { Text(service.output).font(.system(size: 12)).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 11)); Button("Copy response") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(service.output, forType: .string) }.font(.system(size: 10)) }
            InlineError(text: service.error)
        }
    }
}
