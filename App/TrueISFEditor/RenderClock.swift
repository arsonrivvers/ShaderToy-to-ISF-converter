import Foundation
import QuartzCore

/// B2: the app-owned shader clock. Lives on the render core and SURVIVES scene swaps, so a
/// recompile no longer restarts TIME — the old per-scene timer restarted every animation on each
/// keystroke. Pause freezes elapsed time; resume continues without a jump; reset (document switch
/// or an explicit user action) returns to 0. Its lock permits synchronized comparison previews to
/// share one clock across separate render cores. `nowSource` is injectable for deterministic tests.
final class RenderClock {
    private let nowSource: () -> Double
    private let lock = NSLock()
    private var startRef: Double
    private var pausedElapsed: Double?

    init(nowSource: @escaping () -> Double = { CACurrentMediaTime() }) {
        self.nowSource = nowSource
        self.startRef = nowSource()
    }

    /// Elapsed shader time in seconds (frozen while paused).
    var now: Double {
        lock.lock(); defer { lock.unlock() }
        return pausedElapsed ?? (nowSource() - startRef)
    }

    func pause() {
        lock.lock(); defer { lock.unlock() }
        guard pausedElapsed == nil else { return }
        pausedElapsed = nowSource() - startRef
    }

    /// Continue from the paused elapsed time — no jump.
    func resume() {
        lock.lock(); defer { lock.unlock() }
        guard let p = pausedElapsed else { return }
        startRef = nowSource() - p
        pausedElapsed = nil
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        startRef = nowSource()
        if pausedElapsed != nil { pausedElapsed = 0 }
    }
}
