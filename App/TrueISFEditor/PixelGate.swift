import Foundation

/// Outcome of the pixel-truth render gate for one shader.
/// FAIL set blocks the corpus pass-list; WARN set is reported only.
enum PixelVerdict: String {
    case ok = "OK"
    case black = "BLACK"                // all frames under the luma floor
    case nan = "NAN"                    // any NaN/Inf component in any frame
    case constant = "STATIC"            // renders, but no frame ever changes (WARN)
    case renderError = "RENDER-ERR"     // threw or produced no readable frame
    case unsupported = "UNSUPPORTED"    // engine output format not analyzable (WARN)

    var isFail: Bool { self == .black || self == .nan || self == .renderError }
}

enum PixelGate {
    /// Luma floor under which a frame counts as black.
    static let blackLumaFloor = 2.0 / 255.0

    /// Maps the analyzed frames to a verdict. Precedence: render-err > nan > black > static > ok.
    /// `nil` entries mean a frame failed to render/read back.
    static func verdict(_ frames: [FramePixelStats?]) -> PixelVerdict {
        let stats = frames.compactMap { $0 }
        guard !frames.isEmpty, stats.count == frames.count else { return .renderError }
        if stats.contains(where: { $0.nanCount > 0 }) { return .nan }
        if stats.allSatisfy({ $0.maxLuma < blackLumaFloor }) { return .black }
        if Set(stats.map(\.digest)).count == 1 { return .constant }
        return .ok
    }

    /// ImportLog mapping (spec §C): OK records nothing; WARN set → .warning; FAIL set → .error.
    static func importOutcome(_ v: PixelVerdict) -> (outcome: ImportEvent.Outcome, message: String)? {
        switch v {
        case .ok:
            return nil
        case .constant:
            return (.warning, "pixel gate: STATIC — renders, but no frame ever changes")
        case .unsupported:
            return (.warning, "pixel gate: UNSUPPORTED — engine output format not analyzable")
        case .black:
            return (.error, "pixel gate: BLACK — compiled but renders black")
        case .nan:
            return (.error, "pixel gate: NAN — compiled but renders NaN/Inf pixels")
        case .renderError:
            return (.error, "pixel gate: RENDER-ERR — compiled but failed at render time")
        }
    }
}
