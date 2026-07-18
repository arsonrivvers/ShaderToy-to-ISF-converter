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
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.5); }") // aiApply capture
        vm.saveInPlace()                                                  // v02
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.first?.kind, .save(number: 2))
        XCTAssertTrue(snaps.contains { $0.kind == .aiApply })
    }

    func testPinCapturesWithName() {
        let vm = makeVM()
        vm.saveAs(root.appendingPathComponent("pin.fs"))
        vm.pin(name: "good strobe feel")
        let snaps = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snaps.count, 2)
        XCTAssertEqual(snaps.first?.kind, .pin(name: "good strobe feel"))
        XCTAssertEqual(snaps.first?.displayTitle, "good strobe feel")
        XCTAssertEqual(snaps.last?.kind, .save(number: 1))
    }

    func testAssistAppliedLifecycle() {
        let vm = makeVM()
        XCTAssertFalse(vm.assistApplied)
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        XCTAssertTrue(vm.assistApplied, "AI apply raises the save-nudge flag")
        vm.clearAssistNudge()
        XCTAssertFalse(vm.assistApplied)
    }

    func testManualEditClearsAssistNudge() {
        let vm = makeVM()
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        vm.editor.onChange?("/*{}*/ void main(){ gl_FragColor = vec4(0.2); }")  // user typed
        XCTAssertFalse(vm.assistApplied, "a manual edit makes 'Rewrite applied' stale")
        XCTAssertTrue(vm.file.isDirty)
    }

    func testHeaderRewriteClearsAssistNudge() {
        let vm = makeVM()
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        XCTAssertTrue(vm.assistApplied)

        vm.headerModel.update {
            $0.inputs.append(.makeDefault(type: "float", name: "gain"))
        }

        XCTAssertFalse(vm.assistApplied,
                       "a GUI header rewrite makes 'Rewrite applied' stale")
    }

    func testRestoreClearsAssistNudge() {
        let vm = makeVM()
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        XCTAssertTrue(vm.assistApplied)
        let snapshot = Snapshot(id: "restore-target", date: Date(), label: "Earlier",
                                source: "/*{}*/ void main(){ gl_FragColor = vec4(0.8); }",
                                params: ParamSnapshot(params: [:]))

        vm.restore(snapshot)

        XCTAssertFalse(vm.assistApplied,
                       "restoring a version makes 'Rewrite applied' stale")
    }

    func testSaveClearsAssistNudge() throws {
        let vm = makeVM()
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.1); }")
        vm.saveAs(root.appendingPathComponent("nudge.fs"))
        XCTAssertFalse(vm.assistApplied)
    }

    func testManualEditDebounceUpdatesChangeMarksAndSaveClearsUnderHarness() async throws {
        let vm = makeVM()
        vm.editor.onChange?("a\nb")
        vm.saveAs(root.appendingPathComponent("gutter.fs"))
        XCTAssertEqual(vm.editor.lastChangeMarksForTest.added, [])
        XCTAssertEqual(vm.editor.lastChangeMarksForTest.changed, [])

        vm.editor.onChange?("a\nX\nb")
        let deadline = Date().addingTimeInterval(2)
        while vm.editor.lastChangeMarksForTest.added != [2], Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(vm.editor.lastChangeMarksForTest.added, [2])
        XCTAssertEqual(vm.editor.lastChangeMarksForTest.changed, [])

        vm.saveInPlace()
        XCTAssertEqual(vm.editor.lastChangeMarksForTest.added, [])
        XCTAssertEqual(vm.editor.lastChangeMarksForTest.changed, [])
    }

    func testPinAfterEditDoesNotSuppressNextNumberedSave() {
        let vm = makeVM()
        let sourceA = vm.file.source
        let sourceB = "/*{}*/ void main(){ gl_FragColor = vec4(0.25); }"

        vm.saveAs(root.appendingPathComponent("pin-then-save.fs"))   // v01(A)
        vm.file.source = sourceB                                    // edit B
        vm.pin(name: "B pin")                                      // pin(B)
        vm.saveInPlace()                                            // v02(B)

        let saves = vm.snapshots.snapshots(for: vm.file).filter {
            if case .save = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(saves.map(\.kind), [.save(number: 2), .save(number: 1)])
        XCTAssertEqual(saves.map(\.source), [sourceB, sourceA])
        XCTAssertEqual(vm.nextSaveVersion, 3)
        XCTAssertEqual(vm.lastSaveSource, sourceB)
    }

    func testFirstSaveAsPreservesUntitledAIAndPinHistoryBeforeMintingSave() {
        let vm = makeVM()
        let original = vm.file.source
        let rewritten = "/*{}*/ void main(){ gl_FragColor = vec4(0.4); }"
        vm.replaceSourceFromAssist(rewritten)
        vm.pin(name: "keep this")
        let untitledFile = vm.file

        vm.saveAs(root.appendingPathComponent("First-save-as.fs"))

        let snapshots = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertTrue(snapshots.contains { $0.kind == .aiApply && $0.source == original })
        XCTAssertTrue(snapshots.contains { $0.kind == .pin(name: "keep this") && $0.source == rewritten })
        XCTAssertTrue(snapshots.contains { $0.kind == .save(number: 1) && $0.source == rewritten })
        XCTAssertTrue(vm.snapshots.snapshots(for: untitledFile).isEmpty,
                      "Save As must retire the temporary untitled history key")
        XCTAssertEqual(vm.versionCount, 3)
        XCTAssertEqual(vm.nextSaveVersion, 2)
        XCTAssertEqual(vm.lastSaveSource, rewritten)
    }

    func testLaterSaveAsMovesExistingTimelineAndContinuesSaveNumbers() {
        let vm = makeVM()
        let original = vm.file.source
        let firstRewrite = "/*{}*/ void main(){ gl_FragColor = vec4(0.4); }"
        let laterEdit = "/*{}*/ void main(){ gl_FragColor = vec4(0.8); }"
        vm.replaceSourceFromAssist(firstRewrite)
        vm.pin(name: "first look")
        vm.saveAs(root.appendingPathComponent("First-path.fs"))
        let firstSavedFile = vm.file

        vm.editor.onChange?(laterEdit)
        vm.saveAs(root.appendingPathComponent("Second-path.fs"))

        let snapshots = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(snapshots.count, 4)
        XCTAssertTrue(snapshots.contains { $0.kind == .aiApply && $0.source == original })
        XCTAssertTrue(snapshots.contains { $0.kind == .pin(name: "first look") })
        let saves = snapshots.filter {
            if case .save = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(saves.map(\.kind), [.save(number: 2), .save(number: 1)])
        XCTAssertEqual(saves.map(\.source), [laterEdit, firstRewrite])
        XCTAssertTrue(vm.snapshots.snapshots(for: firstSavedFile).isEmpty,
                      "a later Save As must retire the previous path's history key")
        XCTAssertEqual(vm.versionCount, 4)
        XCTAssertEqual(vm.nextSaveVersion, 3)
        XCTAssertEqual(vm.lastSaveSource, laterEdit)
    }

    func testFailedSaveAsHistoryMigrationRetriesOnNextSave() throws {
        let vm = makeVM()
        let rewritten = "/*{}*/ void main(){ gl_FragColor = vec4(0.6); }"
        vm.replaceSourceFromAssist(rewritten)
        vm.pin(name: "retry me")
        let untitledFile = vm.file
        let target = root.appendingPathComponent("History-blocked.fs")
        var destinationFile = untitledFile
        try destinationFile.save(to: target)
        let blockedHistoryDirectory = root
            .appendingPathComponent(SnapshotStore.documentKey(for: destinationFile))
        try Data("not a directory".utf8).write(to: blockedHistoryDirectory)

        vm.saveAs(target)

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), rewritten)
        XCTAssertEqual(vm.file.url, target)
        XCTAssertFalse(vm.file.isDirty)
        XCTAssertEqual(vm.snapshots.snapshots(for: untitledFile).count, 2,
                       "failed migration keeps the old history available for a later retry")

        try FileManager.default.removeItem(at: blockedHistoryDirectory)
        vm.saveInPlace()

        let migrated = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(migrated.count, 3)
        XCTAssertTrue(migrated.contains { $0.kind == .aiApply })
        XCTAssertTrue(migrated.contains { $0.kind == .pin(name: "retry me") })
        XCTAssertTrue(migrated.contains { $0.kind == .save(number: 1) })
        XCTAssertTrue(vm.snapshots.snapshots(for: untitledFile).isEmpty)
        XCTAssertEqual(vm.versionCount, 3)
        XCTAssertEqual(vm.nextSaveVersion, 2)
        XCTAssertEqual(vm.lastSaveSource, rewritten)
    }

    func testReopeningSameSavedDocumentKeepsPendingHistoryRetry() throws {
        let vm = makeVM()
        let rewritten = "/*{}*/ void main(){ gl_FragColor = vec4(0.65); }"
        vm.replaceSourceFromAssist(rewritten)
        vm.pin(name: "survive reopen")
        let untitledFile = vm.file
        let target = root.appendingPathComponent("Reopen-pending.fs")
        var destinationFile = untitledFile
        try destinationFile.save(to: target)
        let blocker = root.appendingPathComponent(
            SnapshotStore.documentKey(for: destinationFile)
        )
        try Data("not a directory".utf8).write(to: blocker)
        vm.saveAs(target)

        vm.open(TrueISFEditor.LibraryEntry(url: target))
        try FileManager.default.removeItem(at: blocker)
        vm.saveInPlace()

        let migrated = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(migrated.count, 3)
        XCTAssertTrue(migrated.contains { $0.kind == .aiApply })
        XCTAssertTrue(migrated.contains { $0.kind == .pin(name: "survive reopen") })
        XCTAssertTrue(migrated.contains { $0.kind == .save(number: 1) })
        XCTAssertTrue(vm.snapshots.snapshots(for: untitledFile).isEmpty)
        XCTAssertEqual(vm.versionCount, 3)
        XCTAssertEqual(vm.nextSaveVersion, 2)
        XCTAssertEqual(vm.lastSaveSource, rewritten)
    }

    func testSaveAsMergesNumberCollisionsBeforeMintingNextSave() throws {
        let vm = makeVM()
        let params = ParamSnapshot(params: [:])
        let sourceV1 = vm.file.source
        XCTAssertNotNil(vm.snapshots.capture(file: vm.file, params: params,
                                             label: "v01", kind: .save(number: 1)))
        let sourceV2 = "/*{}*/ void main(){ gl_FragColor = vec4(0.2); }"
        vm.file.source = sourceV2
        XCTAssertNotNil(vm.snapshots.capture(file: vm.file, params: params,
                                             label: "v02", kind: .save(number: 2)))
        let sourceFile = vm.file

        let target = root.appendingPathComponent("Existing-timeline.fs")
        var destinationFile = TrueISFEditor.ISFFile.untitled(
            source: "/*{}*/ void main(){ gl_FragColor = vec4(0.5); }",
            suggestedName: "Existing-timeline.fs"
        )
        try destinationFile.save(to: target)
        let destinationV1 = destinationFile.source
        XCTAssertNotNil(vm.snapshots.capture(file: destinationFile, params: params,
                                             label: "v01", kind: .save(number: 1)))
        let destinationV2 = "/*{}*/ void main(){ gl_FragColor = vec4(0.7); }"
        destinationFile.source = destinationV2
        XCTAssertNotNil(vm.snapshots.capture(file: destinationFile, params: params,
                                             label: "v02", kind: .save(number: 2)))

        let currentSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.9); }"
        vm.file.source = currentSource
        vm.saveAs(target)

        let saves = vm.snapshots.snapshots(for: vm.file).compactMap { snapshot -> (String, Int)? in
            if case .save(let number) = snapshot.kind { return (snapshot.source, number) }
            return nil
        }
        let savesBySource = Dictionary(uniqueKeysWithValues: saves)
        XCTAssertEqual(savesBySource, [
            destinationV1: 1,
            destinationV2: 2,
            sourceV1: 3,
            sourceV2: 4,
            currentSource: 5
        ])
        XCTAssertEqual(Set(saves.map(\.1)).count, saves.count)
        XCTAssertTrue(vm.snapshots.snapshots(for: sourceFile).isEmpty)
        XCTAssertEqual(vm.versionCount, 5)
        XCTAssertEqual(vm.nextSaveVersion, 6)
        XCTAssertEqual(vm.lastSaveSource, currentSource)
    }

    func testDocumentSwitchClearsPendingHistoryMigration() throws {
        let vm = makeVM()
        let oldSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.1); }"
        vm.loadExample(name: "Pending-source.fs", source: oldSource)
        vm.replaceSourceFromAssist("/*{}*/ void main(){ gl_FragColor = vec4(0.2); }")
        vm.pin(name: "old pin")
        let oldFile = vm.file
        let blockedTarget = root.appendingPathComponent("Blocked-old.fs")
        var blockedDestination = oldFile
        try blockedDestination.save(to: blockedTarget)
        let blocker = root.appendingPathComponent(
            SnapshotStore.documentKey(for: blockedDestination)
        )
        try Data("not a directory".utf8).write(to: blocker)
        vm.saveAs(blockedTarget)

        let newSource = "/*{}*/ void main(){ gl_FragColor = vec4(0.9); }"
        vm.loadExample(name: "New-document.fs", source: newSource)
        try FileManager.default.removeItem(at: blocker)
        vm.saveAs(root.appendingPathComponent("New-document-saved.fs"))

        let current = vm.snapshots.snapshots(for: vm.file)
        XCTAssertEqual(current.count, 2, "only the new document's opened safety + v01 belong here")
        XCTAssertFalse(current.contains { $0.kind == .pin(name: "old pin") })
        XCTAssertEqual(vm.snapshots.snapshots(for: oldFile).count, 3,
                       "clearing pending work must not delete the old shader's recoverable history")
    }
}
