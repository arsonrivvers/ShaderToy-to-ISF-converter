import Foundation
import Metal

enum DeckID: String, CaseIterable, Identifiable, Sendable {
    case one = "1"
    case two = "2"
    var id: String { rawValue }
    /// What the operator sees. Decks are "A" and "B" on the surface, 1 and 2 in the layer stack.
    var displayName: String { self == .one ? "A" : "B" }
}

/// One deck: a hosted shader (`ShaderUnit`) plus the things only a deck has — an owned output
/// texture that monitors read in a later command buffer, and a position in the layer stack.
///
/// The shader itself — compile state, parameters, image routing — lives in `unit`, so an FX stage
/// can host one the same way. `Deck` is deliberately NOT `ObservableObject`: nothing observable
/// remains on it, and views observe `unit`.
///
/// `render(in:)` is `nonisolated` because the frame graph calls it from the display-link thread; it
/// touches only `ShaderUnit.core` (already lock-guarded), the copy pass (immutable after init), and
/// `renderOwnedOutput`, which — like `ISFSceneSource.lastGood` — is written and read by that single
/// render-thread consumer alone.
@MainActor
final class Deck {
    let id: DeckID
    let unit: ShaderUnit

    /// This deck's FX chain. Its output is what the deck contributes AND what its monitor shows —
    /// the operator cues the finished look.
    let fx = FXChain()

    private let device: MTLDevice
    /// Built once in init, immutable after — a lazy var would not be safe to touch from the
    /// render thread.
    private let copyPass: TextureCopyPass?
    /// Touched ONLY by the render thread (see the class comment).
    nonisolated(unsafe) private var renderOwnedOutput: MTLTexture?
    /// The chain's ping-pong partner. Allocated alongside the owned output, so a chain of any
    /// depth costs exactly one extra texture per deck.
    nonisolated(unsafe) private var fxScratch: MTLTexture?

    init(id: DeckID, device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.id = id
        self.device = device
        self.unit = ShaderUnit(device: device, queue: queue, clock: clock)
        self.copyPass = TextureCopyPass(device: device,
                                        destinationFormat: InstrumentRenderer.masterFormat)
    }

    // MARK: rendering (display-link thread)

    /// Render this deck into the caller's command buffer and return the deck's OWNED output
    /// texture. Nil when no shader is loaded — the layer contributes nothing and the compositor
    /// skips it. Never returns a pool texture: monitors read this in a later buffer.
    ///
    /// `renderSize` is what the ISF shader is actually asked to rasterise — the dominant GPU cost,
    /// and the only real saving lever. `ownedSize` is the texture everything downstream reads, and
    /// stays at the output resolution regardless.
    ///
    /// Keeping the owned texture at a FIXED size is deliberate: a deck being cued renders small
    /// and is upscaled into it, so when the operator starts a fade there is no reallocation and no
    /// hitch at exactly the wrong moment. Only the rasterised pixel count changes.
    nonisolated func render(in cb: MTLCommandBuffer,
                            renderSize: MTLSize,
                            ownedSize: MTLSize,
                            compositor: Compositor?) -> MTLTexture? {
        guard let engineTexture = unit.renderOffscreen(size: renderSize, in: cb) else { return nil }
        // Reallocate only when the OUTPUT resolution changes — never per frame, never on a fade.
        if renderOwnedOutput?.width != ownedSize.width
            || renderOwnedOutput?.height != ownedSize.height {
            renderOwnedOutput = Self.makeOutputTexture(device: device, size: ownedSize)
            fxScratch = Self.makeOutputTexture(device: device, size: ownedSize)
        }
        guard let owned = renderOwnedOutput, let copyPass else { return nil }
        copyPass.encode(from: engineTexture, to: owned, in: cb)
        // No compositor is the survivable failure state, not a crash: the deck still contributes
        // its un-effected image rather than nothing.
        guard let compositor, let scratch = fxScratch else { return owned }
        // Stages rasterise at the deck's CURRENT size, so a cued deck's chain is cheap too. The
        // mix pass writes into the owned-size targets and upscales by sampling.
        // preserveAlpha: the deck's contribution is a LAYER — forcing it opaque here would change
        // how it composites into the master.
        return fx.encode(input: owned, scratch: scratch, renderSize: renderSize,
                         compositor: compositor, preserveAlpha: true, in: cb)
    }

    // NOTE: deliberately NO public accessor for `renderOwnedOutput`. Monitors read deck textures
    // through `InstrumentRenderer.deckTexture(_:)`, which serves a lock-guarded snapshot taken
    // during the frame. An accessor here would hand any caller an unsynchronized read of a field
    // the render thread owns — a race with no symptom until it tears. (Removed during the Task 13
    // manual review, having been added and never called.)

    nonisolated private static func makeOutputTexture(device: MTLDevice,
                                                      size: MTLSize) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat,
            width: size.width,
            height: size.height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }
}
