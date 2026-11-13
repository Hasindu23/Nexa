import AppKit
import SwiftUI

enum NexaAccessibility {
    // Only the isolated native QA runner sets these; normal launches use macOS.
    static var qaReduceTransparency: Bool?
    static var qaIncreaseContrast: Bool?
    static var reduceTransparency: Bool { qaReduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    static var increaseContrast: Bool { qaIncreaseContrast ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}

/// One policy shared by native glass and the macOS 15 material fallback.
struct NexaGlassEnvironment: Equatable {
    enum Backend: Equatable { case native, visualEffect, opaque }
    let backend: Backend
    let tintAlpha: Double
    let borderAlpha: Double
    let interactive: Bool
    init(preferences: AppPreferences, nativeAvailable: Bool, reduceTransparency: Bool, increaseContrast: Bool, active: Bool = true) {
        if !active || reduceTransparency || preferences.energySaving || preferences.appearanceMode == .classicBlack {
            backend = .opaque
        } else { backend = nativeAvailable ? .native : .visualEffect }
        let styleTint: Double = preferences.glassStyle == .clear ? 0.18 : preferences.glassStyle == .tinted ? 0.52 : 0.34
        tintAlpha = backend == .opaque ? 1 : min(0.72, styleTint + preferences.glassTintStrength * 0.18)
        borderAlpha = increaseContrast ? 0.65 : preferences.border ? (preferences.specularHighlight ? 0.20 : 0.12) : 0
        interactive = preferences.interactiveGlass && backend == .native && !preferences.reduceMotion
    }
}

@MainActor final class NexaGlassSurface: NSView {
    private let fallback = NSVisualEffectView()
    private let tint = NSView()
    private var native: NSView?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        fallback.material = .hudWindow; fallback.blendingMode = .behindWindow; fallback.state = .active
        addSubview(fallback)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(); glass.style = .regular
            glass.contentView = NSView()
            addSubview(glass); native = glass
        }
        tint.wantsLayer = true; addSubview(tint)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); fallback.frame = bounds; native?.frame = bounds; tint.frame = bounds }
    func configure(_ preferences: AppPreferences, active: Bool, radius: CGFloat) {
        appearance = NSAppearance(named: .darkAqua)
        let accessibility = NSWorkspace.shared
        let policy = NexaGlassEnvironment(preferences: preferences, nativeAvailable: native != nil,
            reduceTransparency: NexaAccessibility.reduceTransparency,
            increaseContrast: NexaAccessibility.increaseContrast, active: active)
        fallback.isHidden = policy.backend != .visualEffect
        native?.isHidden = policy.backend != .native
        if #available(macOS 26.0, *), let glass = native as? NSGlassEffectView {
            glass.cornerRadius = radius
            glass.style = preferences.glassStyle == .clear ? .clear : .regular
            glass.tintColor = preferences.blueReflection ? NSColor(red: 0.04, green: 0.09, blue: 0.19, alpha: 0.12) : nil
            if #available(macOS 27.0, *) { glass.effectIsInteractive = policy.interactive && !accessibility.accessibilityDisplayShouldReduceMotion }
        }
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(policy.tintAlpha).cgColor
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct NexaGlassBackground: NSViewRepresentable {
    var preferences: AppPreferences
    var radius: CGFloat = 24
    func makeNSView(context: Context) -> NexaGlassSurface { NexaGlassSurface() }
    func updateNSView(_ view: NexaGlassSurface, context: Context) { view.configure(preferences, active: true, radius: radius) }
}
