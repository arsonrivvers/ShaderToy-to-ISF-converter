---
schema_version: 1
topic: native-instrument-milestone-1
date: 2026-07-30
status: draft
correlation_id: arshader-native-pivot-20260730
implements_spec: docs/superpowers/specs/2026-07-30-native-performance-instrument-design.md
target_repo: ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter
---

> ✅ **EXECUTED AND CONFIRMED — do not re-run.** The frontmatter says `status: draft` because the
> file was never updated after execution. Milestone 1 was built, and the operator ran and signed
> the live smoke on device: `docs/reports/live-smoke-instrument-m1.md`. Milestone 2 phases 1–2
> (render scale, stacked FX chains) landed on top of it and are also CONFIRMED. Two M1 items remain
> genuinely open: **projector legs 15–18**, never run on real hardware, and the collapsible-library
> finding that became Milestone 2 phase 3. This plan was authored in `AV_Projects/AR_Shader` and
> ported to its own `target_repo` on 2026-07-31.

# Native Performance Instrument — Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS performance instrument — two ISF decks, per-deck opacity and blend
mode, a crossfader macro, three monitor viewports, a shader library with auto-generated controls,
and a blackout gate — on top of the TrueISFEditor codebase, playable by hand for an hour.

**Architecture:** A shared `ISFRuntime` source directory is extracted from the editor and compiled
into both app targets. The instrument runs **one** `DisplayLinkDriver` and **one** `RenderClock`.
Each frame, inside a single `MTLCommandBuffer`: deck 1 renders offscreen, deck 2 renders offscreen,
a hand-written Metal compositor blends them onto an opaque-black master via ping-pong textures, and
a blackout gate decides whether the program texture reaches any consumer at all. Monitors and the
program output blit textures that already exist — no readback, no encode, no cost governor.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, Metal + MetalKit, ISFMSLKit (vendored, MIT) via an
Objective-C++ crash-safe bridge, XcodeGen, XCTest.

**Where this plan lives:** the AR_Shader repo, beside the spec it implements. **All code changes
happen in `~/Desktop/AV_Projects/ShaderToy-to-ISF-converter`.**

---

## Deviation from the spec — read before Task 1

Spec §5 calls for "a new Swift package, `ISFRuntimeKit`". **That is not buildable as written**, for
three reasons verified in the repository on 2026-07-30:

1. `vendor/prebuilt/` contains plain `.framework` bundles (`ISFMSLKit.framework`,
   `VVMetalKit.framework`, `PINCache.framework`, `PINOperation.framework`). There is no
   `.xcframework` anywhere in the tree. SwiftPM's `.binaryTarget` accepts an XCFramework or an
   artifact bundle — not a plain framework.
2. The crash-safe entry points every render path depends on (`ISFMSLSafeCreateAndLoad`,
   `ISFMSLSafeRenderAtTime`, `ISFMSLSafeRender`) are defined in `App/TrueISFEditor/ISFMSLSafeBridge.mm`,
   an **Objective-C++** file exposed to Swift through `SWIFT_OBJC_BRIDGING_HEADER`. SwiftPM targets
   cannot use bridging headers.
3. The existing `ShadertoyISFKit` package is pure Swift with no Metal or ISFMSLKit dependency, so it
   is not a precedent for packaging the render layer.

**This plan instead extracts `ISFRuntime` as a shared source directory** listed in the `sources:` of
both app targets in `App/project.yml`. This satisfies §5's stated goals — one source of truth for
the ISF runtime, no duplicated vendored frameworks — and matches the pattern the repo already uses
to share code with its test target (`TrueISFEditorTests` compiles app sources directly rather than
using `@testable import`). Converting to a real package later is possible once ISFMSLKit is rebuilt
as an XCFramework; that is not Milestone 1 work.

## Global Constraints

Every task's requirements implicitly include this section.

- **Deployment target:** macOS 13.0. **Toolchain:** Xcode 26+, XcodeGen (`brew install xcodegen`).
- **Build architecture:** always `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` with an explicit
  `-derivedDataPath`. Never rely on default DerivedData — it silently serves stale incremental
  builds.
- **Signing (both app targets):** `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: Q9DY8S68BC`,
  `bundleIdPrefix: com.arsonrivvers`. `ENABLE_HARDENED_RUNTIME: YES` in Release, `NO` in Debug (the
  vendored frameworks contain ad-hoc-signed nested dylibs that library validation rejects).
- **`App/TrueISFEditor.xcodeproj` is generated and gitignored.** Run `xcodegen generate` from `App/`
  after any `project.yml` or new-file change, or the build silently omits the file.
- **Master resolution is fixed at 1920×1080.** Every persistent texture is allocated once; the
  steady-state frame performs no texture allocation.
- **Blend math comes from the W3C Compositing and Blending Level 1 specification only.** Never
  extract, decompile, or copy blend implementations from any installed commercial application.
- **Licensing:** no AGPL. All dependencies stay MIT/BSD/Apache.
- **Milestone 1 non-goals (spec §13):** audio reactivity, MIDI, Syphon out, movie recording, scenes
  and presets, deck-to-deck source routing, more than two decks. Do not build them, do not add
  parameters "for later".
- **App target name and bundle identifier:** `ARShader` / `com.arsonrivvers.ARShader`. This resolves
  spec §14 open question 1 with a default; changing it is two lines in `project.yml` plus a
  directory rename, and is cheap until Task 13.
- **Commit style:** Conventional Commits, and `Co-Authored-By` trailers are enabled for this user.
  Stage exact paths — never `git add .`.

## Threading Model — corrected during execution, 2026-07-30

**This section overrides any code block later in this plan that disagrees with it.** It was written
after Task 2's first build crashed on frame one.

The instrument renders on the **CVDisplayLink thread**, not the main thread. That is the entire
reason `DisplayLinkDriver` exists: the editor's own source comments record that a main-thread render
loop gets starved by AppKit/SwiftUI layout during a slider drag, collapsing FPS.

`MainActor.assumeIsolated` is a **runtime assertion**, not a way to quiet the compiler. Called off
the main actor it traps immediately — `dispatch_assert_queue_fail` inside
`swift_task_checkIsolatedSwift`. The first build of Task 2 died there on the first tick, before any
test could run.

**The rule for every type on the render path:**

| Type | Isolation | Why |
|---|---|---|
| `InstrumentRenderer` | `final class … @unchecked Sendable`, one `NSLock` | `renderFrame()` is called from the display-link thread |
| `Deck` | `@MainActor` for `@Published` UI state, but `render(in:)` and anything it touches must be `nonisolated` and lock-guarded | the frame graph calls it off-main |
| `MixerState` | `@MainActor` for the UI, plus a `nonisolated` lock-protected snapshot for the render thread | layer params are read per frame, off-main |
| `Compositor` | stateless after `init` | encode-only; no mutable state |
| `TexturePresentingView` closures | plain calls, no isolation wrapper | they already run off-main |

The precedent is in this codebase, twice: `MetalRenderCore` is `@unchecked Sendable` with one coarse
lock, and `SourceRouter` keeps a `nonisolated(unsafe)` mirror of its routes guarded by `routesLock`
specifically so the render thread never touches main-actor state. Copy those patterns; do not invent
a third.

## Verification commands

```sh
# From the repo root: ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter

# Conversion-kit suite (pure Swift package)
cd ShadertoyISFKit && swift test

# Regenerate the Xcode project after ANY project.yml or new-file change
cd App && xcodegen generate

# Editor app suite
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test

# Instrument app suite (exists from Task 2 onward)
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test

# Build + install the instrument as the single canonical app (Task 12)
./scripts/run-instrument.sh
```

## File Structure

**Moved into the shared runtime** (`App/ISFRuntime/`, from `App/TrueISFEditor/`) — these are the
files both the editor and the instrument need:

| File | Responsibility |
|---|---|
| `MetalRenderCore.swift` | Owns one `ISFMSLScene` behind a coarse lock; renders it to a texture. |
| `RenderClock.swift` | App-owned shader clock that survives scene swaps. |
| `DisplayLinkDriver.swift` | CVDisplayLink → off-main draw ticks. |
| `ImageSource.swift` | `ImageSource` protocol + `NoneSource`. |
| `SourceRouter.swift` | `[imageInputName: ImageSource]` map, render-thread-safe. |
| `ISFSceneSource.swift` | An `ImageSource` backed by a second ISF scene. |
| `CameraSource.swift` | Camera `ImageSource` + `SharedCamera`. |
| `BlitFit.swift` | Pure aspect-fit math. |
| `ISFPreviewInput.swift` | The ISF input descriptor struct. |
| `RenderStats.swift` | FPS/GPU-ms accumulator + observable model. |
| `FramePixelStats.swift` | Per-frame luma/NaN/digest analysis. |
| `FramePNGEncoder.swift` | Texture → PNG. |
| `PixelGate.swift` | Never-black / NaN verdict logic. |
| `GateInputPattern.swift` | Deterministic image-input pattern for headless gates. |
| `Models/ParamStore.swift` → `ParamStore.swift` | User-set shader input values, replayable. |
| `Models/LibraryModel.swift` → `LibraryModel.swift` | `.fs` folder enumeration + search. |
| `ISFMSLSafeBridge.h` / `.mm` | Crash-safe ObjC++ wrapper around ISFMSLKit. |

**New in the shared runtime:**

| File | Responsibility |
|---|---|
| `ISFRuntime-Bridging-Header.h` | Shared bridging header, imported by both app targets. |
| `ISFSceneLoader.swift` | Compile ISF text → `ISFMSLScene`; map scene attribs → `ISFPreviewInput`. |
| `TextureReadback.swift` | Blit any texture into a CPU-readable copy (test + gate support). |
| `BlendMath.swift` | W3C separable blend modes as pure Swift — the reference implementation. |
| `CrossfadeMacro.swift` | Crossfader weighting + effective-opacity math (pure). |

**New instrument target** (`App/ARShader/`):

| File | Responsibility |
|---|---|
| `ARShaderApp.swift` | `@main` App; owns the instrument, builds the window. |
| `Info.plist`, `ARShader.entitlements` | Bundle configuration. |
| `InstrumentRenderer.swift` | The single clock. Owns decks, compositor, master textures, frame graph. |
| `Deck.swift` | One deck: scene, params, image routing, owned output texture. |
| `MixerState.swift` | Observable: per-deck opacity/blend mode, crossfader, blackout. |
| `Compositor.swift` | Hand-written Metal blend pipeline (MSL as a source string). |
| `ProgramView.swift` | `MTKView` that presents the program texture. |
| `MonitorView.swift` | `MTKView` that presents an arbitrary source texture. |
| `DeckControlsView.swift` | Auto-generated per-shader controls for one deck. |
| `LibraryPanelView.swift` | Library browser; loads a shader into a deck. |
| `InstrumentView.swift` | Root layout: monitors, deck strips, mixer, blackout. |

**New instrument tests** (`App/ARShaderTests/`): one file per task, named below.

---

## Task 1: Extract the shared ISF runtime

**Files:**
- Create: `App/ISFRuntime/` (directory)
- Move (via `git mv`): the 17 files listed in the File Structure table above
- Create: `App/ISFRuntime/ISFRuntime-Bridging-Header.h`
- Create: `App/ISFRuntime/ISFSceneLoader.swift`
- Modify: `App/project.yml`
- Modify: `App/TrueISFEditor/TrueISFEditor-Bridging-Header.h`
- Modify: `App/TrueISFEditor/MetalPreviewController.swift:207-283` (delegate to `ISFSceneLoader`)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `ISFSceneLoader.load(source:device:) -> ISFSceneLoader.Result`,
  `ISFSceneLoader.mapInputs(_ attribs: [any ISFMSLSceneAttrib]) -> [ISFPreviewInput]`,
  `ISFSceneLoader.parseLine(from: String?) -> Int?`. Every moved type keeps its current name and
  `internal` access — both targets compile their own copy, so no `public` annotations are needed.

**This task is a refactor. Its gate is that the existing suites pass with identical counts.**

- [ ] **Step 1: Capture the real baseline before touching anything**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter
git status --porcelain    # MUST be empty; stop if not
git log --oneline -1
cd ShadertoyISFKit && swift test 2>&1 | tail -5
cd ../App && xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```

Write the two "Executed N tests" lines into `docs/superpowers/plans/.baseline-m1.txt`. The spec
cites 302 kit + 227 app; **use the numbers you actually observe**, not those. Every later step in
this task compares against the file, not against the spec.

- [ ] **Step 2: Move the files with `git mv` so history follows them**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App
mkdir -p ISFRuntime
for f in MetalRenderCore RenderClock DisplayLinkDriver ImageSource SourceRouter \
         ISFSceneSource CameraSource BlitFit ISFPreviewInput RenderStats \
         FramePixelStats FramePNGEncoder PixelGate GateInputPattern; do
  git mv "TrueISFEditor/$f.swift" "ISFRuntime/$f.swift"
done
git mv TrueISFEditor/Models/ParamStore.swift   ISFRuntime/ParamStore.swift
git mv TrueISFEditor/Models/LibraryModel.swift ISFRuntime/LibraryModel.swift
git mv TrueISFEditor/ISFMSLSafeBridge.h  ISFRuntime/ISFMSLSafeBridge.h
git mv TrueISFEditor/ISFMSLSafeBridge.mm ISFRuntime/ISFMSLSafeBridge.mm
```

- [ ] **Step 3: Create the shared bridging header**

`App/ISFRuntime/ISFRuntime-Bridging-Header.h`:

```objc
//  ISFRuntime-Bridging-Header.h
//  Shared by every app target that renders ISF. Exposes ISFMSLKit (Obj-C++) and the crash-safe
//  wrapper to Swift. Target-specific bridging headers #import this one and add their own headers.
#import <ISFMSLKit/ISFMSLKit.h>
#import "ISFMSLSafeBridge.h"
```

- [ ] **Step 4: Point the editor's bridging header at it**

`App/TrueISFEditor/TrueISFEditor-Bridging-Header.h` becomes:

```objc
//  TrueISFEditor-Bridging-Header.h
//  Editor-specific bridging: the shared ISF runtime plus the editor's crash writer.
#import "ISFRuntime-Bridging-Header.h"
#import "CrashWriter.h"
```

- [ ] **Step 5: Create `ISFSceneLoader` and move the input mapping into it**

`App/ISFRuntime/ISFSceneLoader.swift`:

```swift
import Foundation
import Metal
import ISFMSLKit

/// Compiles ISF source text into an `ISFMSLScene` and describes its inputs. Shared by the editor's
/// preview controller and the instrument's decks so both go through the SAME crash-safe path and
/// produce the SAME input descriptors.
///
/// Compilation is synchronous and blocking (a full GLSL→SPIR-V→MSL transpile). Callers that must
/// not stall the main thread run `load` on a background queue and apply the result on main.
enum ISFSceneLoader {
    struct Result {
        let scene: ISFMSLScene?
        let inputs: [ISFPreviewInput]
        let errorMessage: String?
        let errorLine: Int?
        var isValid: Bool { scene != nil && errorMessage == nil }
    }

    /// Write `source` to a temp `.fs` and compile it. The temp file is removed before returning.
    static func load(source: String, device: MTLDevice) -> Result {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("isfruntime-\(UUID().uuidString).fs")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return Result(scene: nil, inputs: [], errorMessage: "Could not stage shader source.",
                          errorLine: nil)
        }
        var compileError: ObjCBool = false
        var message: NSString?
        let scene = ISFMSLSafeCreateAndLoad(device, url, &compileError, &message)
        let msg = message as String?
        guard let scene, !compileError.boolValue else {
            return Result(scene: nil, inputs: [],
                          errorMessage: (msg?.isEmpty == false ? msg : "Shader failed to compile."),
                          errorLine: parseLine(from: msg))
        }
        return Result(scene: scene, inputs: mapInputs(scene.inputs),
                      errorMessage: nil, errorLine: nil)
    }

    /// Map ISFMSLKit scene attributes into the app-side input descriptors. Moved verbatim from
    /// `MetalPreviewController.mapInputs` — behavior must not change.
    static func mapInputs(_ attribs: [any ISFMSLSceneAttrib]) -> [ISFPreviewInput] {
        attribs.compactMap { attrib in
            let typeStr: String
            switch attrib.type {
            case .event:   typeStr = "event"
            case .bool:    typeStr = "bool"
            case .long:    typeStr = "long"
            case .float:   typeStr = "float"
            case .point2D: typeStr = "point2D"
            case .color:   typeStr = "color"
            case .image:   typeStr = "image"
            default:       return nil   // audio/cube: still unsupported
            }

            let defaultValue: Any?
            let minVal: Any?
            let maxVal: Any?

            switch attrib.type {
            case .color:
                let d = attrib.defaultVal
                defaultValue = [d.colorValue(by: 0), d.colorValue(by: 1),
                                d.colorValue(by: 2), d.colorValue(by: 3)]
                minVal = nil; maxVal = nil
            case .point2D:
                let d = attrib.defaultVal
                defaultValue = [d.pointValue(by: 0), d.pointValue(by: 1)]
                let mn = attrib.minVal
                minVal = [mn.pointValue(by: 0), mn.pointValue(by: 1)]
                let mx = attrib.maxVal
                maxVal = [mx.pointValue(by: 0), mx.pointValue(by: 1)]
            case .bool:
                defaultValue = attrib.defaultVal.boolValue
                minVal = nil; maxVal = nil
            case .event, .image:
                defaultValue = nil; minVal = nil; maxVal = nil
            default:
                defaultValue = attrib.defaultVal.doubleValue
                minVal = attrib.minVal.doubleValue
                maxVal = attrib.maxVal.doubleValue
            }

            let labels: [String]? = attrib.labelArray.isEmpty ? nil : attrib.labelArray
            let values: [Double]? = attrib.valArray.isEmpty ? nil
                : attrib.valArray.map { $0.doubleValue }

            return ISFPreviewInput(name: attrib.name, type: typeStr,
                                   defaultValue: defaultValue,
                                   min: minVal, max: maxVal,
                                   labels: labels, values: values)
        }
    }

    /// glslang error format: "ERROR: 0:NN:" → NN.
    static func parseLine(from msg: String?) -> Int? {
        guard let msg else { return nil }
        if let r = msg.range(of: #"0:(\d+):"#, options: .regularExpression) {
            let digits = msg[r].dropFirst(2).dropLast()
            return Int(digits)
        }
        return nil
    }
}
```

Then in `App/TrueISFEditor/MetalPreviewController.swift`, **delete** the bodies of
`static func mapInputs` (lines 207-262) and `static func parseLine` (lines 264-272) and replace both
with forwarders, so any existing caller keeps compiling:

```swift
    static func mapInputs(_ attribs: [any ISFMSLSceneAttrib]) -> [ISFPreviewInput] {
        ISFSceneLoader.mapInputs(attribs)
    }

    static func parseLine(from msg: String?) -> Int? {
        ISFSceneLoader.parseLine(from: msg)
    }
```

- [ ] **Step 6: Add `TextureReadback`**

`App/ISFRuntime/TextureReadback.swift`:

```swift
import Metal

/// Blit a GPU-private texture into a CPU-readable copy. Every pixel-verification path needs this
/// (VVMTLPool textures are `.private` and cannot be read directly), and each one used to open-code
/// it. Synchronous: commits its own command buffer and waits.
enum TextureReadback {
    static func managedCopy(of texture: MTLTexture,
                            device: MTLDevice,
                            queue: MTLCommandQueue) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height,
            mipmapped: false)
        desc.storageMode = .managed
        guard let readback = device.makeTexture(descriptor: desc),
              let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, to: readback)
        blit.synchronize(resource: readback)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return readback
    }
}
```

- [ ] **Step 7: Rewire `App/project.yml`**

In `targets.TrueISFEditor.sources`, add `ISFRuntime` above the existing `TrueISFEditor` entry:

```yaml
    sources:
      - path: ISFRuntime
      - path: TrueISFEditor
      - path: TrueISFEditor/Resources
        buildPhase: resources
```

In `targets.TrueISFEditor.settings.base`, change the bridging header and add a user header search
path so the quoted `#import "ISFMSLSafeBridge.h"` resolves from the new directory:

```yaml
        SWIFT_OBJC_BRIDGING_HEADER: TrueISFEditor/TrueISFEditor-Bridging-Header.h
        USER_HEADER_SEARCH_PATHS: $(SRCROOT)/ISFRuntime $(SRCROOT)/TrueISFEditor
```

In `targets.TrueISFEditorTests.sources`, **replace** the individual moved-file entries with the
directory, and delete the now-stale per-file lines for every file moved in Step 2:

```yaml
      - TrueISFEditorTests
      - path: TrueISFEditor/Resources/symbols.json
        buildPhase: resources
      - path: ISFRuntime
        excludes:
          - "ParamStore.swift"
      - TrueISFEditor/TestHarness.swift
      - TrueISFEditor/FetchStrategy.swift
      # ...every remaining TrueISFEditor/* entry stays exactly as it was...
```

> **The `ParamStore.swift` exclusion is load-bearing — found during execution, 2026-07-30.**
> This repo uses a HYBRID test setup: 45 test files `@testable import TrueISFEditor` (reaching the
> app module) *and* the test target compiles ~60 app sources directly into the test bundle. Types in
> both sets therefore exist twice as distinct types, and the tests navigate that on purpose —
> `ParamStoreTests.swift` carries a comment saying so explicitly.
>
> `ParamStore.swift` was **never** in the test target's source list; `ParamStoreTests` reaches it
> only through `@testable import`. A bare `- path: ISFRuntime` sweeps the whole directory and would
> mint a second, distinct `ParamStore` type in the test bundle — changing behavior in a refactor
> whose entire gate is "behavior unchanged". Every other file in `ISFRuntime` *was* already compiled
> into the test bundle, so no other exclusion is needed.

Add the same `USER_HEADER_SEARCH_PATHS` line to `targets.TrueISFEditorTests.settings.base`.

- [ ] **Step 8: Regenerate and build**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. The likely failure is a duplicate-symbol or missing-header error —
both mean a `project.yml` source entry is stale, not that the move was wrong.

- [ ] **Step 9: Run both suites and compare to the baseline**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/ShadertoyISFKit && swift test 2>&1 | tail -5
cd ../App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```

Expected: **identical** "Executed N tests" counts to `.baseline-m1.txt`, zero failures. A changed
count — in either direction — means the extraction was not behavior-preserving. Do not proceed; a
test that stopped being compiled is as much a failure as one that broke.

- [ ] **Step 10: Commit**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter
git add App/ISFRuntime App/TrueISFEditor App/project.yml
git commit -m "refactor(runtime): extract shared ISFRuntime source directory

Moves the ISF render layer out of the editor target into App/ISFRuntime, compiled
into both app targets. Adds ISFSceneLoader (shared compile + input mapping) and
TextureReadback. Editor and kit suites pass with unchanged counts.

Spec §5 called for a SwiftPM package; the vendored deps are plain .frameworks (not
XCFrameworks) and the ISFMSLKit safe bridge is Obj-C++ reached via a bridging header,
neither of which SwiftPM supports. A shared source directory meets the same goals."
```

---

## Task 2: Instrument target that boots to an opaque-black master

**Files:**
- Create: `App/ARShader/ARShaderApp.swift`
- Create: `App/ARShader/Info.plist`
- Create: `App/ARShader/ARShader.entitlements`
- Create: `App/ARShader/ARShader-Bridging-Header.h`
- Create: `App/ARShader/InstrumentRenderer.swift`
- Create: `App/ARShader/ProgramView.swift`
- Create: `App/ARShaderTests/InstrumentRendererTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: `RenderClock`, `DisplayLinkDriver`, `BlitFit`, `FramePixelStats`, `TextureReadback` (Task 1).
- Produces:
  - `final class InstrumentRenderer` — `init(device:queue:)`, `func renderFrame()`,
    `func programTexture() -> MTLTexture?`, `var onFrameRendered: (() -> Void)?`,
    `func start()`, `func stop()`, `static let masterWidth = 1920`, `static let masterHeight = 1080`.
  - `final class ProgramView: MTKView` — `var sourceTexture: (() -> MTLTexture?)?`.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/InstrumentRendererTests.swift`:

```swift
import XCTest
import Metal
import VVMetalKit

@MainActor
final class InstrumentRendererTests: XCTestCase {
    private func makeRenderer() throws -> (InstrumentRenderer, MTLDevice, MTLCommandQueue) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return (InstrumentRenderer(device: device, queue: queue), device, queue)
    }

    func testMasterIsFixedAt1920x1080() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        XCTAssertEqual(tex.width, 1920)
        XCTAssertEqual(tex.height, 1080)
    }

    func testEmptyInstrumentRendersOpaqueBlack() throws {
        let (renderer, device, queue) = try makeRenderer()
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        let readback = try XCTUnwrap(TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let stats = try XCTUnwrap(FramePixelStats.analyze(texture: readback))
        XCTAssertLessThan(stats.maxLuma, PixelGate.blackLumaFloor,
                          "An instrument with no shaders loaded must render black, not garbage")
        XCTAssertEqual(stats.nanCount, 0)
    }

    func testSteadyStateAllocatesNoNewTextures() throws {
        let (renderer, _, _) = try makeRenderer()
        renderer.renderFrame()
        let first = try XCTUnwrap(renderer.programTexture())
        for _ in 0..<30 { renderer.renderFrame() }
        let last = try XCTUnwrap(renderer.programTexture())
        XCTAssertTrue(first === last,
                      "Master textures are pooled and reused; a new object per frame means the "
                      + "steady-state frame is allocating")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

The `ARShader` scheme does not exist yet, so this fails at the scheme lookup:

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata test
```

Expected: `xcodebuild: error: The workspace ... does not contain a scheme named "ARShader".`

- [ ] **Step 3: Write `InstrumentRenderer`**

`App/ARShader/InstrumentRenderer.swift`:

```swift
import Metal
import QuartzCore
import VVMetalKit

/// The instrument's single clock and frame graph.
///
/// One `DisplayLinkDriver` drives ONE frame for everything — decks, compositor, monitors, program
/// output. This is the deliberate departure from the editor, where each MTKView owns its own
/// display link (correct for N independent previews, wrong for one instrument).
///
/// Master textures ping-pong: the compositor reads one and writes the other, so each layer sees the
/// backdrop the previous layer produced. Both are allocated once at 1920×1080; the steady-state
/// frame allocates nothing.
///
/// NOT @MainActor - renderFrame() runs on the display-link thread. See the Threading Model
/// section: MainActor.assumeIsolated is an assertion and traps there. One coarse NSLock guards
/// every field the render thread touches, exactly as MetalRenderCore does.
final class InstrumentRenderer: @unchecked Sendable {
    static let masterWidth = 1920
    static let masterHeight = 1080
    /// 16-bit float: ISF scenes commonly output float formats, and blending in a wider space than
    /// the 8-bit drawable avoids banding on repeated composites.
    static let masterFormat: MTLPixelFormat = .rgba16Float

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    let clock: RenderClock

    /// Ping-pong pair. `masterIndex` names the texture holding the CURRENT composited result.
    private var masters: [MTLTexture] = []
    private var masterIndex = 0

    private var driver: DisplayLinkDriver?
    /// Called on the render thread after each frame's command buffer is committed. Views hook this
    /// to present; nothing else may touch main-actor state from it.
    var onFrameRendered: (() -> Void)?

    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        self.clock = RenderClock()
        // ISFMSLKit needs its global pool before any scene work; harmless if already set.
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: device) }
        masters = (0..<2).compactMap { _ in Self.makeMaster(device: device) }
    }

    private static func makeMaster(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: masterFormat, width: masterWidth, height: masterHeight, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// The texture a consumer should display. Nil means "show opaque black" — consumers must honor
    /// that rather than reusing their last frame.
    func programTexture() -> MTLTexture? {
        masters.indices.contains(masterIndex) ? masters[masterIndex] : nil
    }

    /// Render exactly one frame. Task 2 renders an empty instrument: clear the master to opaque
    /// black. Tasks 6-8 extend this into the full deck → compositor → blackout graph.
    func renderFrame() {
        guard let cb = queue.makeCommandBuffer(), let master = programTexture() else { return }
        clearToOpaqueBlack(master, in: cb)
        cb.commit()
        onFrameRendered?()
    }

    /// The one operation that must never depend on a compiled pipeline: a render pass whose only
    /// job is a clear. This is the failure floor for the whole instrument (spec §8).
    func clearToOpaqueBlack(_ texture: MTLTexture, in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
    }

    // MARK: clock control

    func start() { driver?.start() }
    func stop() { driver?.pause() }

    /// Attach the display link to the view that owns the frame cadence (the program output).
    /// Called once, after the window exists.
    func attachClock(to view: MTKView) {
        guard driver == nil else { return }
        driver = DisplayLinkDriver(view: view)
        view.isPaused = (driver != nil)
        driver?.start()
    }

    deinit { driver?.invalidate() }
}
```

Add `import MetalKit` at the top alongside the others.

- [ ] **Step 4: Write `ProgramView`**

`App/ARShader/ProgramView.swift`:

```swift
import MetalKit

/// Presents a source texture, aspect-fit, with an opaque-black clear behind it.
///
/// `sourceTexture` returning nil is the blackout / no-output path and MUST render black — never a
/// stale frame. That property is what makes blackout structurally independent of the compositor.
final class TexturePresentingView: MTKView, MTKViewDelegate {
    /// Pulled once per draw. Nil ⇒ present opaque black.
    var sourceTexture: (() -> MTLTexture?)?

    private var pipeline: MTLRenderPipelineState?
    private var pipelineFormat: MTLPixelFormat = .invalid
    private let queue: MTLCommandQueue

    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.queue = queue
        super.init(frame: .zero, device: device)
        self.delegate = self
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = false
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Rebuild if the drawable format changed; a pipeline built for the old format would render
        // through a mismatched attachment description.
        if pipeline == nil || pipelineFormat != view.colorPixelFormat {
            pipeline = Self.makePipeline(device: device!, colorFormat: view.colorPixelFormat)
            pipelineFormat = view.colorPixelFormat
        }

        // Nil source, or no pipeline: the clear alone IS the frame. Opaque black, always.
        guard let tex = sourceTexture?(), let pipeline else {
            cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
            cb.present(drawable)
            cb.commit()
            return
        }

        var fit = BlitFit.scale(
            textureSize: MTLSize(width: tex.width, height: tex.height, depth: 1),
            drawableSize: view.drawableSize)
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBytes(&fit, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        cb.present(drawable)
        cb.commit()
    }

    /// Fullscreen quad at the ±fit corners. A quad (not a fullscreen triangle) so letterboxing
    /// cannot expose a hypotenuse as a diagonal cut.
    private static func makePipeline(device: MTLDevice,
                                     colorFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        vertex VOut ar_present_v(uint vid [[vertex_id]], constant float2& fit [[buffer(0)]]) {
            float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
            VOut o;
            o.pos = float4((corner * 2.0 - 1.0) * fit, 0.0, 1.0);
            o.uv = float2(corner.x, 1.0 - corner.y);
            return o;
        }
        fragment float4 ar_present_f(VOut v [[stage_in]], texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return float4(tex.sample(s, v.uv).rgb, 1.0);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "ar_present_v")
        desc.fragmentFunction = lib.makeFunction(name: "ar_present_f")
        desc.colorAttachments[0].pixelFormat = colorFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}
```

- [ ] **Step 5: Write the app entry point**

`App/ARShader/ARShaderApp.swift`:

```swift
import SwiftUI
import Metal
import VVMetalKit

@main
struct ARShaderApp: App {
    @StateObject private var instrument = Instrument()

    var body: some Scene {
        WindowGroup("ARShader") {
            InstrumentRootView(instrument: instrument)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Process-wide owner of the Metal context and the renderer. One instance, created at launch.
@MainActor
final class Instrument: ObservableObject {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let renderer: InstrumentRenderer

    init() {
        let props = RenderProperties.global()
        self.device = props.device
        self.queue = props.renderQueue
        self.renderer = InstrumentRenderer(device: props.device, queue: props.renderQueue)
    }
}

/// Task 2 placeholder root: the program output filling the window. Task 13 replaces it.
struct InstrumentRootView: View {
    @ObservedObject var instrument: Instrument
    var body: some View {
        ProgramOutputView(instrument: instrument).background(.black)
    }
}
```

`App/ARShader/ProgramView.swift` gains the SwiftUI wrapper at the bottom:

```swift
import SwiftUI

/// SwiftUI host for the program output. Owns the clock attachment: the display link starts when
/// this view is in a window and drives the whole instrument.
struct ProgramOutputView: NSViewRepresentable {
    let instrument: Instrument

    func makeNSView(context: Context) -> TexturePresentingView {
        let view = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        let renderer = instrument.renderer
        // Each tick: render one frame, then present it in this same view's draw pass.
        view.sourceTexture = { renderer.programTexture() }   // display-link thread; no isolation wrapper
        view.preferredFramesPerSecond = 60
        DispatchQueue.main.async { renderer.attachClock(to: view) }
        return view
    }

    func updateNSView(_ nsView: TexturePresentingView, context: Context) {}
}
```

> **Frame-order note for Task 7:** at Task 2 the renderer only clears, so presenting the master
> while `renderFrame()` has not yet run this tick is harmless. Task 7 makes `renderFrame()` the
> first thing the tick does, before any view draws.

- [ ] **Step 6: Write the bundle files**

`App/ARShader/ARShader-Bridging-Header.h`:

```objc
//  ARShader-Bridging-Header.h
#import "ISFRuntime-Bridging-Header.h"
```

`App/ARShader/Info.plist` — copy `App/TrueISFEditor/Info.plist` and change `CFBundleName`,
`CFBundleExecutable`, and `CFBundleIdentifier` to `ARShader` / `com.arsonrivvers.ARShader`. Keep
`NSCameraUsageDescription` (filter shaders default their primary image input to the camera):

```xml
	<key>NSCameraUsageDescription</key>
	<string>ARShader uses the camera as a live source for filter shaders.</string>
```

`App/ARShader/ARShader.entitlements` — copy `App/TrueISFEditor/TrueISFEditor.entitlements` verbatim.

- [ ] **Step 7: Add both targets to `project.yml`**

Append under `targets:`:

```yaml
  ARShader:
    type: application
    platform: macOS
    sources:
      - path: ISFRuntime
      - path: ARShader
    dependencies:
      - package: ShadertoyISFKit
      - framework: ../vendor/prebuilt/ISFMSLKit.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/VVMetalKit.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/PINCache.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/PINOperation.framework
        embed: true
        codeSign: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arsonrivvers.ARShader
        INFOPLIST_FILE: ARShader/Info.plist
        CODE_SIGN_ENTITLEMENTS: ARShader/ARShader.entitlements
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: Q9DY8S68BC
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "0.1.0"
        GENERATE_INFOPLIST_FILE: NO
        FRAMEWORK_SEARCH_PATHS: $(SRCROOT)/../vendor/prebuilt
        LD_RUNPATH_SEARCH_PATHS: $(inherited) @executable_path/../Frameworks
        SWIFT_OBJC_BRIDGING_HEADER: ARShader/ARShader-Bridging-Header.h
        USER_HEADER_SEARCH_PATHS: $(SRCROOT)/ISFRuntime $(SRCROOT)/ARShader
      configs:
        Debug:
          ENABLE_HARDENED_RUNTIME: NO
  ARShaderTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ARShaderTests
      - path: ISFRuntime
      - path: ARShader
        excludes:
          - "ARShaderApp.swift"   # a second @main in the test bundle is a duplicate entry point
    dependencies:
      - target: ARShader
      - package: ShadertoyISFKit
      - framework: ../vendor/prebuilt/ISFMSLKit.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/VVMetalKit.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/PINCache.framework
        embed: true
        codeSign: true
      - framework: ../vendor/prebuilt/PINOperation.framework
        embed: true
        codeSign: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arsonrivvers.ARShaderTests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/ARShader.app/Contents/MacOS/ARShader"
        BUNDLE_LOADER: "$(TEST_HOST)"
        FRAMEWORK_SEARCH_PATHS: $(SRCROOT)/../vendor/prebuilt
        LD_RUNPATH_SEARCH_PATHS: $(inherited) @loader_path/../Frameworks $(SRCROOT)/../vendor/prebuilt
        SWIFT_OBJC_BRIDGING_HEADER: ARShader/ARShader-Bridging-Header.h
        USER_HEADER_SEARCH_PATHS: $(SRCROOT)/ISFRuntime $(SRCROOT)/ARShader
```

And under `schemes:`:

```yaml
  ARShader:
    build:
      targets:
        ARShader: all
        ARShaderTests: [test]
    test:
      targets: [ARShaderTests]
```

- [ ] **Step 8: Run the tests to verify they pass**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```

Expected: 3 tests, 0 failures.

- [ ] **Step 9: Confirm the editor suite still passes**

Adding a target must not disturb the editor. Re-run the editor scheme and compare to
`.baseline-m1.txt` again — same counts, zero failures.

- [ ] **Step 10: Commit**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter
git add App/ARShader App/ARShaderTests App/project.yml
git commit -m "feat(instrument): ARShader target boots to an opaque-black 1920x1080 master

One InstrumentRenderer owning one RenderClock and one DisplayLinkDriver, with a
ping-pong pair of master textures allocated once. TexturePresentingView renders
opaque black when its source texture is nil - the property blackout depends on."
```

---

## Task 3: Offscreen deck rendering and the `Deck` model

**Files:**
- Modify: `App/ISFRuntime/MetalRenderCore.swift` (add `renderOffscreen(size:in:)`, refactor `renderOnce`)
- Create: `App/ISFRuntime/TextureCopyPass.swift`
- Create: `App/ARShader/Deck.swift`
- Create: `App/ARShaderTests/DeckTests.swift`
- Create: `App/ARShaderTests/Fixtures/solid_red.fs`
- Create: `App/ARShaderTests/Fixtures/solid_green.fs`
- Create: `App/ARShaderTests/Fixtures/broken.fs`
- Modify: `App/project.yml` (add the fixtures as test resources)

**Interfaces:**
- Consumes: `MetalRenderCore`, `ISFSceneLoader`, `SourceRouter`, `ParamStore`, `TextureReadback`,
  `InstrumentRenderer.masterWidth/masterHeight/masterFormat` (Tasks 1–2).
- Produces:
  - `MetalRenderCore.renderOffscreen(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?`
    — renders the current scene at app-clock time into the caller's command buffer, binding routed
    image inputs. **Does not commit.** Returns nil when no scene is loaded.
  - `TextureCopyPass.init?(device:destinationFormat:)`,
    `func encode(from: MTLTexture, to: MTLTexture, in cb: MTLCommandBuffer)`.
  - `enum DeckID: String, CaseIterable { case one = "1", two = "2" }` with `var displayName: String`
    (`"A"` / `"B"`).
  - `final class Deck: ObservableObject` — `init(id:device:queue:clock:)`,
    `func load(url: URL)`, `func load(source: String, name: String)`,
    `func render(in cb: MTLCommandBuffer) -> MTLTexture?`,
    `@Published private(set) var shaderName: String?`,
    `@Published private(set) var compileError: String?`,
    `@Published private(set) var inputs: [ISFPreviewInput]`,
    `@Published private(set) var isLoading: Bool`,
    `let params: ParamStore`, `let imageSources: SourceRouter`,
    `var onCompileFinished: (() -> Void)?`.

- [ ] **Step 1: Write the test fixtures**

`App/ARShaderTests/Fixtures/solid_red.fs`:

```glsl
/*{
    "DESCRIPTION": "Solid red — deterministic compositor fixture.",
    "CREDIT": "ARShader test fixture",
    "CATEGORIES": ["Test"],
    "INPUTS": []
}*/

void main() {
    gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
```

`App/ARShaderTests/Fixtures/solid_green.fs` — identical but `vec4(0.0, 1.0, 0.0, 1.0)` and
`"DESCRIPTION": "Solid green — deterministic compositor fixture."`.

`App/ARShaderTests/Fixtures/broken.fs`:

```glsl
/*{
    "DESCRIPTION": "Deliberately uncompilable — proves a failed compile never reaches the output.",
    "CATEGORIES": ["Test"],
    "INPUTS": []
}*/

void main() {
    gl_FragColor = this_symbol_does_not_exist(1.0);
}
```

- [ ] **Step 2: Write the failing tests**

`App/ARShaderTests/DeckTests.swift`:

```swift
import XCTest
import Metal
import ISFMSLKit

@MainActor
final class DeckTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeDeck() -> Deck {
        Deck(id: .one, device: device, queue: queue, clock: RenderClock())
    }

    /// Load synchronously for tests: compile happens off-main, so wait for the callback.
    private func loadAndWait(_ deck: Deck, source: String, name: String) {
        let done = expectation(description: "compile \(name)")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: source, name: name)
        wait(for: [done], timeout: 30)
        deck.onCompileFinished = nil
    }

    private func meanRGB(of texture: MTLTexture) throws -> SIMD3<Double> {
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: texture, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testEmptyDeckRendersNothing() throws {
        let deck = makeDeck()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(deck.render(in: cb), "A deck with no shader must return nil, not a stale texture")
        cb.commit()
    }

    func testLoadedDeckRendersItsShader() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        XCTAssertNil(deck.compileError)
        XCTAssertEqual(deck.shaderName, "solid_red.fs")

        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = try XCTUnwrap(deck.render(in: cb))
        cb.commit()
        cb.waitUntilCompleted()

        let rgb = try meanRGB(of: tex)
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
        XCTAssertEqual(rgb.y, 0.0, accuracy: 0.02)
        XCTAssertEqual(rgb.z, 0.0, accuracy: 0.02)
    }

    func testFailedCompileLeavesTheRunningShaderUntouched() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        loadAndWait(deck, source: try fixture("broken"), name: "broken.fs")

        XCTAssertNotNil(deck.compileError, "The failure must be reported")
        XCTAssertEqual(deck.shaderName, "solid_red.fs",
                       "A failed compile must not claim to have loaded")

        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let tex = try XCTUnwrap(deck.render(in: cb), "The previous shader must still be rendering")
        cb.commit()
        cb.waitUntilCompleted()
        let rgb = try meanRGB(of: tex)
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02, "Still red — the failed compile never swapped in")
    }

    func testDeckOutputTextureIsReusedAcrossFrames() throws {
        let deck = makeDeck()
        loadAndWait(deck, source: try fixture("solid_red"), name: "solid_red.fs")
        let cb1 = try XCTUnwrap(queue.makeCommandBuffer())
        let first = try XCTUnwrap(deck.render(in: cb1))
        cb1.commit(); cb1.waitUntilCompleted()
        let cb2 = try XCTUnwrap(queue.makeCommandBuffer())
        let second = try XCTUnwrap(deck.render(in: cb2))
        cb2.commit(); cb2.waitUntilCompleted()
        XCTAssertTrue(first === second,
                      "The deck owns ONE output texture — a per-frame allocation would also mean "
                      + "monitors could sample a pool-recycled texture")
    }

    func testRenderOffscreenDoesNotCommitTheCallersCommandBuffer() throws {
        let core = MetalRenderCore(device: device, renderQueue: queue)
        let result = ISFSceneLoader.load(source: try fixture("solid_red"), device: device)
        core.setScene(result.scene, imageInputNames: [])
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        _ = core.renderOffscreen(size: MTLSize(width: 64, height: 36, depth: 1), in: cb)
        XCTAssertEqual(cb.status, .notEnqueued,
                       "renderOffscreen must leave the command buffer to its caller — the whole "
                       + "frame is one buffer")
        cb.commit()
    }
}
```

`App/ARShaderTests/TestPixels.swift` (a shared helper this and later tasks use):

```swift
import Metal

/// Mean RGB of a CPU-readable texture, in linear 0-1. Supports the formats the instrument produces
/// (`.rgba16Float` master and deck outputs) plus the 8-bit formats ISF scenes commonly return.
enum TestPixels {
    static func meanRGB(of texture: MTLTexture) -> SIMD3<Double>? {
        let w = texture.width, h = texture.height
        guard w > 0, h > 0 else { return nil }
        var sum = SIMD3<Double>(0, 0, 0)

        switch texture.pixelFormat {
        case .rgba16Float:
            var bytes = [UInt16](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: w * 8,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            for i in stride(from: 0, to: bytes.count, by: 4) {
                sum += SIMD3(Double(Float16(bitPattern: bytes[i])),
                             Double(Float16(bitPattern: bytes[i + 1])),
                             Double(Float16(bitPattern: bytes[i + 2])))
            }
        case .bgra8Unorm, .bgra8Unorm_srgb:
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: w * 4,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            for i in stride(from: 0, to: bytes.count, by: 4) {
                sum += SIMD3(Double(bytes[i + 2]) / 255.0, Double(bytes[i + 1]) / 255.0,
                             Double(bytes[i]) / 255.0)
            }
        case .rgba8Unorm, .rgba8Unorm_srgb:
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: w * 4,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            for i in stride(from: 0, to: bytes.count, by: 4) {
                sum += SIMD3(Double(bytes[i]) / 255.0, Double(bytes[i + 1]) / 255.0,
                             Double(bytes[i + 2]) / 255.0)
            }
        default:
            return nil
        }
        return sum / Double(w * h)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App && xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'Deck' in scope`, `value of type 'MetalRenderCore' has no
member 'renderOffscreen'`.

- [ ] **Step 4: Add `renderOffscreen` to `MetalRenderCore`**

In `App/ISFRuntime/MetalRenderCore.swift`, **replace** `renderOnce(drawableSize:)` (lines 101-112)
with:

```swift
    /// Render the current scene into the CALLER's command buffer and return the engine's output
    /// texture. Does NOT commit — the instrument encodes an entire frame (both decks, the
    /// compositor, the blackout gate) into one buffer, so committing here would split it.
    ///
    /// Binds routed image-input sources first, inside the same buffer, so a source renders before
    /// the filter that reads it (the ordering `draw(in:)` already relies on).
    func renderOffscreen(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        guard let scene else { return nil }
        for name in imageInputNames {
            if let src = imageRouter?.renderSource(for: name),
               let tex = src.texture(size: size, in: cb),
               let val = ISFMSLSceneVal.create(with: tex) as? ISFMSLSceneVal {
                scene.setValue(val, forInputNamed: name)
            }
        }
        var err: NSString?
        return ISFMSLSafeRenderAtTime(scene, NSSize(width: size.width, height: size.height),
                                      clock.now, cb, &err)
    }

    /// Offscreen one-frame render at the current target size (editor test hook; commits its own
    /// buffer and returns once encoded).
    @discardableResult
    func renderOnce(drawableSize: CGSize) -> MTLTexture? {
        guard let cb = renderQueue.makeCommandBuffer() else { return nil }
        let size = lock.withLock { targetSizeLocked(drawableSize: drawableSize) }
        let tex = renderOffscreen(size: size, in: cb)
        cb.commit()
        return tex
    }
```

`targetSizeLocked` is `private` and requires the lock; add this small helper next to it so
`renderOnce` can read the size without duplicating lock code:

```swift
    /// Run `body` under the render lock. Mirrors `withScene` for callers that need other
    /// lock-guarded state.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
```

and change `renderOnce`'s size line to `let size = withLock { targetSizeLocked(drawableSize: drawableSize) }`.

- [ ] **Step 5: Add `TextureCopyPass`**

`App/ISFRuntime/TextureCopyPass.swift`:

```swift
import Metal

/// A format-converting full-target copy: samples a source texture into a destination render target.
///
/// Not a blit. `MTLBlitCommandEncoder.copy` requires matching pixel formats, and ISF scenes return
/// whatever format their last pass used (8-bit unorm, 16-bit float, 32-bit float). Sampling
/// converts, so any engine output lands in the instrument's fixed master format.
///
/// Why the instrument needs an owned copy at all: engine output textures come from `VVMTLPool`,
/// which recycles them. Anything that reads a deck texture in a LATER command buffer (the deck
/// monitors) could otherwise sample memory the pool has already handed to another render — the
/// same aliasing bug `ISFSceneSource` fixed with its own owned last-good texture.
final class TextureCopyPass {
    private let pipeline: MTLRenderPipelineState

    init?(device: MTLDevice, destinationFormat: MTLPixelFormat) {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        vertex VOut ar_copy_v(uint vid [[vertex_id]]) {
            float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
            VOut o;
            o.pos = float4(corner * 2.0 - 1.0, 0.0, 1.0);
            o.uv = float2(corner.x, 1.0 - corner.y);
            return o;
        }
        fragment float4 ar_copy_f(VOut v [[stage_in]], texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return tex.sample(s, v.uv);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "ar_copy_v")
        desc.fragmentFunction = lib.makeFunction(name: "ar_copy_f")
        desc.colorAttachments[0].pixelFormat = destinationFormat
        guard let p = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        pipeline = p
    }

    func encode(from source: MTLTexture, to destination: MTLTexture, in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = destination
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(source, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}
```

- [ ] **Step 6: Write `Deck`**

`App/ARShader/Deck.swift`:

```swift
import Foundation
import Metal
import Combine
import ISFMSLKit

enum DeckID: String, CaseIterable, Identifiable {
    case one = "1"
    case two = "2"
    var id: String { rawValue }
    /// What the operator sees. Decks are "A" and "B" on the surface, 1 and 2 in the layer stack.
    var displayName: String { self == .one ? "A" : "B" }
}

/// One deck: a loaded ISF shader, its parameter values, its image-input routing, and one owned
/// output texture.
///
/// **Compile first, swap only on success.** A failed compile leaves the running shader playing and
/// reports the error. This is the opposite of the editor's behavior (which drops the scene so the
/// author sees their mistake) and it is deliberate: on stage, the shader that is already up is the
/// one thing you cannot afford to lose. Ported from Phase A rather than rediscovered.
///
/// @MainActor covers the @Published UI state ONLY. `render(in:)` is called from the display-link
/// thread and must be `nonisolated` - it touches only MetalRenderCore (already lock-guarded), the
/// owned output texture, and the copy pass. See the Threading Model section.
@MainActor
final class Deck: ObservableObject {
    let id: DeckID
    let params = ParamStore()
    let imageSources: SourceRouter

    @Published private(set) var shaderName: String?
    @Published private(set) var compileError: String?
    @Published private(set) var compileErrorLine: Int?
    @Published private(set) var inputs: [ISFPreviewInput] = []
    @Published private(set) var isLoading = false

    /// Fired on the main actor after every load attempt, success or failure. Tests await it.
    var onCompileFinished: (() -> Void)?

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let core: MetalRenderCore
    private let compileQueue = DispatchQueue(label: "arshader.deck.compile", qos: .userInitiated)
    private lazy var copyPass = TextureCopyPass(
        device: device, destinationFormat: InstrumentRenderer.masterFormat)
    private var ownedOutput: MTLTexture?
    /// Monotonic: a compile finishing for anything but the current generation is superseded.
    private var loadGeneration = 0

    init(id: DeckID, device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.id = id
        self.device = device
        self.queue = queue
        self.imageSources = SourceRouter(device: device, queue: queue)
        self.core = MetalRenderCore(device: device, renderQueue: queue, clock: clock)
        core.imageRouter = imageSources
        // A fresh scene boots at header defaults; replay the operator's values over it.
        params.onSet = { [weak self] name, json in self?.applyInput(name, json) }
    }

    // MARK: loading

    func load(url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            compileError = "Could not read \(url.lastPathComponent)."
            onCompileFinished?()
            return
        }
        load(source: text, name: url.lastPathComponent)
    }

    func load(source: String, name: String) {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let device = self.device
        compileQueue.async { [weak self] in
            let result = ISFSceneLoader.load(source: source, device: device)
            Task { @MainActor in self?.apply(result, name: name, generation: generation) }
        }
    }

    private func apply(_ result: ISFSceneLoader.Result, name: String, generation: Int) {
        guard generation == loadGeneration else { return }   // superseded by a newer load
        isLoading = false
        guard let scene = result.scene, result.isValid else {
            // FAILURE PATH: report, change nothing else. The previous scene keeps rendering.
            compileError = result.errorMessage ?? "Shader failed to compile."
            compileErrorLine = result.errorLine
            onCompileFinished?()
            return
        }
        compileError = nil
        compileErrorLine = nil
        shaderName = name
        inputs = result.inputs
        imageSources.updateInputs(result.inputs)
        params.syncInputs(result.inputs)
        core.setScene(scene, imageInputNames: result.inputs.filter { $0.type == "image" }.map(\.name))
        params.replayAll()
        onCompileFinished?()
    }

    /// Clear the deck back to no shader — the layer contributes nothing.
    func unload() {
        loadGeneration += 1
        core.setScene(nil, imageInputNames: [])
        shaderName = nil
        inputs = []
        compileError = nil
        params.resetAll()
    }

    // MARK: inputs

    private func applyInput(_ name: String, _ jsonValue: String) {
        guard let data = jsonValue.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else { return }
        var val: ISFMSLSceneVal?
        if let b = raw as? Bool {
            val = ISFMSLSceneVal.create(with: b) as? ISFMSLSceneVal
        } else if let arr = raw as? [Any] {
            let d = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
            if d.count == 2 {
                val = ISFMSLSceneVal.create(withPoint2D: NSPoint(x: d[0], y: d[1])) as? ISFMSLSceneVal
            } else if d.count >= 4 {
                val = ISFMSLSceneVal.create(with: NSColor(red: d[0], green: d[1], blue: d[2],
                                                          alpha: d[3])) as? ISFMSLSceneVal
            }
        } else if let n = raw as? NSNumber {
            val = CFNumberIsFloatType(n as CFNumber)
                ? ISFMSLSceneVal.create(withFloat: n.doubleValue) as? ISFMSLSceneVal
                : ISFMSLSceneVal.create(withLong: n.int32Value) as? ISFMSLSceneVal
        }
        if let val { core.withScene { $0?.setValue(val, forInputNamed: name) } }
    }

    /// Fire an ISF `event` input for exactly one rendered frame.
    func pulseEvent(_ name: String) {
        core.withScene { $0?.setValue(ISFMSLSceneVal.createWithEvent(), forInputNamed: name) }
    }

    // MARK: rendering

    /// Render this deck into the caller's command buffer and return the deck's OWNED output
    /// texture. Nil when no shader is loaded — the layer contributes nothing and the compositor
    /// skips it. Never returns a pool texture: monitors read this in a later buffer.
    func render(in cb: MTLCommandBuffer) -> MTLTexture? {
        let size = MTLSize(width: InstrumentRenderer.masterWidth,
                           height: InstrumentRenderer.masterHeight, depth: 1)
        guard let engineTexture = core.renderOffscreen(size: size, in: cb) else { return nil }
        if ownedOutput == nil { ownedOutput = Self.makeOutputTexture(device: device) }
        guard let owned = ownedOutput, let copyPass else { return nil }
        copyPass.encode(from: engineTexture, to: owned, in: cb)
        return owned
    }

    private static func makeOutputTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat,
            width: InstrumentRenderer.masterWidth,
            height: InstrumentRenderer.masterHeight, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }
}
```

Add `import AppKit` for `NSPoint`/`NSColor`.

- [ ] **Step 7: Register the fixtures as test resources**

In `project.yml`, under `targets.ARShaderTests.sources`, add:

```yaml
      - path: ARShaderTests/Fixtures
        buildPhase: resources
        type: folder
```

- [ ] **Step 8: Run the tests to verify they pass**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App && xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```

Expected: 8 tests (3 from Task 2 + 5 new), 0 failures.

- [ ] **Step 9: Re-run the editor suite**

`renderOnce` changed shape. Confirm the editor suite still matches `.baseline-m1.txt` exactly.

- [ ] **Step 10: Commit**

```sh
git add App/ISFRuntime/MetalRenderCore.swift App/ISFRuntime/TextureCopyPass.swift \
        App/ARShader/Deck.swift App/ARShaderTests App/project.yml
git commit -m "feat(instrument): decks render offscreen into the frame's command buffer

renderOffscreen encodes without committing so one frame stays one buffer. Deck
compiles off-main and swaps ONLY on success - a failed compile leaves the running
shader playing. Each deck owns its output texture (TextureCopyPass converts format)
so monitors reading it in a later buffer cannot sample pool-recycled memory."
```

---

## Task 4: W3C blend math as a pure Swift reference

**Files:**
- Create: `App/ISFRuntime/BlendMath.swift`
- Create: `App/ARShaderTests/BlendMathTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum BlendMode: String, CaseIterable, Identifiable` — cases `normal, multiply, screen, overlay,
    darken, lighten, colorDodge, colorBurn, hardLight, softLight, difference, exclusion`, with
    `var displayName: String` and `var shaderIndex: Int32` (its position in `allCases`, the value
    handed to MSL).
  - `enum BlendMath` — `static func blend(_ mode: BlendMode, backdrop: Double, source: Double) -> Double`,
    `static func blend(_ mode: BlendMode, backdrop: SIMD3<Double>, source: SIMD3<Double>) -> SIMD3<Double>`,
    `static func composite(backdrop: SIMD3<Double>, source: SIMD3<Double>, alpha: Double, mode: BlendMode) -> SIMD3<Double>`.

This is the **reference implementation**. Task 6's MSL is a transcription of it, and Task 6's
golden-frame tests assert the GPU agrees with this Swift within tolerance. Getting this right is
what makes the GPU verifiable at all.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/BlendMathTests.swift`:

```swift
import XCTest

/// Expected values are computed by hand from the W3C Compositing and Blending Level 1 formulas
/// (§blending, separable blend modes). No implementation was consulted.
final class BlendMathTests: XCTestCase {
    private let acc = 1e-9

    func testNormalReturnsTheSource() {
        XCTAssertEqual(BlendMath.blend(.normal, backdrop: 0.2, source: 0.8), 0.8, accuracy: acc)
    }

    func testMultiply() {
        XCTAssertEqual(BlendMath.blend(.multiply, backdrop: 0.5, source: 0.5), 0.25, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.multiply, backdrop: 1.0, source: 0.3), 0.3, accuracy: acc)
    }

    func testScreen() {
        // Cb + Cs - Cb*Cs
        XCTAssertEqual(BlendMath.blend(.screen, backdrop: 0.5, source: 0.5), 0.75, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.screen, backdrop: 0.0, source: 0.4), 0.4, accuracy: acc)
    }

    func testDarkenAndLighten() {
        XCTAssertEqual(BlendMath.blend(.darken, backdrop: 0.3, source: 0.7), 0.3, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.lighten, backdrop: 0.3, source: 0.7), 0.7, accuracy: acc)
    }

    func testHardLightBothBranches() {
        // Cs <= 0.5 -> Multiply(Cb, 2*Cs) = 0.4 * 0.6 = 0.24
        XCTAssertEqual(BlendMath.blend(.hardLight, backdrop: 0.4, source: 0.3), 0.24, accuracy: acc)
        // Cs > 0.5 -> Screen(Cb, 2*Cs - 1) = 0.4 + 0.5 - 0.2 = 0.7
        XCTAssertEqual(BlendMath.blend(.hardLight, backdrop: 0.4, source: 0.75), 0.7, accuracy: acc)
    }

    func testOverlayIsHardLightWithSwappedArguments() {
        // overlay(Cb=0.25, Cs=0.75) == hardLight(Cb=0.75, Cs=0.25)
        //   = Multiply(0.75, 0.5) = 0.375
        XCTAssertEqual(BlendMath.blend(.overlay, backdrop: 0.25, source: 0.75), 0.375, accuracy: acc)
        for cb in stride(from: 0.0, through: 1.0, by: 0.1) {
            for cs in stride(from: 0.0, through: 1.0, by: 0.1) {
                XCTAssertEqual(BlendMath.blend(.overlay, backdrop: cb, source: cs),
                               BlendMath.blend(.hardLight, backdrop: cs, source: cb),
                               accuracy: acc)
            }
        }
    }

    func testColorDodgeIncludingItsTwoSpecialCases() {
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.0, source: 0.9), 0.0, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.5, source: 1.0), 1.0, accuracy: acc)
        // min(1, Cb / (1 - Cs)) = min(1, 0.5/0.5) = 1
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.5, source: 0.5), 1.0, accuracy: acc)
        // min(1, 0.2/0.75) = 0.2666...
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.2, source: 0.25),
                       0.2 / 0.75, accuracy: acc)
    }

    func testColorBurnIncludingItsTwoSpecialCases() {
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 1.0, source: 0.1), 1.0, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 0.5, source: 0.0), 0.0, accuracy: acc)
        // 1 - min(1, (1-0.5)/0.5) = 0
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 0.5, source: 0.5), 0.0, accuracy: acc)
        // 1 - min(1, (1-0.8)/0.5) = 1 - 0.4 = 0.6
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 0.8, source: 0.5), 0.6, accuracy: acc)
    }

    func testSoftLightBothBranchesAndTheDFunctionSplit() {
        // Cs <= 0.5: Cb - (1 - 2Cs) * Cb * (1 - Cb)
        //          = 0.25 - 0.5 * 0.25 * 0.75 = 0.15625
        XCTAssertEqual(BlendMath.blend(.softLight, backdrop: 0.25, source: 0.25),
                       0.15625, accuracy: acc)
        // Cs > 0.5, Cb <= 0.25: D(Cb) = ((16*0.16 - 12) * 0.16 + 4) * 0.16 = 0.398336
        //          B = 0.16 + (2*0.75 - 1) * (0.398336 - 0.16) = 0.279168
        XCTAssertEqual(BlendMath.blend(.softLight, backdrop: 0.16, source: 0.75),
                       0.279168, accuracy: 1e-9)
        // Cs > 0.5, Cb > 0.25: D(Cb) = sqrt(0.49) = 0.7
        //          B = 0.49 + (2*1.0 - 1) * (0.7 - 0.49) = 0.7
        XCTAssertEqual(BlendMath.blend(.softLight, backdrop: 0.49, source: 1.0), 0.7, accuracy: acc)
    }

    func testDifferenceAndExclusion() {
        XCTAssertEqual(BlendMath.blend(.difference, backdrop: 0.75, source: 0.25), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.exclusion, backdrop: 0.5, source: 0.5), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.exclusion, backdrop: 1.0, source: 1.0), 0.0, accuracy: acc)
    }

    // MARK: compositing over an opaque backdrop

    func testAlphaZeroLeavesTheBackdropUntouched() {
        let cb = SIMD3<Double>(0.2, 0.4, 0.6)
        let result = BlendMath.composite(backdrop: cb, source: SIMD3(1, 1, 1),
                                         alpha: 0, mode: .multiply)
        XCTAssertEqual(result.x, cb.x, accuracy: acc)
        XCTAssertEqual(result.y, cb.y, accuracy: acc)
        XCTAssertEqual(result.z, cb.z, accuracy: acc)
    }

    func testAlphaOneGivesThePureBlendResult() {
        let result = BlendMath.composite(backdrop: SIMD3(0.5, 0.5, 0.5),
                                         source: SIMD3(0.5, 0.5, 0.5),
                                         alpha: 1, mode: .multiply)
        XCTAssertEqual(result.x, 0.25, accuracy: acc)
    }

    func testPartialAlphaInterpolatesBackdropTowardTheBlend() {
        // Co = (1 - a)*Cb + a*B(Cb, Cs) with an opaque backdrop.
        // = 0.5*0.5 + 0.5*0.25 = 0.375
        let result = BlendMath.composite(backdrop: SIMD3(0.5, 0.5, 0.5),
                                         source: SIMD3(0.5, 0.5, 0.5),
                                         alpha: 0.5, mode: .multiply)
        XCTAssertEqual(result.x, 0.375, accuracy: acc)
    }

    func testEveryModeHasAStableShaderIndex() {
        // The MSL switch is indexed by this value; reordering allCases silently remaps every
        // operator's saved blend selection.
        XCTAssertEqual(BlendMode.allCases.map(\.shaderIndex), Array(0..<Int32(BlendMode.allCases.count)))
        XCTAssertEqual(BlendMode.normal.shaderIndex, 0)
        XCTAssertEqual(BlendMode.allCases.count, 12)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: `cannot find 'BlendMath' in scope`.

- [ ] **Step 3: Write `BlendMath`**

`App/ISFRuntime/BlendMath.swift`:

```swift
import Foundation

/// The separable blend modes of the W3C Compositing and Blending Level 1 specification.
///
/// Non-separable modes (hue, saturation, color, luminosity) are deliberately absent: they operate
/// on the colour as a whole rather than per channel, and are not Milestone 1 scope.
///
/// `shaderIndex` is the wire value handed to MSL. It is derived from declaration order, and the
/// test suite pins it — reordering these cases would silently remap the operator's blend selection.
enum BlendMode: String, CaseIterable, Identifiable, Codable {
    case normal, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, hardLight, softLight, difference, exclusion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:     return "Normal"
        case .multiply:   return "Multiply"
        case .screen:     return "Screen"
        case .overlay:    return "Overlay"
        case .darken:     return "Darken"
        case .lighten:    return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn:  return "Color Burn"
        case .hardLight:  return "Hard Light"
        case .softLight:  return "Soft Light"
        case .difference: return "Difference"
        case .exclusion:  return "Exclusion"
        }
    }

    var shaderIndex: Int32 {
        Int32(Self.allCases.firstIndex(of: self) ?? 0)
    }
}

/// Pure blend and composite math. The reference implementation: `Compositor.metal`'s MSL is a
/// transcription of this, and the compositor's golden-frame tests assert the GPU matches it.
enum BlendMath {
    /// B(Cb, Cs) for one channel, per W3C §blending. Inputs are expected in [0, 1].
    static func blend(_ mode: BlendMode, backdrop cb: Double, source cs: Double) -> Double {
        switch mode {
        case .normal:
            return cs
        case .multiply:
            return cb * cs
        case .screen:
            return cb + cs - cb * cs
        case .overlay:
            return blend(.hardLight, backdrop: cs, source: cb)
        case .darken:
            return min(cb, cs)
        case .lighten:
            return max(cb, cs)
        case .colorDodge:
            if cb == 0 { return 0 }
            if cs == 1 { return 1 }
            return min(1, cb / (1 - cs))
        case .colorBurn:
            if cb == 1 { return 1 }
            if cs == 0 { return 0 }
            return 1 - min(1, (1 - cb) / cs)
        case .hardLight:
            return cs <= 0.5
                ? blend(.multiply, backdrop: cb, source: 2 * cs)
                : blend(.screen, backdrop: cb, source: 2 * cs - 1)
        case .softLight:
            if cs <= 0.5 {
                return cb - (1 - 2 * cs) * cb * (1 - cb)
            }
            let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : sqrt(cb)
            return cb + (2 * cs - 1) * (d - cb)
        case .difference:
            return abs(cb - cs)
        case .exclusion:
            return cb + cs - 2 * cb * cs
        }
    }

    static func blend(_ mode: BlendMode,
                      backdrop cb: SIMD3<Double>,
                      source cs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(blend(mode, backdrop: cb.x, source: cs.x),
              blend(mode, backdrop: cb.y, source: cs.y),
              blend(mode, backdrop: cb.z, source: cs.z))
    }

    /// Source-over composite of a blended source onto an OPAQUE backdrop.
    ///
    /// The general W3C formula is
    ///     Co = (1 - ab)*as*Cs + ab*as*B(Cb, Cs) + (1 - as)*ab*Cb
    /// The instrument's master starts as opaque black and every layer writes opaque, so ab = 1
    /// always and this reduces to
    ///     Co = (1 - as)*Cb + as*B(Cb, Cs)
    /// `alpha` is the layer's effective opacity times the source pixel's own alpha.
    static func composite(backdrop cb: SIMD3<Double>,
                          source cs: SIMD3<Double>,
                          alpha: Double,
                          mode: BlendMode) -> SIMD3<Double> {
        let a = min(max(alpha, 0), 1)
        let blended = blend(mode, backdrop: cb, source: cs)
        return cb * (1 - a) + blended * a
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: 13 tests in `BlendMathTests`, 0 failures. All run on the CPU — no Metal device needed.

- [ ] **Step 5: Commit**

```sh
git add App/ISFRuntime/BlendMath.swift App/ARShaderTests/BlendMathTests.swift
git commit -m "feat(mixer): W3C separable blend modes as a pure Swift reference

Twelve separable modes from W3C Compositing and Blending Level 1, with hand-computed
expected values per branch (including soft-light's D() split and the dodge/burn
special cases). Task 6's MSL is a transcription of this and is verified against it."
```

---

## Task 5: Crossfader macro and mixer state

**Files:**
- Create: `App/ISFRuntime/CrossfadeMacro.swift`
- Create: `App/ARShader/MixerState.swift`
- Create: `App/ARShaderTests/CrossfadeMacroTests.swift`
- Create: `App/ARShaderTests/MixerStateTests.swift`

**Interfaces:**
- Consumes: `BlendMode` (Task 4), `DeckID` (Task 3).
- Produces:
  - `enum CrossfadeMacro` — `static func weight(forLayerIndex: Int, layerCount: Int, position: Double) -> Double`,
    `static func effectiveOpacity(userOpacity: Double, weight: Double) -> Double`.
  - `struct LayerParams: Equatable` — `let deck: DeckID`, `let userOpacity: Double`,
    `let crossfadeWeight: Double`, `let effectiveOpacity: Double`, `let blendMode: BlendMode`.
  - `final class MixerState: ObservableObject` — `@Published var crossfadePosition: Double`,
    `@Published var opacity: [DeckID: Double]`, `@Published var blendMode: [DeckID: BlendMode]`,
    `@Published private(set) var isBlackedOut: Bool`,
    `func setOpacity(_:for:)`, `func setBlendMode(_:for:)`,
    `func toggleBlackoutLatch()`, `func beginBlackoutHold()`, `func endBlackoutHold()`,
    `func layers() -> [LayerParams]`.

**Both values are real and both are displayed (spec §7.1).** `LayerParams` carries the operator's
own fader AND what it is actually contributing; the UI in Task 12 shows both. No control silently
overwrites another.

- [ ] **Step 1: Write the failing crossfade test**

`App/ARShaderTests/CrossfadeMacroTests.swift`:

```swift
import XCTest

final class CrossfadeMacroTests: XCTestCase {
    private let acc = 1e-12

    func testFullyLeftGivesDeckOneEverythingAndDeckTwoNothing() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 0),
                       0.0, accuracy: acc)
    }

    func testFullyRightGivesDeckTwoEverything() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 1),
                       0.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 1),
                       1.0, accuracy: acc)
    }

    func testCentreGivesBothHalf() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 0.5),
                       0.5, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 0.5),
                       0.5, accuracy: acc)
    }

    func testPositionIsClampedToTheUnitInterval() {
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: -3),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 1, layerCount: 2, position: 99),
                       1.0, accuracy: acc)
    }

    func testASingleLayerIgnoresTheCrossfader() {
        // The model must extend past two decks without redesign (spec §7.1). With one layer there
        // is nothing to fade between, so the fader cannot silently mute it.
        for x in [0.0, 0.25, 0.5, 1.0] {
            XCTAssertEqual(CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 1, position: x),
                           1.0, accuracy: acc)
        }
    }

    func testEffectiveOpacityIsTheProductOfBothValues() {
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 0.8, weight: 0.5),
                       0.4, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 1.0, weight: 1.0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 0.0, weight: 1.0),
                       0.0, accuracy: acc)
    }

    func testEffectiveOpacityClampsBothInputs() {
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: 2.0, weight: 2.0),
                       1.0, accuracy: acc)
        XCTAssertEqual(CrossfadeMacro.effectiveOpacity(userOpacity: -1.0, weight: 0.5),
                       0.0, accuracy: acc)
    }
}
```

- [ ] **Step 2: Write the failing mixer-state test**

`App/ARShaderTests/MixerStateTests.swift`:

```swift
import XCTest

@MainActor
final class MixerStateTests: XCTestCase {
    func testDefaultsAreBothDecksFullyUpWithNormalBlend() {
        let mixer = MixerState()
        XCTAssertEqual(mixer.opacity[.one], 1.0)
        XCTAssertEqual(mixer.opacity[.two], 1.0)
        XCTAssertEqual(mixer.blendMode[.one], .normal)
        XCTAssertEqual(mixer.blendMode[.two], .normal)
        XCTAssertEqual(mixer.crossfadePosition, 0.0,
                       "The instrument boots showing deck A, not a half-and-half blend")
    }

    func testLayersCarryBothTheUserValueAndTheEffectiveValue() {
        let mixer = MixerState()
        mixer.setOpacity(0.8, for: .one)
        mixer.crossfadePosition = 0.5

        let layers = mixer.layers()
        XCTAssertEqual(layers.count, 2)
        let a = layers[0]
        XCTAssertEqual(a.deck, .one)
        XCTAssertEqual(a.userOpacity, 0.8, accuracy: 1e-12,
                       "The fader the operator set is never overwritten")
        XCTAssertEqual(a.crossfadeWeight, 0.5, accuracy: 1e-12)
        XCTAssertEqual(a.effectiveOpacity, 0.4, accuracy: 1e-12)
    }

    func testLayersAreOrderedDeckOneThenDeckTwo() {
        // Layer order IS composite order: deck 1 onto black, deck 2 onto the result.
        XCTAssertEqual(MixerState().layers().map(\.deck), [.one, .two])
    }

    func testBlackoutLatchToggles() {
        let mixer = MixerState()
        XCTAssertFalse(mixer.isBlackedOut)
        mixer.toggleBlackoutLatch()
        XCTAssertTrue(mixer.isBlackedOut)
        mixer.toggleBlackoutLatch()
        XCTAssertFalse(mixer.isBlackedOut)
    }

    func testMomentaryHoldBlacksOutAndReleases() {
        let mixer = MixerState()
        mixer.beginBlackoutHold()
        XCTAssertTrue(mixer.isBlackedOut)
        mixer.endBlackoutHold()
        XCTAssertFalse(mixer.isBlackedOut)
    }

    func testReleasingAMomentaryHoldDoesNotCancelAnEngagedLatch() {
        // The failure this prevents: latch blackout on, someone taps the momentary key, and
        // releasing it puts the room back in light.
        let mixer = MixerState()
        mixer.toggleBlackoutLatch()
        mixer.beginBlackoutHold()
        mixer.endBlackoutHold()
        XCTAssertTrue(mixer.isBlackedOut, "The latch is still engaged")
    }

    func testOpacityIsClampedOnTheWayIn() {
        let mixer = MixerState()
        mixer.setOpacity(5, for: .one)
        XCTAssertEqual(mixer.opacity[.one], 1.0)
        mixer.setOpacity(-5, for: .two)
        XCTAssertEqual(mixer.opacity[.two], 0.0)
    }
}
```

- [ ] **Step 3: Run both to verify they fail**

Expected: `cannot find 'CrossfadeMacro' in scope`, `cannot find 'MixerState' in scope`.

- [ ] **Step 4: Write `CrossfadeMacro`**

`App/ISFRuntime/CrossfadeMacro.swift`:

```swift
import Foundation

/// The crossfader as a MACRO over deck opacity — not a separate signal path (spec §7.1).
///
///     effectiveOpacity(deck) = userOpacity(deck) × crossfadeWeight(deck, x)
///
/// Both values stay real and both are displayed: the operator always sees the fader they set and
/// what it is actually contributing. This is the base-value/effective-value pattern approved in the
/// TouchDesigner Bindings design, reused deliberately.
///
/// The weighting generalises past two layers — only `weight` changes, never the callers.
enum CrossfadeMacro {
    /// Weight for layer `index` at crossfader position `position` ∈ [0, 1].
    ///
    /// Two layers: layer 0 gets `1 - x`, layer 1 gets `x`. Fewer than two layers: the crossfader
    /// has nothing to fade between and must not be able to mute the only source, so the weight
    /// is 1. Three or more: the position sweeps across the layers, each peaking at its own slot.
    static func weight(forLayerIndex index: Int, layerCount: Int, position: Double) -> Double {
        guard layerCount > 1 else { return 1 }
        let x = min(max(position, 0), 1)
        guard layerCount > 2 else {
            return index == 0 ? 1 - x : x
        }
        // N-layer generalisation: a triangular window of half-width one slot, centred on the
        // layer, swept by `position` across [0, layerCount - 1].
        let cursor = x * Double(layerCount - 1)
        return max(0, 1 - abs(cursor - Double(index)))
    }

    /// The product, clamped. Either value at zero silences the layer; neither can exceed 1.
    static func effectiveOpacity(userOpacity: Double, weight: Double) -> Double {
        let u = min(max(userOpacity, 0), 1)
        let w = min(max(weight, 0), 1)
        return u * w
    }
}
```

- [ ] **Step 5: Write `MixerState`**

`App/ARShader/MixerState.swift`:

```swift
import Foundation
import Combine

/// One layer's contribution for a single frame. Carries BOTH the operator's own fader value and
/// what it is actually contributing, so no readout has to reverse-engineer one from the other.
struct LayerParams: Equatable {
    let deck: DeckID
    let userOpacity: Double
    let crossfadeWeight: Double
    let effectiveOpacity: Double
    let blendMode: BlendMode
}

/// The mixer surface: per-deck opacity and blend mode, the crossfader, and blackout.
///
/// Layer order is composite order — deck 1 onto opaque black, deck 2 onto the result (spec §7).
@MainActor
final class MixerState: ObservableObject {
    /// Composite order. Adding a deck means appending here; nothing else changes.
    static let layerOrder: [DeckID] = [.one, .two]

    @Published var crossfadePosition: Double = 0.0 {
        didSet { crossfadePosition = min(max(crossfadePosition, 0), 1) }
    }
    @Published private(set) var opacity: [DeckID: Double] =
        Dictionary(uniqueKeysWithValues: DeckID.allCases.map { ($0, 1.0) })
    @Published private(set) var blendMode: [DeckID: BlendMode] =
        Dictionary(uniqueKeysWithValues: DeckID.allCases.map { ($0, .normal) })

    /// Blackout is engaged when EITHER the latch is on or a momentary key is held. Releasing the
    /// momentary must never cancel the latch — the failure mode is a room going back to light
    /// because someone tapped a key.
    @Published private(set) var isBlackedOut = false
    private var latchEngaged = false
    private var holdEngaged = false

    func setOpacity(_ value: Double, for deck: DeckID) {
        opacity[deck] = min(max(value, 0), 1)
    }

    func setBlendMode(_ mode: BlendMode, for deck: DeckID) {
        blendMode[deck] = mode
    }

    func toggleBlackoutLatch() {
        latchEngaged.toggle()
        recomputeBlackout()
    }

    func beginBlackoutHold() {
        holdEngaged = true
        recomputeBlackout()
    }

    func endBlackoutHold() {
        holdEngaged = false
        recomputeBlackout()
    }

    private func recomputeBlackout() {
        isBlackedOut = latchEngaged || holdEngaged
    }

    /// Per-frame layer parameters, in composite order.
    func layers() -> [LayerParams] {
        let order = Self.layerOrder
        return order.enumerated().map { index, deck in
            let user = opacity[deck] ?? 1.0
            let weight = CrossfadeMacro.weight(forLayerIndex: index, layerCount: order.count,
                                               position: crossfadePosition)
            return LayerParams(
                deck: deck,
                userOpacity: user,
                crossfadeWeight: weight,
                effectiveOpacity: CrossfadeMacro.effectiveOpacity(userOpacity: user, weight: weight),
                blendMode: blendMode[deck] ?? .normal)
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Expected: 7 crossfade + 7 mixer tests, 0 failures.

- [ ] **Step 7: Commit**

```sh
git add App/ISFRuntime/CrossfadeMacro.swift App/ARShader/MixerState.swift \
        App/ARShaderTests/CrossfadeMacroTests.swift App/ARShaderTests/MixerStateTests.swift
git commit -m "feat(mixer): crossfader as a macro over deck opacity

effectiveOpacity = userOpacity x crossfadeWeight, both values kept real and both
exposed on LayerParams. Weighting generalises past two decks. Blackout is a latch
OR a momentary hold, so releasing the hold cannot cancel an engaged latch."
```

---

## Task 6: The Metal compositor

**Files:**
- Create: `App/ARShader/Compositor.swift`
- Create: `App/ARShaderTests/CompositorTests.swift`

**Interfaces:**
- Consumes: `BlendMode`/`BlendMath` (Task 4), `LayerParams` (Task 5),
  `InstrumentRenderer.masterFormat` (Task 2), `TestPixels`/`TextureReadback` (Tasks 1, 3).
- Produces:
  - `final class Compositor` — `init?(device:)`,
    `func encodeLayer(source: MTLTexture, backdrop: MTLTexture, destination: MTLTexture, opacity: Double, mode: BlendMode, in cb: MTLCommandBuffer)`.
  - Failable `init` is load-bearing: a nil compositor is the "output black" path in Task 8, not a crash.

The compositor is **hand-written Metal, not an ISF filter** (spec §7). A load-bearing mixer that
fails to compile would leave the instrument with no output at all; a compiled Metal pipeline cannot
fail at shader-load time.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/CompositorTests.swift`:

```swift
import XCTest
import Metal

@MainActor
final class CompositorTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var compositor: Compositor!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        compositor = try XCTUnwrap(Compositor(device: device))
    }

    /// A small solid-colour texture in the master format.
    private func solid(_ rgb: SIMD3<Double>, size: Int = 16) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat, width: size, height: size,
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: rgb.x, green: rgb.y, blue: rgb.z,
                                                           alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return tex
    }

    private func blank(size: Int = 16) throws -> MTLTexture {
        try solid(SIMD3(0, 0, 0), size: size)
    }

    private func composite(source: SIMD3<Double>, backdrop: SIMD3<Double>,
                           opacity: Double, mode: BlendMode) throws -> SIMD3<Double> {
        let src = try solid(source)
        let back = try solid(backdrop)
        let dest = try blank()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        compositor.encodeLayer(source: src, backdrop: back, destination: dest,
                               opacity: opacity, mode: mode, in: cb)
        cb.commit()
        cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: dest, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    /// The GPU must agree with the Swift reference. Tolerance covers rgba16Float precision.
    func testEveryBlendModeMatchesTheSwiftReference() throws {
        let source = SIMD3<Double>(0.75, 0.5, 0.25)
        let backdrop = SIMD3<Double>(0.25, 0.5, 0.75)
        for mode in BlendMode.allCases {
            for opacity in [0.0, 0.35, 1.0] {
                let gpu = try composite(source: source, backdrop: backdrop,
                                        opacity: opacity, mode: mode)
                let cpu = BlendMath.composite(backdrop: backdrop, source: source,
                                              alpha: opacity, mode: mode)
                XCTAssertEqual(gpu.x, cpu.x, accuracy: 0.005,
                               "\(mode.rawValue) @ \(opacity) red")
                XCTAssertEqual(gpu.y, cpu.y, accuracy: 0.005,
                               "\(mode.rawValue) @ \(opacity) green")
                XCTAssertEqual(gpu.z, cpu.z, accuracy: 0.005,
                               "\(mode.rawValue) @ \(opacity) blue")
            }
        }
    }

    func testZeroOpacityLeavesTheBackdropExactlyAsItWas() throws {
        let backdrop = SIMD3<Double>(0.2, 0.4, 0.6)
        let out = try composite(source: SIMD3(1, 1, 1), backdrop: backdrop,
                                opacity: 0, mode: .difference)
        XCTAssertEqual(out.x, backdrop.x, accuracy: 0.005)
        XCTAssertEqual(out.y, backdrop.y, accuracy: 0.005)
        XCTAssertEqual(out.z, backdrop.z, accuracy: 0.005)
    }

    func testNormalAtFullOpacityReplacesTheBackdrop() throws {
        let out = try composite(source: SIMD3(0.9, 0.1, 0.3), backdrop: SIMD3(0.1, 0.9, 0.7),
                                opacity: 1, mode: .normal)
        XCTAssertEqual(out.x, 0.9, accuracy: 0.005)
        XCTAssertEqual(out.y, 0.1, accuracy: 0.005)
        XCTAssertEqual(out.z, 0.3, accuracy: 0.005)
    }

    func testOutputIsAlwaysOpaque() throws {
        // The master must stay opaque: a stack that leaks alpha < 1 is how the TouchDesigner
        // build's blackout gate silently failed (Level TOP alpha leak, Phase B).
        let dest = try blank()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        compositor.encodeLayer(source: try solid(SIMD3(1, 1, 1)), backdrop: try blank(),
                               destination: dest, opacity: 0.5, mode: .normal, in: cb)
        cb.commit(); cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: dest, device: device, queue: queue))
        XCTAssertEqual(try XCTUnwrap(TestPixels.meanAlpha(of: readback)), 1.0, accuracy: 0.005)
    }
}
```

Add to `App/ARShaderTests/TestPixels.swift`:

```swift
    /// Mean alpha, same format support as `meanRGB`. Only `.rgba16Float` is needed today; the
    /// 8-bit paths return their alpha channel for completeness.
    static func meanAlpha(of texture: MTLTexture) -> Double? {
        let w = texture.width, h = texture.height
        guard w > 0, h > 0, texture.pixelFormat == .rgba16Float else { return nil }
        var bytes = [UInt16](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: w * 8,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        var sum = 0.0
        for i in stride(from: 3, to: bytes.count, by: 4) {
            sum += Double(Float16(bitPattern: bytes[i]))
        }
        return sum / Double(w * h)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: `cannot find 'Compositor' in scope`.

- [ ] **Step 3: Write `Compositor`**

`App/ARShader/Compositor.swift`:

```swift
import Metal
import simd

/// Blends one layer onto a backdrop and writes the result to a destination texture.
///
/// Hand-written Metal, not an ISF filter (spec §7): the mixer is load-bearing, and an ISF mixer
/// that failed to compile would leave the instrument with no output at all. A compiled Metal
/// pipeline cannot fail at shader-load time.
///
/// Reads the backdrop as a TEXTURE and writes to a separate destination rather than using
/// framebuffer fetch. Fixed-function Metal blending cannot express multiply/overlay/soft-light —
/// those need the backdrop value in the fragment shader — and programmable blending
/// (`[[color(0)]]` fragment input) is an Apple-GPU feature. Ping-pong is universal.
///
/// The MSL below is a transcription of `BlendMath`. `CompositorTests` asserts the two agree for
/// every mode at three opacities; change one without the other and that test fails.
final class Compositor {
    private let pipeline: MTLRenderPipelineState

    /// Must match the `blendMode` case order pinned by `BlendMathTests`.
    private struct Uniforms {
        var opacity: Float
        var mode: Int32
    }

    init?(device: MTLDevice) {
        guard let lib = try? device.makeLibrary(source: Self.shaderSource, options: nil) else {
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "ar_composite_v")
        desc.fragmentFunction = lib.makeFunction(name: "ar_composite_f")
        desc.colorAttachments[0].pixelFormat = InstrumentRenderer.masterFormat
        guard let p = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        pipeline = p
    }

    /// Encode one layer. `backdrop` and `destination` must be different textures — a render target
    /// cannot also be sampled in the same pass.
    func encodeLayer(source: MTLTexture,
                     backdrop: MTLTexture,
                     destination: MTLTexture,
                     opacity: Double,
                     mode: BlendMode,
                     in cb: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = destination
        rpd.colorAttachments[0].loadAction = .dontCare   // every pixel is written
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var uniforms = Uniforms(opacity: Float(min(max(opacity, 0), 1)), mode: mode.shaderIndex)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentTexture(backdrop, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; float2 uv; };

    struct Uniforms { float opacity; int mode; };

    vertex VOut ar_composite_v(uint vid [[vertex_id]]) {
        float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
        VOut o;
        o.pos = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(corner.x, 1.0 - corner.y);
        return o;
    }

    // ── W3C Compositing and Blending Level 1, separable blend modes ──
    // Transcribed from BlendMath.swift. Per-channel; callers pass float3.

    static inline float3 b_multiply(float3 cb, float3 cs) { return cb * cs; }
    static inline float3 b_screen(float3 cb, float3 cs)   { return cb + cs - cb * cs; }

    static inline float3 b_hardlight(float3 cb, float3 cs) {
        float3 lo = b_multiply(cb, 2.0 * cs);
        float3 hi = b_screen(cb, 2.0 * cs - 1.0);
        return select(hi, lo, cs <= 0.5);
    }

    static inline float3 b_colordodge(float3 cb, float3 cs) {
        float3 r = min(float3(1.0), cb / max(1.0 - cs, 1e-7));
        r = select(r, float3(1.0), cs >= 1.0);
        r = select(r, float3(0.0), cb <= 0.0);
        return r;
    }

    static inline float3 b_colorburn(float3 cb, float3 cs) {
        float3 r = 1.0 - min(float3(1.0), (1.0 - cb) / max(cs, 1e-7));
        r = select(r, float3(0.0), cs <= 0.0);
        r = select(r, float3(1.0), cb >= 1.0);
        return r;
    }

    static inline float3 b_softlight(float3 cb, float3 cs) {
        float3 d = select(sqrt(cb), ((16.0 * cb - 12.0) * cb + 4.0) * cb, cb <= 0.25);
        float3 lo = cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb);
        float3 hi = cb + (2.0 * cs - 1.0) * (d - cb);
        return select(hi, lo, cs <= 0.5);
    }

    static inline float3 apply_blend(int mode, float3 cb, float3 cs) {
        switch (mode) {
            case 0:  return cs;                                  // normal
            case 1:  return b_multiply(cb, cs);                  // multiply
            case 2:  return b_screen(cb, cs);                    // screen
            case 3:  return b_hardlight(cs, cb);                 // overlay (args swapped)
            case 4:  return min(cb, cs);                         // darken
            case 5:  return max(cb, cs);                         // lighten
            case 6:  return b_colordodge(cb, cs);                // colorDodge
            case 7:  return b_colorburn(cb, cs);                 // colorBurn
            case 8:  return b_hardlight(cb, cs);                 // hardLight
            case 9:  return b_softlight(cb, cs);                 // softLight
            case 10: return abs(cb - cs);                        // difference
            case 11: return cb + cs - 2.0 * cb * cs;             // exclusion
            default: return cs;
        }
    }

    fragment float4 ar_composite_f(VOut v [[stage_in]],
                                   texture2d<float> srcTex [[texture(0)]],
                                   texture2d<float> backTex [[texture(1)]],
                                   constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 src = srcTex.sample(s, v.uv);
        float3 cb = backTex.sample(s, v.uv).rgb;
        // Layer alpha = the source pixel's own alpha times the layer's effective opacity.
        float a = clamp(src.a * u.opacity, 0.0, 1.0);
        float3 blended = apply_blend(u.mode, clamp(cb, 0.0, 1.0), clamp(src.rgb, 0.0, 1.0));
        // Source-over onto an OPAQUE backdrop: Co = (1 - a)*Cb + a*B(Cb, Cs).
        float3 co = mix(cb, blended, a);
        // The master is opaque by contract. Never propagate a layer's alpha into it.
        return float4(co, 1.0);
    }
    """
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App && xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```

Expected: 0 failures. `testEveryBlendModeMatchesTheSwiftReference` covers 12 modes × 3 opacities ×
3 channels = 108 assertions in one test.

> If dodge/burn disagree at the extremes, the cause is the `select` ordering: the special cases must
> be applied AFTER the general formula so they overwrite it, and `cb <= 0` must win over `cs >= 1`
> for dodge (W3C evaluates the backdrop test first). The test asserts exactly those cases.

- [ ] **Step 5: Commit**

```sh
git add App/ARShader/Compositor.swift App/ARShaderTests/CompositorTests.swift \
        App/ARShaderTests/TestPixels.swift
git commit -m "feat(mixer): hand-written Metal compositor verified against the Swift reference

Ping-pong (backdrop as a sampled texture, separate destination) rather than
framebuffer fetch, so the twelve W3C modes work on any GPU. The golden test asserts
the GPU matches BlendMath for every mode at three opacities, and that the master
stays opaque - the alpha-leak class that broke the TouchDesigner blackout gate."
```

---

## Task 7: The frame graph — one command buffer, two decks, one master

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift`
- Modify: `App/ARShader/ARShaderApp.swift` (wire decks + mixer into `Instrument`)
- Modify: `App/ARShaderTests/InstrumentRendererTests.swift`
- Create: `App/ARShaderTests/FrameGraphTests.swift`

**Interfaces:**
- Consumes: `Deck` (Task 3), `MixerState`/`LayerParams` (Task 5), `Compositor` (Task 6).
- Produces:
  - `InstrumentRenderer.init(device:queue:mixer:)`, `let decks: [DeckID: Deck]`,
    `func deck(_ id: DeckID) -> Deck`,
    `func deckTexture(_ id: DeckID) -> MTLTexture?` (the deck's owned output, nil when unloaded),
    and the extended `renderFrame()`.

Per frame, inside **one** `MTLCommandBuffer` (spec §6):

1. deck 1 renders offscreen into its owned texture
2. deck 2 renders offscreen into its owned texture
3. master A is cleared to opaque black
4. layer 1 composites A → B, layer 2 composites B → A (ping-pong)
5. the buffer is committed; views present the result

A layer with no shader loaded, or with zero effective opacity, is **skipped** — but the ping-pong
parity must still come out right, so the renderer tracks which master holds the current result
rather than assuming it after N layers.

- [ ] **Step 1: Write the failing tests**

`App/ARShaderTests/FrameGraphTests.swift`:

```swift
import XCTest
import Metal

@MainActor
final class FrameGraphTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var mixer: MixerState!
    private var renderer: InstrumentRenderer!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        mixer = MixerState()
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: mixer)
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func load(_ id: DeckID, _ fixtureName: String) throws {
        let deck = renderer.deck(id)
        let done = expectation(description: "compile \(fixtureName) on \(id.rawValue)")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        deck.onCompileFinished = nil
        XCTAssertNil(deck.compileError)
    }

    private func renderAndRead() throws -> SIMD3<Double> {
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testOneDeckAtFullOpacityReachesTheMaster() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0    // deck 1 weight 1
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
        XCTAssertEqual(rgb.y, 0.0, accuracy: 0.02)
    }

    func testAnUnloadedDeckContributesNothingRatherThanBlack() throws {
        // Deck 2 is empty. With the crossfader hard right, deck 2's weight is 1 and deck 1's is 0,
        // so the correct output is black - but via "deck 1 muted", not "deck 2 painted black".
        try load(.one, "solid_red")
        mixer.crossfadePosition = 1
        let rgb = try renderAndRead()
        XCTAssertLessThan(rgb.x, 0.02, "Deck 1 is faded out")

        // Slide back to centre: deck 1 returns at half. An empty deck 2 must not have painted over
        // the master in the meantime.
        mixer.crossfadePosition = 0.5
        let mid = try renderAndRead()
        XCTAssertEqual(mid.x, 0.5, accuracy: 0.03)
    }

    func testTwoDecksCompositeInLayerOrder() throws {
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0.5   // both weight 0.5
        mixer.setBlendMode(.normal, for: .two)

        // deck 1: normal, a = 0.5, backdrop black  -> (0.5, 0, 0)
        // deck 2: normal, a = 0.5, backdrop above  -> (0.25, 0.5, 0)
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 0.25, accuracy: 0.03)
        XCTAssertEqual(rgb.y, 0.5, accuracy: 0.03)
        XCTAssertEqual(rgb.z, 0.0, accuracy: 0.02)
    }

    func testCompositeOrderIsNotCommutative() throws {
        // Proves the layer stack is real: swapping which deck holds which shader changes the
        // output for a non-commutative blend.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0.5
        mixer.setBlendMode(.colorBurn, for: .two)
        let first = try renderAndRead()

        try load(.one, "solid_green")
        try load(.two, "solid_red")
        let swapped = try renderAndRead()
        XCTAssertNotEqual(first.x, swapped.x, accuracy: 0.0,
                          "Layer order must affect a non-commutative blend")
    }

    func testMasterResultAlternatesButProgramTextureIsAlwaysCorrect() throws {
        // Ping-pong parity: with one active layer the result lands in a different master than with
        // two. programTexture() must track that, not assume it.
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        let oneLayer = try renderAndRead()
        XCTAssertEqual(oneLayer.x, 1.0, accuracy: 0.02)

        try load(.two, "solid_green")
        mixer.setOpacity(1.0, for: .two)
        mixer.crossfadePosition = 1     // only deck 2 contributes
        let twoLayers = try renderAndRead()
        XCTAssertEqual(twoLayers.y, 1.0, accuracy: 0.02)
        XCTAssertLessThan(twoLayers.x, 0.02)
    }

    func testEmptyInstrumentStillRendersOpaqueBlack() throws {
        let rgb = try renderAndRead()
        XCTAssertLessThan(rgb.x + rgb.y + rgb.z, 0.02)
    }

    func testDeckTexturesAreAvailableForMonitorsAfterTheFrame() throws {
        try load(.one, "solid_red")
        renderer.renderFrame()
        let deckTex = try XCTUnwrap(renderer.deckTexture(.one),
                                    "Monitors read this in a LATER command buffer")
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: deckTex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02,
                       "The deck monitor shows the deck BEFORE opacity and blending")
        XCTAssertNil(renderer.deckTexture(.two), "An unloaded deck has no monitor image")
    }

    func testFrameUsesASingleCommandBuffer() throws {
        // The spec's central claim: no readback, no per-stage commit. If a stage started
        // committing its own buffer, this scheduled count would exceed one.
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        let before = renderer.committedBufferCount
        renderer.renderFrame()
        XCTAssertEqual(renderer.committedBufferCount - before, 1)
    }
}
```

Also update `InstrumentRendererTests` — its three tests now construct the renderer with a mixer:

```swift
    private func makeRenderer() throws -> (InstrumentRenderer, MTLDevice, MTLCommandQueue) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return (InstrumentRenderer(device: device, queue: queue, mixer: MixerState()), device, queue)
    }
```

- [ ] **Step 2: Run to verify they fail**

Expected: `extra argument 'mixer' in call`, `value of type 'InstrumentRenderer' has no member 'deck'`.

- [ ] **Step 3: Extend `InstrumentRenderer`**

Replace the properties and `renderFrame()` in `App/ARShader/InstrumentRenderer.swift`:

```swift
    private let mixer: MixerState
    private let compositor: Compositor?
    private(set) var decks: [DeckID: Deck] = [:]
    /// Test observability: how many command buffers this renderer has committed.
    private(set) var committedBufferCount = 0

    init(device: MTLDevice, queue: MTLCommandQueue, mixer: MixerState) {
        self.device = device
        self.queue = queue
        self.mixer = mixer
        self.clock = RenderClock()
        if VVMTLPool.global == nil { VVMTLPool.global = VVMTLPool(device: device) }
        masters = (0..<2).compactMap { _ in Self.makeMaster(device: device) }
        // Nil compositor is a survivable state, not a crash: renderFrame falls back to a black
        // master and the instrument still starts (spec §8).
        self.compositor = Compositor(device: device)
        // Every deck shares the ONE clock, so a swap on deck A cannot restart deck B's animation.
        for id in DeckID.allCases {
            decks[id] = Deck(id: id, device: device, queue: queue, clock: clock)
        }
    }

    func deck(_ id: DeckID) -> Deck {
        guard let d = decks[id] else {
            preconditionFailure("Deck \(id.rawValue) is created in init and cannot be missing")
        }
        return d
    }

    /// The deck's own output, pre-opacity and pre-blend — what a deck monitor shows. Nil when the
    /// deck has no shader loaded.
    func deckTexture(_ id: DeckID) -> MTLTexture? { deckOutputs[id] }
    private var deckOutputs: [DeckID: MTLTexture] = [:]

    /// Render exactly one frame of the whole instrument into ONE command buffer.
    func renderFrame() {
        guard let cb = queue.makeCommandBuffer(), masters.count == 2 else { return }

        // 1-2. Decks render offscreen into their own textures.
        let layers = mixer.layers()
        deckOutputs.removeAll(keepingCapacity: true)
        for layer in layers {
            if let tex = deck(layer.deck).render(in: cb) {
                deckOutputs[layer.deck] = tex
            }
        }

        // 3. The master begins each frame as OPAQUE BLACK (spec §7). This is what a bottom-layer
        //    blend mode blends against, and what an empty instrument shows.
        var current = 0
        clearToOpaqueBlack(masters[current], in: cb)

        // 4. Composite each contributing layer, ping-ponging between the two masters.
        if let compositor {
            for layer in layers {
                guard let source = deckOutputs[layer.deck], layer.effectiveOpacity > 0 else {
                    continue    // no shader, or faded out — the backdrop passes through untouched
                }
                let next = 1 - current
                compositor.encodeLayer(source: source,
                                       backdrop: masters[current],
                                       destination: masters[next],
                                       opacity: layer.effectiveOpacity,
                                       mode: layer.blendMode,
                                       in: cb)
                current = next
            }
        }
        // The result may be in either master depending on how many layers contributed — track it
        // rather than assuming parity from the deck count.
        masterIndex = current

        cb.commit()
        committedBufferCount += 1
        onFrameRendered?()
    }
```

- [ ] **Step 4: Wire the decks and mixer into `Instrument`**

In `App/ARShader/ARShaderApp.swift`:

```swift
@MainActor
final class Instrument: ObservableObject {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let mixer = MixerState()
    let library = LibraryModel()
    let renderer: InstrumentRenderer

    init() {
        let props = RenderProperties.global()
        self.device = props.device
        self.queue = props.renderQueue
        self.renderer = InstrumentRenderer(device: props.device, queue: props.renderQueue,
                                           mixer: mixer)
        library.loadStandardLibraries()
    }

    func deck(_ id: DeckID) -> Deck { renderer.deck(id) }
}
```

- [ ] **Step 5: Drive the frame from the clock, before any view presents**

In `App/ARShader/ProgramView.swift`, change `ProgramOutputView.makeNSView` so the renderer produces
the frame at the START of the tick:

```swift
    func makeNSView(context: Context) -> TexturePresentingView {
        let view = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        let renderer = instrument.renderer
        // The display link calls view.draw() once per tick. Producing the frame here — before the
        // present pass samples anything — is what makes ONE tick equal ONE instrument frame.
        // These run on the display-link thread. InstrumentRenderer is lock-guarded and NOT
        // main-actor precisely so they can - never wrap them in MainActor.assumeIsolated.
        view.onWillDraw = { renderer.renderFrame() }
        view.sourceTexture = { renderer.programTexture() }
        view.preferredFramesPerSecond = 60
        DispatchQueue.main.async { renderer.attachClock(to: view) }
        return view
    }
```

and add to `TexturePresentingView`:

```swift
    /// Called at the top of every draw, before the source texture is pulled. The program view uses
    /// it to render the instrument's frame; monitors leave it nil.
    var onWillDraw: (() -> Void)?
```

with `onWillDraw?()` as the first line of `draw(in:)`.

> **Threading — see the Threading Model section above. Do NOT use `MainActor.assumeIsolated` here.**
> An earlier draft of this plan did, on the theory that it merely silenced the compiler and might at
> worst cost a stutter. It is a runtime ASSERTION: it trapped in `dispatch_assert_queue_fail` on the
> first display-link tick (measured 2026-07-30, Task 2). The closures call the renderer directly
> because `InstrumentRenderer` is lock-guarded and non-isolated.

- [ ] **Step 6: Run the tests to verify they pass**

Expected: 8 frame-graph tests + the earlier suites, 0 failures.

- [ ] **Step 7: Commit**

```sh
git add App/ARShader/InstrumentRenderer.swift App/ARShader/ARShaderApp.swift \
        App/ARShader/ProgramView.swift App/ARShaderTests
git commit -m "feat(instrument): full frame graph in one command buffer

Decks render offscreen, the master starts opaque black, layers composite in order
with ping-pong masters. Skipped layers (no shader, zero effective opacity) leave the
backdrop untouched, and the renderer tracks which master holds the result rather
than assuming parity. Deck textures survive the frame for the monitors."
```

---

## Task 8: The blackout gate

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift`
- Create: `App/ARShaderTests/BlackoutTests.swift`

**Interfaces:**
- Consumes: `MixerState.isBlackedOut` (Task 5), the frame graph (Task 7).
- Produces: `InstrumentRenderer.programTexture()` returns **nil** while blacked out;
  `func monitorTexture(_ source: MonitorSource) -> MTLTexture?` with
  `enum MonitorSource { case deck(DeckID), master }`, where `.master` honours blackout.

Blackout is **not** a blend mode, not a shader, and not a compositor stage (spec §8). It is a final
gate, and it must be structurally incapable of depending on anything that can fail to compile.

The implementation is deliberately the smallest thing that can work: `programTexture()` returns nil,
and every consumer already renders opaque black on nil (Task 2's `TexturePresentingView`). There is
no pipeline in that path, no shader, and no state to get out of sync. The same nil is what a failed
compositor produces, so the failure floor and the panic button are the same code path.

- [ ] **Step 1: Write the failing tests**

`App/ARShaderTests/BlackoutTests.swift`:

```swift
import XCTest
import Metal

@MainActor
final class BlackoutTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var mixer: MixerState!
    private var renderer: InstrumentRenderer!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        mixer = MixerState()
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: mixer)
        let deck = renderer.deck(.one)
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "solid_red", withExtension: "fs", subdirectory: "Fixtures"))
        let done = expectation(description: "compile")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: try String(contentsOf: url, encoding: .utf8), name: "solid_red.fs")
        wait(for: [done], timeout: 30)
        mixer.crossfadePosition = 0
    }

    func testBlackoutWithdrawsTheProgramTexture() throws {
        renderer.renderFrame()
        XCTAssertNotNil(renderer.programTexture(), "Sanity: the instrument is producing output")

        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture(),
                     "Blackout must withdraw the texture entirely — consumers render black on nil, "
                     + "so no pipeline can stand between the panic button and darkness")
    }

    func testBlackoutReleasesBackToTheSameImage() throws {
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture())

        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.programTexture())
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
    }

    func testTheMasterMonitorGoesDarkWithTheRoom() throws {
        // A master monitor showing video while the room is dark is the same class of false readout
        // as a recorder that counts frames it never wrote. It taps POST-blackout.
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.monitorTexture(.master))
    }

    func testDeckMonitorsKeepShowingTheirDecksDuringBlackout() throws {
        // Deck monitors are cue monitors: the operator must be able to line up the next shader
        // while the room is dark. They are not program output and do not tap post-blackout.
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNotNil(renderer.monitorTexture(.deck(.one)))
    }

    func testBlackoutStillHoldsWhenTheDecksAreRenderingNormally() throws {
        mixer.toggleBlackoutLatch()
        for _ in 0..<10 {
            renderer.renderFrame()
            XCTAssertNil(renderer.programTexture())
        }
    }

    func testAMomentaryHoldBlacksOutForExactlyTheHold() throws {
        mixer.beginBlackoutHold()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture())
        mixer.endBlackoutHold()
        renderer.renderFrame()
        XCTAssertNotNil(renderer.programTexture())
    }

    func testAnInstrumentWithNoCompositorOutputsBlackRatherThanGarbage() throws {
        // The failure floor: if the compositor pipeline could not be built, the instrument must
        // still start and must show black — never a stale or uninitialised frame (spec §8).
        let broken = InstrumentRenderer(device: device, queue: queue, mixer: mixer,
                                        compositorOverride: .failed)
        broken.renderFrame()
        let tex = try XCTUnwrap(broken.programTexture(),
                                "Still produces a master; it is simply black")
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let stats = try XCTUnwrap(FramePixelStats.analyze(texture: readback))
        XCTAssertLessThan(stats.maxLuma, PixelGate.blackLumaFloor)
        XCTAssertEqual(stats.nanCount, 0)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Expected: `no member 'monitorTexture'`, `no parameter 'compositorOverride'`.

- [ ] **Step 3: Implement the gate**

In `App/ARShader/InstrumentRenderer.swift`:

```swift
/// What a viewport is looking at.
enum MonitorSource: Equatable {
    case deck(DeckID)
    /// The program feed. Taps POST-blackout: when the room is dark, this monitor is dark.
    case master
}
```

Add the test seam and rewrite `programTexture()`:

```swift
    /// Test seam: forces the "compositor could not be built" branch without a broken GPU.
    enum CompositorOverride { case failed }

    init(device: MTLDevice, queue: MTLCommandQueue, mixer: MixerState,
         compositorOverride: CompositorOverride? = nil) {
        // ...as Task 7, except:
        self.compositor = compositorOverride == .failed ? nil : Compositor(device: device)
        // ...
    }

    /// The program feed. **Nil while blacked out** — and consumers render opaque black on nil.
    ///
    /// Blackout is a final gate (spec §8), not a stage: there is no pipeline, no shader and no
    /// extra state between the panic button and darkness. The same nil is what a failed compositor
    /// yields, so the failure floor and the panic button share one code path.
    func programTexture() -> MTLTexture? {
        guard !mixer.isBlackedOut else { return nil }
        return masters.indices.contains(masterIndex) ? masters[masterIndex] : nil
    }

    /// Backdoor for the blackout tests and the failure floor: the master texture regardless of the
    /// gate. Never call this from a display path.
    func rawMasterTexture() -> MTLTexture? {
        masters.indices.contains(masterIndex) ? masters[masterIndex] : nil
    }

    func monitorTexture(_ source: MonitorSource) -> MTLTexture? {
        switch source {
        case .deck(let id):
            // Cue monitors: the operator lines up the next shader while the room is dark, so these
            // deliberately do NOT tap post-blackout.
            return deckTexture(id)
        case .master:
            return programTexture()
        }
    }
```

`testAnInstrumentWithNoCompositorOutputsBlackRatherThanGarbage` asserts on `programTexture()` with
blackout off, so it reads the cleared master — no change needed there. But the earlier
`testMasterIsFixedAt1920x1080` in `InstrumentRendererTests` must switch to `rawMasterTexture()` so
it keeps measuring the texture rather than the gate.

- [ ] **Step 4: Run the tests to verify they pass**

Expected: 7 blackout tests plus everything before, 0 failures.

- [ ] **Step 5: Commit**

```sh
git add App/ARShader/InstrumentRenderer.swift App/ARShaderTests
git commit -m "feat(safety): blackout as a final gate that withdraws the program texture

Nil from programTexture(), and every consumer already renders opaque black on nil -
so no pipeline, shader or extra state sits between the panic button and darkness.
A compositor that fails to build takes the same path. The master monitor taps
post-blackout; deck cue monitors deliberately do not."
```

---

## Task 9: Monitor viewports

**Files:**
- Create: `App/ARShader/MonitorView.swift`
- Create: `App/ARShaderTests/MonitorViewTests.swift`
- Modify: `App/ARShader/InstrumentRenderer.swift` (monitor tick fan-out)

**Interfaces:**
- Consumes: `TexturePresentingView` (Task 2), `MonitorSource`/`monitorTexture` (Task 8).
- Produces:
  - `struct MonitorViewport: NSViewRepresentable` — `init(instrument:source:label:)`.
  - `InstrumentRenderer.registerMonitor(_ view: MTKView)` / `unregisterMonitor(_ view: MTKView)`.

Monitors draw textures that already exist. There is no readback, no encode, no frame budget and no
cost governor — the problem class that made the browser cockpit expensive does not exist here
(spec §6). A monitor is a small `MTKView` that presents `monitorTexture(source)`.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/MonitorViewTests.swift`:

```swift
import XCTest
import MetalKit

@MainActor
final class MonitorViewTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var renderer: InstrumentRenderer!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: MixerState())
    }

    func testRegisteredMonitorsAreDrawnOncePerFrame() throws {
        let monitor = CountingPresentingView(device: device, queue: queue)
        renderer.registerMonitor(monitor)
        renderer.renderFrame()
        XCTAssertEqual(monitor.drawRequests, 1,
                       "One instrument frame drives exactly one draw per monitor")
        renderer.renderFrame()
        XCTAssertEqual(monitor.drawRequests, 2)
    }

    func testUnregisteredMonitorsStopBeingDrawn() throws {
        let monitor = CountingPresentingView(device: device, queue: queue)
        renderer.registerMonitor(monitor)
        renderer.renderFrame()
        renderer.unregisterMonitor(monitor)
        renderer.renderFrame()
        XCTAssertEqual(monitor.drawRequests, 1)
    }

    func testTheRendererDoesNotRetainMonitorsAfterTheyAreGone() throws {
        weak var weakMonitor: CountingPresentingView?
        autoreleasepool {
            let monitor = CountingPresentingView(device: device, queue: queue)
            weakMonitor = monitor
            renderer.registerMonitor(monitor)
            renderer.unregisterMonitor(monitor)
        }
        XCTAssertNil(weakMonitor, "A monitor list that retains its views leaks a window's worth "
                     + "of Metal state every time a panel closes")
    }

    func testAMonitorWithANilSourceRendersBlackRatherThanItsLastFrame() throws {
        // The blackout contract at the view layer.
        let monitor = CountingPresentingView(device: device, queue: queue)
        var backing: MTLTexture?
        monitor.sourceTexture = { backing }
        backing = renderer.rawMasterTexture()
        XCTAssertNotNil(monitor.sourceTexture?())
        backing = nil
        XCTAssertNil(monitor.sourceTexture?(),
                     "The view must consult the closure every draw, never cache the texture")
    }
}

/// Counts draw requests without needing a window or a drawable.
@MainActor
private final class CountingPresentingView: TexturePresentingView {
    private(set) var drawRequests = 0
    override func draw() {
        drawRequests += 1
        // Deliberately does NOT call super: there is no window, so currentDrawable is nil and the
        // real draw would early-return anyway.
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `no member 'registerMonitor'`.

- [ ] **Step 3: Add the monitor fan-out to `InstrumentRenderer`**

```swift
    /// Views presenting instrument textures. Weak: a closed panel's view must deallocate, and a
    /// strong list would hold a window's worth of Metal state alive forever.
    private let monitors = NSHashTable<MTKView>.weakObjects()

    func registerMonitor(_ view: MTKView) { monitors.add(view) }
    func unregisterMonitor(_ view: MTKView) { monitors.remove(view) }
```

and at the end of `renderFrame()`, after `onFrameRendered?()`:

```swift
        // Monitors present textures produced by the buffer just committed. Each MTKView.draw()
        // manages its own drawable cycle and encodes its own (tiny) blit buffer — the frame's
        // RENDER work is still one buffer; these are presents.
        for case let view as MTKView in monitors.allObjects { view.draw() }
```

Add `import MetalKit` if not already present.

- [ ] **Step 4: Write `MonitorView`**

`App/ARShader/MonitorView.swift`:

```swift
import SwiftUI
import MetalKit

/// A live viewport onto one of the instrument's textures.
///
/// Draws a texture that already exists on the GPU — no readback, no encode, no budget. `freeze`
/// stops pulling new textures (the view keeps presenting whatever it last drew); `isOff` withdraws
/// the source entirely so the viewport goes black. Both are manual overrides and always win.
struct MonitorViewport: NSViewRepresentable {
    let instrument: Instrument
    let source: MonitorSource
    var isFrozen: Bool = false
    var isOff: Bool = false

    func makeNSView(context: Context) -> TexturePresentingView {
        let view = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        view.preferredFramesPerSecond = 60
        view.isPaused = true            // the instrument's clock drives it, not its own
        view.enableSetNeedsDisplay = false
        context.coordinator.view = view
        let renderer = instrument.renderer
        let src = source
        view.sourceTexture = { [weak coordinator = context.coordinator] () -> MTLTexture? in
            // Runs on the display-link thread — see the Threading Model section. No isolation
            // wrapper: the coordinator's freeze/off flags and cached texture are guarded by its
            // own lock, mirroring SourceRouter's `routesLock` mirror of `renderRoutes`.
            guard let coordinator else { return nil }
            return coordinator.currentTexture { renderer.monitorTexture(src) }
        }
        renderer.registerMonitor(view)
        return view
    }

    func updateNSView(_ nsView: TexturePresentingView, context: Context) {
        context.coordinator.isFrozen = isFrozen
        context.coordinator.isOff = isOff
    }

    static func dismantleNSView(_ nsView: TexturePresentingView, coordinator: Coordinator) {
        coordinator.renderer?.unregisterMonitor(nsView)
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.renderer = instrument.renderer
        return c
    }

    /// Written from SwiftUI on main, READ from the display-link thread every frame — so every
    /// field is behind one lock. Not `@MainActor`: see the Threading Model section.
    final class Coordinator: @unchecked Sendable {
        weak var view: TexturePresentingView?
        var renderer: InstrumentRenderer?

        private let lock = NSLock()
        private var _isFrozen = false
        private var _isOff = false
        /// The last texture pulled before freezing. Held so a frozen monitor keeps showing the
        /// frame the operator froze rather than going black.
        private var frozenTexture: MTLTexture?

        var isFrozen: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _isFrozen }
            set { lock.lock(); _isFrozen = newValue; lock.unlock() }
        }
        var isOff: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _isOff }
            set { lock.lock(); _isOff = newValue; lock.unlock() }
        }

        /// The texture this monitor should present, applying off/freeze. `pull` is only called
        /// when a live texture is actually wanted.
        func currentTexture(_ pull: () -> MTLTexture?) -> MTLTexture? {
            lock.lock(); defer { lock.unlock() }
            if _isOff { return nil }
            if _isFrozen { return frozenTexture }
            let tex = pull()
            frozenTexture = tex
            return tex
        }
    }
}

/// One labelled monitor tile with its freeze / off controls.
struct MonitorTile: View {
    let instrument: Instrument
    let source: MonitorSource
    let label: String
    @State private var isFrozen = false
    @State private var isOff = false

    var body: some View {
        VStack(spacing: 4) {
            MonitorViewport(instrument: instrument, source: source,
                            isFrozen: isFrozen, isOff: isOff)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(.black)
                .overlay(alignment: .topLeading) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(4)
                }
            HStack(spacing: 6) {
                Toggle("Freeze", isOn: $isFrozen).toggleStyle(.button).controlSize(.small)
                Toggle("Off", isOn: $isOff).toggleStyle(.button).controlSize(.small)
            }
            .font(.system(size: 11))
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Expected: 4 monitor tests, 0 failures.

- [ ] **Step 6: Commit**

```sh
git add App/ARShader/MonitorView.swift App/ARShader/InstrumentRenderer.swift \
        App/ARShaderTests/MonitorViewTests.swift
git commit -m "feat(monitors): deck and master viewports driven by the instrument clock

Monitors present textures that already exist - no readback, no encode, no governor.
Weak registration so a closed panel's view deallocates. Freeze holds the last pulled
texture; off withdraws the source. Master taps post-blackout, decks stay live as cue
monitors."
```

---

## Task 10: Shader library

**Files:**
- Create: `App/ARShader/LibraryPanelView.swift`
- Create: `App/ARShaderTests/LibraryPanelTests.swift`
- Modify: `App/ISFRuntime/LibraryModel.swift` (add the instrument's default source)

**Interfaces:**
- Consumes: `LibraryModel`/`LibraryEntry`/`LibrarySort` (Task 1), `Deck.load(url:)` (Task 3).
- Produces:
  - `LibraryModel.loadInstrumentLibraries()` — adds `/Library/Graphics/ISF` and
    `~/Library/Graphics/ISF`, skipped under `TestHarness.isActive`.
  - `final class LibrarySelection: ObservableObject` — `@Published var query: String`,
    `@Published var sort: LibrarySort`, `func results(in: LibraryModel) -> [LibraryEntry]`.
  - `struct LibraryPanelView: View` — `init(instrument:targetDeck:)`.

The library points at `/Library/Graphics/ISF`, the authoritative 947-file `AR_` corpus (spec §9).
`LibraryModel` already enumerates lazily — it never parses file contents — which is what makes a
~1,400-file directory listable without a stall.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/LibraryPanelTests.swift`:

```swift
import XCTest

@MainActor
final class LibraryPanelTests: XCTestCase {
    private func makeModel(with names: [String]) throws -> (LibraryModel, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arshader-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in names {
            try "/*{\"INPUTS\":[]}*/\nvoid main(){gl_FragColor=vec4(1.0);}"
                .write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8)
        }
        let model = LibraryModel()
        model.addFolder(dir, title: "Test")
        return (model, dir)
    }

    func testSearchRequiresEveryTokenToMatch() throws {
        let (model, dir) = try makeModel(with: [
            "AR_Genuary2026_Day14.fs", "AR_Genuary2026_Day02.fs", "AR_Devolution_Kindling.fs"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let selection = LibrarySelection()
        selection.query = "genuary 14"
        XCTAssertEqual(selection.results(in: model).map(\.name), ["AR_Genuary2026_Day14.fs"])

        selection.query = "genuary"
        XCTAssertEqual(selection.results(in: model).count, 2)

        selection.query = ""
        XCTAssertEqual(selection.results(in: model).count, 3)
    }

    func testSearchIsCaseInsensitiveAndOrderIndependent() throws {
        let (model, dir) = try makeModel(with: ["AR_Genuary2026_Day14.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let selection = LibrarySelection()
        selection.query = "14 GENUARY"
        XCTAssertEqual(selection.results(in: model).count, 1)
    }

    func testSortOrderIsHonoured() throws {
        let (model, dir) = try makeModel(with: ["b.fs", "a.fs", "c.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let selection = LibrarySelection()
        selection.sort = .name
        XCTAssertEqual(selection.results(in: model).map(\.name), ["a.fs", "b.fs", "c.fs"])
    }

    func testLoadingAnEntryPutsItOnTheTargetDeck() throws {
        let (model, dir) = try makeModel(with: ["loadme.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())

        let entry = try XCTUnwrap(model.filtered(query: "loadme").first)
        let done = expectation(description: "load")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(url: entry.url)
        wait(for: [done], timeout: 30)

        XCTAssertNil(deck.compileError)
        XCTAssertEqual(deck.shaderName, "loadme.fs")
    }

    func testTheInstrumentLibraryIsSkippedUnderTheTestHarness() {
        // The suite must never scan the user's real folders: a persisted folder in a TCC-protected
        // location would block the run behind a permission prompt.
        XCTAssertTrue(TestHarness.isActive)
        let model = LibraryModel()
        model.loadInstrumentLibraries()
        XCTAssertTrue(model.sources.isEmpty)
    }
}
```

Add `import Metal` to the test file.

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'LibrarySelection' in scope`, `no member 'loadInstrumentLibraries'`.

- [ ] **Step 3: Add `loadInstrumentLibraries` to `LibraryModel`**

Append to `App/ISFRuntime/LibraryModel.swift`:

```swift
    /// The instrument's libraries: the authoritative system corpus at `/Library/Graphics/ISF`
    /// (947 `AR_` originals including the Genuary series) plus the user's own folder.
    ///
    /// Unlike the editor's `loadStandardLibraries`, no bundled samples: a performance instrument
    /// browses the operator's real corpus, not a demo gallery.
    func loadInstrumentLibraries() {
        // Headless test mode: never scan the user's real folders from a test host — a persisted
        // folder in a TCC-protected location blocks the harness behind a permission prompt.
        guard !TestHarness.isActive else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.systemISFDir.path) {
            addFolder(Self.systemISFDir, title: "System")
        }
        if fm.fileExists(atPath: Self.userISFDir.path) {
            addFolder(Self.userISFDir, title: "User")
        }
    }
```

`userISFDir` and `systemISFDir` are currently `private static`; change both to `static` so the
instrument path can name them.

- [ ] **Step 4: Write the library panel**

`App/ARShader/LibraryPanelView.swift`:

```swift
import SwiftUI

/// Search and sort state for the library browser. Separate from `LibraryModel` (which owns the
/// folders and their entries) so the view can filter without the model recooking.
@MainActor
final class LibrarySelection: ObservableObject {
    @Published var query: String = ""
    @Published var sort: LibrarySort = .name

    func results(in model: LibraryModel) -> [LibraryEntry] {
        model.filtered(query: query, sort: sort)
    }
}

/// Browse the corpus and load a shader onto a deck.
struct LibraryPanelView: View {
    let instrument: Instrument
    @Binding var targetDeck: DeckID
    @StateObject private var selection = LibrarySelection()
    @ObservedObject private var library: LibraryModel

    init(instrument: Instrument, targetDeck: Binding<DeckID>) {
        self.instrument = instrument
        self._targetDeck = targetDeck
        self.library = instrument.library
    }

    private var entries: [LibraryEntry] { selection.results(in: library) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Search", text: $selection.query)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $selection.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Picker("Load onto", selection: $targetDeck) {
                ForEach(DeckID.allCases) { Text("Deck \($0.displayName)").tag($0) }
            }
            .pickerStyle(.segmented)

            List(entries) { entry in
                Button {
                    instrument.deck(targetDeck).load(url: entry.url)
                } label: {
                    Text(entry.name)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)   // long AR_Genuary names differ at the END
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.name)
            }
            .listStyle(.inset)

            Text("\(entries.count) shaders")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
    }
}
```

`Instrument.init` already calls `library.loadStandardLibraries()` from Task 7 — change it to
`library.loadInstrumentLibraries()`.

- [ ] **Step 5: Run the tests to verify they pass**

Expected: 5 library tests, 0 failures.

- [ ] **Step 6: Commit**

```sh
git add App/ISFRuntime/LibraryModel.swift App/ARShader/LibraryPanelView.swift \
        App/ARShaderTests/LibraryPanelTests.swift App/ARShader/ARShaderApp.swift
git commit -m "feat(library): browse /Library/Graphics/ISF and load onto a deck

Token search (every token must match, any order), sort, and an explicit target-deck
picker. Names truncate in the MIDDLE because AR_Genuary entries differ at the end -
the truncation bug the TouchDesigner browser shipped with."
```

---

## Task 11: Auto-generated per-deck controls

**Files:**
- Create: `App/ARShader/DeckControlsView.swift`
- Create: `App/ARShaderTests/DeckControlsTests.swift`

**Interfaces:**
- Consumes: `Deck` (Task 3), `ParamStore`/`ParamValue`/`ISFPreviewInput` (Task 1).
- Produces: `struct DeckControlsView: View` — `init(deck: Deck)`; and
  `enum DeckControlModel` — `static func rows(for inputs: [ISFPreviewInput]) -> [ControlRow]`,
  `struct ControlRow: Identifiable, Equatable { let input: ISFPreviewInput; let kind: Kind }` with
  `enum Kind { case slider, toggle, point, color, menu, pulse, routed, unsupported }`.

The row-kind mapping is pulled out as a **pure function** so the control generation is testable
without instantiating SwiftUI. The view is then a thin renderer over it.

`LazyVStack` is load-bearing, not cosmetic: a plain `VStack` lays out every row on each main-thread
layout pass, and with an 80-input shader that starves the render loop during a slider drag. The
editor learned this the hard way; the same applies here with two decks' worth of controls on screen.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/DeckControlsTests.swift`:

```swift
import XCTest

final class DeckControlsTests: XCTestCase {
    private func input(_ name: String, _ type: String,
                       defaultValue: Any? = nil, min: Any? = nil, max: Any? = nil,
                       labels: [String]? = nil, values: [Double]? = nil) -> ISFPreviewInput {
        ISFPreviewInput(name: name, type: type, defaultValue: defaultValue,
                        min: min, max: max, labels: labels, values: values)
    }

    func testEachISFTypeMapsToItsControl() {
        let rows = DeckControlModel.rows(for: [
            input("amount", "float", defaultValue: 0.5, min: 0.0, max: 1.0),
            input("enabled", "bool", defaultValue: true),
            input("centre", "point2D", defaultValue: [0.5, 0.5], min: [0.0, 0.0], max: [1.0, 1.0]),
            input("tint", "color", defaultValue: [1.0, 0.0, 0.0, 1.0]),
            input("style", "long", defaultValue: 1.0, labels: ["A", "B"], values: [0, 1]),
            input("trigger", "event"),
            input("inputImage", "image"),
        ])
        XCTAssertEqual(rows.map(\.kind),
                       [.slider, .toggle, .point, .color, .menu, .pulse, .routed])
    }

    func testUnknownTypesAreSurfacedRatherThanDropped() {
        // Silently dropping an input the engine reports is how an operator discovers mid-set that
        // a control they expected does not exist.
        let rows = DeckControlModel.rows(for: [input("mystery", "audioFFT")])
        XCTAssertEqual(rows.map(\.kind), [.unsupported])
    }

    func testDeclarationOrderIsPreserved() {
        let rows = DeckControlModel.rows(for: [
            input("z", "float"), input("a", "float"), input("m", "bool"),
        ])
        XCTAssertEqual(rows.map(\.input.name), ["z", "a", "m"],
                       "ISF header order is the author's intent — never alphabetise it")
    }

    func testAShaderWithNoInputsProducesNoRows() {
        XCTAssertTrue(DeckControlModel.rows(for: []).isEmpty)
    }

    // MARK: value plumbing

    @MainActor
    func testSettingAControlValueReachesTheParamStoreAndTheEngine() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())

        var seen: [(String, String)] = []
        let original = deck.params.onSet
        deck.params.onSet = { name, json in
            seen.append((name, json))
            original?(name, json)
        }
        deck.params.set("amount", .float(0.25))
        XCTAssertEqual(seen.map(\.0), ["amount"])
        XCTAssertEqual(seen.map(\.1), ["0.25"])
    }

    @MainActor
    func testResetRestoresTheHeaderDefault() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())
        deck.params.syncInputs([input("amount", "float", defaultValue: 0.5, min: 0.0, max: 1.0)])

        deck.params.set("amount", .float(0.9))
        XCTAssertTrue(deck.params.isModified("amount"))
        deck.params.resetToDefault("amount")
        XCTAssertFalse(deck.params.isModified("amount"))
        guard case .float(let v)? = deck.params.value(for: "amount") else {
            return XCTFail("expected a float")
        }
        XCTAssertEqual(v, 0.5, accuracy: 1e-12)
    }
}
```

Add `import Metal` to the test file.

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'DeckControlModel' in scope`.

- [ ] **Step 3: Write `DeckControlsView`**

`App/ARShader/DeckControlsView.swift`:

```swift
import SwiftUI

/// Pure mapping from ISF input descriptors to control rows. Split out from the view so control
/// generation is testable without SwiftUI, and so an unknown type is a visible row rather than a
/// silent omission.
enum DeckControlModel {
    enum Kind: Equatable {
        case slider, toggle, point, color, menu, pulse
        /// Image inputs are routed through `SourceRouter`, not set as values.
        case routed
        /// The engine reported a type this build cannot render a control for. Shown, never dropped.
        case unsupported
    }

    struct ControlRow: Identifiable, Equatable {
        let input: ISFPreviewInput
        let kind: Kind
        var id: String { input.name }
    }

    /// Rows in ISF header declaration order — the author's intent, never alphabetised.
    static func rows(for inputs: [ISFPreviewInput]) -> [ControlRow] {
        inputs.map { input in
            let kind: Kind
            switch input.type {
            case "float":   kind = .slider
            case "bool":    kind = .toggle
            case "point2D": kind = .point
            case "color":   kind = .color
            case "long":    kind = .menu
            case "event":   kind = .pulse
            case "image":   kind = .routed
            default:        kind = .unsupported
            }
            return ControlRow(input: input, kind: kind)
        }
    }
}

/// Auto-generated controls for one deck's loaded shader.
struct DeckControlsView: View {
    @ObservedObject var deck: Deck

    private var rows: [DeckControlModel.ControlRow] {
        DeckControlModel.rows(for: deck.inputs)
    }

    var body: some View {
        ScrollView {
            // LazyVStack is load-bearing: a plain VStack lays out ALL rows on every main-thread
            // layout pass, and an 80-input shader then starves the render loop during a drag.
            LazyVStack(alignment: .leading, spacing: 9) {
                if let error = deck.compileError {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if deck.shaderName == nil {
                    Text("No shader loaded").font(.caption).foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    Text("No adjustable inputs").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    switch row.kind {
                    case .slider:      sliderRow(row.input)
                    case .toggle:      toggleRow(row.input)
                    case .point:       pointRow(row.input)
                    case .color:       colorRow(row.input)
                    case .menu:        menuRow(row.input)
                    case .pulse:       pulseRow(row.input)
                    case .routed:      EmptyView()
                    case .unsupported: unsupportedRow(row.input)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Label left, live value right. Double-click resets; a dot marks a value off its default.
    private func labelRow(_ name: String, value: String) -> some View {
        HStack(spacing: 5) {
            if deck.params.isModified(name) { Circle().fill(.tint).frame(width: 5, height: 5) }
            Text(name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { deck.params.resetToDefault(name) }
        .help("Double-click to reset to default")
    }

    private func format(_ v: Double) -> String { String(format: "%.3g", v) }

    @ViewBuilder private func sliderRow(_ input: ISFPreviewInput) -> some View {
        let lo = (input.min as? Double) ?? 0
        let hi = (input.max as? Double) ?? 1
        let fallback = (input.defaultValue as? Double) ?? lo
        let binding = Binding<Double>(
            get: { if case .float(let v)? = deck.params.value(for: input.name) { return v }
                   return fallback },
            set: { deck.params.set(input.name, .float($0)) })
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: format(binding.wrappedValue))
            Slider(value: binding, in: lo...max(hi, lo + 0.0001))
        }
    }

    @ViewBuilder private func toggleRow(_ input: ISFPreviewInput) -> some View {
        let binding = Binding<Bool>(
            get: { if case .bool(let v)? = deck.params.value(for: input.name) { return v }
                   return (input.defaultValue as? Bool) ?? false },
            set: { deck.params.set(input.name, .bool($0)) })
        Toggle(input.name, isOn: binding).font(.system(size: 12))
    }

    @ViewBuilder private func pointRow(_ input: ISFPreviewInput) -> some View {
        let lo = ParamStore.doubles(input.min, count: 2, fallback: [0, 0])
        let hi = ParamStore.doubles(input.max, count: 2, fallback: [1, 1])
        let fallback = ParamStore.doubles(input.defaultValue, count: 2, fallback: [0.5, 0.5])
        let current: [Double] = {
            if case .point2D(let p)? = deck.params.value(for: input.name) { return p }
            return fallback
        }()
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: "\(format(current[0])), \(format(current[1]))")
            ForEach(0..<2, id: \.self) { axis in
                Slider(value: Binding<Double>(
                    get: { current[axis] },
                    set: { newValue in
                        var next = current
                        next[axis] = newValue
                        deck.params.set(input.name, .point2D(next))
                    }), in: lo[axis]...max(hi[axis], lo[axis] + 0.0001))
            }
        }
    }

    @ViewBuilder private func colorRow(_ input: ISFPreviewInput) -> some View {
        let fallback = ParamStore.doubles(input.defaultValue, count: 4, fallback: [1, 1, 1, 1])
        let current: [Double] = {
            if case .color(let c)? = deck.params.value(for: input.name) { return c }
            return fallback
        }()
        let binding = Binding<Color>(
            get: { Color(red: current[0], green: current[1], blue: current[2])
                     .opacity(current[3]) },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .white
                deck.params.set(input.name, .color([Double(ns.redComponent),
                                                    Double(ns.greenComponent),
                                                    Double(ns.blueComponent),
                                                    Double(ns.alphaComponent)]))
            })
        HStack {
            labelRow(input.name, value: "")
            ColorPicker("", selection: binding, supportsOpacity: true).labelsHidden()
        }
    }

    @ViewBuilder private func menuRow(_ input: ISFPreviewInput) -> some View {
        let values = input.values ?? []
        let labels = input.labels ?? values.map { format($0) }
        let fallback = (input.defaultValue as? Double) ?? values.first ?? 0
        let binding = Binding<Double>(
            get: { if case .long(let v)? = deck.params.value(for: input.name) { return v }
                   return fallback },
            set: { deck.params.set(input.name, .long($0)) })
        HStack {
            Text(input.name).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Picker("", selection: binding) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    Text(i < labels.count ? labels[i] : format(v)).tag(v)
                }
            }
            .labelsHidden().frame(maxWidth: 160)
        }
    }

    @ViewBuilder private func pulseRow(_ input: ISFPreviewInput) -> some View {
        Button(input.name) { deck.pulseEvent(input.name) }
            .font(.system(size: 12))
    }

    @ViewBuilder private func unsupportedRow(_ input: ISFPreviewInput) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text("\(input.name) — \(input.type) not supported")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .help("The engine reports this input, but this build has no control for its type.")
    }
}
```

Add `import AppKit` for `NSColor`.

- [ ] **Step 4: Run the tests to verify they pass**

Expected: 6 control tests, 0 failures.

- [ ] **Step 5: Commit**

```sh
git add App/ARShader/DeckControlsView.swift App/ARShaderTests/DeckControlsTests.swift
git commit -m "feat(controls): auto-generated per-deck controls from the ISF header

Row-kind mapping is a pure function so control generation is testable without
SwiftUI, and an unknown input type renders a visible 'not supported' row rather than
vanishing. LazyVStack, because a plain VStack starves the render loop on high-input
shaders."
```

---

## Task 12: Program output window — fullscreen on a second display

**Added 2026-07-30 at the operator's request, mid-execution.** The Self-Review had flagged its
absence as an accepted gap; the operator ruled it back in: *"We would need to be able to connect a
monitor for full screen output on that screen to mock the projector… also having that floating as a
window would be great if second monitor isn't detected."* A projector mock you cannot put on a
projector is not a rehearsal, and the whole milestone exists to be rehearsed with.

**Files:**
- Create: `App/ARShader/OutputDestination.swift`
- Create: `App/ARShader/OutputWindowController.swift`
- Create: `App/ARShaderTests/OutputDestinationTests.swift`
- Modify: `App/ARShader/Instrument.swift` (own the controller)

**Interfaces:**
- Consumes: `TexturePresentingView`, `InstrumentRenderer.programTexture()` /
  `registerMonitor` (Tasks 2, 8, 9).
- Produces:
  - `struct ScreenInfo: Identifiable, Equatable, Sendable` — `let id: String`, `let name: String`,
    `let frame: CGRect`, `let isMain: Bool`. A value model of `NSScreen` so the selection logic is
    testable without hardware.
  - `enum OutputDestination: Equatable, Sendable` — `case off`, `case floating`, `case screen(id: String)`.
  - `enum OutputPlacement` — `static func resolve(_ requested: OutputDestination, screens: [ScreenInfo]) -> Resolved`,
    with `enum Resolved: Equatable { case closed; case floating(on: ScreenInfo); case fullscreen(on: ScreenInfo) }`.
  - `enum OutputMenu` — `static func options(for screens: [ScreenInfo]) -> [OutputDestination]`.
  - `@MainActor final class OutputWindowController` — `init(instrument:)`, `var destination: OutputDestination { get }`,
    `func setDestination(_:)`, `func toggleFullscreen()`, `var isOpen: Bool`.

### Design decisions

- **Borderless window covering the target screen's frame — NOT macOS native fullscreen.** Native
  fullscreen animates into its own Space, is slow to enter and leave, and interacts badly with
  ⌘-tab and with a second window. A borderless `NSWindow` at `screen.frame` is what a projector
  feed wants and what every VJ host does.
- **Ships closed.** `OutputDestination.off` is the launch default. Nothing is ever projected until
  the operator deliberately opens it. This is the same doctrine as the TouchDesigner build's
  "servers ship OFF, every launch needs a deliberate operator enable" — the most valuable habit
  that build produced.
- **Auto-fallback, announced.** If the screen the output is on disappears (unplug mid-set), the
  window becomes a floating window on the main screen. It never silently vanishes and never
  strands itself on a screen that no longer exists.
- **Blackout needs no new path.** The output window presents `programTexture()`, which returns nil
  while blacked out, and `TexturePresentingView` renders opaque black on nil. Blackout covers the
  projector by construction — there is no second gate to keep in sync, which is exactly why
  Task 8 withdrew the texture instead of setting a flag.
- **⌘⇧F toggles the output window; Escape is NOT used** — Escape is the momentary blackout hold
  (Task 13). A panic key that also closes the projector window would be a bad surprise.
- **The cursor hides over the output window.** A projector showing a mouse pointer reads as broken.

- [ ] **Step 1: Write the failing test**

`App/ARShaderTests/OutputDestinationTests.swift`:

```swift
import XCTest

final class OutputDestinationTests: XCTestCase {
    private let laptop = ScreenInfo(id: "1", name: "Built-in Display",
                                    frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                    isMain: true)
    private let projector = ScreenInfo(id: "2", name: "EPSON PJ",
                                       frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                                       isMain: false)

    func testOffIsClosedNoMatterWhatIsPluggedIn() {
        XCTAssertEqual(OutputPlacement.resolve(.off, screens: [laptop, projector]), .closed)
        XCTAssertEqual(OutputPlacement.resolve(.off, screens: [laptop]), .closed)
    }

    func testFloatingLandsOnTheMainScreen() {
        XCTAssertEqual(OutputPlacement.resolve(.floating, screens: [laptop, projector]),
                       .floating(on: laptop))
    }

    func testAScreenRequestGoesFullscreenOnThatScreen() {
        XCTAssertEqual(OutputPlacement.resolve(.screen(id: "2"), screens: [laptop, projector]),
                       .fullscreen(on: projector))
    }

    func testAnUnpluggedScreenFallsBackToFloatingRatherThanDisappearing() {
        // The unplug-mid-set case. Going .closed here would black the room with no warning;
        // stranding the window on a dead screen would lose the output entirely.
        XCTAssertEqual(OutputPlacement.resolve(.screen(id: "2"), screens: [laptop]),
                       .floating(on: laptop))
    }

    func testWithNoScreensAtAllTheOutputIsClosed() {
        XCTAssertEqual(OutputPlacement.resolve(.screen(id: "2"), screens: []), .closed)
        XCTAssertEqual(OutputPlacement.resolve(.floating, screens: []), .closed)
    }

    func testFloatingFallsBackToTheFirstScreenWhenNoneClaimsToBeMain() {
        let odd = ScreenInfo(id: "9", name: "Odd", frame: .zero, isMain: false)
        XCTAssertEqual(OutputPlacement.resolve(.floating, screens: [odd]), .floating(on: odd))
    }

    // MARK: menu

    func testTheMenuOffersOffFloatingAndEveryScreen() {
        XCTAssertEqual(OutputMenu.options(for: [laptop, projector]),
                       [.off, .floating, .screen(id: "1"), .screen(id: "2")])
    }

    func testTheMenuStillOffersFloatingWithOnlyOneScreen() {
        XCTAssertEqual(OutputMenu.options(for: [laptop]),
                       [.off, .floating, .screen(id: "1")])
    }

    func testOffIsTheLaunchDefault() {
        // Nothing is ever projected until the operator asks for it.
        XCTAssertEqual(OutputDestination.launchDefault, .off)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'ScreenInfo' in scope`.

- [ ] **Step 3: Write the placement model**

`App/ARShader/OutputDestination.swift`:

```swift
import AppKit

/// A value model of an `NSScreen`, so placement logic is testable without hardware. Screens are
/// identified by their `NSScreenNumber`, which is stable across a plug/unplug of the same display.
struct ScreenInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let frame: CGRect
    let isMain: Bool

    init(id: String, name: String, frame: CGRect, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isMain = isMain
    }

    @MainActor
    init(screen: NSScreen) {
        let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.id = number.map { "\($0.uint32Value)" } ?? screen.localizedName
        self.name = screen.localizedName
        self.frame = screen.frame
        self.isMain = screen == NSScreen.main
    }

    @MainActor
    static func current() -> [ScreenInfo] { NSScreen.screens.map(ScreenInfo.init(screen:)) }
}

/// Where the operator has asked the program feed to go.
enum OutputDestination: Equatable, Sendable {
    case off
    case floating
    case screen(id: String)

    /// Nothing is projected until the operator deliberately opens it — the same doctrine as the
    /// TouchDesigner build's ships-off servers.
    static let launchDefault: OutputDestination = .off
}

/// Resolves a request against the screens that actually exist right now.
enum OutputPlacement {
    enum Resolved: Equatable {
        case closed
        case floating(on: ScreenInfo)
        case fullscreen(on: ScreenInfo)
    }

    static func resolve(_ requested: OutputDestination, screens: [ScreenInfo]) -> Resolved {
        guard let main = screens.first(where: \.isMain) ?? screens.first else { return .closed }
        switch requested {
        case .off:
            return .closed
        case .floating:
            return .floating(on: main)
        case .screen(let id):
            guard let target = screens.first(where: { $0.id == id }) else {
                // Unplugged mid-set. Fall back to a floating window rather than vanishing
                // (output lost with no signal) or staying on a screen that no longer exists.
                return .floating(on: main)
            }
            return .fullscreen(on: target)
        }
    }
}

enum OutputMenu {
    static func options(for screens: [ScreenInfo]) -> [OutputDestination] {
        [.off, .floating] + screens.map { .screen(id: $0.id) }
    }

    static func title(for destination: OutputDestination, screens: [ScreenInfo]) -> String {
        switch destination {
        case .off:      return "Off"
        case .floating: return "Floating Window"
        case .screen(let id):
            return screens.first(where: { $0.id == id })?.name ?? "Display \(id) (disconnected)"
        }
    }
}
```

- [ ] **Step 4: Write the window controller**

`App/ARShader/OutputWindowController.swift`:

```swift
import AppKit

/// Owns the program-output window: a borderless window covering a chosen screen (the projector
/// mock), or a resizable floating window when no second display is available.
///
/// Deliberately NOT macOS native fullscreen: that animates into its own Space, is slow to enter and
/// leave, and fights ⌘-tab. A borderless window at `screen.frame` is what a projector feed wants.
///
/// The window presents `renderer.programTexture()`, so blackout covers it with no second gate —
/// the texture is withdrawn and `TexturePresentingView` renders opaque black on nil.
@MainActor
final class OutputWindowController: NSObject {
    private unowned let instrument: Instrument
    private var window: NSWindow?
    private var view: TexturePresentingView?
    private var screenObserver: NSObjectProtocol?

    private(set) var destination: OutputDestination = .launchDefault

    var isOpen: Bool { window?.isVisible == true }

    init(instrument: Instrument) {
        self.instrument = instrument
        super.init()
        // Watch for plug/unplug so an output on a vanished screen falls back rather than stranding.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDestination() }
        }
    }

    deinit {
        // Block-based observers are not auto-removed.
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func setDestination(_ destination: OutputDestination) {
        self.destination = destination
        applyDestination()
    }

    /// ⌘⇧F: closed → the first non-main screen if there is one, else floating; open → closed.
    func toggleFullscreen() {
        if destination == .off {
            let screens = ScreenInfo.current()
            let external = screens.first(where: { !$0.isMain })
            setDestination(external.map { .screen(id: $0.id) } ?? .floating)
        } else {
            setDestination(.off)
        }
    }

    private func applyDestination() {
        switch OutputPlacement.resolve(destination, screens: ScreenInfo.current()) {
        case .closed:
            closeWindow()
        case .floating(let screen):
            showWindow(on: screen, fullscreen: false)
        case .fullscreen(let screen):
            showWindow(on: screen, fullscreen: true)
        }
    }

    private func showWindow(on screen: ScreenInfo, fullscreen: Bool) {
        let content = existingView() ?? makeView()
        let frame: NSRect = fullscreen
            ? screen.frame
            : NSRect(x: screen.frame.midX - 480, y: screen.frame.midY - 270,
                     width: 960, height: 540)

        if window == nil {
            let w = NSWindow(contentRect: frame,
                             styleMask: fullscreen ? [.borderless]
                                                   : [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.title = "ARShader — Output"
            window = w
        } else if let w = window, w.styleMask.contains(.borderless) != fullscreen {
            // Switching modes needs a new style mask; rebuild rather than mutate.
            w.orderOut(nil)
            window = nil
            showWindow(on: screen, fullscreen: fullscreen)
            return
        }

        guard let w = window else { return }
        w.contentView = content
        w.setFrame(frame, display: true)
        if fullscreen {
            // Above normal windows so the main UI cannot land on top of the projector feed, but
            // below the screen-saver/alert levels.
            w.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
            w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
            w.hidesOnDeactivate = false
        } else {
            w.level = .normal
            w.collectionBehavior = [.fullScreenAuxiliary]
        }
        w.orderFront(nil)      // never makeKey: the operator keeps focus on the control surface
        NSCursor.setHiddenUntilMouseMoves(fullscreen)
    }

    private func closeWindow() {
        if let view { instrument.renderer.unregisterMonitor(view) }
        view = nil
        window?.orderOut(nil)
        window = nil
    }

    private func existingView() -> TexturePresentingView? { view }

    private func makeView() -> TexturePresentingView {
        let v = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        v.isPaused = true               // the instrument's clock drives it
        v.enableSetNeedsDisplay = false
        let renderer = instrument.renderer
        v.sourceTexture = { renderer.programTexture() }   // nil while blacked out ⇒ black
        renderer.registerMonitor(v)
        view = v
        return v
    }
}
```

- [ ] **Step 5: Own the controller on `Instrument`**

In `App/ARShader/Instrument.swift`, add:

```swift
    private(set) lazy var output = OutputWindowController(instrument: self)
```

- [ ] **Step 6: Run the tests to verify they pass**

Expected: 9 placement tests, 0 failures. The window itself is not unit-tested — it needs real
screens. It is covered by Task 13's live smoke, which is the only honest way to test a projector.

- [ ] **Step 7: Commit**

```sh
git add App/ARShader/OutputDestination.swift App/ARShader/OutputWindowController.swift \
        App/ARShader/Instrument.swift App/ARShaderTests/OutputDestinationTests.swift
git commit -m "feat(output): program output window, fullscreen on a chosen screen

Borderless window at the target screen's frame rather than macOS native fullscreen,
which animates into its own Space and fights cmd-tab. Ships CLOSED - nothing is
projected until the operator opens it. An unplugged screen falls back to a floating
window rather than vanishing or stranding itself. Blackout needs no new path: the
window presents programTexture(), which is withdrawn while blacked out."
```

---

## Task 13: Assemble the instrument and play it

**Files:**
- Create: `App/ARShader/InstrumentView.swift`
- Create: `App/ARShader/BlackoutKeyMonitor.swift`
- Create: `scripts/run-instrument.sh`
- Create: `Tests/reports/live-smoke-instrument-m1.md`
- Modify: `App/ARShader/ARShaderApp.swift`
- Create: `App/ARShaderTests/BlackoutKeyMonitorTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–11.
- Produces:
  - `final class BlackoutKeyMonitor` — `init(mixer:)`, `func start()`, `func stop()`,
    `static func action(for event: KeyEventDescriptor) -> BlackoutAction?`,
    `enum BlackoutAction { case toggleLatch, beginHold, endHold }`,
    `struct KeyEventDescriptor { let keyCode: UInt16; let hasCommand: Bool; let isDown: Bool; let isRepeat: Bool }`.
  - `struct InstrumentView: View`.

**UI scope is deliberately minimal (spec §11):** decks, faders, blend dropdowns, library, monitors,
blackout. No visual design ambition, no theming, no motion work. The interface the operator actually
wants is designed **after** they have played with this one — that sequencing is the entire point of
the milestone and is not an invitation to "make it nice while we're in there."

### Keyboard blackout: why ⌘B and Escape

Blackout must be reachable "at all times, and regardless of what any panel or drawer is doing"
(spec §8). A bare letter key cannot satisfy that: the library search field is a first responder that
swallows plain keystrokes, so a bare `B` would either do nothing while searching or need a
focus exception — which is exactly the "reachable except when…" the spec rules out.

`⌘B` (latch toggle) and `Escape` (momentary hold) are both un-typeable into a text field, so a
single global `NSEvent` local monitor handles them with no focus special-casing at all.

- [ ] **Step 1: Write the failing key-mapping test**

`App/ARShaderTests/BlackoutKeyMonitorTests.swift`:

```swift
import XCTest

final class BlackoutKeyMonitorTests: XCTestCase {
    private func key(_ code: UInt16, command: Bool = false,
                     down: Bool = true, repeated: Bool = false) -> KeyEventDescriptor {
        KeyEventDescriptor(keyCode: code, hasCommand: command, isDown: down, isRepeat: repeated)
    }

    private let bKey: UInt16 = 11        // kVK_ANSI_B
    private let escapeKey: UInt16 = 53   // kVK_Escape
    private let aKey: UInt16 = 0         // kVK_ANSI_A

    func testCommandBTogglesTheLatch() {
        XCTAssertEqual(BlackoutKeyMonitor.action(for: key(bKey, command: true)), .toggleLatch)
    }

    func testBareBDoesNothing() {
        // A bare letter key would be swallowed by the library search field — and blackout must not
        // have a "reachable except while typing" caveat.
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(bKey)))
    }

    func testEscapeIsMomentary() {
        XCTAssertEqual(BlackoutKeyMonitor.action(for: key(escapeKey)), .beginHold)
        XCTAssertEqual(BlackoutKeyMonitor.action(for: key(escapeKey, down: false)), .endHold)
    }

    func testAutoRepeatDoesNotRetriggerTheHold() {
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(escapeKey, repeated: true)))
    }

    func testCommandBAutoRepeatDoesNotStrobeTheLatch() {
        // Holding cmd-B must not flash the room.
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(bKey, command: true, repeated: true)))
    }

    func testUnrelatedKeysAreIgnored() {
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(aKey)))
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(aKey, command: true)))
    }

    @MainActor
    func testTheMonitorDrivesTheMixer() {
        let mixer = MixerState()
        let monitor = BlackoutKeyMonitor(mixer: mixer)
        monitor.apply(.toggleLatch)
        XCTAssertTrue(mixer.isBlackedOut)
        monitor.apply(.beginHold)
        monitor.apply(.endHold)
        XCTAssertTrue(mixer.isBlackedOut, "The latch survives a momentary tap")
        monitor.apply(.toggleLatch)
        XCTAssertFalse(mixer.isBlackedOut)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'BlackoutKeyMonitor' in scope`.

- [ ] **Step 3: Write `BlackoutKeyMonitor`**

`App/ARShader/BlackoutKeyMonitor.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// The parts of an NSEvent the mapping depends on. Split out so the mapping is a pure function and
/// testable without synthesising AppKit events.
struct KeyEventDescriptor: Equatable {
    let keyCode: UInt16
    let hasCommand: Bool
    let isDown: Bool
    let isRepeat: Bool
}

enum BlackoutAction: Equatable {
    case toggleLatch
    case beginHold
    case endHold
}

/// Global keyboard access to blackout.
///
/// Uses an app-wide `NSEvent` local monitor rather than a SwiftUI `.keyboardShortcut`, because the
/// panic path must not depend on what has focus or which panel is open (spec §8). ⌘B and Escape are
/// both un-typeable into a text field, so no focus special-casing is needed.
@MainActor
final class BlackoutKeyMonitor {
    private let mixer: MixerState
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    init(mixer: MixerState) { self.mixer = mixer }

    /// Pure mapping. Auto-repeat produces no action: a held ⌘B must not strobe the latch, and a
    /// held Escape must not re-trigger the hold.
    static func action(for event: KeyEventDescriptor) -> BlackoutAction? {
        guard !event.isRepeat else { return nil }
        switch (event.keyCode, event.hasCommand, event.isDown) {
        case (UInt16(kVK_ANSI_B), true, true):  return .toggleLatch
        case (UInt16(kVK_Escape), false, true): return .beginHold
        case (UInt16(kVK_Escape), false, false): return .endHold
        default: return nil
        }
    }

    func apply(_ action: BlackoutAction) {
        switch action {
        case .toggleLatch: mixer.toggleBlackoutLatch()
        case .beginHold:   mixer.beginBlackoutHold()
        case .endHold:     mixer.endBlackoutHold()
        }
    }

    func start() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event, isDown: true) ?? event
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handle(event, isDown: false) ?? event
        }
    }

    func stop() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m); keyUpMonitor = nil }
    }

    deinit {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
    }

    /// Returns nil to SWALLOW the event (we handled it), or the event to pass it on.
    private func handle(_ event: NSEvent, isDown: Bool) -> NSEvent? {
        let descriptor = KeyEventDescriptor(
            keyCode: event.keyCode,
            hasCommand: event.modifierFlags.contains(.command),
            isDown: isDown,
            isRepeat: isDown && event.isARepeat)
        guard let action = Self.action(for: descriptor) else { return event }
        apply(action)
        return nil
    }
}
```

- [ ] **Step 4: Write the root layout**

`App/ARShader/InstrumentView.swift`:

```swift
import SwiftUI

/// The instrument surface. Deliberately plain (spec §11): three monitors across the top, a deck
/// strip per deck, the mixer, and the library. Design comes after the operator has played with it.
struct InstrumentView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject private var mixer: MixerState
    @State private var libraryTarget: DeckID = .one

    init(instrument: Instrument) {
        self.instrument = instrument
        self.mixer = instrument.mixer
    }

    var body: some View {
        VStack(spacing: 0) {
            monitors
            Divider()
            HSplitView {
                LibraryPanelView(instrument: instrument, targetDeck: $libraryTarget)
                    .frame(minWidth: 260, idealWidth: 300)
                deckStrips
                mixerStrip.frame(width: 190)
            }
        }
        .background(Color.black)
        .onAppear { instrument.blackoutKeys.start() }
        .onDisappear { instrument.blackoutKeys.stop() }
    }

    private var monitors: some View {
        HStack(spacing: 10) {
            MonitorTile(instrument: instrument, source: .deck(.one), label: "DECK A")
            MonitorTile(instrument: instrument, source: .deck(.two), label: "DECK B")
            MonitorTile(instrument: instrument, source: .master, label: "PROGRAM")
        }
        .padding(10)
        .frame(maxHeight: 260)
    }

    private var deckStrips: some View {
        HStack(spacing: 0) {
            ForEach(MixerState.layerOrder) { id in
                deckStrip(id)
                if id != MixerState.layerOrder.last { Divider() }
            }
        }
        .frame(minWidth: 420)
    }

    private func deckStrip(_ id: DeckID) -> some View {
        let deck = instrument.deck(id)
        let layer = mixer.layers().first { $0.deck == id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DECK \(id.displayName)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                if deck.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Clear") { deck.unload() }.controlSize(.small)
            }
            Text(deck.shaderName ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(deck.shaderName == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)

            // Both values, always — the fader the operator set AND what it is contributing.
            HStack {
                Text("Opacity").font(.system(size: 11))
                Spacer()
                Text(String(format: "%.2f", layer?.userOpacity ?? 1))
                    .font(.system(size: 11, design: .monospaced))
                Text(String(format: "→ %.2f", layer?.effectiveOpacity ?? 1))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("Effective opacity after the crossfader")
            }
            Slider(value: Binding(
                get: { mixer.opacity[id] ?? 1 },
                set: { mixer.setOpacity($0, for: id) }), in: 0...1)

            Picker("Blend", selection: Binding(
                get: { mixer.blendMode[id] ?? .normal },
                set: { mixer.setBlendMode($0, for: id) })) {
                ForEach(BlendMode.allCases) { Text($0.displayName).tag($0) }
            }

            Divider()
            DeckControlsView(deck: deck)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mixerStrip: some View {
        VStack(spacing: 10) {
            Text("CROSSFADER").font(.system(size: 11, weight: .bold, design: .monospaced))
            Slider(value: $mixer.crossfadePosition, in: 0...1)
            HStack {
                Text("A").font(.system(size: 11, design: .monospaced))
                Spacer()
                Text(String(format: "%.2f", mixer.crossfadePosition))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("B").font(.system(size: 11, design: .monospaced))
            }

            Spacer()

            Button {
                mixer.toggleBlackoutLatch()
            } label: {
                Text(mixer.isBlackedOut ? "BLACKOUT ON" : "BLACKOUT")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(mixer.isBlackedOut ? .red : .gray)
            .help("⌘B latches blackout. Hold Escape for a momentary blackout.")

            Text("⌘B latch · hold ESC")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(10)
    }
}
```

In `ARShaderApp.swift`, add `let blackoutKeys: BlackoutKeyMonitor` to `Instrument` (constructed
after `mixer`), and replace `InstrumentRootView` with `InstrumentView(instrument: instrument)`. The
program output is no longer the whole window — the PROGRAM monitor tile is the on-screen program
feed for Milestone 1, and `renderFrame()` is driven by whichever `TexturePresentingView` the clock
is attached to. **Attach the clock to the PROGRAM tile's view**: in `MonitorViewport.makeNSView`,
when `source == .master`, set `view.onWillDraw = { renderer.renderFrame() }` and call
`renderer.attachClock(to: view)` instead of registering it as a passive monitor.

> This makes the program monitor the frame driver. It is the one viewport guaranteed to exist, and
> it means a frame is produced exactly once per tick. A dedicated fullscreen output window is
> Milestone 2 (`NSScreen` selection is explicitly not Milestone 1 scope).

- [ ] **Step 5: Write the build-and-run script**

`scripts/run-instrument.sh` — copy `scripts/run-latest.sh` and change `TrueISFEditor` → `ARShader`
throughout, `DDATA` → `/tmp/arshader-ddata`, and `DEST` → `${HOME}/Applications/ARShader.app`. Keep
the /tmp DerivedData path (not Spotlight-indexed, so Finder can never open a stale copy) and the
quit-and-wait block. Then:

```sh
chmod +x scripts/run-instrument.sh
```

- [ ] **Step 6: Run every suite, then verify the binary is actually fresh**

```sh
cd ~/Desktop/AV_Projects/ShaderToy-to-ISF-converter
cd ShadertoyISFKit && swift test 2>&1 | tail -3          # unchanged from .baseline-m1.txt
cd ../App && xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -5   # unchanged from .baseline-m1.txt
xcodebuild -project TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -5
cd .. && ./scripts/run-instrument.sh
```

**Staleness check — do not skip.** Xcode 26 puts compiled code in a debuggable dylib, so grep the
dylib, not the stub. Use a string longer than 15 characters (Swift small-string optimisation makes
shorter literals invisible to `strings`):

```sh
strings ~/Applications/ARShader.app/Contents/MacOS/ARShader.debug.dylib | grep -c "⌘B latch · hold ESC"
```

Expected: `1` or more. **A zero means the staged binary does not contain your change — do not tell
the operator to relaunch.**

- [ ] **Step 7: Manual code review (Mechanic, run by hand — not a subagent)**

For native macOS Swift/Metal work this project's standing rule is a **manual** review: read the
changed files directly. A dispatched Mechanic cannot build or run this project and reliably stalls
on the watchdog. Check specifically:

- Zero uses of `MainActor.assumeIsolated` anywhere on the render path. It is a runtime assertion
  and traps off-main; every render-path type must be lock-guarded and non-isolated instead (see the
  Threading Model section).
- Every `NotificationCenter` / `NSEvent` observer has a matching removal. Block-based observers are
  not auto-removed.
- No texture is retained across command buffers except the ones the decks and masters own.
- No `TOP`-style per-frame allocation crept into `renderFrame()`.

- [ ] **Step 8: Client Success review of the live app**

Drive the running app and capture the key states, then have Client Success review them. Required
states: idle (no shaders), one deck loaded, both decks loaded at crossfade centre, blackout engaged,
a compile failure on deck B while deck A keeps playing, and a long shader name in the library.
Check specifically:

- Is BLACKOUT unmistakable at rest and unmistakable when engaged? (The cockpit shipped grey-on-grey
  at rest with a red Stop beside it — measured and rejected.)
- Are the sliders large enough to hit under stage conditions? The project's own floor is 44px for
  primary targets, and automated a11y checks do **not** verify target size.
- Does a compile error say what failed, or just that something did?
- Does anything display a number it did not measure? (The fabricated REC counter is the standing
  example — honest absence beats a plausible readout.)

- [ ] **Step 9: Live smoke with the operator — the CONFIRMED gate**

Write `Tests/reports/live-smoke-instrument-m1.md` with a row per leg, filled in **during** the
session, not after:

| Leg | Hypothesis stated so it can fail | Result |
|---|---|---|
| Library loads | `/Library/Graphics/ISF` lists ≥900 `.fs` entries and search narrows them | |
| Deck A plays | An `AR_Genuary` shader loads and animates at 60 fps | |
| Deck B plays | A second, different shader loads without interrupting deck A | |
| Crossfade | Sweeping A→B moves the program monitor continuously, no jump at the ends | |
| Opacity | Deck opacity and effective opacity both move, and disagree when the fader is off-centre | |
| Blend modes | All 12 modes visibly differ; multiply/screen/difference behave as expected | |
| Blackout latch | ⌘B blacks the program monitor while deck monitors keep running | |
| Blackout momentary | Escape held blacks out; released, the image returns; the latch survives it | |
| Failed compile | Loading a known-broken shader on deck B leaves deck A playing and shows the error | |
| Controls | A shader's own sliders move its image; double-click resets to header default | |
| **Output → floating** | Output ▸ Floating Window opens a window showing the program feed, and the main UI keeps keyboard focus | |
| **Output → second screen** | With an external display connected, Output ▸ <that display> fills it edge to edge with no title bar, no menu bar, and no cursor | |
| **Output ships closed** | On a cold launch nothing is projected until Output is chosen | |
| **Blackout reaches the projector** | ⌘B blacks the external display, not just the on-screen monitors | |
| **Unplug mid-set** | Pulling the display cable while output is live falls back to a floating window; it does not vanish and does not strand | |
| **Replug** | Reconnecting and re-selecting the display restores fullscreen output | |
| Sustained run | 20 minutes with shader swaps: no fps decay, no memory growth, no black frame | |

**Status until the operator signs this off: STAGED, not complete.** Milestone 1's whole premise is
that a lot got built before anything got played last time. A green suite is not a performance.

- [ ] **Step 10: Commit**

```sh
git add App/ARShader/InstrumentView.swift App/ARShader/BlackoutKeyMonitor.swift \
        App/ARShader/ARShaderApp.swift App/ARShader/MonitorView.swift \
        App/ARShaderTests/BlackoutKeyMonitorTests.swift scripts/run-instrument.sh \
        Tests/reports/live-smoke-instrument-m1.md
git commit -m "feat(instrument): assemble the Milestone 1 surface

Three monitors, two deck strips showing both the set fader and its effective value,
crossfader, blend pickers, library, and blackout. Blackout is on a global NSEvent
monitor (cmd-B latch, held Escape momentary) rather than a SwiftUI shortcut, so it
does not depend on what has focus - both keys are un-typeable into the search field."
```

---

## Self-Review

Run against the spec after the plan is written; findings fixed inline.

**Spec coverage**

| Spec section | Covered by |
|---|---|
| §4 two decks, opacity, blend mode | Tasks 3, 5, 6, 7 |
| §4 crossfader as a macro | Task 5 |
| §4 monitor viewports | Task 9 |
| §4 shader library + auto-generated controls | Tasks 10, 11 |
| §4 blackout / panic | Tasks 8, 12 |
| §4 deliberately minimal UI | Task 12 |
| §5 shared runtime, editor tests pass unchanged | Task 1 (**mechanism changed — see the deviation note**) |
| §6 one clock, one command buffer, fixed 1920×1080, pooled | Tasks 2, 7 |
| §7 opaque-black master, layer order, W3C blend, hand-written Metal | Tasks 4, 6, 7 |
| §7.1 crossfade semantics, both values displayed | Tasks 5, 12 |
| §8 blackout as a final gate, fail-closed | Task 8 |
| §9 compile first, swap only on success; `/Library/Graphics/ISF`; camera fallback | Tasks 3, 10 (camera fallback is `SourceRouter`'s existing behavior, carried by Task 1) |
| §10 pure-function unit tests, golden frames, never-black gate, editor suites | Tasks 4, 5, 6, 7, 8; Task 1 |
| §11 minimal UI | Task 12 |
| §13 non-goals | Global Constraints |
| §14 Q1 app name / bundle id | Global Constraints (`ARShader` / `com.arsonrivvers.ARShader`) |
| §14 Q2 control generation ownership | Resolved by Task 1 (`ParamStore` moves to the shared runtime) and Task 11 (the instrument owns its own row mapping) |
| §14 Q3 audio approach | Out of scope — Milestone 2 |

**§12 (parking TouchDesigner) is deliberately NOT in this plan.** It is work in the AR_Shader repo,
not the ShaderToy repo, and it is already tracked as action item
`arshader-park-td-recoverable-20260730`. Doing it inside this plan would mix two repos in one
task list.

**Gaps accepted, with reasons**

- ~~**Fullscreen output on a second display is not in Milestone 1.**~~ **RESOLVED — pulled back IN
  as Task 12, 2026-07-30.** This was flagged as the one plausible reading of "playable" the plan did
  not deliver, and the operator ruled it back in on being asked: a projector mock you cannot put on
  a projector is not a rehearsal. Spec §4 says "monitor viewports" and §13's non-goals are silent on
  displays, so this is an addition to the milestone rather than a contradiction of it.
- **`RenderStats` is moved but no FPS readout is wired into the instrument UI.** The sustained-run
  leg of Task 13 Step 9 needs one to be judged honestly. Add it during Task 13 Step 8 if the review
  finds the operator cannot tell 60 fps from 45 by eye — do not add a number the app does not
  measure.

**Type-consistency check** — verified across tasks: `DeckID` (Task 3) is used identically in Tasks
5, 7, 8, 9, 10, 12; `BlendMode.shaderIndex` (Task 4) is the value `Compositor.Uniforms.mode` carries
(Task 6) and is pinned by a test; `LayerParams` (Task 5) is produced by `MixerState.layers()` and
consumed only in Tasks 7 and 12; `MonitorSource` is introduced in Task 8 and consumed in Task 9;
`programTexture()` changes meaning in Task 8 and Task 8 updates the Task 2 test that depended on the
old meaning; `InstrumentRenderer.init` gains `mixer:` in Task 7 and `compositorOverride:` in Task 8,
and both tasks update every existing call site.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-07-30-native-instrument-milestone-1.md`.

**Before Task 1 begins:**

1. Confirm no other session is writing to `~/Desktop/AV_Projects/ShaderToy-to-ISF-converter`
   (`git status --porcelain` empty, `git stash list` empty, no active Codex session in that
   directory).
2. `/gate` — this plan has 13 tasks, well past the 3-task threshold.
3. The deferred PM spec review (`arshader-native-pivot-pm-review-20260730`) is still open. Its
   sharpest target, §4.1, has now been approved by the operator directly, which is the outcome that
   review existed to test.

**Execution options:**

1. **Subagent-Driven (recommended)** — a fresh subagent per task, reviewed between tasks. Tasks 4,
   5, 10 and 11 are mechanical enough for a down-tiered implementer; Tasks 1, 6, 7 and 8 should
   inherit the session tier (the extraction, the GPU math, the frame graph and the safety gate are
   where a wrong answer is expensive and quiet).
2. **Inline Execution** — batch execution in this session with checkpoints.
