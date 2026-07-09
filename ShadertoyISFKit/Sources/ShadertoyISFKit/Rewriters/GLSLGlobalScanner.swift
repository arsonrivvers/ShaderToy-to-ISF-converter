import Foundation

/// Shared scanner for top-level (file-scope) GLSL global declarations — scalars, consts, and arrays
/// (`float f = 0.025;`, `const float pi = 3.14159;`, `vec3[16] pal = vec3[](…);`).
///
/// Why it mirrors GLSLFunctionScanner: Shadertoy compiles each pass separately, so two passes may each
/// declare the SAME top-level global. The converter merges every pass into one file, where those land
/// at the same scope and collide ("redefinition" / "redeclaration of array with size"). The two
/// consumers resolve it the same way they do for functions:
///   • GLSLPassNamespace renames globals whose VALUE differs across passes (4tfBRB's per-pass `float f`).
///   • GLSLFunctionDedup removes byte-identical duplicate globals (Nl3czM's shared const palette) —
///     keeping one shared file-scope copy so passes that merely REFERENCE it still resolve.
enum GLSLGlobalScanner {
    /// A top-level declaration: its variable name and the UTF-16 range of the whole `… ;` statement
    /// (`end` is exclusive, just past the terminating `;`).
    struct Def { let name: String; let start: Int; let end: Int }

    /// File-scope declaration header: optional `const`, a type (+ optional `[…]`), the variable name
    /// (+ optional `[…]`), then `=`, `;`, or `,` (M2: multi-declarator lists). A function
    /// def/prototype has `(` where we require the terminator, so both are excluded; `struct …{`,
    /// `precision …;`, and `#…` lines fail the shape too. The `,` case would also match a
    /// line-leading PARAMETER in a multi-line function signature — excluded by the paren-depth
    /// guard in `defs`. Capture group 1 is the first declarator's name.
    private static let headerPattern =
        "(?m)^[ \\t]*(?:const[ \\t]+)?[A-Za-z_]\\w*(?:[ \\t]*\\[[^\\]]*\\])?[ \\t]+([A-Za-z_]\\w*)(?:[ \\t]*\\[[^\\]]*\\])?[ \\t]*(?:=|;|,)"

    /// All file-scope (brace-depth-0) global declarations in `code`, in source order — one `Def`
    /// PER DECLARATOR (M2: `float a, b = 2., c;` yields a, b, c, all sharing the statement range).
    /// Matching runs on comment-masked text (M14: a commented-out global can't become a Def);
    /// ranges index into the original, which is offset-identical. Depth/statement scans are
    /// directive-aware via GLSLScanner (a `{` or `;` inside a `#define` line can't desync them).
    static func defs(in code: String) -> [Def] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let masked = GLSLScanner.strip(code)
        let ms = masked as NSString
        var out: [Def] = []
        for m in re.matches(in: masked, range: NSRange(location: 0, length: ms.length)) {
            let depths = GLSLScanner.depths(code, before: m.range.location)
            guard depths.brace == 0, depths.paren == 0 else { continue }   // skip locals AND params
            guard let end = GLSLScanner.statementEnd(code, from: m.range.location) else { continue }
            for name in declaratorNames(ms, firstName: m.range(at: 1), statementEnd: end) {
                out.append(Def(name: name, start: m.range.location, end: end))
            }
        }
        return out
    }

    /// All declarator names in a (possibly multi-declarator) global statement — `float a, b = 2., c;`
    /// → ["a","b","c"]. Splits on commas at nesting depth 0 within the statement (commas inside
    /// initializers like `vec2(1., 2.)` or `float[](1., 2.)` sit inside parens/brackets/braces and
    /// are not declarator boundaries). `masked` is comment-blanked, so comment commas are spaces.
    private static func declaratorNames(_ masked: NSString, firstName: NSRange,
                                        statementEnd end: Int) -> [String] {
        var names = [masked.substring(with: firstName)]
        var depth = 0
        var commas: [Int] = []
        var i = firstName.location + firstName.length
        while i < end {
            switch masked.character(at: i) {
            case 40, 91, 123: depth += 1                    // ( [ {
            case 41, 93, 125: if depth > 0 { depth -= 1 }   // ) ] }
            case 44: if depth == 0 { commas.append(i) }     // ,
            default: break
            }
            i += 1
        }
        guard !commas.isEmpty else { return names }
        let idRe = try! NSRegularExpression(pattern: "[A-Za-z_]\\w*")
        let str = masked as String
        for c in commas {
            if let m = idRe.firstMatch(in: str, range: NSRange(location: c + 1, length: end - c - 1)) {
                names.append(masked.substring(with: m.range))
            }
        }
        return names
    }
}
