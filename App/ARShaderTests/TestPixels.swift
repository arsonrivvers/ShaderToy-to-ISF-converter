import Metal

/// Mean RGB of a CPU-readable texture, in linear 0-1. Supports the formats the instrument produces
/// (`.rgba16Float` master and deck outputs) plus the 8-bit formats ISF scenes commonly return.
enum TestPixels {
    static func meanRGB(of texture: MTLTexture) -> SIMD3<Double>? {
        let w = texture.width, h = texture.height
        guard w > 0, h > 0 else { return nil }
        var sum = SIMD3<Double>(0, 0, 0)

        switch texture.pixelFormat {
        case .rgba16Float:
            var bytes = [UInt16](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: w * 8,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            for i in stride(from: 0, to: bytes.count, by: 4) {
                sum += SIMD3(Double(Float16(bitPattern: bytes[i])),
                             Double(Float16(bitPattern: bytes[i + 1])),
                             Double(Float16(bitPattern: bytes[i + 2])))
            }
        case .bgra8Unorm, .bgra8Unorm_srgb:
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: w * 4,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            for i in stride(from: 0, to: bytes.count, by: 4) {
                sum += SIMD3(Double(bytes[i + 2]) / 255.0, Double(bytes[i + 1]) / 255.0,
                             Double(bytes[i]) / 255.0)
            }
        case .rgba8Unorm, .rgba8Unorm_srgb:
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: w * 4,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            for i in stride(from: 0, to: bytes.count, by: 4) {
                sum += SIMD3(Double(bytes[i]) / 255.0, Double(bytes[i + 1]) / 255.0,
                             Double(bytes[i + 2]) / 255.0)
            }
        default:
            return nil
        }
        return sum / Double(w * h)
    }

    /// Mean alpha. Only `.rgba16Float` is needed today — the instrument's master and deck format.
    static func meanAlpha(of texture: MTLTexture) -> Double? {
        let w = texture.width, h = texture.height
        guard w > 0, h > 0, texture.pixelFormat == .rgba16Float else { return nil }
        var bytes = [UInt16](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: w * 8,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        var sum = 0.0
        for i in stride(from: 3, to: bytes.count, by: 4) {
            sum += Double(Float16(bitPattern: bytes[i]))
        }
        return sum / Double(w * h)
    }
}
