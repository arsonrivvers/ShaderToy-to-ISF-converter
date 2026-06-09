# P1.5 — Native ISFMSLKit Preview (Design Spec)

**Date:** 2026-06-09
**Status:** Approved (brainstorm complete; ready for implementation plan)
**Repo:** `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter`
**Predecessor:** `2026-06-09-trueisfeditor-p1-editor-spine-design.md` (P1 editor spine, merged at `301b91f`)

---

## 1. Problem & Goal

TrueISFEditor previews ISF `.fs` shaders via a WebKit + ISF.js harness that runs **WebGL1 / GLSL ES 1.00**.
That renderer rejects valid **GLSL ES 3.00** patterns (dynamic loop bounds, dynamic array indexing, etc.)
that real ISF hosts accept — so a meaningful fraction of the user's `AR_*.fs` library fails to preview
("not all files load"; errors like *"Loop index cannot be compared with non-constant expression"*).

The user performs these shaders in **VDMX6 Plus**, which runs **`mrRay/ISFMSLKit`** (Metal) — VIDVOX
open-sourced it 2025-03-21 as "the same code running under the hood in VDMX6." It transpiles
GLSL→SPIR-V→MSL (glslang + SPIRV-Cross), which is exactly why it accepts what the WebGL1 harness rejects.

**Goal:** make a native **ISFMSLKit + MTKView** view the **primary** preview engine, rendering identically
to VDMX6 and accepting ES3 shaders. The existing **WebKit engine is retained as a manual fallback**,
selected via a **Metal | WebKit** toggle.

### Non-goals (explicitly out of scope for P1.5)
- **Syphon output** — no publishing the preview as a Syphon source. (Possible later feature.)
- **Off-main `CVDisplayLink` render loop** — a later optimization, only if interaction stutters (§7).
- **Per-shader automatic fallback** — the toggle is manual; we do not silently route failing shaders to WebKit.
- The OpenGL `libVVISF.dylib` (ISF Editor's old engine) is **not** used. Neither is a WebGL2 stopgap.

---

## 2. Acceptance Criteria (Definition of Done)

1. **Corpus pass-rate.** A headless render-test loads all `AR_*.fs` shaders in `/Library/Graphics/ISF`
   (~1,057 files) through the native `MetalPreviewController` and records compile/render success per file.
   The native engine must:
   - compile/render **≥ the WebKit baseline set** (no regressions vs. what WebKit already renders), **and**
   - **move the WebKit-rejected ES3 shaders to passing** (the dynamic-loop / dynamic-index files that
     currently error in WebGL1).
   - The test emits a report: per-file `{pass, error}` for both engines + a diff (gained / lost / shared).
2. **Visual fidelity spot-check.** A handful of representative shaders (including a persistent-buffer sim like
   `AR_ReactionDiffusion_*` or `AR_GameOfLife_*`) render on-device and visually match VDMX6 for the same inputs.
3. **Toggle works.** Switching Metal ↔ WebKit in the running app reloads the current source and shows the
   selected engine's output and compile state. No crash, no stale frame.
4. **No editor-loop regressions.** Live recompile, inline error gutter, controls panel, Save/New, pop-out
   output, and output-dimensions control all behave as in P1 with the Metal engine active.
5. **Build hygiene.** App builds clean; embedded frameworks + nested dylibs sign; the staged binary is
   verified fresh (`.debug.dylib` grep) before any "relaunch" claim.

**License gate (blocking before distribution, not before building):** confirm glslang's GPL-3 component is
build-tool-only and **not** present in the app's linked runtime path. Documented finding required before any
commercial distribution; does **not** block development/testing.

---

## 3. Architecture

### 3.1 The engine seam

Today the concrete `ISFPreviewController` (`@MainActor ObservableObject`) is the engine. It exposes:

- Published: `compileValid: Bool`, `compileError: String?`, `compileErrorLine: Int?`, `inputs: [ISFPreviewInput]`
- Methods: `load(isf:)`, `setInput(_ name:_ jsonValue:)`, `setRenderSize(width:height:)`
- A `webView: WKWebView` the SwiftUI `ISFPreviewView` binds to.

Consumers: `EditorViewModel.preview`, `EditorScreen`, `PreviewControlsView` (`@ObservedObject`),
`OutputWindow` (its own controller), and a dev smoke-test in `TrueISFEditorApp`.

We introduce a protocol and a coordinator:

```
protocol PreviewEngine: AnyObject {
    // published-equivalent state (see note on ObservableObject below)
    var compileValid: Bool { get }
    var compileError: String? { get }
    var compileErrorLine: Int? { get }
    var inputs: [ISFPreviewInput] { get }
    var nsView: NSView { get }            // WKWebView or MTKView

    func load(isf: String)
    func setInput(_ name: String, _ jsonValue: String)
    func setRenderSize(width: Int?, height: Int?)
}

WebKitPreviewController : PreviewEngine   // today's ISFPreviewController, renamed; behavior unchanged
MetalPreviewController  : PreviewEngine   // NEW — wraps ISFMSLScene

final class PreviewCoordinator: ObservableObject {   // the type views bind to
    enum Engine { case metal, webkit }
    @Published var active: Engine = .metal
    @Published var compileValid / compileError / compileErrorLine / inputs   // mirrored from active engine
    var nsView: NSView { activeEngine.nsView }
    func load(isf:) / setInput(_:_:) / setRenderSize(width:height:)   // forward to active engine
}
```

**Why a concrete coordinator instead of `any PreviewEngine` everywhere:** SwiftUI's `@ObservedObject` and
`@Published` do not compose cleanly with an existential `any ObservableObject`. The coordinator is a single
concrete `ObservableObject` that owns both engines, subscribes to the active engine's state (via Combine on
the concrete controllers, which keep their own `@Published` fields), re-publishes a unified surface, and vends
the active engine's `NSView`. The two engines stay fully isolated and independently testable.

**Toggle behavior:** setting `active` (a) tears down the subscription to the old engine and subscribes to the
new one, (b) calls `load(isf:)` on the new engine with the current source, (c) re-pushes the current
`renderSize`. The view layer re-reads `nsView` and swaps the hosted NSView.

### 3.2 View layer

- `ISFPreviewView` (NSViewRepresentable) generalizes from "wraps a `WKWebView`" to "wraps the
  coordinator's current `nsView`," swapping the hosted subview when `active` changes.
- `EditorScreen` and `OutputWindow` bind to `PreviewCoordinator` instead of `ISFPreviewController`.
  Their reads of `compileValid` / `compileError` / `compileErrorLine` / `inputs` are unchanged in shape.
- `PreviewControlsView` takes `@ObservedObject var coordinator: PreviewCoordinator` and reads
  `coordinator.inputs` / calls `coordinator.setInput(...)`. Its per-type control code is unchanged.
- A **renderer toggle** (segmented `Metal | WebKit`) is added to the preview toolbar in `EditorScreen`
  (and mirrored in `OutputWindow` if the pop-out should be switchable independently — see Open Questions).

---

## 4. Vendoring & Build (Approach 1 — prebuilt, committed)

Driven by the `isfmslkit-macos-app` skill draft. The frameworks are built **once** by a checked-in script and
the **signed binaries are committed** to `vendor/prebuilt/`; the app build just links + embeds them.

### 4.1 `vendor/build-isfmslkit.sh` (new, checked in)
1. `git clone --depth 1 https://github.com/mrRay/ISFMSLKit.git` then
   `git -C ISFMSLKit submodule update --init --recursive` (pulls VVMetalKit, PINCache, ISFGLSLGenerator;
   transpiler dylibs ship prebuilt in `extern/`).
2. Xcode-26 environment (each blocks the build if missing):
   - `xcodebuild -runFirstLaunch`
   - `xcodebuild -downloadComponent MetalToolchain` (Xcode 26 ships `metal` separately, ~700MB)
   - `brew install cmake` (ISFGLSLGenerator builds via cmake)
   - Patch `ISFGLSLGenerator_build_script.sh`: replace the
     `codesign … "Developer ID Application: Vidvox, LLC"` line with ad-hoc `codesign -f -s -` `|| true`.
3. Build frameworks:
   `xcodebuild -workspace ISFMSLKit.xcworkspace -scheme ISFMSLKit -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
4. Collect **ISFMSLKit / VVMetalKit / PINCache / PINOperation** `.framework`s into `vendor/prebuilt/` via `ditto`.
   **(Syphon omitted.)**
5. **Pre-sign nested dylibs** inside
   `vendor/prebuilt/ISFMSLKit.framework/Versions/A/Frameworks/*.dylib`
   (`libISFGLSLGenerator`, `libGLSLangValidatorLib`, `libSPIRVCrossLib`) with `codesign -f -s -` — otherwise the
   app's embed-codesign fails with *"code object is not signed at all in subcomponent."*
6. Write `vendor/prebuilt/README.md` documenting source SHAs, build date, and the exact command set.

### 4.2 `App/project.yml` changes
- Add the 4 frameworks to the `TrueISFEditor` target as dependencies with `embed: true, codeSign: true`.
- `settings.base`:
  - `FRAMEWORK_SEARCH_PATHS = $(SRCROOT)/../vendor/prebuilt`
  - `LD_RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks`
- Keep `CODE_SIGN_IDENTITY = "-"`, unsandboxed (already set in P1). Hardened runtime currently `YES`; verify the
  ad-hoc-signed embedded dylibs load under it — if they trip the runtime, set `ENABLE_HARDENED_RUNTIME = NO`
  for local dev (consistent with this being a local authoring tool).
- Regenerate the Xcode project with `xcodegen`.

### 4.3 Obj-C++ ↔ Swift bridge
- ISFMSLKit is Objective-C(++). Expose its headers to Swift via a bridging header (or a small `.modulemap`)
  in the app target. `MetalPreviewController.swift` calls the framework directly; no separate wrapper target.
- `.gitignore`: ensure `vendor/prebuilt/*.framework` is **committed** (not ignored), while the transient
  `ISFMSLKit` clone/build dir under `vendor/` is ignored.

---

## 5. `MetalPreviewController` Internals

> **API-name caveat:** the exact ISFMSLKit selector names differ between sources (skill draft says
> `ISFMSLScene(device:)` / `.load(url)` / `.createAndRender(toTextureSized:in:)` / `.inputs`; the renderer
> memo references `createAndRenderToTextureSized:inCommandBuffer:` / `setValue:forInputNamed:`). The
> implementation **must read the vendored `ISFMSLScene.h` and `ISFMSLSceneVal.h` headers** and bind to the
> actual symbols. This spec describes behavior, not literal selectors.

### 5.1 One-time setup
- `RenderProperties.global()` → `.device`, `.renderQueue`.
- `VVMTLPool.global = VVMTLPool(device:)`.
- `ISFMSLCache.primary = ISFMSLCache(directoryURL:)` pointing at an Application Support subdir — the PINCache
  that persists transpiled MSL across runs so first-sight latency is paid once per shader, not per session.

### 5.2 Loading source
- ISFMSLKit's scene loads from a **URL**. The editor holds an in-memory buffer, so each recompile writes the
  current source to a stable temp `.fs` path and loads that. **If** a string-load entry point exists in
  `ISFMSLScene.h`, prefer it (avoids the temp-file round-trip).
- After load: read `ISFMSLScene.compilerError`. Map to `compileValid` / `compileError` / `compileErrorLine`.
- Parse `ISFMSLScene.inputs` (`ISFMSLSceneAttrib`: `.name/.label/.type/.currentVal/.minVal/.maxVal/.labelArray/.valArray`)
  into `[ISFPreviewInput]` — the **same struct the controls panel already consumes**, so `PreviewControlsView`
  needs no per-type changes.

### 5.3 Inputs
- `ISFValType` rawValue: `1 Event, 2 Bool, 3 Long, 4 Float, 5 Point2D, 6 Color`.
- `setInput(name, jsonValue)` decodes the JSON the controls panel sends and constructs the matching
  `ISFMSLSceneVal`: `.create(withFloat:)`, `.create(with:)` (Bool / NSColor), `.create(withLong:)`,
  `.createWithEvent()`, `.create(withPoint2D:)`; set on the scene by input name.
- **iMouse:** preserve the P0 interactivity fix — map mouse position to a "pressed" position and center the
  default — so mouse-gated shaders stay interactive (parity with the WebKit path).

### 5.4 Render
- Driver: **main-thread self-driving `MTKView`** (`isPaused = false`, `MTKViewDelegate`). Per frame:
  `createAndRender(toTextureSized:in:)` → `MTLTexture`, blit/draw into the view's `currentDrawable`.
- `setRenderSize(width:height:)` sets the **target texture size** (Fit / W×H / ÷2 / ×2) independent of the
  MTKView's bounds — Fit uses the view's backing size; explicit sizes render to that texture and scale to fit.
  Pop-out output honors the same setting (parity with P1).
- **Resize safety** (relevant now even on main; mandatory if we later go off-main): size changes set a
  `pendingSize`; applied at the top of the next frame, never mid-read.

---

## 6. Error Handling & Latency

- **Compile errors → gutter.** Parse `compilerError` into message + line. If the error string lacks a line
  number, the gutter shows the message without a line marker (graceful degradation). Keep the existing
  `EditorViewModel` pipe from `compileError`/`compileErrorLine` to the CodeMirror gutter.
- **First-run transpile latency.** GLSL→SPIR-V→MSL is slow on first sight of a shader, then PINCached. The
  live-recompile loop already debounces. We run `load` **off the main thread** (the transpile must not block UI
  or the render loop), surface a transient "compiling…" state, and only swap the live scene when the new one
  compiles. The render thread never transpiles.
- **Stale frame on failure.** Preserve the P0 behavior: a failed compile **clears** the preview (no frozen last
  frame). On the Metal path this means not presenting a drawable for the dead scene / clearing to background.
- **Engine init failure.** If the Metal stack can't initialize (framework load failure, no Metal device), the
  coordinator surfaces a clear error in the preview area. (Manual toggle to WebKit remains available; we do
  **not** auto-switch — per scope.)

---

## 7. Render-Loop Phasing

1. **P1.5 ships on the main-thread self-driving MTKView.** Simplest correct path; functional.
2. **If** dragging controls visibly stutters (the classic SwiftUI+MTKView main-thread-starvation symptom),
   apply the `swiftui-mtkview-offmain-render` draft: `isPaused = true` + `CVDisplayLink` calling `view.draw()`
   (never `renderFrame` directly — that renders to an unpresented drawable = black screen), with the lifetime
   drain (`DispatchSemaphore`, `Unmanaged.passRetained`), no `@Published` writes on the render thread, and the
   `pendingSize` hand-off. This is **out of scope for P1.5** and tracked as a fast-follow only if needed.

One change at a time on the render path; build → on-device test → keep/revert. Never stack changes on a black
screen.

---

## 8. Testing

- **`MetalPreviewControllerTests`** (mirrors the existing WebKit smoke test): load a known-good ISF →
  `compileValid == true`, inputs parsed; load a known-bad ISF (e.g. ES3 construct or a deliberate error) →
  `compileValid == false`, `compileError` set, `compileErrorLine` set when available.
- **`PreviewCoordinatorTests`:** toggling `active` reloads the current source on the newly active engine and
  republishes its compile state; `nsView` returns the active engine's view.
- **Corpus render-test harness** (acceptance, §2): a headless test/CLI that walks `/Library/Graphics/ISF`'s
  `AR_*.fs`, loads each through `MetalPreviewController`, and writes a report
  (`pass/fail/error` per file) plus a **diff vs. the WebKit baseline**. Gating assertion: zero regressions +
  the known WebKit-rejected ES3 set flips to passing.
- **Manual on-device spot-check:** a few shaders incl. a persistent-buffer sim, visually compared to VDMX6.
- **Build verification:** `xcodebuild` BUILD SUCCEEDED; embedded frameworks + nested dylibs signed; staged
  `.debug.dylib` grep confirms the binary is fresh before any "relaunch."

No lint/format tooling exists in this Swift project; build-clean + tests are the gate. Mechanic review is a
**manual inline code review by the CoS** (native Swift/Metal — not a subagent), per project rule.

---

## 9. Files Touched (anticipated)

**New**
- `vendor/build-isfmslkit.sh`, `vendor/prebuilt/README.md`, `vendor/prebuilt/{ISFMSLKit,VVMetalKit,PINCache,PINOperation}.framework`
- `App/TrueISFEditor/MetalPreviewController.swift`
- `App/TrueISFEditor/PreviewCoordinator.swift`
- `App/TrueISFEditor/PreviewEngine.swift` (protocol)
- `App/TrueISFEditor/MetalPreviewView` (or generalize `ISFPreviewView`)
- Bridging header / modulemap for ISFMSLKit
- `App/TrueISFEditorTests/MetalPreviewControllerTests.swift`, `PreviewCoordinatorTests.swift`, corpus harness

**Modified**
- `App/project.yml` (frameworks, search paths, rpath, bridging header)
- `App/TrueISFEditor/ISFPreviewController.swift` → renamed `WebKitPreviewController`, conform to `PreviewEngine`
- `App/TrueISFEditor/ISFPreviewView.swift` (host coordinator's `nsView`)
- `App/TrueISFEditor/EditorViewModel.swift`, `Views/EditorScreen.swift`, `Views/PreviewControlsView.swift`,
  `OutputWindow.swift`, `TrueISFEditorApp.swift` (bind to `PreviewCoordinator`; add renderer toggle)

---

## 10. Open Questions (carry into the plan)

1. **Pop-out independence:** should the detached `OutputWindow` have its own Metal|WebKit toggle, or always
   mirror the main editor's engine? (Default assumption: mirror the main editor.)
2. **Hardened runtime:** keep `YES` if the ad-hoc-signed embedded dylibs load cleanly; otherwise `NO` for local
   dev. Decide during the framework-embed step based on what actually loads.
3. **String-load vs temp-file load:** resolved by reading `ISFMSLScene.h` during implementation.

---

## 11. Risk Register

| Risk | Mitigation |
|---|---|
| ISFMSLKit selector names differ from drafts | Bind to actual vendored headers; spec is behavior-only (§5 caveat) |
| Per-keystroke transpile latency makes editor sluggish | Off-main load + debounce + PINCache; off-main render path as escape valve (§7) |
| Embed-codesign fails on nested dylibs | Pre-sign nested dylibs ad-hoc (§4.1.5) — known fix from skill draft |
| Xcode-26 build env (Metal toolchain / cmake) | Scripted one-time in `build-isfmslkit.sh`; binaries committed so app builds don't repeat it |
| Stale staged binary → false "relaunch" claim | `.debug.dylib` grep verification before any relaunch (project rule) |
| glslang GPL-3 in linked path | License gate before distribution; verify build-tool-only (§2) |
| Black screen on render-path changes | One change at a time, build→test→keep/revert; never stack on black (§7) |
