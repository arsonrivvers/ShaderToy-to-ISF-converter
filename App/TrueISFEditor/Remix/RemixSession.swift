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
    var nodes: [RemixNode]
    let requestsByNodeID: [String: RemixGenerationRequestSnapshot]
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
    var schemaVersion = 1
    var round: Int
    var seedCounter: Int
    var parentAID: String?
    var parentBID: String?
    var parentHistory: [RemixParentConfiguration]
    var mode: RemixMode
    var steer: String
    var batchSize: Int
    var currentBatch: [RemixNode]
    var batchHistory: [RemixBatchRecord]
    var lineage: RemixLineage
    var workspace: RemixWorkspaceState
    var selectedLineageNodeID: String?
    var crossoverSettings: RemixCrossoverSettings
    var activity: RemixActivityState
    /// Optional so sessions written before compile provenance existed remain decodable.
    var compileDiagnosticsByNodeID: [String: String]? = nil
    var pendingParentRequest: RemixParentRequestSnapshot?
    var transcript: [String]

    func normalizedAfterRestore() -> RemixSession {
        var restored = self
        var replacedGeneratingNode = false

        restored.currentBatch = restored.currentBatch.map {
            Self.interruptedIfGenerating($0, replaced: &replacedGeneratingNode)
        }
        restored.batchHistory = restored.batchHistory.map { record in
            var updated = record
            updated.nodes = record.nodes.map {
                Self.interruptedIfGenerating($0, replaced: &replacedGeneratingNode)
            }
            return updated
        }

        var normalizedLineage = restored.lineage
        for node in restored.lineage.allNodes {
            normalizedLineage.insert(
                Self.interruptedIfGenerating(node, replaced: &replacedGeneratingNode)
            )
        }
        restored.lineage = normalizedLineage

        let allNodes = restored.lineage.allNodes
            + restored.currentBatch
            + restored.batchHistory.flatMap(\.nodes)
        let highestRound = allNodes.reduce(0) { highest, node in
            max(highest, node.round, Self.roundIndex(in: node.id) ?? 0)
        }
        restored.round = max(restored.round, highestRound)
        restored.seedCounter = max(
            restored.seedCounter,
            (allNodes.compactMap { Self.seedIndex(in: $0.id) }.max() ?? -1) + 1
        )

        if replacedGeneratingNode {
            restored.activity = .interrupted
        }
        return restored
    }

    private static func interruptedIfGenerating(
        _ node: RemixNode,
        replaced: inout Bool
    ) -> RemixNode {
        guard node.status == .generating else { return node }
        var updated = node
        updated.status = .interrupted
        replaced = true
        return updated
    }

    private static func seedIndex(in id: String) -> Int? {
        guard id.hasPrefix("seed-") else { return nil }
        return Int(id.dropFirst("seed-".count))
    }

    private static func roundIndex(in id: String) -> Int? {
        guard id.first == "r",
              let separator = id.firstIndex(of: "-")
        else {
            return nil
        }
        return Int(id[id.index(after: id.startIndex)..<separator])
    }
}
