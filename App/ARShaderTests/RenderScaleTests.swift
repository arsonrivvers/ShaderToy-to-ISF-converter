import XCTest

final class RenderScaleTests: XCTestCase {
    func testPercentClampsToTheSafeRange() {
        XCTAssertEqual(RenderScale(percent: 0).percent, RenderScale.minPercent)
        XCTAssertEqual(RenderScale(percent: -40).percent, RenderScale.minPercent)
        XCTAssertEqual(RenderScale(percent: 400).percent, RenderScale.maxPercent,
                       "Above 100% is supersampling — 4x the cost, deliberately out of scope")
    }

    func testFullScaleIsExactlyTheOutputSize() {
        let out = RenderSize(width: 1920, height: 1080)
        XCTAssertEqual(RenderScale.full.applied(to: out), out,
                       "100% must be identity — no rounding drift on the common path")
    }

    func testHalfScaleIsAQuarterOfThePixels() {
        let out = RenderSize(width: 1920, height: 1080)
        let half = RenderScale(percent: 50).applied(to: out)
        XCTAssertEqual(half.width, 960)
        XCTAssertEqual(half.height, 540)
        XCTAssertEqual(half.megapixels, out.megapixels / 4, accuracy: 0.01)
    }

    func testScalingPreservesAspectSoACuedDeckNeverStretches() {
        // A cued deck is faded INTO the program. A different aspect would stretch it at exactly
        // the wrong moment.
        let out = RenderSize(width: 1080, height: 1920)   // vertical, for LED columns
        let scaled = RenderScale(percent: 33).applied(to: out)
        XCTAssertEqual(Double(scaled.width) / Double(scaled.height),
                       Double(out.width) / Double(out.height), accuracy: 0.01)
    }

    func testTheMinimumScaleStillProducesARenderableSize() {
        let tiny = RenderScale(percent: RenderScale.minPercent)
            .applied(to: RenderSize(width: 1920, height: 1080))
        XCTAssertGreaterThanOrEqual(tiny.width, RenderSize.minDimension)
        XCTAssertGreaterThanOrEqual(tiny.height, RenderSize.minDimension)
    }

    func testDefaultsMatchTheSpec() {
        XCTAssertEqual(RenderScale.defaultRender.percent, 100, "live output is full quality")
        XCTAssertEqual(RenderScale.defaultCue.percent, 50, "a cued deck feeds only a small monitor")
    }
}
