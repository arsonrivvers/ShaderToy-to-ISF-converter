import MetalKit
import CoreVideo

/// Drives an MTKView's draw cycle from a CVDisplayLink thread — OFF the main thread.
///
/// Ported from OffspringEngine's `MetalPreviewView.Coordinator` (VJ_Code-crossfade), where this
/// pattern is field-proven. Why off-main: the render loop's `currentDrawable` wait + GPU pacing,
/// when on the main thread, get starved by AppKit/SwiftUI layout passes during a slider drag —
/// collapsing FPS. On the display-link thread, main-thread layout is irrelevant to render rate.
///
/// CRITICAL (inherited from the reference implementation): the callback drives `view.draw()` —
/// NOT the delegate's render method directly. `MTKView.draw()` manages the drawable frame-cycle;
/// bypassing it was OffspringEngine's black-screen bug. The view must be `isPaused = true` so it
/// never self-drives in parallel.
///
/// Lifecycle: the driver retains itself (`passRetained`) for the link's lifetime so an in-flight
/// callback can never touch a freed driver. The owner MUST call `invalidate()` (safe from deinit)
/// or the link thread and this object leak. If CVDisplayLink creation fails, `init` returns nil —
/// the owner falls back to MTKView's own main-thread loop (functional, with the known drag-lag).
///
/// CVDisplayLink is deprecated (macOS 15) but functional; kept for parity with the proven
/// reference and the macOS 13 deployment target (NSView.displayLink(target:) is 14+).
final class DisplayLinkDriver: @unchecked Sendable {
    private weak var view: MTKView?
    private var displayLink: CVDisplayLink?
    private var unmanagedSelf: Unmanaged<DisplayLinkDriver>?
    /// Drains an in-flight tick on invalidate (CVDisplayLinkStop is not a barrier).
    private let renderGate = DispatchSemaphore(value: 1)
    private let stateLock = NSLock()
    private var running = false
    private var invalidated = false

    init?(view: MTKView) {
        self.view = view
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return nil }
        // Retain self for the link's lifetime. Released exactly once, in invalidate().
        let retained = Unmanaged.passRetained(self)
        unmanagedSelf = retained
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, ctx) -> CVReturn in
            Unmanaged<DisplayLinkDriver>.fromOpaque(ctx!).takeUnretainedValue().tick()
            return kCVReturnSuccess
        }, retained.toOpaque())
        displayLink = link
    }

    func start() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let link = displayLink, !running, !invalidated else { return }
        CVDisplayLinkStart(link)
        running = true
    }

    func pause() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let link = displayLink, running else { return }
        CVDisplayLinkStop(link)
        running = false
    }

    /// Stop permanently, wait out any in-flight tick, and release the self-retain. Idempotent;
    /// callable from the owner's deinit.
    func invalidate() {
        stateLock.lock()
        if invalidated { stateLock.unlock(); return }
        invalidated = true
        if let link = displayLink, running { CVDisplayLinkStop(link); running = false }
        displayLink = nil
        stateLock.unlock()
        // Not a barrier against an in-flight callback — wait for a running tick to finish
        // before dropping the retain that keeps this object alive for that callback.
        renderGate.wait(); renderGate.signal()
        unmanagedSelf?.release()
        unmanagedSelf = nil
    }

    /// Runs on the display-link thread.
    private func tick() {
        renderGate.wait()
        defer { renderGate.signal() }
        view?.draw()
    }
}
