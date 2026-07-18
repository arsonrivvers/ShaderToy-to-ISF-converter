import XCTest
@testable import TrueISFEditor

@MainActor
final class SnapshotStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-tests-\(UUID().uuidString)")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testCaptureAndListRoundTrip() {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "v1", suggestedName: "Doc")
        let snap = store.capture(file: file, params: ParamSnapshot(params: ["gain": .float(0.5)]),
                                 label: "Opened")
        XCTAssertNotNil(snap)
        let listed = store.snapshots(for: file)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].source, "v1")
        XCTAssertEqual(listed[0].label, "Opened")
        XCTAssertEqual(listed[0].params.params, ["gain": .float(0.5)])
    }

    func testCaptureDedupesIdenticalSource() {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "same", suggestedName: "Doc")
        XCTAssertNotNil(store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Opened"))
        XCTAssertNil(store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Opened"),
                     "identical source must not stack duplicate versions")
        XCTAssertEqual(store.snapshots(for: file).count, 1)
    }

    func testCapIsEnforcedOldestPruned() {
        let store = SnapshotStore(rootURL: root, cap: 3)
        var file = TrueISFEditor.ISFFile.untitled(source: "v0", suggestedName: "Doc")
        for i in 1...5 {
            file.source = "v\(i)"
            XCTAssertNotNil(store.capture(file: file, params: ParamSnapshot(params: [:]),
                                          label: "step \(i)"))
        }
        let listed = store.snapshots(for: file)
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(listed.first?.source, "v5", "newest first")
        XCTAssertEqual(listed.last?.source, "v3", "oldest beyond cap pruned")
    }

    func testDocumentsKeepSeparateHistories() {
        let store = SnapshotStore(rootURL: root)
        let a = TrueISFEditor.ISFFile.untitled(source: "aaa", suggestedName: "A")
        let b = TrueISFEditor.ISFFile.untitled(source: "bbb", suggestedName: "B")
        store.capture(file: a, params: ParamSnapshot(params: [:]), label: "Opened")
        store.capture(file: b, params: ParamSnapshot(params: [:]), label: "Opened")
        XCTAssertEqual(store.snapshots(for: a).map(\.source), ["aaa"])
        XCTAssertEqual(store.snapshots(for: b).map(\.source), ["bbb"])
    }

    func testCorruptSnapshotFileIsSkippedNotFatal() throws {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "good", suggestedName: "Doc")
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Opened")
        let dir = root.appendingPathComponent(SnapshotStore.documentKey(for: file))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("zzz-corrupt.json"))
        XCTAssertEqual(store.snapshots(for: file).count, 1, "corrupt file skipped, list survives")
    }

    func testKindRoundTripsThroughDisk() {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "a", suggestedName: "Doc.fs")
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v01", kind: .save(number: 1))
        var f2 = file; f2.source = "b"
        store.capture(file: f2, params: ParamSnapshot(params: [:]), label: "good strobe feel", kind: .pin(name: "good strobe feel"))
        var f3 = file; f3.source = "c"
        store.capture(file: f3, params: ParamSnapshot(params: [:]), label: "Before AI rewrite", kind: .aiApply)
        let snaps = store.snapshots(for: f3)   // same document key (same suggestedName)
        XCTAssertEqual(snaps.map(\.kind), [.aiApply, .pin(name: "good strobe feel"), .save(number: 1)])
    }

    func testMissingKindDecodesAsLegacy() throws {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "a", suggestedName: "Old.fs")
        // Simulate a pre-kind snapshot file: write JSON without kind/number/name fields.
        let dir = root.appendingPathComponent(SnapshotStore.documentKey(for: file))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"date":100.5,"label":"Opened","source":"a","params":{"params":{}}}"#
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("20260101-000000-000.json"))
        let snaps = store.snapshots(for: file)
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].kind, .legacy)
        XCTAssertEqual(snaps[0].displayTitle, "Opened")   // legacy shows its stored label
    }

    func testNextSaveNumberSkipsNonSavesAndSurvivesGaps() {
        let store = SnapshotStore(rootURL: root)
        var file = TrueISFEditor.ISFFile.untitled(source: "a", suggestedName: "N.fs")
        XCTAssertEqual(store.nextSaveNumber(for: file), 1)   // empty history → v01
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v03", kind: .save(number: 3))
        file.source = "b"
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "Before AI rewrite", kind: .aiApply)
        XCTAssertEqual(store.nextSaveNumber(for: file), 4)   // max save + 1; aiApply doesn't count
    }

    func testDisplayTitles() {
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "v03", source: "", params: ParamSnapshot(params: [:]), kind: .save(number: 3)).displayTitle, "v03")
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "x", source: "", params: ParamSnapshot(params: [:]), kind: .pin(name: "warm")).displayTitle, "warm")
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "x", source: "", params: ParamSnapshot(params: [:]), kind: .pin(name: nil)).displayTitle, "Pinned")
        XCTAssertEqual(Snapshot(id: "s", date: Date(), label: "Before restore", source: "", params: ParamSnapshot(params: [:]), kind: .safety).displayTitle, "Before restore")
    }

    func testCaptureBumpsRevisionOnlyOnWrite() {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "a", suggestedName: "R.fs")
        let r0 = store.revision
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v01", kind: .save(number: 1))
        XCTAssertEqual(store.revision, r0 + 1)
        store.capture(file: file, params: ParamSnapshot(params: [:]), label: "v02", kind: .save(number: 2))
        XCTAssertEqual(store.revision, r0 + 1, "identical-source dedup must not bump revision")
    }
}
