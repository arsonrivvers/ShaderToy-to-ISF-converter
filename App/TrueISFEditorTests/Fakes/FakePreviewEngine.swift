import AppKit
import Combine
import Metal

@MainActor
final class FakePreviewEngine: PreviewEngine, ObservableObject {
    @Published var compileValid = false
    @Published var compileError: String?
    @Published var compileErrorLine: Int?
    @Published var inputs: [ISFPreviewInput] = []
    let view = NSView()
    var nsView: NSView { view }
    var compileStateWillChange: ObservableObjectPublisher { objectWillChange }
    let imageSources: SourceRouter = {
        let device = MTLCreateSystemDefaultDevice()!
        return SourceRouter(device: device, queue: device.makeCommandQueue()!)
    }()

    var onSceneInstalled: (() -> Void)?

    private(set) var loadedISF: String?
    private(set) var lastInput: (String, String)?
    private(set) var lastRenderSize: (width: Int, height: Int, fit: Bool)?
    func load(isf: String) { loadedISF = isf }
    func setInput(_ name: String, _ jsonValue: String) { lastInput = (name, jsonValue) }
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool) { lastRenderSize = (width, height, fitToWindow) }

    func simulateCompile(valid: Bool, error: String?, line: Int?, inputs: [ISFPreviewInput]) {
        self.compileValid = valid; self.compileError = error
        self.compileErrorLine = line; self.inputs = inputs
        objectWillChange.send()
    }

    /// Mimics the REAL `@Published` notification ordering of MetalPreviewController.applyCompile:
    /// each property's `objectWillChange` fires BEFORE the new value is stored, and there is NO
    /// trailing manual send. A coordinator that reads engine state inside the will-change handler
    /// therefore sees pre-store (stale) values. Use this to catch the off-by-one mirror bug.
    func simulateCompileLikePublished(valid: Bool, error: String?, line: Int?, inputs: [ISFPreviewInput]) {
        self.compileValid = valid; self.compileError = error
        self.compileErrorLine = line; self.inputs = inputs
    }
}
