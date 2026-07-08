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

**Exit criteria (Phase 1):** all listed items `done` in DESLOPPIFY.md; kit + app suites green; corpus non-regressed; render-path items CONFIRMED on-device.

## Phase 2 — Launch pack (public GitHub release)

**Task 2.1 — M39: bundle AI skill texts + fix the 12k preamble cap (PM REWRITE finding).** The runtime hard-caps the concatenated preamble at 12,000 chars while `isf-shader-development/SKILL.md` alone is already 15,148 bytes — **ShaderAssist is silently truncating TODAY**, and the tool-stripped CLI (`--tools ""` etc.) means SKILL.md-linked reference files are structurally unreachable, so content must be *inlined*, not referenced. Scope: (a) raise/remove the cap or replace raw concatenation with a curated, purpose-built preamble assembled from the skill texts (incl. the 964-shader technique catalog); (b) re-derive the byte math from actual file sizes and add a no-truncation assertion + test; (c) bundle as app resources with `~/.claude/skills` as override. Closes action item `trueisf-skillpreamble-12k-cap-20260708`. Test: preamble resolves complete on a machine without the skills dir.
**Task 2.2 — N9 + N11: `#if DEBUG` the four debug env affordances** (CSO's single pre-launch ask). Gate: release build ignores `SHADERTOY_DEBUG_*`.
**Task 2.3 — LICENSE + attribution.** Repo LICENSE (Conner picks — see Decisions), in-app Acknowledgements (ISFGLSLGenerator BSD-3, glslang/SPIRV-Cross, exprtk/nlohmann MIT, ISFMSLKit/VVMetalKit), per the 06-09 license-check note.
**Task 2.4 — Release engineering.** `scripts/release.sh`: xcodebuild archive → notarize → staple → DMG. Verify on a clean user account.
**Task 2.5 — Onboarding.** README screenshots/GIF, bundled `samples/` gallery (10 converted `.fs`), first-run opens a sample (fold-in of new-shader templates if cheap).
**Task 2.6 — CI.** GitHub Actions: `swift test` + app build + cached-fixture corpus subset (`--cached` mode; fixtures gitignored/ToS-safe — CI runs the checked-in-safe subset).

**Exit criteria:** clean-machine install → import → export → load in VDMX works; CI green on a PR; CSO items closed.

## Phase 3 — Structural bet (ordering is the point)

**Task 3.1 — Pixel-truth render gate FIRST.** Extend corpus harness + import report: render 2–3 frames offscreen (`drawOneFrame`/`TextureSnapshot` exist), flag black/NaN/constant frames. This is the safety net every "wait: validate against corpus" item depends on — a compile-only corpus cannot see the bugs M1/M2/M3/C5 cause.
**Task 3.2 — Shared `GLSLScanner` + rewriter protocol (M3 + N1), absorbing** C5 (scope-aware uniform rewriting), M14 (comment-position checks), M18 (Common-aware macro scoper), M19 (detection comment-stripping), M20 (paste-path scope awareness), N2. Then M1 (per-pass lint) + M2 (multi-declarator scanner).
Gate: full suite + corpus with pixel gate; any pass-list regression blocks.

**Exit criteria:** one scanner primitive; C5/M1/M2/M14/M18/M19/M20/N2 closed; corpus pixel-pass count ≥ baseline.

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
6. **C5 launch call (PM-flagged):** ship v1 with C5 open (mitigated by the Task 1.2b loud warning, real fix in Phase 3) — or pull the full scope-aware rewrite forward, accepting corpus-regression risk without the pixel gate? Recommendation: warning now, fix in Phase 3.

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
