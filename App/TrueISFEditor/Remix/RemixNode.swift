import Foundation

enum RemixMode: String, Codable, Equatable, CaseIterable { case crossover, mutate }

struct RemixNode: Identifiable, Codable, Equatable {
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
}
