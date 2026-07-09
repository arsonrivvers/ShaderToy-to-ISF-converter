import XCTest
@testable import TrueISFEditor

final class PixelGateTests: XCTestCase {
    private func stats(luma: Double = 0.8, nan: Int = 0, constant: Bool = false,
                       digest: UInt64 = 1) -> FramePixelStats {
        FramePixelStats(maxLuma: luma, nanCount: nan, isConstant: constant, digest: digest)
    }

    func testEmptyOrNilFrameIsRenderError() {
        XCTAssertEqual(PixelGate.verdict([]), .renderError)
        XCTAssertEqual(PixelGate.verdict([stats(), nil, stats()]), .renderError)
    }

    func testNaNBeatsBlack() {
        let black = stats(luma: 0, nan: 1, digest: 2)
        XCTAssertEqual(PixelGate.verdict([black, black, black]), .nan)
    }

    func testAllFramesBlackIsBlack() {
        let f = stats(luma: 0.001, digest: 3)
        XCTAssertEqual(PixelGate.verdict([f, f, f]), .black)
    }

    func testFadeInIsNotBlack() {
        // Black only at t=0, lit and changing afterwards → OK.
        let v = PixelGate.verdict([stats(luma: 0, digest: 1),
                                   stats(luma: 0.5, digest: 2),
                                   stats(luma: 0.9, digest: 3)])
        XCTAssertEqual(v, .ok)
    }

    func testEqualDigestsIsStatic() {
        let f = stats(digest: 7)
        XCTAssertEqual(PixelGate.verdict([f, f, f]), .constant)
    }

    func testDifferentDigestsIsOK() {
        XCTAssertEqual(PixelGate.verdict([stats(digest: 1), stats(digest: 2), stats(digest: 3)]), .ok)
    }

    func testFailSet() {
        XCTAssertTrue(PixelVerdict.black.isFail)
        XCTAssertTrue(PixelVerdict.nan.isFail)
        XCTAssertTrue(PixelVerdict.renderError.isFail)
        XCTAssertFalse(PixelVerdict.ok.isFail)
        XCTAssertFalse(PixelVerdict.constant.isFail)
        XCTAssertFalse(PixelVerdict.unsupported.isFail)
    }

    func testImportOutcomeMapping() {
        XCTAssertNil(PixelGate.importOutcome(.ok))
        XCTAssertEqual(PixelGate.importOutcome(.constant)?.severity, .warning)
        XCTAssertEqual(PixelGate.importOutcome(.unsupported)?.severity, .warning)
        XCTAssertEqual(PixelGate.importOutcome(.black)?.severity, .error)
        XCTAssertEqual(PixelGate.importOutcome(.nan)?.severity, .error)
        XCTAssertEqual(PixelGate.importOutcome(.renderError)?.severity, .error)
        XCTAssertTrue(PixelGate.importOutcome(.black)!.message.contains("BLACK"))
    }

    // MARK: - SHADERTOY_DEBUG_GATE_TIMES parsing (triage affordance)

    func test_parseTimes_nilAndGarbage_returnNil() {
        XCTAssertNil(PixelGate.parseTimes(nil))
        XCTAssertNil(PixelGate.parseTimes(""))
        XCTAssertNil(PixelGate.parseTimes("abc,def"))
    }

    func test_parseTimes_commaSeparated_parsesAndTrims() {
        XCTAssertEqual(PixelGate.parseTimes("0, 0.75,2.0"), [0.0, 0.75, 2.0])
    }

    func test_parseTimes_partialGarbage_keepsValid() {
        XCTAssertEqual(PixelGate.parseTimes("0,x,4"), [0.0, 4.0])
    }
}
