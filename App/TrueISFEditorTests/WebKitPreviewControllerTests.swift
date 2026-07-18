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

/// Runtime contract for the bundled CodeMirror resource and its Swift ready-gated bridge.
@MainActor
final class CodeEditorControllerBridgeTests: XCTestCase {
    func testChangeMarksQueueBeforeReadyRenderAndClear() async throws {
        let controller = CodeEditorController()
        controller.setText("one\ntwo\nthree")
        controller.setChangeMarks(added: [2, 99], changed: [-1, 3])

        try await waitForCount(".cm-editor", equals: 1, in: controller)
        try await waitForCount(".cm-changebar-added", equals: 1, in: controller)
        try await waitForCount(".cm-changebar-changed", equals: 1, in: controller)

        controller.setChangeMarks(added: [], changed: [])
        try await waitForCount(".cm-changebar", equals: 0, in: controller)
    }

    private func waitForCount(_ selector: String, equals expected: Int,
                              in controller: CodeEditorController,
                              timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let count = try? await elementCount(selector, in: controller), count == expected {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let actual = try? await elementCount(selector, in: controller)
        let actualDescription = actual.map(String.init) ?? "unavailable"
        XCTFail("Timed out waiting for \(selector) count \(expected); got \(actualDescription)")
    }

    private func elementCount(_ selector: String,
                              in controller: CodeEditorController) async throws -> Int {
        let selectorData = try JSONEncoder().encode(selector)
        let selectorJSON = String(data: selectorData, encoding: .utf8)!
        let value = try await controller.webView.evaluateJavaScript(
            "document.querySelectorAll(\(selectorJSON)).length"
        )
        return (value as? NSNumber)?.intValue ?? -1
    }
}
