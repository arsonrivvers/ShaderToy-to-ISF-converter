import Foundation
public enum ShaderAssistPrompt {
    public static func system(for task: ShaderAssistTask) -> String {
        let common = """
        You are an ISF/GLSL shader co-pilot inside the TrueISFEditor app. The shader targets ISFMSLKit / \
        VDMX6 (Metal, GLSL ES 3.0 transpiled via SPIR-V). Use the `isf-shader-development` and `shader-dev` \
        skills and their knowledge. Line numbers are 1-based exactly as shown in the user message. \
        Respond with ONLY a single JSON object matching the schema below — no prose, no markdown fences.
        """
        switch task {
        case .diagnoseAndFix:
            return common + "\n" + """
            Schema: {"explanation": string (1-3 sentences), "edits": [ {"fromLine": int, "toLine": int, \
            "replacement": string (the full replacement text for those lines), "rationale": string} ]}. \
            If nothing needs fixing, return an empty "edits" array and explain why.
            """
        case .suggestions:
            return common + "\n" + """
            Suggest creative evolutions of this working shader. Identify hardcoded constants that could \
            become interactive ISF INPUTS, and ways the visual design could develop. \
            Schema: {"ideas": [ {"title": string, "detail": string, "kind": string \
            (one of: make-interactive, design, technique, perf), "lines": [int] or null} ]}.
            """
        }
    }
    public static func user(task: ShaderAssistTask, source: String, diagnostics: [Diagnostic]) -> String {
        let numbered = source.components(separatedBy: "\n").enumerated()
            .map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let diagText = diagnostics.isEmpty ? "(none)" :
            diagnostics.map { d in
                let loc = d.line.map { "line \($0)" } ?? "—"
                return "[\(d.severity)] \(loc): \(d.message)"
            }.joined(separator: "\n")
        let header = task == .diagnoseAndFix
            ? "Diagnose and fix the compile/diagnostic issues in this ISF shader."
            : "Suggest how this ISF shader could evolve (interactivity + visual design)."
        return """
        \(header)

        SHADER (numbered, 1-based):
        \(numbered)

        CURRENT DIAGNOSTICS:
        \(diagText)
        """
    }
}
