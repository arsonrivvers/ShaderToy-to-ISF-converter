import XCTest
@testable import ShadertoyISFKit
final class ShaderAssistTypesTests: XCTestCase {
    func testDecodeFixResult() throws {
        let json = #"{"explanation":"texture2D unavailable","edits":[{"fromLine":11,"toLine":11,"replacement":"IMG_PIXEL(a,b)","rationale":"use ISF sampler"}]}"#
        let r = try JSONDecoder().decode(AIFixResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.explanation, "texture2D unavailable")
        XCTAssertEqual(r.edits.count, 1); XCTAssertEqual(r.edits[0].fromLine, 11)
        XCTAssertEqual(r.edits[0].rationale, "use ISF sampler")
    }
    func testDecodeSuggestions() throws {
        let json = #"{"ideas":[{"title":"Expose speed","detail":"line 23 hardcodes rate","kind":"make-interactive","lines":[23]}]}"#
        let r = try JSONDecoder().decode(AISuggestionsResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.ideas.count, 1); XCTAssertEqual(r.ideas[0].kind, "make-interactive"); XCTAssertEqual(r.ideas[0].lines, [23])
    }
}
