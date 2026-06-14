import XCTest
@testable import ShadertoyISFKit

final class ShadertoyInternalParserTests: XCTestCase {
    private func fixture(_ n: String) throws -> Data {
        let url = Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Fixtures")
        return try Data(contentsOf: try XCTUnwrap(url))
    }

    func test_parsesArrayResponse_toFirstShader() throws {
        let shader = try ShadertoyInternalParser.parse(try fixture("internal_seascape"))
        XCTAssertEqual(shader.info.name, "Seascape")
        XCTAssertEqual(shader.renderpass.count, 1)
        XCTAssertEqual(shader.renderpass[0].type, .image)
    }

    func test_emptyArray_throwsNotFound() {
        let data = Data("[]".utf8)
        XCTAssertThrowsError(try ShadertoyInternalParser.parse(data)) { error in
            XCTAssertEqual(error as? ShadertoyInternalParserError, .shaderNotFound)
        }
    }

    func test_errorObject_throwsNotFound() {
        // Internal endpoint sometimes returns an error object instead of an array.
        let data = Data(#"{"Error":"Shader not found"}"#.utf8)
        XCTAssertThrowsError(try ShadertoyInternalParser.parse(data)) { error in
            XCTAssertEqual(error as? ShadertoyInternalParserError, .shaderNotFound)
        }
    }

    /// Regression for N323DD: the internal `/shadertoy` endpoint names the channel-type field
    /// `type` (with `filepath`/`previewfilepath`), NOT `ctype` like the REST API. A public
    /// multipass/texture shader must still parse, not collapse to shaderNotFound.
    func test_parsesInternalEndpointInputs_typeKeyNotCtype() throws {
        let json = """
        [{"ver":"0.1","info":{"id":"N323DD","name":"Everyday 289","username":"moonlightoctopus"},
          "renderpass":[
            {"name":"Image","type":"image","code":"void mainImage(out vec4 c, vec2 p){c=vec4(0);}",
             "inputs":[{"id":"4dXGR8","filepath":"/media/a.png","previewfilepath":"/media/p.png",
                        "type":"buffer","channel":0,"sampler":{"filter":"linear","wrap":"clamp","vflip":"true","srgb":"false","internal":"byte"},"published":1}],
             "outputs":[{"id":"4dfGRr","channel":0}]},
            {"name":"Buffer A","type":"buffer","code":"void mainImage(out vec4 c, vec2 p){c=vec4(1);}",
             "inputs":[],"outputs":[{"id":"4dXGR8","channel":0}]}
          ]}]
        """
        let shader = try ShadertoyInternalParser.parse(Data(json.utf8))
        XCTAssertEqual(shader.info.name, "Everyday 289")
        XCTAssertEqual(shader.renderpass.count, 2)
        XCTAssertEqual(shader.renderpass[0].inputs.first?.ctype, .buffer)
        XCTAssertEqual(shader.renderpass[0].inputs.first?.channel, 0)
    }

    /// A non-empty array whose shader fails to decode (unknown shape) must surface as `.malformed`,
    /// NOT `.shaderNotFound` — masking a decode failure as "not found/not public" is the bug that
    /// cost an hour diagnosing N323DD.
    func test_undecodableShader_throwsMalformedNotNotFound() {
        // Valid array, but the renderpass input is missing BOTH `ctype` and `type` → undecodable.
        let json = """
        [{"info":{"id":"X","name":"Broken","username":"u"},
          "renderpass":[{"name":"Image","type":"image","code":"x",
            "inputs":[{"id":"1","channel":0}],"outputs":[{"id":"1","channel":0}]}]}]
        """
        XCTAssertThrowsError(try ShadertoyInternalParser.parse(Data(json.utf8))) { error in
            guard case .malformed = (error as? ShadertoyInternalParserError) else {
                return XCTFail("expected .malformed, got \(error)")
            }
        }
    }

    /// REST-API shape (key `ctype`) must keep working alongside the internal-endpoint shape.
    func test_parsesRestApiInputs_ctypeKey() throws {
        let json = """
        [{"info":{"id":"X","name":"Rest","username":"u"},
          "renderpass":[
            {"name":"Image","type":"image","code":"x","inputs":[{"id":"1","ctype":"texture","channel":0}],"outputs":[{"id":"1","channel":0}]}
          ]}]
        """
        let shader = try ShadertoyInternalParser.parse(Data(json.utf8))
        XCTAssertEqual(shader.renderpass[0].inputs.first?.ctype, .texture)
    }
}
