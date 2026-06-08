# Shadertoy → ISF Converter

Native macOS app that converts Shadertoy shaders to ISF (`.fs`) for VDMX / CoGe / ISF Editor.
Replaces the defunct "Import from Shadertoy" feature of the ISF Editor.

## Build

Requirements: Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

**Engine (headless, fully unit-tested):**
```
cd ShadertoyISFKit && swift test
```

**App:**
```
cd App && xcodegen generate && open ShadertoyISF.xcodeproj
```
or build from the command line:
```
cd App && xcodegen generate
xcodebuild -project ShadertoyISF.xcodeproj -scheme ShadertoyISF -derivedDataPath ./ddata build
open ddata/Build/Products/Debug/ShadertoyISF.app
```

> Build note (Xcode 26): the app uses debuggable-dylib mode, so compiled code/strings live in
> `ShadertoyISF.app/Contents/MacOS/ShadertoyISF.debug.dylib`, not the main stub binary. Grep the
> `.debug.dylib` when verifying a build is fresh.

## Use

**No account or API key required.** Two ways to get a shader in:

- **Paste the code (reliable):** open the shader on Shadertoy, copy the **Image** tab's GLSL,
  expand *"Or paste shader code"* in the app, paste, and click **Convert pasted code**.
- **Paste a URL (best-effort):** paste a Shadertoy URL (or 6-char ID) and click **Convert**. The
  app tries to fetch it through a built-in browser window. Shadertoy is behind Cloudflare bot
  protection, so this may not always clear — if it doesn't, fall back to pasting the code.

Then review the imported code (left), converted ISF (right), and warnings; **Save .fs** / **Copy**,
and load it in VDMX / ISF Editor.

> **Optional (Advanced):** Shadertoy Silver/Gold members can add an API key in **Settings** to use
> the official API instead of the browser fetch.

## Why fetching is limited

Shadertoy's official API requires a paid (Silver/Gold) membership, and the public site is behind
Cloudflare's bot challenge — which a `WKWebView` does not reliably clear. The **paste-code path**
sidesteps both: it's local, needs no account, and can't be rate-limited or flagged. See
`docs/superpowers/specs/2026-06-08-phase1.5-webview-fetch-design.md` for the full story.

## Scope

- **Conversion engine (complete):** single- and multi-pass (Buffer A–D); maps Shadertoy
  uniforms/samplers to ISF; multi-pass buffers become `PERSISTENT FLOAT` passes. Unsupported
  channels (keyboard/cubemap/audio/video), vector ternaries, and dropped `textureLod` LODs are
  flagged as **warnings**, never silent failures.
- **Manual paste fallback (v1.5):** currently **single-pass (Image)**. Multi-pass via manual paste
  is a future addition; multi-pass works via the URL fetch when it isn't Cloudflare-blocked.

**Phase 2 (planned):** live in-app preview via the official `interactive-shader-format.js` in a
WKWebView, with real compile errors surfaced to the warnings panel.

## Architecture

- `ShadertoyISFKit/` — pure-Swift conversion engine (URL parsing, API client + internal-endpoint
  parser, `ShaderFactory`, rewriters, builders, `ISFConverter`). No UI; tested via `swift test`.
- `App/` — SwiftUI app shell (xcodegen) importing the engine: URL + paste inputs, `WebKitShaderFetcher`
  (browser fetch), Keychain API key (optional), three-pane UI, Save/Copy.

See `docs/superpowers/specs/` and `docs/superpowers/plans/` for the design and implementation plan.
