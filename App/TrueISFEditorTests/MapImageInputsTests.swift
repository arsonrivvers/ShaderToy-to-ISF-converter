import XCTest

@MainActor
final class MapImageInputsTests: XCTestCase {
    func test_filterImageInputIsSurfaced() {
        let controller = MetalPreviewController()
        let filter = """
        /*{ "DESCRIPTION": "passthrough", "CATEGORIES": ["Filter"], "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ] }*/
        void main() { gl_FragColor = IMG_THIS_PIXEL(inputImage); }
        """
        let expect = expectation(description: "compiled")
        controller.load(isf: filter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertTrue(controller.inputs.contains { $0.name == "inputImage" && $0.type == "image" })
            expect.fulfill()
        }
        wait(for: [expect], timeout: 4.0)
    }
}
