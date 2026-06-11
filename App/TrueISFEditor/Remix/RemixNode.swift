import Foundation

enum RemixMode: String, Equatable, CaseIterable { case crossover, mutate }

struct RemixNode: Identifiable, Equatable {
    enum Status: Equatable { case generating, compiled, failed(String) }
    let id: String
    var isfSource: String
    var parents: [String]
    var mode: RemixMode
    var steer: String
    var directive: String
    var round: Int
    var status: Status = .generating
}
