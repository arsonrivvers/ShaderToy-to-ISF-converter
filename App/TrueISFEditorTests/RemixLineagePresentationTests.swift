import XCTest
@testable import TrueISFEditor

final class RemixLineagePresentationTests: XCTestCase {
    func test_salvageButtonIdentity_isStableAndSemantic() {
        let first = RemixSalvageButton(title: "Retry Preview") {}
        let second = RemixSalvageButton(title: "Retry Preview") {}

        XCTAssertEqual(first.id, "Retry Preview")
        XCTAssertEqual(second.id, first.id)
    }

    func test_focusedCanvasActions_explainWhyUnavailableWithoutFocus() {
        let unavailable = RemixCanvasFocusedActionAvailability(
            focusedChildID: nil,
            retainedReadyArtifactID: nil
        )
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertEqual(
            unavailable.reason,
            "Focus a child card to use focused child actions."
        )

        let nonReady = RemixCanvasFocusedActionAvailability(
            focusedChildID: "child-1",
            retainedReadyArtifactID: nil
        )
        XCTAssertFalse(nonReady.isEnabled)
        XCTAssertEqual(
            nonReady.reason,
            "Wait for the focused child to become Ready before using focused child actions."
        )

        let available = RemixCanvasFocusedActionAvailability(
            focusedChildID: "child-1",
            retainedReadyArtifactID: "artifact-1"
        )
        XCTAssertTrue(available.isEnabled)
        XCTAssertNil(available.reason)
    }

    func test_accessibilityAnnouncementSafelySkipsMissingApplication() {
        XCTAssertFalse(
            RemixAccessibilityAnnouncement.post(
                "Generation completed.",
                application: nil
            )
        )
    }

    func test_emptyCanvasInstruction_canGrowVerticallyAtNarrowWidths() {
        XCTAssertNil(RemixCanvasEmptyStatePolicy.instructionLineLimit)
        XCTAssertTrue(RemixCanvasEmptyStatePolicy.usesFixedVerticalSize)
        XCTAssertTrue(RemixCanvasEmptyStatePolicy.fillsAvailableHeight)
        XCTAssertEqual(RemixCanvasEmptyStatePolicy.horizontalPadding, 16)
    }

    private func node(
        id: String,
        parents: [String] = [],
        status: RemixNode.Status = .compiled,
        label: String? = nil
    ) -> RemixNode {
        RemixNode(
            id: id,
            isfSource: "/*{}*/",
            parents: parents,
            mode: .crossover,
            steer: "",
            directive: "blend structure",
            round: parents.isEmpty ? 0 : 1,
            status: status,
            label: label
        )
    }

    func test_rootRowSummaryNamesDepthCompileStateAndActions() {
        var lineage = RemixLineage()
        let root = node(id: "seed-0", label: "Plasma")
        lineage.insert(root)

        let row = RemixLineagePresentation.row(
            RemixTreeRow(id: root.id, depth: 0, secondaryParentID: nil),
            node: root,
            lineage: lineage,
            selected: false,
            collapsed: false,
            hasChildren: true
        )

        XCTAssertEqual(row.label, "Plasma")
        XCTAssertEqual(
            row.value,
            "Depth 1. Not favorite. Root shader. Compiled. Expanded."
        )
        XCTAssertEqual(
            row.help,
            "Select Plasma. Available actions: Collapse descendants, Open in Editor, Promote to Parent A, Promote to Parent B, Favorite."
        )
        XCTAssertEqual(
            row.actions,
            [
                "Collapse descendants",
                "Open in Editor",
                "Promote to Parent A",
                "Promote to Parent B",
                "Favorite",
            ]
        )
    }

    func test_nestedCrossoverFavoriteSelectedCollapsedSummaryNamesBothParents() {
        var lineage = RemixLineage()
        let primary = node(id: "seed-0", label: "Primary")
        let secondary = node(id: "seed-1", label: "Secondary")
        let child = node(id: "r1-0", parents: [primary.id, secondary.id], label: "Aurora")
        lineage.insert(primary)
        lineage.insert(secondary)
        lineage.insert(child)
        lineage.toggleFavorite(child.id)

        let row = RemixLineagePresentation.row(
            RemixTreeRow(id: child.id, depth: 1, secondaryParentID: secondary.id),
            node: child,
            lineage: lineage,
            selected: true,
            collapsed: true,
            hasChildren: true
        )

        XCTAssertEqual(row.label, "Aurora, selected")
        XCTAssertEqual(
            row.value,
            "Depth 2. Favorite. Primary parent Primary. Secondary parent Secondary. Compiled. Collapsed."
        )
        XCTAssertEqual(row.actions.first, "Expand descendants")
        XCTAssertTrue(row.actions.contains("Select Primary Parent"))
        XCTAssertTrue(row.actions.contains("Select Secondary Parent"))
        XCTAssertTrue(row.actions.contains("Remove Favorite"))
    }

    func test_failedRowSummaryNamesFailureAndSalvageActions() {
        var lineage = RemixLineage()
        let failed = node(
            id: "r2-0",
            parents: ["seed-0"],
            status: .failed("line 4: invalid token"),
            label: "Broken Child"
        )
        lineage.insert(node(id: "seed-0", label: "Parent"))
        lineage.insert(failed)

        let row = RemixLineagePresentation.row(
            RemixTreeRow(id: failed.id, depth: 1, secondaryParentID: nil),
            node: failed,
            lineage: lineage,
            selected: false,
            collapsed: false,
            hasChildren: false
        )

        XCTAssertEqual(
            row.value,
            "Depth 2. Not favorite. Primary parent Parent. Compile failed: line 4: invalid token."
        )
        XCTAssertEqual(
            row.actions,
            [
                "View Compile Summary",
                "Copy Diagnostic",
                "Open Source in Editor to Fix",
                "Retry This Child",
            ]
        )
    }

    func test_activityActionsCoverEveryActivityStateAndFailureSurface() {
        let requestID = UUID()
        let cases: [(RemixActivityState, [String])] = [
            (.idle, ["Copy Activity"]),
            (
                .generating(total: 5, completed: 2, lastEventAt: nil),
                ["Stop", "Copy Activity"]
            ),
            (
                .quiet(total: 5, completed: 2, lastEventAt: nil),
                ["Stop", "Copy Activity"]
            ),
            (
                .verificationRequired(slot: .b, requestID: requestID),
                ["Copy Activity"]
            ),
            (.resuming(slot: .b, requestID: requestID), ["Copy Activity"]),
            (
                .childFailed(id: "r1-0", message: "Compile failed"),
                ["Retry All Failed", "Copy Activity"]
            ),
            (
                .partialFailure(total: 5, failed: 2),
                ["Retry All Failed", "Copy Activity"]
            ),
            (.interrupted, ["Retry Interrupted Batch", "Copy Activity"]),
            (.completed(failed: 0), ["Copy Activity"]),
            (
                .completed(failed: 2),
                ["Retry All Failed", "Copy Activity"]
            ),
            (.cancelled, ["Retry All Failed", "Copy Activity"]),
        ]

        for (state, expected) in cases {
            XCTAssertEqual(
                RemixLineagePresentation.activityActions(for: state),
                expected,
                "\(state)"
            )
            XCTAssertEqual(
                RemixLineagePresentation.compactActivityStatus(for: state),
                state.summary.compactStatus
            )
        }
    }

    func test_activityFailureRowsExposeScopedCompileActions() {
        let rows = RemixLineagePresentation.failureRows(
            nodes: [
                node(id: "r1-0", status: .failed("provider stopped")),
                node(id: "r1-1", status: .failed("line 8: bad token")),
            ],
            compileDiagnosticsByNodeID: ["r1-1": "line 8: bad token"]
        )

        XCTAssertEqual(rows[0].actions, ["Retry This Child"])
        XCTAssertEqual(
            rows[1].actions,
            [
                "View Compile Summary",
                "Copy Diagnostic",
                "Open Source in Editor to Fix",
                "Retry This Child",
            ]
        )
    }

    func test_activityAnnouncementPolicySkipsProgressChatterButNamesSignificantTransitions() {
        let started = RemixActivityState.generating(
            total: 5,
            completed: 0,
            lastEventAt: nil
        )
        let progressed = RemixActivityState.generating(
            total: 5,
            completed: 1,
            lastEventAt: Date()
        )

        XCTAssertEqual(
            RemixLineagePresentation.announcement(from: .idle, to: started),
            started.summary.accessibilityAnnouncement
        )
        XCTAssertNil(
            RemixLineagePresentation.announcement(from: started, to: progressed)
        )
        XCTAssertEqual(
            RemixLineagePresentation.announcement(
                from: progressed,
                to: .childFailed(id: "r1-0", message: "Compile failed")
            ),
            "r1-0 failed. Compile failed"
        )
        XCTAssertNil(
            RemixLineagePresentation.announcement(from: .idle, to: .idle)
        )
    }

    func test_selectedNodeActionNamesComeFromPresentationForBothFavoriteStates() {
        XCTAssertEqual(
            RemixLineagePresentation.selectedNodeActions(favorite: false),
            [
                .promoteA,
                .promoteB,
                .favorite,
                .open,
                .deselect,
            ]
        )
        XCTAssertEqual(
            RemixLineagePresentation.selectedNodeActions(favorite: true),
            [
                .promoteA,
                .promoteB,
                .removeFavorite,
                .open,
                .deselect,
            ]
        )
    }

    func test_keyboardRouteMovesVisibleRowFocusAndActivatesFocusedSelection() {
        let visible = ["seed-0", "r1-0", "r1-1"]

        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 125,
                focusedID: "seed-0",
                visibleIDs: visible
            ),
            .focus("r1-0")
        )
        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 126,
                focusedID: "r1-0",
                visibleIDs: visible
            ),
            .focus("seed-0")
        )
        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 36,
                focusedID: "r1-0",
                visibleIDs: visible
            ),
            .select("r1-0")
        )
        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 49,
                focusedID: "r1-0",
                visibleIDs: visible
            ),
            .select("r1-0")
        )
    }

    func test_keyboardRouteInitializesFocusAndIgnoresModifiedOrUnknownKeys() {
        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 125,
                focusedID: nil,
                visibleIDs: ["seed-0"]
            ),
            .focus("seed-0")
        )
        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 125,
                modifiersPresent: true,
                focusedID: "seed-0",
                visibleIDs: ["seed-0"]
            ),
            .ignore
        )
        XCTAssertEqual(
            RemixLineageKeyboardRoute.route(
                keyCode: 0,
                focusedID: "seed-0",
                visibleIDs: ["seed-0"]
            ),
            .ignore
        )
    }
}
