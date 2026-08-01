import Foundation

/// Recovers an empty legacy node only from its own humanized transcript entries.
enum RemixLegacyRecovery {
    static func candidate(childID: String, transcript: [String]) -> String? {
        let prefix = "[\(childID)] "
        for entry in transcript where entry.hasPrefix(prefix) {
            let response = String(entry.dropFirst(prefix.count))
            if case .success(let source) = RemixResponseParser.extractCandidate(response) {
                return source
            }
        }
        return nil
    }
}
