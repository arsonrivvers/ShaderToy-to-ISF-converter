import Foundation
public enum CoPilotResponseParser {
    public static func fixResult(fromClaudeStdout s: String) throws -> AIFixResult { try decode(AIFixResult.self, from: candidateJSON(s)) }
    public static func suggestions(fromClaudeStdout s: String) throws -> AISuggestionsResult { try decode(AISuggestionsResult.self, from: candidateJSON(s)) }
    private struct Envelope: Decodable { let result: String?; let is_error: Bool? }
    private static func candidateJSON(_ stdout: String) -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = trimmed
        if let data = trimmed.data(using: .utf8), let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            if env.is_error == true { return "" }
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
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { return String(text[start...i]) } }
            i = text.index(after: i)
        }
        return nil
    }
    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8), !json.isEmpty, let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw CoPilotParseError.unparseable(raw: json)
        }
        return value
    }
}
