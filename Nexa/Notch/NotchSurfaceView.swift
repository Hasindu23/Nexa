import AppKit
import SwiftUI
import QuartzCore

/// Widgets keep their final layout while Core Animation morphs only the shell
/// and fades its two content layers. The native window never resizes per frame.
@MainActor final class NotchSurfaceView: NSView {
    override var isFlipped: Bool { true }
    let expandedHost: NotchHostingView
    let compactHost: NotchHostingView
    private let surface = FlippedSurface()
    private let backdrop = NSVisualEffectView()
    private let tint = NSView()
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var tracking: NSTrackingArea?
    var onHover: ((Bool) -> Void)?
    private var lastExpanded = false
    private var canvasSize = CGSize.zero
    private var dropTarget = false
    private(set) var renderedSize = CGSize.zero

    init(expanded: NotchView, compact: NotchView) {
        expandedHost = NotchHostingView(rootView: expanded)
        compactHost = NotchHostingView(rootView: compact)
        super.init(frame: .zero)
        wantsLayer = true; surface.wantsLayer = true; tint.wantsLayer = true
        addSubview(surface)
        backdrop.material = .hudWindow; backdrop.blendingMode = .behindWindow; backdrop.state = .active
        surface.addSubview(backdrop); surface.addSubview(tint)
        for host in [expandedHost, compactHost] {
            host.safeAreaRegions = []; host.sizingOptions = []; host.wantsLayer = true
            surface.addSubview(host)
        }
        expandedHost.layer?.opacity = 0; expandedHost.isHidden = true
        expandedHost.acceptsInteraction = false
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

    func render(canvas: CGSize, target: CGSize, expandedSize: CGSize, compactSize: CGSize,
                expanded: Bool, hasNotch: Bool, preferences: AppPreferences, module: ModuleID,
                duration: TimeInterval, completion: @escaping () -> Void) {
        let oldPath = maskLayer.presentation()?.path ?? maskLayer.path
        var translation = CGAffineTransform(translationX: (canvas.width - canvasSize.width) / 2, y: 0)
        let from = oldPath?.copy(using: &translation)
        let opening = expanded && !lastExpanded, closing = !expanded && lastExpanded
        let liftOrigin = expandedHost.isHidden ? -5.0 : (expandedHost.layer?.presentation()?.value(forKeyPath: "transform.translation.y") as? Double ?? 0)
        lastExpanded = expanded; canvasSize = canvas; renderedSize = target

        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = CGRect(origin: .zero, size: canvas)
        backdrop.frame = surface.bounds; tint.frame = surface.bounds
        // A collapsed notch is opaque, so sampling the desktop behind it is wasted work.
        updateAppearance(expanded: expanded, hasNotch: hasNotch, preferences: preferences)
        expandedHost.frame = CGRect(x: (canvas.width - expandedSize.width) / 2, y: 0, width: expandedSize.width, height: expandedSize.height)
        compactHost.frame = CGRect(x: (canvas.width - compactSize.width) / 2, y: 0, width: compactSize.width, height: compactSize.height)
        expandedHost.isHidden = false; compactHost.isHidden = false
        expandedHost.acceptsInteraction = expanded; compactHost.acceptsInteraction = !expanded
        maskLayer.frame = surface.bounds; borderLayer.frame = surface.bounds
        let path = Self.path(size: target, canvasWidth: canvas.width, radius: expanded ? preferences.cornerRadius : 14, shoulder: hasNotch && expanded ? 15 : 0, detached: !hasNotch)
        maskLayer.path = path; borderLayer.path = path
        if duration > 0, let from {
            let morph = CABasicAnimation(keyPath: "path")
            morph.fromValue = from; morph.toValue = path; morph.duration = duration
            morph.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.82, 0.22, 1)
            maskLayer.add(morph, forKey: "nexa.morph"); borderLayer.add(morph, forKey: "nexa.morph")
        } else { maskLayer.removeAllAnimations(); borderLayer.removeAllAnimations() }
        animateOpacity(expandedHost.layer!, to: expanded ? 1 : 0, duration: duration * (closing ? 0.34 : 0.8), delay: opening ? duration * 0.08 : 0)
        animateOpacity(compactHost.layer!, to: expanded ? 0 : 1, duration: duration * 0.5, delay: closing ? duration * 0.32 : 0)
        if opening, duration > 0 {
            let lift = CABasicAnimation(keyPath: "transform.translation.y")
            lift.fromValue = liftOrigin; lift.toValue = 0; lift.duration = duration
            lift.timingFunction = CAMediaTimingFunction(name: .easeOut)
            expandedHost.layer?.add(lift, forKey: "nexa.lift")
        } else if duration == 0 { expandedHost.layer?.removeAnimation(forKey: "nexa.lift") }
        CATransaction.commit()
        // Completion is generation-checked by the controller. An interrupted
        // transition starts at the presentation layer, never an obsolete endpoint.
        if duration == 0 { finish(expanded: expanded); completion() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.015) { completion() } }
    }
    func finish(expanded: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        maskLayer.removeAllAnimations(); borderLayer.removeAllAnimations()
        expandedHost.layer?.removeAllAnimations(); compactHost.layer?.removeAllAnimations()
        expandedHost.layer?.opacity = expanded ? 1 : 0; compactHost.layer?.opacity = expanded ? 0 : 1
        expandedHost.isHidden = !expanded; compactHost.isHidden = expanded
        CATransaction.commit()
    }
    func updateAppearance(expanded: Bool, hasNotch: Bool, preferences: AppPreferences, dropTarget: Bool? = nil) {
        if let dropTarget { self.dropTarget = dropTarget }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdrop.isHidden = !expanded || preferences.blur == 0
        backdrop.alphaValue = preferences.blur
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(expanded ? preferences.opacity : 1).cgColor
        borderLayer.lineWidth = self.dropTarget ? 2 : 1
        borderLayer.strokeColor = self.dropTarget ? NSColor(preferences.accent.color).cgColor : preferences.border && !hasNotch ? NSColor.white.withAlphaComponent(0.10).cgColor : nil
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
