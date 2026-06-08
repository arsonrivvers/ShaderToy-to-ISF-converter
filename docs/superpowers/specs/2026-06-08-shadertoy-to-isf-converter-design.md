# Shadertoy → ISF Converter — Design

**Date:** 2026-06-08
**Status:** Approved (architecture), pending implementation plan
**Author:** ArsonRivvers + Chief of Staff

## Problem

The ISF Editor's "Import from Shadertoy" feature is broken/defunct. There is no
reliable way to take a Shadertoy URL and get a working ISF (`.fs`) shader for use
in VDMX / CoGe / ISF Editor. We want a small native macOS app that does this:
paste a Shadertoy URL → fetch the source → convert GLSL to ISF → see the imported
code, the converted output, warnings, compile errors, and a live preview.

## Goals

- Paste a Shadertoy URL, get a valid ISF `.fs` file out.
- Support **single-pass (Image) AND multi-pass (Buffer A–D)** shaders.
- Show imported Shadertoy code, converted ISF, conversion warnings, and (Phase 2)
  a live in-app preview with real compile errors.
- Save `.fs` and Copy to clipboard.
- Be a real double-clickable Mac app, not a terminal tool.

## Non-Goals (v1)

- Converting Sound shaders, cubemap passes, VR/360, or volume textures (warn, skip).
- Editing/round-tripping ISF back to Shadertoy.
- Reimplementing an ISF host in Metal (preview uses the canonical JS engine).
- Batch conversion / library management.

## Approach

**Native SwiftUI `.app` + pure-Swift conversion engine + WKWebView/ISF.js preview.**

Chosen over (B) a fully-native Metal ISF host for preview — rejected as the
biggest, riskiest path (Metal black-screen iteration loops) — and (C) an
all-web app in a wrapper — rejected because it discards the native-app feel and
gives no testing advantage.

The preview reuses VIDVOX's official `interactive-shader-format.js` (the same
lineage as the ISF Editor) inside a `WKWebView`, so we never reimplement an ISF
host and compile errors come straight from the canonical renderer.

## Architecture

### App shell

- Native SwiftUI macOS app.
- **App Sandbox** with `com.apple.security.network.client` (Shadertoy API).
- Shadertoy API key stored in **Keychain**, set via a Settings sheet.
- File save via **`NSSavePanel`** (sandbox-friendly; grants write scope).
- Build with `xcodebuild ... -derivedDataPath ./ddata` and stage from there.
  Before any "relaunch to see the change" claim, grep a known >15-char source
  string from the last edit in the staged binary; if absent, the build is stale.

### Components (each independently testable)

| Component | Responsibility | Depends on |
|---|---|---|
| `ShadertoyClient` | Fetch shader JSON from `shadertoy.com/api/v1/shaders/{id}?key=…`; parse URL/ID. Network behind a protocol so tests use fixtures. | `URLSession`, `ShadertoyModel` |
| `ShadertoyModel` | `Codable` structs: `Shader → renderpass[] → {code, type, name, inputs[], outputs[]}` + `info`. | — |
| `ISFConverter` | Pure function `ShadertoyShader → (ISFDocument, [ConversionWarning])`. Orchestrates the rewriters below. | rewriters |
| `UniformRewriter` | Token replacement of Shadertoy uniforms (table below). | — |
| `SamplerRewriter` | `texture/texture2D/texelFetch/textureLod` → `IMG_*` macros; resolve each `iChannelN` to its bound source. | channel-binding map |
| `PassBuilder` | Map Buffer A–D + Image to ISF `PASSES` (buffers first, Image last); set `PERSISTENT:true, FLOAT:true` on buffers; resolve cross-buffer channel refs. | — |
| `HeaderBuilder` | Emit ISF JSON header: `INPUTS` (image channels, `point2D` mouse, etc.), `PASSES`, `CATEGORIES`, `DESCRIPTION`, `CREDIT`. | — |
| `GLSLBodyBuilder` | Keep each pass's `mainImage` as a function; wrap in a `PASSINDEX` dispatch `main()`. | — |
| `ISFDocument` | Header + GLSL body; serialize to `.fs` text. | — |
| `ConversionWarning` | `{severity, message, sourceContext}`. | — |

`ISFConverter` is the seam everything tests through: deterministic, no I/O.

### Conversion mapping

| Shadertoy | ISF | Notes |
|---|---|---|
| `iResolution` (vec3) | `vec3(RENDERSIZE, 1.0)` | `.z` (pixel aspect) → 1.0 |
| `iTime` | `TIME` | same across passes in a frame |
| `iTimeDelta` | `max(TIMEDELTA, 1e-4)` | guard first-frame 0.0 (gotcha) |
| `iFrame` | `FRAMEINDEX` | first-frame init uses `< 2`, not `== 0` |
| `iMouse` (vec4) | `point2D` input → pixel coords | `.xy` current, `.zw` click; map `.xy = mouse * RENDERSIZE` |
| `iDate` (vec4) | `DATE` | |
| `iChannelResolution[i]` | `vec3(IMG_SIZE(chanN), 1.0)` | |
| `iChannelTime[i]` | `TIME` | no per-channel clock in ISF |
| `iSampleRate` | `44100.0` | constant |
| `texture(iChanN, uv)` | `IMG_NORM_PIXEL(chanN, uv)` | normalized coords |
| `texture2D(iChanN, uv)` | `IMG_NORM_PIXEL(chanN, uv)` | |
| `texelFetch(iChanN, p, 0)` | `IMG_PIXEL(chanN, vec2(p))` | pixel coords |
| `textureLod(iChanN, uv, l)` | `IMG_NORM_PIXEL(chanN, uv)` | LOD dropped → warn |
| `mainImage(out c, in fc)` | kept as a function, called from dispatch `main()` | `fragCoord` = `gl_FragCoord.xy` (both bottom-left pixel origin) |
| Buffer A–D | `PERSISTENT FLOAT` pass targets named `bufA…bufD` | render order = buffers, then Image |
| `iChannelN` → Buffer X | `IMG_NORM_PIXEL(bufX, …)` | cross-/self-buffer feedback reads last frame (gotcha #2) |

### Multi-pass model

Shadertoy renders Buffer A, B, C, D (in that order) then Image. ISF `PASSES`
mirrors that: one pass per used buffer (`TARGET:"bufX", PERSISTENT:true,
FLOAT:true`) followed by the final empty `{}` Image pass. Each pass's original
`mainImage` body is preserved as a function (`passBufA_mainImage`, …) and
dispatched by `PASSINDEX`. A channel bound to a buffer becomes an image read of
that buffer's name; a self-referencing buffer read is left-frame feedback, which
is exactly ISF's PERSISTENT semantics.

### Warnings (best-effort, never hard-fail)

The converter always produces output; problems are surfaced, never silently
dropped. Flagged cases:

- **Vector ternaries** (`cond ? vecA : vecB`) — legal GLSL but unreliable on
  Metal/macOS ISF backends. Flag with line context (auto-rewrite is unsafe via
  regex because it needs type info; v1 warns).
- **`iChannel` bound to keyboard / cubemap / volume / video / mic / music /
  audioFFT** — no clean ISF equivalent. Audio *may* map to an ISF `audio` input
  later; v1 warns and inserts a placeholder image input.
- **GLSL ES 3.00-only constructs** the host may reject (best-effort detection).
- **Dropped `textureLod` LOD argument.**
- **Non-API-visible shader** — see error handling.

### Data flow

```
URL ─▶ ShadertoyClient ─▶ ShadertoyShader ─▶ ISFConverter ─▶ (ISFDocument, [warning])
                                                                      │
                                          UI: imported code | ISF out | warnings
                                                                      │
                                            user edits ISF text  ◀────┘
                                                      │
                                    (Phase 2) WKWebView/ISF.js render
                                                      │
                                       compile errors ─▶ warnings/errors panel
```

### UI

- **Three panes:** imported Shadertoy code (read-only, one section per render
  pass) · converted ISF (editable text) · live preview (Phase 2).
- **Warnings/errors list** below the panes.
- **Toolbar:** URL field + Convert · Save `.fs` · Copy · Settings (API key).

### Preview (Phase 2)

- `WKWebView` loads a bundled local HTML harness running VIDVOX's official
  `interactive-shader-format.js` (**MIT — bundle + attribute in About/credits**).
- Swift posts the current (possibly user-edited) ISF text in via a JS bridge.
- The harness builds an ISF renderer, renders to a `<canvas>` with
  `requestAnimationFrame`, and posts GLSL compile errors back through
  `window.webkit.messageHandlers`.
- No Metal, no ISF host reimplementation.

## Error handling

| Condition | Behavior |
|---|---|
| Malformed / non-Shadertoy URL | Inline validation error, no network call |
| Missing API key | Prompt to open Settings and add the key |
| Shader ID not found / not public+API | **Specific** message: the shader's author must enable "public + API" visibility (the same wall the old import hit) |
| Network failure / timeout | Error with Retry |
| Unsupported features in source | Warnings (not failure); best-effort `.fs` still produced |
| GLSL compile error in preview (Phase 2) | Surfaced in the errors panel with the renderer's message/line |

## Testing

- **TDD throughout.** Pure-string unit tests per rewriter (`UniformRewriter`,
  `SamplerRewriter`, etc.): known input → known output.
- **Golden-file tests:** fixture Shadertoy JSON → expected `.fs`. Cover single-pass,
  multi-pass feedback, mouse input, multiple texture channels.
- **Integration:** `ISFConverter` against full fixture shaders; assert header
  parses as JSON, `PASSES` ordering, buffer naming.
- **Zero network in tests** — `ShadertoyClient` mocked via its protocol.
- **Preview smoke test (Phase 2):** JS harness loads a known-good ISF and reports
  success/error; basic Swift↔JS bridge round-trip test.

## Phases

- **Phase 1 — Converter + shell (usable on its own):** `ShadertoyClient`,
  `ShadertoyModel`, full `ISFConverter` (single + multi-pass), app shell, imported
  + output panes, warnings, Save/Copy, Settings/Keychain, complete test suite.
- **Phase 2 — Live preview + compile errors:** bundle `interactive-shader-format.js`,
  WKWebView harness, JS bridge, render loop, compile-error surfacing.

Each phase gets its own implementation plan and is verified before the next.

## Open implementation tasks (tracked into the plan)

- Confirm `interactive-shader-format.js` license text and attribution placement.
- Decide `point2D` mouse default/min/max range (pixels vs normalized).
- Xcode project scaffold, bundle ID, entitlements, signing for local run.
- Channel-binding map shape (how `SamplerRewriter` learns each `iChannelN`'s source
  from the Shadertoy `inputs[]` array per pass).
