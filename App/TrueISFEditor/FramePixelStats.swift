import Metal

/// Per-frame pixel statistics for the pixel-truth render gate. The byte-level `analyze` is pure —
/// unit tests feed synthetic frames with no GPU. See
/// docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md.
struct FramePixelStats: Equatable {
    /// Max over pixels of max(R,G,B) (alpha excluded), normalized 0–1. NaN/Inf components are
    /// excluded here — they are counted separately in `nanCount`.
    let maxLuma: Double
    /// NaN/Inf color-component count (float formats only; always 0 for 8-bit).
    let nanCount: Int
    /// True when every pixel's raw bytes equal the first pixel's.
    let isConstant: Bool
    /// FNV-1a 64 hash of the raw bytes, for cross-frame comparison.
    let digest: UInt64

    /// Formats the analyzer understands (mirrors TextureSnapshot's supported set).
    static func supports(_ format: MTLPixelFormat) -> Bool {
        switch format {
        case .bgra8Unorm, .bgra8Unorm_srgb, .rgba8Unorm, .rgba8Unorm_srgb,
             .rgba16Float, .rgba32Float:
            return true
        default:
            return false
        }
    }

    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .rgba32Float: return 16
        case .rgba16Float: return 8
        default: return 4
        }
    }

    /// Reads a CPU-accessible texture back and analyzes it. The caller must have committed and
    /// waited on the command buffer that produced it (the gate blits into a readback texture
    /// first — pool textures aren't guaranteed CPU-readable).
    static func analyze(texture: MTLTexture) -> FramePixelStats? {
        guard supports(texture.pixelFormat) else { return nil }
        let w = texture.width
        let h = texture.height
        let bytesPerRow = w * bytesPerPixel(texture.pixelFormat)
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return analyze(bytes: bytes, format: texture.pixelFormat, width: w, height: h)
    }

    /// Pure byte-level analysis. `bytes` is tightly packed (bytesPerRow == width × bpp).
    static func analyze(bytes: [UInt8], format: MTLPixelFormat,
                        width: Int, height: Int) -> FramePixelStats? {
        guard supports(format) else { return nil }
        let bpp = bytesPerPixel(format)
        let pixelCount = width * height
        guard bytes.count >= pixelCount * bpp, pixelCount > 0 else { return nil }

        var maxLuma = 0.0
        var nanCount = 0
        var isConstant = true
        var digest: UInt64 = 0xcbf29ce484222325            // FNV-1a offset basis
        for byte in bytes[..<(pixelCount * bpp)] {
            digest = (digest ^ UInt64(byte)) &* 0x100000001b3
        }

        // RGB component byte offsets within one pixel (alpha excluded from luma).
        let rgbOffsets: [Int]
        switch format {
        case .bgra8Unorm, .bgra8Unorm_srgb: rgbOffsets = [2, 1, 0]
        default: rgbOffsets = [0, 1, 2]                    // rgba8 / rgba16F / rgba32F
        }

        bytes.withUnsafeBytes { raw in
            for p in 0..<pixelCount {
                let base = p * bpp
                if isConstant && p > 0 {
                    for i in 0..<bpp where raw[base + i] != raw[i] {
                        isConstant = false
                        break
                    }
                }
                switch format {
                case .rgba32Float:
                    for c in 0..<4 {
                        let v = raw.loadUnaligned(fromByteOffset: base + c * 4, as: Float.self)
                        if !v.isFinite { nanCount += 1 }
                        else if c < 3 { maxLuma = max(maxLuma, Double(v)) }
                    }
                case .rgba16Float:
                    for c in 0..<4 {
                        let v = raw.loadUnaligned(fromByteOffset: base + c * 2, as: Float16.self)
                        if !v.isFinite { nanCount += 1 }
                        else if c < 3 { maxLuma = max(maxLuma, Double(v)) }
                    }
                default:
                    for off in rgbOffsets {
                        maxLuma = max(maxLuma, Double(raw[base + off]) / 255.0)
                    }
                }
            }
        }
        return FramePixelStats(maxLuma: maxLuma, nanCount: nanCount,
                               isConstant: isConstant, digest: digest)
    }
}
