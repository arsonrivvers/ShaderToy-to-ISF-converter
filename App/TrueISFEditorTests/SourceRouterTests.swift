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
}
