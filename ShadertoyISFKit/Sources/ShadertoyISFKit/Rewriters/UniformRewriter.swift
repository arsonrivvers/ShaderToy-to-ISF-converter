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

    public static func rewrite(_ code: String) -> String {
        var out = code

        // iChannelResolution[N] has no ISF equivalent (ISF exposes no per-channel resolution uniform).
        // Consume the whole indexed access — index included — and map it to vec3(RENDERSIZE, 1.0):
        // mapping the bare word would leave a dangling `[N]` that mis-indexes the constructor (and
        // `[N].xy` on a float would not compile). Exact for buffer channels (ISF buffers are
        // RENDERSIZE); an approximation for image inputs. Runs before the word rules so nothing of the
        // `iChannelResolution` token survives for those to touch.
        let chanRes = try! NSRegularExpression(pattern: "iChannelResolution\\s*\\[[^\\[\\]]*\\]")
        out = chanRes.stringByReplacingMatches(
            in: out, range: NSRange(out.startIndex..<out.endIndex, in: out),
            withTemplate: NSRegularExpression.escapedTemplate(for: "vec3(RENDERSIZE, 1.0)"))

        // iChannelTime[N] (per-channel playback time in seconds, for video/audio inputs) has no ISF
        // equivalent — map the whole indexed access to TIME (ISF's global clock). Same index-consuming
        // reason as iChannelResolution. A close approximation: it loses any per-channel playback offset,
        // which almost no shader depends on.
        let chanTime = try! NSRegularExpression(pattern: "iChannelTime\\s*\\[[^\\[\\]]*\\]")
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
