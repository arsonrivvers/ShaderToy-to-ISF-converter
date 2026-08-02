import Foundation

enum RemixMode: String, Codable, Equatable, CaseIterable { case crossover, mutate }

struct RemixNode: Identifiable, Codable, Equatable {
    /// Schema-v1 execution states. Schema v2 decodes these only through
    /// `LegacyRemixSessionV1`; durable provider state belongs to `RemixChildRunRecord`.
    enum Status: Codable, Equatable {
        case generating
        case compiled
        case interrupted
        case failed(String)
    }
    let id: String
    var isfSource: String
    var parents: [String]
    var mode: RemixMode
    var steer: String
    var directive: String
    var round: Int
    var status: Status = .generating
    var label: String? = nil          // display name for seeds (library name / "editor" / "pasted")

    init(
        id: String,
        isfSource: String,
        parents: [String],
        mode: RemixMode,
        steer: String,
        directive: String,
        round: Int,
        status: Status = .generating,
        label: String? = nil
    ) {
        self.id = id
        self.isfSource = isfSource
        self.parents = parents
        self.mode = mode
        self.steer = steer
        self.directive = directive
        self.round = round
        self.status = status
        self.label = label
    }

    /// The only schema-v2 artifact constructor. Execution and failure states are never artifacts.
    init(
        artifactID: String,
        isfSource: String,
        parents: [String],
        mode: RemixMode,
        steer: String,
        directive: String,
        round: Int,
        label: String? = nil
    ) {
        self.init(
            id: artifactID,
            isfSource: isfSource,
            parents: parents,
            mode: mode,
            steer: steer,
            directive: directive,
            round: round,
            status: .compiled,
            label: label
        )
    }
}
