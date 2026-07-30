import Foundation

/// A rasterisation scale, as a percentage of the output resolution.
///
/// Typed rather than picked from a fixed set, matching `RenderSize`: the operator types a number
/// and the presets are a convenience, not the vocabulary. Clamped in `init` so no path can ask for
/// a zero-pixel or a supersampled target.
///
/// Replaces `CueQuality`, a five-case enum that was applied ONLY to decks with zero effective
/// opacity — which made it inert on the live deck actually costing the frame (reported by the
/// operator 2026-07-30: 62.8 ms GPU with Cue already set to 25%).
struct RenderScale: Equatable, Hashable, Codable, Sendable {
    /// Below this, a 1920-wide output rasterises under 100px and a cue image stops being judgeable.
    static let minPercent = 5
    /// The ceiling. Above 100% is supersampling — genuine free anti-aliasing at four times the
    /// cost — deliberately out of scope.
    static let maxPercent = 100

    let percent: Int

    init(percent: Int) {
        self.percent = min(max(percent, Self.minPercent), Self.maxPercent)
    }

    var factor: Double { Double(percent) / 100.0 }

    var label: String { "\(percent)%" }

    /// The pixel size this scale resolves to. Identity at 100% so the common case allocates and
    /// rasterises exactly what the operator typed, with no rounding drift.
    func applied(to output: RenderSize) -> RenderSize {
        percent >= Self.maxPercent ? output : output.scaled(by: factor)
    }

    static let full = RenderScale(percent: 100)
    /// Live decks and the master composite: full quality until the operator decides otherwise.
    static let defaultRender = full
    /// A cued deck feeds only a small monitor. Half resolution is a QUARTER of the pixels.
    static let defaultCue = RenderScale(percent: 50)

    /// Offered in the presets menu. Typing any other value is equally valid.
    static let presets: [RenderScale] = [100, 75, 50, 33, 25, 10].map { RenderScale(percent: $0) }
}
