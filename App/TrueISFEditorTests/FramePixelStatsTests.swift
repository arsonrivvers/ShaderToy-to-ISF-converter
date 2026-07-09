import XCTest
import Metal
@testable import TrueISFEditor

final class FramePixelStatsTests: XCTestCase {
    // Tightly packed frames from per-pixel byte arrays.
    private func bgra8(_ pixels: [[UInt8]]) -> [UInt8] { pixels.flatMap { $0 } }

    func testBlackFrameBGRA8() {
        let bytes = bgra8([[0, 0, 0, 255], [0, 0, 0, 255]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 2, height: 1)
        XCTAssertNotNil(s)
        XCTAssertEqual(s!.maxLuma, 0)
        XCTAssertEqual(s!.nanCount, 0)
        XCTAssertTrue(s!.isConstant)
    }

    func testBGRAChannelOrderLuma() {
        // Pure red in BGRA byte order: [B,G,R,A] = [0,0,255,255]. Alpha must NOT count as luma.
        let bytes = bgra8([[0, 0, 255, 255], [0, 0, 0, 0]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 2, height: 1)!
        XCTAssertEqual(s.maxLuma, 1.0, accuracy: 0.001)
        XCTAssertFalse(s.isConstant)
    }

    func testAlphaOnlyPixelIsBlack() {
        // Opaque but zero RGB: alpha alone must not lift maxLuma above the black floor.
        let bytes = bgra8([[0, 0, 0, 255]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 1, height: 1)!
        XCTAssertEqual(s.maxLuma, 0)
    }

    func testNaNAndInfDetectedRGBA32Float() {
        let floats: [Float] = [Float.nan, 0, 0, 1,   0, Float.infinity, 0, 1]
        let bytes = floats.withUnsafeBytes { Array($0) }
        let s = FramePixelStats.analyze(bytes: bytes, format: .rgba32Float, width: 2, height: 1)!
        XCTAssertEqual(s.nanCount, 2)
    }

    func testRGBA16FloatLumaAndNaN() {
        let halves: [Float16] = [Float16(0.5), 0, 0, 1,   Float16.nan, 0, 0, 1]
        let bytes = halves.withUnsafeBytes { Array($0) }
        let s = FramePixelStats.analyze(bytes: bytes, format: .rgba16Float, width: 2, height: 1)!
        XCTAssertEqual(s.maxLuma, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.nanCount, 1)
    }

    func testConstantColorNonBlack() {
        let bytes = bgra8([[10, 200, 30, 255], [10, 200, 30, 255]])
        let s = FramePixelStats.analyze(bytes: bytes, format: .bgra8Unorm, width: 2, height: 1)!
        XCTAssertTrue(s.isConstant)
        XCTAssertGreaterThan(s.maxLuma, 0.5)
    }

    func testDigestsDifferForDifferentFrames() {
        let a = FramePixelStats.analyze(bytes: bgra8([[1, 2, 3, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        let b = FramePixelStats.analyze(bytes: bgra8([[3, 2, 1, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        XCTAssertNotEqual(a.digest, b.digest)
        let a2 = FramePixelStats.analyze(bytes: bgra8([[1, 2, 3, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        XCTAssertEqual(a.digest, a2.digest)
    }

    func testUnsupportedFormatReturnsNil() {
        XCTAssertFalse(FramePixelStats.supports(.depth32Float))
        XCTAssertNil(FramePixelStats.analyze(bytes: [0, 0, 0, 0], format: .depth32Float, width: 1, height: 1))
    }
}
