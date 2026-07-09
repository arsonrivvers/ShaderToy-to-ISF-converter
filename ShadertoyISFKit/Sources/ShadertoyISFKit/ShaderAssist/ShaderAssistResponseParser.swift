import Foundation
public enum ShaderAssistResponseParser {
    public static func fixResult(fromClaudeStdout s: String) throws -> AIFixResult { try decode(AIFixResult.self, from: candidateJSON(s)) }
    public static func suggestions(fromClaudeStdout s: String) throws -> AISuggestionsResult { try decode(AISuggestionsResult.self, from: candidateJSON(s)) }
    public static func suggestionGoals(fromClaudeStdout s: String) throws -> AISuggestionGoalsResult { try decode(AISuggestionGoalsResult.self, from: candidateJSON(s)) }
    public static func applyResult(fromClaudeStdout s: String) throws -> AIApplyResult { try decode(AIApplyResult.self, from: candidateJSON(s)) }
    private struct Envelope: Decodable { let result: String?; let is_error: Bool? }
    private static func candidateJSON(_ stdout: String) throws -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = trimmed
        if let data = trimmed.data(using: .utf8), let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            // Surface the CLI's own error text (quota, auth, timeout) — it lives in `result`.
            if env.is_error == true {
                throw ShaderAssistParseError.cliError(message: env.result ?? "CLI reported an error with no message")
            }
            if let r = env.result { text = r }
        }
        return extractObject(from: text) ?? text
    }
    private static func extractObject(from text: String) -> String? {
        if let fence = text.range(of: #"```json\s*(\{[\s\S]*?\})\s*```"#, options: .regularExpression) {
            let block = String(text[fence])
            if let inner = block.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) { return String(block[inner]) }
        }
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0; var i = start
        var inString = false
        var escaped = false
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...i]) }
            }
            i = text.index(after: i)
        }
        return nil
    }
    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8), !json.isEmpty else {
            throw ShaderAssistParseError.unparseable(raw: json)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as DecodingError {
            // Root-level dataCorrupted = the text isn't JSON at all → still "unparseable".
            // Anything deeper is real JSON of the wrong shape → carry the field-level detail.
            if case .dataCorrupted(let ctx) = e, ctx.codingPath.isEmpty {
                throw ShaderAssistParseError.unparseable(raw: json)
            }
            throw ShaderAssistParseError.malformed(detail: describe(e), raw: json)
        } catch {
            throw ShaderAssistParseError.unparseable(raw: json)
        }
    }

    /// Human-readable field-level reason for a DecodingError.
    private static func describe(_ e: DecodingError) -> String {
        func path(_ ctx: DecodingError.Context) -> String {
            ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let key, let ctx): return "missing key '\(key.stringValue)' at \(path(ctx))"
        case .typeMismatch(let t, let ctx):  return "type mismatch (expected \(t)) at \(path(ctx))"
        case .valueNotFound(let t, let ctx): return "null where \(t) expected at \(path(ctx))"
        case .dataCorrupted(let ctx):        return "data corrupted at \(path(ctx)): \(ctx.debugDescription)"
        @unknown default:                    return "\(e)"
        }
    }
}
