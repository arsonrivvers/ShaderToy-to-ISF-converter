import XCTest
@testable import TrueISFEditor

final class RemixResponseParserTests: XCTestCase {
    private let isf = """
    /*{ "ISFVSN": "2.0" }*/
    void main(){ gl_FragColor=vec4(1.0); }
    """

    func test_extracts_fencedGLSLBlock() {
        let out = "Here you go:\n```glsl\n/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }\n```\nDone."
        let isf = RemixResponseParser.extractISF(out)
        XCTAssertEqual(isf, "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }")
    }
    func test_extracts_rawHeaderToEnd_whenNoFence() {
        let out = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(0.0); }"
        XCTAssertEqual(RemixResponseParser.extractISF(out), out)
    }
    func test_returnsNil_whenNoISF() {
        XCTAssertNil(RemixResponseParser.extractISF("I couldn't do that."))
    }

    func test_extractCandidate_skipsNonShaderFenceBeforeFirstCompleteValidISF() {
        let response = "prose\n```text\nno shader\n```\n```glsl\n\(isf)\n```"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .success(isf))
    }

    func test_extractCandidate_reportsIncompleteFenceForUnclosedShaderFence() {
        XCTAssertEqual(
            RemixResponseParser.extractCandidate("```glsl\n/*{\"ISFVSN\":\"2.0\"}*/"),
            .failure(.incompleteFence)
        )
    }

    func test_extractCandidate_reportsInvalidHeaderForMalformedRawHeader() {
        XCTAssertEqual(
            RemixResponseParser.extractCandidate("/*{not json}*/\nvoid main(){}"),
            .failure(.invalidHeader("malformed ISF header"))
        )
    }

    func test_extractCandidate_reportsIncompleteSourceForHeaderWithoutShaderBody() {
        XCTAssertEqual(
            RemixResponseParser.extractCandidate("/*{\"ISFVSN\":\"2.0\"}*/"),
            .failure(.incompleteSource)
        )
    }

    func test_extractCandidate_reportsNoISFFoundWhenResponseHasNoHeader() {
        XCTAssertEqual(
            RemixResponseParser.extractCandidate("no shader here"),
            .failure(.noISFFound)
        )
    }

    func test_extractCandidate_recoversValidRawSourceAfterMalformedCompleteFence() {
        let response = """
        ```glsl
        /*{not json}*/
        void main(){}
        ```
        \(isf)
        """

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .success(isf))
    }

    func test_extractCandidate_doesNotRawFallbackInsideUnclosedShaderFence() {
        let response = "```glsl\n\(isf)"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .failure(.incompleteFence))
    }

    func test_extractCandidate_usesDeterministicDiagnosticPrecedenceWhenNoCandidateExists() {
        let response = """
        ```glsl
        /*{not json}*/
        void main(){}
        ```
        /*{ "ISFVSN": "2.0" }*/
        ```glsl
        /*{ "ISFVSN": "2.0" }*/
        """

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .failure(.incompleteFence))
    }
}
