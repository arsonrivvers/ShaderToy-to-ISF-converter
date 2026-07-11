import Foundation

public enum UniformRewriter {
    // Longest names first so substring rules can't clobber longer tokens.
    private static let rules: [(String, String)] = [
        ("iResolution", "vec3(RENDERSIZE, 1.0)"),
        ("iTimeDelta", "max(TIMEDELTA, 1e-4)"),
        ("iSampleRate", "44100.0"),
        ("iFrameRate", "60.0"),
        // iMouse.xy is in pixels; ISF point2D `mouse` is normalized [0,1]. iMouse.zw is the click
        // position with sign signalling button-down; many shaders gate interaction on it
        // (`if (iMouse.z < 0.01) ...`). Mirror xy into zw (non-zero, "pressed") so the mouse input
        // actually drives those shaders. A standard rule (not a converter special case) so the
        // scope-aware Common path picks it up too.
        ("iMouse", "vec4(mouse * RENDERSIZE, mouse * RENDERSIZE)"),
        ("iTime", "TIME"),
        ("iFrame", "FRAMEINDEX"),
        ("iDate", "DATE"),
    ]

    /// Every Shadertoy uniform name this rewriter maps — used by the C5-interim detection of
    /// body-scope uses the scope-aware Common rewrite can't reach.
    static var detectableNames: [String] { rules.map(\.0) + ["iChannelResolution", "iChannelTime"] }

    /// Scope-aware uniform rewrite (C5/M20): rewrites every detectable Shadertoy uniform EXCEPT
    /// occurrences inside a function whose OWN parameter list declares that name (the author
    /// threads the uniform through as a parameter — substituting the mapped expression into the
    /// declaration or its uses would corrupt the code). File scope, directive bodies, and
    /// unshadowed function bodies all rewrite. Comment content is never rewritten.
    ///
    /// Replaces both the whole-string per-pass call (M20: paste-path helpers now protected) and
    /// CommonUniformRewriter's indiscriminate depth>0 protection (C5: unshadowed Common helper
    /// bodies now rewritten instead of shipping raw `iTime`).
    public static func rewriteScoped(_ code: String) -> String {
        let masked = GLSLScanner.strip(code)
        let mns = masked as NSString
        let defs = GLSLFunctionScanner.functionDefs(in: code)

        func isProtected(_ pos: Int, _ name: String) -> Bool {
            for d in defs where pos >= d.start && pos < d.end {
                return d.paramNames.contains(name)
            }
            return false
        }

        var edits: [(NSRange, String)] = []
        // Indexed forms first (same rationale as `rewrite`: consume the whole `name[…]` access;
        // ranges can't overlap the word rules — no rule name is a substring of these at `\b`).
        let indexed: [(name: String, pattern: String, replacement: String)] = [
            ("iChannelResolution", "iChannelResolution\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]",
             "vec3(RENDERSIZE, 1.0)"),
            ("iChannelTime", "iChannelTime\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]", "TIME"),
        ]
        for f in indexed {
            let re = try! NSRegularExpression(pattern: f.pattern)
            for m in re.matches(in: masked, range: NSRange(location: 0, length: mns.length))
            where !isProtected(m.range.location, f.name) {
                edits.append((m.range, f.replacement))
            }
        }
        // A word-rule uniform can sit INSIDE an indexed access's index (`iChannelResolution[iFrame % 2]`);
        // the indexed edit consumes the whole access, so a nested word edit would corrupt the output
        // when both are applied (M44).
        let claimed = edits.map(\.0)
        for (from, to) in rules {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b")
            for m in re.matches(in: masked, range: NSRange(location: 0, length: mns.length))
            where !isProtected(m.range.location, from)
                && !claimed.contains(where: { NSLocationInRange(m.range.location, $0) }) {
                edits.append((m.range, to))
            }
        }
        guard !edits.isEmpty else { return code }
        let out = NSMutableString(string: code)
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            out.replaceCharacters(in: range, with: replacement)
        }
        return out as String
    }

    /// Post-rewrite tripwire (replaces the C5-interim `unrewrittenBodyUniforms`): detectable
    /// uniform names still present (outside comments) in ALREADY-REWRITTEN code, excluding
    /// legitimate param-shadowed uses. Non-empty means something the scoped rewrite should have
    /// handled slipped through (e.g. a bare un-indexed iChannelResolution) — callers warn loudly.
    public static func unresolvedUniformUses(_ rewrittenCode: String) -> [String] {
        let masked = GLSLScanner.strip(rewrittenCode)
        let mns = masked as NSString
        let defs = GLSLFunctionScanner.functionDefs(in: rewrittenCode)
        var out: [String] = []
        for name in detectableNames {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            let hits = re.matches(in: masked, range: NSRange(location: 0, length: mns.length))
            let unresolved = hits.contains { m in
                let d = defs.first { m.range.location >= $0.start && m.range.location < $0.end }
                return !(d?.paramNames.contains(name) ?? false)
            }
            if unresolved { out.append(name) }
        }
        return out
    }

    public static func rewrite(_ code: String) -> String {
        var out = code

        // iChannelResolution[N] has no ISF equivalent (ISF exposes no per-channel resolution uniform).
        // Consume the whole indexed access — index included — and map it to vec3(RENDERSIZE, 1.0):
        // mapping the bare word would leave a dangling `[N]` that mis-indexes the constructor (and
        // `[N].xy` on a float would not compile). Exact for buffer channels (ISF buffers are
        // RENDERSIZE); an approximation for image inputs. Runs before the word rules so nothing of the
        // `iChannelResolution` token survives for those to touch.
        // One nesting level allowed in the index (`iChannelResolution[idx[0]]`) — a flat
        // `[^\[\]]*` fails on it and leaves the identifier undeclared.
        let chanRes = try! NSRegularExpression(pattern: "iChannelResolution\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]")
        out = chanRes.stringByReplacingMatches(
            in: out, range: NSRange(out.startIndex..<out.endIndex, in: out),
            withTemplate: NSRegularExpression.escapedTemplate(for: "vec3(RENDERSIZE, 1.0)"))

        // iChannelTime[N] (per-channel playback time in seconds, for video/audio inputs) has no ISF
        // equivalent — map the whole indexed access to TIME (ISF's global clock). Same index-consuming
        // reason as iChannelResolution. A close approximation: it loses any per-channel playback offset,
        // which almost no shader depends on.
        let chanTime = try! NSRegularExpression(pattern: "iChannelTime\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]")
        out = chanTime.stringByReplacingMatches(
            in: out, range: NSRange(out.startIndex..<out.endIndex, in: out),
            withTemplate: NSRegularExpression.escapedTemplate(for: "TIME"))

        for (from, to) in rules {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b"
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = regex.stringByReplacingMatches(in: out, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: to))
        }
        return out
    }
}
