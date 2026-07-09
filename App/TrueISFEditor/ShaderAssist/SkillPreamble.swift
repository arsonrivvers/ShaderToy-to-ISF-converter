import Foundation

/// Assembles the ISF "knowledge preamble" fed to the assist providers (B4): the bodies of the
/// isf-shader-development + shader-dev skills, concatenated and length-capped. Falls back to a small
/// built-in primer if those files aren't present (e.g. another machine).
enum SkillPreamble {
    /// One logical skill text: the user's live copy wins (the maker edits skills in
    /// `~/.claude/skills`), the app-bundled copy (`Resources/<name>.md`) is the floor every public
    /// install gets — without it, any machine but the maker's silently fell back to the tiny primer.
    /// Bundled copies are refreshed from `~/.claude/skills` at release time.
    struct SkillSource {
        let name: String       // section title AND bundled resource basename
        let userPath: String   // live override
    }

    static let defaultSources = [
        SkillSource(name: "isf-shader-development",
                    userPath: "\(NSHomeDirectory())/.claude/skills/isf-shader-development/SKILL.md"),
        SkillSource(name: "shader-dev",
                    userPath: "\(NSHomeDirectory())/.claude/skills/shader-dev/SKILL.md"),
    ]

    static let defaultPaths = [
        "\(NSHomeDirectory())/.claude/skills/isf-shader-development/SKILL.md",
        "\(NSHomeDirectory())/.claude/skills/shader-dev/SKILL.md",
    ]

    /// Safety ceiling on the assembled preamble length, in characters. This is an ARG_MAX guard —
    /// the preamble ships as a CLI argument to the claude/codex subprocess and macOS ARG_MAX is ≈1 MB —
    /// NOT a content budget. It must stay well above the real skill set so the SKILL.md files and the
    /// corpus catalog load in FULL. (Was 12,000, which silently truncated isf-shader-development
    /// mid-file and dropped shader-dev + the catalog entirely — the bug this constant fixes.)
    static let defaultCap = 200_000

    /// Source-based load: user path → bundled resource → skip; primer only if NOTHING loaded.
    static func load(sources: [SkillSource] = defaultSources, cap: Int = defaultCap) -> String {
        let parts = sources.compactMap { src in
            text(for: src).map { "## Skill: \(src.name)\n\n\($0)" }
        }
        guard !parts.isEmpty else { return fallback }
        let combined = "# ISF authoring expertise (loaded skills)\n\n" + parts.joined(separator: "\n\n")
        return combined.count > cap ? String(combined.prefix(cap)) : combined
    }

    static func text(for src: SkillSource) -> String? {
        if let t = try? String(contentsOfFile: src.userPath, encoding: .utf8),
           !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        if let url = Bundle.main.url(forResource: src.name, withExtension: "md"),
           let t = try? String(contentsOf: url, encoding: .utf8),
           !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        return nil
    }

    /// Path-only load (no bundle fallback) — kept for tests and explicit file lists.
    static func load(paths: [String], cap: Int = defaultCap) -> String {
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
