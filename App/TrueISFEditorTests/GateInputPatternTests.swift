import XCTest
import Metal
@testable import TrueISFEditor

final class GateInputPatternTests: XCTestCase {
    func testBytesDeterministicNonBlackNonConstant() {
        let a = GateInputPattern.bytes()
        let b = GateInputPattern.bytes()
        XCTAssertEqual(a, b, "pattern must be identical every run — the pass-list is a baseline")
        let s = FramePixelStats.analyze(bytes: a, format: .bgra8Unorm,
                                        width: GateInputPattern.size, height: GateInputPattern.size)!
        XCTAssertGreaterThan(s.maxLuma, 0.5, "pattern must be clearly non-black")
        XCTAssertFalse(s.isConstant, "pattern must vary spatially to exercise sampling")
    }

    func testMakeTextureUploadsPattern() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let tex = try XCTUnwrap(GateInputPattern.makeTexture(device: device))
        XCTAssertEqual(tex.width, GateInputPattern.size)
        XCTAssertEqual(tex.pixelFormat, .bgra8Unorm)
        let s = try XCTUnwrap(FramePixelStats.analyze(texture: tex))
        XCTAssertGreaterThan(s.maxLuma, 0.5)
    }
}
