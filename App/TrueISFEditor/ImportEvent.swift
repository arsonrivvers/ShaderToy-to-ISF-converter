import Foundation

/// One Shadertoy import attempt (fetch → parse → convert), recorded into `ImportLog`.
struct ImportEvent: Codable, Equatable, Identifiable {
    enum FetchSource: String, Codable { case api, webView }
    enum Stage: String, Codable { case urlInvalid, fetched, parsed, converted, rendered }
    enum Outcome: String, Codable { case success, warning, error }

    var id = UUID()
    var timestamp = Date()
    let query: String
    let shaderID: String?
    let fetchSource: FetchSource
    let httpStatus: Int?
    let stage: Stage
    let outcome: Outcome
    let message: String
    let responseSnippet: String?
    let warningCount: Int

    /// One-line outcome for the import sheet. Pure; unit-tested.
    var summaryLine: String {
        switch outcome {
        case .success: return "✓ Converted"
        case .warning:
            let unit = warningCount == 1 ? "warning" : "warnings"
            return "✓ Converted (\(warningCount) \(unit))"
        case .error: return "✗ \(message)"
        }
    }
}
