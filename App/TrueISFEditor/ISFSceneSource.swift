import Metal
import Foundation
import ISFMSLKit
import VVMetalKit

/// An ImageSource backed by a second ISFMSLScene loaded from ISF source text. Powers both test
/// patterns and library-shader chaining. Validated by rendering one probe frame on init; if that
/// fails, init returns nil so the router can fall back. Renders into the caller's command buffer.
@MainActor
final class ISFSceneSource: ImageSource {
    let displayName: String
    private let scene: ISFMSLScene
    private let queue: MTLCommandQueue
    private let tempURL: URL
    private var lastGood: MTLTexture?

    /// Returns nil if the shader fails to compile or render a probe frame.
    init?(displayName: String, sourceText: String, device: MTLDevice, queue: MTLCommandQueue) {
        self.displayName = displayName
        self.queue = queue
        self.tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trueisf-src-\(UUID().uuidString).fs")
        do { try sourceText.write(to: tempURL, atomically: true, encoding: .utf8) } catch { return nil }

        // Ensure VVMetalKit / ISFMSLKit global singletons are initialized before any scene work.
        // Mirrors MetalPreviewController.init(). Without these, ISFMSLScene.loadURL: fails silently.
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: device) }
        if ISFMSLCache.primary == nil {
            let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TrueISFEditor/ISFMSLCache")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            ISFMSLCache.primary = ISFMSLCache(directoryURL: cacheDir)
        }

        var compileError: ObjCBool = false
        var message: NSString?
        guard let s = ISFMSLSafeCreateAndLoad(device, tempURL, &compileError, &message),
              !compileError.boolValue else { return nil }
        self.scene = s

        // Probe frame: confirm it actually renders before we accept this source.
        guard let cb = queue.makeCommandBuffer() else { return nil }
        var err: NSString?
        let tex = ISFMSLSafeRender(s, NSSize(width: 320, height: 180), cb, &err)
        cb.commit()
        cb.waitUntilCompleted()
        guard tex != nil, !s.compilerError else { return nil }
    }

    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, NSSize(width: size.width, height: size.height), cb, &err)
        if let tex { lastGood = tex; return tex }
        return lastGood   // keep-last-good on a transient render failure
    }
}
