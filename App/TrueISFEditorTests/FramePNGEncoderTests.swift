import XCTest
import Metal
import ImageIO
import CoreGraphics
@testable import TrueISFEditor

/// The byte-level encoder is pure — these run with no GPU, mirroring FramePixelStatsTests.
final class FramePNGEncoderTests: XCTestCase {
    private func bgra8(_ pixels: [[UInt8]]) -> [UInt8] { pixels.flatMap { $0 } }

    /// Decode a PNG back into a known RGBA8 layout so assertions don't depend on the
    /// decoder's preferred format. Returns row-major, top row first, 4 bytes per pixel.
    private func decodeRGBA(_ png: Data) -> (w: Int, h: Int, bytes: [UInt8])? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (w, h, bytes) : nil
    }

    func testEmitsPNGSignature() {
        let png = FramePNGEncoder.encodePNG(
            bytes: bgra8([[0, 0, 0, 255]]), format: .bgra8Unorm, width: 1, height: 1)
        XCTAssertNotNil(png)
        XCTAssertEqual(Array(png!.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testDimensionsPreserved() {
        let bytes = bgra8(Array(repeating: [0, 0, 0, 255], count: 6))
        let png = FramePNGEncoder.encodePNG(bytes: bytes, format: .bgra8Unorm, width: 3, height: 2)!
        let out = decodeRGBA(png)
        XCTAssertEqual(out?.w, 3)
        XCTAssertEqual(out?.h, 2)
    }

    /// The B/R swap is the silent killer here: it would tint every captured frame without
    /// ever failing a signature or dimension check.
    func testBGRAChannelOrderIsCorrectedNotSwapped() {
        // Pure red in BGRA byte order is [B,G,R,A] = [0,0,255,255].
        let png = FramePNGEncoder.encodePNG(
            bytes: bgra8([[0, 0, 255, 255]]), format: .bgra8Unorm, width: 1, height: 1)!
        let out = decodeRGBA(png)!
        XCTAssertEqual(out.bytes[0], 255, "red channel")
        XCTAssertEqual(out.bytes[1], 0, "green channel")
        XCTAssertEqual(out.bytes[2], 0, "blue channel")
    }

    func testRGBA8ChannelOrderPassesThrough() {
        let png = FramePNGEncoder.encodePNG(
            bytes: [0, 0, 255, 255], format: .rgba8Unorm, width: 1, height: 1)!
        let out = decodeRGBA(png)!
        XCTAssertEqual(out.bytes[0], 0, "red channel")
        XCTAssertEqual(out.bytes[2], 255, "blue channel")
    }

    /// A Y-flip here would mirror every capture, and every frame would still look plausible.
    func testRowZeroStaysRowZero() {
        // Row 0 white, row 1 black. Metal getBytes row 0 is the top row; PNG row 0 is the top row.
        let bytes = bgra8([[255, 255, 255, 255], [0, 0, 0, 255]])
        let png = FramePNGEncoder.encodePNG(bytes: bytes, format: .bgra8Unorm, width: 1, height: 2)!
        let out = decodeRGBA(png)!
        XCTAssertEqual(out.bytes[0], 255, "top row must stay the white one")
        XCTAssertEqual(out.bytes[4], 0, "bottom row must stay the black one")
    }

    func testFloatFormatClampsAboveOneAndZeroesNaN() {
        // Pixel 0: HDR overshoot must clamp to white, not wrap. Pixel 1: NaN must not
        // become garbage — a NaN frame should read as black, which is what the flash
        // analyzer downstream expects to see.
        let floats: [Float] = [2.5, 2.5, 2.5, 1.0,
                               Float.nan, Float.nan, Float.nan, 1.0]
        let bytes = floats.withUnsafeBytes { Array($0) }
        let png = FramePNGEncoder.encodePNG(bytes: bytes, format: .rgba32Float, width: 2, height: 1)!
        let out = decodeRGBA(png)!
        XCTAssertEqual(out.bytes[0], 255, "2.5 must clamp to 255")
        XCTAssertEqual(out.bytes[4], 0, "NaN must encode as 0")
    }

    func testHalfFloatFormatEncodes() {
        let halves: [Float16] = [Float16(1.0), 0, 0, 1]
        let bytes = halves.withUnsafeBytes { Array($0) }
        let png = FramePNGEncoder.encodePNG(bytes: bytes, format: .rgba16Float, width: 1, height: 1)!
        let out = decodeRGBA(png)!
        XCTAssertEqual(out.bytes[0], 255)
        XCTAssertEqual(out.bytes[1], 0)
    }

    func testUnsupportedFormatReturnsNil() {
        XCTAssertNil(FramePNGEncoder.encodePNG(
            bytes: [0, 0, 0, 0], format: .depth32Float, width: 1, height: 1))
    }

    /// Silently encoding a short buffer would emit a frame built partly from uninitialized
    /// memory, and it would look like a real capture.
    func testTruncatedBufferReturnsNil() {
        XCTAssertNil(FramePNGEncoder.encodePNG(
            bytes: [0, 0, 0, 255], format: .bgra8Unorm, width: 4, height: 4))
    }

    func testZeroDimensionsReturnNil() {
        XCTAssertNil(FramePNGEncoder.encodePNG(
            bytes: [], format: .bgra8Unorm, width: 0, height: 0))
    }
}
