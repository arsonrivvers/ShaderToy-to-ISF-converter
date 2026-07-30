import Foundation

/// The separable blend modes of the W3C Compositing and Blending Level 1 specification.
///
/// Non-separable modes (hue, saturation, color, luminosity) are deliberately absent: they operate
/// on the colour as a whole rather than per channel, and are not Milestone 1 scope.
///
/// `shaderIndex` is the wire value handed to MSL. It is derived from declaration order, and the
/// test suite pins it — reordering these cases would silently remap the operator's blend selection.
enum BlendMode: String, CaseIterable, Identifiable, Codable, Sendable {
    // ── W3C Compositing and Blending Level 1, separable ──
    case normal, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, hardLight, softLight, difference, exclusion
    // ── Extended set (standard published compositing math; NOT in the W3C separable list) ──
    // Added 2026-07-30: the operator flagged Add as missing, which it was. These are the
    // arithmetic and light-family modes every VJ host carries, TouchDesigner's Composite TOP
    // included. The formulas are standard and published; nothing here is extracted from any
    // installed application.
    //
    // APPENDED, never interleaved: `shaderIndex` is declaration order and the MSL switch indexes
    // on it, so inserting a case among the W3C ones would silently remap saved blend selections.
    case add, subtract, linearBurn, vividLight, pinLight, hardMix, divide

    var id: String { rawValue }

    /// True for the twelve W3C separable modes — lets the UI group them apart from the extras.
    var isW3CSeparable: Bool {
        switch self {
        case .normal, .multiply, .screen, .overlay, .darken, .lighten,
             .colorDodge, .colorBurn, .hardLight, .softLight, .difference, .exclusion:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .normal:     return "Normal"
        case .multiply:   return "Multiply"
        case .screen:     return "Screen"
        case .overlay:    return "Overlay"
        case .darken:     return "Darken"
        case .lighten:    return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn:  return "Color Burn"
        case .hardLight:  return "Hard Light"
        case .softLight:  return "Soft Light"
        case .difference: return "Difference"
        case .exclusion:  return "Exclusion"
        case .add:        return "Add"
        case .subtract:   return "Subtract"
        case .linearBurn: return "Linear Burn"
        case .vividLight: return "Vivid Light"
        case .pinLight:   return "Pin Light"
        case .hardMix:    return "Hard Mix"
        case .divide:     return "Divide"
        }
    }

    var shaderIndex: Int32 {
        Int32(Self.allCases.firstIndex(of: self) ?? 0)
    }
}

/// Pure blend and composite math. The reference implementation: `Compositor`'s MSL is a
/// transcription of this, and the compositor's golden-frame tests assert the GPU matches it.
enum BlendMath {
    /// B(Cb, Cs) for one channel, per W3C §blending. Inputs are expected in [0, 1].
    static func blend(_ mode: BlendMode, backdrop cb: Double, source cs: Double) -> Double {
        switch mode {
        case .normal:
            return cs
        case .multiply:
            return cb * cs
        case .screen:
            return cb + cs - cb * cs
        case .overlay:
            return blend(.hardLight, backdrop: cs, source: cb)
        case .darken:
            return min(cb, cs)
        case .lighten:
            return max(cb, cs)
        case .colorDodge:
            if cb == 0 { return 0 }
            if cs == 1 { return 1 }
            return min(1, cb / (1 - cs))
        case .colorBurn:
            if cb == 1 { return 1 }
            if cs == 0 { return 0 }
            return 1 - min(1, (1 - cb) / cs)
        case .hardLight:
            return cs <= 0.5
                ? blend(.multiply, backdrop: cb, source: 2 * cs)
                : blend(.screen, backdrop: cb, source: 2 * cs - 1)
        case .softLight:
            if cs <= 0.5 {
                return cb - (1 - 2 * cs) * cb * (1 - cb)
            }
            let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : sqrt(cb)
            return cb + (2 * cs - 1) * (d - cb)
        case .difference:
            return abs(cb - cs)
        case .exclusion:
            return cb + cs - 2 * cb * cs

        // ── extended set ──
        case .add:
            return min(1, cb + cs)                      // linear dodge
        case .subtract:
            return max(0, cb - cs)
        case .linearBurn:
            return max(0, cb + cs - 1)
        case .vividLight:
            return cs <= 0.5
                ? blend(.colorBurn, backdrop: cb, source: min(1, 2 * cs))
                : blend(.colorDodge, backdrop: cb, source: min(1, 2 * cs - 1))
        case .pinLight:
            return cs <= 0.5 ? min(cb, 2 * cs) : max(cb, 2 * cs - 1)
        case .hardMix:
            // The threshold form: everything lands on 0 or 1, which is the point of the mode.
            return (cb + cs) >= 1 ? 1 : 0
        case .divide:
            if cs == 0 { return cb == 0 ? 0 : 1 }
            return min(1, cb / cs)
        }
    }

    static func blend(_ mode: BlendMode,
                      backdrop cb: SIMD3<Double>,
                      source cs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(blend(mode, backdrop: cb.x, source: cs.x),
              blend(mode, backdrop: cb.y, source: cs.y),
              blend(mode, backdrop: cb.z, source: cs.z))
    }

    /// Source-over composite of a blended source onto an OPAQUE backdrop.
    ///
    /// The general W3C formula is
    ///     Co = (1 - ab)*as*Cs + ab*as*B(Cb, Cs) + (1 - as)*ab*Cb
    /// The instrument's master starts as opaque black and every layer writes opaque, so ab = 1
    /// always and this reduces to
    ///     Co = (1 - as)*Cb + as*B(Cb, Cs)
    /// `alpha` is the layer's effective opacity times the source pixel's own alpha.
    static func composite(backdrop cb: SIMD3<Double>,
                          source cs: SIMD3<Double>,
                          alpha: Double,
                          mode: BlendMode) -> SIMD3<Double> {
        let a = min(max(alpha, 0), 1)
        let blended = blend(mode, backdrop: cb, source: cs)
        return cb * (1 - a) + blended * a
    }
}
