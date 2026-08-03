import Foundation

struct RemixGenerationRequestSnapshot: Codable, Equatable {
    let parentIDs: [String]
    let parentSources: [String]
    let mode: RemixMode
    let steer: String
    let directive: String
    let settings: RemixCrossoverSettings
}

struct RemixBatchRecord: Codable, Equatable {
    let round: Int
    var runs: [RemixChildRunRecord]

    init(round: Int, runs: [RemixChildRunRecord]) {
        self.round = round
        self.runs = runs
    }

    /// Temporary source compatibility until Task 7 moves the studio model to `currentRuns`.
    init(
        round: Int,
        nodes: [RemixNode],
        requestsByNodeID: [String: RemixGenerationRequestSnapshot]
    ) {
        self.round = round
        runs = nodes.enumerated().map { offset, node in
            Self.run(
                from: node,
                slot: Self.slot(in: node.id) ?? offset,
                request: requestsByNodeID[node.id] ?? Self.fallbackRequest(for: node)
            )
        }
    }

    var requestsByNodeID: [String: RemixGenerationRequestSnapshot] {
        Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0.request) })
    }

    var nodes: [RemixNode] {
        get { runs.map(Self.legacyNode(from:)) }
        set {
            let requests = requestsByNodeID
            runs = newValue.enumerated().map { offset, node in
                Self.run(
                    from: node,
                    slot: Self.slot(in: node.id) ?? offset,
                    request: requests[node.id] ?? Self.fallbackRequest(for: node)
                )
            }
        }
    }

    private static func run(
        from node: RemixNode,
        slot: Int,
        request: RemixGenerationRequestSnapshot
    ) -> RemixChildRunRecord {
        let stage: RemixChildRunRecord.Stage
        var boundary: RemixChildRunRecord.FailureBoundary?
        var failureMessage: String?
        switch node.status {
        case .generating:
            stage = .queued
        case .compiled:
            stage = .compiling
        case .interrupted:
            stage = .interrupted
        case .failed(let message):
            if message.localizedCaseInsensitiveContains("cancelled") {
                stage = .cancelled
            } else {
                stage = .failed
                boundary = message == "No ISF in reply" ? .response : .provider
            }
            failureMessage = message
        }
        return RemixChildRunRecord(
            id: node.id,
            round: node.round,
            slot: slot,
            request: request,
            stage: stage,
            queuedAt: Date(timeIntervalSince1970: 0),
            terminalAt: stage.isTerminal ? Date(timeIntervalSince1970: 0) : nil,
            candidateSource: node.isfSource.isEmpty ? nil : node.isfSource,
            failureBoundary: boundary,
            failureMessage: failureMessage
        )
    }

    private static func legacyNode(from run: RemixChildRunRecord) -> RemixNode {
        let status: RemixNode.Status
        switch run.stage {
        case .ready:
            status = .compiled
        case .failed:
            status = .failed(run.failureMessage ?? run.compileDiagnostic ?? "failed")
        case .cancelled:
            status = .failed("cancelled")
        case .interrupted:
            status = .interrupted
        case .queued, .starting, .thinking, .receiving, .retrying, .extracting, .compiling:
            status = .generating
        }
        return RemixNode(
            id: run.id,
            isfSource: run.stage == .ready ? (run.candidateSource ?? "") : "",
            parents: run.request.parentIDs,
            mode: run.request.mode,
            steer: run.request.steer,
            directive: run.request.directive,
            round: run.round,
            status: status
        )
    }

    fileprivate static func fallbackRequest(for node: RemixNode) -> RemixGenerationRequestSnapshot {
        RemixGenerationRequestSnapshot(
            parentIDs: node.parents,
            parentSources: [],
            mode: node.mode,
            steer: node.steer,
            directive: node.directive,
            settings: RemixCrossoverSettings()
        )
    }

    fileprivate static func slot(in id: String) -> Int? {
        guard let separator = id.lastIndex(of: "-") else { return nil }
        return Int(id[id.index(after: separator)...])
    }
}

struct RemixParentConfiguration: Codable, Equatable {
    let parentAID: String?
    let parentBID: String?
}

enum RemixParentSourceSnapshot: Codable, Equatable {
    case pastedISF(String)
    case libraryPath(String)
    case shadertoyLink(String)
    case currentEditorSource(String)
}

enum RemixParentRequestPhase: String, Codable, Equatable {
    case fetching
    case verificationRequired
    case waitingForHuman
    case resuming
    case converting
}

struct RemixParentRequestSnapshot: Codable, Equatable {
    let id: UUID
    let slot: ParentSlot
    let source: RemixParentSourceSnapshot
    let displayInput: String
    let phase: RemixParentRequestPhase
}

struct RemixSession: Codable, Equatable {
    var schemaVersion = 2
    var round: Int
    var seedCounter: Int
    var parentAID: String?
    var parentBID: String?
    var parentHistory: [RemixParentConfiguration]
    var mode: RemixMode
    var steer: String
    var batchSize: Int
    var currentRuns: [RemixChildRunRecord]
    var batchHistory: [RemixBatchRecord]
    var lineage: RemixLineage
    var workspace: RemixWorkspaceState
    var selectedLineageNodeID: String?
    var crossoverSettings: RemixCrossoverSettings
    var activity: RemixActivityState
    var pendingParentRequest: RemixParentRequestSnapshot?
    var transcript: [String]
    var previewStates: [String: RemixPreviewState]

    init(
        round: Int,
        seedCounter: Int,
        parentAID: String?,
        parentBID: String?,
        parentHistory: [RemixParentConfiguration],
        mode: RemixMode,
        steer: String,
        batchSize: Int,
        currentRuns: [RemixChildRunRecord],
        batchHistory: [RemixBatchRecord],
        lineage: RemixLineage,
        workspace: RemixWorkspaceState,
        selectedLineageNodeID: String?,
        crossoverSettings: RemixCrossoverSettings,
        activity: RemixActivityState,
        pendingParentRequest: RemixParentRequestSnapshot?,
        transcript: [String],
        previewStates: [String: RemixPreviewState] = [:]
    ) {
        self.round = round
        self.seedCounter = seedCounter
        self.parentAID = parentAID
        self.parentBID = parentBID
        self.parentHistory = parentHistory
        self.mode = mode
        self.steer = steer
        self.batchSize = batchSize
        self.currentRuns = currentRuns
        self.batchHistory = batchHistory
        self.lineage = lineage
        self.workspace = workspace
        self.selectedLineageNodeID = selectedLineageNodeID
        self.crossoverSettings = crossoverSettings
        self.activity = activity
        self.pendingParentRequest = pendingParentRequest
        self.transcript = transcript
        self.previewStates = previewStates
    }

    /// Temporary source compatibility until Task 7 replaces the legacy studio-model state.
    init(
        round: Int,
        seedCounter: Int,
        parentAID: String?,
        parentBID: String?,
        parentHistory: [RemixParentConfiguration],
        mode: RemixMode,
        steer: String,
        batchSize: Int,
        currentBatch: [RemixNode],
        batchHistory: [RemixBatchRecord],
        lineage: RemixLineage,
        workspace: RemixWorkspaceState,
        selectedLineageNodeID: String?,
        crossoverSettings: RemixCrossoverSettings,
        activity: RemixActivityState,
        compileDiagnosticsByNodeID: [String: String]? = nil,
        pendingParentRequest: RemixParentRequestSnapshot?,
        transcript: [String],
        previewStates: [String: RemixPreviewState] = [:]
    ) {
        let requests = batchHistory.reduce(into: [String: RemixGenerationRequestSnapshot]()) {
            for (id, request) in $1.requestsByNodeID { $0[id] = request }
        }
        let diagnostics = compileDiagnosticsByNodeID ?? [:]
        let assembledCurrentRuns = currentBatch.enumerated().map { offset, node in
            let run = RemixBatchRecord(
                round: node.round,
                nodes: [node],
                requestsByNodeID: [
                    node.id: requests[node.id] ?? RemixBatchRecord.fallbackRequest(for: node),
                ]
            ).runs[0]
            return Self.assemblingCompatibilityCompileDiagnostic(
                diagnostics[node.id],
                into: run
            )
        }
        let assembledHistory = batchHistory.map { batch in
            RemixBatchRecord(
                round: batch.round,
                runs: batch.runs.map { run in
                    Self.assemblingCompatibilityCompileDiagnostic(
                        diagnostics[run.id],
                        into: run
                    )
                }
            )
        }
        self.init(
            round: round,
            seedCounter: seedCounter,
            parentAID: parentAID,
            parentBID: parentBID,
            parentHistory: parentHistory,
            mode: mode,
            steer: steer,
            batchSize: batchSize,
            currentRuns: assembledCurrentRuns,
            batchHistory: assembledHistory,
            lineage: Self.seedArtifacts(from: lineage),
            workspace: workspace,
            selectedLineageNodeID: selectedLineageNodeID,
            crossoverSettings: crossoverSettings,
            activity: activity,
            pendingParentRequest: pendingParentRequest,
            transcript: transcript,
            previewStates: previewStates
        )
    }

    var currentBatch: [RemixNode] {
        get { RemixBatchRecord(round: round, runs: currentRuns).nodes }
        set {
            let requests = Dictionary(uniqueKeysWithValues: currentRuns.map { ($0.id, $0.request) })
            currentRuns = RemixBatchRecord(
                round: round,
                nodes: newValue,
                requestsByNodeID: requests
            ).runs
        }
    }

    var compileDiagnosticsByNodeID: [String: String]? {
        get {
            let runs = currentRuns + batchHistory.flatMap(\.runs)
            let values = runs.reduce(into: [String: String]()) { result, run in
                if let diagnostic = run.compileDiagnostic {
                    result[run.id] = diagnostic
                }
            }
            return values.isEmpty ? nil : values
        }
        set {
            guard let newValue else { return }
            currentRuns = currentRuns.map { run in
                guard !run.stage.isTerminal else { return run }
                return Self.applyingCompileDiagnostic(newValue[run.id], to: run)
            }
            batchHistory = batchHistory.map { record in
                RemixBatchRecord(
                    round: record.round,
                    runs: record.runs.map { run in
                        guard !run.stage.isTerminal else { return run }
                        return Self.applyingCompileDiagnostic(newValue[run.id], to: run)
                    }
                )
            }
        }
    }

    /// Task 7 owns launch-time normalization and local resume. Persistence preserves exact v2 state.
    func normalizedAfterRestore() -> RemixSession { self }

    func boundedForPersistence() -> RemixSession {
        var bounded = self
        bounded.currentRuns = currentRuns.map { $0.boundedForPersistence() }
        bounded.batchHistory = batchHistory.map { record in
            RemixBatchRecord(
                round: record.round,
                runs: record.runs.map { $0.boundedForPersistence() }
            )
        }
        return bounded
    }

    private static func applyingCompileDiagnostic(
        _ diagnostic: String?,
        to value: RemixChildRunRecord
    ) -> RemixChildRunRecord {
        guard let diagnostic else { return value }
        var run = value
        run.stage = .failed
        run.failureBoundary = .compile
        run.failureMessage = diagnostic
        run.compileDiagnostic = diagnostic
        run.terminalAt = run.terminalAt ?? Date(timeIntervalSince1970: 0)
        return run.boundedForPersistence()
    }

    private static func assemblingCompatibilityCompileDiagnostic(
        _ diagnostic: String?,
        into value: RemixChildRunRecord
    ) -> RemixChildRunRecord {
        guard let diagnostic else { return value }
        guard value.stage == .failed else {
            return value.stage.isTerminal ? value : applyingCompileDiagnostic(diagnostic, to: value)
        }
        var run = value
        run.failureBoundary = .compile
        run.failureMessage = diagnostic
        run.compileDiagnostic = diagnostic
        return run.boundedForPersistence()
    }

    private static func seedArtifacts(from legacyLineage: RemixLineage) -> RemixLineage {
        var artifacts = RemixLineage()
        for node in legacyLineage.allNodes where node.id.hasPrefix("seed-") {
            artifacts.insert(RemixNode(
                artifactID: node.id,
                isfSource: node.isfSource,
                parents: node.parents,
                mode: node.mode,
                steer: node.steer,
                directive: node.directive,
                round: node.round,
                label: node.label
            ))
            if legacyLineage.isFavorite(node.id) {
                artifacts.toggleFavorite(node.id)
            }
        }
        return artifacts
    }

    private init(migrating legacy: LegacyRemixSessionV1) {
        let candidates = Self.candidatesByNodeID(in: legacy)
        let requests = Self.requestsByNodeID(in: legacy)
        let diagnostics = legacy.compileDiagnosticsByNodeID ?? [:]
        currentRuns = legacy.currentBatch.enumerated().map { offset, node in
            Self.migratedRun(
                node,
                slot: RemixBatchRecord.slot(in: node.id) ?? offset,
                candidate: candidates[node.id],
                request: requests[node.id] ?? Self.fallbackRequest(for: node, in: legacy),
                compileDiagnostic: diagnostics[node.id],
                transcript: legacy.transcript
            )
        }
        var migratedHistory = legacy.batchHistory.map { batch in
            RemixBatchRecord(
                round: batch.round,
                runs: batch.nodes.enumerated().map { offset, node in
                    Self.migratedRun(
                        node,
                        slot: RemixBatchRecord.slot(in: node.id) ?? offset,
                        candidate: candidates[node.id],
                        request: requests[node.id] ?? Self.fallbackRequest(for: node, in: legacy),
                        compileDiagnostic: diagnostics[node.id],
                        transcript: legacy.transcript
                    )
                }
            )
        }
        let representedRunIDs = Set(
            legacy.currentBatch.map(\.id) + legacy.batchHistory.flatMap(\.nodes).map(\.id)
        )
        let lineageOnlyGeneratedNodes = legacy.lineage.allNodes.filter {
            !$0.id.hasPrefix("seed-") && !representedRunIDs.contains($0.id)
        }
        for node in lineageOnlyGeneratedNodes {
            if let batchIndex = migratedHistory.lastIndex(where: { $0.round == node.round }) {
                let slot = RemixBatchRecord.slot(in: node.id)
                    ?? migratedHistory[batchIndex].runs.count
                migratedHistory[batchIndex].runs.append(Self.migratedRun(
                    node,
                    slot: slot,
                    candidate: candidates[node.id],
                    request: requests[node.id] ?? Self.fallbackRequest(for: node, in: legacy),
                    compileDiagnostic: diagnostics[node.id],
                    transcript: legacy.transcript
                ))
            } else {
                let run = Self.migratedRun(
                    node,
                    slot: RemixBatchRecord.slot(in: node.id) ?? 0,
                    candidate: candidates[node.id],
                    request: requests[node.id] ?? Self.fallbackRequest(for: node, in: legacy),
                    compileDiagnostic: diagnostics[node.id],
                    transcript: legacy.transcript
                )
                let insertionIndex = migratedHistory.firstIndex { $0.round > node.round }
                    ?? migratedHistory.endIndex
                migratedHistory.insert(
                    RemixBatchRecord(round: node.round, runs: [run]),
                    at: insertionIndex
                )
            }
        }
        batchHistory = migratedHistory
        let allNodes = legacy.lineage.allNodes
            + legacy.currentBatch
            + legacy.batchHistory.flatMap(\.nodes)
        schemaVersion = 2
        round = max(
            legacy.round,
            allNodes.reduce(0) { max($0, $1.round, Self.roundIndex(in: $1.id) ?? 0) }
        )
        seedCounter = max(
            legacy.seedCounter,
            (allNodes.compactMap { Self.seedIndex(in: $0.id) }.max() ?? -1) + 1
        )
        parentAID = legacy.parentAID
        parentBID = legacy.parentBID
        parentHistory = legacy.parentHistory
        mode = legacy.mode
        steer = legacy.steer
        batchSize = legacy.batchSize
        lineage = Self.seedArtifacts(from: legacy.lineage)
        workspace = legacy.workspace
        selectedLineageNodeID = lineage.node(legacy.selectedLineageNodeID ?? "") == nil
            ? nil
            : legacy.selectedLineageNodeID
        crossoverSettings = legacy.crossoverSettings
        activity = legacy.activity
        pendingParentRequest = legacy.pendingParentRequest
        transcript = legacy.transcript
        previewStates = [:]
    }

    private static func candidatesByNodeID(in legacy: LegacyRemixSessionV1) -> [String: String] {
        var candidates: [String: String] = [:]
        for node in legacy.lineage.allNodes {
            if let candidate = RemixResponseParser.extractISF(node.isfSource) {
                candidates[node.id] = candidate
            }
        }
        for node in legacy.batchHistory.flatMap(\.nodes) {
            if let candidate = RemixResponseParser.extractISF(node.isfSource) {
                candidates[node.id] = candidate
            }
        }
        for node in legacy.currentBatch {
            if let candidate = RemixResponseParser.extractISF(node.isfSource) {
                candidates[node.id] = candidate
            }
        }
        return candidates
    }

    private static func requestsByNodeID(
        in legacy: LegacyRemixSessionV1
    ) -> [String: RemixGenerationRequestSnapshot] {
        legacy.batchHistory.reduce(into: [:]) { requests, batch in
            for (id, request) in batch.requestsByNodeID {
                requests[id] = request
            }
        }
    }

    private static func fallbackRequest(
        for node: RemixNode,
        in legacy: LegacyRemixSessionV1
    ) -> RemixGenerationRequestSnapshot {
        RemixGenerationRequestSnapshot(
            parentIDs: node.parents,
            parentSources: node.parents.compactMap { legacy.lineage.node($0)?.isfSource },
            mode: node.mode,
            steer: node.steer,
            directive: node.directive,
            settings: legacy.crossoverSettings
        )
    }

    private static func migratedRun(
        _ node: RemixNode,
        slot: Int,
        candidate selectedCandidate: String?,
        request: RemixGenerationRequestSnapshot,
        compileDiagnostic: String?,
        transcript: [String]
    ) -> RemixChildRunRecord {
        let legacyFailure: String?
        if case .failed(let message) = node.status {
            legacyFailure = message
        } else {
            legacyFailure = nil
        }
        var candidate = selectedCandidate?.isEmpty == false ? selectedCandidate : nil
        var recoveredFromTranscript = false
        let isLegacyUnfinished = node.status == .generating || node.status == .interrupted
        if candidate == nil,
           (legacyFailure == "No ISF in reply" || isLegacyUnfinished),
           let recovered = RemixLegacyRecovery.candidate(childID: node.id, transcript: transcript) {
            candidate = recovered
            recoveredFromTranscript = true
        }

        var run = RemixChildRunRecord(
            id: node.id,
            round: node.round,
            slot: slot,
            request: request,
            stage: .interrupted,
            queuedAt: Date(timeIntervalSince1970: 0),
            terminalAt: Date(timeIntervalSince1970: 0),
            candidateSource: candidate,
            failureMessage: legacyFailure
        )

        if let compileDiagnostic {
            return applyingCompileDiagnostic(compileDiagnostic, to: run)
        }

        switch node.status {
        case .compiled:
            if candidate != nil {
                run.stage = .compiling
                run.terminalAt = nil
                run.failureMessage = nil
            }
        case .generating, .interrupted:
            if candidate != nil {
                run.stage = recoveredFromTranscript ? .extracting : .compiling
                run.terminalAt = nil
                run.failureMessage = nil
            }
        case .failed(let message):
            if message == "No ISF in reply" {
                if recoveredFromTranscript {
                    run.stage = .extracting
                    run.terminalAt = nil
                    run.failureMessage = nil
                } else if candidate != nil {
                    run.stage = .compiling
                    run.terminalAt = nil
                    run.failureMessage = nil
                } else {
                    run.stage = .failed
                    run.failureBoundary = .response
                }
            } else if message.localizedCaseInsensitiveContains("cancelled") {
                run.stage = .cancelled
            } else if Self.isKnownProviderFailure(message) {
                run.stage = .failed
                run.failureBoundary = .provider
            } else if message.localizedCaseInsensitiveContains("extract") {
                run.stage = .failed
                run.failureBoundary = .extraction
            } else {
                run.stage = .failed
            }
        }
        return run.boundedForPersistence()
    }

    private static func isKnownProviderFailure(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return ["provider", "timed out", "timeout", "process failed", "not authenticated", "binary not found"]
            .contains { lowercased.contains($0) }
    }

    private static func seedIndex(in id: String) -> Int? {
        guard id.hasPrefix("seed-") else { return nil }
        return Int(id.dropFirst("seed-".count))
    }

    private static func roundIndex(in id: String) -> Int? {
        guard id.first == "r", let separator = id.firstIndex(of: "-") else { return nil }
        return Int(id[id.index(after: id.startIndex)..<separator])
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, round, seedCounter, parentAID, parentBID, parentHistory
        case mode, steer, batchSize, currentRuns, batchHistory, lineage, workspace
        case selectedLineageNodeID, crossoverSettings, activity, pendingParentRequest, transcript
        case previewStates
    }

    init(from decoder: Decoder) throws {
        let versionContainer = try decoder.container(keyedBy: CodingKeys.self)
        let version = try versionContainer.decode(Int.self, forKey: .schemaVersion)
        if version == 1 {
            self.init(migrating: try LegacyRemixSessionV1(from: decoder))
            return
        }
        guard version == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: versionContainer,
                debugDescription: "Unsupported RemixSession schema version \(version)"
            )
        }

        self.init(
            round: try versionContainer.decode(Int.self, forKey: .round),
            seedCounter: try versionContainer.decode(Int.self, forKey: .seedCounter),
            parentAID: try versionContainer.decodeIfPresent(String.self, forKey: .parentAID),
            parentBID: try versionContainer.decodeIfPresent(String.self, forKey: .parentBID),
            parentHistory: try versionContainer.decode(
                [RemixParentConfiguration].self,
                forKey: .parentHistory
            ),
            mode: try versionContainer.decode(RemixMode.self, forKey: .mode),
            steer: try versionContainer.decode(String.self, forKey: .steer),
            batchSize: try versionContainer.decode(Int.self, forKey: .batchSize),
            currentRuns: try versionContainer.decode(
                [RemixChildRunRecord].self,
                forKey: .currentRuns
            ),
            batchHistory: try versionContainer.decode(
                [RemixBatchRecord].self,
                forKey: .batchHistory
            ),
            lineage: try versionContainer.decode(RemixLineage.self, forKey: .lineage),
            workspace: try versionContainer.decode(RemixWorkspaceState.self, forKey: .workspace),
            selectedLineageNodeID: try versionContainer.decodeIfPresent(
                String.self,
                forKey: .selectedLineageNodeID
            ),
            crossoverSettings: try versionContainer.decode(
                RemixCrossoverSettings.self,
                forKey: .crossoverSettings
            ),
            activity: try versionContainer.decode(RemixActivityState.self, forKey: .activity),
            pendingParentRequest: try versionContainer.decodeIfPresent(
                RemixParentRequestSnapshot.self,
                forKey: .pendingParentRequest
            ),
            transcript: try versionContainer.decode([String].self, forKey: .transcript),
            previewStates: try versionContainer.decodeIfPresent(
                [String: RemixPreviewState].self,
                forKey: .previewStates
            ) ?? [:]
        )
    }

    func encode(to encoder: Encoder) throws {
        let bounded = boundedForPersistence()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .schemaVersion)
        try container.encode(bounded.round, forKey: .round)
        try container.encode(bounded.seedCounter, forKey: .seedCounter)
        try container.encodeIfPresent(bounded.parentAID, forKey: .parentAID)
        try container.encodeIfPresent(bounded.parentBID, forKey: .parentBID)
        try container.encode(bounded.parentHistory, forKey: .parentHistory)
        try container.encode(bounded.mode, forKey: .mode)
        try container.encode(bounded.steer, forKey: .steer)
        try container.encode(bounded.batchSize, forKey: .batchSize)
        try container.encode(bounded.currentRuns, forKey: .currentRuns)
        try container.encode(bounded.batchHistory, forKey: .batchHistory)
        try container.encode(bounded.lineage, forKey: .lineage)
        try container.encode(bounded.workspace, forKey: .workspace)
        try container.encodeIfPresent(bounded.selectedLineageNodeID, forKey: .selectedLineageNodeID)
        try container.encode(bounded.crossoverSettings, forKey: .crossoverSettings)
        try container.encode(bounded.activity, forKey: .activity)
        try container.encodeIfPresent(bounded.pendingParentRequest, forKey: .pendingParentRequest)
        try container.encode(bounded.transcript, forKey: .transcript)
        try container.encode(bounded.previewStates, forKey: .previewStates)
    }
}
