# DESLOPPIFY — Cleanup Backlog

_Last scan: 2026-06-27 · branch: desloppify-cleanup · 11 open / 16 done (M8 + M12-probe staged) · remaining: M1/M2/M3 (corpus) + 8 N-tier_

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

## Medium

### M1 — OutputInitializer runs on the merged multi-pass file → cross-pass false negative → NaN/black pass
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLLint.swift:24-37` (consumed by `OutputInitializer.swift:18`, invoked at `ISFConverter.swift:121,126`)
- **Why it matters:** Uninitialized-accumulator detection scans the whole concatenated file and dedups output names. Multipass shaders almost always name the output `O`/`fragColor` in every pass; if pass 0 plainly assigns `O` and pass 1 accumulates into `O` before assigning, the global "first plain `=` before first compound" test sees pass 0's plain assignment first → pass 1 is **not** flagged or auto-initialized → it stays NaN/black. Silent, and exactly the bug this file exists to fix.
- **Recommend:** Run the detector per-pass body (before `GLSLBodyBuilder` concatenation, while each pass's `mainImage` is isolated).
- **Safe to fix now?** wait — depends on reordering relative to `GLSLBodyBuilder`; validate against the corpus.

### M2 — GLSLGlobalScanner misses comma-separated / multi-line globals → silent cross-pass collision
- **Status:** todo
- **Where:** `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLGlobalScanner.swift:22-23`
- **Why it matters:** The header pattern needs `TYPE NAME (=|;)` on one line. `float a, b, c;` matches only up to `a`, sees `,`, and **fails entirely** → the declaration is invisible to `GLSLFunctionDedup` and `GLSLPassNamespace`. If two passes both declare `float a, b;`, the cross-pass collision those rewriters exist to prevent slips through to the transpiler as a redefinition error.
- **Recommend:** Handle multi-declarator lists in the scanner, or emit a conversion warning when a depth-0 comma-list declaration is detected so the failure isn't silent.
- **Safe to fix now?** wait — changing the scanner shifts dedup/namespace behavior; validate against the corpus.

### M3 — Five duplicate hand-rolled GLSL char-scanners (comment/brace/paren) that disagree
- **Status:** todo
- **Where:** `Rewriters/GLSLGlobalScanner.swift:40,63`, `Rewriters/GLSLFunctionScanner.swift:57`, `Rewriters/CommonUniformRewriter.swift:42-84`, `Rewriters/GLSLCallParser.swift:45`, `ShaderAssist/ShaderAssistResponseParser.swift:17`
- **Why it matters:** Five separate state machines each walk characters tracking "in `//` / `/* */` / paren depth / brace depth," and they don't agree on what they handle (some skip comments, `GLSLCallParser.parseArgs` ignores them — see C1). A fix to comment-handling has to be made in up to five places and they silently diverge — the accumulation pattern that already produces this engine's bugs.
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
- **Why it matters:** `try? JSONDecoder().decode(...)` collapses any failure into `unparseable(raw:)`, losing the field-level reason — so when Claude returns almost-valid JSON (one missing key), debugging means re-reading the raw blob by hand. `ShadertoyInternalParser.malformed(detail:)` already shows the better pattern.
- **Recommend:** Capture and attach the `DecodingError` detail.
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
- **Safe to fix now?** yes.
