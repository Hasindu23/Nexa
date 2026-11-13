import AppKit
import SwiftUI
import QuartzCore

/// Widgets keep their final layout while Core Animation morphs only the shell
/// and fades its two content layers. The native window never resizes per frame.
@MainActor final class NotchSurfaceView: NSView {
    override var isFlipped: Bool { true }
    let expandedHost: NotchHostingView
    let compactHost: NotchHostingView
    let peekHost: NotchHostingView
    let railHost: NSHostingView<WorkspaceRail>
    private let surface = FlippedSurface()
    private let backdrop = NexaGlassSurface()
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var tracking: NSTrackingArea?
    var onHover: ((Bool) -> Void)?
    private var lastPresentation = IslandPresentation.ambient
    private var canvasSize = CGSize.zero
    private var dropTarget = false
    private(set) var renderedSize = CGSize.zero
    private var settledState = NexaMorphState(width: 1, height: 1, radius: 14, shoulder: 0)
    private var morph: NexaMorph?
    private var morphStart: CFTimeInterval = 0

    private func currentState(at time: CFTimeInterval) -> NexaMorphState {
        morph?.sample(time - morphStart) ?? settledState
    }
    private func targetState(_ size: CGSize, expanded: Bool, hasNotch: Bool, preferences: AppPreferences) -> NexaMorphState {
        NexaMorphState(width: size.width, height: size.height, radius: expanded ? preferences.cornerRadius : 14, shoulder: hasNotch && expanded ? 15 : 0)
    }
    func requiredCanvas(target: CGSize, expanded: Bool, hasNotch: Bool, preferences: AppPreferences, duration: Double) -> CGSize {
        guard duration > 0 else { return target }
        let curve = NexaMorph(from: currentState(at: CACurrentMediaTime()), to: targetState(target, expanded: expanded, hasNotch: hasNotch, preferences: preferences), duration: duration, damping: NexaMotion(preferences: preferences).damping)
        let samples = curve.samples
        return CGSize(width: ceil(max(target.width, samples.map(\.width).max() ?? target.width)) + 2,
                      height: ceil(max(target.height, samples.map(\.height).max() ?? target.height)) + 2)
    }

    init(expanded: NotchView, compact: NotchView, peek: NotchView, rail: WorkspaceRail) {
        expandedHost = NotchHostingView(rootView: expanded)
        compactHost = NotchHostingView(rootView: compact)
        peekHost = NotchHostingView(rootView: peek)
        railHost = NSHostingView(rootView: rail)
        super.init(frame: .zero)
        wantsLayer = true; surface.wantsLayer = true
        addSubview(surface)
        surface.addSubview(backdrop)
        for host in [expandedHost, compactHost, peekHost] {
            host.safeAreaRegions = []; host.sizingOptions = []; host.wantsLayer = true
            surface.addSubview(host)
        }
        expandedHost.layer?.opacity = 0; expandedHost.isHidden = true
        expandedHost.acceptsInteraction = false
        peekHost.isHidden = true; peekHost.acceptsInteraction = false; peekHost.layer?.opacity = 0
        railHost.safeAreaRegions = []; railHost.sizingOptions = []; railHost.wantsLayer = true
        railHost.isHidden = true; railHost.layer?.opacity = 0; addSubview(railHost)
        surface.layer?.mask = maskLayer
        borderLayer.fillColor = nil; borderLayer.lineWidth = 1
        surface.layer?.addSublayer(borderLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        maskLayer.contentsScale = scale; borderLayer.contentsScale = scale
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    func render(canvas: CGSize, target: CGSize, expandedSize: CGSize, compactSize: CGSize, peekSize: CGSize,
                presentation: IslandPresentation, hasNotch: Bool, preferences: AppPreferences, module: ModuleID,
                duration: TimeInterval, completion: @escaping () -> Void) {
        let expanded = presentation.isOpen
        let now = CACurrentMediaTime()
        let current = currentState(at: now)
        let destination = targetState(target, expanded: expanded, hasNotch: hasNotch, preferences: preferences)
        let opening = presentation != lastPresentation && expanded, closing = !expanded && lastPresentation.isOpen
        let liftOrigin = expandedHost.isHidden ? -5.0 : (expandedHost.layer?.presentation()?.value(forKeyPath: "transform.translation.y") as? Double ?? 0)
        lastPresentation = presentation; canvasSize = canvas; renderedSize = target

        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = CGRect(origin: .zero, size: canvas)
        backdrop.frame = surface.bounds
        // A collapsed notch is opaque, so sampling the desktop behind it is wasted work.
        updateAppearance(expanded: expanded || closing && duration > 0, hasNotch: hasNotch, preferences: preferences)
        expandedHost.frame = CGRect(x: (canvas.width - expandedSize.width) / 2, y: 0, width: expandedSize.width, height: expandedSize.height)
        compactHost.frame = CGRect(x: (canvas.width - compactSize.width) / 2, y: 0, width: compactSize.width, height: compactSize.height)
        peekHost.frame = CGRect(x: (canvas.width - peekSize.width) / 2, y: 0, width: peekSize.width, height: peekSize.height)
        let railWidth = min(650, expandedSize.width - 28)
        railHost.frame = CGRect(x: (canvas.width - railWidth) / 2, y: target.height + WorkspaceLayout.railGap, width: railWidth, height: WorkspaceLayout.railHeight)
        let showRail = presentation == .workspace && preferences.showWorkspaceRail
        railHost.isHidden = false
        for host in [expandedHost, compactHost, peekHost] { host.isHidden = false }
        expandedHost.acceptsInteraction = presentation == .workspace
        compactHost.acceptsInteraction = presentation == .ambient
        peekHost.acceptsInteraction = presentation == .peek
        maskLayer.frame = surface.bounds; borderLayer.frame = surface.bounds
        let path = Self.path(size: target, canvasWidth: canvas.width, radius: expanded ? preferences.cornerRadius : 14, shoulder: hasNotch && expanded ? 15 : 0, detached: !hasNotch)
        maskLayer.path = path; borderLayer.path = path
        if duration > 0 {
            let curve = NexaMorph(from: current, to: destination, duration: duration, damping: NexaMotion(preferences: preferences).damping)
            morph = curve; morphStart = now
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = curve.samples.map { state in
                Self.path(size: CGSize(width: max(1, state.width), height: max(1, state.height)), canvasWidth: canvas.width,
                          radius: max(0, state.radius), shoulder: max(0, state.shoulder), detached: !hasNotch)
            }
            if let layer = railHost.layer {
                let railMotion = CAKeyframeAnimation(keyPath: "transform.translation.y")
                railMotion.values = curve.samples.map { $0.height - target.height }
                railMotion.duration = duration; railMotion.beginTime = now; railMotion.calculationMode = .linear
                layer.add(railMotion, forKey: "nexa.rail.position")
            }
            animation.duration = duration; animation.beginTime = now; animation.calculationMode = .linear
            maskLayer.add(animation, forKey: "nexa.morph"); borderLayer.add(animation, forKey: "nexa.morph")
        } else { morph = nil; maskLayer.removeAllAnimations(); borderLayer.removeAllAnimations() }
        settledState = destination
        animateOpacity(expandedHost.layer!, to: presentation == .workspace ? 1 : 0, duration: duration * (closing ? 0.34 : 0.8), delay: opening ? duration * 0.08 : 0)
        animateOpacity(compactHost.layer!, to: presentation == .ambient ? 1 : 0, duration: duration * 0.5, delay: closing ? duration * 0.32 : 0)
        animateOpacity(peekHost.layer!, to: presentation == .peek ? 1 : 0, duration: duration * 0.5, delay: 0)
        animateOpacity(railHost.layer!, to: showRail ? 1 : 0, duration: duration * (showRail ? 0.65 : 0.25), delay: showRail ? duration * 0.12 : 0)
        if opening, duration > 0 {
            let lift = CABasicAnimation(keyPath: "transform.translation.y")
            lift.fromValue = liftOrigin; lift.toValue = 0; lift.duration = duration
            lift.timingFunction = CAMediaTimingFunction(name: .easeOut)
            expandedHost.layer?.add(lift, forKey: "nexa.lift")
        } else if duration == 0 { expandedHost.layer?.removeAnimation(forKey: "nexa.lift") }
        CATransaction.commit()
        // Completion is generation-checked by the controller. Retargets sample
        // the same analytic trajectory used by the compositor, including velocity.
        if duration == 0 { finish(presentation: presentation); completion() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.015) { completion() } }
    }
    func finish(presentation: IslandPresentation) {
        morph = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        maskLayer.removeAllAnimations(); borderLayer.removeAllAnimations()
        for (host, state) in [(expandedHost, IslandPresentation.workspace), (compactHost, .ambient), (peekHost, .peek)] {
            host.layer?.removeAllAnimations(); host.layer?.opacity = state == presentation ? 1 : 0
            host.isHidden = state != presentation
        }
        railHost.layer?.removeAllAnimations(); railHost.isHidden = railHost.layer?.opacity == 0
        CATransaction.commit()
    }
    func updateAppearance(expanded: Bool, hasNotch: Bool, preferences: AppPreferences, dropTarget: Bool? = nil) {
        if let dropTarget { self.dropTarget = dropTarget }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdrop.configure(preferences, active: expanded, radius: expanded ? preferences.cornerRadius : 14)
        let policy = NexaGlassEnvironment(preferences: preferences, nativeAvailable: true, reduceTransparency: NexaAccessibility.reduceTransparency, increaseContrast: NexaAccessibility.increaseContrast)
        borderLayer.lineWidth = self.dropTarget || NexaAccessibility.increaseContrast ? 2 : 1
        borderLayer.strokeColor = self.dropTarget ? NSColor(preferences.accent.color).cgColor : NSColor.white.withAlphaComponent(expanded || !hasNotch ? policy.borderAlpha : 0).cgColor
        CATransaction.commit()
    }
    private func animateOpacity(_ layer: CALayer, to opacity: Float, duration: Double, delay: Double) {
        let current = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = opacity
        guard duration > 0 else { layer.removeAnimation(forKey: "nexa.opacity"); return }
        guard current != opacity else { layer.removeAnimation(forKey: "nexa.opacity"); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = current; fade.toValue = opacity
        fade.duration = duration; fade.beginTime = CACurrentMediaTime() + delay; fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "nexa.opacity")
    }
    static func path(size: CGSize, canvasWidth: CGFloat, radius: CGFloat, shoulder: CGFloat, detached: Bool = false) -> CGPath {
        var translation = CGAffineTransform(translationX: (canvasWidth - size.width) / 2, y: 0)
        return NotchSilhouette(radius: radius, shoulder: shoulder, detached: detached).path(in: CGRect(origin: .zero, size: size)).cgPath.copy(using: &translation)!
    }
}

private final class FlippedSurface: NSView { override var isFlipped: Bool { true } }

/// A faded-out hosting view must not steal native clicks or drag destinations.
final class NotchHostingView: NSHostingView<NotchView> {
    var acceptsInteraction = true
    override func hitTest(_ point: NSPoint) -> NSView? { acceptsInteraction ? super.hitTest(point) : nil }
}
