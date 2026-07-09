import XCTest

/// M32 — WebKit runtime errors must reach the diagnostics pipeline. `EditorViewModel` maps
/// `compileError` to the gutter only when `compileValid` is false, so a "runtime" message that
/// left `compileValid == true` showed a broken render with "No diagnostics".
@MainActor
final class WebKitPreviewControllerTests: XCTestCase {
    func testCompileMessage_parsesStateAndInputs() {
        let c = WebKitPreviewController()
        c.handleScriptMessage([
            "type": "compile", "valid": true,
            "inputs": [["NAME": "gain", "TYPE": "float"]],
        ])
        XCTAssertTrue(c.compileValid)
        XCTAssertNil(c.compileError)
        XCTAssertEqual(c.inputs.map(\.name), ["gain"])
    }

    func testRuntimeError_invalidatesCompileSoDiagnosticsShowIt() {
        let c = WebKitPreviewController()
        c.handleScriptMessage(["type": "compile", "valid": true, "inputs": [[String: Any]]()])
        c.handleScriptMessage(["type": "runtime", "error": "uniform u not bound"])
        XCTAssertEqual(c.compileError, "uniform u not bound")
        XCTAssertFalse(c.compileValid, "a runtime error must surface through the diagnostics path")
    }
}
