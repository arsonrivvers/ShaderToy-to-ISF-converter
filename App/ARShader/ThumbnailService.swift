import Foundation
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

    /// Not t=0 — many shaders are black there. See `testTheSampleTimeIsTwoSeconds`.
    static let sampleTime: Double = 2.0

    /// 16:9, twice the 96pt cell width at 2× backing scale.
    static let thumbnailWidth = 320
    static let thumbnailHeight = 180

    /// Above the ~1,500-shader library, so a full sweep never thrashes.
    static let cacheCeiling = 2_000

    private let cache: ThumbnailCache
    private let device: MTLDevice
    /// NOT `RenderProperties.global().renderQueue`. `bgCmdQueue` is the singleton's documented
    /// background queue; the live path must never wait behind a thumbnail compile.
    private let queue: MTLCommandQueue
    private var interactiveTask: Task<Result, Never>?

    private(set) var compileCountForTesting = 0
    var commandQueueForTesting: MTLCommandQueue { queue }

    init(cacheDirectory: URL) {
        let properties = RenderProperties.global()
        self.device = properties.device
        self.queue = properties.bgCmdQueue
        self.cache = (try? ThumbnailCache(directory: cacheDirectory))!
    }

    func thumbnail(for shaderURL: URL, priority: Priority) async -> Result {
        if let cached = try? cache.entry(for: shaderURL) {
            switch cached {
            case .image(let data): return .image(data)
            case .unavailable:     return .unavailable
            }
        }
        switch priority {
        case .batch:
            return await render(shaderURL)
        case .interactive:
            interactiveTask?.cancel()
            let task = Task { await self.render(shaderURL) }
            interactiveTask = task
            return await task.value
        }
    }

    /// Drops in-flight hover work only. A queued `.batch` request is untouched — the two consumers
    /// have opposite requirements and this is the line between them.
    func cancelInteractive() {
        interactiveTask?.cancel()
        interactiveTask = nil
    }

    func sweepCache() {
        try? cache.evict(keepingAtMost: Self.cacheCeiling)
    }

    private func render(_ shaderURL: URL) async -> Result {
        compileCountForTesting += 1
        guard !Task.isCancelled,
              let source = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            try? cache.store(.unavailable, for: shaderURL)
            return .unavailable
        }
        let loaded = ISFSceneLoader.load(source: source, device: device)
        guard loaded.isValid, let scene = loaded.scene,
              !Task.isCancelled,
              let png = renderPNG(scene: scene) else {
            try? cache.store(.unavailable, for: shaderURL)
            return .unavailable
        }
        try? cache.store(.image(png), for: shaderURL)
        return .image(png)
    }

    /// Assembles the offscreen pipeline: render at `sampleTime` on `queue`, commit and wait, blit
    /// into a CPU-readable copy, then encode PNG bytes. Mirrors the isolated-device pattern in
    /// `InstrumentRendererTests` — device shared, work committed synchronously on our own queue.
    private func renderPNG(scene: ISFMSLScene) -> Data? {
        guard let cb = queue.makeCommandBuffer() else { return nil }
        let size = NSSize(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
        var err: NSString?
        guard let rendered = ISFMSLSafeRenderAtTime(scene, size, Self.sampleTime, cb, &err) else {
            return nil
        }
        cb.commit()
        cb.waitUntilCompleted()
        guard let readback = TextureReadback.managedCopy(of: rendered, device: device, queue: queue)
        else { return nil }
        return FramePNGEncoder.encodePNG(texture: readback)
    }
}
