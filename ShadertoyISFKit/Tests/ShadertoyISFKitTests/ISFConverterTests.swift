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

    /// Regression for Xtf3Rn: a shader samples iChannel0 but the renderpass declares no input for
    /// it. Without a stub the bare `texture(iChannel0,…)` is left undeclared and the shader won't
    /// compile. The converter must auto-declare a stub image input and rewrite the call.
    func test_convert_unboundChannel_autoStubsImageInput() {
        let shader = ShaderFactory.singlePass(
            imageCode: "void mainImage( out vec4 O, vec2 I ){ O = texture(iChannel0, I/iResolution.xy); }",
            name: "Unbound Channel")
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("\"NAME\" : \"iChannel0img\""), "expected a stub image input")
        XCTAssertTrue(doc.fileText.contains("IMG_NORM_PIXEL(iChannel0img"), "expected the call rewritten")
        XCTAssertFalse(doc.fileText.contains("texture(iChannel0"), "raw undeclared call must be gone")
        XCTAssertTrue(warnings.contains { $0.message.contains("iChannel0 is used but") })
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

    func test_convert_xorGolfShader_warnsUninitializedOutput() {
        let shader = ShaderFactory.singlePass(
            imageCode: "void mainImage( out vec4 O, vec2 I ){ for(O*=I.x; I.x<9.;) O += vec4(1.0); O = O; }",
            name: "Golf")
        let (_, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(warnings.contains { $0.message.contains("initial") })
    }

    func test_iMouse_mappedToEngagedState_notZeroed() {
        // A shader that gates on iMouse.z must respond to the mouse point2D slider, so the
        // rewrite must give iMouse.zw a non-zero ("pressed") value, not 0.
        let shader = ShaderFactory.singlePass(
            imageCode: "void mainImage(out vec4 O, vec2 I){ O = vec4(iMouse.z < 0.01 ? 0.0 : 1.0); }",
            name: "MouseGate")
        let (doc, _) = ISFConverter.convert(shader)
        let text = doc.fileText
        XCTAssertTrue(text.contains("vec4(mouse * RENDERSIZE, mouse * RENDERSIZE)"))
        XCTAssertFalse(text.contains("vec4(mouse * RENDERSIZE, 0.0, 0.0)"))
    }

    func test_iMouse_wordBoundary_preservesLongerIdentifiers() {
        // The iMouse rewrite must be word-boundary-aware so it doesn't corrupt longer identifiers
        // that merely start with "iMouse" (e.g. a user-named `iMouseScale`).
        let shader = ShaderFactory.singlePass(
            imageCode: "void mainImage(out vec4 O, vec2 I){ float iMouseScale = 2.0; O = vec4(iMouse.x * iMouseScale); }",
            name: "MouseWB")
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("iMouseScale"))
        XCTAssertTrue(doc.fileText.contains("vec4(mouse * RENDERSIZE, mouse * RENDERSIZE).x"))
    }

    /// C6 — iMouse referenced ONLY in the Common tab must still declare the mouse input in the
    /// header and be rewritten at Common file scope (it previously reached the transpiler as an
    /// undeclared `iMouse` → black import).
    func test_iMouse_inCommonOnly_declaresMouseInputAndRewrites() {
        let common = RenderPass(inputs: [], outputs: [], code: "#define M iMouse",
                                name: "Common", type: .common)
        let image = RenderPass(inputs: [], outputs: [PassOutput(id: "out0", channel: 0)],
                               code: "void mainImage(out vec4 O, vec2 I){ O = vec4(M.xy, 0.0, 1.0); }",
                               name: "Image", type: .image)
        let shader = Shader(info: Info(id: "", name: "CommonMouse", username: nil, description: nil),
                            renderpass: [image, common])
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.fileText.contains("\"NAME\" : \"mouse\""),
                      "Common-only iMouse must declare the mouse input; got header:\n\(doc.headerJSON)")
        XCTAssertNil(doc.fileText.range(of: #"\biMouse\b"#, options: .regularExpression),
                     "no raw iMouse may survive conversion")
    }

    /// M24 — a shader with no convertible render passes (e.g. sound-only) must surface an
    /// error-severity warning instead of "successfully" emitting an empty, black main().
    func test_soundOnlyShader_errorsInsteadOfSilentBlack() {
        let sound = RenderPass(inputs: [], outputs: [],
                               code: "vec2 mainSound(float t){ return vec2(0.0); }",
                               name: "Sound", type: .sound)
        let shader = Shader(info: Info(id: "", name: "SoundOnly", username: nil, description: nil),
                            renderpass: [sound])
        let (_, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(warnings.contains {
            $0.severity == .error && $0.message.lowercased().contains("no convertible")
        }, "\(warnings)")
    }

    /// N17 — stub-input warnings must come out in deterministic ascending-channel order
    /// (Set iteration made corpus report diffs noisy run-to-run).
    func test_stubWarnings_deterministicAscendingOrder() {
        let shader = ShaderFactory.singlePass(
            imageCode: "void mainImage(out vec4 O, vec2 I){ O = texture(iChannel3, I) + texture(iChannel1, I) + texture(iChannel2, I); }",
            name: "Stubs")
        let (_, warnings) = ISFConverter.convert(shader)
        let stubs = warnings.filter { $0.message.contains("added a stub image input") }.map(\.message)
        XCTAssertEqual(stubs.count, 3)
        XCTAssertTrue(stubs[0].contains("iChannel1"), "\(stubs)")
        XCTAssertTrue(stubs[1].contains("iChannel2"), "\(stubs)")
        XCTAssertTrue(stubs[2].contains("iChannel3"), "\(stubs)")
    }

    /// C5 interim — a Shadertoy uniform inside a Common helper BODY is not auto-rewritten (the
    /// scope-aware rewrite protects bodies); until the real scope-aware fix lands, conversion must
    /// warn loudly instead of silently shipping an undeclared identifier.
    func test_commonBodyUniform_warnsLoudly() {
        let common = RenderPass(inputs: [], outputs: [],
                                code: "float n(vec2 p){ return sin(p.x + iTime); }",
                                name: "Common", type: .common)
        let image = RenderPass(inputs: [], outputs: [PassOutput(id: "out0", channel: 0)],
                               code: "void mainImage(out vec4 O, vec2 I){ O = vec4(n(I.xy)); }",
                               name: "Image", type: .image)
        let shader = Shader(info: Info(id: "", name: "C5", username: nil, description: nil),
                            renderpass: [image, common])
        let (_, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(warnings.contains {
            $0.severity == .warning && $0.message.contains("iTime")
                && $0.message.lowercased().contains("common")
        }, "\(warnings)")
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
