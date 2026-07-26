import XCTest
@testable import TrueISFEditor

final class RemixBreedingBayPresentationTests: XCTestCase {
    func test_emptySession_leadsWithMakerGoalAndShortestPath() {
        let crossover = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: nil,
            parentBID: nil,
            parentLoadState: .idle
        )
        let mutate = RemixBreedingBayPresentation(
            mode: .mutate,
            parentAID: nil,
            parentBID: nil,
            parentLoadState: .idle
        )

        XCTAssertEqual(crossover.heading, "Choose a starting shader")
        XCTAssertEqual(crossover.shortestPath, "Add Parent A, then add Parent B.")
        XCTAssertEqual(mutate.shortestPath, "Add Parent A to begin.")
    }

    func test_parentActions_nameExactTargetAndWhetherTheyAddOrReplace() {
        let empty = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: nil,
            parentBID: "b",
            parentLoadState: .idle
        )

        XCTAssertEqual(empty.parentActionTitle(for: .a), "Add Parent A")
        XCTAssertEqual(empty.parentActionTitle(for: .b), "Replace Parent B")
        XCTAssertEqual(empty.sourceActionLabel(.library, slot: .a), "Add Parent A from Library")
        XCTAssertEqual(empty.sourceActionLabel(.shadertoy, slot: .b), "Replace Parent B from Shadertoy")
    }

    func test_generateDisabledReason_namesMissingParentAndResolvingAction() {
        let missingA = RemixBreedingBayPresentation(
            mode: .mutate,
            parentAID: nil,
            parentBID: nil,
            parentLoadState: .idle
        )
        let missingB = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: "a",
            parentBID: nil,
            parentLoadState: .idle
        )

        XCTAssertEqual(missingA.generateDisabledReason, "Generate unavailable: Parent A is missing.")
        XCTAssertEqual(missingA.generateResolvingAction, "Use Add Parent A.")
        XCTAssertEqual(missingB.generateDisabledReason, "Generate unavailable: Parent B is missing.")
        XCTAssertEqual(missingB.generateResolvingAction, "Use Add Parent B.")
    }

    func test_parentLoadCopy_preservesSlotAndHumanVerificationLanguage() {
        let request = RemixParentRequest(
            slot: .b,
            spec: .shadertoyLink("https://www.shadertoy.com/view/abc123"),
            displayInput: "https://www.shadertoy.com/view/abc123"
        )
        let presentation = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: "a",
            parentBID: nil,
            parentLoadState: .verificationRequired(request)
        )

        XCTAssertEqual(presentation.parentLoadStatus, "Verification required for Parent B.")
        XCTAssertEqual(
            presentation.parentLoadInstruction,
            "Complete the visible security check, then choose Continue Verification."
        )
    }

    func test_collapseReopenAndPopoverReturn_haveStableFocusTokens() {
        XCTAssertEqual(
            RemixBreedingBayPresentation.focusAfterCollapsing(.breedingBay),
            .reopenZone(.breedingBay)
        )
        XCTAssertEqual(
            RemixBreedingBayPresentation.focusAfterExpanding(.lineage),
            .collapseZone(.lineage)
        )
        XCTAssertEqual(RemixBreedingBayPresentation.crossoverPopoverReturnFocus, .crossoverSettings)
    }

    func test_resizeDescriptionAndResetLayout_areExactAndBounded() {
        var state = RemixWorkspaceState()
        state.resize(.breedingBay, to: 317)
        state.resize(.lineage, to: 401)
        state.collapse(.lineage)

        XCTAssertEqual(
            RemixBreedingBayPresentation.resizeValueDescription(zone: .breedingBay, width: 317),
            "Breeding Bay width, 317 points"
        )

        RemixBreedingBayPresentation.resetLayout(&state)

        XCTAssertEqual(state.zoneWidths[.breedingBay], 280)
        XCTAssertEqual(state.zoneWidths[.lineage], 300)
        XCTAssertTrue(state.collapsedZones.isEmpty)
    }

    func test_failedAndCancelledImport_offerExactSlotRecoveryActions() {
        let request = RemixParentRequest(
            slot: .b,
            spec: .shadertoyLink("abc123"),
            displayInput: "abc123"
        )
        let failed = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: "a",
            parentBID: nil,
            parentLoadState: .failed(request, message: "Timed out")
        )
        let cancelled = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: "a",
            parentBID: nil,
            parentLoadState: .cancelled(request)
        )

        XCTAssertEqual(
            failed.recoveryActions,
            [
                RemixParentRecoveryAction(title: "Retry Fetch for Parent B", kind: .retryFetch),
                RemixParentRecoveryAction(title: "Use API Key for Parent B", kind: .useAPIKey),
                RemixParentRecoveryAction(title: "Paste ISF for Parent B", kind: .paste),
            ]
        )
        XCTAssertEqual(cancelled.recoveryActions, failed.recoveryActions)
        XCTAssertEqual(failed.retryRequest, request)
    }

    func test_actionableLibraryAndEditorLabels_includeIntentSlotAndIdentity() {
        let presentation = RemixBreedingBayPresentation(
            mode: .crossover,
            parentAID: nil,
            parentBID: "b",
            parentLoadState: .idle
        )

        XCTAssertEqual(
            presentation.actionableSourceLabel(.library, slot: .a, identity: "Aurora"),
            "Add Parent A from Library: Aurora"
        )
        XCTAssertEqual(
            presentation.actionableSourceLabel(.currentEditor, slot: .b, identity: "Nebula.fs"),
            "Replace Parent B from Current Editor: Nebula.fs"
        )
    }

    func test_textLayoutPolicy_usesRelativeStylesAndAllowsCriticalTextToGrow() {
        XCTAssertTrue(RemixAccessibleTextLayout.usesRelativeStyles)
        XCTAssertEqual(RemixAccessibleTextLayout.basePointSize, 14)
        XCTAssertNil(RemixAccessibleTextLayout.criticalTextLineLimit)
        XCTAssertEqual(
            RemixAccessibleTextLayout.minimumControlHeight(base: 44, textScale: 2),
            88
        )
    }

    func test_actionContainerFontPolicy_coversEveryVisibleActionZone() {
        XCTAssertEqual(RemixTextPolicy.basePointSize, 14)
        XCTAssertTrue(RemixTextPolicy.usesRelativeScaling)
        XCTAssertEqual(
            RemixTextPolicy.actionContainers,
            [
                .breedingBay,
                .workspaceToolbar,
                .reopenControls,
                .resizeMenus,
                .lineageInspector,
                .activityDrawer,
            ]
        )
        XCTAssertNil(RemixTextPolicy.criticalTextLineLimit)
        XCTAssertTrue(RemixTextPolicy.allowsFlexibleVerticalGrowth)
    }

    func test_recoveryActions_areScopedToSourceForFailedAndCancelledRequests() {
        struct Fixture {
            let spec: ParentSpec
            let expected: [RemixParentRecoveryAction]
            let failedInstruction: String
        }
        let fixtures = [
            Fixture(
                spec: .shadertoyLink("abc123"),
                expected: [
                    RemixParentRecoveryAction(title: "Retry Fetch for Parent B", kind: .retryFetch),
                    RemixParentRecoveryAction(title: "Use API Key for Parent B", kind: .useAPIKey),
                    RemixParentRecoveryAction(title: "Paste ISF for Parent B", kind: .paste),
                ],
                failedInstruction: "Retry Fetch, use an API key, or paste ISF code."
            ),
            Fixture(
                spec: .currentEditor,
                expected: [
                    RemixParentRecoveryAction(
                        title: "Retry Current Editor for Parent B",
                        kind: .retryCurrentEditor
                    ),
                    RemixParentRecoveryAction(title: "Paste ISF for Parent B", kind: .paste),
                ],
                failedInstruction: "Retry Current Editor or paste ISF code."
            ),
            Fixture(
                spec: .libraryFile(URL(fileURLWithPath: "/tmp/Aurora.fs")),
                expected: [
                    RemixParentRecoveryAction(
                        title: "Choose Another Library Shader for Parent B",
                        kind: .chooseLibrary
                    ),
                    RemixParentRecoveryAction(title: "Paste ISF for Parent B", kind: .paste),
                ],
                failedInstruction: "Choose another Library shader or paste ISF code."
            ),
            Fixture(
                spec: .pastedISF("bad source"),
                expected: [
                    RemixParentRecoveryAction(
                        title: "Correct Pasted ISF for Parent B",
                        kind: .paste
                    ),
                ],
                failedInstruction: "Correct the pasted ISF code."
            ),
        ]

        for fixture in fixtures {
            let request = RemixParentRequest(
                slot: .b,
                spec: fixture.spec,
                displayInput: "retained input"
            )
            for state in [
                RemixParentLoadState.failed(request, message: "failed"),
                RemixParentLoadState.cancelled(request),
            ] {
                let presentation = RemixBreedingBayPresentation(
                    mode: .crossover,
                    parentAID: "a",
                    parentBID: nil,
                    parentLoadState: state
                )
                XCTAssertEqual(presentation.recoveryActions, fixture.expected)
                XCTAssertFalse(
                    presentation.recoveryActions.contains {
                        $0.kind == .useAPIKey && fixture.spec != .shadertoyLink("abc123")
                    }
                )
                if case .failed = state {
                    XCTAssertEqual(presentation.parentLoadInstruction, fixture.failedInstruction)
                } else {
                    XCTAssertNil(presentation.parentLoadInstruction)
                }
            }
        }
    }
}
