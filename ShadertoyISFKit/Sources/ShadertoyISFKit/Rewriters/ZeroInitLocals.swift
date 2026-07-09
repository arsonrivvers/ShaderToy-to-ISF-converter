import Foundation

/// Zero-initializes uninitialized LOCAL declarators — `float i, d, z, r;` becomes
/// `float i = 0.0, d = 0.0, z = 0.0, r = 0.0;`, and `for (float i; …)` gains `= 0.0`.
///
/// Why: ANGLE (the WebGL compiler under Shadertoy) zero-initializes locals; Metal does not.
/// Golf shaders lean on that (`for(O*=i; i++<9e1;)` with `float i, …;`) — on Metal the loop
/// guard reads garbage/NaN, the loop never runs, and the shader renders black while compiling
/// clean. Injecting explicit zeros reproduces the WebGL semantics the author wrote against;
/// for a local that IS later written first, the initializer is dead and harmless.
///
/// Deliberately narrow:
/// - Only statement declarations at brace depth ≥ 1 (inside a function) and paren depth 0,
///   plus init-less `for (TYPE i; …)` declarations — file-scope globals are untouched
///   (cross-pass semantics belong to dedup/namespacing), parameters can't match (paren depth).
/// - Only whitelisted zeroable types; user structs/samplers untouched.
/// - Declarators with an array suffix untouched (array constructors are noisy and absent from
///   the golf idiom).
/// - Declarations inside `struct { … }` bodies untouched (member initializers are illegal).
/// - All matching on comment-masked text; edits applied to the original back-to-front.
public enum ZeroInitLocals {
    /// TYPE → zero literal.
    private static let zeroByType: [String: String] = [
        "float": "0.0", "int": "0", "uint": "0u", "bool": "false",
        "vec2": "vec2(0.0)", "vec3": "vec3(0.0)", "vec4": "vec4(0.0)",
        "ivec2": "ivec2(0)", "ivec3": "ivec3(0)", "ivec4": "ivec4(0)",
        "uvec2": "uvec2(0u)", "uvec3": "uvec3(0u)", "uvec4": "uvec4(0u)",
        "bvec2": "bvec2(false)", "bvec3": "bvec3(false)", "bvec4": "bvec4(false)",
        "mat2": "mat2(0.0)", "mat3": "mat3(0.0)", "mat4": "mat4(0.0)",
    ]
    private static let typeAlternation = zeroByType.keys.sorted { $0.count > $1.count }
        .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")

    public static func rewrite(_ code: String) -> RewriteResult {
        let masked = GLSLScanner.strip(code)
        let mns = masked as NSString

        // struct bodies: `float a, b;` members must NOT gain initializers (illegal GLSL).
        var structSpans: [NSRange] = []
        let structRe = try! NSRegularExpression(pattern: "\\bstruct\\b[^{;]*\\{")
        for m in structRe.matches(in: masked, range: NSRange(location: 0, length: mns.length)) {
            let open = m.range.location + m.range.length - 1
            if let end = GLSLScanner.braceMatchEnd(code, openBrace: open) {
                structSpans.append(NSRange(location: m.range.location, length: end - m.range.location))
            }
        }
        func inStruct(_ pos: Int) -> Bool { structSpans.contains { NSLocationInRange(pos, $0) } }

        var inserts: [(at: Int, text: String)] = []   // insert `text` at UTF-16 offset `at`
        var names: [String] = []

        // (a) Statement declarations inside function bodies: TYPE at brace≥1, paren==0.
        let declRe = try! NSRegularExpression(
            pattern: "(?<![\\w.])(\(typeAlternation))[ \\t\\n]+[A-Za-z_]")
        for m in declRe.matches(in: masked, range: NSRange(location: 0, length: mns.length)) {
            let at = m.range.location
            let depths = GLSLScanner.depths(code, before: at)
            guard depths.brace >= 1, depths.paren == 0, !inStruct(at) else { continue }
            guard let end = GLSLScanner.statementEnd(code, from: at) else { continue }
            let type = mns.substring(with: m.range(at: 1))
            collectDeclarators(mns, from: at + type.utf16.count, to: end - 1, type: type,
                               inserts: &inserts, names: &names)
        }

        // (b) Init-less for-loop declarations: `for (TYPE i; …)` — the init clause ends at the
        // first `;` not nested in parens/brackets opened within it.
        let forRe = try! NSRegularExpression(
            pattern: "\\bfor[ \\t]*\\([ \\t]*(\(typeAlternation))[ \\t]+")
        for m in forRe.matches(in: masked, range: NSRange(location: 0, length: mns.length)) {
            guard !inStruct(m.range.location) else { continue }
            let type = mns.substring(with: m.range(at: 1))
            let initStart = m.range.location + m.range.length
            var depth = 0
            var semi: Int? = nil
            var i = initStart
            while i < mns.length {
                switch mns.character(at: i) {
                case 40, 91: depth += 1                      // ( [
                case 41, 93: if depth > 0 { depth -= 1 } else { i = mns.length }  // stray `)` ends
                case 59: if depth == 0 { semi = i; i = mns.length }               // ;
                default: break
                }
                i += 1
            }
            guard let end = semi else { continue }
            collectDeclarators(mns, from: initStart - 1, to: end, type: type,
                               inserts: &inserts, names: &names)
        }

        guard !inserts.isEmpty else { return RewriteResult(code: code) }
        let out = NSMutableString(string: code)
        for ins in inserts.sorted(by: { $0.at > $1.at }) {
            out.insert(ins.text, at: ins.at)
        }
        let warning = ConversionWarning(severity: .info,
            message: "Zero-initialized uninitialized local(s): \(names.joined(separator: ", ")) — WebGL zero-initializes locals, Metal does not (read-before-write rendered black on Metal).",
            context: "")
        return RewriteResult(code: out as String, warnings: [warning])
    }

    /// Walks the declarator list of one declaration spanning masked[(from)..<to] (to = index of
    /// the terminating `;` / just past the last declarator). For each declarator with no `=` and
    /// no array suffix, records an insertion ` = <zero>` right after its name.
    private static func collectDeclarators(_ masked: NSString, from: Int, to: Int, type: String,
                                           inserts: inout [(at: Int, text: String)],
                                           names: inout [String]) {
        guard let zero = zeroByType[type] else { return }
        let idRe = try! NSRegularExpression(pattern: "[A-Za-z_]\\w*")
        var depth = 0
        var chunkStart = from
        var chunks: [NSRange] = []
        var i = from
        while i < to {
            switch masked.character(at: i) {
            case 40, 91, 123: depth += 1                    // ( [ {
            case 41, 93, 125: if depth > 0 { depth -= 1 }   // ) ] }
            case 44 where depth == 0:                       // top-level comma
                chunks.append(NSRange(location: chunkStart, length: i - chunkStart))
                chunkStart = i + 1
            default: break
            }
            i += 1
        }
        chunks.append(NSRange(location: chunkStart, length: to - chunkStart))

        for chunk in chunks {
            let text = masked.substring(with: chunk)
            guard let idMatch = idRe.firstMatch(in: text,
                                                range: NSRange(location: 0, length: (text as NSString).length))
            else { continue }
            let after = (text as NSString).substring(from: idMatch.range.location + idMatch.range.length)
            // initialized (`=`) or array (`[`) declarators are left alone
            if after.contains("=") || after.contains("[") { continue }
            let name = (text as NSString).substring(with: idMatch.range)
            let insertAt = chunk.location + idMatch.range.location + idMatch.range.length
            inserts.append((at: insertAt, text: " = \(zero)"))
            names.append(name)
        }
    }
}
