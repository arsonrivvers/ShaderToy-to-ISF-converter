import Foundation
import Metal

/// One stage's contribution for a single frame — an immutable value the render thread reads.
/// `MetalRenderCore` is `@unchecked Sendable` behind its own lock, so this is safe to hand across.
struct FXStageSnapshot: @unchecked Sendable {
    let core: MetalRenderCore
    let mix: Double
    let blendMode: BlendMode
}

/// An ordered, unbounded stack of FX stages.
///
/// `@MainActor` covers the `@Published` UI state. The render thread never reads those properties:
/// it calls `renderStages()`, which reads a lock-protected mirror kept in sync by every mutation —
/// the same arrangement `MixerState` and `SourceRouter` use, and required for the same reason.
///
/// The mirror carries ONLY stages that will actually encode. A disabled stage, or one at zero mix,
/// is filtered out at publish time, so "skipped entirely" is a property of the data the render
/// thread sees rather than a branch it has to remember to take.
@MainActor
final class FXChain: ObservableObject {
    @Published private(set) var stages: [FXStage] = []

    private let renderLock = NSLock()
    nonisolated(unsafe) private var renderCache: [FXStageSnapshot] = []

    func append(_ stage: FXStage) {
        stages.append(stage)
        publishToRenderThread()
    }

    func remove(_ id: UUID) {
        stages.removeAll { $0.id == id }
        publishToRenderThread()
    }

    /// SwiftUI `onMove` (drag to reorder).
    func move(from source: IndexSet, to destination: Int) {
        stages.move(fromOffsets: source, toOffset: destination)
        publishToRenderThread()
    }

    /// Button reorder. Out-of-range and end-of-list moves are no-ops, never crashes — this runs
    /// under stage lighting.
    func moveUp(_ index: Int) {
        guard stages.indices.contains(index), index > 0 else { return }
        stages.swapAt(index, index - 1)
        publishToRenderThread()
    }

    func moveDown(_ index: Int) {
        guard stages.indices.contains(index), index < stages.count - 1 else { return }
        stages.swapAt(index, index + 1)
        publishToRenderThread()
    }

    func setEnabled(_ enabled: Bool, for stage: FXStage) {
        stage.apply(isEnabled: enabled)
        publishToRenderThread()
    }

    func setMix(_ mix: Double, for stage: FXStage) {
        stage.apply(mix: mix)
        publishToRenderThread()
    }

    func setBlendMode(_ mode: BlendMode, for stage: FXStage) {
        stage.apply(blendMode: mode)
        publishToRenderThread()
    }

    /// Republish after a stage finishes compiling — a stage whose scene just arrived must start
    /// encoding without waiting for an unrelated mutation.
    func stageDidChangeScene() { publishToRenderThread() }

    private func publishToRenderThread() {
        let snapshot = stages
            .filter { $0.isEnabled && $0.mix > 0 }
            .map { FXStageSnapshot(core: $0.unit.core, mix: $0.mix, blendMode: $0.blendMode) }
        renderLock.lock()
        renderCache = snapshot
        renderLock.unlock()
        objectWillChange.send()
    }

    // ── render thread ──

    /// The stages that will encode this frame, in order. Safe from the display-link thread.
    nonisolated func renderStages() -> [FXStageSnapshot] {
        renderLock.lock(); defer { renderLock.unlock() }
        return renderCache
    }
}

extension FXChain {
    /// Encode the whole chain into `cb`, ping-ponging between `input` and `scratch`.
    ///
    /// A chain only ever reads the IMMEDIATELY PREVIOUS stage, so a pair of textures covers any
    /// depth — the same argument that justifies the master ping-pong. Metal's automatic hazard
    /// tracking handles the write-after-read across passes within one command buffer.
    ///
    /// The mix pass is not an extra cost: every stage must copy its output out of the VVMTLPool
    /// texture the engine returns (the aliasing hazard documented on `TextureCopyPass`), and
    /// `encodeLayer` performs that copy while also applying the stage's mix and blend mode.
    ///
    /// Returns the texture holding the final result — `input` itself when nothing encoded.
    nonisolated func encode(input: MTLTexture,
                            scratch: MTLTexture,
                            renderSize: MTLSize,
                            compositor: Compositor,
                            preserveAlpha: Bool,
                            in cb: MTLCommandBuffer) -> MTLTexture {
        var source = input
        var target = scratch
        for stage in renderStages() {
            // `primaryInput: source` is what makes this a CHAIN: the stage's first image input is
            // the previous stage's result, not whatever its router would otherwise supply.
            // A transient render failure passes this stage's input through — never black.
            guard let produced = stage.core.renderOffscreen(size: renderSize, in: cb,
                                                            primaryInput: source) else {
                continue
            }
            compositor.encodeLayer(source: produced, backdrop: source, destination: target,
                                   opacity: stage.mix, mode: stage.blendMode,
                                   preserveAlpha: preserveAlpha, in: cb)
            swap(&source, &target)
        }
        return source
    }
}
