import Foundation

/// Auto-fixes the "code-golf" pattern where an `out vec4` output is accumulated (`O *= / += / …`)
/// before it is plainly assigned, relying on GPU zero-initialization (common in @XorDev shaders,
/// e.g. `for (O*=i; …)`).
///
/// On WebGL/Shadertoy the out param tends to be zero, so the trick works. On Metal (the ISFMSLKit
/// preview, and real ISF hosts) the value is undefined — typically NaN — so the accumulation stays
/// NaN and the shader renders black. Injecting `O = vec4(0.0);` as the first statement of the
/// function makes the shader behave as the author intended. Harmless when the output is later plainly
/// assigned (it's simply overwritten), and only applied to outputs the detector flags.
public enum OutputInitializer {
    public struct Result { public let code: String; public let notes: [ConversionWarning] }

    public static func apply(_ code: String) -> Result {
        var out = code
        var notes: [ConversionWarning] = []
        for name in GLSLLint.uninitializedAccumulatorOutputs(code) {
            // Match the function signature declaring this output through its opening brace, and
            // insert the initializer right after the brace. `[^)]*` spans the rest of the params.
            let pattern = "(out\\s+vec4\\s+\(name)\\b[^)]*\\)\\s*\\{)"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard re.firstMatch(in: out, range: range) != nil else { continue }
            out = re.stringByReplacingMatches(in: out, range: range,
                                              withTemplate: "$1\n    \(name) = vec4(0.0);")
            notes.append(ConversionWarning(severity: .info,
                message: "Auto-initialized output '\(name)' to vec4(0.0) — the shader accumulated into it before initializing (relies on GPU zero-init, which ISF/Metal doesn't guarantee).",
                context: ""))
        }
        return Result(code: out, notes: notes)
    }
}
