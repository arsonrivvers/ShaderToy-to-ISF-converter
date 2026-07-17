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
        case .suggestionGoals:
            return common + "\n" + """
            Before suggesting edits, identify 4-5 useful goals tailored to THIS shader. Mix practical \
            performability goals and creative evolution goals when the source supports them. \
            Schema: {"goals": [ {"id": string, "title": string, "detail": string, "kind": string, \
            "whyThisShader": string} ]}. The "whyThisShader" field must cite a concrete property of the \
            provided shader, not generic advice.
            """
        case .suggestions(goal: _):
            return common + "\n" + """
            Suggest creative evolutions scoped ONLY to the selected goal. Identify hardcoded constants that \
            could become interactive ISF INPUTS when relevant, and ways the visual design could develop. \
            Schema: {"goal": string, "ideas": [ {"id": string, "title": string, "detail": string, \
            "kind": string (one of: make-interactive, design, technique, perf), "lines": [int] or null, \
            "impact": string or null} ]}.
            """
        case .applySuggestions(goal: _, selectedIdeas: _):
            return common + "\n" + """
            Implement the selected suggestions as ONE coordinated shader rewrite. Return a complete valid ISF \
            source file in "replacementSource"; do not return line patches. Preserve valid ISF JSON header \
            syntax, existing inputs, passes, and image inputs unless the selected suggestions require a change. \
            Preserve the shader's visual identity unless the selected goal explicitly asks for transformation. \
            Schema: {"explanation": string, "replacementSource": string, "changedLines": [int]}.
            """
        case .research(request: _):
            return common + "\n" + """
            The user wants to explore an upgrade direction for this shader. Dig through the loaded skill \
            knowledge (isf-shader-development, shader-dev, and the technique catalog when present) and \
            propose 3-6 concrete, implementable upgrades that serve the request. Each idea must name the \
            technique in "title", and in "detail" describe specifically how it would be applied to THIS \
            shader — cite its actual passes, inputs, or functions, not generic advice. Rank the best idea \
            first and rate each idea's visual payoff in "impact". \
            Schema: {"goal": string (the user's request), "ideas": [ {"id": string, "title": string, \
            "detail": string, "kind": string (one of: make-interactive, design, technique, perf), \
            "lines": [int] or null, "impact": string or null} ]}.
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

        let header: String
        switch task {
        case .diagnoseAndFix:
            header = "Diagnose and fix the compile/diagnostic issues in this ISF shader."
        case .suggestionGoals:
            header = "Suggest 4-5 improvement goals tailored to this ISF shader before proposing edits."
        case .suggestions(let goal):
            header = "Suggest actionable changes for this ISF shader.\nGoal: \(goal)"
        case .applySuggestions(let goal, let selectedIdeas):
            let ideasJSON = selectedIdeasJSON(selectedIdeas)
            header = """
            Implement the selected ShaderAssist suggestions in one coordinated rewrite.
            Goal: \(goal)
            Selected suggestions JSON:
            \(ideasJSON)
            Return the full replacement source in "replacementSource".
            """
        case .research(let request):
            header = "Research upgrade directions for this ISF shader using the loaded skill knowledge.\nRequest: \(request)"
        }

        return """
        \(header)

        SHADER (numbered, 1-based):
        \(numbered)

        CURRENT DIAGNOSTICS:
        \(diagText)
        """
    }

    private static func selectedIdeasJSON(_ ideas: [AIIdea]) -> String {
        guard let data = try? JSONEncoder().encode(ideas),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}
