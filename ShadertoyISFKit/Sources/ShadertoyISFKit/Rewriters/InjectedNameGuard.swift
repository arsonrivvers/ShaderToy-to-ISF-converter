import Foundation

/// Renames user identifiers that collide with names the converter's OWN rewrites inject
/// references to — `mouse` (the ISF point2D input the iMouse rule expands to), `RENDERSIZE`,
/// `TIME`, `TIMEDELTA`, `FRAMEINDEX`, `DATE`, `PASSINDEX`.
///
/// Why: none of these names mean anything in Shadertoy GLSL, so ANY whole-word occurrence in the
/// ORIGINAL source is the user's identifier. Left alone, a user local `vec2 mouse = iMouse.xy`
/// shadows the ISF `mouse` input the moment the iMouse rewrite expands the initializer to
/// `vec4(mouse * RENDERSIZE, …)` — the initializer then reads the just-declared, uninitialized
/// local (tXfBz2's black import). Renaming to `usr_<name>` (the GLSLReservedIdentifierRewriter
/// convention) before ANY uniform rewriting makes shadowing impossible.
///
/// The decision is per-shader: if a name occurs (comment-masked) in any pass or Common, every
/// occurrence in ALL passes + Common is renamed, so cross-tab helper calls keep resolving.
public enum InjectedNameGuard {
    public struct Result {
        public let passBodies: [String]
        public let commonCode: String
        public let warnings: [ConversionWarning]
    }

    /// Names the converter's output references at user scope. `iChannelNimg`/buffer names are
    /// synthesized per-shader and can't pre-exist; ISF function names (IMG_NORM_PIXEL …) are
    /// syntactically impossible as Shadertoy user identifiers in practice — start narrow.
    static let guardedNames = ["mouse", "RENDERSIZE", "TIME", "TIMEDELTA",
                               "FRAMEINDEX", "DATE", "PASSINDEX"]

    public static func rewrite(passBodies: [String], commonCode: String) -> Result {
        let maskedBodies = passBodies.map { GLSLScanner.strip($0) }
        let maskedCommon = GLSLScanner.strip(commonCode)

        // Which guarded names occur as real (non-comment) identifiers anywhere in this shader?
        var colliding: [String] = []
        for name in guardedNames {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            let hit = (maskedBodies + [maskedCommon]).contains { masked in
                let mns = masked as NSString
                return re.firstMatch(in: masked, range: NSRange(location: 0, length: mns.length)) != nil
            }
            if hit { colliding.append(name) }
        }
        guard !colliding.isEmpty else {
            return Result(passBodies: passBodies, commonCode: commonCode, warnings: [])
        }

        func rename(_ code: String, _ masked: String) -> String {
            let mns = masked as NSString
            var edits: [(NSRange, String)] = []
            for name in colliding {
                let re = try! NSRegularExpression(
                    pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
                for m in re.matches(in: masked, range: NSRange(location: 0, length: mns.length)) {
                    edits.append((m.range, GLSLReservedIdentifierRewriter.prefix + name))
                }
            }
            guard !edits.isEmpty else { return code }
            let out = NSMutableString(string: code)
            for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
                out.replaceCharacters(in: range, with: replacement)
            }
            return out as String
        }

        let newBodies = zip(passBodies, maskedBodies).map { rename($0, $1) }
        let newCommon = rename(commonCode, maskedCommon)
        let warnings = colliding.map { name in
            ConversionWarning(severity: .info,
                message: "Renamed user identifier '\(name)' to '\(GLSLReservedIdentifierRewriter.prefix + name)' — the converter injects an ISF '\(name)' reference that the user's name would shadow.",
                context: "")
        }
        return Result(passBodies: newBodies, commonCode: newCommon, warnings: warnings)
    }
}
