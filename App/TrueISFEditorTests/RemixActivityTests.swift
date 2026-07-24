import XCTest
@testable import TrueISFEditor

final class RemixActivityTests: XCTestCase {
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
}
