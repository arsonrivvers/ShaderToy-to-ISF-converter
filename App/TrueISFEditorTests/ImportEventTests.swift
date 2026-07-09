import XCTest
@testable import TrueISFEditor

final class ImportEventTests: XCTestCase {
    func test_success_summaryLine() {
        let e = ImportEvent(query: "N323DD", shaderID: "N323DD", fetchSource: .webView,
                            httpStatus: 200, stage: .converted, outcome: .success,
                            message: "Converted cleanly.", responseSnippet: nil, warningCount: 0)
        XCTAssertEqual(e.summaryLine, "✓ Converted")
    }
    func test_warning_summaryLine_pluralizes() {
        let e = ImportEvent(query: "x", shaderID: "x", fetchSource: .webView, httpStatus: 200,
                            stage: .converted, outcome: .warning, message: "Converted with 2 warning(s).",
                            responseSnippet: nil, warningCount: 2)
        XCTAssertEqual(e.summaryLine, "✓ Converted (2 warnings)")
    }
    func test_warning_summaryLine_singular() {
        let e = ImportEvent(query: "x", shaderID: "x", fetchSource: .webView, httpStatus: 200,
                            stage: .converted, outcome: .warning, message: "m", responseSnippet: nil, warningCount: 1)
        XCTAssertEqual(e.summaryLine, "✓ Converted (1 warning)")
    }
    func test_error_summaryLine() {
        let e = ImportEvent(query: "x", shaderID: nil, fetchSource: .webView, httpStatus: nil,
                            stage: .urlInvalid, outcome: .error, message: "That doesn't look like a Shadertoy URL or ID.",
                            responseSnippet: nil, warningCount: 0)
        XCTAssertEqual(e.summaryLine, "✗ That doesn't look like a Shadertoy URL or ID.")
    }
    func test_codableRoundTrip() throws {
        let e = ImportEvent(query: "q", shaderID: "id", fetchSource: .api, httpStatus: 403,
                            stage: .fetched, outcome: .error, message: "m", responseSnippet: "body…", warningCount: 0)
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(ImportEvent.self, from: data), e)
    }
    func test_renderedStage_codableRoundTrip() throws {
        let e = ImportEvent(query: "q", shaderID: "abc", fetchSource: .webView, httpStatus: nil,
                            stage: .rendered, outcome: .error,
                            message: "pixel gate: BLACK — compiled but renders black",
                            responseSnippet: nil, warningCount: 0)
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(ImportEvent.self, from: data)
        XCTAssertEqual(back.stage, .rendered)
        XCTAssertEqual(back, e)
    }
}
