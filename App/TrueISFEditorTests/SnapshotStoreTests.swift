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

    private func directory(for file: TrueISFEditor.ISFFile) -> URL {
        root.appendingPathComponent(SnapshotStore.documentKey(for: file))
    }

    private func rawSnapshotData(date: Double, label: String, source: String,
                                 kind: String? = nil, number: Int? = nil,
                                 name: String? = nil, futureMarker: String? = nil) throws -> Data {
        var object: [String: Any] = [
            "date": date,
            "label": label,
            "source": source,
            "params": ["params": [String: Any]()]
        ]
        object["kind"] = kind
        object["number"] = number
        object["name"] = name
        if let futureMarker {
            object["futureMetadata"] = ["marker": futureMarker]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func writeRawSnapshot(_ data: Data, named name: String,
                                  for file: TrueISFEditor.ISFFile) throws {
        let dir = directory(for: file)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
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

    func testSameSourceEventKindsCaptureWhileSaveAndLegacyDedupe() {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "same", suggestedName: "Events.fs")
        let params = ParamSnapshot(params: [:])

        XCTAssertNotNil(store.capture(file: file, params: params, label: "v01", kind: .save(number: 1)))
        XCTAssertNil(store.capture(file: file, params: params, label: "v02", kind: .save(number: 2)))
        XCTAssertNotNil(store.capture(file: file, params: params, label: "Before AI rewrite", kind: .aiApply))
        XCTAssertNotNil(store.capture(file: file, params: params, label: "good strobe feel",
                                      kind: .pin(name: "good strobe feel")))
        XCTAssertNotNil(store.capture(file: file, params: params, label: "Before restore", kind: .safety))
        XCTAssertNil(store.capture(file: file, params: params, label: "Legacy default"))

        XCTAssertEqual(store.snapshots(for: file).map(\.kind),
                       [.safety, .pin(name: "good strobe feel"), .aiApply, .save(number: 1)])

        let legacyFile = TrueISFEditor.ISFFile.untitled(source: "legacy", suggestedName: "Legacy.fs")
        XCTAssertNotNil(store.capture(file: legacyFile, params: params, label: "Opened"))
        XCTAssertNil(store.capture(file: legacyFile, params: params, label: "Opened again"))
    }

    func testSaveDedupesAgainstNewestSaveRatherThanNewestEvent() {
        let store = SnapshotStore(rootURL: root)
        var file = TrueISFEditor.ISFFile.untitled(source: "A", suggestedName: "Pinned-edit.fs")
        let params = ParamSnapshot(params: [:])

        XCTAssertNotNil(store.capture(file: file, params: params,
                                      label: "v01", kind: .save(number: 1)))
        file.source = "B"
        XCTAssertNotNil(store.capture(file: file, params: params,
                                      label: "B pin", kind: .pin(name: "B pin")))
        XCTAssertNotNil(store.capture(file: file, params: params,
                                      label: "v02", kind: .save(number: 2)),
                        "a same-source pin must not suppress a save of edits since the last save")

        let saves = store.snapshots(for: file).filter {
            if case .save = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(saves.map(\.kind), [.save(number: 2), .save(number: 1)])
        XCTAssertEqual(saves.map(\.source), ["B", "A"])
        XCTAssertEqual(store.nextSaveNumber(for: file), 3)
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

    func testSameNamedUntitledDocumentsUseDistinctStableKeys() {
        let first = TrueISFEditor.ISFFile.untitled(source: "first", suggestedName: "Remixed shader")
        let second = TrueISFEditor.ISFFile.untitled(source: "second", suggestedName: "Remixed shader")
        var editedFirst = first
        editedFirst.source = "first edited"

        XCTAssertNotEqual(first.documentID, second.documentID)
        XCTAssertEqual(first.documentID, editedFirst.documentID,
                       "value-semantic edits must retain the document identity")
        XCTAssertNotEqual(SnapshotStore.documentKey(for: first),
                          SnapshotStore.documentKey(for: second))
        XCTAssertEqual(SnapshotStore.documentKey(for: first),
                       SnapshotStore.documentKey(for: editedFirst))
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
        let snaps = store.snapshots(for: f3)   // same document key (same document identity)
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

    func testUnknownKindDecodesAsLegacy() throws {
        let store = SnapshotStore(rootURL: root)
        let file = TrueISFEditor.ISFFile.untitled(source: "a", suggestedName: "Future.fs")
        let dir = root.appendingPathComponent(SnapshotStore.documentKey(for: file))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"date":100.5,"label":"Future capture","source":"a","params":{"params":{}},"kind":"futureKind","number":99,"name":"ignored"}"#
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("20260101-000000-000.json"))

        let snaps = store.snapshots(for: file)

        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].kind, .legacy)
        XCTAssertEqual(snaps[0].displayTitle, "Future capture")
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

    func testMigrateHistoryPreservesRawMetadataAndKindsThenRetiresOldKey() throws {
        let store = SnapshotStore(rootURL: root)
        let sourceFile = TrueISFEditor.ISFFile.untitled(source: "pin", suggestedName: "Raw.fs")
        let saveData = try rawSnapshotData(date: 100, label: "v07", source: "save",
                                           kind: "save", number: 7,
                                           futureMarker: "preserve-me")
        let pinData = try rawSnapshotData(date: 200, label: "favorite", source: "pin",
                                          kind: "pin", name: "favorite")
        try writeRawSnapshot(saveData, named: "save.json", for: sourceFile)
        try writeRawSnapshot(pinData, named: "pin.json", for: sourceFile)

        var destinationFile = sourceFile
        try destinationFile.save(to: root.appendingPathComponent("Raw-saved.fs"))
        let revisionBeforeMigration = store.revision

        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: destinationFile))

        let destinationDirectory = directory(for: destinationFile)
        XCTAssertEqual(try Data(contentsOf: destinationDirectory.appendingPathComponent("save.json")),
                       saveData, "migration must preserve unknown metadata byte-for-byte")
        XCTAssertEqual(try Data(contentsOf: destinationDirectory.appendingPathComponent("pin.json")),
                       pinData)
        XCTAssertEqual(store.snapshots(for: destinationFile).map(\.kind),
                       [.pin(name: "favorite"), .save(number: 7)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory(for: sourceFile).path),
                       "the old document key must retire after every entry is safely present")
        XCTAssertEqual(store.revision, revisionBeforeMigration + 1)

        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: destinationFile))
        XCTAssertEqual(store.revision, revisionBeforeMigration + 1,
                       "retrying an already-complete migration is not a material change")
    }

    func testMigrateHistoryMergesCollisionDedupesAndPrunesOldestToCap() throws {
        let store = SnapshotStore(rootURL: root, cap: 3)
        let sourceFile = TrueISFEditor.ISFFile.untitled(source: "source", suggestedName: "Merge.fs")
        var destinationFile = sourceFile
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try destinationFile.save(to: root.appendingPathComponent("Merge-saved.fs"))

        let destinationOldest = try rawSnapshotData(date: 100, label: "oldest", source: "d100")
        let sourceOld = try rawSnapshotData(date: 200, label: "source old", source: "s200")
        let destinationCollision = try rawSnapshotData(date: 300, label: "destination collision",
                                                       source: "d300", kind: "save", number: 3)
        let sourceCollision = try rawSnapshotData(date: 400, label: "source collision",
                                                  source: "s400", kind: "pin", name: "keep")
        let destinationNewest = try rawSnapshotData(date: 500, label: "newest", source: "d500",
                                                    kind: "save", number: 5)

        try writeRawSnapshot(destinationOldest, named: "destination-oldest.json", for: destinationFile)
        try writeRawSnapshot(destinationCollision, named: "collision.json", for: destinationFile)
        try writeRawSnapshot(destinationNewest, named: "destination-newest.json", for: destinationFile)
        try writeRawSnapshot(sourceOld, named: "source-old.json", for: sourceFile)
        try writeRawSnapshot(sourceCollision, named: "collision.json", for: sourceFile)
        try writeRawSnapshot(destinationNewest, named: "duplicate-newest.json", for: sourceFile)

        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: destinationFile))

        let destinationDirectory = directory(for: destinationFile)
        XCTAssertEqual(try Data(contentsOf: destinationDirectory.appendingPathComponent("collision.json")),
                       destinationCollision, "a name collision must never overwrite destination data")
        let listed = store.snapshots(for: destinationFile)
        XCTAssertEqual(listed.map(\.source), ["d500", "s400", "d300"],
                       "identical entries dedupe and the oldest unique entries prune to the cap")
        XCTAssertEqual(listed.filter { $0.source == "d500" }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory(for: sourceFile).path))
        XCTAssertEqual(store.revision, 1)
    }

    func testMigrateHistoryNoOpsDoNotBumpRevision() throws {
        let store = SnapshotStore(rootURL: root)
        let sourceFile = TrueISFEditor.ISFFile.untitled(source: "source", suggestedName: "No-op.fs")

        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: sourceFile))
        XCTAssertEqual(store.revision, 0, "the same document key needs no migration")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var destinationFile = sourceFile
        try destinationFile.save(to: root.appendingPathComponent("No-op-saved.fs"))
        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: destinationFile))
        XCTAssertEqual(store.revision, 0, "an absent source history is not a material change")
    }

    func testMigrateHistoryRenumbersIncomingSaveCollisionsIntoLinearTimeline() throws {
        let store = SnapshotStore(rootURL: root)
        let sourceFile = TrueISFEditor.ISFFile.untitled(source: "source-v2",
                                                       suggestedName: "Source.fs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var destinationFile = TrueISFEditor.ISFFile.untitled(source: "destination-v2",
                                                             suggestedName: "Destination.fs")
        try destinationFile.save(to: root.appendingPathComponent("Destination.fs"))

        let destinationV1 = try rawSnapshotData(date: 50, label: "v01",
                                                source: "destination-v1", kind: "save", number: 1)
        let destinationV2 = try rawSnapshotData(date: 60, label: "v02",
                                                source: "destination-v2", kind: "save", number: 2)
        let sourceV1 = try rawSnapshotData(date: 100, label: "v01",
                                           source: "source-v1", kind: "save", number: 1)
        let sourcePin = try rawSnapshotData(date: 150, label: "source pin",
                                            source: "source-v1", kind: "pin", name: "source pin",
                                            futureMarker: "keep-raw")
        let sourceV2 = try rawSnapshotData(date: 200, label: "v02",
                                           source: "source-v2", kind: "save", number: 2)
        try writeRawSnapshot(destinationV1, named: "destination-v1.json", for: destinationFile)
        try writeRawSnapshot(destinationV2, named: "destination-v2.json", for: destinationFile)
        try writeRawSnapshot(sourceV1, named: "source-v1.json", for: sourceFile)
        try writeRawSnapshot(sourcePin, named: "source-pin.json", for: sourceFile)
        try writeRawSnapshot(sourceV2, named: "source-v2.json", for: sourceFile)

        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: destinationFile))

        let savesBySource = Dictionary(uniqueKeysWithValues: store.snapshots(for: destinationFile)
            .compactMap { snapshot -> (String, Int)? in
                if case .save(let number) = snapshot.kind {
                    return (snapshot.source, number)
                }
                return nil
            })
        XCTAssertEqual(savesBySource, [
            "destination-v1": 1,
            "destination-v2": 2,
            "source-v1": 3,
            "source-v2": 4
        ], "destination numbers win; incoming collisions append oldest-first above the merged max")
        XCTAssertEqual(Set(savesBySource.values).count, savesBySource.count)
        XCTAssertEqual(store.nextSaveNumber(for: destinationFile), 5)
        let destinationDirectory = directory(for: destinationFile)
        XCTAssertEqual(try Data(contentsOf: destinationDirectory
            .appendingPathComponent("destination-v1.json")), destinationV1)
        XCTAssertEqual(try Data(contentsOf: destinationDirectory
            .appendingPathComponent("destination-v2.json")), destinationV2)
        XCTAssertEqual(try Data(contentsOf: destinationDirectory
            .appendingPathComponent("source-pin.json")), sourcePin,
                       "entries that do not need renumbering remain byte-for-byte unchanged")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory(for: sourceFile).path))
    }

    func testMigrateHistoryReportsFailureAndKeepsSourceWhenDestinationIsBlocked() throws {
        let store = SnapshotStore(rootURL: root)
        let sourceFile = TrueISFEditor.ISFFile.untitled(source: "source",
                                                       suggestedName: "Blocked-source.fs")
        XCTAssertNotNil(store.capture(file: sourceFile, params: ParamSnapshot(params: [:]),
                                      label: "keep", kind: .pin(name: "keep")))
        var destinationFile = sourceFile
        try destinationFile.save(to: root.appendingPathComponent("Blocked-destination.fs"))
        try Data("not a directory".utf8).write(to: directory(for: destinationFile))

        XCTAssertFalse(store.migrateHistory(from: sourceFile, to: destinationFile))

        XCTAssertEqual(store.snapshots(for: sourceFile).count, 1)
        XCTAssertEqual(store.revision, 1, "the failed migration itself made no material change")
    }

    func testInterruptedRenumberMigrationRetriesWithoutDuplicateOrNumberDrift() throws {
        let store = SnapshotStore(rootURL: root)
        let sourceFile = TrueISFEditor.ISFFile.untitled(source: "source-v1",
                                                       suggestedName: "Retry-source.fs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var destinationFile = TrueISFEditor.ISFFile.untitled(source: "destination-v1",
                                                             suggestedName: "Retry-destination.fs")
        try destinationFile.save(to: root.appendingPathComponent("Retry-destination.fs"))
        let destinationV1 = try rawSnapshotData(date: 50, label: "v01",
                                                source: "destination-v1", kind: "save", number: 1)
        let sourceV1 = try rawSnapshotData(date: 100, label: "v01",
                                           source: "source-v1", kind: "save", number: 1)
        try writeRawSnapshot(destinationV1, named: "destination-v1.json", for: destinationFile)
        try writeRawSnapshot(sourceV1, named: "source-v1.json", for: sourceFile)
        let retryMarker = directory(for: sourceFile).appendingPathComponent("keep-for-retry.tmp")
        try Data("unknown sidecar".utf8).write(to: retryMarker)

        XCTAssertFalse(store.migrateHistory(from: sourceFile, to: destinationFile))
        XCTAssertEqual(store.snapshots(for: destinationFile).compactMap { snapshot -> Int? in
            if case .save(let number) = snapshot.kind { return number }
            return nil
        }.sorted(), [1, 2])

        try FileManager.default.removeItem(at: retryMarker)
        XCTAssertTrue(store.migrateHistory(from: sourceFile, to: destinationFile))

        let saves = store.snapshots(for: destinationFile).filter {
            if case .save = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(saves.count, 2)
        XCTAssertEqual(saves.compactMap { snapshot -> Int? in
            if case .save(let number) = snapshot.kind { return number }
            return nil
        }.sorted(), [1, 2])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory(for: sourceFile).path))
    }
}
