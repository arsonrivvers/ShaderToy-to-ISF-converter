import XCTest
@testable import TrueISFEditor

final class RemixSessionTests: XCTestCase {
    private let recoveredISF = """
    /*{ "ISFVSN": "2.0", "DESCRIPTION": "Recovered r2-3" }*/
    void main(){ gl_FragColor=vec4(1.0); }
    """

    func test_schemaV2RoundTripRestoresRunsArtifactsAndWorkspace() throws {
        let queued = run(id: "r4-0", slot: 0, stage: .queued)
        var compiling = run(id: "r4-1", slot: 1, stage: .compiling)
        compiling.candidateSource = "candidate-r4-1"
        var lineage = RemixLineage()
        lineage.insert(artifact(id: "seed-0", source: "seed-source"))
        lineage.toggleFavorite("seed-0")
        var workspace = RemixWorkspaceState()
        workspace.showHero("seed-0")
        workspace.collapse(.lineage)
        let value = session(
            currentRuns: [queued, compiling],
            batchHistory: [RemixBatchRecord(round: 4, runs: [queued, compiling])],
            lineage: lineage,
            workspace: workspace
        )

        let restored = try roundTrip(value)

        XCTAssertEqual(restored.schemaVersion, 2)
        XCTAssertEqual(restored.currentRuns, [queued, compiling])
        XCTAssertEqual(restored.batchHistory, value.batchHistory)
        XCTAssertEqual(restored.lineage, lineage)
        XCTAssertTrue(restored.lineage.isFavorite("seed-0"))
        XCTAssertEqual(restored.workspace, workspace)
    }

    func test_persistenceBoundsDirectlyConstructedPreviewDiagnosticsByUTF8Bytes() throws {
        var value = session()
        value.previewStates = [
            "artifact-r4-0": RemixPreviewState(
                stage: .failed,
                attempt: 3,
                diagnostic: String(
                    repeating: "🫧",
                    count: RemixPreviewState.maximumDiagnosticBytes
                ),
                updatedAt: Date(timeIntervalSince1970: 4)
            ),
        ]

        let restored = try roundTrip(value)
        let preview = try XCTUnwrap(restored.previewStates["artifact-r4-0"])

        XCTAssertEqual(preview.stage, .failed)
        XCTAssertEqual(preview.attempt, 3)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(preview.diagnostic).utf8.count,
            RemixPreviewState.maximumDiagnosticBytes
        )
    }

    func test_generationRequestSnapshotPreservesOriginalSettingsAfterControlsChange() throws {
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

    func test_v1MigrationUsesDeterministicPrecedenceAndNeverPromotesGeneratedArtifacts() throws {
        let migrated = try JSONDecoder().decode(RemixSession.self, from: legacyV1Data())

        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.currentRuns.map(\.id), ["r2-0", "r2-1", "r2-2", "r2-3", "r2-4"])

        XCTAssertEqual(migrated.currentRuns[0].stage, .interrupted)

        XCTAssertEqual(migrated.currentRuns[1].stage, .compiling)
        XCTAssertEqual(migrated.currentRuns[1].candidateSource, completeISF("current-candidate"))
        XCTAssertNil(migrated.currentRuns[1].artifactID)

        XCTAssertEqual(migrated.currentRuns[2].stage, .failed)
        XCTAssertEqual(migrated.currentRuns[2].failureBoundary, .compile)
        XCTAssertEqual(migrated.currentRuns[2].compileDiagnostic, "line 12: bad uniform")

        XCTAssertEqual(migrated.currentRuns[3].stage, .extracting)
        XCTAssertEqual(migrated.currentRuns[3].candidateSource, recoveredISF)
        XCTAssertEqual(migrated.currentRuns[3].failureBoundary, nil)

        XCTAssertEqual(migrated.currentRuns[4].stage, .failed)
        XCTAssertEqual(migrated.currentRuns[4].failureBoundary, .response)
        XCTAssertEqual(migrated.currentRuns[4].failureMessage, "No ISF in reply")
        XCTAssertNil(migrated.currentRuns[4].candidateSource)

        XCTAssertEqual(migrated.batchHistory[0].runs.first?.id, "r1-9")
        XCTAssertEqual(migrated.batchHistory[0].runs.first?.stage, .interrupted)
        XCTAssertEqual(
            migrated.batchHistory[1].runs.first?.candidateSource,
            completeISF("current-candidate")
        )

        XCTAssertEqual(migrated.lineage.allNodes.map(\.id), ["seed-0"])
        XCTAssertEqual(migrated.lineage.node("seed-0")?.status, .compiled)
        XCTAssertNil(migrated.lineage.node("r2-1"))
    }

    func test_migratedV1DecodeEncodeDecodeIsIdempotentAndWritesOnlySchemaV2Fields() throws {
        let migrated = try JSONDecoder().decode(RemixSession.self, from: legacyV1Data())

        let encoded = try JSONEncoder().encode(migrated)
        let decodedAgain = try JSONDecoder().decode(RemixSession.self, from: encoded)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(decodedAgain, migrated)
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertNotNil(object["currentRuns"])
        XCTAssertNil(object["currentBatch"])
        XCTAssertNil(object["compileDiagnosticsByNodeID"])
        let history = try XCTUnwrap(object["batchHistory"] as? [[String: Any]])
        XCTAssertTrue(history.allSatisfy { $0["runs"] != nil && $0["nodes"] == nil })
    }

    func test_preRetrySchemaV2DefaultsRetryFieldsAndRoundTripsIdempotently() throws {
        let decoded = try JSONDecoder().decode(RemixSession.self, from: preRetryV2Data())

        XCTAssertEqual(decoded.currentRuns.count, 1)
        XCTAssertEqual(decoded.currentRuns[0].stage, .receiving)
        XCTAssertEqual(decoded.currentRuns[0].receivedBytes, 11)
        XCTAssertEqual(decoded.currentRuns[0].apiRetryCount, 0)
        XCTAssertNil(decoded.currentRuns[0].lastProviderNotice)

        let decodedAgain = try roundTrip(decoded)
        XCTAssertEqual(decodedAgain, decoded)
    }

    func test_literalMidBatchSchemaV2FixturePreservesLiveStagesAndCandidates() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "remix-schema-v2-mid-batch",
            withExtension: "json"
        ))
        let decoded = try JSONDecoder().decode(
            RemixSession.self,
            from: Data(contentsOf: url)
        )

        XCTAssertEqual(decoded.currentRuns.map(\.stage), [
            .queued, .starting, .thinking, .receiving, .retrying, .extracting, .compiling,
        ])
        XCTAssertEqual(decoded.currentRuns[4].apiRetryCount, 2)
        XCTAssertEqual(decoded.currentRuns[4].lastProviderNotice, "rate limited; retrying")
        XCTAssertEqual(decoded.currentRuns[5].candidateSource, "extracting-candidate")
        XCTAssertEqual(decoded.currentRuns[6].candidateSource, "compiling-candidate")
        XCTAssertEqual(try roundTrip(decoded), decoded)
    }

    func test_v1EmptyResultFixturePromotesOnlyCompleteChildTaggedCandidatesForLocalResume() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "remix-2026-08-01-empty-result-session-v1",
            withExtension: "json"
        ))
        let decoded = try JSONDecoder().decode(RemixSession.self, from: Data(contentsOf: url))

        XCTAssertEqual(decoded.currentRuns.map(\.stage), [
            .extracting, .extracting, .interrupted, .extracting, .interrupted,
        ])
        XCTAssertEqual(decoded.currentRuns.compactMap(\.candidateSource), [
            completeISF("Recovered r1-0"),
            completeISF("Recovered r1-1"),
            completeISF("Recovered r1-3"),
        ])
    }

    func test_v1MigrationRetainsLineageOnlyGeneratedChildrenInDeterministicRoundGroups() throws {
        let existingHistoryNode = legacyNode(
            id: "r1-0",
            source: completeISF("history-r1-0"),
            round: 1,
            status: .compiled
        )
        let lineageRoundTwoFirst = legacyNode(
            id: "r2-0",
            source: completeISF("lineage-r2-0"),
            round: 2,
            status: .compiled
        )
        let lineageRoundOne = legacyNode(
            id: "r1-1",
            source: completeISF("lineage-r1-1"),
            round: 1,
            status: .compiled
        )
        let lineageRoundTwoSecond = legacyNode(
            id: "r2-1",
            source: completeISF("lineage-r2-1"),
            round: 2,
            status: .compiled
        )
        var lineage = RemixLineage()
        lineage.insert(artifact(id: "seed-0", source: completeISF("seed")))
        lineage.insert(lineageRoundTwoFirst)
        lineage.insert(lineageRoundOne)
        lineage.insert(lineageRoundTwoSecond)
        let legacy = legacySession(
            batchHistory: [
                LegacyRemixBatchRecordV1(
                    round: 1,
                    nodes: [existingHistoryNode],
                    requestsByNodeID: [:]
                ),
            ],
            lineage: lineage
        )

        let migrated = try JSONDecoder().decode(
            RemixSession.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertTrue(migrated.currentRuns.isEmpty)
        XCTAssertEqual(migrated.batchHistory.map(\.round), [1, 2])
        XCTAssertEqual(migrated.batchHistory.map { $0.runs.map(\.id) }, [
            ["r1-0", "r1-1"],
            ["r2-0", "r2-1"],
        ])
        XCTAssertEqual(migrated.batchHistory.flatMap(\.runs).map(\.stage), [
            .compiling, .compiling, .compiling, .compiling,
        ])
        XCTAssertEqual(migrated.lineage.allNodes.map(\.id), ["seed-0"])
    }

    func test_v1MigrationLeavesMalformedSavedSourceInterrupted() throws {
        let malformed = """
        /*{ "ISFVSN": "2.0" }*/
        void main() {
        """
        let child = legacyNode(
            id: "r2-0",
            source: malformed,
            round: 2,
            status: .compiled
        )
        let legacy = legacySession(currentBatch: [child])

        let migrated = try JSONDecoder().decode(
            RemixSession.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(migrated.currentRuns.first?.stage, .interrupted)
        XCTAssertNil(migrated.currentRuns.first?.candidateSource)
    }

    func test_v1MigrationKeepsUnknownGenericFailureTerminalWithoutInventingBoundary() throws {
        let child = legacyNode(
            id: "r2-0",
            source: "",
            round: 2,
            status: .failed("opaque legacy failure")
        )
        let legacy = legacySession(currentBatch: [child])

        let migrated = try JSONDecoder().decode(
            RemixSession.self,
            from: JSONEncoder().encode(legacy)
        )
        let run = try XCTUnwrap(migrated.currentRuns.first)

        XCTAssertEqual(run.stage, .failed)
        XCTAssertEqual(run.failureMessage, "opaque legacy failure")
        XCTAssertNil(run.failureBoundary)
        XCTAssertNotNil(run.terminalAt)
    }

    func test_compatibilityCompileDiagnosticSetterDoesNotRewriteTerminalRuns() throws {
        var ready = run(id: "r4-0", slot: 0, stage: .compiling)
        ready.candidateSource = completeISF("ready")
        XCTAssertTrue(ready.finishReady(
            artifactID: "artifact-r4-0",
            at: Date(timeIntervalSince1970: 2)
        ))
        let interrupted = run(id: "r3-0", slot: 0, stage: .interrupted)
        var value = session(
            currentRuns: [ready],
            batchHistory: [RemixBatchRecord(round: 3, runs: [interrupted])]
        )
        let originalCurrentRuns = value.currentRuns
        let originalBatchHistory = value.batchHistory

        value.compileDiagnosticsByNodeID = [
            ready.id: "late ready diagnostic",
            interrupted.id: "late interrupted diagnostic",
        ]

        XCTAssertEqual(value.currentRuns, originalCurrentRuns)
        XCTAssertEqual(value.batchHistory, originalBatchHistory)
    }

    func test_compatibilityInitializerAssemblesCompileEvidenceBeforeTerminalImmutability() throws {
        let diagnostic = "line 12: bad uniform"
        let failed = legacyNode(
            id: "r4-0",
            source: completeISF("compile-failure"),
            round: 4,
            status: .failed(diagnostic)
        )
        let history = RemixBatchRecord(
            round: 4,
            nodes: [failed],
            requestsByNodeID: [:]
        )
        var value = RemixSession(
            round: 4,
            seedCounter: 1,
            parentAID: "seed-0",
            parentBID: nil,
            parentHistory: [],
            mode: .crossover,
            steer: "legacy compatibility",
            batchSize: 1,
            currentBatch: [failed],
            batchHistory: [history],
            lineage: RemixLineage(),
            workspace: RemixWorkspaceState(),
            selectedLineageNodeID: nil,
            crossoverSettings: RemixCrossoverSettings(),
            activity: .idle,
            compileDiagnosticsByNodeID: [failed.id: diagnostic],
            pendingParentRequest: nil,
            transcript: []
        )

        let assembledRuns = value.currentRuns + value.batchHistory.flatMap(\.runs)
        XCTAssertEqual(assembledRuns.map(\.stage), [.failed, .failed])
        XCTAssertEqual(assembledRuns.map(\.failureBoundary), [.compile, .compile])
        XCTAssertEqual(assembledRuns.map(\.failureMessage), [diagnostic, diagnostic])
        XCTAssertEqual(assembledRuns.map(\.compileDiagnostic), [diagnostic, diagnostic])
        XCTAssertEqual(
            assembledRuns.map(\.terminalAt),
            [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 0)]
        )

        value.compileDiagnosticsByNodeID = [failed.id: "late diagnostic must not win"]

        XCTAssertEqual(value.currentRuns + value.batchHistory.flatMap(\.runs), assembledRuns)
    }

    func test_v1MigrationCompileDiagnosticStillOverridesGenericFailure() throws {
        let child = legacyNode(
            id: "r2-0",
            source: completeISF("compile-failure"),
            round: 2,
            status: .failed("opaque legacy failure")
        )
        let legacy = legacySession(
            currentBatch: [child],
            compileDiagnosticsByNodeID: ["r2-0": "line 7: invalid uniform"]
        )

        let migrated = try JSONDecoder().decode(
            RemixSession.self,
            from: JSONEncoder().encode(legacy)
        )
        let run = try XCTUnwrap(migrated.currentRuns.first)

        XCTAssertEqual(run.stage, .failed)
        XCTAssertEqual(run.failureBoundary, .compile)
        XCTAssertEqual(run.failureMessage, "line 7: invalid uniform")
        XCTAssertEqual(run.compileDiagnostic, "line 7: invalid uniform")
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

    private func artifact(id: String, source: String) -> RemixNode {
        RemixNode(
            artifactID: id,
            isfSource: source,
            parents: [],
            mode: .crossover,
            steer: "",
            directive: "seed",
            round: 0,
            label: "Seed"
        )
    }

    private func legacyNode(
        id: String,
        source: String,
        round: Int,
        status: RemixNode.Status
    ) -> RemixNode {
        RemixNode(
            id: id,
            isfSource: source,
            parents: ["seed-0"],
            mode: .crossover,
            steer: "legacy",
            directive: "migrate",
            round: round,
            status: status
        )
    }

    private func legacySession(
        currentBatch: [RemixNode] = [],
        batchHistory: [LegacyRemixBatchRecordV1] = [],
        lineage suppliedLineage: RemixLineage? = nil,
        compileDiagnosticsByNodeID: [String: String]? = nil
    ) -> LegacyRemixSessionV1 {
        var lineage = suppliedLineage ?? RemixLineage()
        if suppliedLineage == nil {
            lineage.insert(artifact(id: "seed-0", source: completeISF("seed")))
        }
        return LegacyRemixSessionV1(
            schemaVersion: 1,
            round: 2,
            seedCounter: 1,
            parentAID: "seed-0",
            parentBID: nil,
            parentHistory: [],
            mode: .crossover,
            steer: "legacy",
            batchSize: max(1, currentBatch.count),
            currentBatch: currentBatch,
            batchHistory: batchHistory,
            lineage: lineage,
            workspace: RemixWorkspaceState(),
            selectedLineageNodeID: nil,
            crossoverSettings: RemixCrossoverSettings(),
            activity: .idle,
            compileDiagnosticsByNodeID: compileDiagnosticsByNodeID,
            pendingParentRequest: nil,
            transcript: []
        )
    }

    private func completeISF(_ description: String) -> String {
        """
        /*{ "ISFVSN": "2.0", "DESCRIPTION": "\(description)" }*/
        void main(){ gl_FragColor=vec4(1.0); }
        """
    }

    private func run(
        id: String,
        slot: Int,
        stage: RemixChildRunRecord.Stage
    ) -> RemixChildRunRecord {
        RemixChildRunRecord(
            id: id,
            round: 4,
            slot: slot,
            request: RemixGenerationRequestSnapshot(
                parentIDs: ["seed-0", "seed-1"],
                parentSources: ["source-a", "source-b"],
                mode: .crossover,
                steer: "liquid",
                directive: "combine",
                settings: settings(balance: 0.75)
            ),
            stage: stage,
            queuedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func session(
        currentRuns: [RemixChildRunRecord] = [],
        batchHistory: [RemixBatchRecord] = [],
        lineage: RemixLineage = RemixLineage(),
        workspace: RemixWorkspaceState = RemixWorkspaceState()
    ) -> RemixSession {
        RemixSession(
            round: 4,
            seedCounter: 2,
            parentAID: "seed-0",
            parentBID: "seed-1",
            parentHistory: [],
            mode: .crossover,
            steer: "liquid",
            batchSize: 2,
            currentRuns: currentRuns,
            batchHistory: batchHistory,
            lineage: lineage,
            workspace: workspace,
            selectedLineageNodeID: nil,
            crossoverSettings: settings(balance: 0.75),
            activity: .idle,
            pendingParentRequest: nil,
            transcript: []
        )
    }

    private func legacyV1Data() -> Data {
        Data(#"""
        {
          "schemaVersion": 1,
          "round": 2,
          "seedCounter": 1,
          "parentAID": "seed-0",
          "parentBID": null,
          "parentHistory": [],
          "mode": "crossover",
          "steer": "liquid",
          "batchSize": 5,
          "currentBatch": [
            {"id":"r2-0","isfSource":"","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"zero","round":2,"status":{"generating":{}},"label":null},
            {"id":"r2-1","isfSource":"/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"current-candidate\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"one","round":2,"status":{"compiled":{}},"label":null},
            {"id":"r2-2","isfSource":"compile-candidate","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"two","round":2,"status":{"failed":{"_0":"generic legacy failure"}},"label":null},
            {"id":"r2-3","isfSource":"","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"three","round":2,"status":{"failed":{"_0":"No ISF in reply"}},"label":null},
            {"id":"r2-4","isfSource":"","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"four","round":2,"status":{"failed":{"_0":"No ISF in reply"}},"label":null}
          ],
          "batchHistory": [
            {"round":1,"nodes":[{"id":"r1-9","isfSource":"","parents":["seed-0"],"mode":"crossover","steer":"","directive":"old","round":1,"status":{"generating":{}},"label":null}],"requestsByNodeID":{}},
            {"round":2,"nodes":[{"id":"r2-1","isfSource":"/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"history-candidate\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"one","round":2,"status":{"compiled":{}},"label":null}],"requestsByNodeID":{}}
          ],
          "lineage": {
            "nodes": {
              "seed-0":{"id":"seed-0","isfSource":"seed-source","parents":[],"mode":"crossover","steer":"","directive":"seed","round":0,"status":{"compiled":{}},"label":"Seed"},
              "r2-1":{"id":"r2-1","isfSource":"/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"lineage-candidate\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }","parents":["seed-0"],"mode":"crossover","steer":"liquid","directive":"one","round":2,"status":{"compiled":{}},"label":null}
            },
            "order":["seed-0","r2-1"],
            "favorites":["r2-1"]
          },
          "workspace": {
            "canvasMode":"grid","focusedChildID":null,"comparedChildIDs":[],"heroChildID":null,
            "collapsedZones":[],"zoneWidths":["breedingBay",280,"lineage",300,"activity",180],
            "previewsPaused":false,"preFocusCollapsed":null,"preFocusWidths":null
          },
          "selectedLineageNodeID":"r2-1",
          "crossoverSettings":{"balance":0.5,"variation":0.4,"traitSources":{},"enabledDirectives":[]},
          "activity":{"idle":{}},
          "compileDiagnosticsByNodeID":{"r2-2":"line 12: bad uniform"},
          "pendingParentRequest":null,
          "transcript":[
            "[r2-3] ```glsl\n/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"Recovered r2-3\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }\n```",
            "[r2-4] ```glsl\n/*{ \"ISFVSN\": \"2.0\" }*/",
            "[r2-40] ```glsl\n/*{ \"ISFVSN\": \"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(0.0); }\n```"
          ]
        }
        """#.utf8)
    }

    private func preRetryV2Data() -> Data {
        Data(#"""
        {
          "schemaVersion":2,"round":1,"seedCounter":0,"parentAID":null,"parentBID":null,
          "parentHistory":[],"mode":"crossover","steer":"","batchSize":1,
          "currentRuns":[{
            "id":"r1-0","round":1,"slot":0,
            "request":{"parentIDs":[],"parentSources":[],"mode":"crossover","steer":"","directive":"test","settings":{"balance":0.5,"variation":0.4,"traitSources":{},"enabledDirectives":[]}},
            "stage":"receiving","queuedAt":0,"startedAt":1,"lastEventAt":2,"providerCompletedAt":null,"terminalAt":null,
            "provider":"codex","model":null,"workerLabel":"Worker 1","queuePosition":0,"receivedBytes":11,
            "candidateSource":null,"diagnosticResponse":"partial response","failureBoundary":null,"failureMessage":null,
            "compileDiagnostic":null,"artifactID":null
          }],
          "batchHistory":[],"lineage":{"nodes":{},"order":[],"favorites":[]},
          "workspace":{"canvasMode":"grid","focusedChildID":null,"comparedChildIDs":[],"heroChildID":null,"collapsedZones":[],"zoneWidths":["breedingBay",280,"lineage",300,"activity",180],"previewsPaused":false,"preFocusCollapsed":null,"preFocusWidths":null},
          "selectedLineageNodeID":null,"crossoverSettings":{"balance":0.5,"variation":0.4,"traitSources":{},"enabledDirectives":[]},
          "activity":{"idle":{}},"pendingParentRequest":null,"transcript":[]
        }
        """#.utf8)
    }
}
