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
}
