import Foundation

public enum ISFConverter {
    public static func convert(_ shader: Shader) -> (ISFDocument, [ConversionWarning]) {
        var warnings: [ConversionWarning] = []
        let plan = PassBuilder.build(passes: shader.renderpass)
        warnings.append(contentsOf: plan.warnings)

        var imageInputNames: Set<String> = []
        var includeMouse = false
        var passBodies: [String] = []

        for pass in plan.renderPasses {
            let resolved = ChannelBinding.resolve(inputs: pass.inputs,
                                                  bufferOutputIDToName: plan.bufferOutputIDToName)
            warnings.append(contentsOf: resolved.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message, context: pass.name)
            })
            for (_, b) in resolved.bindings where b.kind != .buffer {
                imageInputNames.insert(b.glslName)
            }

            // Splice `\` line-continuations first — glslang rejects them and black-screens the
            // shader; downstream rewriters and the transpiler then see clean, single-logical-line code.
            var code = GLSLLineContinuation.splice(pass.code)
            if code.range(of: #"\biMouse\b"#, options: .regularExpression) != nil { includeMouse = true }

            code = UniformRewriter.rewrite(code)
            if includeMouse {
                // iMouse.xy is in pixels; ISF point2D `mouse` is normalized [0,1].
                // iMouse.zw is the click position with sign signalling button-down on Shadertoy;
                // many shaders gate interaction on it (`if (iMouse.z < 0.01) ...`). Mirror xy into
                // zw (non-zero, "pressed") so the mouse slider actually drives those shaders.
                code = code.replacingOccurrences(of: #"\biMouse\b"#,
                    with: "vec4(mouse * RENDERSIZE, mouse * RENDERSIZE)",
                    options: .regularExpression)
            }
            let sampled = SamplerRewriter.rewrite(code, bindings: resolved.bindings)
            warnings.append(contentsOf: sampled.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message, context: pass.name)
            })
            passBodies.append(sampled.code)
        }

        // The Common code is shared, un-renamed source. Rewrite its FILE-SCOPE Shadertoy uniforms
        // (e.g. `#define res iResolution.xy`) while leaving helper-function parameters/bodies alone —
        // some shaders thread the uniforms through helpers as parameters, which the per-pass
        // whole-string rewriter would corrupt.
        let commonCode = CommonUniformRewriter.rewrite(GLSLLineContinuation.splice(plan.commonCode))
        let glsl = GLSLBodyBuilder.build(passBodies: passBodies, commonCode: commonCode)
        warnings.append(contentsOf: glsl.warnings)

        // Auto-initialize outputs accumulated before assignment (XorDev `for(O*=i;…)` pattern) —
        // undefined on Metal → NaN → black. Runs before lint so the now-fixed case isn't also warned.
        let initialized = OutputInitializer.apply(glsl.code)
        warnings.append(contentsOf: initialized.notes)

        let compat = GLSLCompat.apply(initialized.code)
        warnings.append(contentsOf: compat.warnings)
        warnings.append(contentsOf: GLSLLint.check(initialized.code))

        // Reuse the plan's ordered buffer names — the single source of truth shared with the
        // in-body sampler names — so the header PASSES TARGETs can never drift from the GLSL.
        let bufferNames = plan.orderedBufferNames

        let header = HeaderBuilder.build(
            description: shader.info.description ?? shader.info.name,
            credit: "Converted from Shadertoy \(shader.info.id) by \(shader.info.username ?? "unknown")",
            imageInputNames: imageInputNames.sorted(),
            includeMouse: includeMouse,
            bufferNames: bufferNames)

        return (ISFDocument(headerJSON: header, glslBody: compat.code), warnings)
    }
}
