import AVFoundation
import Metal
import CoreVideo

/// Non-isolated capture worker. Owns the AVCaptureSession and creates a Metal texture from each
/// frame SYNCHRONOUSLY on the capture queue (the pixel buffer is only valid during the callback),
/// retaining the CVMetalTexture so the MTLTexture stays alive. Thread-safe via a lock.
final class CameraFrameProvider: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "trueisf.camera")
    private var cache: CVMetalTextureCache?
    private let lock = NSLock()
    private var latest: MTLTexture?
    private var retained: CVMetalTexture?

    private var startRequested = false   // guarded by `lock`

    init?(device: MTLDevice) {
        super.init()
        var c: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &c) == kCVReturnSuccess,
              let c else { return nil }
        cache = c
        // Deliberately NO permission request / session start here: with camera as the default
        // filter source, eager start would light the camera on every filter COMPILE — including
        // windowless import-gate and Remix controllers that never draw. The session starts lazily
        // on the first frame that actually consumes it (currentTexture).
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
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer), let cache else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixel, nil, .bgra8Unorm, w, h, 0, &cvTex)
        guard status == kCVReturnSuccess, let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return }
        lock.lock()
        retained = cvTex   // keep the CVMetalTexture alive while its MTLTexture is in use
        latest = tex
        lock.unlock()
    }

    /// Latest captured frame; kicks off permission + capture on first call (any thread — the
    /// render loop is the usual caller). Returns nil until frames flow (or forever, if denied).
    func currentTexture() -> MTLTexture? {
        lock.lock()
        let needsStart = !startRequested
        startRequested = true
        let tex = latest
        lock.unlock()
        if needsStart {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                self.queue.async { self.start() }
            }
        }
        return tex
    }
}

/// A live-camera ImageSource. Thin wrapper over CameraFrameProvider (which is internally locked, so
/// the render thread can read `texture` while the capture queue writes frames). Returns nil until a
/// frame arrives or if permission is denied (the router then falls back to the default test pattern).
final class CameraSource: ImageSource {
    var displayName: String { "Camera" }
    private let provider: CameraFrameProvider

    init?(device: MTLDevice) {
        guard let p = CameraFrameProvider(device: device) else { return nil }
        provider = p
    }

    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? { provider.currentTexture() }
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
