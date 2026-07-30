import Foundation

struct ISFPreviewInput: Identifiable, Equatable {
    let name: String
    let type: String          // "float","bool","color","point2D","long","image","event"
    let defaultValue: Any?
    let min: Any?
    let max: Any?
    let labels: [String]?     // long enum display names
    let values: [Double]?     // long enum underlying values
    var id: String { name }
    static func == (l: ISFPreviewInput, r: ISFPreviewInput) -> Bool { l.name == r.name && l.type == r.type }
}
