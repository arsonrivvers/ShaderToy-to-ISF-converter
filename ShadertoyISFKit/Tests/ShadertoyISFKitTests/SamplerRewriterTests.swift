import XCTest
@testable import ShadertoyISFKit

final class SamplerRewriterTests: XCTestCase {
    private func binding() -> [Int: ChannelBinding.Binding] {
        [0: .init(glslName: "bufA", kind: .buffer),
         1: .init(glslName: "iChannel1img", kind: .texture)]
    }

    func test_texture_toNormPixel() {
        let r = SamplerRewriter.rewrite("texture(iChannel0, uv)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(bufA, uv)")
    }
    func test_texture2D_toNormPixel() {
        let r = SamplerRewriter.rewrite("texture2D(iChannel1, uv)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(iChannel1img, uv)")
    }
    func test_texelFetch_toPixel() {
        let r = SamplerRewriter.rewrite("texelFetch(iChannel0, ivec2(p), 0)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_PIXEL(bufA, vec2(ivec2(p)))")
    }
    func test_textureLod_dropsLod_andWarns() {
        let r = SamplerRewriter.rewrite("textureLod(iChannel0, uv, 2.0)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(bufA, uv)")
        XCTAssertTrue(r.warnings.contains { $0.message.contains("LOD") })
    }

    /// Regression for N323DD: a bare `iChannelN` used as a value (e.g. passed as a function
    /// argument, not inside a builtin sampling call) must be rewritten to the bound sampler name.
    /// Otherwise it survives as an undeclared identifier and the shader won't compile.
    func test_bareChannelIdentifier_rewrittenToBinding() {
        let r = SamplerRewriter.rewrite("ups(ivec2(I), O, iChannel0, res);", bindings: binding())
        XCTAssertEqual(r.code, "ups(ivec2(I), O, bufA, res);")
    }

    /// A bare channel identifier alongside a sampling call: the call rewrites, and the leftover
    /// bare use also rewrites — and `iChannel1img` (the texture binding name) is NOT re-matched.
    func test_bareChannel_withSamplingCall_noDoubleRewrite() {
        let r = SamplerRewriter.rewrite("vec4 c = texture(iChannel1, uv); foo(iChannel1);", bindings: binding())
        XCTAssertEqual(r.code, "vec4 c = IMG_NORM_PIXEL(iChannel1img, uv); foo(iChannel1img);")
    }
}
