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

1. Get a free API key at shadertoy.com → Profile → Apps. Paste it into **Settings** (gear icon).
2. Paste a Shadertoy URL (or bare 6-char ID), click **Convert**.
3. Review the imported code (left), converted ISF (right), and any warnings.
4. **Save .fs** or **Copy**, then load it in VDMX / ISF Editor.

## Scope (Phase 1)

- Single- and multi-pass (Buffer A–D) Image conversion.
- Maps Shadertoy uniforms/samplers to ISF; multi-pass buffers become `PERSISTENT FLOAT` passes.
- Best-effort: unsupported channels (keyboard/cubemap/audio/video/cubemap), vector ternaries, and
  dropped `textureLod` LODs are flagged as **warnings**, never silent failures.
- Only shaders whose author enabled **"public + API"** visibility can be fetched (Shadertoy API limit).

**Phase 2 (planned):** live in-app preview via the official `interactive-shader-format.js` in a
WKWebView, with real compile errors surfaced to the warnings panel.

## Architecture

- `ShadertoyISFKit/` — pure-Swift conversion engine (URL parsing, API client, rewriters, builders,
  `ISFConverter`). No UI, no app dependencies; tested via `swift test`.
- `App/` — SwiftUI app shell (xcodegen project) that imports the engine. Keychain-stored API key,
  three-pane UI, Save/Copy.

See `docs/superpowers/specs/` and `docs/superpowers/plans/` for the design and implementation plan.
