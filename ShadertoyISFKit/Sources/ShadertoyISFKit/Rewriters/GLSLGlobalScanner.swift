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
    /// Matching runs on comment-masked text (M14: a commented-out global can't become a Def);
    /// ranges index into the original, which is offset-identical. Depth/statement scans are
    /// directive-aware via GLSLScanner (a `{` or `;` inside a `#define` line can't desync them).
    static func defs(in code: String) -> [Def] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let masked = GLSLScanner.strip(code)
        let ms = masked as NSString
        var out: [Def] = []
        for m in re.matches(in: masked, range: NSRange(location: 0, length: ms.length)) {
            guard GLSLScanner.braceDepth(code, before: m.range.location) == 0 else { continue }
            guard let end = GLSLScanner.statementEnd(code, from: m.range.location) else { continue }
            let name = ms.substring(with: m.range(at: 1))
            out.append(Def(name: name, start: m.range.location, end: end))
        }
        return out
    }
}
