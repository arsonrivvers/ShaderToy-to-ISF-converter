import Combine
import Foundation

/// One snapshot of the live render loop, published at most every `RenderStatsAccumulator.interval`.
struct RenderStats: Equatable {
    /// Draw-cadence frames per second over the last window.
    var fps: Double
    /// Mean GPU time per frame (ms) over the last window; nil until a completed handler reports.
    var gpuMs: Double?

    /// Readout text: "60 FPS · 1.3 ms GPU" (or just "60 FPS" before any GPU sample lands).
    var readoutLabel: String {
        let fpsText = String(format: "%.0f FPS", fps)
        guard let gpuMs else { return fpsText }
        return fpsText + String(format: " · %.1f ms GPU", gpuMs)
    }
}

/// Pure windowed accumulator behind the FPS readout: feed it frame timestamps and GPU durations,
/// it emits one `RenderStats` per elapsed window. No clocks of its own — callers pass `now`
/// (CACurrentMediaTime in production, literals in tests).
struct RenderStatsAccumulator {
    /// Seconds between published snapshots. ~2 Hz keeps the SwiftUI readout cheap.
    let interval: Double
    private var windowStart: Double?
    private var frames = 0
    private var gpuSeconds = 0.0
    private var gpuSamples = 0

    init(interval: Double = 0.5) {
        self.interval = interval
    }

    /// Record one completed command buffer's GPU duration (seconds).
    mutating func addGPUTime(seconds: Double) {
        guard seconds > 0 else { return }   // gpuStart/EndTime are 0 on some failure paths
        gpuSeconds += seconds
        gpuSamples += 1
    }

    /// Record a presented frame at `now`. Returns a snapshot when the window has elapsed, else nil.
    mutating func frame(at now: Double) -> RenderStats? {
        guard let start = windowStart else {
            windowStart = now
            return nil
        }
        frames += 1
        let elapsed = now - start
        guard elapsed >= interval, frames > 0 else { return nil }
        let stats = RenderStats(
            fps: Double(frames) / elapsed,
            gpuMs: gpuSamples > 0 ? (gpuSeconds / Double(gpuSamples)) * 1000.0 : nil)
        windowStart = now
        frames = 0
        gpuSeconds = 0
        gpuSamples = 0
        return stats
    }

    /// Drop the current window (render loop paused, scene invalidated, or renderer switched).
    mutating func reset() {
        windowStart = nil
        frames = 0
        gpuSeconds = 0
        gpuSamples = 0
    }
}

/// Observable slot the preview engine publishes snapshots into and the readout view observes.
/// Separate from the engine so SwiftUI views can watch stats without observing the whole
/// controller (which would re-render controls on every compile-state change).
@MainActor
final class RenderStatsModel: ObservableObject {
    @Published var stats: RenderStats?
}
