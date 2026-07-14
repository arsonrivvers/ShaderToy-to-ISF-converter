# TrueISFEditor

Native macOS ISF editor and Shadertoy-to-ISF converter. It renders ISF 2.0 through
ISFMSLKit, the Metal engine used by VDMX6, so the preview path matches the VJ host this project is
targeting.

The app is built for authoring, importing, testing, and remixing `.fs` shaders:

- Shadertoy to ISF conversion, including Image, Common, Buffer A-D, audio channels, cubemaps as
  equirect inputs, and persistent float buffers.
- Metal and WebKit preview engines with compiler diagnostics surfaced in the editor. The Metal
  render loop runs off the main thread (CVDisplayLink), so dragging sliders never stutters the
  preview, with a live FPS / GPU-frame-time readout on the preview and pop-out output window.
- ISF library sidebar (with a bundled sample gallery), save/open flow, output pop-out window,
  render-size controls (16:9 / 1920x1080 default), and image-source routing for filter inputs —
  filters auto-load the webcam (falling back to a test pattern when camera access is unavailable).
- Auto-generated live controls for common ISF inputs (`float`, `bool`, `long`, `point2D`, `color`,
  `event`; image inputs are routed from the preview toolbar), each with a live value readout.
- Header authoring for Inputs and Passes, including persistent/float feedback buffers.
- ShaderAssist, which runs local Claude CLI sessions with ISF-specific prompts for diagnose,
  fix, and suggestion workflows (no API key — it uses your existing subscription).
- Remix Studio for parent selection, AI generation, compiled child previews, favorites, and
  lineage tracking.

Output targets VDMX, CoGe, ISF Editor, and other ISF hosts.

## Install

Download the latest DMG from [Releases](https://github.com/arsonrivvers/ShaderToy-to-ISF-converter/releases)
and drag TrueISFEditor to Applications. **The app isn't notarized** (it's shared friend-to-friend),
so macOS blocks the first launch: open it once, then System Settings → Privacy & Security →
"Open Anyway" — or run `xattr -cr /Applications/TrueISFEditor.app` in Terminal. The same
instructions ship inside the DMG. After that it opens normally.

First run opens a bundled sample shader with live controls; the `samples/` gallery also appears in
the library sidebar.

To cut a release build locally: `./scripts/release.sh` (produces the DMG; signing/notarization stay
env-gated for whoever wants them — see the script header).

## Build

Requirements:

- macOS 13+
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

Run the conversion kit tests:

```sh
cd ShadertoyISFKit
swift test
```

Generate and open the Xcode project:

```sh
cd App
xcodegen generate
open TrueISFEditor.xcodeproj
```

Build and install the canonical local app:

```sh
./scripts/run-latest.sh
```

That script regenerates the Xcode project, builds arm64 to `/tmp/trueisfeditor-ddata`, installs the
fresh app at `~/Applications/TrueISFEditor.app`, and launches it. Use this path when verifying a
fresh build so Spotlight/Finder do not open an older DerivedData copy.

Xcode 26 note: the app uses debuggable-dylib mode, so compiled code and strings live in
`TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib`, not the main stub binary.

## Importing Shadertoy

No account or API key is required for the reliable path.

Use **New from Shadertoy...** and choose one of these paths:

- **Paste GLSL:** reliable and local. Paste a single Image tab, or use marker lines for multipass:
  `// [Common]`, `// [Buffer A]`, `// [Buffer B]`, `// [Buffer C]`, `// [Buffer D]`, `// [Image]`.
  Pasted multipass imports infer `iChannelN -> Buffer N` routing and warn you to verify it against
  the original Shadertoy channel setup.
- **Fetch by URL or 6-character ID:** best-effort. The app can fetch through the official API when a
  Silver/Gold API key is saved in Settings, otherwise it tries a built-in browser fetch. Shadertoy's
  public site is behind Cloudflare bot protection, so browser fetch can fail intermittently.

After import, review the conversion report, compiler diagnostics, generated ISF header, and live
preview before saving the `.fs`.

## Conversion Coverage

The converter is measured by compiling through the real ISFMSLKit path, not just by whether text
rewriting succeeds. The current curated discovery corpus is **74/78 shaders compiling** through the
Metal transpiler, with the remaining failures documented in [docs/SHADERTOY_TO_ISF.md](docs/SHADERTOY_TO_ISF.md).

Currently handled classes include:

- Shadertoy uniforms mapped to ISF builtins (`iResolution`, `iTime`, `iFrame`, `iDate`, `iMouse`,
  `iChannelResolution[N]`, `iChannelTime[N]`, and others).
- Image, buffer, cubemap, video/webcam/keyboard fallback, and audio channel bindings.
- Common-tab channel sampling via `PASSINDEX` dispatchers.
- Multi-pass function/global namespacing and duplicate helper deduplication.
- Header-macro `mainImage` expansion.
- Per-pass macro scoping to recover Shadertoy's per-buffer preprocessor isolation.
- Metal-facing compatibility fixes such as reserved identifier renaming, vector-ternary warnings,
  output initialization, line-continuation splicing, and GLSL compatibility polyfills.

Run the corpus harness:

```sh
./scripts/corpus-run.sh
./scripts/corpus-run.sh -o /tmp/raw corpus/discovery-ids.txt
```

The harness fetches, converts, and transpiles each shader through the app's real ISFMSLKit path. Fetch
failures can be network/Cloudflare flakiness, so re-run failures before treating a headline count as a
conversion regression.

## Repository Layout

- `ShadertoyISFKit/` - pure-Swift conversion engine, Shadertoy models/client/parser, rewriters,
  builders, diagnostics, test patterns, and unit tests.
- `App/` - SwiftUI macOS app, Metal/WebKit preview controllers, editor UI, import sheet, header
  authoring, ShaderAssist, Remix Studio, crash/import logs, and app tests.
- `corpus/` - curated Shadertoy ID list for conversion conformance.
- `docs/SHADERTOY_TO_ISF.md` - living conversion pipeline, mapping reference, gap classes, and
  conformance history.
- `docs/superpowers/` - implementation specs, plans, and project notes from the build history.
- `scripts/` - build/install and corpus verification helpers.
- `vendor/` - bundled browser assets and prebuilt ISFMSLKit/VVMetalKit/PIN frameworks used by the app.

## Notes

- The generated `App/TrueISFEditor.xcodeproj/` is ignored. Regenerate it with XcodeGen after source
  changes.
- `ShadertoyISFKit/.build/`, DerivedData, vendored `node_modules`, and app build products are ignored.
- ShaderAssist and Remix Studio use the user's local Claude CLI authentication; no API key is
  stored by this repo for those workflows. (Debug builds additionally expose a Codex provider for
  development.)
- Sample shaders in `samples/` are original work by ArsonRivvers, shipped under the repo license.
  Shadertoy shaders you convert yourself remain under their authors' terms (typically CC BY-NC-SA) —
  the app never bundles third-party Shadertoy content.

## Privacy & Security

Webcam frames are processed locally and never transmitted. ShaderAssist sends shader text only to
your local `claude` CLI (tools disabled — pure text transform). See [SECURITY.md](SECURITY.md) for
details and vulnerability reporting.

## License

MIT — see [LICENSE](LICENSE). Bundled third-party components keep their own licenses; see
[THIRD_PARTY_LICENSES/](THIRD_PARTY_LICENSES/) and the in-app Acknowledgements (Settings).
