import Metal

/// Deterministic 64×64 bgra8 texture bound to every image input before a pixel-gate render
/// (offscreen gate renders bind nothing, so texture-sampling shaders would false-fail black).
/// Gradient-checker with distinct hue quadrants — non-black everywhere, no symmetry that could
/// mask flipped or wrong-scaled sampling. Same bytes every run: the pixel pass-list is a baseline.
enum GateInputPattern {
    static let size = 64

    static func bytes() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                // Intensity ramp 32…223 (never black) + an 8px checker for spatial variation.
                let ramp = UInt8(32 + (x + y) * 191 / (2 * (size - 1)))
                let checker: UInt8 = ((x / 8 + y / 8) % 2 == 0) ? 224 : 96
                let top = y < size / 2
                let left = x < size / 2
                // Quadrant hues (BGRA byte order): TL red, TR green, BL blue, BR magenta.
                let r: UInt8 = (top && left) || (!top && !left) ? checker : ramp
                let g: UInt8 = (top && !left) ? checker : ramp
                let b: UInt8 = (!top) ? checker : ramp
                out.append(contentsOf: [b, g, r, 255])
            }
        }
        return out
    }

    static func makeTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        let b = bytes()
        b.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: size * 4)
        }
        return tex
    }
}
