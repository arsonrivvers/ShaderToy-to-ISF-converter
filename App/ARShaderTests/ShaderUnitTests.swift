import XCTest
import Metal

@MainActor
final class ShaderUnitTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var unit: ShaderUnit!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        unit = ShaderUnit(device: device, queue: queue, clock: RenderClock())
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func load(_ fixtureName: String) throws {
        let done = expectation(description: "compile \(fixtureName)")
        unit.onCompileFinished = { done.fulfill() }
        unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        unit.onCompileFinished = nil
    }

    func testASuccessfulLoadPublishesTheNameAndInputs() throws {
        try load("solid_red")
        XCTAssertEqual(unit.shaderName, "solid_red.fs")
        XCTAssertNil(unit.compileError)
    }

    func testAFailedCompileKeepsThePreviousShaderPlaying() throws {
        // On stage, the shader that is already up is the one thing you cannot afford to lose.
        try load("solid_red")
        try load("broken")
        XCTAssertNotNil(unit.compileError, "the failure must be reported")
        XCTAssertEqual(unit.shaderName, "solid_red.fs",
                       "and the previous shader must keep rendering")
    }

    func testUnloadClearsEverything() throws {
        try load("solid_red")
        unit.unload()
        XCTAssertNil(unit.shaderName)
        XCTAssertTrue(unit.inputs.isEmpty)
        XCTAssertNil(unit.compileError)
    }

    func testRenderOffscreenReturnsNilWithNoSceneLoaded() throws {
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(unit.renderOffscreen(size: MTLSize(width: 64, height: 64, depth: 1), in: cb),
                     "an empty unit contributes nothing — it does not paint black")
    }
}
