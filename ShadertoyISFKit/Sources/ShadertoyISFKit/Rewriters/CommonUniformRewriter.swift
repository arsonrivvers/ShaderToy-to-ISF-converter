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
        var run = ""
        var inProtected = false   // true while inside parens or braces
        var brace = 0
        var paren = 0

        func flush() {
            if run.isEmpty { return }
            output += inProtected ? run : UniformRewriter.rewrite(run)
            run = ""
        }

        // Delimiters inside comments must NOT affect depth (a `:(` in a comment once made the whole
        // rest of the file look "protected"). Track comment state and skip depth counting there.
        enum Mode { case normal, line, block }
        var mode: Mode = .normal
        let chars = Array(code)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            switch mode {
            case .normal:
                if ch == "/", next == "/" { mode = .line }
                else if ch == "/", next == "*" { mode = .block }
            case .line:
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
        return output
    }
}
