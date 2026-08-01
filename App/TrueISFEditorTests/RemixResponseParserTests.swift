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

    func test_extractCandidate_acceptsWhitespaceAndCommentSeparatedAllmanMain() {
        let source = shader("""
        void /* separator */
        main
        (void)
        {
            if (true) {
                gl_FragColor = vec4(1.0);
            }
        }
        """)

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_acceptsNestedMatchedMainBody() {
        let source = shader("""
        void main() {
            if (true) {
                if (true) {
                    gl_FragColor = vec4(1.0);
                }
            }
        }
        """)

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_rejectsMainImageImpostor() {
        XCTAssertEqual(
            RemixResponseParser.extractCandidate(shader("void mainImage() {}")),
            .failure(.incompleteSource)
        )
    }

    func test_extractCandidate_rejectsTruncatedMainBody() {
        XCTAssertEqual(
            RemixResponseParser.extractCandidate(shader("void main() { gl_FragColor = vec4(1.0);")),
            .failure(.incompleteSource)
        )
    }

    func test_extractCandidate_ignoresBracesInCommentsQuotedTextAndPreprocessorLines() {
        let incompleteBodies = [
            "void main() { // }",
            "void main() { /* } */",
            "void main() { \"}\"",
            "void main() {\n#define END }"
        ]

        for body in incompleteBodies {
            XCTAssertEqual(
                RemixResponseParser.extractCandidate(shader(body)),
                .failure(.incompleteSource),
                "Expected incomplete source for: \(body)"
            )
        }
    }

    func test_extractCandidate_ignoresBracesInContinuedPreprocessorDirectives() {
        let source = shader("""
        void main() {
        #define CLOSE \\
        }
        """)

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .failure(.incompleteSource))
    }

    func test_extractCandidate_treatsWhitespaceAfterABackslashAsTheEndOfAPreprocessorDirective() {
        let source = shader("void main() {\n#define CLOSE \\   \n}")

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_skipsMalformedRawHeaderBeforeLaterValidRawISF() {
        let valid = shader("void main() { gl_FragColor = vec4(1.0); }")
        let response = "/*{not json}*/\nvoid main() {}\n\(valid)"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .success(valid))
    }

    func test_extractCandidate_boundsAnIncompleteRawHeaderBeforeLaterValidRawISF() {
        let incomplete = "/*{ \"ISFVSN\": \"2.0\" }*/\nnot a shader"
        let valid = shader("void main() { gl_FragColor = vec4(1.0); }")

        XCTAssertEqual(RemixResponseParser.extractCandidate("\(incomplete)\n\(valid)"), .success(valid))
    }

    func test_extractCandidate_keepsObjectShapedBlockCommentsInsideAValidShaderBody() {
        let source = shader("""
        void main() {
            /* { debug note } */
            gl_FragColor = vec4(1.0);
        }
        """)

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_keepsValidJSONBlockCommentsInsideAValidShaderBody() {
        let source = shader("""
        void main() {
            /* {"debug": true} */
            gl_FragColor = vec4(1.0);
        }
        """)

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_keepsVersionedHeaderCommentsInsideAMainBody() {
        let source = shader("""
        void main() {
            /*{ "ISFVSN": "2.0" }*/
            gl_FragColor = vec4(1.0);
        }
        """)

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_acceptsAHeaderDescriptionContainingABlockCommentMarker() {
        let source = """
        /*{ "ISFVSN": "2.0", "DESCRIPTION": "look /* inward" }*/
        void main() { gl_FragColor = vec4(1.0); }
        """

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_rejectsClosedMainFollowedByAnUnterminatedBlockComment() {
        let source = shader("void main() { gl_FragColor = vec4(1.0); }\n/* trailing shader comment")

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .failure(.incompleteSource))
    }

    func test_extractCandidate_skipsAnUnterminatedMalformedRawOpenerBeforeLaterValidRawISF() {
        let valid = shader("void main() { gl_FragColor = vec4(1.0); }")
        let response = "/*{ malformed header\n\(valid)"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .success(valid))
    }

    func test_extractCandidate_stopsAtTheNextVersionedRawISFResponse() {
        let first = shader("void main() { gl_FragColor = vec4(1.0); }")
        let second = shader("void main() { gl_FragColor = vec4(0.0); }")

        XCTAssertEqual(RemixResponseParser.extractCandidate("\(first)\n\(second)"), .success(first))
    }

    func test_extractCandidate_keepsVersionlessParsedHeadersAsCompatibilityCandidates() {
        let source = """
        /*{ "DESCRIPTION": "legacy output" }*/
        void main() { gl_FragColor = vec4(1.0); }
        """

        XCTAssertEqual(RemixResponseParser.extractCandidate(source), .success(source))
    }

    func test_extractCandidate_keepsEmbeddedBackticksInShaderComments() {
        let source = shader("""
        void main() {
            // ``` is shader text, not a closing fence
            gl_FragColor = vec4(1.0);
        }
        """)
        let response = "```glsl\n\(source)\n```"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .success(source))
    }

    func test_extractCandidate_recognizesIndentedTaggedAndBareFences() {
        let tagged = shader("void main() { gl_FragColor = vec4(1.0); }")
        let bare = shader("void main() { gl_FragColor = vec4(0.0); }")
        let response = "  ```glsl\n\(tagged)\n  ```\n\t```\n\(bare)\n\t```"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .success(tagged))
    }

    func test_extractCandidate_requiresStandaloneClosingFenceLine() {
        let response = "```glsl\n\(isf)\n``` trailing text"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .failure(.incompleteFence))
    }

    func test_extractCandidate_handlesAdjacentFencedBlocksAndCRLF() {
        let source = shader("void main() { gl_FragColor = vec4(1.0); }")
        let adjacent = "```text\nnot a shader\n```\n```glsl\n\(source)\n```"
        let crlf = "  ```glsl\r\n\(source)\r\n  ```\r\n"

        XCTAssertEqual(RemixResponseParser.extractCandidate(adjacent), .success(source))
        XCTAssertEqual(RemixResponseParser.extractCandidate(crlf), .success(source))
    }

    func test_extractCandidate_excludesAnUnterminatedOpeningFenceWithoutNewline() {
        let response = "```glsl /*{ \"ISFVSN\": \"2.0\" }*/"

        XCTAssertEqual(RemixResponseParser.extractCandidate(response), .failure(.incompleteFence))
    }

    private func shader(_ body: String) -> String {
        "/*{ \"ISFVSN\": \"2.0\" }*/\n\(body)"
    }
}
