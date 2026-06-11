import Metal
import Foundation
import ISFMSLKit
import VVMetalKit
import ShadertoyISFKit

/// An ImageSource backed by a second ISFMSLScene loaded from ISF source text. Powers both test
/// patterns and library-shader chaining. Validated by rendering one probe frame on init; if that
/// fails, init returns nil so the router can fall back. Renders into the caller's command buffer.
@MainActor
final class ISFSceneSource: ImageSource {
    let displayName: String
    private let scene: ISFMSLScene
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let tempURL: URL
    private var lastGood: MTLTexture?

    /// Returns nil if the shader fails to compile or render a probe frame.
    init?(displayName: String, sourceText: String, device: MTLDevice, queue: MTLCommandQueue) {
        self.displayName = displayName
        self.device = device
        self.queue = queue
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trueisf-src-\(UUID().uuidString).fs")
        self.tempURL = url
        do { try sourceText.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        // Swift does not call deinit when a failable init returns nil, so clean up the temp file on
        // any failure path here; the deinit handles the success-then-dealloc case. Reference the
        // local `url` (not self.tempURL) so the defer doesn't touch self before init completes.
        var didFinishInit = false
        defer { if !didFinishInit { try? FileManager.default.removeItem(at: url) } }

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

        // Nesting rule: if this source shader is itself a filter, feed its image inputs the default
        // test pattern (one level, no recursion) so it renders instead of showing black.
        if let patternTex = ISFSceneSource.defaultPatternTexture(device: device, queue: queue) {
            for attrib in s.inputs where attrib.isFilterInputImage || attrib.shouldHaveImageBuffer || attrib.type == .image {
                if let val = ISFMSLSceneVal.create(with: patternTex) as? ISFMSLSceneVal {
                    s.setValue(val, forInputNamed: attrib.name)
                }
            }
        }

        // Probe frame: confirm it actually renders before we accept this source.
        guard let cb = queue.makeCommandBuffer() else { return nil }
        var err: NSString?
        let tex = ISFMSLSafeRender(s, NSSize(width: 320, height: 180), cb, &err)
        cb.commit()
        cb.waitUntilCompleted()
        guard tex != nil, !s.compilerError else { return nil }
        didFinishInit = true
    }

    deinit { try? FileManager.default.removeItem(at: tempURL) }

    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, NSSize(width: size.width, height: size.height), cb, &err)
        if let tex { lastGood = tex; return tex }
        return lastGood   // keep-last-good on a transient render failure
    }

    /// Render the default test pattern once to a standalone texture (for the nesting rule).
    private static func defaultPatternTexture(device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        let p = TestPatternCatalog.default
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trueisf-nest-\(UUID().uuidString).fs")
        guard (try? p.sourceText.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        var ce: ObjCBool = false; var msg: NSString?
        guard let scene = ISFMSLSafeCreateAndLoad(device, url, &ce, &msg), !ce.boolValue,
              let cb = queue.makeCommandBuffer() else { return nil }
        var err: NSString?
        let tex = ISFMSLSafeRender(scene, NSSize(width: 320, height: 180), cb, &err)
        cb.commit(); cb.waitUntilCompleted()
        return tex
    }
}
