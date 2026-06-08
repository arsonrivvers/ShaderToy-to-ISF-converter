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
