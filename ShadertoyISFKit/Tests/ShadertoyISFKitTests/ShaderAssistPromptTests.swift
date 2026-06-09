import XCTest
@testable import ShadertoyISFKit
final class ShaderAssistPromptTests: XCTestCase {
    func testUserPromptHasNumberedSourceAndDiagnostics() {
        let src = "void main(){\n  gl_FragColor = vec4(1.0);\n}"
        let diags = [Diagnostic.compiler(message: "ERROR: 2: bad", line: 2)]
        let p = ShaderAssistPrompt.user(task: .diagnoseAndFix, source: src, diagnostics: diags)
        XCTAssertTrue(p.contains("1: void main(){")); XCTAssertTrue(p.contains("ERROR: 2: bad"))
    }
    func testSystemNamesBothSkillsAndJSONOnly() {
        let s = ShaderAssistPrompt.system(for: .diagnoseAndFix)
        XCTAssertTrue(s.contains("isf-shader-development")); XCTAssertTrue(s.contains("shader-dev"))
        XCTAssertTrue(s.lowercased().contains("json")); XCTAssertTrue(s.contains("\"edits\""))
    }
    func testSuggestionsSystemHasIdeasSchema() { XCTAssertTrue(ShaderAssistPrompt.system(for: .suggestions).contains("\"ideas\"")) }
}
