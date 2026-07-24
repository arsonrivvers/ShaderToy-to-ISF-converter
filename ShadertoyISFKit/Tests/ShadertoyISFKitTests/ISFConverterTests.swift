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

    /// M19 interim — channel/mouse mentions inside COMMENTS must not invent header inputs
    /// (`// TODO try iChannel2` produced a phantom stub image input + warning).
    func test_commentedChannelAndMouse_produceNoPhantomInputs() {
        let shader = ShaderFactory.singlePass(
            imageCode: "// TODO try iChannel2 here\n/* maybe iMouse later */\nvoid mainImage(out vec4 O, vec2 I){ O = vec4(1.0); }",
            name: "Comments")
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertFalse(doc.fileText.contains("iChannel2img"), "phantom stub input from a comment")
        XCTAssertFalse(doc.fileText.contains("\"NAME\" : \"mouse\""), "phantom mouse input from a comment")
        XCTAssertFalse(warnings.contains { $0.message.contains("iChannel2") }, "\(warnings)")
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

    /// C5 — a Shadertoy uniform inside an unshadowed Common helper BODY is now REWRITTEN by the
    /// scope-aware pass (was: protected wholesale, shipped raw, loud interim warning). No warning
    /// fires because nothing survives.
    func test_commonBodyUniform_isRewritten_C5() {
        let common = RenderPass(inputs: [], outputs: [],
                                code: "float n(vec2 p){ return sin(p.x + iTime); }",
                                name: "Common", type: .common)
        let image = RenderPass(inputs: [], outputs: [PassOutput(id: "out0", channel: 0)],
                               code: "void mainImage(out vec4 O, vec2 I){ O = vec4(n(I.xy)); }",
                               name: "Image", type: .image)
        let shader = Shader(info: Info(id: "", name: "C5", username: nil, description: nil),
                            renderpass: [image, common])
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("sin(p.x + TIME)"), doc.glslBody)
        XCTAssertFalse(warnings.contains { $0.message.contains("iTime") }, "\(warnings)")
    }

    /// M20 — paste path: a helper with a uniform-named PARAM in a pass body must be protected
    /// (was: whole-string rewrite emitted `vec2 vec3(RENDERSIZE, 1.0)` → syntax error), while
    /// its call sites still get the real rewrite.
    func test_pastePath_helperWithUniformNamedParam_isProtected_M20() {
        let shader = ShaderFactory.singlePass(imageCode: """
            float vig(vec2 uv, vec2 iResolution){ return uv.x / iResolution.x; }
            void mainImage(out vec4 O, in vec2 U){ O = vec4(vig(U, iResolution.xy)); }
            """)
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("float vig(vec2 uv, vec2 iResolution)"), doc.glslBody)
        XCTAssertTrue(doc.glslBody.contains("vig(U, vec3(RENDERSIZE, 1.0).xy)"), doc.glslBody)
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

    /// M1 — multipass: pass 0 plainly assigns `O`, pass 1 accumulates into `O` before assigning.
    /// The merged-file detector saw pass 0's plain `=` first and skipped pass 1 → NaN/black pass.
    /// Per-pass runs must inject the initializer into pass 1.
    func test_multipass_accumulatorSecondPass_isInitialized_M1() {
        let bufA = RenderPass(inputs: [], outputs: [PassOutput(id: "buf0", channel: 0)],
                              code: "void mainImage(out vec4 O, in vec2 U){ O = vec4(1.0); }",
                              name: "Buf A", type: .buffer)
        let img = RenderPass(inputs: [], outputs: [PassOutput(id: "img", channel: 0)],
                             code: "void mainImage(out vec4 O, in vec2 U){ for(int i=0;i<4;i++){ O += vec4(0.1); } }",
                             name: "Image", type: .image)
        let shader = Shader(info: Info(id: "m1", name: "m1", username: nil, description: nil),
                            renderpass: [bufA, img])
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("O = vec4(0.0);"), doc.glslBody)
        XCTAssertTrue(warnings.contains { $0.message.contains("Auto-initialized output 'O'")
                                          && $0.context == "Image" }, "\(warnings)")
    }

    /// ZeroInitLocals end-to-end — the 3XBBWD golf shape: `float t = iTime,i,z,d;` +
    /// `for(o*=i;i++<80.;…)`. Metal doesn't zero-init locals, so without the fix `i` is garbage
    /// and the loop never runs (black). The converted body must carry explicit zeros.
    func test_golfShader_uninitializedLocals_zeroInitialized() {
        let shader = ShaderFactory.singlePass(imageCode: """
            void mainImage( out vec4 o, in vec2 I ){
                float t = iTime,i,z,d;
                for(o*=i;i++<80.;){ z += t; }
                o = vec4(z);
            }
            """)
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("i = 0.0,z = 0.0,d = 0.0;"), doc.glslBody)
        XCTAssertTrue(warnings.contains { $0.message.contains("Zero-initialized") }, "\(warnings)")
    }

    /// InjectedNameGuard end-to-end — the tXfBz2 shape: `vec2 mouse = iMouse.xy` must not shadow
    /// the ISF `mouse` input that the iMouse rewrite's replacement expression references.
    func test_userMouseLocal_doesNotShadowInjectedMouseInput() {
        let shader = ShaderFactory.singlePass(imageCode: """
            void mainImage( out vec4 fragColor, in vec2 fragCoord ){
                vec2 mouse = iMouse.xy;
                fragColor = vec4(mouse / iResolution.xy, 0., 1.);
            }
            """)
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("vec2 usr_mouse = vec4(mouse * RENDERSIZE, mouse * RENDERSIZE).xy"),
                      doc.glslBody)
        XCTAssertTrue(doc.glslBody.contains("vec4(usr_mouse / vec3(RENDERSIZE, 1.0).xy, 0., 1.)"), doc.glslBody)
    }

    func test_metadataCommentTerminator_roundTripsThroughConverter() throws {
        let original = "Title close */ description close */ preserved"
        let image = RenderPass(
            inputs: [],
            outputs: [PassOutput(id: "out0", channel: 0)],
            code: "void mainImage(out vec4 O, vec2 I){ O = vec4(1.0); }",
            name: "Image",
            type: .image)
        let shader = Shader(
            info: Info(id: "safe01", name: "fallback */ title",
                       username: "tester", description: original),
            renderpass: [image])

        let (doc, _) = ISFConverter.convert(shader)
        let text = doc.fileText
        XCTAssertEqual(text.components(separatedBy: "*/").count - 1, 1)

        let headerStart = try XCTUnwrap(text.range(of: "/*")).upperBound
        let headerEnd = try XCTUnwrap(text.range(of: "*/")).lowerBound
        let encoded = String(text[headerStart..<headerEnd])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        XCTAssertEqual(object["DESCRIPTION"] as? String, original)

        let fallbackTitle = "fallback */ title"
        let fallbackShader = Shader(
            info: Info(id: "safe02", name: fallbackTitle,
                       username: "tester", description: nil),
            renderpass: [image])
        let (fallbackDoc, _) = ISFConverter.convert(fallbackShader)
        let fallbackText = fallbackDoc.fileText
        XCTAssertEqual(fallbackText.components(separatedBy: "*/").count - 1, 1)
        let fallbackStart = try XCTUnwrap(fallbackText.range(of: "/*")).upperBound
        let fallbackEnd = try XCTUnwrap(fallbackText.range(of: "*/")).lowerBound
        let fallbackEncoded = String(fallbackText[fallbackStart..<fallbackEnd])
        let fallbackObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(fallbackEncoded.utf8)) as? [String: Any])
        XCTAssertEqual(fallbackObject["DESCRIPTION"] as? String, fallbackTitle)
    }

    func test_perPassUnresolvedUniform_emitsPassScopedWarning() {
        let shader = ShaderFactory.singlePass(
            imageCode: """
                void mainImage(out vec4 O, vec2 I) {
                    vec3 nativeSize = iChannelResolution;
                    O = vec4(nativeSize.xy, 0.0, 1.0);
                }
                """)

        let (_, warnings) = ISFConverter.convert(shader)
        let tripwires = warnings.filter {
            $0.message.contains("iChannelResolution survived uniform rewriting")
        }
        XCTAssertEqual(tripwires.count, 1, "\(warnings)")
        XCTAssertEqual(tripwires[0].severity, .warning)
        XCTAssertEqual(tripwires[0].context, "Image")
    }

    func test_perPassUnresolvedUniform_namesOnlyOffendingPass() {
        let buffer = RenderPass(
            inputs: [],
            outputs: [PassOutput(id: "buf0", channel: 0)],
            code: "void mainImage(out vec4 O, vec2 I){ O = vec4(1.0); }",
            name: "Buffer A",
            type: .buffer)
        let image = RenderPass(
            inputs: [],
            outputs: [PassOutput(id: "out0", channel: 0)],
            code: """
                void mainImage(out vec4 O, vec2 I) {
                    vec3 nativeSize = iChannelResolution;
                    O = vec4(nativeSize.xy, 0.0, 1.0);
                }
                """,
            name: "Image",
            type: .image)
        let shader = Shader(
            info: Info(id: "tripwire", name: "Tripwire", username: nil, description: nil),
            renderpass: [buffer, image])

        let (_, warnings) = ISFConverter.convert(shader)
        let contexts = warnings
            .filter { $0.message.contains("survived uniform rewriting") }
            .compactMap(\.context)
        XCTAssertEqual(contexts, ["Image"], "\(warnings)")
    }

    func test_perPassUnresolvedUniform_parameterShadow_remainsUnwarned() {
        let shader = ShaderFactory.singlePass(imageCode: """
            vec3 nativeSize(vec3 iChannelResolution) { return iChannelResolution; }
            void mainImage(out vec4 O, vec2 I) {
                O = vec4(nativeSize(vec3(1.0)).xy, 0.0, 1.0);
            }
            """)

        let (_, warnings) = ISFConverter.convert(shader)
        XCTAssertFalse(warnings.contains {
            $0.message.contains("iChannelResolution survived uniform rewriting")
        }, "\(warnings)")
    }
}
