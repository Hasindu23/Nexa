import Foundation
import Combine

@MainActor final class TimerService: ObservableObject, ModuleLifecycle {
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var running = false
    @Published private(set) var stopwatch: TimeInterval = 0
    @Published private(set) var stopwatchRunning = false
    var onFinish: (() -> Void)?
    private var deadline: Date?
    private var stopwatchStarted: Date?
    private var stopwatchBase: TimeInterval = 0
    private var ticker: Timer?
    var progress: Double { duration > 0 ? min(1, max(0, 1 - remaining / duration)) : 0 }
    func startTimer(seconds: TimeInterval, now: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        duration = min(seconds, 86400); remaining = duration; deadline = now.addingTimeInterval(duration); running = true; start()
    }
    func toggle(now: Date = Date()) {
        if running { tick(now: now); deadline = nil; running = false }
        else { if remaining <= 0 { remaining = duration }; deadline = now.addingTimeInterval(remaining); running = true }
        updateTicker()
    }
    func reset() { running = false; deadline = nil; remaining = duration; updateTicker() }
    func toggleStopwatch(now: Date = Date()) {
        if stopwatchRunning { tick(now: now); stopwatchBase = stopwatch; stopwatchStarted = nil }
        else { stopwatchStarted = now }
        stopwatchRunning.toggle(); updateTicker()
    }
    func resetStopwatch(now: Date = Date()) { stopwatch = 0; stopwatchBase = 0; stopwatchStarted = stopwatchRunning ? now : nil }
    func tick(now: Date = Date()) {
        if running, let deadline {
            remaining = max(0, deadline.timeIntervalSince(now))
            if remaining == 0 { running = false; self.deadline = nil; onFinish?() }
        }
        if stopwatchRunning, let stopwatchStarted { stopwatch = stopwatchBase + max(0, now.timeIntervalSince(stopwatchStarted)) }
        updateTicker()
    }
    func start() {
        guard ticker == nil, running || stopwatchRunning else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer.tolerance = 0.1; RunLoop.main.add(timer, forMode: .common); ticker = timer
    }
    func stop() { ticker?.invalidate(); ticker = nil }
    func suspend() { tick(); running = false; deadline = nil; stopwatchBase = stopwatch; stopwatchRunning = false; stopwatchStarted = nil; stop() }
    private func updateTicker() { if running || stopwatchRunning { start() } else { stop() } }
}
