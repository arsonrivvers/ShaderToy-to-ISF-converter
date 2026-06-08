# Phase 2 — Live ISF Preview + Compile Errors — Design

**Date:** 2026-06-08
**Status:** Pending review
**Builds on:** Phase 1 + 1.5 (merged), GLSL compat polyfills + lint warnings (merged)

## Problem

After conversion, the only way to know whether the ISF actually compiles/renders is to load
the `.fs` into ISF Editor or VDMX and read its error console (e.g. the `tanh` error). We want the
app to **render the converted ISF live** and **surface compile errors in-app**, closing the loop.

## Approach (validated by research)

Embed VIDVOX's official-lineage **`interactive-shader-format`** JS renderer (msfeldstein, **MIT**) in a
`WKWebView` that loads a **bundled local** HTML harness. This is local content — no Cloudflare, no
network at runtime. The renderer:

- API: `new ISFRenderer(gl)` → `renderer.loadSource(fragmentISF)` → `renderer.draw(canvas)` in a
  `requestAnimationFrame` loop. Inputs via `renderer.setValue(name, value)`.
- **Errors:** after `loadSource`, read `renderer.valid` (bool), `renderer.error`, `renderer.errorLine`.
  `loadSource` may also throw — the harness wraps it in try/catch and reports either source.
- **WebGL1 / GLSL ES 1.00** — same vintage as ISF Editor's OpenGL backend, so it reproduces the same
  class of errors (high fidelity) and our `#if __VERSION__ < 130` polyfills compile there too.
- **Multipass + persistent buffers** are supported by the renderer — our Buffer A–D output previews.

Rejected alternatives: a native Metal ISF host (huge, risky — same reasoning as Phase 1); compiling
GLSL ourselves (can't — ISF macros need ISF's parser, which is exactly what this library provides).

## Architecture

### Vendoring the renderer (build-time, committed)
- `vendor/isf/` holds a small browserify entry (`isf-entry.js`) that `require`s the npm package and
  exposes `window.ISFRenderer` / `window.ISFParser`, plus a `build.sh` that runs
  `npm install interactive-shader-format && npx browserify isf-entry.js -o ../../App/ShadertoyISF/Resources/isf.bundle.js`.
- The **bundled `isf.bundle.js` is committed** (vendored) so the app builds with no network/node.
  The upstream **MIT LICENSE** is committed alongside it and shown in the app's About/credits.

### App pieces
| Unit | Role |
|---|---|
| `App/ShadertoyISF/Resources/isf.bundle.js` | vendored ISF.js (committed) |
| `App/ShadertoyISF/Resources/isf-preview.html` | local harness: a `<canvas>`, includes the bundle, defines `loadISF(src)` + a rAF draw loop, posts compile status back via `window.webkit.messageHandlers.isf` |
| `PreviewWebView` (NSViewRepresentable) | wraps a `WKWebView` loaded from the bundled `isf-preview.html`; exposes `render(_ isf:)` (calls `loadISF` via `evaluateJavaScript`) and a closure for compile results; conforms to `WKScriptMessageHandler` |
| `PreviewState` (ObservableObject or fields on AppModel) | holds `compileOK: Bool`, `compileError: String?`, `compileErrorLine: Int?` |
| `ContentView` | adds the preview pane (third pane, right of ISF output) and shows compile status in the warnings/errors area; re-renders on ISF-output edits (debounced ~400ms) |

### Data flow
```
converted/edited ISF text ──(debounced)──▶ PreviewWebView.render(isf)
   ──evaluateJavaScript loadISF(src)──▶ harness: ISFRenderer.loadSource + draw loop
   ──messageHandlers.isf {valid,error,errorLine}──▶ Swift ──▶ PreviewState ──▶ warnings/errors UI
```

### Harness contract (`isf-preview.html`)
```js
let renderer, animating = false;
function loadISF(src){
  try {
    if (!renderer) { const gl = canvas.getContext('webgl'); renderer = new ISFRenderer(gl); }
    renderer.loadSource(src);
    const ok = renderer.valid !== false && !renderer.error;
    post({ valid: ok, error: ok ? null : String(renderer.error||''), errorLine: renderer.errorLine ?? null });
    if (ok) startLoop();
  } catch (e) {
    post({ valid:false, error:String(e && e.message || e), errorLine: (e && e.line) ?? null });
  }
}
function post(o){ window.webkit?.messageHandlers?.isf?.postMessage(o); }
```
(`startLoop` runs `renderer.draw(canvas)` under `requestAnimationFrame`; `TIME` advances from a JS clock; size set from the canvas/devicePixelRatio.)

## Scope (Phase 2 v1)

- Render the (single- or multi-pass) converted ISF live; advance `TIME`.
- Surface compile **valid/error/errorLine** into the existing warnings/errors panel, tagged "Preview".
- Re-render on edits to the ISF output (debounced).
- **Defer:** live UI controls for ISF INPUTS (sliders/point2D) — render with defaults (mouse → center);
  image inputs render as empty/black. Audio/webcam not wired. About-box license screen can be a simple
  alert/sheet.

## Error handling

| Condition | Behavior |
|---|---|
| GLSL compile error | `valid:false` + message/line → shown in errors panel ("Preview: ERROR 0:NN …") |
| Harness/JS exception | caught, posted as an error string |
| Bundle missing at runtime | preview pane shows "preview engine not bundled" (build-time guard: build.sh must have run) |
| WebGL unavailable | harness posts a clear "WebGL not available" error |

## Testing

- **Unit (Kit):** none new (engine unchanged).
- **Harness smoke (manual + scripted):** load a known-good ISF (the Phase-1 single-pass output) →
  expect `valid:true`; load a deliberately broken ISF (`tanh` with the polyfill removed) → expect
  `valid:false` with a line number. Drive via the existing `SHADERTOY_DEBUG_*` style hook or a tiny
  harness test page opened headlessly.
- **Manual:** convert the Firewall shader → preview renders; remove the polyfill by hand → error
  appears in-app with a line number.

## Non-Goals

- Live INPUT controls, image/video/audio inputs, export of preview frames. (Future.)
- Replacing ISF Editor/VDMX as the final test target — this is a fast in-app sanity loop.
