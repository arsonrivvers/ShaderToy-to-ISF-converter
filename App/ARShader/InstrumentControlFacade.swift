// Spyglass is a local-path package that exists only in the operator checkout (see
// App/spyglass-local.yml), which is also the only place the SPYGLASS compilation condition is
// defined. That keeps a clean clone compiling without the package; `DEBUG` keeps
// the whole surface out of Release regardless.
#if DEBUG && SPYGLASS
import Foundation
import Metal
import QuartzCore
import SpyglassCapture
import SpyglassCore
import SpyglassHost
import SpyglassProtocol

/// The names ARShader gives its capturable outputs. Opaque to Spyglass — the package deliberately
/// knows nothing about decks or program feeds — so this is the one place they are spelled.
enum InstrumentTap {
    /// What the audience sees: the composited master, **after** the blackout gate.
    static let program = "program"

    /// One deck's own output, pre-opacity and pre-blend — what its cue monitor shows.
    ///
    /// Built from `displayName`, not `rawValue`, because the operator's decks are A and B; a tap
    /// called `deck-1` would name something no label on the surface says.
    static func deck(_ id: DeckID) -> String { "deck-\(id.displayName.lowercased())" }
}

/// ARShader's entire surface to Spyglass, and therefore to an agent. Nothing reaches past it.
///
/// **Isolation.** Deliberately not `@MainActor` and deliberately not an `actor`. Everything it
/// touches is already safe off the main thread and lock-guarded at its source — `InstrumentRenderer`
/// (`@unchecked Sendable`, one coarse lock) and `MixerState.isBlackedOutForRender()` (`nonisolated`,
/// its own render lock) — so hopping to the main actor would buy nothing and would put an agent's
/// capture in contention with SwiftUI layout during a control drag. That is the same reasoning
/// `InstrumentRenderer` itself records for not being main-actor, and this follows its pattern:
/// `@unchecked Sendable` over types Metal does not declare `Sendable`.
///
/// **Obligation 1, which the compiler cannot check.** `ControlFacade` requires that a conformer
/// *await* the GPU rather than *wait* on it, and notes that `MTLCommandBuffer.waitUntilCompleted()`
/// is not marked `noasync`, so nothing catches a blocking implementation. The obvious path here —
/// `TextureReadback.managedCopy`, which `ThumbnailService.renderPNG` already uses — commits and
/// blocks. It is therefore **not** used on this path. `encodeFrame` builds the same work into one
/// command buffer and suspends on `addCompletedHandler`, and the CPU-side PNG encode (a per-pixel
/// Swift loop, ~2M iterations at 1080p) runs on `encodeQueue` at `.utility`, bridged by a
/// continuation. Neither the caller's executor nor the display-link thread is ever parked.
///
/// No unit test in this process can distinguish awaiting from blocking here — this type is
/// non-isolated, so an `async` call already switches to the generic executor and a blocked
/// cooperative thread would still return an answer. The obligation is held instead by
/// `testTheCapturePathNeverWaitsOnTheGPU`, which fails if `waitUntilCompleted`,
/// `TextureReadback.managedCopy` or a semaphore wait ever re-enters this file, and confirmed on
/// device by Task 14 Leg B (instrument FPS does not drop across a capture).
///
/// **Read-only, and blackout is honoured.** Every tap reads a texture the operator can already see
/// on their own screen. `rawMasterTexture()` bypasses the blackout gate and is consulted here as a
/// *predicate only* — its pixels are never returned and it is deliberately **not** a tap. Blackout
/// is the panic button; an agent that could look behind it would defeat the one control whose whole
/// value is that it is absolute.
final class InstrumentControlFacade: ControlFacade, @unchecked Sendable {
    /// Bumped when the shape of this surface changes, independently of the app's version.
    static let protocolVersion = "1"

    /// Captures are delivered as 8-bit RGB PNG regardless of the instrument's internal precision
    /// (the masters are `rgba16Float`). `TextureCopyPass` samples, so this conversion is free and
    /// happens in the same pass as the resize.
    static let capturePixelFormat: MTLPixelFormat = .rgba8Unorm
    static let capturePixelFormatName = "rgba8Unorm"

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: InstrumentRenderer
    private let mixer: MixerState

    /// Samples a source texture into a destination render target, so it both **resizes** to the
    /// requested capture size and converts `rgba16Float` → `rgba8Unorm`. A blit could do neither.
    private let copyPass: TextureCopyPass?

    /// `.utility` on purpose: ARShader is a live performance surface, and an agent's capture must
    /// never be scheduled ahead of the frame the room is watching.
    private let encodeQueue = DispatchQueue(
        label: "com.arsonrivvers.arshader.spyglass-capture", qos: .utility)

    private let countLock = NSLock()
    private var performCaptureCalls = 0

    /// How many requests reached `performCapture` — i.e. survived Gate 0's validation. Test
    /// observability only, and the reason a rejection can be shown to have *skipped* the work
    /// rather than done it and relabelled the result.
    var performCaptureCallCountForTesting: Int {
        countLock.lock(); defer { countLock.unlock() }
        return performCaptureCalls
    }

    init(device: MTLDevice, queue: MTLCommandQueue, renderer: InstrumentRenderer, mixer: MixerState) {
        self.device = device
        self.queue = queue
        self.renderer = renderer
        self.mixer = mixer
        // Compiles a small Metal library. Built eagerly rather than lazily because a `lazy var` on
        // a non-isolated class is not thread-safe, and this type is constructed once, only when the
        // startup gate has already decided Spyglass is running.
        self.copyPass = TextureCopyPass(device: device, destinationFormat: Self.capturePixelFormat)
    }

    // MARK: - Taps

    /// Which renderer output a tap name refers to.
    private enum TapSource {
        case program
        case deck(DeckID)
    }

    private static func source(named name: String) -> TapSource? {
        if name == InstrumentTap.program { return .program }
        for id in DeckID.allCases where InstrumentTap.deck(id) == name { return .deck(id) }
        return nil
    }

    /// **Every tap is `.liveOnly`, and that is a statement about ARShader, not a default.**
    ///
    /// The instrument has no render-at-time path at all: `renderFrame()` draws from `clock.now` and
    /// takes no time argument, and neither does anything under it. Declaring `.explicitTime` on any
    /// of these would make a `time` argument silently ignored — the facade's stated worst case,
    /// because the caller then gets a picture that looks like an answer to a question it never
    /// actually asked. Declared this way, `capture` rejects it instead.
    ///
    /// Derived from `DeckID.allCases` so a third deck is a tap without anyone remembering to add one.
    var taps: [TapDescriptor] {
        get async {
            [TapDescriptor(name: InstrumentTap.program, timeSupport: .liveOnly)]
                + DeckID.allCases.map {
                    TapDescriptor(name: InstrumentTap.deck($0), timeSupport: .liveOnly)
                }
        }
    }

    // MARK: - Capabilities

    /// The commands this facade can genuinely answer today, and only those.
    ///
    /// Spec §6.4 also names `get_element_stats` and `get_render_stats`; neither is expressible
    /// through `ControlFacade` as it stands, so neither is advertised. An inventory is a promise,
    /// and obligation 4's objection to a *partial* inventory applies just as well to an inflated
    /// one — an agent that plans around a tool the host cannot serve is worse off than one that
    /// never saw it.
    ///
    /// No `time` property on `capture`: all taps are `.liveOnly`, so there is no value a caller
    /// could legally pass, and a schema advertising one would invite exactly the request the facade
    /// then has to reject.
    static let commands: [ToolDescriptor] = [
        ToolDescriptor(
            name: "instrument.capture",
            description: "Capture one of the instrument's live outputs as a PNG. Returns `stale` "
                + "rather than a picture if the renderer has not advanced.",
            schema: ToolSchema(
                properties: [
                    "tap": .string(description:
                        "Which output to capture: 'program' (what the audience sees, after the "
                        + "blackout gate), or 'deck-a' / 'deck-b' (a deck's own cue output)."),
                    "width": .integer(description: "Capture width in pixels."),
                    "height": .integer(description: "Capture height in pixels."),
                ],
                required: ["tap", "width", "height"]),
            annotations: .readOnly),
        ToolDescriptor(
            name: "instrument.describe_state",
            description: "The instrument's capturable taps and its renderer liveness "
                + "(frame counter and seconds since the last frame).",
            schema: .none,
            annotations: .readOnly),
    ]

    func capabilities() async -> Capabilities {
        Capabilities(protocolVersion: Self.protocolVersion, descriptors: Self.commands)
    }

    // MARK: - Render health

    /// Obligation 3, at the boundary: a renderer that has never composited has **no** honest
    /// last-frame time, so this reports that it cannot be read rather than inventing one.
    /// `InstrumentRenderer.lastFrameAt` is `Optional` for this reason, and a fabricated
    /// `0 frames / 0 seconds` here would read downstream as a permanently healthy renderer —
    /// silently defeating the stall detection this whole path exists to provide.
    ///
    /// Both signals come from one `renderLiveness` read, so the count and the timestamp always
    /// describe the same frame.
    func renderHealth() async -> Result<RenderHealth, ToolError> {
        if Task.isCancelled { return .failure(.cancelled) }
        let (frames, lastFrameAt) = renderer.renderLiveness
        guard let lastFrameAt else { return .failure(.healthUnavailable) }
        // Same clock the renderer stamps with (`CACurrentMediaTime`), so the subtraction is
        // meaningful; mixing in `Date` here would silently compare two different time bases.
        return .success(RenderHealth(frameCounter: frames,
                                     secondsSinceLastFrame: CACurrentMediaTime() - lastFrameAt))
    }

    // MARK: - Capture

    /// Already validated by `ControlFacade.capture` — the tap exists, the size is legal, and `time`
    /// is `nil` (no tap here accepts anything else). Nothing re-checks that, deliberately: a
    /// conformer that cannot see an invalid request cannot mishandle one.
    func performCapture(tap: String, width: Int, height: Int, time: Double?) async -> CaptureOutcome {
        countLock.lock(); performCaptureCalls += 1; countLock.unlock()

        // Redundant with `renderHealth()`'s own check one line down, and deliberately kept: it is
        // free, and it means obligation 2 does not depend on a check inside a *different* method
        // staying where it is. Stated because it is redundant — mutation-testing confirmed that
        // deleting it changes no observable behaviour, so no test pins it and none should pretend to.
        if Task.isCancelled { return .failure(.cancelled) }

        // Health first, and the stall check before any pixels: a renderer that has not advanced
        // must not yield a picture at all, so no texture is resolved and no GPU work is queued.
        let health: RenderHealth
        switch await renderHealth() {
        case .success(let h): health = h
        case .failure(let error): return .failure(error)
        }
        if health.isStalled() { return .stale(health: health) }

        guard let source = Self.source(named: tap) else {
            // Unreachable through `capture`, which resolves the tap first. Kept because
            // `performCapture` is a protocol requirement and could be called directly in future.
            return .failure(.unknownTap(tap, known: await taps.map(\.name)))
        }

        let texture: MTLTexture
        switch resolveTexture(source) {
        case .success(let t): texture = t
        case .failure(let error): return .failure(error)
        }

        if Task.isCancelled { return .failure(.cancelled) }

        switch await encodeFrame(from: texture, width: width, height: height) {
        case .failure(let error):
            return .failure(error)
        case .success(let png):
            return .success(
                frame: FrameResult(
                    pngBase64: png.base64EncodedString(),
                    metadata: FrameMetadata(
                        tap: tap,
                        // The size actually delivered. `TextureCopyPass` resizes to the request, so
                        // this is a measurement rather than an echo — aspect ratio is NOT preserved,
                        // because returning a different size than the one asked for would be the
                        // same silent substitution the `time` rule exists to prevent.
                        width: width, height: height,
                        pixelFormat: Self.capturePixelFormatName,
                        // Always `nil` — validation guarantees it for every `.liveOnly` tap, and
                        // every tap here is one. Forwarded rather than hardcoded so this stays
                        // correct if ARShader ever grows a tap that can seek.
                        time: time,
                        // ARShader has no document: no file is open, nothing is saved, and there is
                        // no version to report. `0` says "not applicable". `1` would be worse — it
                        // claims a first generation of something that does not exist, and v2's
                        // comparison work would key on a number that never moves.
                        documentGeneration: 0)),
                health: health)
        }
    }

    /// Resolves a tap to the texture to capture, or to the reason there is none.
    ///
    /// **Blackout semantics.** `programTexture()` returns `nil` for two entirely different reasons —
    /// the operator hit blackout, or nothing has been composited at all — and reporting the first as
    /// the second would tell an agent the show is broken when the operator simply cut the output.
    /// `rawMasterTexture()` bypasses the gate, so its presence separates them: master exists behind
    /// the gate ⇒ blackout. It is read as a predicate; its pixels never leave this function.
    ///
    /// Deck taps are deliberately **not** blackout-gated, matching the app: `monitorTexture` routes
    /// deck monitors to `deckTexture`, so the operator's own cue monitors stay live while the room
    /// is dark. An agent sees exactly what the operator sees, which is the whole point.
    private func resolveTexture(_ source: TapSource) -> Result<MTLTexture, ToolError> {
        switch source {
        case .program:
            if let texture = renderer.programTexture() { return .success(texture) }
            if renderer.rawMasterTexture() != nil { return .failure(.blackedOut) }
            return .failure(.noOutput(
                tap: InstrumentTap.program,
                reason: "the instrument has not composited a master frame"))
        case .deck(let id):
            if let texture = renderer.deckTexture(id) { return .success(texture) }
            return .failure(.noOutput(
                tap: InstrumentTap.deck(id),
                reason: "deck \(id.displayName) has no shader loaded"))
        }
    }

    /// Resize, convert, read back and encode — one command buffer, awaited, never waited on.
    ///
    /// The two textures are not one: `TextureCopyPass` needs a render target and
    /// `FramePNGEncoder.encodePNG(texture:)` needs CPU-readable bytes, so the frame is drawn into a
    /// `.private` target and blitted into a `.managed` copy in the same buffer. That is the pair
    /// `TextureReadback` and `ThumbnailService` already prove; what is new here is that the wait is
    /// a suspension instead of `waitUntilCompleted()`.
    private func encodeFrame(from source: MTLTexture,
                             width: Int,
                             height: Int) async -> Result<Data, ToolError> {
        guard let copyPass else {
            return .failure(.captureFailed("the capture pipeline could not be built on this GPU"))
        }

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.capturePixelFormat, width: width, height: height, mipmapped: false)
        targetDescriptor.storageMode = .private
        targetDescriptor.usage = [.renderTarget, .shaderRead]

        let readbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.capturePixelFormat, width: width, height: height, mipmapped: false)
        readbackDescriptor.storageMode = .managed

        guard let target = device.makeTexture(descriptor: targetDescriptor),
              let readback = device.makeTexture(descriptor: readbackDescriptor),
              let commandBuffer = queue.makeCommandBuffer() else {
            return .failure(.captureFailed("could not allocate a \(width)\u{00D7}\(height) capture"))
        }

        copyPass.encode(from: source, to: target, in: commandBuffer)

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            return .failure(.captureFailed("could not encode the readback"))
        }
        blit.copy(from: target, to: readback)
        blit.synchronize(resource: readback)
        blit.endEncoding()

        // Obligation 1: await the GPU, do not wait on it. The handler is installed before `commit`
        // so a buffer that finishes immediately cannot resume a continuation that does not exist yet.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }

        if let error = commandBuffer.error {
            return .failure(.captureFailed("the GPU rejected the capture: \(error.localizedDescription)"))
        }
        // Obligation 2: the pixels exist but the caller has walked away, so the CPU encode — by far
        // the most expensive part — is not started.
        if Task.isCancelled { return .failure(.cancelled) }

        guard let png = await encodePNG(readback) else {
            return .failure(.captureFailed("the frame could not be encoded as PNG"))
        }
        return .success(png)
    }

    private func encodePNG(_ texture: MTLTexture) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            encodeQueue.async {
                continuation.resume(returning: FramePNGEncoder.encodePNG(texture: texture))
            }
        }
    }
}

// MARK: - ARShader's own facade errors

/// Codes that only ARShader can raise. They live here rather than beside `ToolError.cancelled` and
/// `.healthUnavailable` in the package because those name conditions *every* host has, and these
/// name conditions only an instrument has — a facade that stayed app-agnostic in every member would
/// stop being so the moment it learned the word "blackout".
extension ToolError {
    /// Spec §10 / Task 13 Step 5. The operator cut the output; this is not a missing scene, and
    /// saying so is the whole point of the code existing.
    static let blackedOut = ToolError(
        code: "blacked_out",
        message: "the program feed is blacked out — the operator has cut the output",
        hint: "this is the instrument's panic button, not a missing or failed scene; the deck taps "
            + "still show what the operator is cueing")

    /// There is genuinely nothing to capture on that tap.
    static func noOutput(tap: String, reason: String) -> ToolError {
        ToolError(code: "no_output",
                  message: "tap '\(tap)' has no frame to capture: \(reason)",
                  hint: nil)
    }

    /// The capture was attempted and failed — GPU allocation, encoding, or the PNG codec.
    /// Distinct from `no_output`, which means it was never attempted because there was nothing to
    /// attempt it on.
    static func captureFailed(_ reason: String) -> ToolError {
        ToolError(code: "capture_failed",
                  message: "the capture could not be completed: \(reason)",
                  hint: nil)
    }
}
#endif
