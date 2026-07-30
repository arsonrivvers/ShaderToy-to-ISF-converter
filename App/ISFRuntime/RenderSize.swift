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

/// How much of the output resolution a deck rasterises at while it is NOT on program.
///
/// A fraction rather than an independent size, deliberately: it follows whatever the operator
/// types for output, so a cued deck can never have a different aspect from the program it is about
/// to be faded into. That mismatch would show up as a stretch at the worst possible moment.
enum CueQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case full = "100%"
    case threeQuarter = "75%"
    case half = "50%"
    case third = "33%"
    case quarter = "25%"

    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .full:         return 1.0
        case .threeQuarter: return 0.75
        case .half:         return 0.5
        case .third:        return 1.0 / 3.0
        case .quarter:      return 0.25
        }
    }

    /// Half resolution is a QUARTER of the pixels — a real saving, with a cue image still easily
    /// good enough to judge on a small monitor.
    static let `default`: CueQuality = .half

    func applied(to output: RenderSize) -> RenderSize {
        self == .full ? output : output.scaled(by: factor)
    }
}
