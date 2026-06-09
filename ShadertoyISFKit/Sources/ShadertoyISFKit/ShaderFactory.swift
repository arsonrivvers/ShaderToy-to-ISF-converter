import Foundation

/// Builds a `Shader` from raw GLSL pasted by the user (manual fallback when the
/// Cloudflare-gated fetch is unavailable).
public enum ShaderFactory {
    /// Single Image pass — the simplest paste path.
    public static func singlePass(imageCode: String, name: String = "Pasted Shader") -> Shader {
        let pass = RenderPass(
            inputs: [],
            outputs: [PassOutput(id: "out0", channel: 0)],
            code: imageCode,
            name: "Image",
            type: .image)
        let info = Info(id: "", name: name, username: nil, description: nil)
        return Shader(info: info, renderpass: [pass])
    }

    /// Builds a `Shader` from a single pasted blob that may contain multiple tabs
    /// delimited by markers: `// [Common]`, `// [Buffer A]`…`// [Buffer D]`, `// [Image]`.
    ///
    /// Pasted GLSL carries no channel-routing metadata (Shadertoy stores routing as UI
    /// config, not in the code), so bindings are inferred by convention: a pass that
    /// references `iChannelN` binds channel N to Buffer N (A=0, B=1, …) when that buffer
    /// was pasted, otherwise to a plain image input. Callers should warn the user to verify.
    ///
    /// With no recognized markers the whole text is treated as a single Image pass, so this
    /// is a safe drop-in for the previous single-pass paste behavior.
    public static func fromPaste(_ text: String, name: String = "Pasted Shader") -> Shader {
        let sections = parseSections(text)
        let info = Info(id: "", name: name, username: nil, description: nil)

        // No markers → the whole blob is the Image pass.
        guard !sections.isEmpty else {
            return Shader(info: info, renderpass: [
                RenderPass(inputs: [], outputs: [PassOutput(id: "out0", channel: 0)],
                           code: text, name: "Image", type: .image)
            ])
        }

        let letters = ["A", "B", "C", "D"]
        // Which buffer letters were actually pasted (ordered) and their stable output ids.
        let presentLetters = letters.filter { sections[.buffer($0)] != nil }
        var channelToBufferOutputID: [Int: String] = [:]
        for (index, letter) in presentLetters.enumerated() {
            channelToBufferOutputID[index] = "pasteBuf\(letter)_out"
        }

        var passes: [RenderPass] = []
        if let common = sections[.common] {
            passes.append(RenderPass(inputs: [], outputs: [], code: common,
                                     name: "Common", type: .common))
        }
        for letter in presentLetters {
            let code = sections[.buffer(letter)] ?? ""
            passes.append(RenderPass(
                inputs: inferInputs(code, channelToBufferOutputID: channelToBufferOutputID),
                outputs: [PassOutput(id: "pasteBuf\(letter)_out", channel: 0)],
                code: code, name: "Buffer \(letter)", type: .buffer))
        }
        // Image is required for a valid ISF generator; default to empty if the user omitted it.
        let imageCode = sections[.image] ?? ""
        passes.append(RenderPass(
            inputs: inferInputs(imageCode, channelToBufferOutputID: channelToBufferOutputID),
            outputs: [PassOutput(id: "pasteImage_out", channel: 0)],
            code: imageCode, name: "Image", type: .image))

        return Shader(info: info, renderpass: passes)
    }

    /// True if the pasted text contains any `// [Buffer X]` marker (i.e. it's multipass).
    public static func pasteContainsBuffers(_ text: String) -> Bool {
        let sections = parseSections(text)
        return ["A", "B", "C", "D"].contains { sections[.buffer($0)] != nil }
    }

    // MARK: - Marker parsing

    private enum Section: Hashable {
        case common, image, buffer(String)
    }

    /// Splits pasted text into sections keyed by tab marker. Returns empty when no markers
    /// are present (the caller then treats the whole blob as a single Image pass).
    private static func parseSections(_ text: String) -> [Section: String] {
        var result: [Section: String] = [:]
        var current: Section?
        var buffer: [Substring] = []

        func flush() {
            if let section = current {
                let code = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                // A later marker for the same tab appends rather than clobbers.
                if let existing = result[section], !existing.isEmpty {
                    result[section] = existing + "\n" + code
                } else {
                    result[section] = code
                }
            }
            buffer = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let marker = parseMarker(line) {
                flush()
                current = marker
            } else if current != nil {
                buffer.append(line)
            }
            // Lines before the first marker are ignored.
        }
        flush()
        return result
    }

    /// Matches a marker line like `// [Buffer A]`, `//[Common]`, `//  [ image ]` (case-insensitive).
    private static func parseMarker(_ line: Substring) -> Section? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("//") else { return nil }
        let afterSlashes = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard afterSlashes.hasPrefix("["), afterSlashes.hasSuffix("]") else { return nil }
        let label = afterSlashes.dropFirst().dropLast()
            .trimmingCharacters(in: .whitespaces).lowercased()
        if label == "common" { return .common }
        if label == "image" { return .image }
        if label.hasPrefix("buffer") {
            let rest = label.dropFirst("buffer".count).trimmingCharacters(in: .whitespaces).uppercased()
            if ["A", "B", "C", "D"].contains(rest) { return .buffer(rest) }
        }
        return nil
    }

    /// Builds the `PassInput` bindings for a pass by scanning its code for `iChannelN` usage.
    private static func inferInputs(_ code: String,
                                    channelToBufferOutputID: [Int: String]) -> [PassInput] {
        var inputs: [PassInput] = []
        for channel in 0...3 {
            guard code.range(of: "\\biChannel\(channel)\\b", options: .regularExpression) != nil
            else { continue }
            if let bufferOutputID = channelToBufferOutputID[channel] {
                inputs.append(PassInput(id: bufferOutputID, ctype: .buffer, channel: channel))
            } else {
                inputs.append(PassInput(id: "pasteImg\(channel)", ctype: .texture, channel: channel))
            }
        }
        return inputs
    }
}
