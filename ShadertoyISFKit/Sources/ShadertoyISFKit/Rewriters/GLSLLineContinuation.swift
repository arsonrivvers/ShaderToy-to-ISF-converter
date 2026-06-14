import Foundation

/// Splices C-style `\` line-continuations (backslash + optional trailing whitespace + newline) into
/// a single space, matching the C/GLSL preprocessor's line-splicing.
///
/// Why: glslang — the GLSL frontend in ISFMSLKit's transpiler — rejects raw backslash-newline
/// continuations with "line continuation not supported for this version or the enabled extensions",
/// which black-screens any imported shader that uses them (common in multi-line `#define` macros and
/// occasionally mid-statement, e.g. Shadertoy 7323zz). A space splice joins the logical line (so a
/// macro body stays intact) while preventing token-merging.
public enum GLSLLineContinuation {
    public static func splice(_ code: String) -> String {
        code.replacingOccurrences(of: #"\\[ \t]*\r?\n"#, with: " ", options: .regularExpression)
    }
}
