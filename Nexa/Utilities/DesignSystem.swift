import SwiftUI
import AppKit

enum NexaStyle {
    static let canvas = Color(red: 0.055, green: 0.060, blue: 0.065)
    static let surface = Color.white.opacity(0.045)
    static let line = Color.white.opacity(0.075)
    static let secondary = Color.white.opacity(0.48)
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(16).background(NexaStyle.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NexaStyle.line, lineWidth: 1)) }
}

struct CapsuleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nexaMotion) private var motion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var accent = Color.white
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 9)
            .foregroundStyle(filled ? Color.black : accent)
            .background(filled ? accent : Color.white.opacity(configuration.isPressed ? 0.13 : hovered && enabled ? 0.10 : 0.07), in: Capsule())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && !motion.reduced ? 0.97 : 1)
            .animation(reduceMotion || motion.reduced ? nil : .easeOut(duration: motion.buttonDuration), value: configuration.isPressed)
            .animation(reduceMotion || motion.reduced ? nil : .easeOut(duration: motion.hoverDuration), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 30
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: size, height: size).background(Color.white.opacity(0.06), in: Circle()) }
            .buttonStyle(NotchButtonStyle()).help(help).accessibilityLabel(help)
    }
}

struct EmptyModule: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 27, weight: .light)).foregroundStyle(.white.opacity(0.65)).frame(width: 62, height: 62).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.system(size: 19, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(NexaStyle.secondary).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 330)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}

struct InlineError: View {
    let text: String?
    var body: some View { if let text { Label(text, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.orange.opacity(0.9)).fixedSize(horizontal: false, vertical: true).padding(.vertical, 5) } }
}

struct VisualEffect: NSViewRepresentable {
    var intensity: Double
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.alphaValue = intensity }
}

struct BrandMark: View {
    var size: CGFloat = 32
    var accent = Accent.mint.color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(accent.opacity(0.12))
            HStack(spacing: size * 0.09) {
                Capsule().fill(accent).frame(width: size * 0.12, height: size * 0.38).rotationEffect(.degrees(-25))
                Capsule().fill(accent).frame(width: size * 0.12, height: size * 0.58).rotationEffect(.degrees(-25))
                Capsule().fill(accent).frame(width: size * 0.12, height: size * 0.38).rotationEffect(.degrees(-25))
            }
        }.frame(width: size, height: size)
    }
}

struct SharePicker: NSViewRepresentable {
    let items: [Any]
    @Binding var presented: Bool
    final class Coordinator { var scheduled = false }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        guard presented, !items.isEmpty, !context.coordinator.scheduled else { return }
        context.coordinator.scheduled = true
        DispatchQueue.main.async {
            defer { context.coordinator.scheduled = false }
            guard presented, view.window != nil, !view.isHiddenOrHasHiddenAncestor else { return }
            NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            presented = false
        }
    }
}

struct NotchButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nexaMotion) private var motion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!enabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && !motion.reduced ? 0.96 : 1)
            .animation(reduceMotion || motion.reduced ? nil : .easeOut(duration: motion.buttonDuration), value: configuration.isPressed)
    }
}
