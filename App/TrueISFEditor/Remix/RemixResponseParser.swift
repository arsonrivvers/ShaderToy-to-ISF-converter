import Foundation

/// Pulls the ISF .fs source out of a model response: prefer a fenced ```glsl/```isf/``` block;
/// otherwise take from the first `/*{` header to the end. Returns nil if no ISF header is present.
enum RemixResponseParser {
    static func extractISF(_ text: String) -> String? {
        // 1) Fenced code block.
        if let fenced = firstFencedBlock(text), fenced.contains("/*{") {
            return fenced.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 2) Raw: from the first ISF header to the end.
        if let open = text.range(of: "/*{") {
            return String(text[open.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func firstFencedBlock(_ text: String) -> String? {
        guard let openFence = text.range(of: "```") else { return nil }
        // Skip the optional language tag on the opening fence line.
        let afterOpen = text[openFence.upperBound...]
        guard let newline = afterOpen.firstIndex(of: "\n") else { return nil }
        let body = afterOpen[afterOpen.index(after: newline)...]
        guard let closeFence = body.range(of: "```") else { return nil }
        return String(body[..<closeFence.lowerBound])
    }
}
