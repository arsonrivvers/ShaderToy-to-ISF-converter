import Foundation
import Combine

/// One layer's contribution for a single frame. Carries BOTH the operator's own fader value and
/// what it is actually contributing, so no readout has to reverse-engineer one from the other.
struct LayerParams: Equatable, Sendable {
    let deck: DeckID
    let userOpacity: Double
    let crossfadeWeight: Double
    let effectiveOpacity: Double
    let blendMode: BlendMode
}

/// The mixer surface: per-deck opacity and blend mode, the crossfader, and blackout.
///
/// Layer order is composite order — deck 1 onto opaque black, deck 2 onto the result (spec §7).
///
/// `@MainActor` covers the `@Published` UI state. The render thread never reads those properties:
/// it calls `renderLayers()` / `isBlackedOutForRender()`, which read a lock-protected mirror kept
/// in sync by every mutation — the same arrangement `SourceRouter` uses for `renderRoutes`, and
/// required for the same reason (see the plan's Threading Model section).
@MainActor
final class MixerState: ObservableObject {
    /// Composite order. Adding a deck means appending here; nothing else changes.
    static let layerOrder: [DeckID] = [.one, .two]

    @Published var crossfadePosition: Double = 0.0 {
        didSet {
            let clamped = min(max(crossfadePosition, 0), 1)
            if clamped != crossfadePosition { crossfadePosition = clamped; return }
            publishToRenderThread()
        }
    }
    @Published private(set) var opacity: [DeckID: Double] =
        Dictionary(uniqueKeysWithValues: DeckID.allCases.map { ($0, 1.0) })
    @Published private(set) var blendMode: [DeckID: BlendMode] =
        Dictionary(uniqueKeysWithValues: DeckID.allCases.map { ($0, .normal) })

    /// Blackout is engaged when EITHER the latch is on or a momentary key is held. Releasing the
    /// momentary must never cancel the latch — the failure mode is a room going back to light
    /// because someone tapped a key.
    @Published private(set) var isBlackedOut = false
    private var latchEngaged = false
    private var holdEngaged = false

    // ── render-thread mirror ──
    private let renderLock = NSLock()
    nonisolated(unsafe) private var renderLayerCache: [LayerParams] = []
    nonisolated(unsafe) private var renderBlackout = false

    init() {
        publishToRenderThread()
    }

    func setOpacity(_ value: Double, for deck: DeckID) {
        opacity[deck] = min(max(value, 0), 1)
        publishToRenderThread()
    }

    func setBlendMode(_ mode: BlendMode, for deck: DeckID) {
        blendMode[deck] = mode
        publishToRenderThread()
    }

    func toggleBlackoutLatch() {
        latchEngaged.toggle()
        recomputeBlackout()
    }

    func beginBlackoutHold() {
        holdEngaged = true
        recomputeBlackout()
    }

    func endBlackoutHold() {
        holdEngaged = false
        recomputeBlackout()
    }

    private func recomputeBlackout() {
        isBlackedOut = latchEngaged || holdEngaged
        publishToRenderThread()
    }

    /// Per-frame layer parameters, in composite order. Main-thread reads (UI).
    func layers() -> [LayerParams] {
        let order = Self.layerOrder
        return order.enumerated().map { index, deck in
            let user = opacity[deck] ?? 1.0
            let weight = CrossfadeMacro.weight(forLayerIndex: index, layerCount: order.count,
                                               position: crossfadePosition)
            return LayerParams(
                deck: deck,
                userOpacity: user,
                crossfadeWeight: weight,
                effectiveOpacity: CrossfadeMacro.effectiveOpacity(userOpacity: user, weight: weight),
                blendMode: blendMode[deck] ?? .normal)
        }
    }

    private func publishToRenderThread() {
        let snapshot = layers()
        let black = isBlackedOut
        renderLock.lock()
        renderLayerCache = snapshot
        renderBlackout = black
        renderLock.unlock()
    }

    // ── render thread ──

    /// The layer parameters for this frame. Safe from the display-link thread.
    nonisolated func renderLayers() -> [LayerParams] {
        renderLock.lock(); defer { renderLock.unlock() }
        return renderLayerCache
    }

    /// Whether the room is dark. Safe from the display-link thread.
    nonisolated func isBlackedOutForRender() -> Bool {
        renderLock.lock(); defer { renderLock.unlock() }
        return renderBlackout
    }
}
