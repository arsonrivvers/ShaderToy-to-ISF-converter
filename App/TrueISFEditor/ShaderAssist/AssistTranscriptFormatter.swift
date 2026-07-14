import Foundation

/// Turns the CLI's raw stream-JSON lines into human Activity-pane lines (N28). End users were
/// seeing 28 lines of `{"ephemeral_5m_input_tokens":…,"costUSD":…,"uuid":…}` — dev noise on a
/// user surface. Pure function → unit-testable. Returns nil for lines that should be dropped.
enum AssistTranscriptFormatter {
    static func display(_ rawLine: String) -> String? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not stream-JSON (CLI stderr, plain progress text) — show as-is unless empty.
            return trimmed.isEmpty ? nil : trimmed
        }

        switch obj["type"] as? String {
        case "system":
            // Session init: surface the model once; drop other system chatter.
            guard obj["subtype"] as? String == "init" else { return nil }
            let model = (obj["model"] as? String).map { " · \($0)" } ?? ""
            return "session started\(model)"
        case "assistant":
            // Show the assistant's own words + which tools it reaches for.
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            let parts: [String] = content.compactMap { block in
                switch block["type"] as? String {
                case "text":
                    let t = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (t?.isEmpty == false) ? t : nil
                case "tool_use":
                    return (block["name"] as? String).map { "→ \($0)" }
                default:
                    return nil
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        case "result":
            // Human closing line; the token/cost internals stay out of the user surface.
            var line = "done"
            if let ms = obj["duration_ms"] as? Double {
                line += String(format: " in %.1fs", ms / 1000.0)
            }
            if obj["is_error"] as? Bool == true { line = "failed" + line.dropFirst(4) }
            return line
        default:
            // user-echo, content deltas, unknown stream types: drop.
            return nil
        }
    }
}
