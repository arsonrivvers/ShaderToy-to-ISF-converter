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
        let s = #"{"ideas":[{"title":"t","detail":"d","kind":"design","lines":null}]}"#
        let env = #"{"is_error":false,"result":"\#(escaped(s))"}"#
        let r = try ShaderAssistResponseParser.suggestions(fromClaudeStdout: env); XCTAssertEqual(r.ideas[0].kind, "design")
    }
    private func escaped(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }
}
