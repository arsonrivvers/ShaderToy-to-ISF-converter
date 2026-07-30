import Metal
import MetalKit
import QuartzCore
import VVMetalKit

/// The instrument's single clock and frame graph.
///
/// One `DisplayLinkDriver` drives ONE frame for everything — decks, compositor, monitors, program
/// output. This is the deliberate departure from the editor, where each MTKView owns its own
/// display link (correct for N independent previews, wrong for one instrument).
///
/// **Deliberately NOT `@MainActor`.** `renderFrame()` is called from the CVDisplayLink thread, and
/// the display link exists precisely so SwiftUI/AppKit layout during a control drag cannot starve
/// the render loop. Marking this main-actor and reaching for `MainActor.assumeIsolated` in the
/// render closure is not a workaround — `assumeIsolated` is a runtime ASSERTION, and it traps
/// (`dispatch_assert_queue_fail`) on the very first tick. Measured 2026-07-30.
///
/// So this follows the pattern `MetalRenderCore` already proves: `@unchecked Sendable` with one
/// coarse lock guarding every field the render thread touches. Main-thread callers (attach, UI
/// reads) take the same lock, so access is strictly serialized.
///
/// Master textures ping-pong: the compositor reads one and writes the other, so each layer sees the
/// backdrop the previous layer produced. Both are allocated once at 1920×1080; the steady-state
/// frame allocates nothing.
final class InstrumentRenderer: @unchecked Sendable {
    static let masterWidth = 1920
    static let masterHeight = 1080
    /// 16-bit float: ISF scenes commonly output float formats, and blending in a wider space than
    /// the 8-bit drawable avoids banding on repeated composites.
    static let masterFormat: MTLPixelFormat = .rgba16Float

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    let clock: RenderClock

    private let lock = NSLock()
    // ── lock-guarded state ──
    /// Ping-pong pair. `masterIndex` names the texture holding the CURRENT composited result.
    private var masters: [MTLTexture] = []
    private var masterIndex = 0
    private var driver: DisplayLinkDriver?

    /// Called after each frame's command buffer is committed, on the render thread.
    var onFrameRendered: (@Sendable () -> Void)?

    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        self.clock = RenderClock()
        // ISFMSLKit needs its global pool before any scene work; harmless if already set.
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: device) }
        masters = (0..<2).compactMap { _ in Self.makeMaster(device: device) }
    }

    private static func makeMaster(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: masterFormat, width: masterWidth, height: masterHeight, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// The texture a consumer should display. Nil means "show opaque black" — consumers must honor
    /// that rather than reusing their last frame. Safe from any thread.
    func programTexture() -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return currentMasterLocked()
    }

    /// Requires `lock` held.
    private func currentMasterLocked() -> MTLTexture? {
        masters.indices.contains(masterIndex) ? masters[masterIndex] : nil
    }

    /// Render exactly one frame. Called on the display-link thread. Task 2 renders an empty
    /// instrument: clear the master to opaque black. Tasks 6-8 extend this into the full
    /// deck → compositor → blackout graph.
    func renderFrame() {
        lock.lock()
        guard let cb = queue.makeCommandBuffer(), let master = currentMasterLocked() else {
            lock.unlock()
            return
        }
        clearToOpaqueBlack(master, in: cb)
        cb.commit()
        lock.unlock()
        onFrameRendered?()
    }

    /// The one operation that must never depend on a compiled pipeline: a render pass whose only
    /// job is a clear. This is the failure floor for the whole instrument (spec §8).
    func clearToOpaqueBlack(_ texture: MTLTexture, in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
    }

    // MARK: clock control (main thread)

    func start() {
        lock.lock(); let d = driver; lock.unlock()
        d?.start()
    }

    func stop() {
        lock.lock(); let d = driver; lock.unlock()
        d?.pause()
    }

    /// Attach the display link to the view that owns the frame cadence (the program output).
    /// Called once, after the window exists.
    @MainActor
    func attachClock(to view: MTKView) {
        lock.lock()
        guard driver == nil else { lock.unlock(); return }
        let d = DisplayLinkDriver(view: view)
        driver = d
        lock.unlock()
        view.isPaused = (d != nil)
        d?.start()
    }

    deinit {
        driver?.invalidate()
    }
}
