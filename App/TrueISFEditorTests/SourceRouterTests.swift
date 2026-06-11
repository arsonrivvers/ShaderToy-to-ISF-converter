import XCTest
import Metal

@MainActor
final class SourceRouterTests: XCTestCase {
    private func makeRouter() throws -> SourceRouter {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return SourceRouter(device: device, queue: queue)
    }

    private func imageInput(_ name: String) -> ISFPreviewInput {
        ISFPreviewInput(name: name, type: "image", defaultValue: nil, min: nil, max: nil, labels: nil, values: nil)
    }

    func test_updateInputsAddsDefaultsAndPrunes() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage"), imageInput("mask")])
        XCTAssertEqual(Set(r.imageInputNames), ["inputImage", "mask"])
        XCTAssertEqual(r.selection(for: "inputImage"), .none)

        r.updateInputs([imageInput("inputImage")])
        XCTAssertEqual(r.imageInputNames, ["inputImage"])
        XCTAssertEqual(r.selection(for: "mask"), .none)
    }

    func test_setSelectionBuildsTestPatternSource() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage")])
        r.setSelection(.testPattern(id: "smpte_bars"), for: "inputImage")
        XCTAssertEqual(r.selection(for: "inputImage"), .testPattern(id: "smpte_bars"))
        XCTAssertEqual(r.source(for: "inputImage").displayName, "SMPTE Bars")
    }

    func test_nonImageInputsIgnored() throws {
        let r = try makeRouter()
        let floatInput = ISFPreviewInput(name: "amount", type: "float", defaultValue: 0.0, min: 0.0, max: 1.0, labels: nil, values: nil)
        r.updateInputs([floatInput])
        XCTAssertTrue(r.imageInputNames.isEmpty)
    }

    // MARK: A4 — pop-out mirroring + shared camera

    /// Mirrors the inline preview's source choices into a detached (pop-out) router so a filter
    /// renders its input there too, instead of black.
    func test_applySelectionsCopiesFromAnotherRouter() throws {
        let a = try makeRouter()
        let b = try makeRouter()
        a.updateInputs([imageInput("inputImage")])
        a.setSelection(.testPattern(id: "smpte_bars"), for: "inputImage")
        b.updateInputs([imageInput("inputImage")])

        b.applySelections(from: a)

        XCTAssertEqual(b.selection(for: "inputImage"), .testPattern(id: "smpte_bars"))
        XCTAssertEqual(b.source(for: "inputImage").displayName, "SMPTE Bars")
    }

    /// Both routers resolve `.camera` to the SAME injected instance — proving a single shared capture
    /// session feeds inline + pop-out rather than two competing AVCaptureSessions.
    func test_cameraSelectionUsesInjectedSharedCamera() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let cam = FakeImageSource(name: "SharedCam")
        let a = SourceRouter(device: device, queue: queue, camera: cam)
        let b = SourceRouter(device: device, queue: queue, camera: cam)
        a.updateInputs([imageInput("inputImage")])
        b.updateInputs([imageInput("inputImage")])

        a.setSelection(.camera, for: "inputImage")
        b.setSelection(.camera, for: "inputImage")

        XCTAssertTrue(a.source(for: "inputImage") === cam)
        XCTAssertTrue(b.source(for: "inputImage") === cam)
    }
}

@MainActor
private final class FakeImageSource: ImageSource {
    let displayName: String
    init(name: String) { displayName = name }
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? { nil }
}
