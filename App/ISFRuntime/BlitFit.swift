import Metal
import CoreGraphics
/// Aspect-fit math for the preview display (blit) pass. Pure — unit-tested without Metal.
enum BlitFit {
    /// NDC scale factors that letterbox/pillarbox a texture into a drawable without distortion.
    /// `(1,1)` when aspects match; one axis < 1 (the bars) otherwise. Safe on zero sizes.
    static func scale(textureSize: MTLSize, drawableSize: CGSize) -> SIMD2<Float> {
        let texW = Double(textureSize.width), texH = Double(textureSize.height)
        let drawW = Double(drawableSize.width), drawH = Double(drawableSize.height)
        guard texW > 0, texH > 0, drawW > 0, drawH > 0 else { return SIMD2(1, 1) }
        let texAR = texW / texH
        let viewAR = drawW / drawH
        if viewAR > texAR {
            return SIMD2(Float(texAR / viewAR), 1)   // view wider than content → pillarbox (bars L/R)
        } else {
            return SIMD2(1, Float(viewAR / texAR))   // view taller than content → letterbox (bars T/B)
        }
    }

    /// Largest rectangle of the given aspect (w/h) that fits inside `drawable`. Clamped to ≥ 1×1.
    static func inscribe(aspect: Double, in drawable: CGSize) -> MTLSize {
        let drawW = Double(drawable.width), drawH = Double(drawable.height)
        guard aspect > 0, drawW > 0, drawH > 0 else { return MTLSize(width: 1, height: 1, depth: 1) }
        let drawAR = drawW / drawH
        let w: Double, h: Double
        if drawAR > aspect {
            h = drawH; w = h * aspect   // drawable wider than content → limited by height
        } else {
            w = drawW; h = w / aspect   // drawable taller than content → limited by width
        }
        return MTLSize(width: max(Int(w.rounded()), 1), height: max(Int(h.rounded()), 1), depth: 1)
    }
}
