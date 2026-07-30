import CoreGraphics
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Encodes a rendered frame to PNG. The byte-level `encodePNG` is pure — unit tests feed
/// synthetic frames with no GPU, mirroring `FramePixelStats`.
///
/// Alpha is deliberately dropped (`noneSkipLast`): captures feed a video encoder and a flash
/// analyzer, both of which want composited RGB, and carrying straight-vs-premultiplied alpha
/// through that chain only creates ways to be wrong. Non-finite float components encode as 0 —
/// `FramePixelStats.nanCount` is the channel that *detects* NaN, this one only has to not
/// produce garbage bytes.
enum FramePNGEncoder {
    /// Same supported set as the pixel gate — a format one accepts and the other rejects
    /// would strand frames mid-capture.
    static func supports(_ format: MTLPixelFormat) -> Bool { FramePixelStats.supports(format) }

    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .rgba32Float: return 16
        case .rgba16Float: return 8
        default: return 4
        }
    }

    private static func clampToByte(_ v: Double) -> UInt8 {
        guard v.isFinite else { return 0 }
        return UInt8(max(0.0, min(1.0, v)) * 255.0 + 0.5)
    }

    /// Reads a CPU-accessible texture back and encodes it. The caller must have committed and
    /// waited on the command buffer that produced it — pool textures aren't guaranteed
    /// CPU-readable, so blit into a `.managed` readback texture first.
    static func encodePNG(texture: MTLTexture) -> Data? {
        guard supports(texture.pixelFormat) else { return nil }
        let w = texture.width, h = texture.height
        let bytesPerRow = w * bytesPerPixel(texture.pixelFormat)
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return encodePNG(bytes: bytes, format: texture.pixelFormat, width: w, height: h)
    }

    /// Pure byte-level encode. `bytes` is tightly packed (bytesPerRow == width × bpp) and row 0
    /// is the top row, which is both Metal's `getBytes` order and PNG's — no flip anywhere.
    static func encodePNG(bytes: [UInt8], format: MTLPixelFormat,
                          width: Int, height: Int) -> Data? {
        guard supports(format) else { return nil }
        let bpp = bytesPerPixel(format)
        let pixelCount = width * height
        guard pixelCount > 0, bytes.count >= pixelCount * bpp else { return nil }

        var rgba = [UInt8](repeating: 255, count: pixelCount * 4)
        bytes.withUnsafeBytes { raw in
            for p in 0..<pixelCount {
                let src = p * bpp, dst = p * 4
                switch format {
                case .bgra8Unorm, .bgra8Unorm_srgb:
                    rgba[dst] = raw[src + 2]
                    rgba[dst + 1] = raw[src + 1]
                    rgba[dst + 2] = raw[src]
                case .rgba32Float:
                    for c in 0..<3 {
                        let v = raw.loadUnaligned(fromByteOffset: src + c * 4, as: Float.self)
                        rgba[dst + c] = clampToByte(Double(v))
                    }
                case .rgba16Float:
                    for c in 0..<3 {
                        let v = raw.loadUnaligned(fromByteOffset: src + c * 2, as: Float16.self)
                        rgba[dst + c] = clampToByte(Double(v))
                    }
                default:                                    // rgba8Unorm / rgba8Unorm_srgb
                    rgba[dst] = raw[src]
                    rgba[dst + 1] = raw[src + 1]
                    rgba[dst + 2] = raw[src + 2]
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
