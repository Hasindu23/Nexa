import AppKit
import SwiftUI
import QuartzCore

enum ElectricBluePalette {
    static let waveform = NSColor(srgbRed: 141 / 255, green: 187 / 255, blue: 249 / 255, alpha: 1)
    static let highlight = NSColor(srgbRed: 196 / 255, green: 225 / 255, blue: 1, alpha: 1)
    static let accent = NSColor(srgbRed: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
    static let royal = NSColor(srgbRed: 8 / 255, green: 32 / 255, blue: 166 / 255, alpha: 1)
    static let dark = NSColor(srgbRed: 6 / 255, green: 25 / 255, blue: 155 / 255, alpha: 1)
}

struct VisualizerConfiguration: Equatable {
    var playing: Bool
    var style: VisualizerStyle
    var brightness: Double
    var glow: Bool
    var glowIntensity: Double
    var reduced: Bool
    var energySaving: Bool
    var enabled: Bool
    init(playing: Bool, preferences: AppPreferences, systemReduceMotion: Bool = false, enabled: Bool = true) {
        self.playing = playing; style = preferences.visualizerStyle
        brightness = preferences.visualizerBrightness.isFinite ? min(1, max(0.1, preferences.visualizerBrightness)) : 0.8
        glow = preferences.ambientBlueGlow
        glowIntensity = preferences.glowIntensity.isFinite ? min(1, max(0, preferences.glowIntensity)) : 0.35
        reduced = systemReduceMotion || preferences.reduceMotion
        energySaving = preferences.energySaving; self.enabled = enabled
    }
    var animates: Bool { playing && enabled && !reduced && !energySaving }
}

/// Playback-state decoration only. This component never reads audio samples.
struct PlaybackPulse: View {
    let playing: Bool
    @ObservedObject var preferences: PreferencesStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        ElectricBlueVisualizer(configuration: VisualizerConfiguration(playing: playing, preferences: preferences.value,
                                                                       systemReduceMotion: systemReduceMotion, enabled: enabled))
            .accessibilityLabel("Decorative playback animation")
            .accessibilityValue(playing ? "Playing" : "Paused")
            .help("Decorative playback animation. No audio is captured or analyzed.")
    }
}

struct ElectricBlueVisualizer: NSViewRepresentable {
    let configuration: VisualizerConfiguration
    func makeNSView(context: Context) -> ElectricBlueVisualizerView { ElectricBlueVisualizerView() }
    func updateNSView(_ view: ElectricBlueVisualizerView, context: Context) { view.configure(configuration) }
    static func dismantleNSView(_ view: ElectricBlueVisualizerView, coordinator: ()) { view.stopAnimations() }
}

final class ElectricBlueVisualizerView: NSView {
    private let content = CALayer()
    private let glow = CAGradientLayer()
    private(set) var bars: [CALayer] = []
    private(set) var configuration = VisualizerConfiguration(playing: false, preferences: AppPreferences())
    private var lastBounds = CGRect.zero
    private var observation: NSObjectProtocol?
    private var running = false
    var repeatingAnimationCount: Int { bars.filter { $0.animation(forKey: "blue.height") != nil }.count + (glow.animation(forKey: "blue.glow") == nil ? 0 : 1) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.addSublayer(glow); layer?.addSublayer(content)
        glow.type = .radial; glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
        glow.colors = [ElectricBluePalette.royal.withAlphaComponent(0.8).cgColor, ElectricBluePalette.dark.withAlphaComponent(0.25).cgColor, NSColor.clear.cgColor]
        glow.locations = [0, 0.45, 1]
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Decorative playback animation")
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil
        if let window {
            observation = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateActivity() }
            }
        }
        updateActivity()
    }
    override func viewDidHide() { super.viewDidHide(); updateActivity() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateActivity() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for bar in bars { bar.contentsScale = window?.backingScaleFactor ?? 2 }
    }
    override func layout() {
        super.layout()
        guard bounds != lastBounds || bars.isEmpty else { return }
        lastBounds = bounds; rebuildBars(); updateActivity(force: true)
    }
    func configure(_ value: VisualizerConfiguration) {
        guard value != configuration else { updateActivity(); return }
        let changedStyle = value.style != configuration.style
        configuration = value
        if changedStyle || bars.isEmpty { rebuildBars() }
        updateActivity(force: true)
    }
    private func rebuildBars() {
        stopAnimations(); bars.forEach { $0.removeFromSuperlayer() }; bars.removeAll()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.frame = bounds; glow.frame = bounds.insetBy(dx: -bounds.width * 0.2, dy: -bounds.height * 0.35)
        let count = configuration.style == .minimal ? 3 : configuration.style == .wave ? 19 : 9
        let available = max(1, bounds.width * 0.82), spacing = available / CGFloat(count)
        let width = max(0.7, spacing * (configuration.style == .wave ? 0.55 : 0.58))
        let height = max(1, bounds.height * 0.72)
        for index in 0..<count {
            let bar = CALayer()
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.position = CGPoint(x: (bounds.width - available) / 2 + spacing * (CGFloat(index) + 0.5), y: bounds.height / 2)
            bar.cornerRadius = width / 2
            bar.backgroundColor = (index % 4 == 2 ? ElectricBluePalette.highlight : ElectricBluePalette.waveform).cgColor
            bar.contentsScale = window?.backingScaleFactor ?? 2
            content.addSublayer(bar); bars.append(bar)
        }
        CATransaction.commit()
    }
    func updateActivity(force: Bool = false) {
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        let shouldAnimate = configuration.animates && visible && !bounds.isEmpty
        guard force || shouldAnimate != running else { return }
        let previousOpacity = content.presentation()?.opacity ?? content.opacity
        let previousGlow = glow.presentation()?.opacity ?? glow.opacity
        stopAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.opacity = Float(configuration.brightness * (configuration.playing ? 1 : 0.32))
        glow.opacity = configuration.playing && configuration.glow ? Float(configuration.glowIntensity * 0.55) : 0
        for (index, bar) in bars.enumerated() {
            let rest = configuration.playing ? 0.32 + Double(index % 4) * 0.12 : 0.18
            bar.transform = CATransform3DMakeScale(1, rest, 1); bar.opacity = 1
        }
        if visible && !configuration.reduced && !configuration.energySaving && previousOpacity != content.opacity {
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = previousOpacity; fade.toValue = content.opacity
            fade.duration = 0.18; content.add(fade, forKey: "blue.fade")
        }
        if visible && !configuration.reduced && !configuration.energySaving && previousGlow != glow.opacity {
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = previousGlow; fade.toValue = glow.opacity
            fade.duration = 0.25; glow.add(fade, forKey: "blue.fade")
        }
        if shouldAnimate {
            for (index, bar) in bars.enumerated() {
                let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
                let phase = Double(index) * 1.37
                animation.values = (0...32).map { step -> NSNumber in
                    let t = Double(step) / 32 * .pi * 2
                    let wave = configuration.style == .wave ? sin(t + Double(index) * 0.42) : sin(t + phase) * 0.65 + sin(2 * t - phase * 0.7) * 0.35
                    return NSNumber(value: 0.20 + (wave + 1) * (configuration.style == .minimal ? 0.25 : 0.37))
                }
                animation.duration = configuration.style == .wave ? 4.8 : 3.7 + Double(index % 7) * 0.39
                animation.repeatCount = .infinity; animation.calculationMode = .cubic
                // Shared media time keeps unrelated metadata updates from resetting phase.
                animation.beginTime = 0; bar.add(animation, forKey: "blue.height")
                let shimmer = CABasicAnimation(keyPath: "opacity"); shimmer.fromValue = 0.72; shimmer.toValue = 1
                shimmer.duration = 2.1 + Double(index % 5) * 0.31; shimmer.autoreverses = true; shimmer.repeatCount = .infinity
                shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); bar.add(shimmer, forKey: "blue.brightness")
            }
            if configuration.glow && configuration.glowIntensity > 0 {
                let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = glow.opacity * 0.7; pulse.toValue = glow.opacity
                pulse.duration = 3.8; pulse.autoreverses = true; pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); glow.add(pulse, forKey: "blue.glow")
            }
        }
        running = shouldAnimate
        CATransaction.commit()
    }
    func stopAnimations() {
        running = false; content.removeAllAnimations(); glow.removeAllAnimations()
        bars.forEach { $0.removeAllAnimations() }
    }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
}
