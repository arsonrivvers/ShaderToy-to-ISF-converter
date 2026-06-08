import XCTest
@testable import ShadertoyISFKit

final class ISFConverterTests: XCTestCase {
    private func fixtureShader(_ name: String) throws -> Shader {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        return try JSONDecoder().decode(ShadertoyResponse.self, from: data).shader
    }

    func test_singlePass_producesValidISF() throws {
        let (doc, warnings) = ISFConverter.convert(try fixtureShader("single_pass"))
        let text = doc.fileText
        // header parses as JSON
        let headerStart = text.range(of: "/*{")!.upperBound
        let headerEnd = text.range(of: "}*/")!.lowerBound
        let headerJSON = "{" + text[headerStart..<headerEnd] + "}"
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(headerJSON.utf8)))
        // uniform + main() present
        XCTAssertTrue(text.contains("RENDERSIZE"))
        XCTAssertTrue(text.contains("TIME"))
        XCTAssertTrue(text.contains("void main()"))
        XCTAssertFalse(text.contains("iResolution"))
        XCTAssertFalse(text.contains("iTime "))
        XCTAssertTrue(warnings.isEmpty)
    }

    func test_convert_tanhShader_includesGuardedPolyfill() {
        let shader = ShaderFactory.singlePass(
            imageCode: "void mainImage( out vec4 O, vec2 I ){ O = tanh(vec4(1.0)); }",
            name: "Tanh Test")
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("#if __VERSION__ < 130"))
        XCTAssertTrue(doc.fileText.contains("float tanh(float x)"))
        XCTAssertTrue(warnings.contains { $0.message.contains("tanh") })
    }

    func test_multipass_producesPersistentBuffersAndReads() throws {
        let (doc, _) = ISFConverter.convert(try fixtureShader("multipass_feedback"))
        let text = doc.fileText
        XCTAssertTrue(text.contains("\"TARGET\""))
        XCTAssertTrue(text.contains("bufA"))
        XCTAssertTrue(text.contains("IMG_NORM_PIXEL(bufA"))
        XCTAssertTrue(text.contains("if (PASSINDEX == 0)"))
        XCTAssertFalse(text.contains("texture(iChannel0"))
    }
}
