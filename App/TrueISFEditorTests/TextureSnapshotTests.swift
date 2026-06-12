import XCTest
import Metal
@testable import TrueISFEditor

final class TextureSnapshotTests: XCTestCase {
    private func makeTexture(_ device: MTLDevice, width: Int, height: Int,
                             format: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                         width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }

    func test_bgra8Texture_convertsToCGImage_atFullSize() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 8, height: 6) else { throw XCTSkip("no Metal") }
        var pixels = [UInt8](repeating: 0, count: 8 * 6 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i + 2] = 255; pixels[i + 3] = 255 } // red, opaque
        tex.replace(region: MTLRegionMake2D(0, 0, 8, 6), mipmapLevel: 0,
                    withBytes: pixels, bytesPerRow: 8 * 4)
        let img = TextureSnapshot.cgImage(from: tex, maxDimension: 64)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 8)
        XCTAssertEqual(img?.height, 6)
    }

    func test_largeTexture_downscalesToMaxDimension() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 128, height: 64) else { throw XCTSkip("no Metal") }
        let img = TextureSnapshot.cgImage(from: tex, maxDimension: 64)
        XCTAssertEqual(img?.width, 64)
        XCTAssertEqual(img?.height, 32)
    }

    func test_floatTexture_converts() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 4, height: 4, format: .rgba16Float)
        else { throw XCTSkip("no Metal") }
        XCTAssertNotNil(TextureSnapshot.cgImage(from: tex, maxDimension: 64))
    }

    func test_unsupportedFormat_returnsNil_notCrash() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let tex = makeTexture(device, width: 4, height: 4, format: .depth32Float)
        else { throw XCTSkip("no Metal") }
        XCTAssertNil(TextureSnapshot.cgImage(from: tex, maxDimension: 64))
    }
}
