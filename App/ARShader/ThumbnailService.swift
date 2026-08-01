import Foundation
import Dispatch
import Metal
import ISFMSLKit
import VVMetalKit

/// Stills for the slot bank and the library, rendered offscreen and cached to disk.
///
/// An `actor` — the first in this app. The house pattern (`@MainActor` class + `NSLock` escape
/// hatch) exists because the renderer is called from the CVDisplayLink thread; nothing here is,
/// so an actor is the right tool and a hand-rolled lock would be strictly worse.
actor ThumbnailService {
    enum Priority: Sendable {
        /// Library hover. Superseded constantly as the pointer moves, so a newer request cancels
        /// the older one — a thumbnail for a row the pointer has left is wasted work.
        case interactive
        /// Populating the bank on launch or on growing a row. Queued and ALWAYS completed:
        /// cancelling these leaves permanently blank cells that only a resize or relaunch fills.
        case batch
    }

    enum Result: Equatable, Sendable {
        case image(Data)
        case unavailable
    }

    /// The outcome of an actual render ATTEMPT — distinct from the public `Result` because only
    /// SOME of these are safe to persist to disk. Round-1 review findings C1/I2/I3: collapsing
    /// every non-image outcome into "persist `.unavailable`" corrupted the cache on the normal
    /// hover-cancellation path and on transient GPU trouble, not just on a real compile failure.
    private enum RenderOutcome {
        case success(Data)
        /// The shader's own source or compile step failed. Deterministic given the file's bytes at
        /// this mtime, so — and ONLY so — this is safe to cache as `.unavailable` (I3).
        case shaderFailed(reason: String)
        /// Command-buffer allocation, the render call, texture readback, or PNG encoding failed.
        /// NOT a property of the shader — a GPU/memory hiccup mid-set must not permanently
        /// blacklist a good shader. NEVER persisted (I3).
        case transientFailure(reason: String)
        /// Cancelled before or during rendering. NEVER persisted — a superseded hover is not a
        /// verdict on the shader; persisting it is exactly how C1 corrupted the cache.
        case cancelled
    }

    /// Not t=0 — many shaders are black there. See `testTheSampleTimeIsTwoSeconds` (a sanity check
    /// on the constant) and `testTheRenderedThumbnailReflectsTheSampleTimeNotZero` (the real proof
    /// — renders a time-varying fixture and inspects pixels, since a literal-vs-literal assertion
    /// can't catch the render call site itself ignoring this constant; see I4).
    static let sampleTime: Double = 2.0

    /// 16:9, twice the 96pt cell width at 2× backing scale.
    static let thumbnailWidth = 320
    static let thumbnailHeight = 180

    /// Above the ~1,500-shader library, so a full sweep never thrashes.
    static let cacheCeiling = 2_000

    /// Upper bound on how long a single render may hold this actor waiting on the GPU (I7). Sized
    /// generously for a 320×180 offscreen render — a backstop against a hung GPU/driver, not a
    /// normal-case budget.
    private static let renderTimeout: TimeInterval = 5.0

    /// `nil` when the disk cache could not be created (permissions, out of space, ...). The service
    /// degrades to render-only-no-cache rather than crash (I6): a bad Application Support directory
    /// must not take down the instrument over a contact-sheet nicety. No other disk-backed store in
    /// this app crashes on this either — `SnapshotStore`, `ISFSceneLoader`, `ISFSceneSource` all
    /// `try?` and degrade.
    private let cache: ThumbnailCache?
    private let device: MTLDevice
    /// NOT `RenderProperties.global().renderQueue`. `bgCmdQueue` is the singleton's documented
    /// background queue; the live path must never wait behind a thumbnail compile.
    private let queue: MTLCommandQueue
    private var interactiveTask: Task<RenderOutcome, Never>?

    private(set) var compileCountForTesting = 0
    var commandQueueForTesting: MTLCommandQueue { queue }
    /// Diagnostic seam (I3): the reason the most recent shader/transient failure was not a success,
    /// so a blank cell has SOME signal beyond "not available." Test-only for now; a future UI task
    /// can surface it as a tooltip.
    private(set) var lastFailureReasonForTesting: String?

    init(cacheDirectory: URL) {
        let properties = RenderProperties.global()
        self.device = properties.device
        self.queue = properties.bgCmdQueue
        self.cache = try? ThumbnailCache(directory: cacheDirectory)
    }

    func thumbnail(for shaderURL: URL, priority: Priority) async -> Result {
        if let cache, let cached = try? cache.entry(for: shaderURL) {
            switch cached {
            case .image(let data): return .image(data)
            case .unavailable:     return .unavailable
            }
        }
        switch priority {
        case .batch:
            return resolve(await render(shaderURL), for: shaderURL)
        case .interactive:
            interactiveTask?.cancel()
            let task = Task { await self.render(shaderURL) }
            interactiveTask = task
            return resolve(await task.value, for: shaderURL)
        }
    }

    /// Maps a render attempt to the public `Result` AND decides what — if anything — reaches disk.
    /// Only `.shaderFailed` persists as `.unavailable`; `.transientFailure` and `.cancelled` both
    /// return `.unavailable` to THIS caller without writing anything, so the very next request
    /// tries again instead of being stuck behind a false verdict (C1/I2/I3).
    private func resolve(_ outcome: RenderOutcome, for shaderURL: URL) -> Result {
        switch outcome {
        case .success(let data):
            lastFailureReasonForTesting = nil
            try? cache?.store(.image(data), for: shaderURL)
            return .image(data)
        case .shaderFailed(let reason):
            lastFailureReasonForTesting = reason
            try? cache?.store(.unavailable, for: shaderURL)
            return .unavailable
        case .transientFailure(let reason):
            lastFailureReasonForTesting = reason
            return .unavailable
        case .cancelled:
            return .unavailable
        }
    }

    /// Marks the currently-tracked interactive request cancelled.
    ///
    /// WHAT THIS ACTUALLY DOES (C1 — the prior doc comment overclaimed it): `render` has no
    /// `await` inside its body once started — `ISFSceneLoader.load` and `renderPNG` are both
    /// synchronous — so calling this while a render is already mid-GPU-work does NOT interrupt it;
    /// that render runs to completion regardless of this call. Cancellation can only take effect at
    /// `render`'s own `Task.isCancelled` checkpoints (before reading the source, and again before
    /// rendering) — i.e. for a request that has not yet reached the GPU. What this reliably
    /// guarantees, now that a cancelled render is never persisted (see `RenderOutcome.cancelled`),
    /// is that a superseded hover cannot corrupt the disk cache — not that it can abort in-flight
    /// work. A queued `.batch` request is untouched either way — the two consumers have opposite
    /// requirements and this is the line between them.
    func cancelInteractive() {
        interactiveTask?.cancel()
        interactiveTask = nil
    }

    func sweepCache() {
        try? cache?.evict(keepingAtMost: Self.cacheCeiling)
    }

    private func render(_ shaderURL: URL) async -> RenderOutcome {
        compileCountForTesting += 1
        guard !Task.isCancelled else { return .cancelled }
        guard let source = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            return .shaderFailed(reason: "Could not read shader source.")
        }
        let loaded = ISFSceneLoader.load(source: source, device: device)
        guard loaded.isValid, let scene = loaded.scene else {
            return .shaderFailed(reason: loaded.errorMessage ?? "Shader failed to compile.")
        }
        guard !Task.isCancelled else { return .cancelled }
        switch renderPNG(scene: scene) {
        case .pngSuccess(let data): return .success(data)
        case .pngFailure(let reason): return .transientFailure(reason: reason)
        }
    }

    /// Local outcome for `renderPNG` — plain `Swift.Result<Data, String>` doesn't compile because
    /// `String` isn't `Error`, and wrapping every message in a throwaway `Error` type is more
    /// ceremony than a two-case enum for a value that's mapped straight into `RenderOutcome`.
    private enum RenderPNGOutcome {
        case pngSuccess(Data)
        case pngFailure(String)
    }

    /// Assembles the offscreen pipeline: render at `sampleTime` on `queue`, wait (bounded — see the
    /// trade-off note below), blit into a CPU-readable copy, then encode PNG bytes.
    ///
    /// TRADE-OFF (I7): this blocks the actor for the GPU round trip — our own commit-then-wait
    /// below, then AGAIN inside `TextureReadback.managedCopy`'s own commit+wait. Neither the main
    /// actor nor the live render thread are touched (the constraints this task must hold), but
    /// every OTHER caller of THIS actor — including a queued `.batch` item behind this one — waits
    /// for the same GPU round trip; this is the structural cause C1 built on. Redesigning this into
    /// a non-blocking / continuation-based path is out of scope for this task (explicitly not
    /// requested — the fix here is behavioral, not architectural). Instead OUR wait is bounded by
    /// `renderTimeout`, so a stuck GPU/driver becomes a timed-out transient failure (never
    /// persisted — see `RenderOutcome.transientFailure`) instead of holding the actor forever.
    /// `TextureReadback`'s own internal wait is shared infrastructure used elsewhere in the app
    /// (e.g. `InstrumentRendererTests`) and is a small GPU-local blit, not touched here.
    private func renderPNG(scene: ISFMSLScene) -> RenderPNGOutcome {
        guard let cb = queue.makeCommandBuffer() else {
            return .pngFailure("Could not allocate a command buffer.")
        }
        let size = NSSize(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
        var err: NSString?
        guard let rendered = ISFMSLSafeRenderAtTime(scene, size, Self.sampleTime, cb, &err) else {
            return .pngFailure((err as String?) ?? "ISF render failed.")
        }
        let done = DispatchSemaphore(value: 0)
        cb.addCompletedHandler { _ in done.signal() }
        cb.commit()
        guard done.wait(timeout: .now() + Self.renderTimeout) == .success else {
            return .pngFailure("Render timed out after \(Self.renderTimeout)s.")
        }
        guard let readback = TextureReadback.managedCopy(of: rendered, device: device, queue: queue)
        else { return .pngFailure("Texture readback failed.") }
        guard let png = FramePNGEncoder.encodePNG(texture: readback) else {
            return .pngFailure("PNG encode failed.")
        }
        return .pngSuccess(png)
    }
}
