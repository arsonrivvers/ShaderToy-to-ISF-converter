# Pixel-Truth Render Gate — Design

**Date:** 2026-07-09 · **Plan:** Phase 3 Task 3.1 of `docs/superpowers/plans/2026-07-08-launch-hardening-and-elevation.md`
**Goal:** a compile-clean shader that renders black/NaN/garbage must be *visible* to the corpus harness and the import report. This is the safety net C5/M1/M2/M3 (and the Phase 4 Library Modernizer) depend on.

## Decisions (Conner, 2026-07-09)

1. **Severity:** BLACK and NAN are FAIL (block the pass-list baseline, same as a compile fail). STATIC is WARN (reported, non-blocking) — plenty of legitimate shaders are static.
2. **Image inputs:** bind a built-in deterministic test pattern to every `image` input before rendering — kills the false-black class and exercises the sampler-rewrite path (C7/M21 territory).
3. **Scope:** all three surfaces — the Shadertoy discovery corpus (`SHADERTOY_DEBUG_CORPUS`), the import report (`ImportLog`), and the ISF-library acceptance test (`CorpusRenderTests`).
4. **Analysis approach:** CPU readback (approach A). Render small offscreen frames, `getBytes`, analyze in pure Swift. No GPU reduction kernel, no CIContext (CIContext clamps NaN — it would hide the class we're catching).

## Components

All new code lives in the app target (it needs Metal + ISFMSLKit) except where noted.

### 1. `ISFMSLSafeRenderAtTime` (ISFMSLSafeBridge.h/.mm)

```objc
id<MTLTexture> _Nullable ISFMSLSafeRenderAtTime(ISFMSLScene *scene, NSSize size, double time,
                                                id<MTLCommandBuffer> cb,
                                                NSString * _Nullable * _Nullable errorOut);
```

Same C++ try/catch shell as `ISFMSLSafeRender`, wrapping `createAndRenderToTextureSized:atTime:inCommandBuffer:` (the API VVISF provides for non-realtime rendering). A shader that throws mid-render at t=0.5 yields a `RENDER-ERR` verdict instead of killing the harness.

### 2. `GateInputPattern` (new file, app target)

Generates one small (64×64, bgra8) deterministic texture on the CPU: a gradient-checker — per-quadrant distinct hues over an intensity gradient, no symmetry that could mask flipped/wrong-scaled sampling. Same bytes every run (no randomness, no time) — determinism is what makes the pass-list a baseline. One public entry:

- `makeTexture(device:) -> MTLTexture?`
- `bind(to scene: ISFMSLScene, inputs: [ISFPreviewInput])` — sets the pattern on every `image`-type input via the existing `ISFMSLSceneVal.create(with:)` + `setValue(_:forInputNamed:)` path.

### 3. `FramePixelStats` (new file, app target; pure analysis)

`static func analyze(texture:) -> FramePixelStats?` — caller has already committed + `waitUntilCompleted`. Reads `getBytes` and computes:

- `maxLuma: Double` — max over pixels of max(R,G,B), normalized 0–1.
- `nanCount: Int` — NaN/Inf component count (float formats only; on 8-bit formats always 0 — post-clamp NaN degrades to the black check, which is what it looks like anyway).
- `isConstant: Bool` — every pixel equals the first pixel.
- `digest: UInt64` — order-dependent FNV-1a style hash of the bytes, for cross-frame comparison.

Format support mirrors `TextureSnapshot`: `bgra8Unorm(_srgb)`, `rgba8Unorm(_srgb)`, `rgba16Float`, `rgba32Float`. Unsupported format → `nil` → verdict `UNSUPPORTED` (WARN, never FAIL — don't punish a shader for the engine's output format). The byte-level analysis takes a raw buffer + format so unit tests feed synthetic frames without a GPU.

### 4. `PixelGate` (new file, app target; pure verdict)

```swift
enum PixelVerdict: String { case ok = "OK", black = "BLACK", nan = "NAN",
                            constant = "STATIC", renderError = "RENDER-ERR",
                            unsupported = "UNSUPPORTED" }
static func verdict(_ frames: [FramePixelStats?]) -> PixelVerdict
```

Rules, in precedence order:
1. any frame nil → `RENDER-ERR` (FAIL) — caller maps a thrown render separately but nil analysis of a returned texture also lands here.
2. any `nanCount > 0` → `NAN` (FAIL).
3. **all** frames `maxLuma < 2/255` → `BLACK` (FAIL). All frames — a fade-in shader black only at t=0 passes.
4. all digests equal (and not black) → `STATIC` (WARN).
5. else `OK`.

FAIL set: `{BLACK, NAN, RENDER-ERR}`. WARN set: `{STATIC, UNSUPPORTED}`.

### 5. `MetalPreviewController.runPixelGate()` (extension on existing controller)

```swift
func runPixelGate(size: CGSize = .init(width: 320, height: 180),
                  times: [Double] = [0.0, 0.5, 1.5]) -> PixelVerdict
```

Orchestration: guard `scene != nil` → bind `GateInputPattern` to image inputs → for each `t`: make command buffer, `ISFMSLSafeRenderAtTime`, commit, `waitUntilCompleted`, `FramePixelStats.analyze` → `PixelGate.verdict`. Frames render **sequentially on the same scene** so persistent/feedback buffers accumulate across the three renders — multipass shaders warm up honestly. 320×180 matches the thumbnail render size already used by `ISFSceneSource`. Synchronous by design (~ms for 3 small frames); callers on the main actor are the headless corpus (fine) and a post-compile hook (dispatched off the render loop).

## Surface integration

### A. Discovery corpus (`TrueISFEditorApp.swift` + `scripts/corpus-run.sh`)

After `compileValid`, run `runPixelGate()`. Line format grows one column (tab-separated, pixel column always present):

```
<id>\tOK\tpixel=OK\twarnings=2
<id>\tOK\tpixel=STATIC\twarnings=0      ← WARN stays an OK line
<id>\tFAIL\tpixel=BLACK                  ← pixel FAIL is a FAIL line
<id>\tFAIL\t<compile error…>             ← compile fail: unchanged, no pixel column
```

Summary: `=== CORPUS compile 74/78 · pixel 71/78 OK ===`. `corpus-run.sh`'s live grep (`\tOK\t|\tFAIL\t|=== CORPUS`) already matches; no script change required beyond the header comment.

**Baseline expectation:** the 74/78 compile baseline will likely drop on the first pixel run — that is the gate working (black-but-compiling imports are exactly C5's failure mode). The first run's per-ID verdict list becomes the pixel baseline recorded in DESLOPPIFY/plan notes; from then on any pass-list regression blocks, same rule as today.

### B. ISF-library corpus (`CorpusRenderTests.swift`)

After `pollCompile` succeeds, run `runPixelGate()` and count verdicts. Report gains a pixel section (pass/black/nan/static/render-err counts + failing filenames). The lenient assertion stays (`report is the deliverable`) — this corpus is exploratory until the Phase 4 modernizer tightens it.

### C. Import report (`AppModel` / `ImportLog`)

`ImportEvent.Stage` gains `.rendered`. When an import-originated document's first compile completes in the preview, run the gate and record a second event:

- verdict OK → no event (don't spam the log with successes; the `converted` event already said ✓).
- WARN (`STATIC`/`UNSUPPORTED`) → `.rendered` event, outcome `.warning`, message e.g. `"pixel gate: STATIC (renders, never animates)"`.
- FAIL (`BLACK`/`NAN`/`RENDER-ERR`) → `.rendered` event, outcome `.error`, message e.g. `"pixel gate: BLACK — compiled but renders black"`.

Hook point: the import flow already knows the shaderID; the post-compile callback carries it to the event. Only import-originated compiles record events — local edits never touch the ImportLog. Decoding old persisted logs is unaffected (new enum case appears only in new records).

## Error handling

- Render throws (C++ exception) → `RENDER-ERR`, message from the bridge; harness continues to next shader.
- `scene == nil` / no compile → gate not run (compile failure already reported).
- Texture `getBytes` on an unsupported format → `UNSUPPORTED` (WARN).
- Pattern-texture creation fails (no device memory) → gate returns `RENDER-ERR` rather than silently rendering unbound.

## Testing

- **Unit (pure, no GPU):** `FramePixelStats` byte-level analysis on synthetic buffers — all-black, single NaN component, constant color, gradient; each supported format incl. bgra channel order. `PixelGate.verdict` precedence table incl. fade-in (black at t=0 only → OK) and all-black-all-frames → BLACK. `GateInputPattern` bytes digest is stable across calls.
- **Integration (GPU, `TrueISFEditorTests`, same pattern as `MetalPreviewControllerTests`):** four tiny inline ISF sources through the real controller — animated gradient → `OK`; `vec4(0)` → `BLACK`; `0.0/0.0` (via a uniform-defeating expression so the compiler can't constant-fold) → `NAN` on float output or `BLACK` on 8-bit; constant color → `STATIC`. Plus: an image-input shader that passes through the bound pattern → `OK` (proves binding works).
- **Corpus:** full discovery run (`scripts/corpus-run.sh`) to establish the pixel baseline; compile pass-list must be unchanged (the gate adds information, it must not disturb compilation).

## Out of scope

- Fixing anything the gate flags (that's C5/M1/M2/M3 work, unlocked by this).
- Audio/audioFFT inputs (no synthetic audio texture yet — inputs other than `image` render unbound as today; if this produces false blacks in practice, extend `GateInputPattern` then).
- Per-pass texture inspection (Phase 4 candidate; the gate sees the final composite).
- On-screen preview behavior — the gate never touches the live render loop.
