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

    private(set) var loadedISF: String?
    private(set) var lastInput: (String, String)?
    private(set) var lastRenderSize: (Int?, Int?)?
    func load(isf: String) { loadedISF = isf }
    func setInput(_ name: String, _ jsonValue: String) { lastInput = (name, jsonValue) }
    func setRenderSize(width: Int?, height: Int?) { lastRenderSize = (width, height) }

    func simulateCompile(valid: Bool, error: String?, line: Int?, inputs: [ISFPreviewInput]) {
        self.compileValid = valid; self.compileError = error
        self.compileErrorLine = line; self.inputs = inputs
        objectWillChange.send()
    }
}
