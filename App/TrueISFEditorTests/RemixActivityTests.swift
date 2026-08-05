import XCTest
@testable import TrueISFEditor

final class RemixActivityTests: XCTestCase {
    func test_runSummaryCountsStableStagesAndUsesOnlyTerminalFractionForProgress() {
        let request = request()
        let queuedAt = Date(timeIntervalSince1970: 10)
        let records = (0..<5).map { slot -> RemixChildRunRecord in
            RemixChildRunRecord(
                id: "r1-\(slot)",
                round: 1,
                slot: slot,
                request: request,
                stage: slot < 3 ? .queued : .receiving,
                queuedAt: queuedAt,
                startedAt: slot < 3 ? nil : Date(timeIntervalSince1970: Double(20 + slot)),
                lastEventAt: slot < 3 ? nil : Date(timeIntervalSince1970: Double(30 + slot))
            )
        }

        let summary = RemixRunSummary(records: records)

        XCTAssertEqual(summary.stageCounts[.queued], 3)
        XCTAssertEqual(summary.stageCounts[.receiving], 2)
        XCTAssertEqual(summary.terminalCount, 0)
        XCTAssertEqual(summary.totalCount, 5)
        XCTAssertEqual(summary.activeWorkerCount, 2)
        XCTAssertEqual(summary.queueCount, 3)
        XCTAssertEqual(summary.earliestStart, Date(timeIntervalSince1970: 23))
        XCTAssertEqual(summary.latestProviderActivity, Date(timeIntervalSince1970: 34))
        XCTAssertEqual(summary.terminalProgress, 0)
    }

    func test_runSummaryTerminalProgressIgnoresUnequalIntermediateStages() {
        let stages: [RemixChildRunRecord.Stage] = [.ready, .failed, .compiling, .receiving]
        let records = stages.enumerated().map { slot, stage in
            RemixChildRunRecord(
                id: "r2-\(slot)",
                round: 2,
                slot: slot,
                request: request(),
                stage: stage,
                queuedAt: Date(timeIntervalSince1970: 1),
                terminalAt: stage.isTerminal ? Date(timeIntervalSince1970: 2) : nil
            )
        }
        XCTAssertEqual(RemixRunSummary(records: records).terminalProgress, 0.5)
    }

    func test_runSummaryActionsDoNotOfferLegacyRetryOrFakeStopDuringLocalRecovery() {
        let recovering = RemixRunSummary(records: [record(stage: .compiling)])
        let recovered = RemixRunSummary(records: [record(stage: .ready)])

        XCTAssertEqual(
            RemixLineagePresentation.activityActions(for: recovering, canStop: false),
            []
        )
        XCTAssertEqual(
            RemixLineagePresentation.activityActions(for: recovering, canStop: true),
            ["Stop"]
        )
        XCTAssertEqual(
            RemixLineagePresentation.activityActions(for: recovered, canStop: false),
            []
        )
    }

    func test_runSummaryEmitsCompletionAnnouncementWhenRecoveryBecomesEntirelyReady() {
        let recovering = RemixRunSummary(records: [record(stage: .compiling)])
        let recovered = RemixRunSummary(records: [record(stage: .ready)])

        XCTAssertEqual(
            RemixLineagePresentation.announcement(from: recovering, to: recovered),
            "Generation complete. 1 child is ready."
        )
    }

    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let eventDate = Date(timeIntervalSince1970: 1_721_844_000)

    func test_generatingSummaryPinsCompactStatusAndAnnouncement() {
        let summary = RemixActivityState.generating(
            total: 5,
            completed: 2,
            lastEventAt: eventDate
        ).summary

        XCTAssertEqual(summary.compactStatus, "Generating 2 of 5")
        XCTAssertEqual(
            summary.accessibilityAnnouncement,
            "Generating batch. 2 of 5 children complete."
        )
    }

    func test_quietSummaryDoesNotClaimFailure() {
        let summary = RemixActivityState.quiet(
            total: 5,
            completed: 2,
            lastEventAt: eventDate
        ).summary

        XCTAssertEqual(summary.compactStatus, "Generating 2 of 5, quiet")
        XCTAssertEqual(
            summary.accessibilityAnnouncement,
            "Generating batch. 2 of 5 children complete. The provider is quiet but still working."
        )
    }

    func test_partialFailureSummaryPinsCounts() {
        let summary = RemixActivityState.partialFailure(total: 5, failed: 2).summary

        XCTAssertEqual(summary.compactStatus, "2 of 5 children failed")
        XCTAssertEqual(
            summary.accessibilityAnnouncement,
            "Batch finished with 2 of 5 children failed."
        )
    }

    func test_cancelledSummaryPinsTerminalLanguage() {
        let summary = RemixActivityState.cancelled.summary

        XCTAssertEqual(summary.compactStatus, "Generation cancelled")
        XCTAssertEqual(summary.accessibilityAnnouncement, "Generation cancelled.")
    }

    func test_verificationRequiredSummaryNamesParentSlot() {
        let summary = RemixActivityState.verificationRequired(
            slot: .a,
            requestID: requestID
        ).summary

        XCTAssertEqual(summary.compactStatus, "Verification required for Parent A")
        XCTAssertEqual(
            summary.accessibilityAnnouncement,
            "Verification required for Parent A. Complete the visible security check to continue."
        )
    }

    func test_resumingSummaryNamesParentSlot() {
        let summary = RemixActivityState.resuming(slot: .b, requestID: requestID).summary

        XCTAssertEqual(summary.compactStatus, "Resuming Parent B import")
        XCTAssertEqual(
            summary.accessibilityAnnouncement,
            "Verification cleared. Resuming the Parent B import."
        )
    }

    func test_interruptedSummaryOffersAccurateRecoveryState() {
        let summary = RemixActivityState.interrupted.summary

        XCTAssertEqual(summary.compactStatus, "Generation interrupted")
        XCTAssertEqual(
            summary.accessibilityAnnouncement,
            "Generation was interrupted. The original inputs are available to retry."
        )
    }

    func test_idleSummaryPinsReadyState() {
        let summary = RemixActivityState.idle.summary

        XCTAssertEqual(summary.compactStatus, "Ready")
        XCTAssertEqual(summary.accessibilityAnnouncement, "Remix Studio is ready.")
    }

    private func request() -> RemixGenerationRequestSnapshot {
        RemixGenerationRequestSnapshot(
            parentIDs: ["seed-0"],
            parentSources: ["parent"],
            mode: .mutate,
            steer: "",
            directive: "test",
            settings: RemixCrossoverSettings()
        )
    }

    private func record(stage: RemixChildRunRecord.Stage) -> RemixChildRunRecord {
        RemixChildRunRecord(
            id: "r1-0",
            round: 1,
            slot: 0,
            request: request(),
            stage: stage,
            queuedAt: Date(timeIntervalSince1970: 1),
            terminalAt: stage.isTerminal ? Date(timeIntervalSince1970: 2) : nil,
            artifactID: stage == .ready ? "r1-0" : nil
        )
    }
}
