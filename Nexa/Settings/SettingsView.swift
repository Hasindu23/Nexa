import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    @State private var selection = "General"
    private let sections = [("General", "switch.2"), ("Appearance", "paintpalette"), ("Modules", "square.grid.2x2"), ("Gestures", "cursorarrow.motionlines"), ("Privacy", "hand.raised"), ("Weather", "cloud.sun"), ("Assistant", "sparkles"), ("About", "info.circle")]
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) { BrandMark(size: 34, accent: accent); VStack(alignment: .leading, spacing: 2) { Text("nexa").font(.system(size: 20, weight: .semibold, design: .rounded)); Text("A little more space.").font(.system(size: 9)).foregroundStyle(NexaStyle.secondary) } }.padding(.bottom, 26).padding(.top, 23)
                ForEach(sections, id: \.0) { section in
                    Button { selection = section.0 } label: {
                        HStack(spacing: 10) { Image(systemName: section.1).frame(width: 18); Text(section.0); Spacer() }.font(.system(size: 12, weight: selection == section.0 ? .medium : .regular)).foregroundStyle(selection == section.0 ? accent : .white.opacity(0.52)).padding(.horizontal, 13).padding(.vertical, 11).background(selection == section.0 ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.\(section.0.lowercased())")
                }
                Spacer()
                HStack(spacing: 6) { Circle().fill(accent).frame(width: 4, height: 4); Text("MADE FOR YOUR MAC").font(.system(size: 7, weight: .semibold)).tracking(1.4) }.foregroundStyle(NexaStyle.secondary).padding(12)
            }.padding(.horizontal, 17).padding(.top, 18).padding(.bottom, 12).frame(width: 202).background(Color.black.opacity(0.25))
            Rectangle().fill(NexaStyle.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) { Text(selection).font(.system(size: 30, weight: .medium)).tracking(-0.8); Text(subtitle).font(.system(size: 12)).foregroundStyle(NexaStyle.secondary) }.padding(.top, 37).padding(.bottom, 4)
                    content
                    Spacer(minLength: 20)
                }.padding(.horizontal, 35).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
        }.frame(minWidth: 820, minHeight: 610).background(NexaStyle.canvas).foregroundStyle(.white).tint(accent).preferredColorScheme(.dark)
    }
    private var subtitle: String {
        switch selection {
        case "General": return "Settle into a setup that feels like you."
        case "Appearance": return "Quiet by design. Yours in the details."
        case "Modules": return "Keep what’s useful. Give the rest some space."
        case "Gestures": return "A small movement. Just the right response."
        case "Privacy": return "Your Mac. Your data. Your decision."
        case "Weather": return "A little context for the world outside."
        case "Assistant": return "A second thought, only when you ask."
        default: return "An original little home at the top of your screen."
        }
    }
    @ViewBuilder private var content: some View {
        switch selection {
        case "General": general
        case "Appearance": appearance
        case "Modules": modules
        case "Gestures": gestures
        case "Privacy": PrivacySettingsView(model: model, preferences: preferences)
        case "Weather": weather
        case "Assistant": AssistantSettingsView(preferences: preferences)
        default: AboutSettingsView(model: model, preferences: preferences)
        }
    }
    private var general: some View {
        VStack(spacing: 17) {
            SettingsGroup(title: "AT HOME ON YOUR MAC") {
                LoginSetting(service: model.controls)
                settingToggle("Show menu bar icon", detail: "Your quick way back to Nexa.", value: $preferences.value.showMenuBar)
                settingToggle("Follow across Spaces", detail: "Also join full-screen apps where macOS permits.", value: $preferences.value.allSpaces)
                settingToggle("Sound effects", detail: "A soft sound when a timer finishes.", value: $preferences.value.soundEffects)
            }
            SettingsGroup(title: "TIMING & POSITION") {
                settingSlider("Animation speed", value: $preferences.value.animationSpeed, range: 0.5...2, label: String(format: "%.1f×", preferences.value.animationSpeed))
                settingSlider("Hover delay", value: $preferences.value.hoverDelay, range: 0...1.5, label: String(format: "%.2fs", preferences.value.hoverDelay))
                settingSlider("Auto-collapse delay", value: $preferences.value.collapseDelay, range: 0.2...3, label: String(format: "%.1fs", preferences.value.collapseDelay))
                settingSlider("Notch width", value: $preferences.value.notchWidth, range: 0...300, label: preferences.value.notchWidth == 0 ? "Auto" : "\(Int(preferences.value.notchWidth)) pt")
                settingSlider("Pill position", value: $preferences.value.horizontalOffset, range: -400...400, label: "\(Int(preferences.value.horizontalOffset)) pt")
                Text("Position adjustment applies to displays without a hardware notch. Set notch width to 0 for automatic detection.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            }
            HStack { Button("Open Nexa") { model.setExpanded?(true) }; Spacer(); Button("Replay welcome") { model.showOnboarding?() } }.buttonStyle(CapsuleButtonStyle(accent: accent))
        }
    }
    private var appearance: some View {
        VStack(spacing: 18) {
            HStack { Spacer(); VStack(spacing: 0) { HStack { BrandMark(size: 18, accent: accent); Spacer(); Text("YOUR SPACE").font(.system(size: 7, weight: .semibold)).tracking(2).foregroundStyle(NexaStyle.secondary) }.padding(15); HStack(spacing: 13) { RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.18)).frame(width: 52, height: 52).overlay(Image(systemName: "waveform").foregroundStyle(accent)); VStack(alignment: .leading, spacing: 7) { Capsule().fill(.white.opacity(0.65)).frame(width: 108, height: 5); Capsule().fill(.white.opacity(0.17)).frame(width: 78, height: 4) }; Spacer(); Image(systemName: "play.fill").foregroundStyle(accent) }.padding([.horizontal, .bottom], 18) }.frame(width: 330).background(.black.opacity(preferences.value.opacity), in: RoundedRectangle(cornerRadius: preferences.value.cornerRadius)).overlay(RoundedRectangle(cornerRadius: preferences.value.cornerRadius).strokeBorder(.white.opacity(preferences.value.border ? 0.12 : 0))).shadow(color: .black.opacity(preferences.value.shadow ? 0.4 : 0), radius: 20, y: 12); Spacer() }.padding(.vertical, 24)
            SettingsGroup(title: "HOME WIDGETS") {
                Picker("Center widget", selection: $preferences.value.centerWidget) { ForEach(["Calendar", "Shortcuts", "Notes", "To-dos", "Timer"], id: \.self) { Text($0) } }
                Picker("Display", selection: $preferences.value.preferredDisplay) { Text("Automatic").tag("Automatic"); ForEach(NSScreen.screens, id: \.localizedName) { Text($0.localizedName).tag($0.localizedName) } }
                Text("Home keeps media, your chosen widget and Mirror side by side. Use the grid button for all widgets.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            }
            SettingsGroup(title: "THE DETAILS") {
                HStack { Text("Accent color").font(.system(size: 12)); Spacer(); ForEach(Accent.allCases, id: \.self) { color in Button { preferences.value.accent = color } label: { Circle().fill(color.color).frame(width: 23, height: 23).overlay(Circle().strokeBorder(.black, lineWidth: preferences.value.accent == color ? 5 : 0)).overlay(Circle().strokeBorder(color.color, lineWidth: 2)) }.buttonStyle(.plain).help(color.rawValue.capitalized).accessibilityLabel(color.rawValue) } }
                Divider()
                HStack { Text("Layout size").font(.system(size: 12)); Spacer(); Picker("Layout", selection: $preferences.value.layout) { ForEach(["Compact", "Normal", "Large"], id: \.self) { Text($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 240) }
                settingSlider("Opacity", value: $preferences.value.opacity, range: 0.65...1, label: "\(Int(preferences.value.opacity * 100))%")
                settingSlider("Background blur", value: $preferences.value.blur, range: 0...1, label: "\(Int(preferences.value.blur * 100))%")
                settingSlider("Corner radius", value: $preferences.value.cornerRadius, range: 12...36, label: "\(Int(preferences.value.cornerRadius)) pt")
                settingToggle("Soft shadow", value: $preferences.value.shadow)
                settingToggle("Subtle border", value: $preferences.value.border)
                Text("Nexa uses a dark appearance to blend with the hardware notch. Reduce Motion follows your macOS accessibility setting.").font(.system(size: 10)).foregroundStyle(NexaStyle.secondary)
            }
        }
    }
    private var modules: some View {
        SettingsGroup(title: "YOUR EVERYDAY ESSENTIALS") {
            ForEach(ModuleID.allCases.filter { $0 != .home }) { module in
                HStack(spacing: 12) { Image(systemName: module.icon).foregroundStyle(accent).frame(width: 23); Text(module.title).font(.system(size: 12)); Spacer(); if module == .ai || module == .weather { Text("OPTIONAL NETWORK").font(.system(size: 7, weight: .medium)).tracking(0.8).foregroundStyle(NexaStyle.secondary) }; Toggle(module.title, isOn: Binding(get: { preferences.value.enabledModules.contains(module) }, set: { preferences.toggle(module, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.small) }.padding(.vertical, 3)
                if module != ModuleID.allCases.last { Divider() }
            }
        }
    }
    private var gestures: some View {
        SettingsGroup(title: "HOW NEXA RESPONDS") {
            settingToggle("Haptic feedback", detail: "A subtle trackpad tap when the notch opens or closes.", value: $preferences.value.hapticFeedback)
            settingToggle("Hover to open", detail: "Rest your pointer over the notch or pill.", value: $preferences.value.hoverToOpen)
            settingToggle("Click to open", value: $preferences.value.clickToOpen)
            settingToggle("Drag and drop", detail: "Bring files, images and text to the notch.", value: $preferences.value.dragAndDrop)
            settingToggle("Right-click menu", value: $preferences.value.rightClickMenu)
            settingToggle("Scroll to switch modules", detail: "Replaces content scrolling while over the notch.", value: $preferences.value.scrollCyclesModules)
            Text("Swipe horizontally over Nexa to change tracks, or vertically to open and close. Press Escape to collapse. Opening on hover leaves your current app focused; click an input to type.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineSpacing(3)
        }
    }
    private var weather: some View {
        SettingsGroup(title: "A LOCATION YOU CHOOSE") {
            TextField("Display name", text: $preferences.value.weatherLocation).textFieldStyle(.roundedBorder)
            HStack { TextField("Latitude (−90 to 90)", text: $preferences.value.weatherLatitude); TextField("Longitude (−180 to 180)", text: $preferences.value.weatherLongitude) }.textFieldStyle(.roundedBorder)
            settingToggle("Use Fahrenheit", value: $preferences.value.fahrenheit)
            TextField("Open-Meteo-compatible HTTPS endpoint", text: $preferences.value.weatherEndpoint).textFieldStyle(.roundedBorder)
            Text("Uses Open-Meteo on manual refresh. Only these coordinates are sent; Nexa never asks for your live location. Enable Weather in Modules and turn off Local-only mode to use it. Open-Meteo’s free service is for non-commercial use.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).lineSpacing(4)
            Link("Open-Meteo terms & attribution ↗", destination: URL(string: "https://open-meteo.com/en/terms")!).font(.system(size: 11))
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 13) { Text(title).font(.system(size: 8, weight: .semibold)).tracking(1.7).foregroundStyle(NexaStyle.secondary); VStack(alignment: .leading, spacing: 15) { content }.padding(19).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(NexaStyle.line)) } }
}

@MainActor func settingToggle(_ title: String, detail: String? = nil, value: Binding<Bool>) -> some View {
    HStack { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 12)); if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(NexaStyle.secondary) } }; Spacer(); Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small) }
}

@MainActor func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
    HStack { Text(title).font(.system(size: 12)).frame(width: 126, alignment: .leading); Slider(value: value, in: range).controlSize(.small); Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(NexaStyle.secondary).frame(width: 55, alignment: .trailing) }
}

struct LoginSetting: View {
    @ObservedObject var service: QuickControlsService
    var body: some View { VStack(alignment: .leading, spacing: 5) { settingToggle("Launch at login", detail: "A familiar space, every time you start.", value: Binding(get: { service.loginEnabled }, set: { service.login($0) })); InlineError(text: service.error) } }
}
