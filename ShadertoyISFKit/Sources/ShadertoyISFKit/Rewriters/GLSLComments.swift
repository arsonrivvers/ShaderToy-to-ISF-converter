import Foundation

/// Blanks comment CONTENT (spaces for every non-newline character) so detection scans see only
/// real code — `// TODO try iChannel2` must not invent a stub input. Offsets and newlines are
/// preserved, and the `//` / `/*` `*/` markers are kept, so positions map back to the original.
///
/// Detection-only: rewrites never consume this output. (M19 interim — this is the seed of the
/// M3 shared-scanner consolidation; when that lands, this folds into it.)
enum GLSLComments {
    static func strip(_ code: String) -> String {
        var out = ""
        out.reserveCapacity(code.count)
        let chars = Array(code)
        var i = 0
        var inLine = false, inBlock = false
        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if inLine {
                if c == "\n" { inLine = false; out.append(c) } else { out.append(" ") }
                i += 1; continue
            }
            if inBlock {
                if c == "*" && next == "/" { inBlock = false; out += "*/"; i += 2; continue }
                out.append(c == "\n" ? "\n" : " "); i += 1; continue
            }
            if c == "/" && next == "/" { inLine = true; out += "//"; i += 2; continue }
            if c == "/" && next == "*" { inBlock = true; out += "/*"; i += 2; continue }
            out.append(c); i += 1
        }
        return out
    }
}
