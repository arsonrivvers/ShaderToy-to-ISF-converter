import CoreGraphics
import CoreImage
import Metal

/// Converts a Metal texture into a small CGImage for lineage-tree row swatches. Core Image
/// handles the engine's output formats uniformly (bgra8 and float alike); unsupported formats
/// (e.g. depth) return nil and callers fall back to a glyph — never an error, never a crash.
enum TextureSnapshot {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func cgImage(from texture: MTLTexture, maxDimension: CGFloat = 64) -> CGImage? {
        let supported: Set<MTLPixelFormat> = [.bgra8Unorm, .bgra8Unorm_srgb, .rgba8Unorm,
                                              .rgba8Unorm_srgb, .rgba16Float, .rgba32Float]
        guard supported.contains(texture.pixelFormat) else { return nil }
        guard let ci = CIImage(mtlTexture: texture,
                               options: [.colorSpace: CGColorSpaceCreateDeviceRGB()])
        else { return nil }
        // Metal textures are top-left origin; CIImage is bottom-left — flip vertically.
        let flipped = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -ci.extent.height))
        let scale = min(1, maxDimension / max(flipped.extent.width, flipped.extent.height))
        let scaled = flipped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
