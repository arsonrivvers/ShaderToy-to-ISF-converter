import Foundation

public enum ISFConverter {
    /// The conversion is an ORDERED pipeline; order is correctness-critical and a wrong order usually
    /// fails silently as a black shader rather than loudly. The authoritative stage list (some stages
    /// live in `GLSLBodyBuilder`, so they aren't visible in this function's body — see stage 10):
    ///
    ///   Per pass:  1. GLSLLineContinuation.splice   2. UniformRewriter (incl. iMouse mirror)
    ///              3. channel auto-stub             4. SamplerRewriter
    ///   Common:    5. GLSLLineContinuation.splice   6. CommonChannelRewriter (PASSINDEX dispatch)
    ///              7. CommonUniformRewriter          8. HeaderMacroExpander
    ///              9. GLSLBodyBuilder.build, which internally runs, IN ORDER:
    ///                   9a. GLSLPassNamespace (rename cross-pass colliding helpers/globals)
    ///                   9b. GLSLPassMacroScoper  (#undef per-pass #defines — restores isolation)
    ///                   9c. per-pass mainImage rename + PASSINDEX dispatch assembly
    ///             10. GLSLFunctionDedup   11. GLSLReservedIdentifierRewriter   12. OutputInitializer
    ///             13. GLSLCompat (+ GLSLLint)   14. HeaderBuilder
    ///
    /// Key invariants: line-continuation splice precedes everything; macro-expand (8) precedes the
    /// per-pass mainImage rename (9c); dedup (10) follows namespacing (9a); compat polyfills (13)
    /// are prepended last. Preserve this order when refactoring.
    public static func convert(_ shader: Shader) -> (ISFDocument, [ConversionWarning]) {
        var warnings: [ConversionWarning] = []
        let plan = PassBuilder.build(passes: shader.renderpass)
        warnings.append(contentsOf: plan.warnings)

        var imageInputNames: Set<String> = []
        var audioFFTNames: Set<String> = []
        var audioWaveNames: Set<String> = []
        var includeMouse = false
        var passBodies: [String] = []
        var usesChannelResolution = false
        // channel index -> (pass index -> the sampler binding for that channel in that pass).
        // Drives the Common-tab PASSINDEX dispatchers (a channel can bind a different buffer per pass).
        var perChannelPerPass: [Int: [Int: ChannelBinding.Binding]] = [:]

        for (passIndex, pass) in plan.renderPasses.enumerated() {
            let resolved = ChannelBinding.resolve(inputs: pass.inputs,
                                                  bufferOutputIDToName: plan.bufferOutputIDToName)
            warnings.append(contentsOf: resolved.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message, context: pass.name)
            })
            var bindings = resolved.bindings

            // Splice `\` line-continuations first — glslang rejects them and black-screens the
            // shader; downstream rewriters and the transpiler then see clean, single-logical-line code.
            var code = GLSLLineContinuation.splice(pass.code)
            if code.range(of: #"\biMouse\b"#, options: .regularExpression) != nil { includeMouse = true }
            if code.contains("iChannelResolution") { usesChannelResolution = true }

            // iMouse is one of UniformRewriter's standard rules (mirrors xy into zw, "pressed");
            // `includeMouse` above only gates declaring the `mouse` input in the header.
            code = UniformRewriter.rewrite(code)

            // Auto-stub any iChannelN used in the code but not declared as a renderpass input —
            // some Shadertoy shaders reference a channel the API/internal response never lists, which
            // would otherwise leave a bare `iChannelN` / `texture(iChannelN,…)` undeclared.
            for n in Self.referencedChannelIndices(code).sorted() where bindings[n] == nil {
                bindings[n] = ChannelBinding.Binding(glslName: "iChannel\(n)img", kind: .texture)
                warnings.append(ConversionWarning(severity: .warning,
                    message: "iChannel\(n) is used but the renderpass declares no input for it — added a stub image input; supply an image or verify.",
                    context: pass.name))
            }
            for (_, b) in bindings {
                switch b.kind {
                case .buffer: break
                case .audio:
                    audioFFTNames.insert(b.glslName)
                    if let wave = b.auxName { audioWaveNames.insert(wave) }
                default: imageInputNames.insert(b.glslName)
                }
            }
            for (ch, b) in bindings { perChannelPerPass[ch, default: [:]][passIndex] = b }

            let sampled = SamplerRewriter.rewrite(code, bindings: bindings)
            warnings.append(contentsOf: sampled.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message, context: pass.name)
            })
            passBodies.append(sampled.code)
        }

        // The Common code is shared, un-renamed source. Rewrite its FILE-SCOPE Shadertoy uniforms
        // (e.g. `#define res iResolution.xy`) while leaving helper-function parameters/bodies alone —
        // some shaders thread the uniforms through helpers as parameters, which the per-pass
        // whole-string rewriter would corrupt.
        let splicedCommon = GLSLLineContinuation.splice(plan.commonCode)
        if splicedCommon.contains("iChannelResolution") { usesChannelResolution = true }
        // iMouse referenced only in the Common tab must still declare the mouse input — the
        // file-scope rewrite happens in CommonUniformRewriter below, but the header flag is set here.
        if splicedCommon.range(of: #"\biMouse\b"#, options: .regularExpression) != nil {
            includeMouse = true
        }
        if usesChannelResolution {
            warnings.append(ConversionWarning(severity: .info,
                message: "iChannelResolution has no ISF equivalent — mapped to vec3(RENDERSIZE, 1.0). Exact for buffer/feedback channels; for image inputs it loses the source's native size, verify if the shader scales by a channel's aspect."))
        }
        // A channel sampled in the Common tab but bound by NO pass → stub it as an image across all
        // passes so its dispatcher samples something real rather than returning 0.
        for n in Self.referencedChannelIndices(splicedCommon).sorted() where perChannelPerPass[n] == nil {
            let stub = ChannelBinding.Binding(glslName: "iChannel\(n)img", kind: .texture)
            for p in 0..<plan.renderPasses.count { perChannelPerPass[n, default: [:]][p] = stub }
            imageInputNames.insert(stub.glslName)
            warnings.append(ConversionWarning(severity: .warning,
                message: "iChannel\(n) is sampled in the Common tab but no pass declares it — added a stub image input; supply an image or verify."))
        }

        // Route Common-tab `iChannelN` sampling through PASSINDEX dispatchers (Common is shared but a
        // channel can bind a different buffer per pass). Dispatchers are prepended ahead of Common so
        // the helpers/macros that call them are defined after.
        let channelRewrite = CommonChannelRewriter.rewrite(
            commonCode: splicedCommon, perChannelPerPass: perChannelPerPass,
            passCount: plan.renderPasses.count)
        warnings.append(contentsOf: channelRewrite.warnings)

        var commonCode = CommonUniformRewriter.rewrite(channelRewrite.rewrittenCommon)
        // C5 interim: body-scope uniform uses are protected from the rewrite (param-shadowing), so
        // an unshadowed one ships as an undeclared identifier — warn loudly until the scope-aware
        // rewrite exists.
        for name in CommonUniformRewriter.unrewrittenBodyUniforms(channelRewrite.rewrittenCommon) {
            warnings.append(ConversionWarning(severity: .warning,
                message: "\(name) is used inside a Common helper body and was NOT auto-rewritten (only file-scope Common code is rewritten) — the shader may fail to compile. Thread it through as a parameter or move the use to file scope.",
                context: "Common"))
        }
        if !channelRewrite.dispatchers.isEmpty {
            commonCode = channelRewrite.dispatchers + "\n\n" + commonCode
        }

        // Expand any Common "header macro" that hides the mainImage signature (`#define Main void
        // mainImage(…)`) into the pass bodies, so GLSLBodyBuilder's per-pass mainImage rename can make
        // each unique (otherwise every pass expands to a duplicate `void mainImage`).
        let expanded = HeaderMacroExpander.expand(commonCode: commonCode, passBodies: passBodies)
        let glsl = GLSLBodyBuilder.build(passBodies: expanded.passBodies, commonCode: expanded.commonCode)
        warnings.append(contentsOf: glsl.warnings)

        // Remove byte-identical duplicate helpers merged from multiple passes (multipass shaders
        // with no Common tab copy helpers into each tab → "function already has a body").
        let deduped = GLSLFunctionDedup.dedup(glsl.code)

        // Rename user identifiers that are MSL/C++ reserved words (`char`, `coord`, …) — legal in
        // Shadertoy's GLSL ES but rejected by the Metal transpiler the preview compiles against.
        let reserved = GLSLReservedIdentifierRewriter.rewrite(deduped)

        // Auto-initialize outputs accumulated before assignment (XorDev `for(O*=i;…)` pattern) —
        // undefined on Metal → NaN → black. Runs before lint so the now-fixed case isn't also warned.
        let initialized = OutputInitializer.apply(reserved)
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
            bufferNames: bufferNames,
            audioFFTNames: audioFFTNames.sorted(),
            audioWaveNames: audioWaveNames.sorted())

        return (ISFDocument(headerJSON: header, glslBody: compat.code), warnings)
    }

    /// Channel indices referenced as `iChannelN` anywhere in `code`.
    private static func referencedChannelIndices(_ code: String) -> Set<Int> {
        let ns = code as NSString
        let re = try! NSRegularExpression(pattern: "\\biChannel(\\d+)\\b")
        var found = Set<Int>()
        for m in re.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            if let n = Int(ns.substring(with: m.range(at: 1))) { found.insert(n) }
        }
        return found
    }
}
