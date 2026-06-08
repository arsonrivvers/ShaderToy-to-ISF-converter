import Foundation

/// Adds GLSL-1.20 compatibility polyfills for functions that exist in Shadertoy's
/// GLSL ES 3.00 but not in the older GLSL some ISF/OpenGL backends compile against
/// (the "Invalid call of undeclared identifier 'tanh'" class of error).
///
/// Polyfills are wrapped in `#if __VERSION__ < 130 ... #endif` so they're only
/// compiled on backends that lack the builtins — newer backends (Metal, GLSL 1.30+,
/// ES 3.00) keep their native versions, avoiding any redefinition conflict.
public enum GLSLCompat {
    public struct Result {
        public let code: String
        public let warnings: [ConversionWarning]
    }

    // name → float-body. vecN overloads are generated componentwise.
    private static let funcs: [(name: String, body: String)] = [
        ("tanh",  "x = clamp(x, -10.0, 10.0); float e = exp(2.0 * x); return (e - 1.0) / (e + 1.0);"),
        ("sinh",  "return 0.5 * (exp(x) - exp(-x));"),
        ("cosh",  "return 0.5 * (exp(x) + exp(-x));"),
        ("asinh", "return log(x + sqrt(x * x + 1.0));"),
        ("acosh", "return log(x + sqrt(x * x - 1.0));"),
        ("atanh", "return 0.5 * log((1.0 + x) / (1.0 - x));"),
        ("round", "return floor(x + 0.5);"),
        ("trunc", "return sign(x) * floor(abs(x));"),
    ]

    public static func apply(_ code: String) -> Result {
        var warnings: [ConversionWarning] = []
        let used = funcs.filter { callsFunction(code, $0.name) }

        var out = code
        if !used.isEmpty {
            var block = "// GLSL 1.20 compatibility polyfills (auto-added by the converter)\n#if __VERSION__ < 130\n"
            for f in used { block += polyfillBlock(name: f.name, body: f.body) }
            block += "#endif\n\n"
            out = block + out
            let names = used.map(\.name).joined(separator: ", ")
            warnings.append(ConversionWarning(severity: .info,
                message: "Added compatibility polyfills for GLSL-ES-3.00 functions not built into older ISF/OpenGL backends: \(names).",
                context: ""))
        }

        if code.range(of: "<<|>>", options: .regularExpression) != nil {
            warnings.append(ConversionWarning(severity: .warning,
                message: "Uses bit-shift operators (<< / >>), which require GLSL ES 3.00 — may not compile on older ISF/OpenGL backends.",
                context: ""))
        }
        if code.range(of: "\\bswitch\\s*\\(", options: .regularExpression) != nil {
            warnings.append(ConversionWarning(severity: .warning,
                message: "Uses a switch statement, which some older ISF/OpenGL backends reject — rewrite as if/else if it fails to compile.",
                context: ""))
        }

        return Result(code: out, warnings: warnings)
    }

    /// True if `name` appears as a function call (word-boundary name followed by `(`).
    static func callsFunction(_ code: String, _ name: String) -> Bool {
        code.range(of: "\\b\(name)\\s*\\(", options: .regularExpression) != nil
    }

    private static func polyfillBlock(name: String, body: String) -> String {
        var s = "float \(name)(float x){ \(body) }\n"
        let vecs: [(String, [String])] = [
            ("vec2", ["x", "y"]),
            ("vec3", ["x", "y", "z"]),
            ("vec4", ["x", "y", "z", "w"]),
        ]
        for (type, comps) in vecs {
            let args = comps.map { "\(name)(v.\($0))" }.joined(separator: ", ")
            s += "\(type) \(name)(\(type) v){ return \(type)(\(args)); }\n"
        }
        return s
    }
}
