import Foundation

/// Assembles the ISF "knowledge preamble" fed to the assist providers (B4): the bodies of the
/// isf-shader-development + shader-dev skills, concatenated and length-capped. Falls back to a small
/// built-in primer if those files aren't present (e.g. another machine).
enum SkillPreamble {
    static let defaultPaths = [
        "\(NSHomeDirectory())/.claude/skills/isf-shader-development/SKILL.md",
        "\(NSHomeDirectory())/.claude/skills/shader-dev/SKILL.md",
    ]

    static func load(paths: [String] = defaultPaths, cap: Int = 12000) -> String {
        var parts: [String] = []
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let name = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            parts.append("## Skill: \(name)\n\n\(text)")
        }
        guard !parts.isEmpty else { return fallback }
        let combined = "# ISF authoring expertise (loaded skills)\n\n" + parts.joined(separator: "\n\n")
        return combined.count > cap ? String(combined.prefix(cap)) : combined
    }

    /// Minimal primer used when the skill files can't be read.
    static let fallback = """
    # ISF authoring expertise

    You are an expert in ISF (Interactive Shader Format) — the `.fs` shaders used by VDMX, CoGe and
    ISF Editor — and in GLSL technique. ISF files carry a `/*{ ... }*/` JSON header (ISFVSN, INPUTS,
    PASSES) followed by GLSL. Key host globals: RENDERSIZE, TIME, TIMEDELTA, FRAMEINDEX, PASSINDEX,
    IMG_NORM_PIXEL, IMG_THIS_PIXEL, isf_FragNormCoord. Filters declare an `inputImage` image INPUT;
    generators do not. Multi-pass shaders use PASSES with TARGET buffers (optionally PERSISTENT/FLOAT).
    Target GLSL ES 3.0 / Metal fidelity. Prefer minimal, correct, VDMX-compatible code.
    """
}
