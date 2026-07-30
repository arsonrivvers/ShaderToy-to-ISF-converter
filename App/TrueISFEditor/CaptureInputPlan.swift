import Foundation

/// Turns a `{"name": value}` map into the ordered `setInput(_:_:)` calls a capture needs.
///
/// Pure and separately tested because of one failure mode: these shaders are performance
/// instruments whose flash behaviour is driven by the operator, so screening them at DEFAULT
/// input values reports on a state nobody performs in. A mistyped input name that is silently
/// ignored produces exactly that — a confident report about the wrong configuration. Unknown
/// names are therefore a hard failure, named.
enum CaptureInputPlan {
    struct Entry: Equatable {
        let name: String
        /// A JSON *fragment* — what `MetalPreviewController.setInput(_:_:)` consumes.
        let jsonValue: String
    }

    /// Not `Result` — its failure type must conform to `Error`, and the only thing a caller
    /// wants here is a message to print before exiting non-zero.
    enum Outcome {
        case success([Entry])
        case failure(String)
    }

    static func parse(json: String, known: Set<String>) -> Outcome {
        guard let data = json.data(using: .utf8) else {
            return .failure("inputs are not valid UTF-8")
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .failure("inputs are not valid JSON: \(error.localizedDescription)")
        }
        guard let obj = parsed as? [String: Any] else {
            return .failure("inputs must be a JSON object of name -> value")
        }

        let unknown = obj.keys.filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            return .failure("unknown input name(s): \(unknown.joined(separator: ", "))")
        }

        var entries: [Entry] = []
        for name in obj.keys.sorted() {                  // sorted so logs are reproducible
            let value = obj[name]!
            // Re-encode each value on its own so it reaches setInput as the fragment type it
            // arrived as. A float must stay a float: an integer fragment routes to
            // ISFMSLSceneVal.create(withLong:) and sets the wrong value type on a float input.
            guard let d = try? JSONSerialization.data(withJSONObject: value,
                                                      options: [.fragmentsAllowed]),
                  var s = String(data: d, encoding: .utf8) else {
                return .failure("input \"\(name)\" has an unencodable value")
            }
            if let n = value as? NSNumber,
               CFNumberIsFloatType(n as CFNumber),
               !s.contains("."), !s.lowercased().contains("e"),
               s != "true", s != "false" {
                s += ".0"
            }
            entries.append(Entry(name: name, jsonValue: s))
        }
        return .success(entries)
    }
}
