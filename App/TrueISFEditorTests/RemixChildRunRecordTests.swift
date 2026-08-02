import XCTest
@testable import TrueISFEditor

final class RemixChildRunRecordTests: XCTestCase {
    func test_pipelineTransitionsAdvanceInOrderToReady() {
        var record = run(stage: .queued)
        let stages: [RemixChildRunRecord.Stage] = [
            .starting, .thinking, .receiving, .extracting, .compiling,
        ]

        for (offset, stage) in stages.enumerated() {
            XCTAssertTrue(record.transition(
                to: stage,
                at: Date(timeIntervalSince1970: TimeInterval(offset + 2))
            ))
            XCTAssertEqual(record.stage, stage)
        }
        XCTAssertTrue(record.finishReady(
            artifactID: "artifact-r3-1",
            at: Date(timeIntervalSince1970: 7)
        ))

        XCTAssertEqual(record.stage, .ready)
        XCTAssertEqual(record.artifactID, "artifact-r3-1")
        XCTAssertEqual(record.startedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(record.providerCompletedAt, Date(timeIntervalSince1970: 5))
        XCTAssertEqual(record.terminalAt, Date(timeIntervalSince1970: 7))
    }

    func test_providerRetryTransitionsResumeFromThinkingReceivingOrAuthoritativeResponse() {
        var thinking = run(stage: .thinking)
        thinking.recordAPIRetry(
            attempt: 1,
            message: "rate limit; retrying",
            at: Date(timeIntervalSince1970: 2)
        )
        XCTAssertEqual(thinking.stage, .retrying)
        XCTAssertTrue(thinking.transition(to: .thinking, at: Date(timeIntervalSince1970: 3)))

        var receiving = run(stage: .receiving)
        receiving.recordAPIRetry(
            attempt: 1,
            message: "connection reset; retrying",
            at: Date(timeIntervalSince1970: 2)
        )
        XCTAssertEqual(receiving.stage, .retrying)
        receiving.recordProviderActivity(bytes: 17, at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(receiving.stage, .receiving)
        XCTAssertEqual(receiving.receivedBytes, 17)

        receiving.recordAPIRetry(
            attempt: 2,
            message: "retrying once more",
            at: Date(timeIntervalSince1970: 4)
        )
        XCTAssertTrue(receiving.transition(to: .extracting, at: Date(timeIntervalSince1970: 5)))
        XCTAssertEqual(receiving.providerCompletedAt, Date(timeIntervalSince1970: 5))
    }

    func test_terminalRecordRejectsEveryMutationAndRemainsByteForByteEqual() {
        var record = run(stage: .compiling)
        XCTAssertTrue(record.finishReady(
            artifactID: "artifact-r3-1",
            at: Date(timeIntervalSince1970: 2)
        ))
        let terminal = record

        XCTAssertFalse(record.transition(to: .failed, at: Date(timeIntervalSince1970: 3)))
        record.recordProviderActivity(bytes: 10, at: Date(timeIntervalSince1970: 3))
        record.recordAPIRetry(
            attempt: 4,
            message: "must not persist",
            at: Date(timeIntervalSince1970: 3)
        )
        record.recordDiagnosticResponse("must not persist")
        XCTAssertFalse(record.fail(
            boundary: .compile,
            message: "must not persist",
            at: Date(timeIntervalSince1970: 3)
        ))
        XCTAssertFalse(record.finishReady(
            artifactID: "replacement",
            at: Date(timeIntervalSince1970: 3)
        ))

        XCTAssertEqual(record, terminal)
    }

    func test_diagnosticResponseTruncatesAtAValidUTF8Boundary() {
        var record = run(stage: .receiving)
        let oversized = String(repeating: "é", count: 140_000) + "tail"

        record.recordDiagnosticResponse(oversized)

        let stored = record.diagnosticResponse ?? ""
        XCTAssertLessThanOrEqual(stored.utf8.count, 262_144)
        XCTAssertTrue(oversized.hasPrefix(stored))
        XCTAssertFalse(stored.contains("\u{FFFD}"))
    }

    func test_apiRetriesCountEventsBoundNoticeAndRemainRetryingUntilProviderEvidence() {
        var record = run(stage: .thinking)
        let oversized = String(repeating: "💥", count: 70_000)

        record.recordAPIRetry(
            attempt: 1,
            message: "first retry",
            at: Date(timeIntervalSince1970: 2)
        )
        record.recordAPIRetry(
            attempt: 2,
            message: oversized,
            at: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(record.apiRetryCount, 2)
        XCTAssertEqual(record.stage, .retrying)
        XCTAssertLessThanOrEqual(record.lastProviderNotice?.utf8.count ?? .max, 262_144)
        XCTAssertTrue(oversized.hasPrefix(record.lastProviderNotice ?? ""))

        record.recordProviderActivity(bytes: 3, at: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(record.stage, .receiving)
        XCTAssertEqual(record.receivedBytes, 3)
    }

    private func run(stage: RemixChildRunRecord.Stage) -> RemixChildRunRecord {
        RemixChildRunRecord(
            id: "r3-1",
            round: 3,
            slot: 1,
            request: RemixGenerationRequestSnapshot(
                parentIDs: ["seed-0", "seed-1"],
                parentSources: ["source-a", "source-b"],
                mode: .crossover,
                steer: "liquid",
                directive: "combine",
                settings: RemixCrossoverSettings()
            ),
            stage: stage,
            queuedAt: Date(timeIntervalSince1970: 1),
            provider: .codex,
            model: "gpt-test",
            queuePosition: 1
        )
    }
}
