import Metal

/// A render size in pixels. Free-form: the operator types width and height, and the presets are a
/// convenience rather than the vocabulary.
///
/// Bounds are enforced in `init` rather than at the UI, so no path can allocate a zero-pixel or an
/// absurd texture. The ceiling is high enough not to argue with the operator and low enough that a
/// texture allocation can survive it.
struct RenderSize: Equatable, Hashable, Codable, Sendable {
    static let minDimension = 16
    static let maxDimension = 7680

    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = min(max(width, Self.minDimension), Self.maxDimension)
        self.height = min(max(height, Self.minDimension), Self.maxDimension)
    }

    var size: MTLSize { MTLSize(width: width, height: height, depth: 1) }

    var label: String { "\(width) × \(height)" }

    /// Megapixels — the number that actually predicts cost, and the reason the readout shows it.
    var megapixels: Double { Double(width * height) / 1_000_000 }

    /// Scale by a factor, preserving aspect. Used for cue rendering, so a cued deck can never end
    /// up a different shape from the output it will be faded into.
    func scaled(by factor: Double) -> RenderSize {
        let f = min(max(factor, 0.05), 1.0)
        return RenderSize(width: Int((Double(width) * f).rounded()),
                          height: Int((Double(height) * f).rounded()))
    }

    static let hd = RenderSize(width: 1920, height: 1080)
    static let `default` = hd

    /// Offered in the presets menu. Typing any other size is equally valid.
    static let presets: [RenderSize] = [
        RenderSize(width: 640, height: 360),
        RenderSize(width: 960, height: 540),
        RenderSize(width: 1280, height: 720),
        .hd,
        RenderSize(width: 2560, height: 1440),
        RenderSize(width: 3840, height: 2160),
        RenderSize(width: 1080, height: 1920),   // vertical, for LED columns
        RenderSize(width: 1024, height: 768),    // 4:3 projector
    ]
}

// `CueQuality` lived here until 2026-07-30. Replaced by `RenderScale` (see RenderScale.swift):
// a five-case enum applied only to non-contributing decks could not express the thing the
// operator actually needed, which is a scale on the LIVE render.
