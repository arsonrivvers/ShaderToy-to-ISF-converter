import Foundation

struct LegacyRemixBatchRecordV1: Codable, Equatable {
    let round: Int
    var nodes: [RemixNode]
    let requestsByNodeID: [String: RemixGenerationRequestSnapshot]
}

struct LegacyRemixSessionV1: Codable, Equatable {
    var schemaVersion: Int
    var round: Int
    var seedCounter: Int
    var parentAID: String?
    var parentBID: String?
    var parentHistory: [RemixParentConfiguration]
    var mode: RemixMode
    var steer: String
    var batchSize: Int
    var currentBatch: [RemixNode]
    var batchHistory: [LegacyRemixBatchRecordV1]
    var lineage: RemixLineage
    var workspace: RemixWorkspaceState
    var selectedLineageNodeID: String?
    var crossoverSettings: RemixCrossoverSettings
    var activity: RemixActivityState
    var compileDiagnosticsByNodeID: [String: String]?
    var pendingParentRequest: RemixParentRequestSnapshot?
    var transcript: [String]
}
