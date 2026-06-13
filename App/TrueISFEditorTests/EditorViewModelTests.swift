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
}
