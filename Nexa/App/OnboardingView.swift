import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: PreferencesStore
    let finish: () -> Void
    @State private var step = 0
    private let titles = ["A little more space.", "Right where you need it.", "Permission, on your terms.", "Pick up where you copied.", "A little ahead of your day.", "There when you arrive.", "Make yourself at home.", "Less reaching. More doing."]
    private let details = ["Meet Nexa. A quiet home for your music, files and everyday essentials, right at the top of your Mac.", "Hover or click the notch to open. Move away to tuck it back. Drop files into the shelf, then drag them out wherever you need them.", "Nexa starts local-only. There are no accounts, analytics or license servers. You choose which connections to enable, when you need them.", "Clipboard history is optional and off by default. If enabled, copies are saved locally. You can pause capture or clear everything at any time.", "See what’s next without leaving what you’re doing. Calendar and Reminders are optional, and each asks for its own permission.", "Let Nexa settle in when you log in. You can change this later in Settings. For the best experience, keep Nexa in your Applications folder.", "A quiet palette. One personal detail. Choose an accent that makes this little space yours.", "You’re all set. Find Nexa at the top of your screen, or use its menu bar icon. This is your space now."]
    private var accent: Color { preferences.value.accent.color }
    var body: some View {
        VStack(spacing: 0) {
            HStack { BrandMark(size: 26, accent: accent); Text("nexa").font(.system(size: 16, weight: .semibold, design: .rounded)); Spacer(); Text("WELCOME / \(String(format: "%02d", step + 1))").font(.system(size: 8, weight: .semibold)).tracking(2).foregroundStyle(NexaStyle.secondary) }.padding(30)
            Spacer(minLength: 10)
            ZStack {
                Circle().stroke(accent.opacity(0.04), lineWidth: 1).frame(width: 235, height: 235)
                Circle().stroke(accent.opacity(0.07), lineWidth: 1).frame(width: 187, height: 187)
                RoundedRectangle(cornerRadius: 23).fill(.black).frame(width: 270, height: 115).overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.12)))
                HStack(spacing: 22) { BrandMark(size: 55, accent: accent); VStack(alignment: .leading, spacing: 10) { Text(step == 7 ? "Hello, you." : "A place for your flow.").font(.system(size: 15, weight: .medium)); HStack(spacing: 18) { ForEach(["waveform", "tray", "timer", "sparkle"], id: \.self) { Image(systemName: $0).font(.system(size: 13)).foregroundStyle(accent.opacity(0.65)) } } } }
            }.frame(height: 155)
            VStack(spacing: 13) {
                Text(titles[step]).font(.system(size: 30, weight: .medium)).tracking(-0.9)
                Text(details[step]).font(.system(size: 13)).foregroundStyle(NexaStyle.secondary).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 410)
            }.padding(.top, 25)
            Group {
                switch step {
                case 1: Button("Try the notch") { model.setExpanded?(true) }.buttonStyle(CapsuleButtonStyle(accent: accent))
                case 3: Toggle("Enable local clipboard history", isOn: $preferences.value.clipboardEnabled).toggleStyle(.switch).font(.system(size: 12)).fixedSize()
                case 4: OnboardingPermissions(service: model.calendar, accent: accent)
                case 5: LoginSetting(service: model.controls).frame(width: 360)
                case 6: HStack(spacing: 17) { ForEach(Accent.allCases, id: \.self) { color in Button { preferences.value.accent = color } label: { Circle().fill(color.color).frame(width: 30, height: 30).overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black).opacity(preferences.value.accent == color ? 1 : 0)) }.buttonStyle(.plain).accessibilityLabel(color.rawValue) } }
                default: Label(step == 2 ? "No data leaves your Mac by default" : "Designed to stay out of your way", systemImage: step == 2 ? "lock.shield" : "sparkle").font(.system(size: 11)).foregroundStyle(accent.opacity(0.75))
                }
            }.frame(height: 60).padding(.top, 8)
            Spacer()
            HStack {
                Button(step == 0 ? "Set up later" : "Back") { if step == 0 { finish() } else { withAnimation { step -= 1 } } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(NexaStyle.secondary).frame(width: 90, alignment: .leading)
                Spacer()
                HStack(spacing: 5) { ForEach(0..<8) { index in Capsule().fill(index == step ? accent : .white.opacity(0.15)).frame(width: index == step ? 16 : 4, height: 4) } }
                Spacer()
                Button(step == 7 ? "Meet your Nexa  ↗" : "Continue  →") { if step == 7 { finish() } else { withAnimation(.easeInOut(duration: 0.2)) { step += 1 } } }.buttonStyle(CapsuleButtonStyle(accent: accent, filled: true)).keyboardShortcut(.defaultAction)
            }.padding(30)
        }.frame(width: 600, height: 630).background(NexaStyle.canvas).foregroundStyle(.white).tint(accent).preferredColorScheme(.dark)
    }
}

struct OnboardingPermissions: View {
    @ObservedObject var service: CalendarService
    let accent: Color
    var body: some View { HStack { Button(service.calendarAccess ? "Calendar connected ✓" : "Connect Calendar") { Task { await service.requestCalendar() } }.disabled(service.calendarAccess); Button(service.reminderAccess ? "Reminders connected ✓" : "Connect Reminders") { Task { await service.requestReminders() } }.disabled(service.reminderAccess) }.buttonStyle(CapsuleButtonStyle(accent: accent)) }
}
