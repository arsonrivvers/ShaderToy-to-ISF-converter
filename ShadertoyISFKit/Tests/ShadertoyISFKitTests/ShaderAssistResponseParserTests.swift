import XCTest
@testable import ShadertoyISFKit
final class ShaderAssistResponseParserTests: XCTestCase {
    private let inner = #"{"explanation":"e","edits":[{"fromLine":1,"toLine":1,"replacement":"x","rationale":"r"}]}"#
    func testEnvelopeWithBareJSON() throws {
        let env = #"{"type":"result","subtype":"success","is_error":false,"result":"\#(escaped(inner))"}"#
        let r = try ShaderAssistResponseParser.fixResult(fromClaudeStdout: env)
        XCTAssertEqual(r.explanation, "e"); XCTAssertEqual(r.edits.count, 1)
    }
    func testEnvelopeWithFencedJSON() throws {
        let fenced = "Here is the fix:\n```json\n\(inner)\n```"
        let env = #"{"type":"result","is_error":false,"result":"\#(escaped(fenced))"}"#
        let r = try ShaderAssistResponseParser.fixResult(fromClaudeStdout: env)
        XCTAssertEqual(r.edits[0].replacement, "x")
    }
    func testRawInnerNoEnvelope() throws {
        let r = try ShaderAssistResponseParser.fixResult(fromClaudeStdout: inner); XCTAssertEqual(r.explanation, "e")
    }
    func testMalformedThrowsUnparseable() {
        XCTAssertThrowsError(try ShaderAssistResponseParser.fixResult(fromClaudeStdout: "no json here")) { err in
            guard case ShaderAssistParseError.unparseable = err else { return XCTFail("wrong error") }
        }
    }
    func testSuggestionsParse() throws {
        let s = #"{"goal":"Design","ideas":[{"id":"palette","title":"t","detail":"d","kind":"design","lines":null,"impact":"i"}]}"#
        let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
        let r = try ShaderAssistResponseParser.suggestions(fromClaudeStdout: env)
        XCTAssertEqual(r.goal, "Design")
        XCTAssertEqual(r.ideas[0].id, "palette")
        XCTAssertEqual(r.ideas[0].impact, "i")
    }
    func testSuggestionGoalsParse() throws {
        let s = #"{"goals":[{"id":"motion","title":"Add motion","detail":"Animate the field","kind":"design","whyThisShader":"The current shader is static."}]}"#
        let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
        let r = try ShaderAssistResponseParser.suggestionGoals(fromClaudeStdout: env)
        XCTAssertEqual(r.goals[0].id, "motion")
    }
    func testApplyResultParse() throws {
        let s = #"{"explanation":"Added input","replacementSource":"/*{}*/\nvoid main(){}","changedLines":[2]}"#
        let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
        let r = try ShaderAssistResponseParser.applyResult(fromClaudeStdout: env)
        XCTAssertEqual(r.changedLines, [2])
        XCTAssertTrue(r.replacementSource.contains("void main"))
    }

    func testApplyResultParseIgnoresBracesInsideReplacementString() throws {
        let replacement = "/*{}*/\n// Preserved comment with }\nvoid main() { gl_FragColor = vec4(1.0); }"
        let s = #"{"explanation":"Kept comment","replacementSource":"\#(escaped(replacement))","changedLines":[3]}"#
        let r = try ShaderAssistResponseParser.applyResult(fromClaudeStdout: s)
        XCTAssertEqual(r.replacementSource, replacement)
    }

    /// N3 — almost-valid JSON (one missing key) must carry the field-level DecodingError detail,
    /// not collapse into a generic unparseable(raw:) the user has to re-debug by hand.
    func testDecodeFailure_carriesDecodingDetail() {
        let raw = #"{"goals":[{"id":"x"}]}"#   // missing "title" etc.
        XCTAssertThrowsError(try ShaderAssistResponseParser.suggestionGoals(fromClaudeStdout: raw)) { err in
            guard case ShaderAssistParseError.malformed(let detail, _) = err else {
                return XCTFail("expected .malformed, got \(err)")
            }
            XCTAssertTrue(detail.contains("title"), detail)
        }
    }

    /// N3 sibling — an is_error envelope used to become unparseable(raw: ""), throwing away the
    /// CLI's actual error message (quota, auth, timeout).
    func testIsErrorEnvelope_preservesCLIErrorText() {
        let raw = #"{"type":"result","result":"Credit balance too low","is_error":true}"#
        XCTAssertThrowsError(try ShaderAssistResponseParser.fixResult(fromClaudeStdout: raw)) { err in
            guard case ShaderAssistParseError.cliError(let message) = err else {
                return XCTFail("expected .cliError, got \(err)")
            }
            XCTAssertTrue(message.contains("Credit balance"), message)
        }
    }

    private func escaped(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }
}
