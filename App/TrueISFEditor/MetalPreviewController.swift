import AppKit
import Combine
import Metal
import MetalKit
import ISFMSLKit
import VVMetalKit

@MainActor
final class MetalPreviewController: NSObject, ObservableObject, PreviewEngine {
    @Published private(set) var compileValid = false
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []

    private let mtkView = MTKView()
    var nsView: NSView { mtkView }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }

    private let device: MTLDevice
    private var scene: ISFMSLScene?
    private let transpileQueue = DispatchQueue(label: "isfmsl.transpile", qos: .userInitiated)
    private let tempURL: URL

    override init() {
        let props = RenderProperties.global()
        self.device = props.device
        // Global singletons ISFMSLKit needs BEFORE any scene work:
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: props.device) }
        if ISFMSLCache.primary == nil {
            let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TrueISFEditor/ISFMSLCache")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            ISFMSLCache.primary = ISFMSLCache(directoryURL: cacheDir)
        }
        self.tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trueisf-live-\(UUID().uuidString).fs")
        super.init()
        mtkView.device = props.device
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false
    }

    func load(isf: String) {
        let url = tempURL
        let device = self.device
        transpileQueue.async { [weak self] in
            guard let self else { return }
            do { try isf.write(to: url, atomically: true, encoding: .utf8) } catch { return }
            guard let s = ISFMSLScene(device: device) else { return }
            s.load(url)
            let hadError = s.compilerError
            // If error, capture detail off-main too (building the transpiler error can be slow).
            var msg: String? = nil
            if hadError {
                let te = ISFMSLTranspilerError(url: url, device: device)
                msg = te.fragGLSLErrString ?? te.fragSPIRVErrString ?? te.fragMSLErrString
                    ?? te.vertGLSLErrString ?? te.generateStringForLogFile()
            }
            Task { @MainActor in self.applyCompile(scene: s, hadError: hadError, message: msg) }
        }
    }

    private func applyCompile(scene s: ISFMSLScene, hadError: Bool, message: String?) {
        if hadError {
            scene = nil
            compileValid = false
            compileError = (message?.isEmpty == false ? message : "Shader failed to compile.")
            compileErrorLine = Self.parseLine(from: message)
        } else {
            scene = s
            compileValid = true
            compileError = nil
            compileErrorLine = nil
            // inputs parsed in the next task
        }
    }

    static func parseLine(from msg: String?) -> Int? {
        guard let msg else { return nil }
        // glslang format: "ERROR: 0:NN:"
        if let r = msg.range(of: #"0:(\d+):"#, options: .regularExpression) {
            let digits = msg[r].dropFirst(2).dropLast()
            return Int(digits)
        }
        return nil
    }

    // Stubs (filled by later tasks) so this conforms + compiles now:
    func setInput(_ name: String, _ jsonValue: String) { /* Task 6 */ }
    func setRenderSize(width: Int?, height: Int?) { /* Task 7 */ }
}
