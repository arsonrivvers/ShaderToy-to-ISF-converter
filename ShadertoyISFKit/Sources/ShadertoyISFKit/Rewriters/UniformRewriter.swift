import Foundation

public enum UniformRewriter {
    // Longest names first so substring rules can't clobber longer tokens.
    private static let rules: [(String, String)] = [
        ("iResolution", "vec3(RENDERSIZE, 1.0)"),
        ("iTimeDelta", "max(TIMEDELTA, 1e-4)"),
        ("iSampleRate", "44100.0"),
        ("iFrameRate", "60.0"),
        ("iTime", "TIME"),
        ("iFrame", "FRAMEINDEX"),
        ("iDate", "DATE"),
    ]

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
