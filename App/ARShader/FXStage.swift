import Foundation
import Metal

/// One stage in an FX chain: a hosted shader plus how much of it to apply and how to blend it
/// against what came before.
///
/// Mutation goes through `FXChain`, not through the stage — the chain owns the lock-protected
/// render mirror and must republish on every change, including changes to a stage's own fields.
@MainActor
final class FXStage: ObservableObject, Identifiable {
    let id = UUID()
    let unit: ShaderUnit

    /// Builds its own unit so a stage can never be constructed with a ROUTED primary input — the
    /// chain drives that slot.
    init(device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.unit = ShaderUnit(device: device, queue: queue, clock: clock,
                               reservesPrimaryInput: true)
    }

    @Published private(set) var isEnabled = true
    /// Dry (0) to wet (1). At 0 the stage is skipped entirely — see FXChain.publishToRenderThread.
    @Published private(set) var mix: Double = 1.0
    /// How the stage's output is combined with its input. The same 19 modes the mixer uses.
    @Published private(set) var blendMode: BlendMode = .normal

    /// True when the shader declares NO image input — a generator, which REPLACES the feed rather
    /// than processing it. Marked in the UI so it is a usable move, not a mystery.
    /// Asks the SHADER, not the router: a filter stage's primary input is deliberately unrouted.
    var isGenerator: Bool { unit.inputs.allSatisfy { $0.type != "image" } }

    // CALL THESE ONLY FROM `FXChain`. They mutate a stage without republishing the chain's
    // render mirror, so calling one directly leaves the render thread encoding stale values —
    // a disabled stage that keeps rendering, or a mix the operator can no longer change.
    // (`fileprivate` would express that, but `FXChain` lives in its own file and could not
    // then reach them; the module boundary plus this notice is the enforcement available.)
    func apply(isEnabled: Bool) { self.isEnabled = isEnabled }
    func apply(mix: Double) { self.mix = min(max(mix, 0), 1) }
    func apply(blendMode: BlendMode) { self.blendMode = blendMode }
}
