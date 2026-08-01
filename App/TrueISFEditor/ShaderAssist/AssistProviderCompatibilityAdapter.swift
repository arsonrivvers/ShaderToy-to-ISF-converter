import Foundation

enum AssistProviderCompatibilityAdapter {
    static func text(from result: AssistRunResult) -> String { result.response }

    static func legacyRawLine(_ line: String, envelopeType: String?) -> String? {
        if envelopeType == "stream_event" { return nil }
        return line
    }
}
