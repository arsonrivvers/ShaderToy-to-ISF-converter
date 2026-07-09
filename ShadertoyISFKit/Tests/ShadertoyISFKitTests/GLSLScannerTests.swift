import XCTest
@testable import ShadertoyISFKit

final class GLSLScannerTests: XCTestCase {
    /// (char, state) per UTF-16 unit — ASCII-only fixtures so unichar↔Character is 1:1.
    private func states(_ code: String) -> [(c: Character, st: GLSLScanner.State)] {
        var out: [(Character, GLSLScanner.State)] = []
        GLSLScanner.scan(code) { _, u, st in
            out.append((Character(UnicodeScalar(u)!), st)); return true
        }
        return out
    }

    // MARK: - comments

    func test_lineComment_contentFlagged_newlineEndsIt() {
        let s = states("a// x\nb")
        XCTAssertFalse(s[0].st.inComment)                                    // a
        XCTAssertTrue(s[1].st.inLineComment && s[1].st.isCommentDelimiter)   // '/'
        XCTAssertTrue(s[2].st.inLineComment && s[2].st.isCommentDelimiter)   // '/'
        XCTAssertTrue(s[4].st.inLineComment && !s[4].st.isCommentDelimiter)  // 'x'
        XCTAssertFalse(s[5].st.inComment)                                    // '\n' not content
        XCTAssertFalse(s[6].st.inComment)                                    // b
    }

    func test_blockComment_spansLines_delimitersFlagged() {
        let s = states("/* x\ny */z")
        XCTAssertTrue(s[0].st.inBlockComment && s[0].st.isCommentDelimiter)
        XCTAssertTrue(s[3].st.inBlockComment && !s[3].st.isCommentDelimiter) // x
        XCTAssertTrue(s[5].st.inBlockComment)                                // y (after \n)
        XCTAssertTrue(s[7].st.inBlockComment && s[7].st.isCommentDelimiter)  // '*' of */
        XCTAssertFalse(s[9].st.inComment)                                    // z
    }

    func test_lineCommentMarker_insideBlockComment_isJustContent() {
        let s = states("/* // */x")
        XCTAssertTrue(s[3].st.inBlockComment && !s[3].st.inLineComment)
        XCTAssertFalse(s[8].st.inComment)   // x — the */ closed it despite the //
    }

    func test_unterminatedBlockComment_runsToEnd() {
        let s = states("/* x")
        XCTAssertTrue(s[3].st.inBlockComment)
    }

    // MARK: - depth

    func test_braceAndParenDepth_beforeEffect() {
        let s = states("f(a){b}")
        XCTAssertEqual(s[1].st.parenDepth, 0)   // '(' reported at outer depth
        XCTAssertEqual(s[2].st.parenDepth, 1)   // a
        XCTAssertEqual(s[3].st.parenDepth, 1)   // ')' reported inside
        XCTAssertEqual(s[4].st.braceDepth, 0)   // '{' outer
        XCTAssertEqual(s[5].st.braceDepth, 1)   // b
        XCTAssertEqual(s[6].st.braceDepth, 1)   // '}' inside
    }

    func test_delimitersInComments_dontCount() {
        // the N323DD smiley — a paren in a comment must not shift depth for the rest of the file
        let s = states("// :(\nx")
        XCTAssertEqual(s.last!.st.parenDepth, 0)
    }

    func test_closersNeverGoNegative() {
        let s = states(")}x")
        XCTAssertEqual(s[2].st.braceDepth, 0)
        XCTAssertEqual(s[2].st.parenDepth, 0)
    }

    // MARK: - directives

    func test_directive_bracesDontCount_endsAtNewline() {
        // ssjyWc header-macro class: unbalanced { in a #define must not desync depth
        let code = "#define Main void mainImage(out vec4 Q){\nfloat g;"
        let s = states(code)
        XCTAssertTrue(s[1].st.inDirective)
        XCTAssertEqual(s.last!.st.braceDepth, 0)
        XCTAssertEqual(s.last!.st.parenDepth, 0)
        XCTAssertFalse(s.last!.st.inDirective)
    }

    func test_hashMidLine_isNotADirective() {
        let s = states("a # b")
        XCTAssertFalse(s[2].st.inDirective)
    }

    func test_indentedHash_isADirective() {
        let s = states("  #define X 1")
        XCTAssertTrue(s[2].st.inDirective)
    }

    func test_lineCommentOpensInsideDirective() {
        let s = states("#define X 1 // note")
        XCTAssertTrue(s[12].st.inLineComment)   // the first '/'
    }

    func test_earlyExit_stops() {
        var count = 0
        GLSLScanner.scan("abcdef") { _, _, _ in count += 1; return count < 3 }
        XCTAssertEqual(count, 3)
    }

    // MARK: - strip (absorbs the GLSLComments contract)

    func test_strip_blanksContent_keepsDelimitersAndNewlines() {
        XCTAssertEqual(GLSLScanner.strip("a // bc\nd"), "a //   \nd")
        XCTAssertEqual(GLSLScanner.strip("a /* b\nc */ d"), "a /*  \n  */ d")
    }

    func test_strip_noComments_identity() {
        XCTAssertEqual(GLSLScanner.strip("float x = 1.0;"), "float x = 1.0;")
    }

    func test_strip_detectionCannotSeeCommentedChannel() {
        // the M19 contract: `// TODO try iChannel2` must not invent a stub input
        let out = GLSLScanner.strip("// TODO try iChannel2\ntexture(iChannel0, uv);")
        XCTAssertFalse(out.contains("iChannel2"))
        XCTAssertTrue(out.contains("iChannel0"))
    }

    func test_strip_preservesUTF16Offsets_astralCharInComment() {
        let code = "// 🙂\nx"
        let out = GLSLScanner.strip(code)
        XCTAssertEqual((out as NSString).length, (code as NSString).length)
        XCTAssertTrue(out.hasSuffix("\nx"))
    }

    // MARK: - helpers

    func test_braceDepth_before() {
        let code = "void f() { int x; } int y;"
        let xPos = (code as NSString).range(of: "int x").location
        let yPos = (code as NSString).range(of: "int y").location
        XCTAssertEqual(GLSLScanner.braceDepth(code, before: xPos), 1)
        XCTAssertEqual(GLSLScanner.braceDepth(code, before: yPos), 0)
    }

    func test_statementEnd_skipsCommentSemicolons() {
        let code = "float x /* ; */ = 1.0; y"
        XCTAssertEqual(GLSLScanner.statementEnd(code, from: 0),
                       (code as NSString).range(of: "1.0;").location + 4)
        XCTAssertNil(GLSLScanner.statementEnd("float x = 1.0", from: 0))
    }

    func test_braceMatchEnd_skipsCommentBraces() {
        let code = "{ /* } */ a }b"
        XCTAssertEqual(GLSLScanner.braceMatchEnd(code, openBrace: 0), 13)
        XCTAssertNil(GLSLScanner.braceMatchEnd("{ a", openBrace: 0))
    }

    func test_splitArgs_commentCommaAndParenNotStructure() {
        let code = "f(a /*, ) */, b)"
        let ns = code as NSString
        let open = ns.range(of: "(").location
        let r = GLSLScanner.splitArgs(code, openParen: open)!
        XCTAssertEqual(r.argRanges.map { ns.substring(with: $0) }, ["a /*, ) */", " b"])
        XCTAssertEqual(ns.substring(with: NSRange(location: r.close, length: 1)), ")")
    }

    func test_splitArgs_nestedParens() {
        let code = "f(g(a, b), c)"
        let ns = code as NSString
        let r = GLSLScanner.splitArgs(code, openParen: 1)!
        XCTAssertEqual(r.argRanges.map { ns.substring(with: $0) }, ["g(a, b)", " c"])
    }

    func test_splitArgs_unclosed_returnsNil() {
        XCTAssertNil(GLSLScanner.splitArgs("f(a, b", openParen: 1))
    }
}
