import XCTest
@testable import TrueISFEditor

@MainActor
final class EditorViewModelTests: XCTestCase {
    func testReplaceSourceFromAssistUpdatesSourceHeaderAndStatus() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        let source = """
        /*{
          "DESCRIPTION": "Applied",
          "CATEGORIES": ["Generator"],
          "INPUTS": [
            {"NAME": "gain", "TYPE": "float", "DEFAULT": 0.5}
          ]
        }*/

        void main() {
            gl_FragColor = vec4(gain);
        }
        """

        vm.replaceSourceFromAssist(source)

        XCTAssertEqual(vm.file.source, source)
        XCTAssertEqual(vm.statusMessage, "Applied ShaderAssist suggestions")
        XCTAssertEqual(vm.headerModel.header.inputs.map(\.name), ["gain"])
    }

    // MARK: M30 — controls state must reset per document, survive same-doc edits

    func testDocumentGeneration_bumpsOnDocumentSwitch_notOnEdit() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        let g0 = vm.documentGeneration
        vm.newUntitled()
        XCTAssertEqual(vm.documentGeneration, g0 + 1, "new document must bump the generation")
        vm.loadImported(isf: EditorViewModel.blankTemplate, warnings: [], suggestedName: "X")
        XCTAssertEqual(vm.documentGeneration, g0 + 2, "import must bump the generation")
        vm.loadExample(name: "ex", source: EditorViewModel.blankTemplate)
        XCTAssertEqual(vm.documentGeneration, g0 + 3, "example must bump the generation")
        // Same-document editing must NOT bump — slider state survives live recompiles.
        vm.file.source = "// edited"
        vm.replaceSourceFromAssist(EditorViewModel.blankTemplate)
        XCTAssertEqual(vm.documentGeneration, g0 + 3, "same-doc edits must not bump")
    }

    func testDefaultRenderSizeIs1080p16x9() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        XCTAssertEqual(vm.renderWidth, 1920)
        XCTAssertEqual(vm.renderHeight, 1080)
        XCTAssertTrue(vm.fitToWindow)
    }

    // MARK: C8 — dirty-document guard (the library list is selection-driven; before the guard,
    // one stray click silently destroyed unsaved edits)

    func testDirtyDocument_declinedConfirm_keepsDocument() {
        let vm = EditorViewModel(file: .untitled(source: "original"))
        vm.file.source = "edited"                                  // marks dirty
        var asked = 0
        vm.confirmDiscardIfDirty = { asked += 1; return false }
        vm.newUntitled()
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(vm.file.source, "edited", "declining the confirm must keep the document")
    }

    func testDirtyDocument_confirmedDiscard_replaces() {
        let vm = EditorViewModel(file: .untitled(source: "original"))
        vm.file.source = "edited"
        vm.confirmDiscardIfDirty = { true }
        vm.newUntitled()
        XCTAssertEqual(vm.file.source, EditorViewModel.blankTemplate)
    }

    func testCleanDocument_replacesWithoutAsking() {
        let vm = EditorViewModel(file: .untitled(source: "original"))
        var asked = 0
        vm.confirmDiscardIfDirty = { asked += 1; return true }
        vm.newUntitled()
        XCTAssertEqual(asked, 0, "a clean document must be replaced without a prompt")
        XCTAssertEqual(vm.file.source, EditorViewModel.blankTemplate)
    }

    func testLoadImported_respectsDirtyGuard() {
        let vm = EditorViewModel(file: .untitled(source: "original"))
        vm.file.source = "edited"
        vm.confirmDiscardIfDirty = { false }
        vm.loadImported(isf: "/*{\"INPUTS\":[]}*/\nvoid main(){}", warnings: [], suggestedName: "X")
        XCTAssertEqual(vm.file.source, "edited")
        XCTAssertNil(vm.conversionReportTitle)
    }

    // MARK: C11 — open() must sync the header tabs and clear a stale import report; before the
    // fix a GUI header edit after open() spliced the PREVIOUS document's header into the new file.

    func testOpen_syncsHeaderModel_andClearsStaleReport() throws {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        vm.conversionReportTitle = "Imported Old"
        let src = """
        /*{
          "DESCRIPTION": "Opened",
          "CATEGORIES": ["Generator"],
          "INPUTS": [
            {"NAME": "speed", "TYPE": "float", "DEFAULT": 1.0}
          ]
        }*/

        void main() {
            gl_FragColor = vec4(speed);
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("c11-open-\(UUID().uuidString).fs")
        try src.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        vm.open(TrueISFEditor.LibraryEntry(url: url))

        XCTAssertEqual(vm.headerModel.header.inputs.map(\.name), ["speed"],
                       "open() must sync the Inputs/Passes tabs to the opened document")
        XCTAssertNil(vm.conversionReportTitle,
                     "a stale import report must not float over an opened document")
    }

    func testNewUntitled_clearsStaleReport() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        vm.conversionReportTitle = "Imported Old"
        vm.newUntitled()
        XCTAssertNil(vm.conversionReportTitle)
    }

    // MARK: A4 — save failures must raise the (injectable) alert, not just the 5s toast

    func testSaveFailureRaisesAlert() {
        let vm = EditorViewModel(file: .untitled(source: "x"))
        var alerted: Error?
        vm.presentSaveErrorAlert = { alerted = $0 }
        vm.saveAs(URL(fileURLWithPath: "/nonexistent-dir-a4/\(UUID().uuidString)/f.fs"))
        XCTAssertNotNil(alerted, "failed save must surface via the alert path")
        XCTAssertTrue(vm.statusMessage.contains("Save failed"))
    }

    // MARK: A1 — document switches must DROP editor undo history (resetText), while in-document
    // programmatic replacements (AI apply) must stay undoable (setText). Before the fix, ⌘Z after
    // opening doc B restored doc A's text into B and ⌘S corrupted B's file.

    func testDocumentSwitchDropsHistory_assistApplyKeepsIt() throws {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("a1-reset-\(UUID().uuidString).fs")
        try "/*{}*/\nvoid main(){ gl_FragColor = vec4(1.0); }".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(vm.editor.lastResetTextForTest, "no reset before any document switch")
        vm.open(TrueISFEditor.LibraryEntry(url: url))
        XCTAssertNotNil(vm.editor.lastResetTextForTest, "open() must reset editor history")

        let marker = "/*{}*/\nvoid main(){ gl_FragColor = vec4(0.5); }"
        vm.replaceSourceFromAssist(marker)
        XCTAssertNotEqual(vm.editor.lastResetTextForTest, marker,
                          "AI apply must use setText (undoable), never resetText")

        vm.newUntitled()
        XCTAssertEqual(vm.editor.lastResetTextForTest, EditorViewModel.blankTemplate,
                       "newUntitled must reset editor history")
    }
}
