import XCTest
@testable import TrueISFEditor

final class RemixSessionStoreTests: XCTestCase {
    private var directory: URL!
    private var sessionURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-session-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        sessionURL = directory.appendingPathComponent("session.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_firstSave_atomicallyMovesTemporaryFileIntoPlace() throws {
        let store = RemixSessionStore(fileURL: sessionURL)
        let expected = session(round: 1)

        try store.save(expected)

        XCTAssertEqual(try decodedSession(at: sessionURL), expected)
        XCTAssertEqual(try siblingTemporaryFiles(), [])
    }

    func test_overwrite_atomicallyReplacesExistingFile() throws {
        let store = RemixSessionStore(fileURL: sessionURL)
        try store.save(session(round: 1))

        let replacement = session(round: 2)
        try store.save(replacement)

        XCTAssertEqual(try decodedSession(at: sessionURL), replacement)
        XCTAssertEqual(try siblingTemporaryFiles(), [])
    }

    func test_load_corruptPayload_quarantinesAndReturnsRecoveryNotice() throws {
        try Data("not-json".utf8).write(to: sessionURL)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let store = RemixSessionStore(fileURL: sessionURL, now: { date })

        let recovery = try store.load()

        guard case let .corruptPayload(quarantinedURL) = recovery else {
            return XCTFail("Expected corrupt-payload recovery, got \(recovery)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedURL.path))
        XCTAssertEqual(quarantinedURL.pathExtension, "corrupt")
        XCTAssertTrue(quarantinedURL.lastPathComponent.contains("20231114T221320Z"))
        XCTAssertEqual(try Data(contentsOf: quarantinedURL), Data("not-json".utf8))
    }

    func test_store_boundsBatchHistoryAndTranscript() throws {
        var unbounded = session(round: 25)
        unbounded.batchHistory = (1...25).map {
            RemixBatchRecord(round: $0, runs: [])
        }
        unbounded.transcript = (1...2_100).map { "line-\($0)" }
        let store = RemixSessionStore(fileURL: sessionURL)

        try store.save(unbounded)

        guard case let .session(restored) = try store.load() else {
            return XCTFail("Expected stored session")
        }
        XCTAssertEqual(restored.batchHistory.map(\.round), Array(6...25))
        XCTAssertEqual(restored.transcript.first, "line-101")
        XCTAssertEqual(restored.transcript.last, "line-2100")
        XCTAssertEqual(restored.transcript.count, 2_000)
        XCTAssertEqual(unbounded.batchHistory.count, 25)
        XCTAssertEqual(unbounded.transcript.count, 2_100)
    }

    func test_loadLiteralMidBatchSchemaV2DoesNotQuarantineOrNormalizeLiveEvidence() throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "remix-schema-v2-mid-batch",
            withExtension: "json"
        ))
        try Data(contentsOf: fixtureURL).write(to: sessionURL)
        let store = RemixSessionStore(fileURL: sessionURL)

        guard case let .session(restored) = try store.load() else {
            return XCTFail("Expected schema-v2 session")
        }

        XCTAssertEqual(restored.currentRuns.map(\.stage), [
            .queued, .starting, .thinking, .receiving, .retrying, .extracting, .compiling,
        ])
        XCTAssertEqual(restored.currentRuns[5].candidateSource, "extracting-candidate")
        XCTAssertEqual(restored.currentRuns[6].candidateSource, "compiling-candidate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).allSatisfy { $0.pathExtension != "corrupt" })
    }

    private func siblingTemporaryFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".tmp") }
    }

    private func decodedSession(at url: URL) throws -> RemixSession {
        try JSONDecoder().decode(RemixSession.self, from: Data(contentsOf: url))
    }

    private func session(round: Int) -> RemixSession {
        RemixSession(
            round: round,
            seedCounter: 2,
            parentAID: nil,
            parentBID: nil,
            parentHistory: [],
            mode: .crossover,
            steer: "",
            batchSize: 5,
            currentRuns: [],
            batchHistory: [],
            lineage: RemixLineage(),
            workspace: RemixWorkspaceState(),
            selectedLineageNodeID: nil,
            crossoverSettings: RemixCrossoverSettings(),
            activity: .idle,
            pendingParentRequest: nil,
            transcript: []
        )
    }
}
