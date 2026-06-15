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

    /// iChannelResolution[N] has no ISF equivalent (ISF has no per-channel resolution uniform).
    /// Map the whole indexed access — index included — to vec3(RENDERSIZE, 1.0); mapping the bare
    /// word would leave a dangling `[N]` that mis-indexes the constructor. Exact for buffer channels
    /// (ISF buffers are RENDERSIZE), approximate for image inputs.
    func test_iChannelResolution_constantIndex() {
        XCTAssertEqual(UniformRewriter.rewrite("iChannelResolution[0].xy"),
                       "vec3(RENDERSIZE, 1.0).xy")
    }
    func test_iChannelResolution_variableIndexAndWhitespace() {
        XCTAssertEqual(UniformRewriter.rewrite("iChannelResolution [ i ].x"),
                       "vec3(RENDERSIZE, 1.0).x")
    }
    func test_iChannelResolution_doesNotClobberPlainIResolution() {
        XCTAssertEqual(UniformRewriter.rewrite("iChannelResolution[1] + iResolution.xy"),
                       "vec3(RENDERSIZE, 1.0) + vec3(RENDERSIZE, 1.0).xy")
    }

    /// iChannelTime[N] (per-channel playback time, seconds) has no ISF equivalent — map the whole
    /// indexed access to TIME (ISF's global clock). Like iChannelResolution, the index must be
    /// consumed; mapping the bare word would leave a dangling `[N]` indexing a float.
    func test_iChannelTime_constantIndex() {
        XCTAssertEqual(UniformRewriter.rewrite("float t = iChannelTime[0];"), "float t = TIME;")
    }
    func test_iChannelTime_variableIndexAndWhitespace() {
        XCTAssertEqual(UniformRewriter.rewrite("iChannelTime [ ch ]"), "TIME")
    }
}
