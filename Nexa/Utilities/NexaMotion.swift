import SwiftUI

/// One policy for geometry, module changes and interaction feedback.
struct NexaMotion: Equatable {
    var preset: MotionPreset = .balanced
    var speed: Double = 1
    var reduced = false
    var energySaving = false
    init(preferences: AppPreferences = AppPreferences(), systemReduceMotion: Bool = false) {
        preset = preferences.motionPreset
        speed = preferences.animationSpeed.isFinite ? min(2, max(0.5, preferences.animationSpeed)) : 1
        reduced = systemReduceMotion || preferences.reduceMotion
        energySaving = preferences.energySaving
    }
    private func duration(_ value: Double) -> Double { reduced ? 0 : value / speed }
    var expansionDuration: Double { duration(preset == .subtle ? 0.29 : preset == .playful ? 0.37 : 0.34) }
    var collapseDuration: Double { duration(preset == .subtle ? 0.23 : preset == .playful ? 0.29 : 0.26) }
    var moduleDuration: Double { duration(preset == .subtle ? 0.18 : preset == .playful ? 0.24 : 0.21) }
    var hoverDuration: Double { duration(0.15) }
    var notificationDuration: Double { duration(0.32) }
    var buttonDuration: Double { duration(0.12) }
    var damping: Double { energySaving || preset == .subtle ? 1 : preset == .playful ? 0.86 : 0.98 }
    var moduleAnimation: Animation? { reduced ? nil : .easeInOut(duration: moduleDuration) }
    var feedbackAnimation: Animation? { reduced ? nil : .spring(duration: buttonDuration, bounce: energySaving || preset != .playful ? 0 : 0.08) }
}

private struct NexaMotionKey: EnvironmentKey { static let defaultValue = NexaMotion() }
extension EnvironmentValues {
    var nexaMotion: NexaMotion {
        get { self[NexaMotionKey.self] }
        set { self[NexaMotionKey.self] = newValue }
    }
}

/// Analytic spring with exact rest at the endpoint. Retargeting retains both
/// position and velocity; the small endpoint correction is C1-continuous.
struct NexaSpring {
    let start: Double
    let velocity: Double
    let target: Double
    let duration: Double
    let damping: Double
    func sample(_ time: Double) -> (value: Double, velocity: Double) {
        guard duration > 0, time < duration else { return (target, 0) }
        let t = max(0, time), u = t / duration
        let raw = response(t), end = response(duration)
        let residual = end.value - target
        let p = 10 * pow(u, 3) - 15 * pow(u, 4) + 6 * pow(u, 5)
        let dp = 30 * pow(u, 2) - 60 * pow(u, 3) + 30 * pow(u, 4)
        let h = -4 * pow(u, 3) + 7 * pow(u, 4) - 3 * pow(u, 5)
        let dh = -12 * pow(u, 2) + 28 * pow(u, 3) - 15 * pow(u, 4)
        return (raw.value - residual * p - duration * end.velocity * h,
                raw.velocity - residual * dp / duration - end.velocity * dh)
    }
    private func response(_ t: Double) -> (value: Double, velocity: Double) {
        let omega = 10 / max(0.001, duration), zeta = min(1, max(0.7, damping))
        let a = start - target
        if zeta >= 0.999 {
            let b = velocity + omega * a, decay = exp(-omega * t)
            return (target + (a + b * t) * decay, (b - omega * (a + b * t)) * decay)
        }
        let wd = omega * sqrt(1 - zeta * zeta), b = (velocity + zeta * omega * a) / wd
        let envelope = exp(-zeta * omega * t), wave = a * cos(wd * t) + b * sin(wd * t)
        let derivative = -a * wd * sin(wd * t) + b * wd * cos(wd * t)
        return (target + envelope * wave, envelope * (derivative - zeta * omega * wave))
    }
}

struct NexaMorphState {
    var width: Double, height: Double, radius: Double, shoulder: Double
    var widthVelocity = 0.0, heightVelocity = 0.0, radiusVelocity = 0.0, shoulderVelocity = 0.0
}

struct NexaMorph {
    let from: NexaMorphState
    let to: NexaMorphState
    let duration: Double
    let damping: Double
    func sample(_ time: Double) -> NexaMorphState {
        func component(_ start: Double, _ velocity: Double, _ target: Double) -> (value: Double, velocity: Double) {
            NexaSpring(start: start, velocity: velocity, target: target, duration: duration, damping: damping).sample(time)
        }
        let w = component(from.width, from.widthVelocity, to.width)
        let h = component(from.height, from.heightVelocity, to.height)
        let r = component(from.radius, from.radiusVelocity, to.radius)
        let s = component(from.shoulder, from.shoulderVelocity, to.shoulder)
        return NexaMorphState(width: w.value, height: h.value, radius: r.value, shoulder: s.value,
                              widthVelocity: w.velocity, heightVelocity: h.velocity, radiusVelocity: r.velocity, shoulderVelocity: s.velocity)
    }
    var samples: [NexaMorphState] {
        let count = max(2, Int(ceil(duration * 120)))
        return (0...count).map { sample(duration * Double($0) / Double(count)) }
    }
}
