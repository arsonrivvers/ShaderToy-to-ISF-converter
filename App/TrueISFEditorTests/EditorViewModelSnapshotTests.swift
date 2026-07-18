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
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeVM() -> EditorViewModel {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate),
                                 snapshots: SnapshotStore(rootURL: root))
        vm.presentSaveErrorAlert = { error in
            XCTFail("Unexpected save error: \(error.localizedDescription)")
        }
        return vm
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

    func testSaveAsMintsNumberedVersion() throws {
        let vm = makeVM()
        let url = root.appendingPathComponent("mint.fs")
        vm.saveAs(url)
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .save(number: 1))
        XCTAssertEqual(snaps.first?.displayTitle, "v01")
        XCTAssertEqual(vm.nextSaveVersion, 2)
        XCTAssertEqual(vm.lastSaveSource, vm.file.source)
    }

    func testUnchangedSaveMintsNothing() throws {
        let vm = makeVM()
        let url = root.appendingPathComponent("same.fs")
        vm.saveAs(url)
        vm.saveInPlace()   // identical source — dedup, no v02
        let saves = vm.snapshots.snapshots(for: vm.file).filter {
            if case .save = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(vm.nextSaveVersion, 2)
    }

    func testAIApplyThenSaveNumbersSequentially() throws {
        let vm = makeVM()
        let url = root.appendingPathComponent("seq.fs")
        vm.saveAs(url)                                                    // v01
        vm.file.source = "/*{}*/ void main(){ gl_FragColor = vec4(0.25); }" // manual edit
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.5); }") // aiApply capture
        vm.saveInPlace()                                                  // v02
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .save(number: 2))
        XCTAssertTrue(snaps.contains { $0.kind == .aiApply })
    }

    func testPinCapturesWithName() {
        let vm = makeVM()
        vm.pin(name: "good strobe feel")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .pin(name: "good strobe feel"))
        XCTAssertEqual(snaps.first?.displayTitle, "good strobe feel")
    }
}
