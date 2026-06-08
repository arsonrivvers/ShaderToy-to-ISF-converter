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
}
