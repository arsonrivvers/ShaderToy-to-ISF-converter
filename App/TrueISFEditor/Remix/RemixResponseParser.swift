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
        var hasPriorCandidateEvidence = false
        let headers = headerCandidates(in: text).filter { header in
            // An initial candidate must begin outside lexical content. After any real candidate
            // evidence, retain the incident-recovery exception for a physically line-leading,
            // semantic header; independent completeness still gates its later promotion.
            if header.isLexicallyStandalone {
                hasPriorCandidateEvidence = true
                return true
            }
            return hasPriorCandidateEvidence
                && header.isContractHeader
                && header.isLineLeading
        }
        guard !headers.isEmpty else {
            return CandidateScan(source: nil, errors: [])
        }

        var errors: [RemixResponseError] = []
        let hardBoundaries = headers.compactMap { header in
            header.isContractHeader ? header.headerRange : nil
        }
        let lineLeadingBoundaryStarts = Set(headers.compactMap { header -> String.Index? in
            guard header.isContractHeader, header.isLineLeading else { return nil }
            return header.headerRange?.lowerBound
        })
        let independentlyCompleteBoundaries = independentlyCompleteContractStarts(
            in: text,
            boundaries: hardBoundaries,
            eligibleStarts: lineLeadingBoundaryStarts
        )
        let firstValidHeader = headers.compactMap(\.headerRange).first
        for header in headers {
            guard let headerRange = header.headerRange else {
                // Once a parsed header has begun a candidate, later malformed object comments are
                // shader text. Only malformed markers before the first candidate are diagnostics.
                if firstValidHeader.map({ header.location < $0.lowerBound }) ?? true {
                    errors.append(.invalidHeader(malformedHeaderMessage))
                }
                continue
            }

            let end = semanticEnd(
                for: headerRange,
                in: text,
                boundaries: hardBoundaries,
                independentlyCompleteStarts: independentlyCompleteBoundaries
            )
            let source = String(text[headerRange.lowerBound..<end])
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
        let logicalBody = phase2Spliced(source[headerRange.upperBound...]).text
        let scan = glslScan(in: logicalBody[...])
        guard scan.isComplete, hasBalancedBraces(scan.tokens) else { return false }
        let tokens = scan.tokens

        var candidateDepth = 0
        for index in tokens.indices {
            let token = tokens[index]
            guard candidateDepth == 0,
                  token == .identifier("void"),
                  index + 2 < tokens.count,
                  tokens[index + 1] == .identifier("main"),
                  tokens[index + 2] == .symbol("(")
            else {
                if token == .symbol("{") {
                    candidateDepth += 1
                } else if token == .symbol("}") {
                    candidateDepth -= 1
                }
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

    private static func hasBalancedBraces(_ tokens: [GLSLToken]) -> Bool {
        var depth = 0
        for token in tokens {
            if token == .symbol("{") {
                depth += 1
            } else if token == .symbol("}") {
                guard depth > 0 else { return false }
                depth -= 1
            }
        }
        return depth == 0
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
        let location: String.Index
        let headerRange: Range<String.Index>?
        let isContractHeader: Bool
        let isLineLeading: Bool
        let isLexicallyStandalone: Bool
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
            let isLexicallyStandalone = isCandidateStartLexicallyStandalone(
                opening.lowerBound,
                in: text
            )
            guard let closing = text.range(of: "*/", range: bodyStart..<text.endIndex) else {
                if text[bodyStart...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix("{") {
                    candidates.append(HeaderCandidate(
                        location: opening.lowerBound,
                        headerRange: nil,
                        isContractHeader: false,
                        isLineLeading: isLineLeading(opening.lowerBound, in: text),
                        isLexicallyStandalone: isLexicallyStandalone
                    ))
                }
                break
            }

            let range = opening.lowerBound..<closing.upperBound
            let comment = String(text[range])
            if text[bodyStart..<closing.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("{") {
                if let parsedHeader = try? ISFHeader.parse(comment) {
                    candidates.append(HeaderCandidate(
                        location: opening.lowerBound,
                        headerRange: range,
                        isContractHeader: parsedHeader.extra["ISFVSN"] != nil,
                        isLineLeading: isLineLeading(opening.lowerBound, in: text),
                        isLexicallyStandalone: isLexicallyStandalone
                    ))
                    cursor = closing.upperBound
                    continue
                }
                candidates.append(HeaderCandidate(
                    location: opening.lowerBound,
                    headerRange: nil,
                    isContractHeader: false,
                    isLineLeading: isLineLeading(opening.lowerBound, in: text),
                    isLexicallyStandalone: isLexicallyStandalone
                ))
            }
            // A malformed opener may contain a later real header before the next `*/`.
            // Advance only past this opener so that later candidates are discovered independently.
            cursor = opening.upperBound
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

    private struct GLSLScan {
        let tokens: [GLSLToken]
        let isComplete: Bool
    }

    private struct Phase2Text {
        let text: String
        let markerOffset: Int?
    }

    /// Removes strict backslash-newline pairs before any lexical classification while retaining
    /// an optional original-source position in the resulting logical character stream.
    private static func phase2Spliced(
        _ source: Substring,
        marking marker: String.Index? = nil
    ) -> Phase2Text {
        var characters: [Character] = []
        characters.reserveCapacity(source.count)
        var markerOffset: Int?
        var cursor = source.startIndex

        while cursor < source.endIndex {
            if cursor == marker {
                markerOffset = characters.count
            }

            let next = source.index(after: cursor)
            if source[cursor] == "\\", next < source.endIndex, source[next] == "\n" {
                cursor = source.index(after: next)
                continue
            }

            characters.append(source[cursor])
            cursor = next
        }
        if marker == source.endIndex {
            markerOffset = characters.count
        }
        return Phase2Text(text: String(characters), markerOffset: markerOffset)
    }

    private static func glslScan(in text: Substring) -> GLSLScan {
        guard hasCompleteLexicalRegions(in: text) else {
            return GLSLScan(tokens: [], isComplete: false)
        }

        var tokens: [GLSLToken] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let character = text[cursor]
            let next = text.index(after: cursor)

            if character == "/", next < text.endIndex, text[next] == "/" {
                cursor = scanLineComment(in: text, startingAt: cursor).end
                continue
            }
            if character == "/", next < text.endIndex, text[next] == "*" {
                let commentStart = text.index(after: next)
                guard let closing = text.range(of: "*/", range: commentStart..<text.endIndex) else {
                    return GLSLScan(tokens: tokens, isComplete: false)
                }
                cursor = closing.upperBound
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                cursor = next
                var closed = false
                while cursor < text.endIndex {
                    if text[cursor] == "\\" {
                        cursor = text.index(after: cursor)
                        if cursor < text.endIndex {
                            cursor = text.index(after: cursor)
                        }
                    } else if text[cursor] == quote {
                        cursor = text.index(after: cursor)
                        closed = true
                        break
                    } else {
                        cursor = text.index(after: cursor)
                    }
                }
                guard closed else {
                    return GLSLScan(tokens: tokens, isComplete: false)
                }
                continue
            }
            if character == "#" {
                let directive = scanPreprocessorDirective(in: text, startingAt: cursor)
                guard directive.isComplete else {
                    return GLSLScan(tokens: tokens, isComplete: false)
                }
                cursor = directive.end
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
        return GLSLScan(tokens: tokens, isComplete: true)
    }

    /// Checks comments and quoted regions before directive bodies are skipped for tokenization.
    /// This keeps directive braces inert without hiding an unterminated block comment inside one.
    private static func hasCompleteLexicalRegions(in text: Substring) -> Bool {
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let character = text[cursor]
            let next = text.index(after: cursor)

            if character == "/", next < text.endIndex, text[next] == "/" {
                cursor = scanLineComment(in: text, startingAt: cursor).end
                continue
            }
            if character == "/", next < text.endIndex, text[next] == "*" {
                let commentStart = text.index(after: next)
                guard let closing = text.range(of: "*/", range: commentStart..<text.endIndex) else {
                    return false
                }
                cursor = closing.upperBound
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                cursor = next
                var closed = false
                while cursor < text.endIndex {
                    if text[cursor] == "\\" {
                        cursor = text.index(after: cursor)
                        if cursor < text.endIndex {
                            cursor = text.index(after: cursor)
                        }
                    } else if text[cursor] == quote {
                        cursor = text.index(after: cursor)
                        closed = true
                        break
                    } else {
                        cursor = text.index(after: cursor)
                    }
                }
                guard closed else { return false }
                continue
            }
            cursor = next
        }
        return true
    }

    private struct PreprocessorDirectiveScan {
        let end: String.Index
        let isComplete: Bool
    }

    private struct LineCommentScan {
        let end: String.Index
        let endedAtNewline: Bool
    }

    /// Scans a line comment in the already phase-2-spliced logical character stream.
    private static func scanLineComment(
        in text: Substring,
        startingAt start: String.Index
    ) -> LineCommentScan {
        if let newline = text.range(of: "\n", range: start..<text.endIndex)?.lowerBound {
            return LineCommentScan(end: text.index(after: newline), endedAtNewline: true)
        }
        return LineCommentScan(end: text.endIndex, endedAtNewline: false)
    }

    private static func scanPreprocessorDirective(
        in text: Substring,
        startingAt start: String.Index
    ) -> PreprocessorDirectiveScan {
        var cursor = start
        while cursor < text.endIndex {
            let character = text[cursor]
            let next = text.index(after: cursor)

            if character == "/", next < text.endIndex, text[next] == "/" {
                let lineComment = scanLineComment(in: text, startingAt: cursor)
                return PreprocessorDirectiveScan(end: lineComment.end, isComplete: true)
            }
            if character == "/", next < text.endIndex, text[next] == "*" {
                let commentStart = text.index(after: next)
                guard let closing = text.range(of: "*/", range: commentStart..<text.endIndex) else {
                    return PreprocessorDirectiveScan(end: text.endIndex, isComplete: false)
                }
                cursor = closing.upperBound
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                cursor = next
                var closed = false
                while cursor < text.endIndex {
                    if text[cursor] == "\\" {
                        cursor = text.index(after: cursor)
                        if cursor < text.endIndex {
                            cursor = text.index(after: cursor)
                        }
                    } else if text[cursor] == quote {
                        cursor = text.index(after: cursor)
                        closed = true
                        break
                    } else if text[cursor] == "\n" {
                        return PreprocessorDirectiveScan(end: cursor, isComplete: false)
                    } else {
                        cursor = text.index(after: cursor)
                    }
                }
                guard closed else {
                    return PreprocessorDirectiveScan(end: text.endIndex, isComplete: false)
                }
                continue
            }
            if character == "\\" {
                guard next < text.endIndex else {
                    return PreprocessorDirectiveScan(end: text.endIndex, isComplete: false)
                }
            }
            if character == "\n" {
                return PreprocessorDirectiveScan(end: next, isComplete: true)
            }
            cursor = next
        }
        return PreprocessorDirectiveScan(end: text.endIndex, isComplete: true)
    }

    private static func independentlyCompleteContractStarts(
        in text: String,
        boundaries: [Range<String.Index>],
        eligibleStarts: Set<String.Index>
    ) -> Set<String.Index> {
        var completeStarts = Set<String.Index>()

        for boundary in boundaries.reversed() {
            let end = semanticEnd(
                for: boundary,
                in: text,
                boundaries: boundaries,
                independentlyCompleteStarts: completeStarts
            )
            let source = String(text[boundary.lowerBound..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard (try? ISFHeader.parse(source)) != nil else { continue }
            if eligibleStarts.contains(boundary.lowerBound), hasCompleteShaderBody(source) {
                completeStarts.insert(boundary.lowerBound)
            }
        }
        return completeStarts
    }

    private static func semanticEnd(
        for header: Range<String.Index>,
        in text: String,
        boundaries: [Range<String.Index>],
        independentlyCompleteStarts: Set<String.Index>
    ) -> String.Index {
        boundaries.first(where: { boundary in
            boundary.lowerBound > header.lowerBound
                && (independentlyCompleteStarts.contains(boundary.lowerBound)
                    || isTopLevelBoundary(boundary.lowerBound, in: text, after: header.upperBound))
        })?.lowerBound ?? text.endIndex
    }

    private static func isCandidateStartLexicallyStandalone(
        _ location: String.Index,
        in text: String
    ) -> Bool {
        let logical = phase2Spliced(text[...], marking: location)
        guard let markerOffset = logical.markerOffset else { return false }
        let boundary = logical.text.index(logical.text.startIndex, offsetBy: markerOffset)
        var cursor = logical.text.startIndex

        while cursor < boundary {
            let character = logical.text[cursor]
            let next = logical.text.index(after: cursor)

            if character == "/", next < boundary, logical.text[next] == "/" {
                let lineComment = scanLineComment(
                    in: logical.text[cursor...],
                    startingAt: cursor
                )
                guard lineComment.endedAtNewline, lineComment.end <= boundary else { return false }
                cursor = lineComment.end
                continue
            }
            if character == "/", next < boundary, logical.text[next] == "*" {
                guard let closing = logical.text.range(
                    of: "*/",
                    range: next..<logical.text.endIndex
                ), closing.upperBound <= boundary else { return false }
                cursor = closing.upperBound
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                cursor = next
                var ended = false
                while cursor < boundary {
                    if logical.text[cursor] == "\\" {
                        cursor = logical.text.index(after: cursor)
                        guard cursor < boundary else { return false }
                        cursor = logical.text.index(after: cursor)
                    } else if logical.text[cursor] == quote {
                        cursor = logical.text.index(after: cursor)
                        ended = true
                        break
                    } else if logical.text[cursor] == "\n" {
                        cursor = logical.text.index(after: cursor)
                        ended = true
                        break
                    } else {
                        cursor = logical.text.index(after: cursor)
                    }
                }
                guard ended else { return false }
                continue
            }
            if character == "#" {
                let directive = scanPreprocessorDirective(
                    in: logical.text[cursor...],
                    startingAt: cursor
                )
                guard directive.isComplete, directive.end <= boundary else { return false }
                cursor = directive.end
                continue
            }
            cursor = next
        }
        return true
    }

    private static func isTopLevelBoundary(
        _ boundary: String.Index,
        in text: String,
        after start: String.Index
    ) -> Bool {
        let logical = phase2Spliced(text[start...], marking: boundary)
        guard let markerOffset = logical.markerOffset else { return false }
        let logicalBoundary = logical.text.index(
            logical.text.startIndex,
            offsetBy: markerOffset
        )
        return isTopLevelBoundary(
            logicalBoundary,
            inPhase2Text: logical.text,
            after: logical.text.startIndex
        )
    }

    private static func isTopLevelBoundary(
        _ boundary: String.Index,
        inPhase2Text text: String,
        after start: String.Index
    ) -> Bool {
        var cursor = start
        var braceDepth = 0

        while cursor < boundary {
            let character = text[cursor]
            let next = text.index(after: cursor)

            if character == "/", next < boundary, text[next] == "/" {
                let lineComment = scanLineComment(
                    in: text[cursor...],
                    startingAt: cursor
                )
                guard lineComment.endedAtNewline, lineComment.end <= boundary else { return false }
                cursor = lineComment.end
                continue
            }
            if character == "/", next < boundary, text[next] == "*" {
                guard let closing = text.range(
                    of: "*/",
                    range: next..<text.endIndex
                ), closing.upperBound <= boundary else { return false }
                cursor = closing.upperBound
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                cursor = next
                var closed = false
                while cursor < boundary {
                    if text[cursor] == "\\" {
                        cursor = text.index(after: cursor)
                        if cursor < boundary {
                            cursor = text.index(after: cursor)
                        }
                    } else if text[cursor] == quote {
                        cursor = text.index(after: cursor)
                        closed = true
                        break
                    } else {
                        cursor = text.index(after: cursor)
                    }
                }
                guard closed else { return false }
                continue
            }
            if character == "#" {
                let directive = scanPreprocessorDirective(in: text[cursor...], startingAt: cursor)
                guard directive.isComplete, directive.end <= boundary else { return false }
                cursor = directive.end
                continue
            }
            if character == "{" {
                braceDepth += 1
            } else if character == "}" {
                guard braceDepth > 0 else { return false }
                braceDepth -= 1
            }
            cursor = next
        }
        return braceDepth == 0
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isLineLeading(_ location: String.Index, in text: String) -> Bool {
        let lineStart = text[..<location].lastIndex(of: "\n")
            .map { text.index(after: $0) } ?? text.startIndex
        return text[lineStart..<location].allSatisfy { $0 == " " || $0 == "\t" }
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
