import XCTest
@testable import ShadertoyISFKit

final class CommonChannelRewriterTests: XCTestCase {
    private func buf(_ n: String) -> ChannelBinding.Binding { .init(glslName: n, kind: .buffer) }

    /// XftGRj class: a Common-tab `texelFetch(iChannel0,…)` whose channel maps to a DIFFERENT buffer
    /// per pass. SamplerRewriter never touches Common, and a GLSL macro can't hold a per-pass value —
    /// so route it through a generated PASSINDEX dispatcher.
    func test_texelFetchInCommon_routedToPassindexDispatcher() {
        let common = "vec4 readA(ivec2 U){ return texelFetch(iChannel0, U, 0); }"
        let r = CommonChannelRewriter.rewrite(
            commonCode: common,
            perChannelPerPass: [0: [0: buf("bufB"), 1: buf("bufA")]],
            passCount: 2)
        // call site rewritten to the dispatcher (sampler + LOD args dropped)
        XCTAssertTrue(r.rewrittenCommon.contains("_ch0_texel(U)"), r.rewrittenCommon)
        XCTAssertFalse(r.rewrittenCommon.contains("texelFetch(iChannel0"))
        // dispatcher branches per pass, with the per-pass buffer
        XCTAssertTrue(r.dispatchers.contains("vec4 _ch0_texel(ivec2 U)"), r.dispatchers)
        XCTAssertTrue(r.dispatchers.contains("if (PASSINDEX == 0) { return IMG_PIXEL(bufB, vec2(U)); }"))
        XCTAssertTrue(r.dispatchers.contains("if (PASSINDEX == 1) { return IMG_PIXEL(bufA, vec2(U)); }"))
        XCTAssertTrue(r.dispatchers.contains("return vec4(0.0);"))
    }

    /// `texture(iChannelN, uv)` in Common → normalized-sample dispatcher.
    func test_textureInCommon_routedToTexDispatcher() {
        let common = "#define A(p) texture(iChannel1, p)\nvec4 f(vec2 q){ return A(q); }"
        let r = CommonChannelRewriter.rewrite(
            commonCode: common,
            perChannelPerPass: [1: [0: buf("bufA"), 1: buf("bufC")]],
            passCount: 2)
        XCTAssertTrue(r.rewrittenCommon.contains("_ch1_tex(p)"), r.rewrittenCommon)
        XCTAssertTrue(r.dispatchers.contains("vec4 _ch1_tex(vec2 uv)"))
        XCTAssertTrue(r.dispatchers.contains("if (PASSINDEX == 0) { return IMG_NORM_PIXEL(bufA, uv); }"))
        XCTAssertTrue(r.dispatchers.contains("if (PASSINDEX == 1) { return IMG_NORM_PIXEL(bufC, uv); }"))
    }

    /// M16 — the Common channel-arg parser must tolerate a trailing comment (`iChannel0 /* src */`)
    /// exactly like the per-pass SamplerRewriter does; requiring the whole token to Int-parse left
    /// the call unrewritten → undeclared iChannel0.
    func test_channelArgWithTrailingComment_isRouted() {
        let common = "vec4 f(vec2 q){ return texture(iChannel0 /* src */, q); }"
        let r = CommonChannelRewriter.rewrite(
            commonCode: common,
            perChannelPerPass: [0: [0: buf("bufA")]],
            passCount: 1)
        XCTAssertTrue(r.rewrittenCommon.contains("_ch0_tex(q)"), r.rewrittenCommon)
        XCTAssertFalse(r.rewrittenCommon.contains("texture(iChannel0"))
    }

    /// M15 — an audio binding's tex dispatcher must do the FFT/waveform y-split like
    /// SamplerRewriter.normSample; sampling the FFT texture flat means waveform reads silently
    /// return spectrum data.
    func test_audioBinding_texDispatcher_splitsFftWave() {
        let audio = ChannelBinding.Binding(glslName: "iChannel0fft", kind: .audio,
                                           auxName: "iChannel0wave")
        let r = CommonChannelRewriter.rewrite(
            commonCode: "vec4 g(vec2 q){ return texture(iChannel0, q); }",
            perChannelPerPass: [0: [0: audio]],
            passCount: 1)
        XCTAssertTrue(r.dispatchers.contains("IMG_NORM_PIXEL(iChannel0fft, vec2((uv).x, 0.5))"), r.dispatchers)
        XCTAssertTrue(r.dispatchers.contains("IMG_NORM_PIXEL(iChannel0wave, vec2((uv).x, 0.5))"), r.dispatchers)
        XCTAssertTrue(r.dispatchers.contains("step(0.5, (uv).y)"), r.dispatchers)
    }

    /// M15 — a cubemap binding's tex dispatcher takes a vec3 direction (that's what the Common call
    /// site passes) and projects via _dirToEquirect; the vec2 signature was a guaranteed
    /// type-mismatch compile error.
    func test_cubemapBinding_texDispatcher_takesVec3AndProjects() {
        let cube = ChannelBinding.Binding(glslName: "iChannel0img", kind: .cubemap)
        let r = CommonChannelRewriter.rewrite(
            commonCode: "vec4 g(vec3 d){ return texture(iChannel0, d); }",
            perChannelPerPass: [0: [0: cube]],
            passCount: 1)
        XCTAssertTrue(r.dispatchers.contains("vec4 _ch0_tex(vec3 dir)"), r.dispatchers)
        XCTAssertTrue(r.dispatchers.contains("IMG_NORM_PIXEL(iChannel0img, _dirToEquirect(dir))"), r.dispatchers)
    }

    /// textureLod in Common drops the LOD and routes to the same tex dispatcher.
    func test_textureLodInCommon_routedToTexDispatcher() {
        let common = "vec4 g(vec2 uv){ return textureLod(iChannel0, uv, 0.0); }"
        let r = CommonChannelRewriter.rewrite(
            commonCode: common, perChannelPerPass: [0: [0: buf("bufA")]], passCount: 1)
        XCTAssertTrue(r.rewrittenCommon.contains("_ch0_tex(uv)"))
        XCTAssertFalse(r.rewrittenCommon.contains("textureLod"))
    }

    /// A non-iChannel sampler call in Common is left completely alone.
    func test_nonChannelCall_untouched() {
        let common = "vec4 h(vec2 uv){ return texture(myOwnSampler, uv); }"
        let r = CommonChannelRewriter.rewrite(commonCode: common, perChannelPerPass: [:], passCount: 2)
        XCTAssertEqual(r.rewrittenCommon, common)
        XCTAssertTrue(r.dispatchers.isEmpty)
    }

    /// A channel sampled in Common but bound by NO pass → dispatcher still compiles (returns 0) and a
    /// warning is emitted (ISFConverter stubs it upstream; this is the last-resort fallback).
    func test_channelWithNoBinding_emitsZeroDispatcherAndWarns() {
        let common = "vec4 k(vec2 uv){ return texture(iChannel3, uv); }"
        let r = CommonChannelRewriter.rewrite(commonCode: common, perChannelPerPass: [:], passCount: 2)
        XCTAssertTrue(r.dispatchers.contains("vec4 _ch3_tex(vec2 uv)"))
        XCTAssertTrue(r.dispatchers.contains("return vec4(0.0);"))
        XCTAssertFalse(r.warnings.isEmpty)
    }
}
