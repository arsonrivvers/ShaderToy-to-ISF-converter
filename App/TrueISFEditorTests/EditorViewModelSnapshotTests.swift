import XCTest
import ShadertoyISFKit
@testable import TrueISFEditor

@MainActor
final class EditorViewModelSnapshotTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-snapshot-tests-\(UUID().uuidString)")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeVM() -> EditorViewModel {
        EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate),
                        snapshots: SnapshotStore(rootURL: root))
    }

    func testImportCapturesOpenedSnapshot() {
        let vm = makeVM()
        vm.loadImported(isf: "/*{}*/ void main(){}", warnings: [], suggestedName: "Imported")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.map(\.label), ["Imported"])
        XCTAssertEqual(snaps[0].source, "/*{}*/ void main(){}")
    }

    func testAIRewriteCapturesPreApplySource() {
        let vm = makeVM()
        let original = vm.file.source
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.0); }")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.label, "Before AI rewrite")
        XCTAssertEqual(snaps.first?.source, original,
                       "the version captured must be the PRE-apply source")
    }

    func testFixApplyCapturesPreApplySource() {
        let vm = makeVM()
        let original = vm.file.source
        // blankTemplate line 1 is "/*{" — an edit that passes the expectedContains guard.
        vm.apply(TextEdit(fromLine: 1, toLine: 1, replacement: "/*{ ", expectedContains: "/*{"))
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.label, "Before AI fix")
        XCTAssertEqual(snaps.first?.source, original)
    }

    func testGuardedFixApplyDoesNotSnapshot() {
        let vm = makeVM()
        vm.apply(TextEdit(fromLine: 1, toLine: 1, replacement: "x", expectedContains: "NOT-IN-SOURCE"))
        XCTAssertTrue(vm.snapshots.snapshots(for: vm.file).isEmpty,
                      "a rejected stale fix must not pollute the version history")
    }

    func testRestoreReplacesSourceParamsAndCapturesPreRestoreVersion() {
        let vm = makeVM()
        let restored = ParamSnapshot(params: ["gain": .float(0.9)])
        let snapshot = Snapshot(id: "s1", date: Date(), label: "Opened",
                                source: "/*{}*/ void main(){ gl_FragColor = vec4(1.0); }",
                                params: restored)
        let current = vm.file.source
        vm.restore(snapshot)
        XCTAssertEqual(vm.file.source, snapshot.source)
        XCTAssertEqual(vm.paramStore.values, ["gain": .float(0.9)])
        let labels = vm.snapshots.snapshots(for: vm.file).map(\.label)
        XCTAssertTrue(labels.contains("Before restore"))
        XCTAssertTrue(vm.snapshots.snapshots(for: vm.file).contains { $0.source == current })
    }
}
