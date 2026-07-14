# Plan of Record — Launch Hardening & Elevation

_Date: 2026-07-08 · Author: Fable 5 session (4-agent audit + elevation scan) · Status: PROPOSED — awaiting Conner's phase approval + Phase 0 gate answers_

## Goal

Take TrueISFEditor from "built and mostly clean" to (a) **correct** — the silent-black-screen and data-loss bug classes eliminated, (b) **launch-ready** — public GitHub release with license/attribution/CI/onboarding in place, and (c) **elevated** — the highest-leverage features that make it a daily VJ instrument, not just a converter.

## Stack & baseline

- Native macOS: SwiftUI app (`App/TrueISFEditor/`, 10.7k LOC across 139 Swift files) + SPM engine (`ShadertoyISFKit/`), Metal preview via vendored ISFMSLKit/VVMetalKit, WebKit fallback, WKWebView Shadertoy fetcher, headless `claude`/`codex` CLI for ShaderAssist/Remix.
- Baseline: branch `desloppify-cleanup` @ `3005f1a`, clean tree, **200 kit tests green** (app tests via xcodebuild — last known 171 green).
- Corpora: conversion 74/78 (95%, saturated); render 776/896 (86.6% — ~84 of the 120 failures are legacy-ISF files the engine's own rewriters could modernize).
- Backlog: `DESLOPPIFY.md` refreshed 2026-07-08 — 61 open (8 critical) / 16 done. Security verdict **SHIP** (CSO rescan; one pre-launch ask).
- Docs-vs-code mismatches found: README/docs advertise audio-channel conversion but the native preview renders audio inputs dead (`MetalPreviewController` "audio/cube: still unsupported"); ShaderAssist/Remix prompts read `~/.claude/skills/...` paths that exist only on this machine (M39); the "763/896" memory figure conflated the two corpora.

## Definition of done (per phase, not global)

"Done" for a native Metal render-path change means **CONFIRMED on-device by Conner**, not tests-green (two-state rule). "Done" for engine changes means tests + `scripts/corpus-run.sh` regression-free. "Done" for launch means a stranger can clone/download, run, import, and export a working shader without touching Conner's machine.

---

## Phase 0 — Open gates (blocks merges, not work)

| Gate | What Conner must confirm on-device |
|---|---|
| M8 (STAGED) | Remix cards visibly freeze when non-live, show compiled frame (not black), resume on promote |
| M6/M7 smoke | Cancel/Stop actually kills the live `claude` CLI (Activity Monitor check) |
| M12 note | (low) old-CLI warning fires on a stale `claude` binary |
| Unmerged branches | `option-a-filter-inputs` (esp. display orientation) and `review-fixes`/`project-b` gates — then merge |

**Exit criteria:** each gate CONFIRMED or explicitly waived; merged branches recorded in memory.

## Phase 1 — Correctness strike (all "safe to fix now"; TDD; ~2 sessions)

**Task 1.1 — Engine batch A (silent-render killers).** C4 (`\bout` boundary — 2 lines + tests), C7 (fixpoint `replaceCall` for nested sampler calls), C6 (Common iMouse detection + file-scope rewrite), M17 (`_isf_passColor` rename).
Gate: new regression tests per item; `swift test` green; `scripts/corpus-run.sh` no regressions (compare pass list, not just count — warning order is nondeterministic until N17).

**Task 1.2 — Engine batch B (parity + honesty).** M15 (Common audio/cubemap dispatcher parity), M16 (shared channel-arg parser), M21 (whitespace before paren), M22 (warn on textureSize/texelFetchOffset/Grad/Proj), M24 (zero-convertible-passes = error), M23 (tanh quick-fix two-part edit), N17 (sort warnings — do first, makes corpus diffs deterministic), N15 (audio MAX 256→512 for converted shaders — skill-verified: normalized sampling means positions unaffected, fidelity doubles), N16 (429 backoff).
Gate: same as 1.1.

**Task 1.2b — C5 interim mitigation (PM REWRITE finding).** The real C5 fix (scope-aware Common-body uniform rewriting) stays in Phase 3 behind the pixel gate — but silent must become loud before launch: emit a warning-severity `ConversionWarning` when a Common function *body* contains a Shadertoy uniform name that isn't shadowed by that function's parameters ("iTime used inside a Common helper — not auto-rewritten; shader may fail to compile"). Detection-only, no rewrite, safe now.
Gate: unit test + corpus (warning counts may rise; pass list must not change).

**Task 1.3 — App batch A (data protection).** C8 (dirty-document guard, single choke point in `EditorViewModel` + test), C11 (header sync + report-title clear on `open()`/`newUntitled()` + test).
Gate: app tests green; manual: edit → click library item → confirm prompt appears.

**Task 1.4 — App batch B (camera + Metal lifecycle).** C9 (CVMetalTexture completed-handler release), C10 denied-path (auth-aware fallback + hint), M25 (compile generation token), M26 (pause on engine switch + output-window close — **bundles the M8 on-device verification**; render-path rule: one change, observe, revert if black), M38 investigation (VVMTLPool wrapper semantics — read vendor source, decide).
Gate: app tests + on-device observation (camera denied → test pattern; close pop-out → GPU% drops in Activity Monitor).

**Task 1.5 — App batch C (UX honesty + waste).** M32 (runtime errors reach diagnostics), M27 (async CLI probe), M28 (thumbnail `reported` reset), M29 (draw on transition only), M30 (controls-state reset), M31 (debounced output window), M33 cancel-on-dismiss, M35 (`Window` scene), M36 (CrashLog debounce), N23, N24.
Gate: app tests green; manual spot-checks per item.

**Task 1.6 — Live FPS / render-time readout (Conner, requested 2026-07-11).** Every live view surfaces frame rate + GPU render time: the editor's ISF preview panel first, then Remix Studio (at minimum the live/promoted child card) and the pop-out output window. Sketch: draw-cadence FPS measured in `MetalPreviewController.draw(in:)` + GPU ms via `commandBuffer.addCompletedHandler` (pairs naturally with C9's completed-handler work in Task 1.4 — build together); small toggleable overlay/status readout. Gate: on-device observation on a heavy shader.
- **CONFIRMED 2026-07-14 (Conner: "looking decent on our current build"):** editor preview readout (header row, "60 FPS · 1.3 ms GPU") + pop-out output window (capsule overlay) shipped — `RenderStats.swift` accumulator (windowed, ~2 Hz publish; 7 unit tests) fed from `MetalPreviewController.draw(in:)` + `addCompletedHandler`. Metal renderer only (WebKit shows nothing). Remix Studio card readout deferred. Same session: controls panel rebuilt crossfade-style (label + live value + compact slider, LazyVStack) and the fixed 210pt strip replaced with a draggable VSplitView. Gate open: observe FPS on a heavy shader + slider-drag smoothness on a high-input shader.

**Task 1.7 — Off-main render loop (OffspringEngine display-link port; Conner, requested 2026-07-14).** Root cause of preview stutter during slider drags: the MTKView self-drove on the main thread, so SwiftUI/AppKit layout starved `draw(in:)` (diagnosed against VJ_Code-crossfade's `MetalPreviewView.swift`, which documents the identical failure and its fix).
- **CONFIRMED 2026-07-14 (Conner: "massive massive upgrade"):** `DisplayLinkDriver` (CVDisplayLink → `view.draw()` off-main, ported retain/drain semantics) + `MetalRenderCore` (scene + all draw-path state behind one coarse lock; pixel gate and input edits serialize through it) + window-membership gating (`HostAwareMTKView`): the link runs only while the view is hosted and not user-paused — starting it at init deadlocked app launch intermittently (off-main layer setup on an unhosted view), and the gating also stops closed/pop-out/off-grid/WebKit-switched Metal views from ticking (finishes M26). `SourceRouter` grew a lock-protected `renderSource(for:)` mirror; `ImageSource` conformers dropped `@MainActor` (camera provider was already lock-safe from C9). Fallback: no CVDisplayLink → classic main-thread self-drive. App suite 240 green ×2 (6 new threading tests). Gate: heavy shader + slider drag with the FPS readout holding steady, on-device.

**Exit criteria (Phase 1):** all listed items `done` in DESLOPPIFY.md; kit + app suites green; corpus non-regressed; render-path items CONFIRMED on-device.

## Phase 2 — Launch pack (public GitHub release)

**Task 2.1 — M39: bundle AI skill texts + fix the 12k preamble cap (PM REWRITE finding).** The runtime hard-caps the concatenated preamble at 12,000 chars while `isf-shader-development/SKILL.md` alone is already 15,148 bytes — **ShaderAssist is silently truncating TODAY**, and the tool-stripped CLI (`--tools ""` etc.) means SKILL.md-linked reference files are structurally unreachable, so content must be *inlined*, not referenced. Scope: (a) raise/remove the cap or replace raw concatenation with a curated, purpose-built preamble assembled from the skill texts (incl. the 964-shader technique catalog); (b) re-derive the byte math from actual file sizes and add a no-truncation assertion + test; (c) bundle as app resources with `~/.claude/skills` as override. Closes action item `trueisf-skillpreamble-12k-cap-20260708`. Test: preamble resolves complete on a machine without the skills dir.
**Task 2.2 — N9 + N11: `#if DEBUG` the four debug env affordances** (CSO's single pre-launch ask). Gate: release build ignores `SHADERTOY_DEBUG_*`.
**Task 2.3 — LICENSE + attribution.** Repo LICENSE (Conner picks — see Decisions), in-app Acknowledgements (ISFGLSLGenerator BSD-3, glslang/SPIRV-Cross, exprtk/nlohmann MIT, ISFMSLKit/VVMetalKit), per the 06-09 license-check note.
**Task 2.4 — Release engineering.** `scripts/release.sh`: xcodebuild archive → notarize → staple → DMG. Verify on a clean user account.
**Task 2.5 — Onboarding.** README screenshots/GIF, bundled `samples/` gallery (10 converted `.fs`), first-run opens a sample (fold-in of new-shader templates if cheap).
**Task 2.6 — CI.** GitHub Actions: `swift test` + app build + cached-fixture corpus subset (`--cached` mode; fixtures gitignored/ToS-safe — CI runs the checked-in-safe subset).

**Exit criteria:** clean-machine install → import → export → load in VDMX works; CI green on a PR; CSO items closed.

**Phase 2 status (2026-07-14):** 2.1 M39 done (bundled skills + cap fix, earlier session). 2.2 done (N9/N11 `#if DEBUG`, earlier session). **2.3 done** — MIT LICENSE (Conner's pick), `THIRD_PARTY_LICENSES/` (ISFMSLKit aggregate incl. VVMetalKit/ISFGLSLGenerator/exprtk/nlohmann/PIN*, upstream glslang + SPIRV-Cross fetched and bundled, CodeMirror, interactive-shader-format), in-app Acknowledgements (Settings disclosure, full texts, resource-presence test). **Claude-only v1 shipped** (Conner's pick): `AssistProviderFactory.codexAvailable` — release builds hide the Codex surface and clamp a stale pref to Claude; debug keeps both. **2.4 done** — `scripts/release.sh` (Release archive → env-gated sign/notarize/staple → DMG); ad-hoc run verified: DMG mounts with app + Applications link + LICENSE, samples + acknowledgements present in the Release bundle. Clean-account + VDMX check remains manual. **2.5 done** — `samples/` gallery (4 ArsonRivvers originals — never third-party Shadertoy content), bundled as folder reference, "Samples" library source, first run opens a sample (each sample compile-tested through the Metal engine); README refreshed (install, features, license). **2.6 done** — `.github/workflows/ci.yml`: kit tests + app tests + Release-config build on macos-15 (corpus stays local: live fetch + ToS). Remaining before tagging a release: CSO repo pass, clean-account DMG smoke, notarization creds.

## Phase 3 — Structural bet (ordering is the point)

**Task 3.1 — Pixel-truth render gate FIRST.** ✅ **DONE 2026-07-09** (spec `docs/superpowers/specs/2026-07-09-pixel-truth-render-gate-design.md`, plan `2026-07-09-pixel-truth-render-gate.md`). `runPixelGate()` renders 3 frames at t=0/0.5/1.5 via a crash-safe `atTime:` bridge, deterministic pattern bound to image inputs, CPU readback; BLACK/NAN fail, STATIC warns. Wired into the discovery corpus, `CorpusRenderTests`, and the Import Log (`.rendered` events). **Pixel baseline: compile 74/78 (unchanged) · pixel 64/78 (50 OK + 14 STATIC); 10 BLACK** — see `docs/corpus-analysis-2026-07-09-pixel-baseline.txt`. Unlocks 3.2.
**Task 3.2 — Shared `GLSLScanner` + rewriter protocol (M3 + N1), absorbing** C5 (scope-aware uniform rewriting), M14 (comment-position checks), M18 (Common-aware macro scoper), M19 (detection comment-stripping), M20 (paste-path scope awareness), N2. Then M1 (per-pass lint) + M2 (multi-declarator scanner).
Gate: full suite + corpus with pixel gate; any pass-list regression blocks.

**Exit criteria:** one scanner primitive; C5/M1/M2/M14/M18/M19/M20/N2 closed; corpus pixel-pass count ≥ baseline.

✅ **DONE 2026-07-09** (spec `2026-07-09-shared-glsl-scanner-design.md`, plan `2026-07-09-shared-glsl-scanner.md`). One `GLSLScanner` primitive, all six walkers deleted; C5/M1/M2/M3/M14/M18/M20/N1/N2 closed. **Triage falsified the C5/M1/M2 BLACK hypothesis** — the real classes were two NEW bugs, fixed as `ZeroInitLocals` (M40: Metal lacks ANGLE's local zero-init — the golf-shader class, 6/10) and `InjectedNameGuard` (M41: user `mouse` shadowing the injected ISF input, 1/10). Kit 302 + app 227 tests green, Release build green; corpus: zero regressions, **BLACK→OK flips confirmed: XXVfRV, 33jcRR, 3XBBWD, wfX3WX** (+ lcXXzM/tXfBz2 pending a fetch window; wc33RN/wX33zX still black — second cause suspected, follow-up filed; M3BfzG needs live mouse = gate limitation; XtdSDn unknown). Also new: `SHADERTOY_DEBUG_GATE_TIMES` triage override; the 14 STATIC warns re-verified genuine at t≤8s.

## Phase 4 — Evolution (post-launch, leverage order)

1. **ISF Library Modernizer** — batch "modernize folder" running the existing rewriters over legacy `.fs` files with per-file diff/report (~776→~860/896; headline feature). Prereq: 3.1.
2. **Audio input in native preview** — mic/system audio → FFT+waveform texture via `SourceRouter` (closes the README-vs-preview mismatch; music-reactive imports come alive).
3. **Remix self-repair** — one bounded repair round-trip on `.failed` children.
4. **Syphon output** — the editor becomes a live source in the VJ rig.
5. **Per-pass preview** (check ISFMSLScene exposes per-pass textures first) · **visual import diff** · remaining approved queue (crossover controls, Suggestions redesign).

## Cut-lines (what slips first)

Phase 4 entirely → then 2.5 samples-gallery polish (keep ≥3 samples) → then Phase 1 Task 1.5 (UX honesty items) → then 1.4 M38 investigation. **Never cut:** Phase 1 Tasks 1.1–1.3, Phase 2 Tasks 2.1–2.3.

## Non-negotiables (block ship)

- C8/C11 fixed (data loss/corruption).
- C4/C6/C7 fixed (silent wrong-render on the tool's headline path).
- M39 **including the 12k-cap fix** + N9/N11 + LICENSE/attribution before the repo goes public.
- C5 either fixed or **explicitly accepted by Conner** for launch with the Task 1.2b loud warning in place (PM: same severity/class as C4/C6/C7 — cannot be silently deferred).
- No render-path change merges without on-device CONFIRMED.
- Tests accompany every logic change; corpus run after every engine batch.

## Deferred backlog

Everything else in `DESLOPPIFY.md` (N-tier clusters N19–N22, N25–N27, M34, M37, N4, N8, N18-pending-VDMX-check) — worked via the desloppify loop, one ID at a time.

## Decisions needed from Conner

1. **Phase 0 gate answers** (M8, M6/M7 smoke, two unmerged branches).
2. **License choice** for the public repo (MIT vs GPL-family — vendored deps are BSD/MIT/Apache-compatible either way).
3. **Ship target date** for the public launch (template placeholder was unfilled; June 15 slipped).
4. **Codex provider at launch:** keep (documented weaker posture) or Claude-only for v1? CSO is fine with either; product call.
5. **Scope check:** approve/reorder Phase 4 ranking (Modernizer first?).
6. **C5 launch call (PM-flagged):** ship v1 with C5 open (mitigated by the Task 1.2b loud warning, real fix in Phase 3) — or pull the full scope-aware rewrite forward, accepting corpus-regression risk without the pixel gate? Recommendation: warning now, fix in Phase 3. ✅ **CLOSED 2026-07-11 — MOOT/SHIPPED-FIXED:** the full scope-aware rewrite landed in Task 3.2 (`UniformRewriter.rewriteScoped`, 2026-07-09) behind the pixel gate, zero corpus regressions; C5 is `done` in DESLOPPIFY.md.

## Cost lens (CFO)

No recurring/metered infra anywhere (no crons, no hosting). Variable cost = Conner's own CLI subscription: Remix batch ≤ 8 children × ~37s runs (capped 2-concurrent), ShaderAssist runs on demand. M33 (fixed in 1.5) currently burns a ~30s run per sheet-open — the only live waste found. CI: GitHub Actions free tier for a public repo. No flags.

## Final gauntlet (before "ready")

1. `swift test` (kit) + xcodebuild test (app) + release build — all green.
2. `scripts/corpus-run.sh` full — pass list ≥ baseline, zero new failures.
3. Clean-account install from the DMG: import a Shadertoy URL, convert, preview, export, load the export in VDMX.
4. On-device sweep of every render-path change this plan touched (M8/M26/C9/C10) — CONFIRMED or reverted.
5. Live smoke of ShaderAssist + Remix on a machine WITHOUT `~/.claude/skills` (proves M39).
6. CSO final pass on the public repo (history, .gitignore, entitlements) — verdict SHIP.
7. DESLOPPIFY.md statuses + memory notes updated; handoff written.
