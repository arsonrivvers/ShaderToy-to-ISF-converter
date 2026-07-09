# DESLOPPIFY — Cleanup Backlog

_Last scan: 2026-07-08 (full refresh) · branch: desloppify-cleanup · 35 open / 42 done (M8 + M12-probe still STAGED) · rescan added C4–C11, M14–M39, N12–N27; Tasks 1.1 (C4/C6/C7/M17) + 1.2/1.2b (M15/M16/M21–M24, N15–N17, C5-interim warning) fixed same day — 223 tests green, corpus 74/78 baseline pass list · CSO re-verdict: **SHIP** (C2/M11/M12/N10 fixes hold, test-pinned; only pre-launch ask = `#if DEBUG`-gate the debug env affordances → N9/N11)_

> How this works: items are grouped Critical → Medium → Nice-to-have. Each has a stable ID
> (permanent — never reused). Status is one of: `todo`, `in-progress`, `done`, `wont-fix`.
> Pick an item by ID to work it next (e.g. "let's do C1").
>
> Sources: parallel read-only scan — maintainability pass on `ShadertoyISFKit/` (conversion
> engine) + `App/TrueISFEditor/` (SwiftUI/Metal app), and a CSO security pass. Security overall
> verdict: **SHIP** (lethal trifecta structurally broken in every LLM context; findings below
> are durability gaps to close before the public GitHub launch, not live exploits).

## Critical

### C1 — GLSLCallParser silently mis-parses calls containing comments → black-screen export
- **Status:** done
- **Resolved:** `parseArgs` + `replaceCall` now track `//` and `/* */` spans so parens/commas inside comments aren't counted as arg structure and calls inside comments aren't rewritten; `SamplerRewriter.binding(forChannelArg:)` parses the leading `iChannelN` so a trailing comment in the channel arg still binds. New `GLSLCallParserTests` (6 cases). 199 tests green.
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLCallParser.swift:45-56`
- **Why it matters:** `parseArgs` counts only literal `(` `)` `,` and ignores comments. A real shader writing `texture(iChannel0, /* offset (px) */ uv)` makes the `(` inside the comment increment depth so the close paren never returns to 0 → the call is left **un-rewritten** → `texture(iChannel0,…)` reaches the transpiler as an undeclared identifier → black screen. A `,` inside a comment splits one arg into two and breaks the `args.count == arity` gate the same way. This is the engine's most-used transform (`SamplerRewriter`, `CommonChannelRewriter` both call it) and comments inside calls are common in real Shadertoy source — high likelihood, large blast radius, the exact silent-black-screen class this project exists to eliminate.
- **Recommend:** Skip `//`…EOL and `/*`…`*/` spans inside `parseArgs` (and the `matchesIdentifier` lookbehind). Best done as part of M3 (shared scanner), but can be fixed standalone first.
- **Safe to fix now?** yes — isolated to `GLSLCallParser`, covered by the sampler tests + `scripts/corpus-run.sh`.

### C2 — ShadertoyClient.apiURL force-unwraps a URL built from untrusted shader id → hard crash
- **Status:** done
- **Resolved:** `apiURL` is now `throws` — validates the id is alphanumeric (Shadertoy's format) and throws `.invalidShaderID` instead of force-unwrapping; the single internal caller already propagates. Added `invalidShaderID` error case + a throwing-on-malformed-id test.
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ShadertoyClient.swift:36-38`
- **Why it matters:** `URLComponents(string: "…/shaders/\(id)")!` and `c.url!` crash the process if `id` contains a space, `#`, or other URL-illegal character. `id` is user-supplied (pasted URL / manual entry), so a malformed paste is a plausible hard crash rather than a handled error.
- **Recommend:** Percent-encode `id` into the path (or build via `URLComponents` path components) and return optional / throw `ShadertoyClientError` instead of force-unwrapping; verify callers handle it.
- **Safe to fix now?** yes — isolated; check call sites consume the new optional/throw.

### C3 — ISFHeader detection bails on a leading non-header comment → header missed + double-header written
- **Status:** done
- **Resolved:** `blockRange` now scans forward past leading non-header `/* */` blocks (license/credit) to find the real `/*{ … }*/` header, so `parse` succeeds and `write` replaces it instead of prepending a duplicate. Added leading-comment parse + write-no-duplicate tests.
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFHeader.swift:114-120`
- **Why it matters:** `blockRange` finds the *first* `/* … */`, checks whether it's a JSON object, and returns `nil` if not — it never scans forward. Any shader with a leading license/credit block comment before the ISF header (very common in shared `.fs` files) defeats detection entirely: `parse` throws `noHeader`, and `write` then **prepends a second header**, corrupting the file the user round-trips.
- **Recommend:** If the first block isn't a JSON object, scan forward for the next `/* { … } */` rather than giving up.
- **Safe to fix now?** yes — isolated, covered by header round-trip tests.

### C4 — GLSLLint/OutputInitializer treat `inout vec4` as `out vec4` → injected zero wipes carried state
- **Status:** done
- **Resolved:** `\bout` word boundary in both patterns (`\b` correctly fails inside `inout`); 3 new tests incl. mixed out+inout same-name case proving only the `out` signature is injected. 209 tests green, corpus 74/78 (no change).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLLint.swift:26`, `Rewriters/OutputInitializer.swift:21`
- **Why it matters:** Both patterns start `out\s+vec4` with no left word boundary, so `inout vec4 col` helper params match as `out vec4`. An `inout` accumulator (`void addGlow(inout vec4 col){ col += g; }`) is mis-detected as uninitialized, and OutputInitializer's injection regex replaces **all** matching signatures — `col = vec4(0.0);` lands at the top of the inout function, wiping the caller's value. Silent wrong/black render, zero diagnostics: the engine's #1 bug class.
- **Recommend:** `\bout\s+vec4` in both patterns (`\b` correctly fails between `in` and `out`) + regression test.
- **Safe to fix now?** yes — one line each, no ordering implications.

### C5 — Common helper bodies never receive uniform rewrites → `iTime` inside a Common function ships raw
- **Status:** todo
- **Interim (2026-07-08, plan Task 1.2b):** `CommonUniformRewriter.unrewrittenBodyUniforms` detects body-scope uniform uses with no param declaration anywhere and ISFConverter emits a loud warning-severity ConversionWarning — the failure is no longer silent. Real scope-aware rewrite still pending (Phase 3, behind the pixel gate). PM requires an explicit ship/hold call on this for launch.
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/CommonUniformRewriter.swift:27`
- **Why it matters:** The param-shadow protection is indiscriminate — **all** brace-depth>0 code is skipped, not just shadowed names. `float n(vec2 p){ return sin(p.x + iTime); }` — extremely common in real Common tabs — reaches the final `.fs` with `iTime` intact → transpile fail → black import. Tests only cover the param-shadow case. Likely a real slice of remaining corpus failures.
- **Recommend:** Protect a uniform name inside a body **only when that function's parameter list declares it**; rewrite otherwise. Needs the function scanner (ties into M3).
- **Safe to fix now?** wait — designed change with corpus validation (ideally after the pixel-truth render gate exists).

### C6 — `iMouse` in Common code is handled nowhere → undeclared identifier
- **Status:** done
- **Resolved:** iMouse is now a standard `UniformRewriter` rule (xy mirrored into zw, "pressed") instead of an ISFConverter special case — the scope-aware `CommonUniformRewriter` picks it up at Common file scope for free, param-threaded `iMouse` stays protected; `includeMouse` detection now also scans `splicedCommon`; the inline conditional rewrite block in ISFConverter is gone and the pipeline stage doc renumbered (15→14). Body-scope Common iMouse inherits C5's design (unchanged). 3 new tests; corpus 74/78 (no change).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift:48` (detection scans pass code only), `:93-120` (Common path has no iMouse step); `Rewriters/UniformRewriter.swift` has no iMouse rule
- **Why it matters:** A Common tab with `#define M iMouse` or file-scope `vec4 m = iMouse;` never gets rewritten and never sets `includeMouse` → undeclared `iMouse` → transpile fail → black import, even when a pass also uses iMouse.
- **Recommend:** Check `splicedCommon` for `\biMouse\b` when setting `includeMouse`; apply the vec4-mirror rewrite to Common file-scope runs (via CommonUniformRewriter so param-threaded `iMouse` stays protected).
- **Safe to fix now?** yes for detection + file-scope; body-scope inherits C5's design.

### C7 — Nested sampler calls are never rewritten (texture-inside-texture)
- **Status:** done
- **Resolved:** `GLSLCallParser.replaceCall` now recursively rewrites each parsed arg before invoking the transform, so calls nested inside a matched call's args (the distortion/feedback idiom) are converted too; bounded by nesting depth, transform-nil path unchanged. 2 new tests incl. end-to-end `texture(iCh0, uv + texture(iCh1, uv).xy)` → both `IMG_NORM_PIXEL`. Corpus 74/78 (no change).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLCallParser.swift:29-41` (`i = endIdx + 1` skips the whole matched call; args never re-scanned)
- **Why it matters:** `texture(iChannel0, uv + texture(iChannel1, uv).xy)` — the standard distortion/feedback idiom — leaves the inner call raw; the bare-identifier fallback then emits `texture(iChannel1img, uv)`. Host-dependent wrong sampling or transpile failure; audio/cubemap special handling (FFT/wave split, `_dirToEquirect`) silently lost.
- **Recommend:** Run each `replaceCall` to a fixpoint (re-scan output until no change) or rewrite `args` recursively before `transform`. Bounded — replacements never reintroduce the function names.
- **Safe to fix now?** yes, with tests.

### C8 — No dirty-document guard anywhere → one stray click destroys unsaved work
- **Status:** done
- **Resolved:** One choke point `EditorViewModel.canReplaceDocument()` guards open()/newUntitled()/loadImported()/loadExample() (Remix open-in-editor routes through loadImported): dirty doc → NSAlert confirm (injectable closure for tests); declining keeps the document + sets a status message. 4 new tests (declined/confirmed/clean/import paths).
- **Where:** `App/TrueISFEditor/Models/ISFFile.swift` (`isDirty` tracked, never consulted); `Views/LibraryView.swift:39-42`; `EditorViewModel.swift:91,103,113,127`; `Remix/RemixStudioView.swift:242`
- **Why it matters:** The library list is selection-driven — a single click replaces the document. Open/new/example/import/remix-open all silently discard unsaved edits with zero confirmation. Straight data loss.
- **Recommend:** One choke-point guard in `EditorViewModel` (`guard !file.isDirty || userConfirms()`) before any document replacement.
- **Safe to fix now?** yes — additive, small, testable.

### C9 — CameraSource releases the previous CVMetalTexture while the GPU may still read it
- **Status:** todo
- **Where:** `App/TrueISFEditor/CameraSource.swift:51-54` (vs `MetalPreviewController.swift:304-309` binding it in-flight)
- **Why it matters:** Each new frame overwrites `retained` — the only strong ref to the previous `CVMetalTexture` — while a command buffer may still be reading its `MTLTexture`. Apple requires holding the CVMetalTexture until GPU completion; the cache can recycle the IOSurface mid-read → tearing/corruption.
- **Recommend:** Small ring of recent CVMetalTextures, or release via `commandBuffer.addCompletedHandler`.
- **Safe to fix now?** yes — isolated to `CameraFrameProvider`.

### C10 — Camera permission denied → silent black forever; capture session never stops
- **Status:** todo
- **Where:** `App/TrueISFEditor/CameraSource.swift:70-73` (init only fails on texture-cache alloc); `SourceRouter.swift:84-85` (fallback never triggers); no `stopRunning()` exists anywhere
- **Why it matters:** On permission-denied the "camera unavailable ⇒ default pattern, never black" fallback never fires — the input renders black forever, the exact class this app's doctrine forbids. And once `SharedCamera` starts, the camera (and indicator light) stays on for the app's lifetime even after every input switches away — privacy + energy.
- **Recommend:** Authorization-aware state (fallback to pattern + "camera denied" hint) now; stop-the-session-when-unused via a small refcount design after.
- **Safe to fix now?** yes for the denied path; wait for session-stop (needs design).

### C11 — `EditorViewModel.open()` skips header sync → old header spliced into the new file
- **Status:** done
- **Resolved:** `open()` now calls `headerModel.syncFromText` like every other load path and clears `conversionReportTitle`; `newUntitled()` clears the stale report too. 3 new tests incl. header-tabs-sync-on-open. App suite 180 tests green.
- **Where:** `App/TrueISFEditor/EditorViewModel.swift:91-101` (no `headerModel.syncFromText`, unlike `newUntitled`/`loadImported`/`loadExample`); `HeaderAuthoringModel.swift:45-47` (writes from its own cached `currentSource`); `conversionReportTitle` not cleared in `open()`/`newUntitled()`
- **Why it matters:** The Inputs/Passes tabs keep the **previous** document's header after opening from the library; a GUI edit there splices the old header into the new file — real file corruption. Plus a stale "Imported X" report banner floats over unrelated documents.
- **Recommend:** `headerModel.syncFromText(file.source)` + `conversionReportTitle = nil` in both paths; regression test.
- **Safe to fix now?** yes.

## Medium

### M1 — OutputInitializer runs on the merged multi-pass file → cross-pass false negative → NaN/black pass
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLLint.swift:24-37` (consumed by `OutputInitializer.swift:18`, invoked at `ISFConverter.swift:139,144` — line refs drifted; re-verified 2026-07-08, still reproduces; C4 compounds this same code)
- **Why it matters:** Uninitialized-accumulator detection scans the whole concatenated file and dedups output names. Multipass shaders almost always name the output `O`/`fragColor` in every pass; if pass 0 plainly assigns `O` and pass 1 accumulates into `O` before assigning, the global "first plain `=` before first compound" test sees pass 0's plain assignment first → pass 1 is **not** flagged or auto-initialized → it stays NaN/black. Silent, and exactly the bug this file exists to fix.
- **Recommend:** Run the detector per-pass body (before `GLSLBodyBuilder` concatenation, while each pass's `mainImage` is isolated).
- **Safe to fix now?** wait — depends on reordering relative to `GLSLBodyBuilder`; validate against the corpus.

### M2 — GLSLGlobalScanner misses comma-separated / multi-line globals → silent cross-pass collision
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLGlobalScanner.swift:22-23`
- **Why it matters:** The header pattern needs `TYPE NAME (=|;)` on one line. `float a, b, c;` matches only up to `a`, sees `,`, and **fails entirely** → the declaration is invisible to `GLSLFunctionDedup` and `GLSLPassNamespace`. If two passes both declare `float a, b;`, the cross-pass collision those rewriters exist to prevent slips through to the transpiler as a redefinition error. (Re-verified 2026-07-08: additionally, `float a = 1., b = 2.;` matches as a single Def named `a` — namespacing renames `a` and leaves `b` colliding.)
- **Recommend:** Handle multi-declarator lists in the scanner, or emit a conversion warning when a depth-0 comma-list declaration is detected so the failure isn't silent.
- **Safe to fix now?** wait — changing the scanner shifts dedup/namespace behavior; validate against the corpus.

### M3 — Five duplicate hand-rolled GLSL char-scanners (comment/brace/paren) that disagree
- **Status:** todo
- **Where:** `Rewriters/GLSLGlobalScanner.swift:40,63`, `Rewriters/GLSLFunctionScanner.swift:57`, `Rewriters/CommonUniformRewriter.swift:42-84`, `Rewriters/GLSLCallParser.swift:45`, `ShaderAssist/ShaderAssistResponseParser.swift:17`
- **Why it matters:** Five separate state machines each walk characters tracking "in `//` / `/* */` / paren depth / brace depth," and they don't agree on what they handle (some skip comments, `GLSLCallParser.parseArgs` ignores them — see C1). A fix to comment-handling has to be made in up to five places and they silently diverge — the accumulation pattern that already produces this engine's bugs. (Re-verified 2026-07-08: **divergence has grown since the C1 fix** — CallParser is now comment-aware but Global/Function scanners still accept match positions inside block comments (M14); `CommonChannelRewriter.chan` vs `SamplerRewriter.binding` disagree on trailing-comment args (M16); only ShaderAssistResponseParser handles string literals. A shared scanner structurally absorbs C5's design, M14, M18, M19, and N2.)
- **Recommend:** Extract one `GLSLScanner` primitive (a cursor yielding chars with `inLineComment`/`inBlockComment`/`braceDepth`/`parenDepth` flags) and build all five consumers on it. C1 and N2 fold into this.
- **Safe to fix now?** wait — touches the parsing core of every rewriter; do it behind `scripts/corpus-run.sh`.

### M4 — FixRuleEngine re-implements rewriter fixes with divergent (sometimes opposite) mappings
- **Status:** done
- **Resolved:** `texture2DRule` now suggests `IMG_NORM_PIXEL` (normalized UV) to match the batch `SamplerRewriter` — was `IMG_PIXEL` (pixel coords), the opposite space. `reservedWordRule` now uses the batch rewriter's shared `usr_` prefix (exposed `GLSLReservedIdentifierRewriter.prefix` as internal) — was a `name_` suffix. `tanhRule`'s intentional divergence (single-line local polyfill vs GLSLCompat's guarded global) is now documented in-code. Existing tests updated to the aligned behavior. 200 tests green.
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/FixRuleEngine.swift:13-41` vs `Rewriters/SamplerRewriter.swift:27-32`, `Rewriters/GLSLReservedIdentifierRewriter.swift:23`, `Rewriters/GLSLCompat.swift:17-24`
- **Why it matters:** The same three problems are solved two ways. `texture2DRule` maps to `IMG_PIXEL` (pixel coords) while `SamplerRewriter` maps to `IMG_NORM_PIXEL` (normalized) — **opposite coordinate spaces**, so the interactive "fix" produces a visually wrong result vs. the batch converter. `reservedWordRule` suffixes `_` while the rewriter prefixes `usr_`; `tanhRule` injects a bare polyfill while `GLSLCompat` emits a `#if __VERSION__`-guarded one. A user hitting the same issue via two paths gets two inconsistent answers, and canonical-mapping changes don't propagate.
- **Recommend:** Have `FixRuleEngine` rules delegate to the same constants/helpers the rewriters use, or document explicitly why the interactive path differs.
- **Safe to fix now?** yes — FixRuleEngine output is advisory (user-reviewed), not on the batch path.

### M5 — FixRuleEngine uses unbounded substring replacement → corrupts unrelated tokens
- **Status:** done
- **Resolved:** `reservedWordRule` replaced the unbounded `replacingOccurrences(of: name)` with a `\b<name>\b` word-boundary regex (folded into the M4 change). Added `testReservedWordRenameRespectsWordBoundaries` proving a short reserved word (`long`) renames the standalone token but leaves `prolong` intact (the old bug produced `pro_long`). 200 tests green.
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/FixRuleEngine.swift:15,26,36`
- **Why it matters:** `src.replacingOccurrences(of: name, with: name + "_")` is a non-word-boundary, all-occurrences replace. For a short reserved word (`in`, `long`, `new`) the suggested edit rewrites it inside other identifiers — `inside` → `_inside`, `prolong` → `pro_long` — presenting a broken "fix" to the user as correct. `GLSLReservedIdentifierRewriter` already uses `\b…\b`; this path has no guard.
- **Recommend:** Use a word-boundary regex (`\b<name>\b`), mirroring the rewriter.
- **Safe to fix now?** yes — isolated.

### M6 — Cancelling a ShaderAssist/Remix run doesn't kill the CLI subprocess
- **Status:** done
- **Resolved:** Added `ProcessRunning.cancel()` (default no-op for test doubles); `RealProcess` is now a class tracking the live `Process` and `cancel()` does SIGTERM→SIGKILL. Both runners wrap the detached await in `withTaskCancellationHandler { … } onCancel: { proc.cancel() }` and throw `CancellationError` instead of mapping the killed-process exit to a failure. `ShaderAssistViewModel` catch guards on `Task.isCancelled`. New `testCancellationTerminatesProcessAndDoesNotReportFailure` proves the wiring. **STAGED:** the live SIGTERM-kills-the-real-CLI behavior wants one on-device smoke (unit test uses a double).
- **Where:** `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift:72-74`, `CodexRunner.swift:35-37`, abandoned by `ShaderAssist/ShaderAssistViewModel.swift:240-247` (run at `:190`)
- **Why it matters:** `provider.run` runs inside `Task.detached{…}.value`; a detached task isn't cancelled by parent cancellation and awaiting `.value` doesn't resume early. So `cancel()` only *abandons the result* — the `claude`/`codex` CLI runs to completion or the 240s timeout, burning subscription tokens + CPU. Hitting "run" again spawns a second CLI while the first is alive (they stack). The SIGTERM→SIGKILL path only fires on timeout, never on user cancel.
- **Recommend:** Give `ProcessRunning.run` a cancellation hook (retain the `Process`, `terminate()` via `withTaskCancellationHandler` on Task cancel); at minimum terminate the live process in `ShaderAssistViewModel.cancel()`.
- **Safe to fix now?** wait — touches the `ProcessRunning` protocol seam the tests inject; coordinate with `RemixGenerator` and the test doubles. Blocks M7.

### M7 — Remix Studio batch has no Stop control
- **Status:** done
- **Resolved:** `RemixStudioModel` now owns the generation `Task` via `startGeneration()`/`cancelGeneration()`; cancelling propagates through the generator's `withTaskGroup` to each provider's cancellation handler (M6) and terminates the CLIs. `RemixGenerator` labels a cancelled child `.failed("cancelled")`. Added a destructive **Stop** button shown while `isGenerating`. **STAGED:** Stop-button UX + live batch-termination need on-device confirmation.
- **Where:** `App/TrueISFEditor/Remix/RemixStudioModel.swift:80-111`, `Remix/RemixStudioView.swift:132-155`
- **Why it matters:** `generate()` awaits the whole `withTaskGroup`; `isGenerating` stays true until every child returns or times out. With batchSize up to 8, maxConcurrent 2, 420s per-child timeout, a wedged provider locks the studio for up to ~4×420s with no escape — and per M6 those CLIs can't be killed either.
- **Recommend:** Hold the generation `Task`, add a model `cancel()` + a Stop button, propagate cancellation into the runner.
- **Safe to fix now?** wait — depends on M6's cancellation plumbing.

### M8 — Live-preview "freeze" cap never pauses the MTKView → all cards render full-rate
- **Status:** done (STAGED — on-device verification REQUIRED before closing)
- **Resolved:** Added `MetalPreviewController.setPaused(_:)` (sets `mtkView.isPaused`) and `drawOneFrame()`. `RemixThumbnailView` now pauses non-animating cards (so GPU work actually stops) and pushes a single frame — including when a frozen card finishes compiling, so it shows its result rather than pre-compile black. Builds + 166 tests green.
- **STAGED / on-device test needed** (render-path change, unobservable in unit tests): (1) non-live cards visibly freeze and drop GPU/thermal load; (2) frozen cards show their compiled frame, not black; (3) promoting a card to favorite/live resumes animation. Per render-path rule: if any card goes black, revert this item.
- **Where:** `App/TrueISFEditor/MetalPreviewController.swift:52-55` vs `Remix/RemixThumbnailView.swift:27-35`, `Remix/RemixStudioModel.swift:148-157`
- **Why it matters:** Each child card hosts its own `MetalPreviewController` whose `MTKView` is created `isPaused = false` with no pause API, so `draw(in:)` runs continuously at display refresh **regardless of the `animating` flag**. The `maxLivePreviews`/`shouldAnimate` cap only governs an *additional* `renderOnce()`; it never pauses the view. A batch of 8 children + 2 parents all render full-rate — exactly the thermal/battery load the cap was meant to prevent (LazyVGrid recycling compounds it).
- **Recommend:** Add `setPaused(_:)` to `MetalPreviewController` (sets `mtkView.isPaused`); in `RemixThumbnailView.updateNSView`, pause when `!animating` and render a single frame.
- **Safe to fix now?** yes — isolated to the controller + thumbnail view.

### M9 — Provider-construction switch duplicated between ShaderAssist and Remix
- **Status:** done
- **Resolved:** Added `AssistProviderFactory.make(kind:defaults:)` as the single source for the `.claude→ClaudeCodeRunner / .codex→CodexRunner` mapping + binary-path resolution; both `ShaderAssistViewModel` and `TrueISFEditorApp` call it. Removed the now-redundant `binaryOverride` seam from `ShaderAssistViewModel` (it duplicated `defaults.string("claudeBinaryPath")`) and its 11 test call sites + the EditorScreen wiring. 166 tests green.
- **Where:** `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift:47-56` and `App/TrueISFEditor/TrueISFEditorApp.swift:11-23`
- **Why it matters:** The `.claude → ClaudeCodeRunner` / `.codex → CodexRunner` mapping (incl. the UserDefaults keys `claudeBinaryPath`/`codexBinaryPath`) is written twice. A new provider, or a change to binary resolution, must be edited in both or the two AI surfaces silently diverge.
- **Recommend:** Extract `AssistProviderFactory.make(kind:defaults:)` and call from both.
- **Safe to fix now?** yes — pure refactor, no behavior change.

### M10 — AppModel mixes settings persistence with conversion orchestration (early god-object)
- **Status:** done
- **Resolved:** Extracted `SettingsStore` (apiKey/Keychain + binary paths + assist provider/model prefs + their save methods + CLI-found statics). `AppModel` is now conversion-only; `convert()` reads the key fresh from `KeychainStore` (the codebase's existing pattern). `SettingsView` binds `SettingsStore`; `TrueISFEditorApp` and `ShadertoyImportSheet` each own a `SettingsStore` for the settings sheet, separate from the conversion `AppModel`. 166 tests green.
- **Where:** `App/TrueISFEditor/AppModel.swift:12-61` (prefs/keychain/CLI paths) alongside `:63-177` (fetch/convert/paste pipeline)
- **Why it matters:** `AppModel` is both the Settings model (`SettingsView(model:)`) and the import/convert engine; the two responsibilities share no state but every settings change recompiles a file that also owns the WebKit fetcher. As ShaderAssist/Remix prefs grow it accumulates unrelated `@Published`s — the early shape of a god-object.
- **Recommend:** Split a `SettingsStore` (persisted prefs + keychain) out from the conversion logic.
- **Safe to fix now?** wait — `SettingsView` and `TrueISFEditorApp` both bind to it; do as a focused refactor.

### M11 — Codex runner retains the file-read leg; trifecta held open by network-default alone
- **Status:** done
- **Resolved:** Pinned the Codex sandbox as a named invariant `CodexRunner.sandboxMode = "read-only"` with an in-code note that read-only constrains writes not reads (an injected shader can still read `~/.ssh`/`.env`; only the network-off default stops exfil), so it must never be raised to `workspace-write`/`danger-full-access` (which also enable network). Added `testCodexSandboxIsPinnedReadOnlyAndNeverEscalated` asserting the run never emits a write/network-enabling sandbox flag. (Dropping Codex as a provider remains a product call, not taken here.) 171 tests green.
- **Where:** `App/TrueISFEditor/ShaderAssist/CodexRunner.swift:25-26`
- **Why it matters:** `-s read-only` constrains *writes*, not *reads* — the model can still execute shell that reads any user-readable file (`~/.ssh/id_*`, `~/.aws/credentials`, `.env`). The only thing stopping exfil of an injected shader's read is that Codex disables network in `read-only` by default. The whole defense rests on one un-asserted external default; if a future Codex changes it, or the user runs a network-enabled profile, an injected shader comment becomes a live trifecta. (The Claude path has no such exposure — it removes execution entirely.)
- **Recommend:** Fail-closed invariant: never allow a Codex sandbox above `read-only`, assert network is off, document in code that read-only ≠ no-file-read; consider pinning `--cd` to a throwaway temp dir. Or drop Codex as a provider (product call).
- **Safe to fix now?** yes — a comment + assertion (provider removal is a product decision). Close before public launch.

### M12 — Tool-restriction defense depends on un-pinned external CLI flag semantics (fail-open on update)
- **Status:** done
- **Resolved:** Added `ClaudeCodeRunner.minVerifiedVersion = (2,1,175)`, `parseVersion`, and `isBelowVerifiedFloor` (true only when the version parses AND is below floor — unknown format never cries wolf). `run()` does an off-main best-effort `claude --version` probe (injectable; the app factory wires the real probe, tests inject nil/stub) and emits a one-time non-gating "SECURITY: CLI older than verified" transcript warning when confidently below floor. 5 tests cover the parser + below/at-floor wiring. **Minor STAGED note:** the exact real `claude --version` output format is assumed `…M.N.P…`; confirm once on-device that a genuinely-old CLI triggers the warning (low risk — non-gating, silent on unrecognized format). A hard version-gate or capability self-test was deliberately NOT taken (would block runs + needs a UX decision).
- **Where:** `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift:62-64` (see the v2.1.175 note at `:49-51`)
- **Why it matters:** The trifecta is broken today only because `--tools ""`/`--disallowedTools LSP` do what was verified on claude CLI **v2.1.175** — the code comment itself records that `--tools ""` alone left LSP exposed until patched, proving semantics shift between versions. The app runs the *user's* auto-updating CLI, so a future flag rename/default change would silently re-arm the removed legs with zero code change and no signal.
- **Recommend:** Fail-closed — detect CLI version (`claude --version`) and refuse/warn outside a known-good range, or run a one-shot capability self-test confirming a tool invocation is actually rejected before enabling assist.
- **Safe to fix now?** yes. Close before public launch.

### M13 — Conversion pipeline ordering is load-bearing but split/hidden across two files
- **Status:** done
- **Resolved:** Added an authoritative ordered 15-stage list to the `ISFConverter.convert` header comment — including the two stages buried in `GLSLBodyBuilder` (10a `GLSLPassNamespace`, 10b `GLSLPassMacroScoper`) and the key ordering invariants — plus a pointer comment in `GLSLBodyBuilder.build`. Documentation only, zero execution change (the structural lift of those stages into `ISFConverter` is deferred — it would reorder calls and needs corpus validation; see M3-class items below).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift:29-141` (orchestration) + `Builders/GLSLBodyBuilder.swift:13,19` (where `GLSLPassNamespace` + `GLSLPassMacroScoper` are actually invoked)
- **Why it matters:** Conversion is a ~12-stage ordered pipeline where order is correctness-critical (line-continuation splice first; macro-expand before per-pass `mainImage` rename; dedup after namespace; compat polyfills prepended last), documented only in prose. Two stages are buried in `GLSLBodyBuilder` and don't appear in `ISFConverter`'s readable sequence, so a maintainer reorganizing the converter can't see them, nothing asserts the ordering, and a wrong order fails silently as a black shader.
- **Recommend:** Lift namespacing/macro-scoping into the visible `ISFConverter` sequence (or document the full ordered stage list in one header comment); consider modelling stages as an explicit array of transforms.
- **Safe to fix now?** wait — pure refactor but must preserve exact order; do under the corpus.

### M14 — Global/Function scanners accept regex matches inside block comments → phantom defs
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLGlobalScanner.swift:30-36`, `Rewriters/GLSLFunctionScanner.swift:28-36`
- **Why it matters:** `depth()`/`braceMatchEnd()` skip comments when counting, but nothing checks whether the match position itself sits inside `/* … */`. A commented-out helper/global becomes a Def → spurious cross-pass renames; worst case `GLSLFunctionDedup` deletes the **real** definition and keeps the commented text. Commented-out variants are common in Shadertoy source.
- **Recommend:** "In-comment at position" check from the shared scanner.
- **Safe to fix now?** wait — fold into M3.

### M15 — Common-tab audio/cubemap dispatchers degrade incorrectly
- **Status:** done
- **Resolved:** Dispatchers now mirror SamplerRewriter's binding semantics: audio bindings split FFT/waveform by read-y in both tex and texel dispatchers; a cubemap-bound channel's tex dispatcher takes `vec3 dir` and projects via `_dirToEquirect` (mixed cube/2D across passes warns + samples dir.xy). 3 new tests. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/CommonChannelRewriter.swift:84-85` (vs `SamplerRewriter.swift:91-99`)
- **Why it matters:** The dispatcher samples `IMG_NORM_PIXEL(b.glslName, uv)` flat: for audio that's the FFT sampler at raw uv with no FFT/wave y-split — waveform reads silently return spectrum data; for cubemaps the call site passes a `vec3` direction into a `vec2` param → type-mismatch compile error.
- **Recommend:** Replicate `normSample`'s audio split in the dispatcher; add a vec3-param `_chN_tex` overload using `_dirToEquirect` for cubemap channels.
- **Safe to fix now?** yes.

### M16 — `CommonChannelRewriter.chan()` diverged from `SamplerRewriter.binding(forChannelArg:)`
- **Status:** done
- **Resolved:** `chan()` now delegates to the shared `GLSLCallParser.channelIndex(forArg:)` (extracted from SamplerRewriter, trailing-comment tolerant); SamplerRewriter uses the same helper. 1 new test. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `CommonChannelRewriter.swift:31-35` vs `SamplerRewriter.swift:66-77`
- **Why it matters:** The per-pass parser tolerates a trailing comment in the channel arg (`iChannel0 /* src */`); the Common one requires the whole trimmed token to `Int`-parse — same input, undeclared `iChannel0` in Common. M3's divergence claim, live and growing.
- **Recommend:** Extract and share one channel-arg parser (SamplerRewriter's version).
- **Safe to fix now?** yes.

### M17 — Synthesized `main()`'s `vec4 c` temp is exposed to leaked pass macros
- **Status:** done
- **Resolved:** Dispatch temp renamed `c` → `_isf_passColor` in `GLSLBodyBuilder` (in-code note on why it must not be a short macro-capturable name); dispatch assertions updated + 1 new test. Corpus 74/78 (no change).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Builders/GLSLBodyBuilder.swift:35-37`; `Rewriters/GLSLPassMacroScoper.swift:42-53` never scans the generated `main()`
- **Why it matters:** A pass's object-like `#define c …` (routine in golfed Shadertoy code) stays live at `main()` → `vec4 c;` expands to garbage → compile fail.
- **Recommend:** Rename the temp to `_isf_passColor` (one line) and/or treat the synthesized `main()` as a pass when the scoper computes mentions.
- **Safe to fix now?** yes.

### M18 — Pass-vs-Common macro collisions unscoped
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLPassMacroScoper.swift:22` (takes only `passBodies`)
- **Why it matters:** Common `#define A …` + a pass `#define A …` → "macro redefined; different substitutions" — the exact class the scoper exists to fix, across a boundary it can't see.
- **Recommend:** Plumb `commonCode` into the scoper.
- **Safe to fix now?** wait — fold into a scoper revision (with M3/M14).

### M19 — iChannel/iMouse/iResolution detection matches inside comments → junk header inputs
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift:48-49,65,101,163-171`
- **Why it matters:** `// TODO try iChannel2 here` yields a phantom stub image input + warning in the published `.fs`; a commented `iMouse` adds a mouse input and triggers the rewrite pass. Users see inputs that don't exist.
- **Recommend:** Comment-strip before the detection scans (shared scanner; or an interim detection-only strip).
- **Safe to fix now?** wait — fold into M3 (interim strip acceptable earlier).

### M20 — Paste path routes helper params through the unprotected whole-string UniformRewriter
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderFactory.swift:33-38` (markerless paste = whole blob as one Image pass) + `ISFConverter.swift:51`; assumption documented at `ISFConverter.swift:89-92`
- **Why it matters:** The "pass bodies don't declare uniform-named parameters" assumption only holds when helpers live in Common. A full shader pasted as one blob with a `vec2 iResolution`-style helper param emits `vec2 vec3(RENDERSIZE, 1.0)` → syntax error. Loud, but it's the fallback path users hit when Cloudflare blocks the fetch.
- **Recommend:** Use the scope-aware rewriter for pass bodies too (with C5's redesign).
- **Safe to fix now?** wait — same design change as C5.

### M21 — `texture (iChannel0, uv)` — space before paren — is not rewritten
- **Status:** done
- **Resolved:** `replaceCall` skips spaces/tabs between the identifier and `(`. 1 new test. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLCallParser.swift:29-31` (requires `(` immediately after the identifier)
- **Why it matters:** Valid GLSL, occasionally seen; falls through to the bare-identifier rename with the same host-dependent consequences as C7.
- **Recommend:** Skip whitespace between identifier and `(`.
- **Safe to fix now?** yes.

### M22 — `textureSize`/`texelFetchOffset`/`textureGrad`/`textureProj` pass through silently
- **Status:** done
- **Resolved:** `SamplerRewriter` emits a warning-severity ConversionWarning when textureSize/texelFetchOffset/textureGrad/textureProj is called on an iChannel — left as-is textually but no longer silent. 2 new tests. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/SamplerRewriter.swift` (no handling)
- **Why it matters:** `textureSize(bufA, 0)` survives conversion; whether it compiles depends entirely on the host's sampler declaration — and the failure is silent.
- **Recommend:** Emit a conversion warning at minimum.
- **Safe to fix now?** yes (warning only).

### M23 — `FixRuleEngine.tanhRule` quick-fix emits a nested function definition → can never compile
- **Status:** done
- **Resolved:** tanhRule is guidance-only (`edit: nil`) with the copyable polyfill + add-at-file-top instructions in the explanation — TextEdit can't express insert-at-top+rewrite-line, and the old single-line edit produced guaranteed-invalid nested-function GLSL. Test updated. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/FixRuleEngine.swift:46-54`
- **Why it matters:** The fix replaces the diagnostic line — by definition inside a function body — with `float tanh_(float x){…}` + the rewritten line: a nested function definition, invalid GLSL, guaranteed second compile error presented to the user as a "fix".
- **Recommend:** Two-part edit (polyfill prepended at file top + line rewrite), or reuse GLSLCompat's prepend.
- **Safe to fix now?** yes — interactive path only.

### M24 — Zero convertible passes converts "successfully" to a black shader
- **Status:** done
- **Resolved:** `PassBuilder` appends an error-severity warning ("no convertible render passes … would render black") when buffers+images is empty (sound/common-only shaders). 1 new test. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Builders/PassBuilder.swift:36-42` + `ISFConverter.swift:37` → emits `void main() {\n\n}`
- **Why it matters:** A shader with only sound/common passes (sound-only shaders exist on Shadertoy) yields a valid-looking `.fs` that renders black, with only a per-pass "skipped" note.
- **Recommend:** Hard error-severity warning ("nothing convertible") or throw.
- **Safe to fix now?** yes.

### M25 — Stale compile results race in `MetalPreviewController.load` (no generation token)
- **Status:** done
- **Resolved:** Monotonic `loadGeneration` in MetalPreviewController; `applyCompile` drops results from superseded loads. Test proves a bad-then-good load burst never publishes the stale error. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/MetalPreviewController.swift:60-81`
- **Why it matters:** `load(B)` resets state synchronously, but a still-in-flight `applyCompile` for A (posted from `transpileQueue`) can land after — A's scene/inputs/diagnostics briefly published as valid for B, and `imageSources.updateInputs` gets the wrong input set. Self-correcting but visible.
- **Recommend:** Monotonic load ID captured per compile; `applyCompile` drops results whose ID ≠ current.
- **Safe to fix now?** yes.

### M26 — Deactivated Metal engine and closed output window keep rendering forever
- **Status:** todo
- **Where:** `App/TrueISFEditor/PreviewCoordinator.swift:56-62` (`switchEngine` never pauses Metal); `OutputWindow.swift` (no `willClose` handling; `isReleasedWhenClosed = false`)
- **Why it matters:** `setPaused`/`drawOneFrame` are only called by `RemixThumbnailView` — switching to WebKit or closing the pop-out leaves an MTKView (internal timer; doesn't reliably stop when detached) driving `draw(in:)` with a loaded scene indefinitely. Invisible GPU/battery burn.
- **Recommend:** Pause the deactivated engine in `switchEngine`; observe `NSWindow.willCloseNotification` in `OutputWindowManager` to pause/unload. **Bundle with M8's still-pending on-device verification** (same `setPaused` API).
- **Safe to fix now?** yes — render-path change: one change, observe on-device, revert if black.

### M27 — SettingsView can run a blocking login-shell CLI probe on the main thread per keystroke
- **Status:** done
- **Resolved:** SettingsView probes CLI presence async (`task(id:)` + 250ms debounce + `Task.detached`; `locateBinary` made nonisolated on both runners); status row shows a checking state. No more login-shell on the main thread per keystroke. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/SettingsView.swift:29,38` → `BinaryLocator.locate` (`ShaderAssist/ClaudeCodeRunner.swift:167-173`: `/bin/zsh -lc "command -v …"`, 5s timeout) inside SwiftUI `body`
- **Why it matters:** When the CLI isn't at a known path, every keystroke in the path field re-runs a synchronous login shell — slow shells (nvm etc.) freeze Settings.
- **Recommend:** Compute found-status async on appear + debounced path changes into `@State`.
- **Safe to fix now?** yes.

### M28 — `RemixThumbnailView.Coordinator.reported` never resets on source change
- **Status:** done
- **Resolved:** `Coordinator.sourceChanged()` re-arms the fire-once compile report when `loadedISF` changes; test proves a recycled coordinator reports the new source's compile. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/Remix/RemixThumbnailView.swift:29-31,59` (+ identity reuse at `RemixLineageTreeView.swift:117`)
- **Why it matters:** A recycled coordinator never delivers the new shader's compile result or snapshot — a newly promoted parent keeps the old tree swatch, and a bad replacement is reported as the previous result.
- **Recommend:** Reset `reported = false` (and re-arm the snapshot) when `loadedISF` changes in `updateNSView`.
- **Safe to fix now?** yes.

### M29 — One forced GPU frame per paused Remix card per transcript line
- **Status:** done
- **Resolved:** `shouldPushFrozenFrame(wasAnimating:animating:)` — frozen cards get one frame on the animating→frozen transition only (post-compile push unchanged). 4-case test. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/Remix/RemixThumbnailView.swift:34-36`
- **Why it matters:** `updateNSView` calls `drawOneFrame()` whenever `!animating`; during generation every transcript append republishes the model → one forced frame per paused card per line, thousands of times per batch — quietly undoing M8's thermal win.
- **Recommend:** `drawOneFrame()` only on an actual `animating` true→false transition (track previous value in the coordinator).
- **Safe to fix now?** yes.

### M30 — PreviewControlsView state dictionaries survive document changes
- **Status:** todo
- **Where:** `App/TrueISFEditor/Views/PreviewControlsView.swift:6-10`
- **Why it matters:** `floats/bools/points/colors/longs` are keyed by input name and never cleared — load shader 2 with an input named like shader 1's and the slider shows the stale value; first drag jumps.
- **Recommend:** Clear the dictionaries when `coordinator.inputs` identity changes.
- **Safe to fix now?** yes.

### M31 — Pop-out output window recompiles on every keystroke
- **Status:** done
- **Resolved:** `OutputWindowManager.update` routes through a new `Debouncer` (300ms, matching the inline preview); Debouncer unit-tested (burst→one call, spaced→both, cancel). App suite 193 tests green.
- **Where:** `App/TrueISFEditor/Views/EditorScreen.swift:96` → `OutputWindow.swift:30-33` (no debounce; the inline preview debounces 300ms at `EditorViewModel.swift:186`)
- **Why it matters:** With the pop-out open, typing runs a full GLSL→SPIRV→MSL transpile per keystroke.
- **Recommend:** Route both consumers through one debounced compiled-source event from `EditorViewModel`.
- **Safe to fix now?** yes.

### M32 — WebKit runtime errors are swallowed by the diagnostics pipeline
- **Status:** done
- **Resolved:** WebKit `runtime` messages now set `compileValid = false` so EditorViewModel's diagnostics mapping surfaces them; delegate body extracted to testable `handleScriptMessage`. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/WebKitPreviewController.swift:87-88` (`"runtime"` message sets `compileError` but leaves `compileValid == true`); `EditorViewModel.swift:193-195`
- **Why it matters:** Runtime errors never reach the diagnostics panel or gutter — the user sees a broken render with "No diagnostics". The exact silent-failure UX this app exists to prevent.
- **Recommend:** Set `compileValid = false` on runtime error, or publish runtime errors on their own channel.
- **Safe to fix now?** yes.

### M33 — SuggestionGoalSheet burns a ~30s LLM run on every open and can't be cancelled by dismissal
- **Status:** done
- **Resolved:** Sheet `.onDisappear` calls new `cancelSuggestionGoalsIfRunning()` — cancels only `running(.suggestionGoals)` so an Apply-started rewrite is never killed. Goal-CACHING half intentionally deferred (interacts with the fingerprint flow). App suite 193 tests green.
- **Where:** `App/TrueISFEditor/Views/SuggestionGoalSheet.swift:64-66`
- **Why it matters:** `onAppear` unconditionally calls `requestSuggestionGoals` — reopening via "Change Goal"/"Start Over" discards prior goals and spends a subscription CLI run even if immediately cancelled; `dismiss()` leaves `state == .running`, keeping main-screen buttons disabled until the CLI finishes on its own.
- **Recommend:** Cancel the run on dismiss now; cache goals per source fingerprint (wait — interacts with the fingerprint flow).
- **Safe to fix now?** cancel-on-dismiss yes; caching wait.

### M34 — Event-input pulse can be dropped before a frame renders
- **Status:** todo
- **Where:** `App/TrueISFEditor/Views/PreviewControlsView.swift:131-137`
- **Why it matters:** Sets `"true"` then `"false"` on the next main-queue turn; nothing guarantees a `draw(in:)` between the two — on a paused/slow view the event never fires.
- **Recommend:** Engine-level auto-clear after one rendered frame (or reset via a draw-count hook).
- **Safe to fix now?** wait — needs engine support; document meanwhile.

### M35 — `WindowGroup` + app-singleton NSViews breaks "New Window"
- **Status:** done
- **Resolved:** `Window("TrueISFEditor", id: "main")` replaces WindowGroup — ⌘N can no longer spawn a second window that steals the singleton NSViews. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/TrueISFEditorApp.swift:182`; `ISFPreviewView.swift:10-14`
- **Why it matters:** macOS offers ⌘N "New Window" on WindowGroups by default; `vm.editor.webView` / `vm.preview.nsView` can only live in one hierarchy, so two windows steal the views back and forth.
- **Recommend:** `Window` scene instead of `WindowGroup` (one line) unless multi-window is actually planned.
- **Safe to fix now?** yes.

### M36 — CrashLog rewrites the whole pretty-printed file on the main thread per event
- **Status:** done
- **Resolved:** CrashLog persistence debounced (500ms) with `flush()` + NSApplication.willTerminate flush; hard crashes unaffected (async-signal-safe pending file). Tests updated + debounce test. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/CrashLog.swift:29-36,50-53`
- **Why it matters:** Consecutive-identical dedup doesn't cover alternating errors — two different compile errors while typing defeat it, rewriting a 500-event JSON file on every debounce tick.
- **Recommend:** Debounce persistence; write on termination + periodic flush.
- **Safe to fix now?** yes.

### M37 — ISFSceneSource blocks the main thread with synchronous transpile + `waitUntilCompleted`
- **Status:** todo
- **Where:** `App/TrueISFEditor/ISFSceneSource.swift:57-61` (and `defaultPatternTexture` `:82-86`), via `SourceRouter.makeSource`
- **Why it matters:** Selecting a heavy library shader as an input source stalls the UI for the full transpile + probe render + GPU wait.
- **Recommend:** Move probe validation to the background like `MetalPreviewController.load` does.
- **Safe to fix now?** wait — touches the router's synchronous fallback contract; do deliberately.

### M38 — ISFMSLSafeRender drops the VVMTLTextureImage wrapper immediately (possible pool recycle mid-read)
- **Status:** todo
- **Where:** `App/TrueISFEditor/ISFMSLSafeBridge.mm:56-57`
- **Why it matters:** Returns the bare `MTLTexture` and releases the wrapper; if VVMTLPool recycles backing textures on wrapper dealloc, an in-flight read can see next-frame reuse — same family as C9.
- **Recommend:** Verify VVMetalKit's pool semantics first; if real, retain the wrapper until command-buffer completion.
- **Safe to fix now?** wait — investigate before changing.

### M39 — ShaderAssist/Remix skill preambles read maker-machine-only paths → public users silently get a degraded AI
- **Status:** todo
- **Where:** `App/TrueISFEditor/ShaderAssist/SkillPreamble.swift` (`defaultPaths` → `~/.claude/skills/isf-shader-development/` etc.), `Remix/RemixPrompt.swift` (`system()`)
- **Why it matters:** Those paths exist only on this machine. Every public user silently falls back to the ~10-line primer — ShaderAssist and Remix ship materially dumber than tested, with no signal. **Launch-critical.**
- **Recommend:** Bundle the skill texts as app resources (user path as override). Also fold in open action item `trueisf-skillpreamble-12k-cap-20260708`: fix the 12,000-char skill-preamble cap in `SkillPreamble` so the bundled texts (incl. the new 964-shader technique catalog) aren't silently truncated.
- **Safe to fix now?** yes.

## Nice-to-have

### N1 — Rewriters share no protocol; return shapes are ad hoc
- **Status:** todo
- **Where:** across `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/` — `GLSLCompat.swift:39`/`SamplerRewriter.swift:6` return a `Result` struct; `UniformRewriter.swift:15`/`GLSLFunctionDedup.swift:14`/`GLSLReservedIdentifierRewriter.swift:25` return bare `String`; `GLSLPassNamespace.swift:20`/`GLSLPassMacroScoper.swift:22` return `[String]`
- **Why it matters:** Wiring a new rewriter into the pipeline means re-learning each one's shape (carries warnings? takes all passes or one body?). A `GLSLRewriter` protocol would make the pipeline composable and the convention discoverable.
- **Recommend:** Define a common rewriter signature; converge the return shapes.
- **Safe to fix now?** wait — broad but mechanical; do once, behind tests.

### N2 — GLSLReservedIdentifierRewriter rewrites reserved words inside comments
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLReservedIdentifierRewriter.swift:25-34`
- **Why it matters:** The `\b…\b` replace runs over the whole body including comments, so `// new approach` becomes `// usr_new approach` — harmless to compilation but pollutes the output a user reads/edits.
- **Recommend:** Skip comment spans (folds into M3's shared scanner).
- **Safe to fix now?** yes.

### N3 — ShaderAssistResponseParser.decode discards the underlying DecodingError
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ShaderAssist/ShaderAssistResponseParser.swift:48-53`
- **Why it matters:** `try? JSONDecoder().decode(...)` collapses any failure into `unparseable(raw:)`, losing the field-level reason — so when Claude returns almost-valid JSON (one missing key), debugging means re-reading the raw blob by hand. `ShadertoyInternalParser.malformed(detail:)` already shows the better pattern. (Re-verified 2026-07-08, plus a sibling: `ShaderAssistResponseParser.swift:12` — an `is_error == true` envelope returns `""`, so the eventual `unparseable(raw: "")` throws away the CLI's actual error message (quota/auth/timeout) that was sitting in `result`.)
- **Recommend:** Capture and attach the `DecodingError` detail; preserve the `is_error` envelope's `result` text in the thrown error.
- **Safe to fix now?** yes.

### N4 — SamplerRewriter bare-identifier audio rewrite drops the waveform sampler
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/SamplerRewriter.swift:54-57`
- **Why it matters:** When an audio `iChannelN` is threaded as a bare value (not a `texture()` call), the loop replaces it with `b.glslName` (FFT sampler only); `auxName` (waveform) is lost → half-correct audio reaction, no warning. Rare.
- **Recommend:** Emit a warning for bare-identifier use of an audio/cubemap binding.
- **Safe to fix now?** yes.

### N5 — RemixGenerator has a duplicate, production-unused initializer
- **Status:** done
- **Resolved:** The `model:` init (used by tests) is now a `convenience` init delegating to the `modelProvider:` designated init instead of duplicating the 5-field body. API unchanged; 171 tests green.
- **Where:** `App/TrueISFEditor/Remix/RemixGenerator.swift:26-44` (two near-identical inits `model:` vs `modelProvider:`; only `modelProvider:` is used in production at `TrueISFEditorApp.swift:11`)
- **Why it matters:** Two constructors to keep in sync; a reader can't tell which is canonical.
- **Recommend:** Keep only `modelProvider:`; have the test-only `model:` convenience (if needed) delegate to it.
- **Safe to fix now?** wait — confirm no test references the `model:` init first.

### N6 — Repeated transcript/log bounding logic
- **Status:** todo
- **Where:** `App/TrueISFEditor/ShaderAssist/ShaderAssistViewModel.swift:251`, `Remix/RemixStudioModel.swift:132`, `CrashLog.swift:34,73`, `ImportLog.swift:27` — all hand-roll `if count > N { removeFirst(count - N) }`
- **Recommend:** An `Array.boundedAppend(_:max:)` helper or a `RingBuffer`.
- **Safe to fix now?** yes.

### N7 — Duplicated renderpass-to-comment formatting in AppModel
- **Status:** done
- **Resolved:** Extracted `AppModel.annotatedSource(_:)`; both `convert()` and `convertPastedCode()` call it instead of repeating the `renderpass.map { … }.joined(...)` banner formatting.
- **Where:** `App/TrueISFEditor/AppModel.swift:99-101` and `:161-163` — identical `renderpass.map { "// ===== …" }.joined(...)`
- **Recommend:** Extract `static func annotatedSource(_ shader:) -> String`.
- **Safe to fix now?** yes.

### N8 — Fragile substring-based auth error classification
- **Status:** todo
- **Where:** `App/TrueISFEditor/ShaderAssist/ClaudeCodeRunner.swift:14-21` (`AssistErrorMapper`)
- **Why it matters:** Any non-zero exit whose output merely *contains* "auth"/"login"/"api key" is reported as "isn't signed in" — even when the real failure is unrelated (a shader comment or error text with one of those tokens misfires).
- **Recommend:** Tighten to known CLI auth phrasings/exit codes, or append it as a hint rather than replacing the real message; add a unit test.
- **Safe to fix now?** yes.

### N9 — Unconditional `print` in harvest + debug exit paths ship in the release binary
- **Status:** todo
- **Where:** `App/TrueISFEditor/WebKitShaderFetcher.swift:78` (`print("HARVEST poll…")`); env-gated `SHADERTOY_DEBUG_*` blocks at `App/TrueISFEditor/TrueISFEditorApp.swift:31-187`
- **Why it matters:** Not dead (the debug harnesses are real corpus tooling) but they ship in release and write to stdout; `harvestShaderIDs` prints on every poll. Noise/surface area.
- **Recommend:** Gate the harvest `print` behind a debug flag; consider `#if DEBUG` around the env-gated harnesses.
- **Safe to fix now?** yes.

### N10 — Keychain item missing kSecAttrAccessible / device scoping
- **Status:** done
- **Resolved:** `KeychainStore.save` now sets `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and checks the `SecItemAdd` `OSStatus` (asserts on failure instead of silently swallowing it).
- **Where:** `App/TrueISFEditor/KeychainStore.swift:10-18`
- **Why it matters:** The Shadertoy key is correctly in the Keychain but `SecItemAdd` omits `kSecAttrAccessible`, inheriting the default rather than declaring intent, and isn't pinned to this device. Low blast radius (Silver-tier read-only key) but explicit is better.
- **Recommend:** Set `kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; optionally check the `OSStatus` so a silent save failure is visible.
- **Safe to fix now?** yes.

### N11 — Debug-fetch affordance bypasses the shaderID validator
- **Status:** todo
- **Where:** `App/TrueISFEditor/TrueISFEditorApp.swift:34-43` (`SHADERTOY_DEBUG_FETCH` / `--debug-fetch` → `fetchShader(id:)` with no validation)
- **Why it matters:** Normal paths validate the id through `ShadertoyURL.shaderID(from:)` (alphanumeric 3–16) before the fetcher; this debug door doesn't. Real exploitability is low (literal host, parameterized in-page JS, requires launch-env control) but it's an inconsistency.
- **Recommend:** Route the debug id through `ShadertoyURL.shaderID(from:)`, or compile the debug affordances out with `#if DEBUG`.
- **Safe to fix now?** yes. (2026-07-08 CSO rescan: `#if DEBUG`-gating the four debug env blocks is the **single named pre-public-launch item** — it resolves N11 and most of N9 in one ~10-minute change.)

### N12 — TestPatternCatalog crashes if bundle resources are missing entirely
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/TestPatternCatalog.swift:39` (`default` falls back to `all[0]`)
- **Why it matters:** An empty resource bundle (broken packaging) turns a fallback into an index-out-of-range crash.
- **Recommend:** Return an inline hardcoded pattern instead.
- **Safe to fix now?** yes.

### N13 — GLSLCompat adds a duplicate tanh polyfill when the shader defines its own
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLCompat.swift:41`
- **Why it matters:** A shader already carrying a `float tanh(` polyfill gets a second one inside the `#if __VERSION__ < 130` block → redefinition on old GL backends.
- **Recommend:** Check for a user definition before adding.
- **Safe to fix now?** yes.

### N14 — UniformRewriter: nested-bracket `iChannelResolution[idx[0]]` survives → loud undeclared identifier
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/UniformRewriter.swift:24` (`[^\[\]]*` can't match nested brackets)
- **Why it matters:** Rare, but the miss is silent at conversion time and only surfaces as a transpile error.
- **Recommend:** Handle one nesting level or emit a warning on `iChannelResolution[` with unmatched inner brackets.
- **Safe to fix now?** yes.

### N15 — HeaderBuilder audio `MAX: 256` vs Shadertoy's 512-wide audio texture
- **Status:** done
- **Resolved:** Audio MAX 256→512 in HeaderBuilder to match Shadertoy's 512-wide audio texture (skill-verified: sampling is normalized, positions unaffected, resolution doubles). 1 new test. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Builders/HeaderBuilder.swift:18-21`
- **Why it matters:** If hosts honor MAX as bin count this halves FFT resolution vs the shader's original sampling assumptions.
- **Recommend:** Verify intended bin count against ISF hosts (VDMX) and align.
- **Safe to fix now?** yes — RESOLVED BY SKILL (2026-07-08): the isf-shader-development spec documents `MAX: 256` as the house convention, and all sampling is normalized (`IMG_NORM_PIXEL(audio, vec2(uv.x,…))`) so bin count affects resolution only, never coordinates. For *converted Shadertoy* shaders, bump to 512 to match Shadertoy's texture width — free fidelity, positions unaffected.

### N16 — ShadertoyClient retries a 429 with zero backoff
- **Status:** done
- **Resolved:** `fetchShader` gains `retryDelayNanos` (default 1.5s) and sleeps before transient retries; tests pass 0 to stay fast, plus a new 429-backoff test. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ShadertoyClient.swift:52-64`
- **Why it matters:** The immediate retry almost certainly 429s again; the retry is dead weight.
- **Recommend:** Small delay (e.g. 1–2s) before the single retry.
- **Safe to fix now?** yes.

### N17 — Conversion warning order is nondeterministic run-to-run
- **Status:** done
- **Resolved:** Both `referencedChannelIndices` iteration sites in ISFConverter now `.sorted()` — stub warnings emit in ascending channel order. 1 new test. 223 tests green; corpus 74/78, baseline pass list (7 transient FETCH-FAILs re-run 7/7 OK).
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift:65,101` (iterating a `Set`/`Dictionary`)
- **Why it matters:** Noisy diffs in corpus logs; makes regression comparison harder than it needs to be.
- **Recommend:** Sort before emitting.
- **Safe to fix now?** yes.

### N18 — Mouse `point2D` normalization assumption unverified against real hosts
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Builders/HeaderBuilder.swift:24-29` + `ISFConverter.swift:57-59` (`mouse * RENDERSIZE` assumes hosts deliver 0–1-normalized point2D)
- **Why it matters:** Several hosts treat point2D as pixel-space — mouse-driven shaders would be wrong by a factor of RENDERSIZE in VDMX.
- **Recommend:** One live VDMX check; branch on the verified behavior.
- **Safe to fix now?** wait — needs an on-host observation first. (2026-07-08: the updated isf-shader-development spec confirms point2D "units depend on host" — the risk is real, the VDMX check is the only way to close it.)

### N19 — Engine doc/dead-code cluster
- **Status:** todo
- **Where:** `Builders/GLSLBodyBuilder.swift:50` (comment says "first occurrence"; `renameMainImage` replaces all — behavior fine, comment wrong); `ShadertoyISFKit.swift` (`version` unused); `Rewriters/SamplerRewriter.swift:103-106` (trivial pass-through `replaceCall` wrapper)
- **Recommend:** Fix the comment; delete/inline the rest.
- **Safe to fix now?** yes.

### N20 — App dead-code cluster
- **Status:** todo
- **Where:** `App/TrueISFEditor/Views/SuggestionsPanel.swift:14-23` (two-arg init, zero call sites); empty `WKNavigationDelegate` conformances (`WebKitPreviewController.swift:8`, `CodeEditorView.swift:14`); `TrueISFEditorApp.swift:77-84` (no-op "poll up to 5s" loop that always breaks at 5); `WebKitShaderFetcher.swift:59` (`harvestShaderIDs(sort:count:)` ignores `sort` — misleading signature)
- **Recommend:** Delete / fix signatures.
- **Safe to fix now?** yes.

### N21 — WK message-handler retain cycles (latent leak)
- **Status:** todo
- **Where:** `App/TrueISFEditor/WebKitPreviewController.swift:33`, `CodeEditorView.swift:29` — `ucc.add(self)` with no `removeScriptMessageHandler` anywhere
- **Why it matters:** Objects are app-lifetime today so nothing leaks yet, but any future per-document/preview instantiation leaks a WKWebView each.
- **Recommend:** `WKScriptMessageHandler` weak-proxy pattern.
- **Safe to fix now?** yes.

### N22 — App duplicated-logic cluster
- **Status:** todo
- **Where:** VVMTLPool/ISFMSLCache bootstrap (`MetalPreviewController.swift:41-47` vs `ISFSceneSource.swift:32-38`); `jsStringLiteral` (`WebKitPreviewController.swift:62` vs `CodeEditorView.swift:85`); add-folder NSOpenPanel (`TrueISFEditorApp.swift:254-261` vs `EditorScreen.swift:270-277`); JSON encode/persist logic (`CrashLog` vs `ImportLog` — extends N6)
- **Recommend:** Extract shared helpers as each area is next touched (don't do a dedicated sweep).
- **Safe to fix now?** yes, opportunistically.

### N23 — Import log attributes the previous fetch's HTTP status to the current failure
- **Status:** done
- **Resolved:** `lastResponseStatus` reset to -1 at the start of every `fetchShader` — no more previous-fetch status attributed to the current failure. (One-line; not unit-harnessable — WKWebView-driven.) App suite 193 tests green.
- **Where:** `App/TrueISFEditor/AppModel.swift:59` (reads `webFetcher.lastResponseStatus`, which persists from the prior fetch)
- **Why it matters:** A challenge-timeout on fetch N+1 logs fetch N's status — actively misleading when debugging Cloudflare issues.
- **Recommend:** Clear `lastResponseStatus` at fetch start (or scope it per-fetch).
- **Safe to fix now?** yes.

### N24 — KeychainStore save failure is silent in release builds
- **Status:** done
- **Resolved:** `KeychainStore.save` returns the OSStatus, `saveErrorMessage(for:)` maps it (unit-tested, no live keychain writes), `SettingsStore.keySaveError` publishes it, SettingsView shows it in red. App suite 193 tests green.
- **Where:** `App/TrueISFEditor/KeychainStore.swift:22-24` (`assertionFailure` is a no-op in release)
- **Why it matters:** A failed save silently drops the API key for shipped users; they'll re-enter it and lose it again.
- **Recommend:** Return the `OSStatus` and surface failure in Settings.
- **Safe to fix now?** yes.

### N25 — Remix cosmetics cluster
- **Status:** todo
- **Where:** `Remix/RemixStudioModel.swift:64,132` (placeholders + seed nodes hardcode `mode: .crossover` — mutate-mode lineage records the wrong mode); `snapshots`/`history` grow unbounded; `RemixStudioView.swift:68` (transcript `ForEach(id: \.offset)` breaks row identity once the 2000-line bound starts dropping from the front); `RemixGenerator.swift:86-89` (on cancel, not-yet-launched slots still spawn a CLI process just to kill it — check `Task.isCancelled` before launching)
- **Recommend:** Fix as one small Remix-polish pass.
- **Safe to fix now?** yes.

### N26 — blitPipeline built once for the first colorPixelFormat, never invalidated
- **Status:** todo
- **Where:** `App/TrueISFEditor/MetalPreviewController.swift:330`
- **Why it matters:** A view whose pixel format changes after first build renders through a mismatched pipeline.
- **Recommend:** Rebuild when `colorPixelFormat` differs from the cached one.
- **Safe to fix now?** yes.

### N27 — Two SettingsStore instances can show diverged drafts
- **Status:** todo
- **Where:** app-level store + `ShadertoyImportSheet.swift:12`
- **Why it matters:** UI-only (values re-read from UserDefaults/Keychain at point of use), but two open settings surfaces can show different unsaved text.
- **Recommend:** Share one instance via environment.
- **Safe to fix now?** yes.
