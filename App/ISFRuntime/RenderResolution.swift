import Metal

/// A render resolution the operator can pick for a deck or for the program output.
///
/// A fixed preset list rather than free numeric entry: every value here is 16:9, which keeps the
/// compositor's sampling free of aspect surprises, and the ceiling is deliberate — the project's
/// own performance rules say never default to 4K, so it is offered but never the default.
enum RenderResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case r360 = "640x360"
    case r540 = "960x540"
    case r720 = "1280x720"
    case r1080 = "1920x1080"
    case r1440 = "2560x1440"
    case r2160 = "3840x2160"

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .r360: return 640
        case .r540: return 960
        case .r720: return 1280
        case .r1080: return 1920
        case .r1440: return 2560
        case .r2160: return 3840
        }
    }

    var height: Int {
        switch self {
        case .r360: return 360
        case .r540: return 540
        case .r720: return 720
        case .r1080: return 1080
        case .r1440: return 1440
        case .r2160: return 2160
        }
    }

    var displayName: String {
        self == .r2160 ? "3840x2160 (4K)" : rawValue
    }

    var size: MTLSize { MTLSize(width: width, height: height, depth: 1) }

    /// Megapixels, for the cost hint next to the picker. A deck at 4K is 36x the pixels of 360p,
    /// and with an effects stack that multiplies per stage.
    var megapixels: Double { Double(width * height) / 1_000_000 }

    static let `default`: RenderResolution = .r1080
}
