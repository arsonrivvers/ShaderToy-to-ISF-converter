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
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        let fences = fencedRegions(in: normalizedText)
        var diagnostics: [Diagnostic] = []

        // A complete fenced ISF is preferred over prose/raw material. Continue past invalid fences:
        // a later complete, valid shader is still authoritative.
        for fence in fences.complete {
            let scan = candidates(in: String(normalizedText[fence.body]))
            if let source = scan.source {
                return .success(source)
            }
            diagnostics.append(contentsOf: scan.errors.map {
                Diagnostic(error: $0, location: fence.range.lowerBound)
            })
        }

        // Raw recovery is deliberately restricted to text outside every examined fenced region.
        // In particular, the body of an unterminated shader fence cannot be reclassified as raw.
        for raw in unfencedRegions(in: normalizedText, excluding: fences.all) {
            let scan = candidates(in: String(normalizedText[raw]))
            if let source = scan.source {
                return .success(source)
            }
            diagnostics.append(contentsOf: scan.errors.map {
                Diagnostic(error: $0, location: raw.lowerBound)
            })
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

    private static func candidates(in text: String) -> CandidateScan {
        let headers = headerCandidates(in: text)
        guard !headers.isEmpty else {
            return CandidateScan(
                source: nil,
                errors: text.contains("/*{") ? [.invalidHeader(malformedHeaderMessage)] : []
            )
        }

        var errors: [RemixResponseError] = []
        for (index, header) in headers.enumerated() {
            guard header.isClosed else {
                errors.append(.invalidHeader(malformedHeaderMessage))
                continue
            }

            let end = index + 1 < headers.count
                ? headers[index + 1].range.lowerBound
                : text.endIndex
            let source = String(text[header.range.lowerBound..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                _ = try ISFHeader.parse(source)
            } catch {
                errors.append(.invalidHeader(malformedHeaderMessage))
                continue
            }

            if hasCompleteShaderBody(source) {
                return CandidateScan(source: source, errors: errors)
            }
            errors.append(.incompleteSource)
        }
        return CandidateScan(source: nil, errors: errors)
    }

    private static func hasCompleteShaderBody(_ source: String) -> Bool {
        guard let headerRange = ISFHeader.blockRange(in: source) else { return false }
        let tokens = glslTokens(in: source[headerRange.upperBound...])

        for index in tokens.indices {
            guard tokens[index] == .identifier("void"),
                  index + 2 < tokens.count,
                  tokens[index + 1] == .identifier("main"),
                  tokens[index + 2] == .symbol("(")
            else {
                continue
            }

            var signatureDepth = 1
            var cursor = index + 3
            while cursor < tokens.count, signatureDepth > 0 {
                switch tokens[cursor] {
                case .symbol("("):
                    signatureDepth += 1
                case .symbol(")"):
                    signatureDepth -= 1
                default:
                    break
                }
                cursor += 1
            }

            guard signatureDepth == 0,
                  cursor < tokens.count,
                  tokens[cursor] == .symbol("{")
            else {
                continue
            }

            var bodyDepth = 1
            cursor += 1
            while cursor < tokens.count, bodyDepth > 0 {
                switch tokens[cursor] {
                case .symbol("{"):
                    bodyDepth += 1
                case .symbol("}"):
                    bodyDepth -= 1
                default:
                    break
                }
                cursor += 1
            }
            if bodyDepth == 0 {
                return true
            }
        }
        return false
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

    private struct CandidateScan {
        let source: String?
        let errors: [RemixResponseError]
    }

    private struct HeaderCandidate {
        let range: Range<String.Index>
        let isClosed: Bool
    }

    private struct FenceRegions {
        var complete: [(range: Range<String.Index>, body: Range<String.Index>)] = []
        var incompleteShaderFences: [String.Index] = []
        var all: [Range<String.Index>] = []
    }

    private static func fencedRegions(in text: String) -> FenceRegions {
        var regions = FenceRegions()
        var lineStart = text.startIndex
        var opening: (location: String.Index, bodyStart: String.Index)?

        while true {
            let lineEnd = text.range(of: "\n", range: lineStart..<text.endIndex)?.lowerBound ?? text.endIndex
            let contentEnd: String.Index
            if lineEnd > lineStart,
               text[text.index(before: lineEnd)] == "\r" {
                contentEnd = text.index(before: lineEnd)
            } else {
                contentEnd = lineEnd
            }
            let line = text[lineStart..<contentEnd]

            if let activeOpening = opening {
                if isFenceClosingLine(line) {
                    let rangeEnd = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                    let range = activeOpening.location..<rangeEnd
                    regions.complete.append((range: range, body: activeOpening.bodyStart..<lineStart))
                    regions.all.append(range)
                    opening = nil
                }
            } else if isFenceOpeningLine(line) {
                let bodyStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                opening = (lineStart, bodyStart)
            }

            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }

        if let opening {
            let range = opening.location..<text.endIndex
            if text[range].contains("/*{") {
                regions.incompleteShaderFences.append(opening.location)
            }
            regions.all.append(range)
        }
        return regions
    }

    private static func headerCandidates(in text: String) -> [HeaderCandidate] {
        var candidates: [HeaderCandidate] = []
        var cursor = text.startIndex

        while let opening = text.range(of: "/*", range: cursor..<text.endIndex) {
            let bodyStart = opening.upperBound
            guard let closing = text.range(of: "*/", range: bodyStart..<text.endIndex) else {
                if text[bodyStart...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix("{") {
                    candidates.append(HeaderCandidate(range: opening.lowerBound..<text.endIndex, isClosed: false))
                }
                break
            }

            if text[bodyStart..<closing.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("{") {
                candidates.append(HeaderCandidate(range: opening.lowerBound..<closing.upperBound, isClosed: true))
            }
            cursor = closing.upperBound
        }
        return candidates
    }

    private static func isFenceOpeningLine(_ line: Substring) -> Bool {
        line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("```")
    }

    private static func isFenceClosingLine(_ line: Substring) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("```") else { return false }
        return trimmed.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private enum GLSLToken: Equatable {
        case identifier(String)
        case symbol(Character)
    }

    private static func glslTokens(in text: Substring) -> [GLSLToken] {
        var tokens: [GLSLToken] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let character = text[cursor]
            let next = text.index(after: cursor)

            if character == "/", next < text.endIndex, text[next] == "/" {
                cursor = text.range(of: "\n", range: next..<text.endIndex)
                    .map { text.index(after: $0.lowerBound) } ?? text.endIndex
                continue
            }
            if character == "/", next < text.endIndex, text[next] == "*" {
                let commentStart = text.index(after: next)
                guard let closing = text.range(of: "*/", range: commentStart..<text.endIndex) else {
                    break
                }
                cursor = closing.upperBound
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                cursor = next
                while cursor < text.endIndex {
                    if text[cursor] == "\\" {
                        cursor = text.index(after: cursor)
                        if cursor < text.endIndex {
                            cursor = text.index(after: cursor)
                        }
                    } else if text[cursor] == quote {
                        cursor = text.index(after: cursor)
                        break
                    } else {
                        cursor = text.index(after: cursor)
                    }
                }
                continue
            }
            if character == "#" {
                cursor = text.range(of: "\n", range: cursor..<text.endIndex)
                    .map { text.index(after: $0.lowerBound) } ?? text.endIndex
                continue
            }
            if isIdentifierStart(character) {
                var end = next
                while end < text.endIndex, isIdentifierContinuation(text[end]) {
                    end = text.index(after: end)
                }
                tokens.append(.identifier(String(text[cursor..<end])))
                cursor = end
                continue
            }
            if character == "(" || character == ")" || character == "{" || character == "}" {
                tokens.append(.symbol(character))
            }
            cursor = next
        }
        return tokens
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
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
