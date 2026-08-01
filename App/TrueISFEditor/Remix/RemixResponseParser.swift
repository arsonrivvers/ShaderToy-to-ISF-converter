import Foundation
import ShadertoyISFKit

enum RemixResponseError: Error, Equatable {
    case noISFFound
    case incompleteFence
    case invalidHeader(String)
    case incompleteSource
}

/// Extracts exactly one complete ISF source from an authoritative provider response.
enum RemixResponseParser {
    private static let malformedHeaderMessage = "malformed ISF header"

    static func extractCandidate(_ text: String) -> Result<String, RemixResponseError> {
        let fences = fencedRegions(in: text)
        var diagnostics: [Diagnostic] = []

        // A complete fenced ISF is preferred over prose/raw material. Continue past invalid fences:
        // a later complete, valid shader is still authoritative.
        for fence in fences.complete {
            switch candidate(in: String(text[fence.body])) {
            case .success(let source):
                return .success(source)
            case .failure(let error):
                if error != .noISFFound {
                    diagnostics.append(Diagnostic(error: error, location: fence.range.lowerBound))
                }
            }
        }

        // Raw recovery is deliberately restricted to text outside every examined fenced region.
        // In particular, the body of an unterminated shader fence cannot be reclassified as raw.
        for raw in unfencedRegions(in: text, excluding: fences.all) {
            switch candidate(in: String(text[raw])) {
            case .success(let source):
                return .success(source)
            case .failure(let error):
                if error != .noISFFound {
                    diagnostics.append(Diagnostic(error: error, location: raw.lowerBound))
                }
            }
        }

        diagnostics.append(contentsOf: fences.incompleteShaderFences.map {
            Diagnostic(error: .incompleteFence, location: $0)
        })
        return failure(from: diagnostics)
    }

    /// Compatibility for callers that only need a source-or-nil answer.
    static func extractISF(_ text: String) -> String? {
        guard case .success(let source) = extractCandidate(text) else { return nil }
        return source
    }

    private static func candidate(in text: String) -> Result<String, RemixResponseError> {
        guard let headerRange = ISFHeader.blockRange(in: text) else {
            return text.contains("/*{")
                ? .failure(.invalidHeader(malformedHeaderMessage))
                : .failure(.noISFFound)
        }

        let source = String(text[headerRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try ISFHeader.parse(source)
        } catch {
            return .failure(.invalidHeader(malformedHeaderMessage))
        }

        guard hasCompleteShaderBody(source) else {
            return .failure(.incompleteSource)
        }
        return .success(source)
    }

    private static func hasCompleteShaderBody(_ source: String) -> Bool {
        guard let headerRange = ISFHeader.blockRange(in: source) else { return false }
        let body = source[headerRange.upperBound...]
        guard let main = body.range(of: "void main") else { return false }
        let function = body[main.lowerBound...]
        return function.contains("{") && function.contains("}")
    }

    private static func failure(from diagnostics: [Diagnostic]) -> Result<String, RemixResponseError> {
        if diagnostics.contains(where: { $0.error == .incompleteFence }) {
            return .failure(.incompleteFence)
        }
        if let invalid = diagnostics
            .filter({ if case .invalidHeader = $0.error { return true }; return false })
            .min(by: { $0.location < $1.location }) {
            return .failure(invalid.error)
        }
        if diagnostics.contains(where: { $0.error == .incompleteSource }) {
            return .failure(.incompleteSource)
        }
        return .failure(.noISFFound)
    }

    private struct Diagnostic {
        let error: RemixResponseError
        let location: String.Index
    }

    private struct FenceRegions {
        var complete: [(range: Range<String.Index>, body: Range<String.Index>)] = []
        var incompleteShaderFences: [String.Index] = []
        var all: [Range<String.Index>] = []
    }

    private static func fencedRegions(in text: String) -> FenceRegions {
        var regions = FenceRegions()
        var cursor = text.startIndex

        while let open = text.range(of: "```", range: cursor..<text.endIndex) {
            let afterOpen = open.upperBound
            guard let newline = text[afterOpen...].firstIndex(of: "\n") else { break }
            let bodyStart = text.index(after: newline)

            guard let close = text.range(of: "```", range: bodyStart..<text.endIndex) else {
                let body = text[bodyStart...]
                if body.contains("/*{") {
                    regions.incompleteShaderFences.append(open.lowerBound)
                }
                regions.all.append(open.lowerBound..<text.endIndex)
                break
            }

            let range = open.lowerBound..<close.upperBound
            regions.complete.append((range: range, body: bodyStart..<close.lowerBound))
            regions.all.append(range)
            cursor = close.upperBound
        }
        return regions
    }

    private static func unfencedRegions(
        in text: String,
        excluding fenced: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        var regions: [Range<String.Index>] = []
        var cursor = text.startIndex
        for range in fenced {
            if cursor < range.lowerBound {
                regions.append(cursor..<range.lowerBound)
            }
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            regions.append(cursor..<text.endIndex)
        }
        return regions
    }
}
