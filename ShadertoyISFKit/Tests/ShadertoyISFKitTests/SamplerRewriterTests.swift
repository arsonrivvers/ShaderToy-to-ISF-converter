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

    /// Audio channel: Shadertoy packs FFT (row y<0.5) + waveform (row y≥0.5) into one texture; ISF
    /// splits them. Route the read to the FFT or waveform sampler by the read's y coordinate at
    /// runtime via step (not a vector ternary — Metal-unsafe).
    func test_audioChannel_routesFftWaveByYCoordinate() {
        let bindings: [Int: ChannelBinding.Binding] = [
            0: .init(glslName: "iChannel0fft", kind: .audio, auxName: "iChannel0wave")]
        let r = SamplerRewriter.rewrite("texture(iChannel0, vec2(f, 0.25))", bindings: bindings)
        XCTAssertTrue(r.code.contains("IMG_NORM_PIXEL(iChannel0fft, vec2((vec2(f, 0.25)).x, 0.5))"), r.code)
        XCTAssertTrue(r.code.contains("IMG_NORM_PIXEL(iChannel0wave, vec2((vec2(f, 0.25)).x, 0.5))"), r.code)
        XCTAssertTrue(r.code.contains("step(0.5, (vec2(f, 0.25)).y)"), r.code)
        XCTAssertTrue(r.code.contains("mix("), r.code)
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
    func test_texture_withBias_dropsBias_andWarns() {
        // 3-arg texture(sampler, coord, bias) is valid GLSL ES 3.00; ISF has no per-sample bias,
        // so drop the bias (like textureLod's LOD) instead of leaving an uncompilable texture() call.
        let r = SamplerRewriter.rewrite("texture(iChannel0, uv, -0.5)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(bufA, uv)")
        XCTAssertTrue(r.warnings.contains { $0.message.lowercased().contains("bias") })
    }
    func test_texture2D_withBias_dropsBias() {
        let r = SamplerRewriter.rewrite("texture2D(iChannel1, uv, 1.0)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(iChannel1img, uv)")
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

    /// Regression for sXBGWy: a cubemap channel is sampled with a vec3 direction. ISF has no cubemap,
    /// so the 2D stub must wrap the direction in an equirectangular projection — otherwise
    /// IMG_NORM_PIXEL (which takes vec2) has "no matching overload" and the shader black-screens.
    private func cubemapBinding() -> [Int: ChannelBinding.Binding] {
        [0: .init(glslName: "iChannel0img", kind: .cubemap)]
    }
    func test_cubemapChannel_texture_wrapsWithEquirect() {
        let r = SamplerRewriter.rewrite("texture(iChannel0, reflect(rd, n))", bindings: cubemapBinding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(iChannel0img, _dirToEquirect(reflect(rd, n)))")
    }
    func test_cubemapChannel_textureLod_wrapsWithEquirect() {
        let r = SamplerRewriter.rewrite("textureLod(iChannel0, rd, 0.0)", bindings: cubemapBinding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(iChannel0img, _dirToEquirect(rd))")
    }
    func test_2dChannel_notWrapped() {
        let r = SamplerRewriter.rewrite("texture(iChannel0, uv)", bindings: binding())
        XCTAssertEqual(r.code, "IMG_NORM_PIXEL(bufA, uv)")  // buffer/2D stays a plain coord
    }

    /// M22 — sampler builtins with no ISF mapping (textureSize, texelFetchOffset, textureGrad,
    /// textureProj) must WARN instead of passing through silently — whether the leftover call
    /// compiles depends entirely on the host's sampler declaration.
    func test_unmappedSamplerBuiltins_warn() {
        let r = SamplerRewriter.rewrite("ivec2 s = textureSize(iChannel0, 0);", bindings: binding())
        XCTAssertTrue(r.warnings.contains { $0.message.contains("textureSize") }, "\(r.warnings)")
    }
    func test_mappedBuiltins_doNotTriggerUnmappedWarning() {
        let r = SamplerRewriter.rewrite("texture(iChannel0, uv)", bindings: binding())
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
    }
}
