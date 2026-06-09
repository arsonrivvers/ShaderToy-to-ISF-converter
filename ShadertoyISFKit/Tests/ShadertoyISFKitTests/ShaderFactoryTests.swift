import XCTest
@testable import ShadertoyISFKit

final class ShaderFactoryTests: XCTestCase {
    func test_singlePass_buildsConvertibleShader() {
        let code = "void mainImage( out vec4 c, in vec2 f ){ c = vec4(f/iResolution.xy, 0.0, 1.0); }"
        let shader = ShaderFactory.singlePass(imageCode: code, name: "Test")
        XCTAssertEqual(shader.renderpass.count, 1)
        XCTAssertEqual(shader.renderpass[0].type, .image)
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("RENDERSIZE"))
        XCTAssertTrue(doc.fileText.contains("void main()"))
        XCTAssertFalse(doc.fileText.contains("iResolution"))
    }

    // MARK: fromPaste — marker parsing & multipass

    func test_fromPaste_noMarkers_isSingleImagePass() {
        let code = "void mainImage( out vec4 c, in vec2 f ){ c = vec4(1.0); }"
        let shader = ShaderFactory.fromPaste(code, name: "Plain")
        XCTAssertEqual(shader.renderpass.count, 1)
        XCTAssertEqual(shader.renderpass[0].type, .image)
        XCTAssertEqual(shader.renderpass[0].code, code)
    }

    func test_fromPaste_commonBufferImage_buildsThreePasses() {
        let text = """
        // [Common]
        float helper(){ return 1.0; }
        // [Buffer A]
        void mainImage( out vec4 O, vec2 I ){ O = vec4(helper()); }
        // [Image]
        void mainImage( out vec4 O, vec2 I ){ O = texture(iChannel0, I/iResolution.xy); }
        """
        let shader = ShaderFactory.fromPaste(text, name: "MP")
        let types = shader.renderpass.map(\.type)
        XCTAssertTrue(types.contains(.common))
        XCTAssertTrue(types.contains(.buffer))
        XCTAssertTrue(types.contains(.image))
        let common = shader.renderpass.first { $0.type == .common }
        XCTAssertTrue(common?.code.contains("float helper()") ?? false)
    }

    func test_fromPaste_imageReadingChannel0_bindsToBufferA() {
        let text = """
        // [Buffer A]
        void mainImage( out vec4 O, vec2 I ){ O = vec4(1.0); }
        // [Image]
        void mainImage( out vec4 O, vec2 I ){ O = texture(iChannel0, I/iResolution.xy); }
        """
        let shader = ShaderFactory.fromPaste(text, name: "MP")
        let image = shader.renderpass.first { $0.type == .image }
        let bufferA = shader.renderpass.first { $0.type == .buffer }
        let input = image?.inputs.first { $0.channel == 0 }
        XCTAssertEqual(input?.ctype, .buffer)
        // The image's iChannel0 input id must match Buffer A's output id so ChannelBinding resolves it.
        XCTAssertEqual(input?.id, bufferA?.outputs.first?.id)
    }

    func test_fromPaste_channelWithoutMatchingBuffer_isTexture() {
        let text = """
        // [Buffer A]
        void mainImage( out vec4 O, vec2 I ){ O = vec4(1.0); }
        // [Image]
        void mainImage( out vec4 O, vec2 I ){ O = texture(iChannel1, I/iResolution.xy); }
        """
        let shader = ShaderFactory.fromPaste(text, name: "MP")
        let image = shader.renderpass.first { $0.type == .image }
        let input = image?.inputs.first { $0.channel == 1 }
        XCTAssertEqual(input?.ctype, .texture)   // no Buffer B exists
    }

    func test_fromPaste_multipass_convertsToPersistentBuffer() {
        let text = """
        // [Buffer A]
        void mainImage( out vec4 O, vec2 I ){ O = texture(iChannel0, I/iResolution.xy) + 0.01; }
        // [Image]
        void mainImage( out vec4 O, vec2 I ){ O = texture(iChannel0, I/iResolution.xy); }
        """
        let shader = ShaderFactory.fromPaste(text, name: "Feedback")
        let (doc, _) = ISFConverter.convert(shader)
        let out = doc.fileText
        XCTAssertTrue(out.contains("\"TARGET\""))
        XCTAssertTrue(out.contains("bufA"))
        XCTAssertTrue(out.contains("if (PASSINDEX == 0)"))
        XCTAssertFalse(out.contains("texture(iChannel0"))
    }

    func test_fromPaste_detectsBuffers_helper() {
        XCTAssertFalse(ShaderFactory.pasteContainsBuffers("void mainImage(){}"))
        XCTAssertTrue(ShaderFactory.pasteContainsBuffers("// [Buffer A]\nvoid mainImage(){}"))
    }
}
