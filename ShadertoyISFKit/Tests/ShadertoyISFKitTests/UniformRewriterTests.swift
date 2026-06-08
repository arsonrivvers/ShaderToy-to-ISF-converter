import XCTest
@testable import ShadertoyISFKit

final class UniformRewriterTests: XCTestCase {
    func test_iResolution() {
        XCTAssertEqual(UniformRewriter.rewrite("fragCoord/iResolution.xy"),
                       "fragCoord/vec3(RENDERSIZE, 1.0).xy")
    }
    func test_iTime_notClobberedByDelta() {
        XCTAssertEqual(UniformRewriter.rewrite("a=iTime; b=iTimeDelta;"),
                       "a=TIME; b=max(TIMEDELTA, 1e-4);")
    }
    func test_iFrame_and_iDate() {
        XCTAssertEqual(UniformRewriter.rewrite("iFrame + iDate.w"), "FRAMEINDEX + DATE.w")
    }
    func test_iSampleRate_constant() {
        XCTAssertEqual(UniformRewriter.rewrite("iSampleRate"), "44100.0")
    }
    func test_wordBoundary_doesNotTouchSubstrings() {
        XCTAssertEqual(UniformRewriter.rewrite("miTime myiFrame"), "miTime myiFrame")
    }
}
