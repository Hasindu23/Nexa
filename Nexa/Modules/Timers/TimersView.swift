import SwiftUI

struct TimersView: View {
    @ObservedObject var service: TimerService
    let accent: Color
    @State private var mode = 0
    @State private var minutes = "25"
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Time, on your terms.").font(.system(size: 21, weight: .medium)).tracking(-0.5); Spacer(); Picker("Mode", selection: $mode) { Text("Timer").tag(0); Text("Stopwatch").tag(1) }.pickerStyle(.segmented).frame(width: 173).labelsHidden() }
            HStack(spacing: 32) {
                ZStack {
                    Circle().stroke(.white.opacity(0.07), lineWidth: 5)
                    Circle().trim(from: 0, to: mode == 0 ? max(0.005, service.progress) : 1).stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 7) { Text(mode == 0 ? service.remaining.clockString : service.stopwatch.clockString).font(.system(size: 31, weight: .light, design: .rounded)).monospacedDigit(); Text(mode == 0 ? service.running ? "MAKE A LITTLE SPACE" : "READY WHEN YOU ARE" : "ONE MOMENT AT A TIME").font(.system(size: 6.5, weight: .semibold)).tracking(1.2).foregroundStyle(NexaStyle.secondary) }
                }.frame(width: 151, height: 151)
                VStack(alignment: .leading, spacing: 14) {
                    if mode == 0 {
                        Text("A MOMENT FOR…").font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(NexaStyle.secondary)
                        HStack(spacing: 7) { ForEach([5, 15, 25], id: \.self) { value in Button("\(value)m") { service.startTimer(seconds: Double(value) * 60) }.buttonStyle(CapsuleButtonStyle(accent: accent)) } }
                        HStack { TextField("Minutes", text: $minutes).textFieldStyle(.roundedBorder).frame(width: 60); Text("min").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary); Button("Set") { if let value = Double(minutes), value > 0 { service.startTimer(seconds: value * 60) } }.buttonStyle(CapsuleButtonStyle(accent: accent)).disabled(Double(minutes).map { !$0.isFinite || $0 <= 0 || $0 > 1440 } ?? true) }
                    } else { Text("No rush.\nJust a little focus.").font(.system(size: 21, weight: .light)).foregroundStyle(NexaStyle.secondary).lineSpacing(4) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.top, 5)
            HStack(spacing: 10) {
                Button(mode == 0 ? service.running ? "Pause timer" : "Start timer" : service.stopwatchRunning ? "Pause stopwatch" : "Start stopwatch") { if mode == 0 { service.toggle() } else { service.toggleStopwatch() } }.buttonStyle(CapsuleButtonStyle(accent: accent, filled: true))
                Button("Reset") { if mode == 0 { service.reset() } else { service.resetStopwatch() } }.buttonStyle(CapsuleButtonStyle())
            }
        }
    }
}
