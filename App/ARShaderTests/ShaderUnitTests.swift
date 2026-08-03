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

    // MARK: - Which file failed (2026-08-03 Client Success review)

    /// `compileError` names the line and the GLSL fault precisely and never names the FILE, while
    /// `shaderName` correctly keeps naming the shader still on screen. Together those two truths
    /// produced a compiler dump attributed, by position, to a deck that was working fine.
    func testAFailedCompileRecordsWhichFileFailed() throws {
        try load("solid_red")
        try load("broken")
        XCTAssertEqual(unit.failedLoadName, "broken.fs",
                       "the attempted file is the only thing the failure path used to discard")
        XCTAssertEqual(unit.shaderName, "solid_red.fs")
    }

    /// The sentence a performer reads mid-set. Asserted on the string, not on the two fields it is
    /// derived from — a summary that named the wrong file would satisfy any field-level check.
    func testTheFailureSummaryNamesBothTheFailedFileAndTheOneStillPlaying() throws {
        try load("solid_red")
        try load("broken")
        let summary = try XCTUnwrap(unit.loadFailureSummary)
        XCTAssertTrue(summary.contains("broken.fs"), "must name what failed — got: \(summary)")
        XCTAssertTrue(summary.contains("solid_red.fs"),
                      "must name what is still playing — got: \(summary)")
    }

    /// With nothing loaded there is nothing to still be on, and saying otherwise would be the same
    /// misattribution one step removed.
    func testAFailedCompileOnAnEmptyDeckClaimsNoSurvivingShader() throws {
        try load("broken")
        let summary = try XCTUnwrap(unit.loadFailureSummary)
        XCTAssertTrue(summary.contains("broken.fs"))
        XCTAssertFalse(summary.contains("still on"),
                       "nothing was playing to survive — got: \(summary)")
    }

    /// A stale warning is worse than none: it would accuse the shader that just loaded correctly.
    func testASuccessfulLoadClearsTheFailure() throws {
        try load("broken")
        XCTAssertNotNil(unit.failedLoadName)
        try load("solid_red")
        XCTAssertNil(unit.failedLoadName)
        XCTAssertNil(unit.loadFailureSummary)
    }

    func testUnloadClearsTheFailure() throws {
        try load("broken")
        unit.unload()
        XCTAssertNil(unit.failedLoadName)
        XCTAssertNil(unit.loadFailureSummary)
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
