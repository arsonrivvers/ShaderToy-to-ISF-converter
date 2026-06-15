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
    /// (+ optional `[…]`), then `=` or `;`. A function def/prototype has `(` where we require `=`/`;`,
    /// so both are excluded; `struct …{`, `precision …;`, and `#…` lines fail the shape too.
    /// Capture group 1 is the variable name.
    private static let headerPattern =
        "(?m)^[ \\t]*(?:const[ \\t]+)?[A-Za-z_]\\w*(?:[ \\t]*\\[[^\\]]*\\])?[ \\t]+([A-Za-z_]\\w*)(?:[ \\t]*\\[[^\\]]*\\])?[ \\t]*(?:=|;)"

    /// All file-scope (brace-depth-0) global declarations in `code`, in source order.
    static func defs(in code: String) -> [Def] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let s = code as NSString
        var out: [Def] = []
        for m in re.matches(in: code, range: NSRange(location: 0, length: s.length)) {
            guard depth(s, before: m.range.location) == 0 else { continue }   // skip locals (depth > 0)
            guard let end = statementEnd(s, from: m.range.location) else { continue }
            let name = s.substring(with: m.range(at: 1))
            out.append(Def(name: name, start: m.range.location, end: end))
        }
        return out
    }

    /// Brace depth immediately before `pos`, skipping // and /* */ comments. 0 == file scope.
    private static func depth(_ s: NSString, before pos: Int) -> Int {
        let slash: unichar = 47, star: unichar = 42, nl: unichar = 10
        let open: unichar = 123, close: unichar = 125
        var depth = 0, i = 0, mode = 0   // 0 normal, 1 line comment, 2 block comment
        while i < pos {
            let c = s.character(at: i)
            let n: unichar? = i + 1 < s.length ? s.character(at: i + 1) : nil
            switch mode {
            case 1: if c == nl { mode = 0 }
            case 2: if c == star, n == slash { mode = 0; i += 2; continue }
            default:
                if c == slash, n == slash { mode = 1 }
                else if c == slash, n == star { mode = 2 }
                else if c == open { depth += 1 }
                else if c == close { depth -= 1 }
            }
            i += 1
        }
        return depth
    }

    /// Index just past the first `;` at or after `from`, skipping // and /* */ comments. A global
    /// initializer contains no `;`, so the first one outside a comment terminates the declaration.
    private static func statementEnd(_ s: NSString, from: Int) -> Int? {
        let slash: unichar = 47, star: unichar = 42, nl: unichar = 10, semi: unichar = 59
        var i = from, mode = 0
        while i < s.length {
            let c = s.character(at: i)
            let n: unichar? = i + 1 < s.length ? s.character(at: i + 1) : nil
            switch mode {
            case 1: if c == nl { mode = 0 }
            case 2: if c == star, n == slash { mode = 0; i += 2; continue }
            default:
                if c == slash, n == slash { mode = 1 }
                else if c == slash, n == star { mode = 2 }
                else if c == semi { return i + 1 }
            }
            i += 1
        }
        return nil
    }
}
