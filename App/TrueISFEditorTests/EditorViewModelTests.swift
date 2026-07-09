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
}
