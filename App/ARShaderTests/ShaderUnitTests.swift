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

    /// F13d: the unreadable-file path did not bump `loadGeneration`, so a compile already in flight
    /// landed AFTERWARDS and applied — clearing the error just reported, swapping the deck, and
    /// stamping `sourceURL` with the shader the operator had already moved on from. On the slot
    /// bank that lights the WRONG slot's live badge, since `liveDeck(for:)` compares `sourceURL`.
    ///
    /// The inverted expectation is the assertion, not decoration: with the fix, A's compile is
    /// superseded and `apply` returns before `onCompileFinished`, so the callback must never fire.
    func testAnUnreadableFileSupersedesACompileAlreadyInFlight() throws {
        let readable = FileManager.default.temporaryDirectory
            .appendingPathComponent("shaderunit-\(UUID().uuidString).fs")
        try fixture("solid_red").write(to: readable, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: readable) }

        unit.load(url: readable)                                  // A: compile now in flight
        unit.load(url: readable.appendingPathExtension("gone"))   // B: unreadable, reports at once

        let landed = expectation(description: "A's compile must NOT apply")
        landed.isInverted = true
        unit.onCompileFinished = { landed.fulfill() }
        wait(for: [landed], timeout: 3)
        unit.onCompileFinished = nil

        XCTAssertNotNil(unit.compileError,
                        "the error the operator was just shown must not be cleared by a load they "
                        + "had already moved on from")
        XCTAssertNil(unit.sourceURL,
                     "and a superseded load must never stamp sourceURL — that is what lights the "
                     + "wrong slot's live badge")
        XCTAssertFalse(unit.isLoading, "no spinner left up by a load nothing will finish")
    }

    func testRenderOffscreenReturnsNilWithNoSceneLoaded() throws {
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(unit.renderOffscreen(size: MTLSize(width: 64, height: 64, depth: 1), in: cb),
                     "an empty unit contributes nothing — it does not paint black")
    }
}
