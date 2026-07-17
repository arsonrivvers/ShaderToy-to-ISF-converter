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
}
