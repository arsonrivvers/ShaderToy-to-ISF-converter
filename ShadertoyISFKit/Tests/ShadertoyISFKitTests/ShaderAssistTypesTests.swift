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
    func testDecodeSuggestionGoals() throws {
        let json = #"{"goals":[{"id":"expose-controls","title":"Expose controls","detail":"Turn constants into INPUTS","kind":"make-interactive","whyThisShader":"The shader has hardcoded speed constants."}]}"#
        let r = try JSONDecoder().decode(AISuggestionGoalsResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.goals.count, 1)
        XCTAssertEqual(r.goals[0].id, "expose-controls")
        XCTAssertEqual(r.goals[0].whyThisShader, "The shader has hardcoded speed constants.")
    }

    func testDecodeSuggestionsWithGoalStableIDsAndImpact() throws {
        let json = #"{"goal":"Expose controls","ideas":[{"id":"speed-slider","title":"Expose speed","detail":"Line 23 hardcodes rate","kind":"make-interactive","lines":[23],"impact":"Makes speed playable live."}]}"#
        let r = try JSONDecoder().decode(AISuggestionsResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.goal, "Expose controls")
        XCTAssertEqual(r.ideas.count, 1)
        XCTAssertEqual(r.ideas[0].id, "speed-slider")
        XCTAssertEqual(r.ideas[0].impact, "Makes speed playable live.")
    }

    func testDecodeLegacySuggestionsStillWorks() throws {
        let json = #"{"ideas":[{"title":"Expose speed","detail":"line 23 hardcodes rate","kind":"make-interactive","lines":[23]}]}"#
        let r = try JSONDecoder().decode(AISuggestionsResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.goal, "")
        XCTAssertEqual(r.ideas[0].id, "Expose speed")
        XCTAssertNil(r.ideas[0].impact)
    }

    func testDecodeApplyResult() throws {
        let json = #"{"explanation":"Added controls","replacementSource":"/*{}*/\nvoid main(){}","changedLines":[3,7]}"#
        let r = try JSONDecoder().decode(AIApplyResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.explanation, "Added controls")
        XCTAssertTrue(r.replacementSource.contains("void main"))
        XCTAssertEqual(r.changedLines, [3, 7])
    }
}
