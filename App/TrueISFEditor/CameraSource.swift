import AVFoundation
import Metal
import CoreVideo
import QuartzCore

/// Non-isolated capture worker. Owns the AVCaptureSession and creates a Metal texture from each
/// frame SYNCHRONOUSLY on the capture queue (the pixel buffer is only valid during the callback),
/// retaining the CVMetalTexture so the MTLTexture stays alive. Thread-safe via a lock.
///
/// Lifecycle (C10): the session starts LAZILY on the first consumed frame and stops itself after
/// `idleStopSeconds` without a consumer — the camera light is on only while something actually
/// samples frames. A later consumer restarts the session transparently.
final class CameraFrameProvider: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// A frame plus the CVMetalTexture that backs it. Consumers MUST keep `backing` alive until
    /// the GPU finishes reading `texture` (C9) — the IOSurface can be recycled the moment the
    /// CVMetalTexture releases, even with the MTLTexture still referenced by an encoder.
    struct PinnedFrame {
        let texture: MTLTexture
        let backing: CVMetalTexture
    }

    /// Seconds without a `currentFrame()` call before the capture session stops itself.
    static let idleStopSeconds: CFTimeInterval = 5

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "trueisf.camera")
    private var cache: CVMetalTextureCache?
    private let now: () -> CFTimeInterval   // injectable clock for idle-stop tests
    /// Injectable permission seam: production asks AVFoundation; tests inject a no-op so a unit
    /// test can never start the real camera (real frames raced the injected clock and flaked).
    private let requestAccess: (@escaping @Sendable (Bool) -> Void) -> Void
    private let lock = NSLock()
    // ── lock-guarded state ──
    private var latest: PinnedFrame?
    private var startRequested = false
    private var sessionStopped = false      // idle-stopped; next consumer restarts
    private var lastAccess: CFTimeInterval = 0

    init?(device: MTLDevice,
          now: @escaping () -> CFTimeInterval = { CACurrentMediaTime() },
          requestAccess: ((@escaping @Sendable (Bool) -> Void) -> Void)? = nil) {
        self.now = now
        self.requestAccess = requestAccess ?? { completion in
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        }
        super.init()
        var c: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &c) == kCVReturnSuccess,
              let c else { return nil }
        cache = c
        // Deliberately NO permission request / session start here: with camera as the default
        // filter source, eager start would light the camera on every filter COMPILE — including
        // windowless import-gate and Remix controllers that never draw. The session starts lazily
        // on the first frame that actually consumes it (currentFrame).
    }

    private func start() {
        session.beginConfiguration()
        if let cam = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: cam),
           session.canAddInput(input) {
            session.addInput(input)
        }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ out: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        ingest(pixelBuffer: pixel)
    }

    /// Wrap a captured pixel buffer as the latest frame; also the idle-stop checkpoint. Split from
    /// `captureOutput` so tests can feed frames without an AVCaptureSession.
    func ingest(pixelBuffer pixel: CVPixelBuffer) {
        // Idle stop (C10): nothing consumed a frame for a while → stop the session (light off).
        // Runs here because this is the per-frame heartbeat on the capture queue.
        lock.lock()
        let idle = lastAccess > 0 && now() - lastAccess > Self.idleStopSeconds && !sessionStopped
        if idle { sessionStopped = true }
        lock.unlock()
        if idle {
            session.stopRunning()
            return
        }

        guard let cache else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixel, nil, .bgra8Unorm, w, h, 0, &cvTex)
        guard status == kCVReturnSuccess, let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return }
        lock.lock()
        latest = PinnedFrame(texture: tex, backing: cvTex)
        lock.unlock()
    }

    /// Latest captured frame; kicks off permission + capture on first call and restarts an
    /// idle-stopped session (any thread — the render loop is the usual caller). Returns nil until
    /// frames flow (or forever, if denied).
    func currentFrame() -> PinnedFrame? {
        lock.lock()
        lastAccess = now()
        let needsStart = !startRequested
        startRequested = true
        let needsRestart = !needsStart && sessionStopped
        sessionStopped = false
        let frame = latest
        lock.unlock()
        if needsStart {
            requestAccess { [weak self] granted in
                guard granted, let self else { return }
                self.queue.async { self.start() }
            }
        } else if needsRestart {
            queue.async { [weak self] in self?.session.startRunning() }
        }
        return frame
    }

    /// Test hook: true after the idle-stop checkpoint has shut the session down.
    var isIdleStoppedForTesting: Bool {
        lock.lock(); defer { lock.unlock() }
        return sessionStopped
    }
}

/// A live-camera ImageSource. Thin wrapper over CameraFrameProvider (which is internally locked, so
/// the render thread can read frames while the capture queue writes them). Returns nil until a
/// frame arrives or if permission is denied (the router then falls back to the default test pattern).
final class CameraSource: ImageSource {
    var displayName: String { "Camera" }
    private let provider: CameraFrameProvider

    init?(device: MTLDevice) {
        guard let p = CameraFrameProvider(device: device) else { return nil }
        provider = p
    }

    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        guard let frame = provider.currentFrame() else { return nil }
        // C9: pin the CVMetalTexture until THIS command buffer's GPU work completes. Without it,
        // the next captured frame drops the previous backing while the GPU may still sample it.
        cb.addCompletedHandler { [backing = frame.backing] _ in _ = backing }
        return frame.texture
    }
}

/// Process-wide single camera so the inline preview and the pop-out output window share ONE
/// AVCaptureSession instead of opening two competing sessions on the same device.
@MainActor
enum SharedCamera {
    private static var instance: CameraSource?
    /// The shared camera, created lazily on first request. Nil if the device has no camera.
    static func make(device: MTLDevice) -> ImageSource? {
        if let instance { return instance }
        instance = CameraSource(device: device)
        return instance
    }
}
