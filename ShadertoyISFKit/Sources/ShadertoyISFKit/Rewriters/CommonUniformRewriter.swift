import Foundation

/// Rewrites Shadertoy uniforms (iResolution, iTime, …) in a shader's **Common** code, but ONLY at
/// file scope — outside any function body (brace depth 0) and outside any parameter list (paren
/// depth 0).
///
/// Why scope-aware: some Shadertoy authors thread the uniforms through helper functions as
/// parameters (`void ups(…, vec2 iResolution, vec4 iMouse, sampler2D iChannel0, …)`) and rely on a
/// file-scope macro like `#define res iResolution.xy` to pick up the global at the top level and the
/// parameter inside helpers. UniformRewriter maps `iResolution` to the *expression*
/// `vec3(RENDERSIZE, 1.0)`; substituting that into a parameter declaration (`vec2 vec3(...)`) is a
/// syntax error. So function bodies and parameter lists are left untouched — only genuine
/// file-scope references (the `#define`, global declarations) are rewritten.
///
/// Per-pass bodies don't have this collision (their `mainImage` signatures don't declare
/// uniform-named parameters), so they keep using the simpler whole-string UniformRewriter.
public enum CommonUniformRewriter {
    public static func rewrite(_ code: String) -> String {
        var output = ""
        walkRuns(code) { run, isProtected in
            output += isProtected ? run : UniformRewriter.rewrite(run)
        }
        return output
    }

    /// C5 interim: uniform names used at brace/paren depth > 0 (function bodies/param lists — the
    /// runs `rewrite` protects) that are NOT declared as a parameter anywhere in the file. Such a
    /// use is never rewritten and reaches the transpiler as an undeclared identifier; callers warn
    /// loudly. Detection only — the real fix is per-function scope-aware rewriting (DESLOPPIFY C5).
    public static func unrewrittenBodyUniforms(_ code: String) -> [String] {
        var protectedText = ""
        walkRuns(code) { run, isProtected in
            if isProtected { protectedText += run }
        }
        return UniformRewriter.detectableNames.filter { name in
            guard protectedText.range(of: "\\b\(name)\\b", options: .regularExpression) != nil
            else { return false }
            // Declared as a parameter somewhere → body uses are (at least sometimes) the parameter;
            // the mixed case is C5-proper, not this interim net.
            return code.range(of: "[(,]\\s*(in\\s+|inout\\s+|out\\s+)?\\w+\\s+\(name)\\b",
                              options: .regularExpression) == nil
        }
    }

    /// Walks `code` splitting it into runs, emitting each with whether it is "protected" (inside
    /// parens or braces). Single walker shared by `rewrite` and `unrewrittenBodyUniforms` so the
    /// two can't disagree about scope.
    private static func walkRuns(_ code: String, _ emit: (String, Bool) -> Void) {
        var run = ""
        var inProtected = false   // true while inside parens or braces
        var brace = 0
        var paren = 0

        func flush() {
            if run.isEmpty { return }
            emit(run, inProtected)
            run = ""
        }

        // Delimiters inside comments must NOT affect depth (a `:(` in a comment once made the whole
        // rest of the file look "protected"). Same for preprocessor directives: a `#define` whose
        // body has an unbalanced `{` (a "header macro" like `#define Main void mainImage(…){ …`)
        // would otherwise leave the rest of the file looking like a function body. Track comment AND
        // directive state and skip depth counting there; directive bodies are still file-scope, so
        // their uniforms get rewritten.
        enum Mode { case normal, line, block, directive }
        var mode: Mode = .normal
        var atLineStart = true
        let chars = Array(code)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            switch mode {
            case .normal:
                if ch == "/", next == "/" { mode = .line }
                else if ch == "/", next == "*" { mode = .block }
                else if atLineStart, ch == "#" { mode = .directive }
            case .line:
                if ch == "\n" { mode = .normal }
            case .directive:
                if ch == "\n" { mode = .normal }
            case .block:
                if ch == "*", next == "/" {
                    // consume both chars of the closing token within this run
                    let protectedNow = brace > 0 || paren > 0
                    if protectedNow != inProtected { flush(); inProtected = protectedNow }
                    run.append(ch); run.append("/"); i += 2; mode = .normal
                    continue
                }
            }

            // Track line-start (leading whitespace preserves it) so `#` is only a directive at the
            // start of a logical line.
            if ch == "\n" { atLineStart = true }
            else if ch != " " && ch != "\t" { atLineStart = false }

            let protectedNow = brace > 0 || paren > 0
            if protectedNow != inProtected { flush(); inProtected = protectedNow }
            run.append(ch)

            if mode == .normal {
                switch ch {
                case "{": brace += 1
                case "}": if brace > 0 { brace -= 1 }
                case "(": paren += 1
                case ")": if paren > 0 { paren -= 1 }
                default: break
                }
            }
            i += 1
        }
        flush()
    }
}
