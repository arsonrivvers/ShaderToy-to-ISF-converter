import Foundation

public enum ISFConverter {
    /// The conversion is an ORDERED pipeline; order is correctness-critical and a wrong order usually
    /// fails silently as a black shader rather than loudly. The authoritative stage list (some stages
    /// live in `GLSLBodyBuilder`, so they aren't visible in this function's body — see stage 10):
    ///
    ///   Per pass:  1. GLSLLineContinuation.splice   2. UniformRewriter.rewriteScoped (scope-aware; incl. iMouse mirror)
    ///              3. channel auto-stub             4. SamplerRewriter
    ///   Common:    5. GLSLLineContinuation.splice   6. CommonChannelRewriter (PASSINDEX dispatch)
    ///              7. UniformRewriter.rewriteScoped   8. HeaderMacroExpander
    ///              8b. OutputInitializer — PER PASS BODY + Common, before concatenation (M1)
    ///              8c. ZeroInitLocals — zero-init uninitialized locals (WebGL parity; golf shaders)
    ///              9. GLSLBodyBuilder.build, which internally runs, IN ORDER:
    ///                   9a. GLSLPassNamespace (rename cross-pass colliding helpers/globals)
    ///                   9b. GLSLPassMacroScoper  (#undef per-pass #defines; Common-aware — M18)
    ///                   9c. per-pass mainImage rename + PASSINDEX dispatch assembly
    ///             10. GLSLFunctionDedup   11. GLSLReservedIdentifierRewriter
    ///             12. GLSLCompat (+ GLSLLint)   13. HeaderBuilder
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
            // Detection scans run on comment-blanked code — `// TODO try iChannel2` must not
            // invent inputs. The rewrites below still run on the real `code`.
            let detectable = GLSLScanner.strip(code)
            if detectable.range(of: #"\biMouse\b"#, options: .regularExpression) != nil { includeMouse = true }
            if detectable.contains("iChannelResolution") { usesChannelResolution = true }

            // iMouse is one of UniformRewriter's standard rules (mirrors xy into zw, "pressed");
            // `includeMouse` above only gates declaring the `mouse` input in the header.
            // Scope-aware (M20): a paste-path helper that threads a uniform as a PARAMETER is
            // protected; everything else rewrites exactly as the whole-string rewriter did.
            code = UniformRewriter.rewriteScoped(code)

            // Auto-stub any iChannelN used in the code but not declared as a renderpass input —
            // some Shadertoy shaders reference a channel the API/internal response never lists, which
            // would otherwise leave a bare `iChannelN` / `texture(iChannelN,…)` undeclared.
            for n in Self.referencedChannelIndices(detectable).sorted() where bindings[n] == nil {
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

        // The Common code is shared, un-renamed source. The scope-aware rewrite maps its Shadertoy
        // uniforms everywhere EXCEPT inside functions that thread a uniform through as a parameter
        // (substituting the mapped expression into a parameter declaration is a syntax error).
        let splicedCommon = GLSLLineContinuation.splice(plan.commonCode)
        let detectableCommon = GLSLScanner.strip(splicedCommon)
        if detectableCommon.contains("iChannelResolution") { usesChannelResolution = true }
        // iMouse referenced only in the Common tab must still declare the mouse input — the
        // rewrite happens in UniformRewriter.rewriteScoped below, but the header flag is set here.
        if detectableCommon.range(of: #"\biMouse\b"#, options: .regularExpression) != nil {
            includeMouse = true
        }
        if usesChannelResolution {
            warnings.append(ConversionWarning(severity: .info,
                message: "iChannelResolution has no ISF equivalent — mapped to vec3(RENDERSIZE, 1.0). Exact for buffer/feedback channels; for image inputs it loses the source's native size, verify if the shader scales by a channel's aspect."))
        }
        // A channel sampled in the Common tab but bound by NO pass → stub it as an image across all
        // passes so its dispatcher samples something real rather than returning 0.
        for n in Self.referencedChannelIndices(detectableCommon).sorted() where perChannelPerPass[n] == nil {
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

        var commonCode = UniformRewriter.rewriteScoped(channelRewrite.rewrittenCommon)
        // Tripwire (C5 is fixed structurally): any detectable uniform that SURVIVED the
        // scope-aware rewrite outside a param-shadowed position means a case the rewriter
        // doesn't map (e.g. bare un-indexed iChannelResolution) — surface it loudly.
        for name in UniformRewriter.unresolvedUniformUses(commonCode) {
            warnings.append(ConversionWarning(severity: .warning,
                message: "\(name) survived uniform rewriting in the Common tab (no ISF mapping applies at this use) — the shader may fail to compile. Verify or rework the use.",
                context: "Common"))
        }
        if !channelRewrite.dispatchers.isEmpty {
            commonCode = channelRewrite.dispatchers + "\n\n" + commonCode
        }

        // Expand any Common "header macro" that hides the mainImage signature (`#define Main void
        // mainImage(…)`) into the pass bodies, so GLSLBodyBuilder's per-pass mainImage rename can make
        // each unique (otherwise every pass expands to a duplicate `void mainImage`).
        let expanded = HeaderMacroExpander.expand(commonCode: commonCode, passBodies: passBodies)

        // M1: run the uninitialized-accumulator fix on each ISOLATED pass body (and on Common's
        // helpers) BEFORE concatenation — on the merged file, pass 0's plain `O =` masked pass 1's
        // compound-first `O` (passes typically all name their output `O`; the whole-file test
        // dedups names). After HeaderMacroExpander so header-macro shaders' expanded mainImage
        // signatures are seen.
        var initializedBodies: [String] = []
        for (idx, body) in expanded.passBodies.enumerated() {
            let r = OutputInitializer.apply(body)
            warnings.append(contentsOf: r.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message,
                                  context: plan.renderPasses[idx].name)
            })
            // 8c: zero-init uninitialized locals (WebGL/ANGLE zero-inits, Metal doesn't — the
            // golf-shader `for(O*=i; i++<…)` class reads garbage guards and renders black).
            let z = ZeroInitLocals.rewrite(r.code)
            warnings.append(contentsOf: z.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message,
                                  context: plan.renderPasses[idx].name)
            })
            initializedBodies.append(z.code)
        }
        var commonInitialized = OutputInitializer.apply(expanded.commonCode)
        warnings.append(contentsOf: commonInitialized.warnings.map {
            ConversionWarning(severity: $0.severity, message: $0.message, context: "Common")
        })
        let commonZeroed = ZeroInitLocals.rewrite(commonInitialized.code)
        warnings.append(contentsOf: commonZeroed.warnings.map {
            ConversionWarning(severity: $0.severity, message: $0.message, context: "Common")
        })
        commonInitialized = RewriteResult(code: commonZeroed.code, warnings: [])

        let glsl = GLSLBodyBuilder.build(passBodies: initializedBodies,
                                         commonCode: commonInitialized.code)
        warnings.append(contentsOf: glsl.warnings)

        // Remove byte-identical duplicate helpers merged from multiple passes (multipass shaders
        // with no Common tab copy helpers into each tab → "function already has a body").
        let deduped = GLSLFunctionDedup.dedup(glsl.code)

        // Rename user identifiers that are MSL/C++ reserved words (`char`, `coord`, …) — legal in
        // Shadertoy's GLSL ES but rejected by the Metal transpiler the preview compiles against.
        let reserved = GLSLReservedIdentifierRewriter.rewrite(deduped)

        let compat = GLSLCompat.apply(reserved)
        warnings.append(contentsOf: compat.warnings)
        warnings.append(contentsOf: GLSLLint.check(reserved))

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
