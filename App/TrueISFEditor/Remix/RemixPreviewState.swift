import Foundation

struct RemixPreviewState: Codable, Equatable {
    static let maximumDiagnosticBytes = 256 * 1024

    enum Stage: String, Codable {
        case pending, available, failed
    }

    var stage: Stage
    var attempt: Int
    var diagnostic: String?
    var updatedAt: Date

    static func boundedDiagnostic(_ value: String) -> String {
        guard value.utf8.count > maximumDiagnosticBytes else { return value }
        var bytes = Data(value.utf8.prefix(maximumDiagnosticBytes))
        while !bytes.isEmpty {
            if let bounded = String(data: bytes, encoding: .utf8) {
                return bounded
            }
            bytes.removeLast()
        }
        return ""
    }

    func boundedForPersistence() -> RemixPreviewState {
        var bounded = self
        bounded.diagnostic = diagnostic.map(Self.boundedDiagnostic)
        return bounded
    }
}
