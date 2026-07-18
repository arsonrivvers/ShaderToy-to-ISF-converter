import XCTest

@MainActor
final class MapImageInputsTests: XCTestCase {
    func test_filterImageInputIsSurfaced() async throws {
        let controller = MetalPreviewController()
        let filter = """
        /*{ "DESCRIPTION": "passthrough", "CATEGORIES": ["Filter"], "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ] }*/
        void main() { gl_FragColor = IMG_THIS_PIXEL(inputImage); }
        """
        controller.load(isf: filter)
        try await waitUntil {
            controller.inputs.contains { $0.name == "inputImage" && $0.type == "image" }
                || controller.compileError != nil
        }
        XCTAssertNil(controller.compileError)
        XCTAssertTrue(controller.inputs.contains {
            $0.name == "inputImage" && $0.type == "image"
        })
    }

    private func waitUntil(timeout: TimeInterval = 10,
                           _ condition: @escaping () -> Bool) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("timed out waiting for image-input compile")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
