import Foundation

/// The crossfader as a MACRO over deck opacity — not a separate signal path (spec §7.1).
///
///     effectiveOpacity(deck) = userOpacity(deck) × crossfadeWeight(deck, x)
///
/// Both values stay real and both are displayed: the operator always sees the fader they set and
/// what it is actually contributing. This is the base-value/effective-value pattern approved in the
/// TouchDesigner Bindings design, reused deliberately.
///
/// The weighting generalises past two layers — only `weight` changes, never the callers.
enum CrossfadeMacro {
    /// Weight for layer `index` at crossfader position `position` ∈ [0, 1].
    ///
    /// Two layers: layer 0 gets `1 - x`, layer 1 gets `x`. Fewer than two layers: the crossfader
    /// has nothing to fade between and must not be able to mute the only source, so the weight
    /// is 1. Three or more: the position sweeps across the layers, each peaking at its own slot.
    static func weight(forLayerIndex index: Int, layerCount: Int, position: Double) -> Double {
        guard layerCount > 1 else { return 1 }
        let x = min(max(position, 0), 1)
        guard layerCount > 2 else {
            return index == 0 ? 1 - x : x
        }
        // N-layer generalisation: a triangular window of half-width one slot, centred on the
        // layer, swept by `position` across [0, layerCount - 1].
        let cursor = x * Double(layerCount - 1)
        return max(0, 1 - abs(cursor - Double(index)))
    }

    /// The product, clamped. Either value at zero silences the layer; neither can exceed 1.
    static func effectiveOpacity(userOpacity: Double, weight: Double) -> Double {
        let u = min(max(userOpacity, 0), 1)
        let w = min(max(weight, 0), 1)
        return u * w
    }
}
