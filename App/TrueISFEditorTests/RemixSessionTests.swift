import XCTest
@testable import TrueISFEditor

final class RemixSessionTests: XCTestCase {
    func test_roundTrip_restoresLineageParentsFavoritesAndWorkspace() throws {
        var lineage = RemixLineage()
        lineage.insert(node(id: "seed-0", status: .compiled))
        lineage.insert(node(id: "r1-0", parents: ["seed-0"], round: 1, status: .failed("compile")))
        lineage.toggleFavorite("r1-0")

        var workspace = RemixWorkspaceState()
        workspace.showHero("r1-0")
        workspace.collapse(.lineage)

        let restored = try roundTrip(session(lineage: lineage, workspace: workspace))

        XCTAssertEqual(restored.lineage, lineage)
        XCTAssertEqual(restored.parentAID, "seed-0")
        XCTAssertEqual(restored.parentBID, "r1-0")
        XCTAssertTrue(restored.lineage.isFavorite("r1-0"))
        XCTAssertEqual(restored.workspace, workspace)
    }

    func test_roundTrip_restoresCountersParentHistorySelectionSettingsActivityAndRequest() throws {
        let requestID = UUID()
        let request = RemixParentRequestSnapshot(
            id: requestID,
            slot: .b,
            source: .shadertoyLink("https://www.shadertoy.com/view/abc123"),
            displayInput: "abc123",
            phase: .waitingForHuman
        )
        let generation = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-0", "seed-1"],
            parentSources: ["A", "B"],
            mode: .crossover,
            steer: "liquid",
            directive: "combine",
            settings: settings(balance: 0.75)
        )
        let child = node(id: "r4-2", parents: generation.parentIDs, round: 4, status: .compiled)
        var value = session()
        value.round = 4
        value.seedCounter = 9
        value.parentHistory = [
            RemixParentConfiguration(parentAID: "seed-0", parentBID: nil),
            RemixParentConfiguration(parentAID: "seed-0", parentBID: "seed-1"),
        ]
        value.mode = .mutate
        value.steer = "liquid"
        value.batchSize = 7
        value.currentBatch = [child]
        value.batchHistory = [
            RemixBatchRecord(round: 4, nodes: [child], requestsByNodeID: [child.id: generation]),
        ]
        value.selectedLineageNodeID = child.id
        value.crossoverSettings = settings(balance: 0.75)
        value.activity = .verificationRequired(slot: .b, requestID: requestID)
        value.pendingParentRequest = request
        value.transcript = ["[r4-2] Complete"]

        XCTAssertEqual(try roundTrip(value), value)
    }

    func test_generationRequestSnapshot_preservesOriginalSettingsAfterControlsChange() throws {
        var controls = settings(balance: 0.2)
        let snapshot = RemixGenerationRequestSnapshot(
            parentIDs: ["a", "b"],
            parentSources: ["source-a", "source-b"],
            mode: .crossover,
            steer: "soft",
            directive: "hybrid",
            settings: controls
        )

        controls.balance = 0.9
        controls.variation = 1

        let restored = try JSONDecoder().decode(
            RemixGenerationRequestSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(restored.settings.balance, 0.2)
        XCTAssertNotEqual(restored.settings, controls)
    }

    func test_normalizedAfterRestore_mapsGeneratingToInterruptedOnlyAtSessionBoundary() throws {
        let generating = node(id: "r2-0", round: 2, status: .generating)
        let encodedNode = try JSONEncoder().encode(generating)
        XCTAssertEqual(try JSONDecoder().decode(RemixNode.self, from: encodedNode).status, .generating)

        var value = session()
        value.currentBatch = [generating, node(id: "r2-1", round: 2, status: .failed("bad"))]
        var lineage = RemixLineage()
        value.currentBatch.forEach { lineage.insert($0) }
        value.lineage = lineage

        let normalized = value.normalizedAfterRestore()

        XCTAssertEqual(normalized.currentBatch[0].status, .interrupted)
        XCTAssertEqual(normalized.currentBatch[1].status, .failed("bad"))
        XCTAssertEqual(normalized.lineage.node("r2-0")?.status, .interrupted)
        XCTAssertEqual(normalized.lineage.node("r2-1")?.status, .failed("bad"))
        XCTAssertEqual(normalized.activity, .interrupted)
    }

    func test_nextIDs_afterRestoreCannotCollideWithLineage() {
        var lineage = RemixLineage()
        lineage.insert(node(id: "seed-9", status: .compiled))
        lineage.insert(node(id: "r7-4", round: 0, status: .compiled))
        lineage.insert(node(id: "custom-99", status: .compiled))
        var value = session(lineage: lineage)
        value.round = 1
        value.seedCounter = 1

        let normalized = value.normalizedAfterRestore()

        XCTAssertEqual(normalized.round, 7)
        XCTAssertEqual(normalized.seedCounter, 10)
    }

    private func roundTrip(_ value: RemixSession) throws -> RemixSession {
        try JSONDecoder().decode(RemixSession.self, from: JSONEncoder().encode(value))
    }

    private func settings(balance: Double = 0.5) -> RemixCrossoverSettings {
        var value = RemixCrossoverSettings()
        value.balance = balance
        value.variation = 0.65
        value.setSource(.a, for: .motion)
        return value
    }

    private func node(
        id: String,
        parents: [String] = [],
        round: Int = 0,
        status: RemixNode.Status = .generating
    ) -> RemixNode {
        RemixNode(
            id: id,
            isfSource: "/*{}*/",
            parents: parents,
            mode: .crossover,
            steer: "",
            directive: "test",
            round: round,
            status: status
        )
    }

    private func session(
        lineage: RemixLineage = RemixLineage(),
        workspace: RemixWorkspaceState = RemixWorkspaceState()
    ) -> RemixSession {
        RemixSession(
            round: 1,
            seedCounter: 2,
            parentAID: "seed-0",
            parentBID: "r1-0",
            parentHistory: [],
            mode: .crossover,
            steer: "",
            batchSize: 5,
            currentBatch: [],
            batchHistory: [],
            lineage: lineage,
            workspace: workspace,
            selectedLineageNodeID: nil,
            crossoverSettings: RemixCrossoverSettings(),
            activity: .idle,
            pendingParentRequest: nil,
            transcript: []
        )
    }
}
