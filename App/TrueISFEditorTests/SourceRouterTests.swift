import XCTest
import Metal
import ShadertoyISFKit

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

    func test_updateInputsDefaultsToCameraAndPrunes() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage"), imageInput("mask")])
        XCTAssertEqual(Set(r.imageInputNames), ["inputImage", "mask"])
        // Filters auto-load the camera (2026-07-14) so they show something moving on load.
        XCTAssertEqual(r.selection(for: "inputImage"), .camera)

        r.updateInputs([imageInput("inputImage")])
        XCTAssertEqual(r.imageInputNames, ["inputImage"])
        XCTAssertEqual(r.selection(for: "mask"), .none)   // pruned input reverts to unrouted
    }

    /// Secondary image inputs (blend layers, masks) default to a moving test pattern DISTINCT
    /// from the primary input's camera. Two identical camera feeds make a blend filter render as
    /// identity — "Layer Blend does nothing" (Conner, 2026-07-18).
    func test_secondaryImageInputsDefaultToDistinctPattern() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage"), imageInput("blendImage"), imageInput("mask")])
        XCTAssertEqual(r.selection(for: "inputImage"), .camera)
        XCTAssertEqual(r.selection(for: "blendImage"), .testPattern(id: "scrolling_checker"))
        XCTAssertEqual(r.selection(for: "mask"), .testPattern(id: "scrolling_checker"))
    }

    /// A later recompile that ADDS a secondary input must not disturb the primary's existing
    /// route, and the new input still gets the distinct-pattern default.
    func test_addedSecondaryInputDefaultsToPatternWithoutTouchingPrimary() throws {
        let r = try makeRouter()
        r.updateInputs([imageInput("inputImage")])
        r.setSelection(.testPattern(id: "smpte_bars"), for: "inputImage")
        r.updateInputs([imageInput("inputImage"), imageInput("blendImage")])
        XCTAssertEqual(r.selection(for: "inputImage"), .testPattern(id: "smpte_bars"))
        XCTAssertEqual(r.selection(for: "blendImage"), .testPattern(id: "scrolling_checker"))
    }

    /// Camera-denied machines must never show black (C10): the camera default (and any explicit
    /// camera pick) falls back to the default test pattern.
    func test_cameraDefaultFallsBackToPatternWhenBlocked() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let r = SourceRouter(device: device, queue: queue, cameraBlocked: { true })
        r.updateInputs([imageInput("inputImage")])
        XCTAssertEqual(r.selection(for: "inputImage"), .camera)   // UI still shows Camera picked
        XCTAssertEqual(r.source(for: "inputImage").displayName,
                       TestPatternCatalog.default.name)           // but the source is the pattern
    }

    /// With camera access available, the default route resolves to the (injected) shared camera.
    func test_cameraDefaultUsesCameraWhenAvailable() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let cam = FakeImageSource(name: "SharedCam")
        let r = SourceRouter(device: device, queue: queue, camera: cam, cameraBlocked: { false })
        r.updateInputs([imageInput("inputImage")])
        XCTAssertTrue(r.source(for: "inputImage") === cam)
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
