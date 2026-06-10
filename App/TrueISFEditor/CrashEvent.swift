import Foundation

/// One recorded failure: a caught compile/render error, or a hard crash ingested on next launch.
struct CrashEvent: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case compile, render, exception, signal }
    let id: UUID
    let timestamp: Date
    let kind: Kind
    let message: String
    let context: String?   // shader DESCRIPTION, when known
    let detail: String?    // backtrace / signal name

    init(id: UUID = UUID(), timestamp: Date = Date(), kind: Kind,
         message: String, context: String? = nil, detail: String? = nil) {
        self.id = id; self.timestamp = timestamp; self.kind = kind
        self.message = message; self.context = context; self.detail = detail
    }
}
