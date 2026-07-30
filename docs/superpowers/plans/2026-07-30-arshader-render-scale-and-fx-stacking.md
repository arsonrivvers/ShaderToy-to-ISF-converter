# ARShader Render Scale + Stacked FX Chains — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the instrument a typed render-scale lever for both live and cued decks, measure the reported FPS gap with it, then add unbounded stacked FX chains per deck and on the program output.

**Architecture:** Part A replaces the `CueQuality` enum with a typed `RenderScale` applied to live decks and the master composite as well as cued decks, then uses it to measure. Part B extracts a shared `ShaderUnit` from `Deck`, adds `FXStage`/`FXChain`, and encodes each chain as a ping-pong between the consumer's owned texture and one scratch texture — with `Compositor.encodeLayer` serving as both the required pool-copy and the per-stage mix.

**Tech Stack:** Swift 5, SwiftUI, Metal, XCTest, ISFMSLKit/VVMetalKit (vendored `.framework`s), xcodegen.

**Spec:** `docs/superpowers/specs/2026-07-30-arshader-render-scale-and-fx-stacking-design.md`

> **STATUS: COMPLETE.** Tasks 1–12 all landed (`a10de95..63ed737`). Live smoke:
> `docs/reports/live-smoke-instrument-m2-phase2.md`.
>
> **Where this document is stale, and it bit during execution:**
> - Task 3 and Task 4 say **RENDER SCALE**; the shipped control is **PREVIEW SCALE**.
> - Task 5 Step 3 says to create `App/ISFRuntime/ShaderUnit.swift`, contradicting its own Files
>   header and the File Structure table. `App/ARShader/` is correct — `project.yml` excludes
>   `ParamStore` from `TrueISFEditorTests`.
> - Task 5 Step 7 expects 134 tests, Task 7 expects 146, and so on; every count downstream of the
>   render-scale session is low. Final: **181**.
> - Task 7's `FXStage` calls an initialiser Task 7.5 creates, and Task 7.5's first test calls
>   `encode` from Task 8. Executed in the order model → binding → encode.
> - Task 7's `FXStage.apply` is `fileprivate` while `FXChain` lives in another file — as written it
>   cannot compile. Shipped `internal` with the invariant documented.
> - Task 9's `masterFX` cannot be a property default (`FXChain.init` is `@MainActor`).
> - Task 9's `testTheMasterChainStillUsesOneCommandBuffer` asserts the retired one-buffer
>   invariant; shipped as `testAMasterChainOfManyStagesAddsNoCommandBuffers`.
> - Task 10's `.onMove` is inert outside a `List`; dropped rather than shipped as a dead
>   affordance. The ▲▼ buttons reorder.
> - The operator's **input-source dropdown** is in the hand-off as "folded into Task 10" but appears
>   nowhere in this plan or the spec. Built separately (`89ad29b`, reworked in `a98c44f`).

## Global Constraints

- **Nothing on the render path is `@MainActor`.** `MainActor.assumeIsolated` must appear nowhere — it is a runtime assertion and traps (`dispatch_assert_queue_fail`) off-actor. Use `@unchecked Sendable` + one coarse `NSLock`, per `MetalRenderCore` and `InstrumentRenderer`.
- ~~**One command buffer per frame.** No stage commits its own buffer. `FrameGraphTests.testFrameUsesASingleCommandBuffer` pins this.~~ **RETIRED 2026-07-30.** Per-element GPU metering commits **one buffer per ELEMENT** (each deck, then the master) because `supportsCounterSampling(.atBlitBoundary)` is false on Apple M5 Max, and metering is ON by default. `testFrameUsesASingleCommandBuffer` was deleted. **What survives:** no stage commits its own buffer, and the count is bounded by the ELEMENT count — never by pass count or chain depth. Pinned by `testFrameStillEncodesNoReadbackAndCommitsPerElementOnly` and `testAMasterChainOfManyStagesAddsNoCommandBuffers`. This note exists because Task 9 Step 1 was written against the retired invariant and shipped a test asserting a delta of ONE buffer; it had to be rewritten on arrival.
- **Never black.** Every failure path passes the previous image through or falls to the existing opaque-black master; no path introduces a new way to lose output.
- **Blackout stays the final gate.** `programTexture()` returning nil is the panic path; nothing may sit between it and darkness.
- **Never display a number the engine did not measure.** No per-chain milliseconds.
- **Files are added by directory.** `App/project.yml` uses `- path: ISFRuntime` / `- path: ARShader`, so new files in those directories are picked up by `xcodegen generate`. Never hand-edit `App/TrueISFEditor.xcodeproj/project.pbxproj` — it is generated.
- **`ISFRuntime/` compiles into BOTH apps.** Anything placed there also builds into TrueISFEditor. Instrument-only concepts (mix, blend, chains) go in `App/ARShader/`.
- **Test command** (used by every task):
  ```bash
  cd /Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/App && xcodegen generate >/dev/null && cd .. && \
  xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -30
  ```
- **`scripts/run-instrument.sh` QUITS the running app before installing.** Never run it while the operator is playing without asking first.
- **Binary freshness** before any "relaunch" claim: grep an **ASCII** marker >15 chars from the last edit in the staged binary. `strings` cannot see literals containing multi-byte glyphs.
- **Regression baseline:** ARShaderTests 124, TrueISFEditor 514 (3 skipped), ShadertoyISFKit 312. Part B changes shared runtime files, so TrueISFEditor's suite must be re-run at Task 5 and Task 12.

---

## File Structure

**Part A**

| File | Responsibility |
|---|---|
| `App/ISFRuntime/RenderScale.swift` **(create)** | Typed clamped rasterisation percentage; `applied(to: RenderSize)` |
| `App/ISFRuntime/RenderSize.swift` **(modify)** | Delete `CueQuality` (used only by ARShader) |
| `App/ARShader/InstrumentRenderer.swift` **(modify)** | `outputRenderScale` + `cueRenderScale`; masters sized `output × renderScale`; deck owned size follows |
| `App/ARShader/InstrumentView.swift` **(modify)** | Two typed % fields with preset menus and resolved-size readouts |
| `App/ARShaderTests/RenderScaleTests.swift` **(create)** | Clamping, identity at 100%, aspect preservation |
| `App/ARShaderTests/FrameGraphTests.swift` **(modify)** | Scale reaches a LIVE deck; cue allocates nothing |

**Part B**

| File | Responsibility |
|---|---|
| `App/ARShader/ShaderUnit.swift` **(create)** | One hosted ISF shader: scene, params, image routing, compile state, load/unload/pulse. **NOT in `ISFRuntime`:** `project.yml:81` excludes `ParamStore.swift` from the `TrueISFEditorTests` target, so a shared `ShaderUnit` referencing `ParamStore` would fail to compile there. Nothing outside ARShader uses it. |
| `App/ISFRuntime/MetalRenderCore.swift` **(modify)** | `renderOffscreen(size:in:primaryInput:)` — an externally supplied texture for the first image input |
| `App/ISFRuntime/SourceRouter.swift` **(modify)** | `updateInputs(_:reservePrimary:)` — leave the first image input unrouted when the chain drives it |
| `App/ARShader/Deck.swift` **(modify)** | `ShaderUnit` + owned output + scratch + `FXChain` |
| `App/ARShader/Compositor.swift` **(modify)** | `preserveAlpha` uniform — opaque for the master, preserving mid-chain |
| `App/ARShader/FXStage.swift` **(create)** | One stage: unit + enabled + mix + blend |
| `App/ARShader/FXChain.swift` **(create)** | Ordered stages, render-thread mirror, ping-pong `encode` |
| `App/ARShader/InstrumentRenderer.swift` **(modify)** | `masterFX` chain at frame-graph step 4 |
| `App/ARShader/ShaderControlsView.swift` **(create, from `DeckControlsView.swift`)** | Generated controls for any `ShaderUnit` |
| `App/ARShader/FXChainView.swift` **(create)** | Stage list: on/off, Mix, blend, ▲▼, ✕, drag, disclosure, budget hint |
| `App/ARShader/InstrumentView.swift` **(modify)** | Third strip: A \| B \| MASTER |
| `App/ARShader/LibraryPanelView.swift` **(modify)** | `LibraryTarget` picker: Deck A · A FX · Deck B · B FX · Master FX |
| `App/ARShaderTests/Fixtures/invert_filter.fs` **(create)** | ISF filter fixture — inverts `inputImage` |
| `App/ARShaderTests/Fixtures/half_bright_filter.fs` **(create)** | ISF filter fixture — halves `inputImage` (non-commutative with invert) |
| `App/ARShaderTests/FXChainTests.swift` **(create)** | Ordering, skipping, mix, parity |
| `App/ARShaderTests/ShaderUnitTests.swift` **(create)** | Migrated `DeckTests` behaviours |

---

# PART A — Render Scale

### Task 1: `RenderScale` value type

**Files:**
- Create: `App/ISFRuntime/RenderScale.swift`
- Test: `App/ARShaderTests/RenderScaleTests.swift`

**Interfaces:**
- Consumes: `RenderSize` (`App/ISFRuntime/RenderSize.swift`) — `init(width:height:)`, `scaled(by:) -> RenderSize`, `megapixels`, `minDimension`
- Produces: `RenderScale(percent: Int)`, `.percent`, `.factor`, `.label`, `.applied(to: RenderSize) -> RenderSize`, `.full`, `.defaultRender`, `.defaultCue`, `.presets`

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/RenderScaleTests.swift`:

```swift
import XCTest

final class RenderScaleTests: XCTestCase {
    func testPercentClampsToTheSafeRange() {
        XCTAssertEqual(RenderScale(percent: 0).percent, RenderScale.minPercent)
        XCTAssertEqual(RenderScale(percent: -40).percent, RenderScale.minPercent)
        XCTAssertEqual(RenderScale(percent: 400).percent, RenderScale.maxPercent,
                       "Above 100% is supersampling — 4x the cost, deliberately out of scope")
    }

    func testFullScaleIsExactlyTheOutputSize() {
        let out = RenderSize(width: 1920, height: 1080)
        XCTAssertEqual(RenderScale.full.applied(to: out), out,
                       "100% must be identity — no rounding drift on the common path")
    }

    func testHalfScaleIsAQuarterOfThePixels() {
        let out = RenderSize(width: 1920, height: 1080)
        let half = RenderScale(percent: 50).applied(to: out)
        XCTAssertEqual(half.width, 960)
        XCTAssertEqual(half.height, 540)
        XCTAssertEqual(half.megapixels, out.megapixels / 4, accuracy: 0.01)
    }

    func testScalingPreservesAspectSoACuedDeckNeverStretches() {
        // A cued deck is faded INTO the program. A different aspect would stretch it at exactly
        // the wrong moment.
        let out = RenderSize(width: 1080, height: 1920)   // vertical, for LED columns
        let scaled = RenderScale(percent: 33).applied(to: out)
        XCTAssertEqual(Double(scaled.width) / Double(scaled.height),
                       Double(out.width) / Double(out.height), accuracy: 0.01)
    }

    func testTheMinimumScaleStillProducesARenderableSize() {
        let tiny = RenderScale(percent: RenderScale.minPercent)
            .applied(to: RenderSize(width: 1920, height: 1080))
        XCTAssertGreaterThanOrEqual(tiny.width, RenderSize.minDimension)
        XCTAssertGreaterThanOrEqual(tiny.height, RenderSize.minDimension)
    }

    func testDefaultsMatchTheSpec() {
        XCTAssertEqual(RenderScale.defaultRender.percent, 100, "live output is full quality")
        XCTAssertEqual(RenderScale.defaultCue.percent, 50, "a cued deck feeds only a small monitor")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the Global Constraints test command.
Expected: FAIL — `cannot find 'RenderScale' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `App/ISFRuntime/RenderScale.swift`:

```swift
import Foundation

/// A rasterisation scale, as a percentage of the output resolution.
///
/// Typed rather than picked from a fixed set, matching `RenderSize`: the operator types a number
/// and the presets are a convenience, not the vocabulary. Clamped in `init` so no path can ask for
/// a zero-pixel or a supersampled target.
///
/// Replaces `CueQuality`, a five-case enum that was applied ONLY to decks with zero effective
/// opacity — which made it inert on the live deck actually costing the frame (reported by the
/// operator 2026-07-30: 62.8 ms GPU with Cue already at 25%).
struct RenderScale: Equatable, Hashable, Codable, Sendable {
    /// Below this, a 1920-wide output rasterises under 100px and a cue image stops being judgeable.
    static let minPercent = 5
    /// The ceiling. Above 100% is supersampling — genuine free anti-aliasing at four times the
    /// cost — deliberately out of scope (spec §8).
    static let maxPercent = 100

    let percent: Int

    init(percent: Int) {
        self.percent = min(max(percent, Self.minPercent), Self.maxPercent)
    }

    var factor: Double { Double(percent) / 100.0 }

    var label: String { "\(percent)%" }

    /// The pixel size this scale resolves to. Identity at 100% so the common case allocates and
    /// rasterises exactly what the operator typed, with no rounding drift.
    func applied(to output: RenderSize) -> RenderSize {
        percent >= Self.maxPercent ? output : output.scaled(by: factor)
    }

    static let full = RenderScale(percent: 100)
    /// Live decks and the master composite: full quality until the operator decides otherwise.
    static let defaultRender = full
    /// A cued deck feeds only a small monitor. Half resolution is a QUARTER of the pixels.
    static let defaultCue = RenderScale(percent: 50)

    /// Offered in the presets menu. Typing any other value is equally valid.
    static let presets: [RenderScale] = [100, 75, 50, 33, 25, 10].map { RenderScale(percent: $0) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the test command. Expected: PASS, and the pre-existing 124 still green.

- [ ] **Step 5: Commit**

```bash
git add App/ISFRuntime/RenderScale.swift App/ARShaderTests/RenderScaleTests.swift
git commit -m "feat(perf): a typed render scale, replacing the cue-quality enum"
```

---

### Task 2: Apply the scales in the frame graph

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift` (lines 61-68, 100-136, 195-223)
- Modify: `App/ISFRuntime/RenderSize.swift` (delete `CueQuality`, lines 52-83)
- Test: `App/ARShaderTests/FrameGraphTests.swift`

**Interfaces:**
- Consumes: `RenderScale` from Task 1
- Produces: `InstrumentRenderer.outputRenderScale: RenderScale` (reallocates masters), `InstrumentRenderer.cueRenderScale: RenderScale` (allocates nothing). `cueRenderQuality` and the type `CueQuality` are **deleted**.

- [ ] **Step 1: Write the failing tests**

Append to `App/ARShaderTests/FrameGraphTests.swift`:

```swift
    // MARK: render scale

    func testRenderScaleResizesTheMaster() throws {
        renderer.outputResolution = RenderSize(width: 1920, height: 1080)
        renderer.outputRenderScale = RenderScale(percent: 50)
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 960)
        XCTAssertEqual(tex.height, 540)
    }

    func testRenderScaleAppliesToALiveDeckNotJustACuedOne() throws {
        // The whole point of replacing CueQuality: it was applied ONLY when effectiveOpacity was
        // zero, so it was inert on the live deck costing the frame.
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0             // deck 1 LIVE at full opacity
        renderer.outputRenderScale = RenderScale(percent: 25)
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.deckTexture(.one))
        XCTAssertEqual(tex.width, 480, "a live deck must follow the render scale")
    }

    func testCueScaleAllocatesNothing() throws {
        // Cue changes only how many pixels are rasterised before upscaling into the EXISTING owned
        // texture. That is exactly why it is safe to drop very low.
        try load(.one, "solid_red")
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.deckTexture(.one))
        renderer.cueRenderScale = RenderScale(percent: 10)
        renderer.renderFrame()
        XCTAssertTrue(try XCTUnwrap(renderer.deckTexture(.one)) === before)
    }

    func testACuedDeckKeepsAFullSizeOwnedTextureAndStaysVisible() throws {
        // Rasterise small, upscale into a fixed owned texture — so starting a fade reallocates
        // nothing and cannot hitch at the worst moment.
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0             // deck 2 cued
        renderer.cueRenderScale = RenderScale(percent: 25)
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.deckTexture(.two))
        XCTAssertEqual(tex.width, renderer.outputResolution.width,
                       "the owned texture stays at the live size")
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: tex, device: device, queue: queue))
        let rgb = try XCTUnwrap(TestPixels.meanRGB(of: readback))
        XCTAssertEqual(rgb.y, 1.0, accuracy: 0.02, "and still shows green on its monitor")
    }

    func testTheInstrumentStillRendersCorrectlyAtAReducedRenderScale() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        renderer.outputRenderScale = RenderScale(percent: 50)
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
    }

    func testSettingTheSameRenderScaleIsANoOp() throws {
        renderer.renderFrame()
        let before = try XCTUnwrap(renderer.rawMasterTexture())
        renderer.outputRenderScale = renderer.outputRenderScale
        XCTAssertTrue(try XCTUnwrap(renderer.rawMasterTexture()) === before,
                      "A no-op set must not reallocate — the UI binds to this and writes freely")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `value of type 'InstrumentRenderer' has no member 'outputRenderScale'`.

- [ ] **Step 3: Implement**

In `App/ARShader/InstrumentRenderer.swift`, replace the `cueQuality` stored property:

```swift
    /// What live decks AND the master composite rasterise at, as a fraction of the output
    /// resolution. The instrument's one real GPU lever: the ISF render is where essentially all
    /// the cost is.
    private var renderScale: RenderScale = .defaultRender
    /// What a deck rasterises at while it is NOT contributing to program. It feeds only a small
    /// monitor there, so this can go much lower than the live scale.
    private var cueScale: RenderScale = .defaultCue
```

Replace `makeMaster`'s call sites with a pair helper and add it beside `makeMaster`:

```swift
    private static func makeMasterPair(device: MTLDevice, resolution: RenderSize) -> [MTLTexture] {
        (0..<2).compactMap { _ in makeMaster(device: device, resolution: resolution) }
    }
```

In `init`, replace the masters line:

```swift
        masters = Self.makeMasterPair(
            device: device, resolution: RenderScale.defaultRender.applied(to: .default))
```

Replace the `outputResolution` setter body and the whole `cueRenderQuality` property with:

```swift
    /// The program-output resolution — what the projector and the typed W×H mean. Reallocates the
    /// master pair; a no-op if unchanged, so the UI can bind to it freely.
    var outputResolution: RenderSize {
        get { lock.lock(); defer { lock.unlock() }; return masterResolution }
        set {
            lock.lock()
            guard newValue != masterResolution else { lock.unlock(); return }
            masterResolution = newValue
            reallocateMastersLocked()
            lock.unlock()
        }
    }

    /// What live decks and the master composite rasterise at. Reallocates the master pair (and,
    /// on the next frame, each deck's owned texture) — rare and operator-driven, never in a frame.
    var outputRenderScale: RenderScale {
        get { lock.lock(); defer { lock.unlock() }; return renderScale }
        set {
            lock.lock()
            guard newValue != renderScale else { lock.unlock(); return }
            renderScale = newValue
            reallocateMastersLocked()
            lock.unlock()
        }
    }

    /// What a deck rasterises at while it is NOT contributing. Allocates NOTHING: the deck draws
    /// small and upscales into its existing owned texture.
    var cueRenderScale: RenderScale {
        get { lock.lock(); defer { lock.unlock() }; return cueScale }
        set { lock.lock(); cueScale = newValue; lock.unlock() }
    }

    /// Requires `lock` held. Only swaps if BOTH allocated — a half-resized pair would composite
    /// across mismatched targets, and the failure would look like a corrupted image, not an error.
    private func reallocateMastersLocked() {
        let fresh = Self.makeMasterPair(device: device,
                                        resolution: renderScale.applied(to: masterResolution))
        if fresh.count == 2 {
            masters = fresh
            masterIndex = 0
        }
    }
```

In `renderFrame`, replace the snapshot block and the deck loop's size computation:

```swift
        let deckList = decks
        let outRes = masterResolution
        let liveRes = renderScale.applied(to: outRes)
        let cueRes = cueScale.applied(to: outRes)
        lock.unlock()
```

```swift
            let renderSize = (isLive ? liveRes : cueRes).size
            if let tex = deck.render(in: cb, renderSize: renderSize, ownedSize: liveRes.size) {
```

Delete the `CueQuality` enum from `App/ISFRuntime/RenderSize.swift` (its whole doc comment and body, from `/// How much of the output resolution a deck rasterises at...` to the closing brace).

- [ ] **Step 4: Fix the one UI call site so it compiles**

`App/ARShader/InstrumentView.swift` still binds the deleted `cueRenderQuality`. Replace the `Cue` `HStack` in `resolutionPickers` with a temporary stand-in; Task 3 builds the real surface:

```swift
            HStack {
                Text("Cue").font(.system(size: 11))
                Picker("", selection: Binding(
                    get: { instrument.renderer.cueRenderScale },
                    set: { instrument.renderer.cueRenderScale = $0 })) {
                    ForEach(RenderScale.presets, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
```

- [ ] **Step 5: Run tests to verify they pass**

Expected: PASS, 130 tests. Existing resolution tests still green.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/InstrumentRenderer.swift App/ISFRuntime/RenderSize.swift \
        App/ARShader/InstrumentView.swift App/ARShaderTests/FrameGraphTests.swift
git commit -m "feat(perf): render scale drives live decks and the master, not just cue"
```

---

### Task 3: The scale surface

**Files:**
- Modify: `App/ARShader/InstrumentView.swift` (`resolutionPickers`, ~lines 178-251)

**Interfaces:**
- Consumes: `InstrumentRenderer.outputRenderScale` / `.cueRenderScale` (Task 2), `RenderScale.presets`
- Produces: no new API — UI only.

- [ ] **Step 1: Add the field state**

Add beside the existing `@State private var widthField`:

```swift
    @State private var renderScaleField = ""
    @State private var cueScaleField = ""
```

- [ ] **Step 2: Replace `resolutionPickers`**

```swift
    /// Output resolution is the NOMINAL size — what the projector shows and what the typed W×H
    /// means. The two scales are what actually gets rasterised, and are the only real GPU lever:
    /// the ISF render is where essentially all the cost is, and monitors merely sample a texture
    /// that already exists.
    private var resolutionPickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("OUTPUT RES").font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Menu {
                    ForEach(RenderSize.presets, id: \.self) { preset in
                        Button(preset.label) { applyOutput(preset) }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Common sizes")
            }

            HStack(spacing: 4) {
                TextField("W", text: $widthField)
                    .textFieldStyle(.roundedBorder).frame(width: 62)
                    .onSubmit { commitTypedResolution() }
                Text("×").foregroundStyle(.secondary)
                TextField("H", text: $heightField)
                    .textFieldStyle(.roundedBorder).frame(width: 62)
                    .onSubmit { commitTypedResolution() }
                Button("Set") { commitTypedResolution() }.controlSize(.small)
            }
            .font(.system(size: 11, design: .monospaced))

            Text(String(format: "%.1f MP", instrument.renderer.outputResolution.megapixels))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)

            Divider()

            scaleField(title: "RENDER SCALE",
                       text: $renderScaleField,
                       current: instrument.renderer.outputRenderScale,
                       resolved: instrument.renderer.outputRenderScale
                           .applied(to: instrument.renderer.outputResolution),
                       caption: "rasterising",
                       help: "What live decks AND the program composite actually rasterise at. "
                           + "Output stays the size you typed — the projector upscales, so low "
                           + "values trade sharpness for GPU.",
                       apply: { instrument.renderer.outputRenderScale = $0 })

            scaleField(title: "CUE SCALE",
                       text: $cueScaleField,
                       current: instrument.renderer.cueRenderScale,
                       resolved: instrument.renderer.cueRenderScale
                           .applied(to: instrument.renderer.outputResolution),
                       caption: "cued decks",
                       help: "What a deck rasterises at while it is NOT on program. It only feeds "
                           + "a small monitor there, and this reallocates nothing — so it is safe "
                           + "to drop very low.",
                       apply: { instrument.renderer.cueRenderScale = $0 })
        }
        .onAppear { syncResolutionFields() }
    }

    /// A typed percentage with a presets menu and the pixel size it resolves to. The resolved size
    /// is shown because softness at low scale should be a number the operator set, not a surprise
    /// on a wall.
    private func scaleField(title: String,
                            text: Binding<String>,
                            current: RenderScale,
                            resolved: RenderSize,
                            caption: String,
                            help: String,
                            apply: @escaping (RenderScale) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Menu {
                    ForEach(RenderScale.presets, id: \.self) { preset in
                        Button(preset.label) { apply(preset); syncResolutionFields() }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton).frame(width: 22)
            }
            HStack(spacing: 4) {
                TextField("%", text: text)
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        // A field that is empty or nonsense keeps the current value rather than
                        // snapping to a default: losing a deliberately-set scale to a stray
                        // keystroke mid-set would be worse than ignoring the edit.
                        let parsed = Int(text.wrappedValue.trimmingCharacters(in: .whitespaces))
                        apply(RenderScale(percent: parsed ?? current.percent))
                        syncResolutionFields()
                    }
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("→ \(caption) \(resolved.label)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .help(help)
    }
```

- [ ] **Step 3: Extend `syncResolutionFields`**

```swift
    private func syncResolutionFields() {
        let r = instrument.renderer.outputResolution
        widthField = String(r.width)
        heightField = String(r.height)
        renderScaleField = String(instrument.renderer.outputRenderScale.percent)
        cueScaleField = String(instrument.renderer.cueRenderScale.percent)
    }
```

- [ ] **Step 4: Build and run tests**

Expected: PASS, 130. (This task is UI-only; its gate is the live capture in Task 4.)

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/InstrumentView.swift
git commit -m "feat(ui): typed render and cue scale fields with resolved-size readouts"
```

---

### Task 4: **GATE** — install, sweep, record

This is a measurement task, not a code task. Its output is a committed report.

- [ ] **Step 1: ASK BEFORE INSTALLING**

`scripts/run-instrument.sh` quits the running app. Ask the operator whether it is safe to reinstall now. Do not proceed without an answer.

- [ ] **Step 2: Build and install**

```bash
cd /Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter && ./scripts/run-instrument.sh
```

- [ ] **Step 3: Verify binary freshness (ASCII marker)**

```bash
grep -c "rasterising" ~/Applications/ARShader.app/Contents/MacOS/ARShader \
  || grep -rc "rasterising" ~/Applications/ARShader.app/Contents/
```
Expected: at least one hit. If zero, the binary is stale — do NOT tell the operator to relaunch.

- [ ] **Step 4: Sweep**

Load `AR_ChaosCubes_v04_beta.fs` onto Deck A, opacity 1.00, crossfader hard left (deck A live), OUTPUT RES `1920 × 1080`. Record **GPU ms** (not FPS) at RENDER SCALE 100 / 75 / 50 / 25.

- [ ] **Step 5: Record the result**

Create `docs/reports/render-scale-sweep-2026-07-30.md` with the four measurements, the pixel counts they correspond to, and the verdict:

- Cost falls roughly with pixel count → **no regression**; proceed to Part B.
- Cost does **not** scale → **stop.** Do not start Task 5. Bisect the frame graph under `superpowers:systematic-debugging` and report to the operator first.

- [ ] **Step 6: Commit**

```bash
git add docs/reports/render-scale-sweep-2026-07-30.md
git commit -m "docs(perf): render scale sweep — GPU ms against rasterised pixels"
```

---

# PART B — Stacked FX chains

**Do not begin until Task 4's verdict is "proceed".**

### Task 5: Extract `ShaderUnit` from `Deck`

This refactor has the exact shape of the Milestone 1 defect where `DeckStripView` stopped observing its model and froze at "—" while 104 tests stayed green. Its gate is a **live capture**, not a test pass.

**Files:**
- Create: `App/ARShader/ShaderUnit.swift` (**not** `ISFRuntime` — see File Structure)
- Modify: `App/ARShader/Deck.swift`, `App/ARShader/InstrumentView.swift`, `App/ARShader/DeckControlsView.swift`
- Test: `App/ARShaderTests/ShaderUnitTests.swift` (create), `App/ARShaderTests/DeckTests.swift` (update references)

**Interfaces:**
- Consumes: `MetalRenderCore`, `ParamStore`, `SourceRouter`, `ISFSceneLoader`, `ISFPreviewInput`, `RenderClock`
- Produces: `ShaderUnit(device:queue:clock:)`; `@Published` `shaderName`, `compileError`, `compileErrorLine`, `inputs`, `isLoading`; `onCompileFinished`; `load(url:)`, `load(source:name:)`, `unload()`, `pulseEvent(_:)`; `let params: ParamStore`; `let imageSources: SourceRouter`; `nonisolated let core: MetalRenderCore`; `nonisolated func renderOffscreen(size:in:) -> MTLTexture?`
- `Deck` keeps: `id`, `let unit: ShaderUnit`, `nonisolated func render(in:renderSize:ownedSize:compositor:)`, `let fx: FXChain` (added in Task 8)

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ShaderUnitTests.swift`:

```swift
import XCTest
import Metal

@MainActor
final class ShaderUnitTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var unit: ShaderUnit!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        unit = ShaderUnit(device: device, queue: queue, clock: RenderClock())
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func load(_ fixtureName: String) throws {
        let done = expectation(description: "compile \(fixtureName)")
        unit.onCompileFinished = { done.fulfill() }
        unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        unit.onCompileFinished = nil
    }

    func testASuccessfulLoadPublishesTheNameAndInputs() throws {
        try load("solid_red")
        XCTAssertEqual(unit.shaderName, "solid_red.fs")
        XCTAssertNil(unit.compileError)
    }

    func testAFailedCompileKeepsThePreviousShaderPlaying() throws {
        // On stage, the shader that is already up is the one thing you cannot afford to lose.
        try load("solid_red")
        try load("broken")
        XCTAssertNotNil(unit.compileError, "the failure must be reported")
        XCTAssertEqual(unit.shaderName, "solid_red.fs",
                       "and the previous shader must keep rendering")
    }

    func testUnloadClearsEverything() throws {
        try load("solid_red")
        unit.unload()
        XCTAssertNil(unit.shaderName)
        XCTAssertTrue(unit.inputs.isEmpty)
        XCTAssertNil(unit.compileError)
    }

    func testRenderOffscreenReturnsNilWithNoSceneLoaded() throws {
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(unit.renderOffscreen(size: MTLSize(width: 64, height: 64, depth: 1), in: cb),
                     "an empty unit contributes nothing — it does not paint black")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'ShaderUnit' in scope`.

- [ ] **Step 3: Create `ShaderUnit`**

Create `App/ISFRuntime/ShaderUnit.swift` by moving, verbatim, from `Deck.swift`: `params`, `imageSources`, all five `@Published` properties, `onCompileFinished`, `device`, `queue`, `core`, `compileQueue`, `loadGeneration`, `load(url:)`, `load(source:name:)`, `apply(_:name:generation:)`, `unload()`, `applyInput(_:_:)`, `pulseEvent(_:)`. Keep every existing comment — the compile-first-swap-only-on-success rationale is load-bearing.

Add at the top:

```swift
/// One hosted ISF shader: the compiled scene, its parameter values, its image-input routing, and
/// its compile state. Shared by `Deck` and `FXStage` — a deck is a unit with an owned output
/// texture and a layer position; an FX stage is a unit with a mix and a blend mode.
///
/// **Compile first, swap only on success.** A failed compile leaves the running shader playing and
/// reports the error. This is the opposite of the editor's behaviour (which drops the scene so the
/// author sees their mistake) and it is deliberate: on stage, the shader that is already up is the
/// one thing you cannot afford to lose.
///
/// `@MainActor` covers the `@Published` UI state ONLY. `renderOffscreen` is `nonisolated` because
/// the frame graph calls it from the display-link thread; it touches only `MetalRenderCore`, which
/// is already lock-guarded.
@MainActor
final class ShaderUnit: ObservableObject {
```

and, replacing `Deck`'s use of `core` directly:

```swift
    /// The render-thread half. `nonisolated` so the frame graph and `FXChain`'s snapshot can hold
    /// it without touching main-actor state; `MetalRenderCore` is `@unchecked Sendable` behind its
    /// own lock.
    nonisolated let core: MetalRenderCore

    /// Render this unit's scene into the caller's command buffer. Nil when nothing is loaded — the
    /// consumer treats that as "contributes nothing", never as black.
    nonisolated func renderOffscreen(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        core.renderOffscreen(size: size, in: cb)
    }
```

`init(device:queue:clock:)` does what `Deck.init` did minus `copyPass`:

```swift
    init(device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.device = device
        self.queue = queue
        self.imageSources = SourceRouter(device: device, queue: queue)
        self.core = MetalRenderCore(device: device, renderQueue: queue, clock: clock)
        core.imageRouter = imageSources
        // A fresh scene boots at header defaults; replay the operator's values over it.
        params.onSet = { [weak self] name, json in self?.applyInput(name, json) }
    }
```

- [ ] **Step 4: Reduce `Deck` to composition**

`Deck` keeps only `id`, `unit`, `device`, `copyPass`, `renderOwnedOutput`, `makeOutputTexture`, and `render(...)`. Delete everything moved. It is no longer `ObservableObject`.

```swift
/// One deck: a hosted shader (`ShaderUnit`) plus the things only a deck has — an owned output
/// texture that monitors read in a later command buffer, and a position in the layer stack.
@MainActor
final class Deck {
    let id: DeckID
    let unit: ShaderUnit

    private let device: MTLDevice
    private let copyPass: TextureCopyPass?
    nonisolated(unsafe) private var renderOwnedOutput: MTLTexture?

    init(id: DeckID, device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.id = id
        self.device = device
        self.unit = ShaderUnit(device: device, queue: queue, clock: clock)
        self.copyPass = TextureCopyPass(device: device,
                                        destinationFormat: InstrumentRenderer.masterFormat)
    }

    nonisolated func render(in cb: MTLCommandBuffer,
                            renderSize: MTLSize,
                            ownedSize: MTLSize) -> MTLTexture? {
        guard let engineTexture = unit.renderOffscreen(size: renderSize, in: cb) else { return nil }
        if renderOwnedOutput?.width != ownedSize.width
            || renderOwnedOutput?.height != ownedSize.height {
            renderOwnedOutput = Self.makeOutputTexture(device: device, size: ownedSize)
        }
        guard let owned = renderOwnedOutput, let copyPass else { return nil }
        copyPass.encode(from: engineTexture, to: owned, in: cb)
        return owned
    }
    // ... makeOutputTexture unchanged, plus the existing NOTE about no public accessor
}
```

- [ ] **Step 5: Retarget the views — the defect-shaped step**

`DeckControlsView` becomes `ShaderControlsView` in a new file `App/ARShader/ShaderControlsView.swift`, with `@ObservedObject var unit: ShaderUnit` replacing `@ObservedObject var deck: Deck`. Replace every `deck.` with `unit.` inside it. Delete `App/ARShader/DeckControlsView.swift` (move `DeckControlModel` across unchanged).

In `InstrumentView.swift`, `DeckStripView` must observe the **unit**, not the deck:

```swift
struct DeckStripView: View {
    let id: DeckID
    @ObservedObject var unit: ShaderUnit
    @ObservedObject var mixer: MixerState
```

and its construction site:

```swift
                DeckStripView(id: id, unit: instrument.deck(id).unit, mixer: mixer)
```

Replace `deck.isLoading` → `unit.isLoading`, `deck.unload()` → `unit.unload()`, `deck.shaderName` → `unit.shaderName`, and `DeckControlsView(deck: deck)` → `ShaderControlsView(unit: unit)`.

In `LibraryPanelView`, `instrument.deck(targetDeck).load(url:)` → `instrument.deck(targetDeck).unit.load(url:)`.

- [ ] **Step 6: Update `DeckTests`**

Every `deck.shaderName` / `.compileError` / `.inputs` / `.isLoading` / `.onCompileFinished` / `.load(` / `.unload()` / `.params` / `.imageSources` becomes `deck.unit.<same>`. Same in `FrameGraphTests.load(_:_:)` and `DeckControlsTests`.

- [ ] **Step 7: Run the full ARShader suite**

Expected: PASS, 134 (130 + 4 new).

- [ ] **Step 8: Run the TrueISFEditor suite (belt and braces — this task should not touch `ISFRuntime`)**

```bash
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -20
```
Expected: 514, 3 skipped — identical to baseline.

- [ ] **Step 9: LIVE CAPTURE GATE**

Ask before installing (Task 4 Step 1's rule). Then install, load a shader onto Deck A, and **capture a screenshot**. Confirm the deck strip shows the shader's **filename** and its generated controls — not "—". A green suite does not discharge this step; the Milestone 1 defect passed 104 tests.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: extract ShaderUnit so decks and FX stages host shaders the same way"
```

---

### Task 6: `Compositor.preserveAlpha`

**Files:**
- Modify: `App/ARShader/Compositor.swift`
- Test: `App/ARShaderTests/CompositorTests.swift`

**Interfaces:**
- Produces: `encodeLayer(source:backdrop:destination:opacity:mode:preserveAlpha:in:)` — `preserveAlpha` defaults to `false`, so every existing call site is unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `CompositorTests`, plus an alpha-capable helper:

```swift
    /// A solid colour with an explicit alpha — needed to prove alpha is carried, not invented.
    private func solid(_ rgb: SIMD3<Double>, alpha: Double, size: Int = 16) throws -> MTLTexture {
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
                                                           alpha: alpha)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        return tex
    }

    private func alphaOf(source: MTLTexture, backdrop: MTLTexture, opacity: Double,
                         preserveAlpha: Bool) throws -> Double {
        let dest = try blank()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        compositor.encodeLayer(source: source, backdrop: backdrop, destination: dest,
                               opacity: opacity, mode: .normal,
                               preserveAlpha: preserveAlpha, in: cb)
        cb.commit(); cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: dest, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanAlpha(of: readback))
    }

    func testMidChainMixPreservesAlphaInsteadOfForcingItOpaque() throws {
        // Forcing alpha to 1 is right for the master and WRONG mid-chain: it would silently make
        // any deck carrying an FX stage fully opaque and change how it composites, because layer
        // alpha is src.a * opacity.
        let src = try solid(SIMD3(1, 1, 1), alpha: 0.25)
        let back = try solid(SIMD3(0, 0, 0), alpha: 0.75)
        let mid = try alphaOf(source: src, backdrop: back, opacity: 1.0, preserveAlpha: true)
        XCTAssertEqual(mid, 0.25, accuracy: 0.01, "fully wet ⇒ the stage's own alpha")

        let dry = try alphaOf(source: src, backdrop: back, opacity: 0.0, preserveAlpha: true)
        XCTAssertEqual(dry, 0.75, accuracy: 0.01, "fully dry ⇒ the input's alpha, untouched")
    }

    func testTheMasterPathStillForcesAlphaOpaque() throws {
        let a = try alphaOf(source: try solid(SIMD3(1, 1, 1), alpha: 0.25),
                            backdrop: try solid(SIMD3(0, 0, 0), alpha: 0.3),
                            opacity: 0.5, preserveAlpha: false)
        XCTAssertEqual(a, 1.0, accuracy: 0.005,
                       "The master is opaque by contract — a stack that leaks alpha < 1 is how the "
                       + "TouchDesigner blackout gate silently failed")
    }

    func testPreservingAlphaDoesNotChangeTheColourResult() throws {
        // The RGB path must be bit-for-bit the same on both branches; only the alpha out differs.
        let src = try solid(SIMD3(0.75, 0.5, 0.25), alpha: 1.0)
        let back = try solid(SIMD3(0.25, 0.5, 0.75), alpha: 1.0)
        for mode in BlendMode.allCases {
            let dest1 = try blank(), dest2 = try blank()
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            compositor.encodeLayer(source: src, backdrop: back, destination: dest1,
                                   opacity: 0.6, mode: mode, preserveAlpha: false, in: cb)
            compositor.encodeLayer(source: src, backdrop: back, destination: dest2,
                                   opacity: 0.6, mode: mode, preserveAlpha: true, in: cb)
            cb.commit(); cb.waitUntilCompleted()
            let a = try XCTUnwrap(TestPixels.meanRGB(of: try XCTUnwrap(
                TextureReadback.managedCopy(of: dest1, device: device, queue: queue))))
            let b = try XCTUnwrap(TestPixels.meanRGB(of: try XCTUnwrap(
                TextureReadback.managedCopy(of: dest2, device: device, queue: queue))))
            XCTAssertEqual(a.x, b.x, accuracy: 0.005, "\(mode.rawValue) red")
            XCTAssertEqual(a.y, b.y, accuracy: 0.005, "\(mode.rawValue) green")
            XCTAssertEqual(a.z, b.z, accuracy: 0.005, "\(mode.rawValue) blue")
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — no `preserveAlpha` argument.

- [ ] **Step 3: Implement**

In `Compositor.swift`, extend `Uniforms` and the signature:

```swift
    private struct Uniforms {
        var opacity: Float
        var mode: Int32
        /// 0 = force alpha 1 (the master is opaque by contract).
        /// 1 = carry alpha through — required MID-CHAIN, where forcing opacity would change how a
        /// deck with FX stages composites into the master.
        var preserveAlpha: Int32
    }

    func encodeLayer(source: MTLTexture,
                     backdrop: MTLTexture,
                     destination: MTLTexture,
                     opacity: Double,
                     mode: BlendMode,
                     preserveAlpha: Bool = false,
                     in cb: MTLCommandBuffer) {
```

and inside, the uniform construction:

```swift
        var uniforms = Uniforms(opacity: Float(min(max(opacity, 0), 1)), mode: mode.shaderIndex,
                                preserveAlpha: preserveAlpha ? 1 : 0)
```

In the MSL, extend the struct and the fragment return:

```
    struct Uniforms { float opacity; int mode; int preserveAlpha; };
```

```
        float3 co = mix(cb, blended, a);
        // Master: opaque by contract. Mid-chain: the wet/dry mix of the two alphas, so a filter
        // that outputs partial alpha stays a partial layer instead of becoming opaque.
        float ao = (u.preserveAlpha != 0)
            ? mix(backTex.sample(s, v.uv).a, src.a, clamp(u.opacity, 0.0, 1.0))
            : 1.0;
        return float4(co, ao);
```

- [ ] **Step 4: Run to verify they pass** — Expected: PASS, 137.

- [ ] **Step 5: MUTATION TEST**

Temporarily hard-code `float ao = 1.0;`. Re-run `CompositorTests`.
Expected: `testMidChainMixPreservesAlphaInsteadOfForcingItOpaque` **FAILS**. Revert.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/Compositor.swift App/ARShaderTests/CompositorTests.swift
git commit -m "feat(mixer): preserve alpha mid-chain, force it opaque on the master"
```

---

### Task 7: `FXStage` and `FXChain` model

**Files:**
- Create: `App/ARShader/FXStage.swift`, `App/ARShader/FXChain.swift`
- Test: `App/ARShaderTests/FXChainTests.swift`

**Interfaces:**
- Consumes: `ShaderUnit` (Task 5), `BlendMode`, `MetalRenderCore`
- Produces:
  - `FXStage`: `id: UUID`, `let unit: ShaderUnit`, `private(set) var isEnabled/mix/blendMode`
  - `FXStageSnapshot`: `core: MetalRenderCore`, `mix: Double`, `blendMode: BlendMode`
  - `FXChain`: `stages: [FXStage]`, `append(_:)`, `remove(_ id: UUID)`, `move(from: IndexSet, to: Int)`, `moveUp(_:)`, `moveDown(_:)`, `setEnabled(_:for:)`, `setMix(_:for:)`, `setBlendMode(_:for:)`, `nonisolated func renderStages() -> [FXStageSnapshot]`

- [ ] **Step 1: Write the failing tests**

Create `App/ARShaderTests/FXChainTests.swift` (model half; the encode half arrives in Task 8):

```swift
import XCTest
import Metal

@MainActor
final class FXChainTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var chain: FXChain!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        chain = FXChain()
    }

    private func makeStage() -> FXStage {
        FXStage(device: device, queue: queue, clock: RenderClock())
    }

    func testAnEmptyChainPublishesNoRenderStages() {
        XCTAssertTrue(chain.renderStages().isEmpty)
    }

    func testAppendingAStagePublishesItToTheRenderThread() {
        chain.append(makeStage())
        XCTAssertEqual(chain.stages.count, 1)
        XCTAssertEqual(chain.renderStages().count, 1)
    }

    func testDisablingAStageWithdrawsItFromTheRenderThread() {
        let s = makeStage()
        chain.append(s)
        chain.setEnabled(false, for: s)
        XCTAssertEqual(chain.stages.count, 1, "it stays in the UI list")
        XCTAssertTrue(chain.renderStages().isEmpty, "but encodes nothing at all")
    }

    func testAZeroMixStageWithdrawsItselfToo() {
        let s = makeStage()
        chain.append(s)
        chain.setMix(0, for: s)
        XCTAssertTrue(chain.renderStages().isEmpty,
                      "paying for an invisible pass mid-set is worse than skipping it")
    }

    func testMixClampsToTheUnitInterval() {
        let s = makeStage()
        chain.append(s)
        chain.setMix(4.2, for: s)
        XCTAssertEqual(s.mix, 1.0)
        chain.setMix(-3, for: s)
        XCTAssertEqual(s.mix, 0.0)
    }

    func testRemoveDropsExactlyOneStage() {
        let a = makeStage(), b = makeStage()
        chain.append(a); chain.append(b)
        chain.remove(a.id)
        XCTAssertEqual(chain.stages.map(\.id), [b.id])
        XCTAssertEqual(chain.renderStages().count, 1)
    }

    func testMoveUpAndDownReorderAndClampAtTheEnds() {
        let a = makeStage(), b = makeStage()
        chain.append(a); chain.append(b)
        chain.moveUp(1)
        XCTAssertEqual(chain.stages.map(\.id), [b.id, a.id])
        chain.moveUp(0)
        XCTAssertEqual(chain.stages.map(\.id), [b.id, a.id], "already first — a no-op, not a crash")
        chain.moveDown(1)
        XCTAssertEqual(chain.stages.map(\.id), [b.id, a.id], "already last — a no-op")
        chain.moveDown(0)
        XCTAssertEqual(chain.stages.map(\.id), [a.id, b.id])
    }

    func testRenderOrderMatchesTheUIOrderAfterAReorder() {
        let a = makeStage(), b = makeStage()
        chain.append(a); chain.append(b)
        chain.moveUp(1)
        XCTAssertEqual(chain.renderStages().map { ObjectIdentifier($0.core) },
                       [ObjectIdentifier(b.unit.core), ObjectIdentifier(a.unit.core)],
                       "the render mirror must be republished on reorder, not just on append")
    }
}
```

- [ ] **Step 2: Run to verify they fail** — Expected: FAIL, `cannot find 'FXChain' in scope`.

- [ ] **Step 3: Create `FXStage`**

```swift
import Foundation

/// One stage in an FX chain: a hosted shader plus how much of it to apply and how to blend it
/// against what came before.
///
/// Mutation goes through `FXChain`, not through the stage — the chain owns the lock-protected
/// render mirror and must republish on every change, including changes to a stage's own fields.
@MainActor
final class FXStage: ObservableObject, Identifiable {
    let id = UUID()
    let unit: ShaderUnit

    /// Builds its own unit so a stage can never be constructed with a ROUTED primary input — the
    /// chain drives that slot (Task 7.5).
    init(device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.unit = ShaderUnit(device: device, queue: queue, clock: clock,
                               reservesPrimaryInput: true)
    }

    @Published private(set) var isEnabled = true
    /// Dry (0) to wet (1). At 0 the stage is skipped entirely — see FXChain.publishToRenderThread.
    @Published private(set) var mix: Double = 1.0
    /// How the stage's output is combined with its input. The same 19 modes the mixer uses.
    @Published private(set) var blendMode: BlendMode = .normal

    /// True when the shader declares NO image input — a generator, which REPLACES the feed rather
    /// than processing it. Marked in the UI so it is a usable move, not a mystery.
    /// Asks the SHADER, not the router: a filter stage's primary input is deliberately unrouted.
    var isGenerator: Bool { unit.inputs.allSatisfy { $0.type != "image" } }

    fileprivate func apply(isEnabled: Bool) { self.isEnabled = isEnabled }
    fileprivate func apply(mix: Double) { self.mix = min(max(mix, 0), 1) }
    fileprivate func apply(blendMode: BlendMode) { self.blendMode = blendMode }
}
```

- [ ] **Step 4: Create `FXChain` (model half)**

```swift
import Foundation
import Metal

/// One stage's contribution for a single frame — an immutable value the render thread reads.
/// `MetalRenderCore` is `@unchecked Sendable` behind its own lock, so this is safe to hand across.
struct FXStageSnapshot: @unchecked Sendable {
    let core: MetalRenderCore
    let mix: Double
    let blendMode: BlendMode
}

/// An ordered, unbounded stack of FX stages.
///
/// `@MainActor` covers the `@Published` UI state. The render thread never reads those properties:
/// it calls `renderStages()`, which reads a lock-protected mirror kept in sync by every mutation —
/// the same arrangement `MixerState` and `SourceRouter` use, and required for the same reason.
///
/// The mirror carries ONLY stages that will actually encode. A disabled stage, or one at zero mix,
/// is filtered out at publish time, so "skipped entirely" is a property of the data the render
/// thread sees rather than a branch it has to remember to take.
@MainActor
final class FXChain: ObservableObject {
    @Published private(set) var stages: [FXStage] = []

    private let renderLock = NSLock()
    nonisolated(unsafe) private var renderCache: [FXStageSnapshot] = []

    func append(_ stage: FXStage) {
        stages.append(stage)
        publishToRenderThread()
    }

    func remove(_ id: UUID) {
        stages.removeAll { $0.id == id }
        publishToRenderThread()
    }

    /// SwiftUI `onMove` (drag to reorder).
    func move(from source: IndexSet, to destination: Int) {
        stages.move(fromOffsets: source, toOffset: destination)
        publishToRenderThread()
    }

    /// Button reorder. Out-of-range and end-of-list moves are no-ops, never crashes — this runs
    /// under stage lighting.
    func moveUp(_ index: Int) {
        guard stages.indices.contains(index), index > 0 else { return }
        stages.swapAt(index, index - 1)
        publishToRenderThread()
    }

    func moveDown(_ index: Int) {
        guard stages.indices.contains(index), index < stages.count - 1 else { return }
        stages.swapAt(index, index + 1)
        publishToRenderThread()
    }

    func setEnabled(_ enabled: Bool, for stage: FXStage) {
        stage.apply(isEnabled: enabled)
        publishToRenderThread()
    }

    func setMix(_ mix: Double, for stage: FXStage) {
        stage.apply(mix: mix)
        publishToRenderThread()
    }

    func setBlendMode(_ mode: BlendMode, for stage: FXStage) {
        stage.apply(blendMode: mode)
        publishToRenderThread()
    }

    /// Republish after a stage finishes compiling — a stage whose scene just arrived must start
    /// encoding without waiting for an unrelated mutation.
    func stageDidChangeScene() { publishToRenderThread() }

    private func publishToRenderThread() {
        let snapshot = stages
            .filter { $0.isEnabled && $0.mix > 0 }
            .map { FXStageSnapshot(core: $0.unit.core, mix: $0.mix, blendMode: $0.blendMode) }
        renderLock.lock()
        renderCache = snapshot
        renderLock.unlock()
        objectWillChange.send()
    }

    // ── render thread ──

    /// The stages that will encode this frame, in order. Safe from the display-link thread.
    nonisolated func renderStages() -> [FXStageSnapshot] {
        renderLock.lock(); defer { renderLock.unlock() }
        return renderCache
    }
}
```

- [ ] **Step 5: Run to verify they pass** — Expected: PASS, 146.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/FXStage.swift App/ARShader/FXChain.swift App/ARShaderTests/FXChainTests.swift
git commit -m "feat(fx): the FX chain model and its render-thread mirror"
```

---

### Task 7.5: Feed the chain into a stage's primary image input

Without this, a stage's `inputImage` is bound by `SourceRouter` to the **camera** — not to the previous stage — and `updateInputs` opens a capture session per stage. Both changes are additive with defaults, so the deck path and the editor are untouched.

**Files:**
- Modify: `App/ISFRuntime/MetalRenderCore.swift` (`renderOffscreen`), `App/ISFRuntime/SourceRouter.swift` (`updateInputs`), `App/ARShader/ShaderUnit.swift`
- Test: `App/ARShaderTests/FXChainTests.swift`

**Interfaces:**
- Produces: `MetalRenderCore.renderOffscreen(size:in:primaryInput:)` (`primaryInput` defaults to `nil`); `SourceRouter.updateInputs(_:reservePrimary:)` (defaults `false`); `ShaderUnit.init(device:queue:clock:reservesPrimaryInput:)` (defaults `false`); `ShaderUnit.renderOffscreen(size:in:primaryInput:)`

- [ ] **Step 1: Write the failing test**

```swift
    func testAStageReadsTheChainFeedNotItsRoutedSources() throws {
        // Without an explicit primary input, MetalRenderCore binds EVERY image input from the
        // SourceRouter — so `inputImage` would be the camera and the chain feed would never
        // reach the shader. Inverting a known red input is the cheapest proof it arrived.
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.y, 1.0, accuracy: 0.03,
                       "the stage must invert the CHAIN input, not a routed camera frame")
    }

    func testAFilterStageLeavesItsPrimaryInputUnrouted() throws {
        // A stage must not open a camera session for an input the chain already drives.
        let stage = try loadedStage("invert_filter")
        XCTAssertEqual(stage.unit.imageSources.selection(for: "inputImage"), .none,
                       "the chain feeds this input; the router must not claim it")
    }
```

- [ ] **Step 2: Run to verify they fail**

Expected: the first FAILS (output is not the inverted chain feed); the second FAILS (selection is `.camera`).

- [ ] **Step 3: Implement `primaryInput` in `MetalRenderCore`**

Replace the input-binding loop in `renderOffscreen`:

```swift
    /// Render the current scene into the CALLER's command buffer and return the engine's output
    /// texture. Does NOT commit — the instrument encodes an entire frame into one buffer.
    ///
    /// `primaryInput`, when given, is bound to the FIRST image input instead of consulting the
    /// router: that is how an FX stage receives the previous stage's output. Every other image
    /// input still routes normally, so a two-input filter keeps its secondary source.
    func renderOffscreen(size: MTLSize, in cb: MTLCommandBuffer,
                         primaryInput: MTLTexture? = nil) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        guard let scene else { return nil }
        for (index, name) in imageInputNames.enumerated() {
            if index == 0, let primaryInput,
               let val = ISFMSLSceneVal.create(with: primaryInput) as? ISFMSLSceneVal {
                scene.setValue(val, forInputNamed: name)
                continue
            }
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
```

- [ ] **Step 4: Implement `reservePrimary` in `SourceRouter`**

```swift
    /// Called by the engine on each successful compile. Adds defaults for new image inputs and
    /// prunes routes for inputs that no longer exist.
    ///
    /// `reservePrimary` marks the FIRST image input as externally driven — an FX stage's chain
    /// feed. That input gets no route and no default, so a stage never opens a camera session for
    /// a slot the chain already fills.
    func updateInputs(_ inputs: [ISFPreviewInput], reservePrimary: Bool = false) {
        let names = inputs.filter { $0.type == "image" }.map { $0.name }
        imageInputNames = names
        let nameSet = Set(names)
        selections = selections.filter { nameSet.contains($0.key) }
        sources = sources.filter { nameSet.contains($0.key) }
        for n in names where selections[n] == nil {
            if reservePrimary && n == names.first {
                selections[n] = .none        // the chain drives this one
                continue
            }
            let sel: SourceSelection = (!reservePrimary && n == names.first)
                ? .camera
                : .testPattern(id: Self.secondaryDefaultPattern)
            selections[n] = sel
            sources[n] = makeSource(sel)
        }
    }
```

- [ ] **Step 5: Thread it through `ShaderUnit`**

```swift
    /// True when this unit's first image input is fed externally (an FX stage's chain feed) rather
    /// than routed. Decks are false: their shader's inputs are the operator's to route.
    private let reservesPrimaryInput: Bool

    init(device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock,
         reservesPrimaryInput: Bool = false) {
        self.reservesPrimaryInput = reservesPrimaryInput
        // ... rest unchanged
    }

    nonisolated func renderOffscreen(size: MTLSize, in cb: MTLCommandBuffer,
                                     primaryInput: MTLTexture? = nil) -> MTLTexture? {
        core.renderOffscreen(size: size, in: cb, primaryInput: primaryInput)
    }
```

and in `apply(_:name:generation:)`:

```swift
        imageSources.updateInputs(result.inputs, reservePrimary: reservesPrimaryInput)
```

`FXStage`'s unit is built with `reservesPrimaryInput: true`; `Deck`'s stays default.

- [ ] **Step 6: Correct `FXStage.isGenerator`**

The router no longer reports a reserved primary, so ask the shader, not the router:

```swift
    /// True when the shader declares NO image input — a generator, which REPLACES the feed rather
    /// than processing it.
    var isGenerator: Bool { unit.inputs.allSatisfy { $0.type != "image" } }
```

- [ ] **Step 7: Run the ARShader suite** — Expected: PASS.

- [ ] **Step 8: Run the TrueISFEditor suite — `MetalRenderCore` and `SourceRouter` are SHARED**

Expected: 514 (3 skipped), identical to baseline. Both changes are additive with defaults, so any failure here means a default was not preserved.

- [ ] **Step 9: Commit**

```bash
git add App/ISFRuntime/MetalRenderCore.swift App/ISFRuntime/SourceRouter.swift \
        App/ARShader/ShaderUnit.swift App/ARShader/FXStage.swift App/ARShaderTests/FXChainTests.swift
git commit -m "feat(fx): bind a stage's primary image input to the chain feed"
```

---

### Task 8: Chain encoding and deck wiring

**Files:**
- Modify: `App/ARShader/FXChain.swift` (add `encode`), `App/ARShader/Deck.swift`, `App/ARShader/InstrumentRenderer.swift`
- Create: `App/ARShaderTests/Fixtures/invert_filter.fs`, `App/ARShaderTests/Fixtures/half_bright_filter.fs`
- Test: `App/ARShaderTests/FXChainTests.swift`

**Interfaces:**
- Produces: `FXChain.encode(input:scratch:renderSize:compositor:preserveAlpha:in:) -> MTLTexture`; `Deck.render(in:renderSize:ownedSize:compositor:)`; `Deck.fx: FXChain`

- [ ] **Step 1: Create the filter fixtures**

`App/ARShaderTests/Fixtures/invert_filter.fs`:

```glsl
/*{
    "DESCRIPTION": "Test fixture: inverts its input.",
    "CREDIT": "ARShader tests",
    "ISFVSN": "2.0",
    "CATEGORIES": ["Test"],
    "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ]
}*/

void main() {
    vec4 c = IMG_THIS_PIXEL(inputImage);
    gl_FragColor = vec4(1.0 - c.rgb, c.a);
}
```

`App/ARShaderTests/Fixtures/half_bright_filter.fs`:

```glsl
/*{
    "DESCRIPTION": "Test fixture: halves its input. Non-commutative with invert.",
    "CREDIT": "ARShader tests",
    "ISFVSN": "2.0",
    "CATEGORIES": ["Test"],
    "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ]
}*/

void main() {
    vec4 c = IMG_THIS_PIXEL(inputImage);
    gl_FragColor = vec4(c.rgb * 0.5, c.a);
}
```

- [ ] **Step 2: Write the failing tests**

Add to `FXChainTests` (the encode half):

```swift
    // MARK: encoding

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A stage whose shader is compiled and ready.
    private func loadedStage(_ fixtureName: String) throws -> FXStage {
        let stage = makeStage()
        let done = expectation(description: "compile \(fixtureName)")
        stage.unit.onCompileFinished = { done.fulfill() }
        stage.unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        stage.unit.onCompileFinished = nil
        XCTAssertNil(stage.unit.compileError, "fixture \(fixtureName) must compile")
        return stage
    }

    private func texture(_ rgb: SIMD3<Double>) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat, width: 64, height: 64, mipmapped: false)
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
        cb.commit(); cb.waitUntilCompleted()
        return tex
    }

    /// Run the chain over a solid input and read the mean colour of whatever it returns.
    private func runChain(input rgb: SIMD3<Double>) throws -> SIMD3<Double> {
        let input = try texture(rgb)
        let scratch = try texture(SIMD3(0, 0, 0))
        let compositor = try XCTUnwrap(Compositor(device: device))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let out = chain.encode(input: input, scratch: scratch,
                               renderSize: MTLSize(width: 64, height: 64, depth: 1),
                               compositor: compositor, preserveAlpha: true, in: cb)
        cb.commit(); cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: out, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testAnEmptyChainReturnsItsInputUntouched() throws {
        let out = try runChain(input: SIMD3(0.8, 0.2, 0.4))
        XCTAssertEqual(out.x, 0.8, accuracy: 0.02)
        XCTAssertEqual(out.y, 0.2, accuracy: 0.02)
        XCTAssertEqual(out.z, 0.4, accuracy: 0.02)
    }

    func testOneStageTransformsTheImage() throws {
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.x, 0.0, accuracy: 0.03, "red inverted is cyan")
        XCTAssertEqual(out.y, 1.0, accuracy: 0.03)
        XCTAssertEqual(out.z, 1.0, accuracy: 0.03)
    }

    func testTwoStagesApplyInOrderAndTheParityIsRight() throws {
        // Invert twice returns the original. This is the ping-pong parity test: if the swap is
        // wrong, an even-depth chain returns the wrong texture and this fails.
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(0.8, 0.2, 0.4))
        XCTAssertEqual(out.x, 0.8, accuracy: 0.03)
        XCTAssertEqual(out.y, 0.2, accuracy: 0.03)
        XCTAssertEqual(out.z, 0.4, accuracy: 0.03)
    }

    func testOddDepthAlsoReturnsTheRightTexture() throws {
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.y, 1.0, accuracy: 0.03, "three inverts is one invert")
    }

    func testADisabledStageIsSkippedEntirely() throws {
        let s = try loadedStage("invert_filter")
        chain.append(s)
        chain.setEnabled(false, for: s)
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.x, 1.0, accuracy: 0.03, "still red — the stage never ran")
    }

    func testMixHalfSitsBetweenDryAndWet() throws {
        let s = try loadedStage("invert_filter")
        chain.append(s)
        chain.setMix(0.5, for: s)
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.x, 0.5, accuracy: 0.04, "halfway between red and cyan")
        XCTAssertEqual(out.y, 0.5, accuracy: 0.04)
    }

    func testStageBlendModeApplies() throws {
        // Multiply against its own input: 0.5 * 0.5 = 0.25 on every channel.
        let s = try loadedStage("half_bright_filter")
        chain.append(s)
        chain.setBlendMode(.multiply, for: s)
        let out = try runChain(input: SIMD3(1, 1, 1))
        XCTAssertEqual(out.x, 0.5, accuracy: 0.04)
    }

    func testReorderingChangesTheResultForANonCommutativePair() throws {
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("half_bright_filter"))
        let first = try runChain(input: SIMD3(1, 0, 0))   // invert → (0,1,1), half → (0,0.5,0.5)
        chain.moveUp(1)
        let swapped = try runChain(input: SIMD3(1, 0, 0)) // half → (0.5,0,0), invert → (0.5,1,1)
        XCTAssertNotEqual(first.x, swapped.x, accuracy: 0.05,
                          "order must be real, not decorative")
    }
```

- [ ] **Step 3: Run to verify they fail** — Expected: FAIL, no `encode` member.

- [ ] **Step 4: Implement `FXChain.encode`**

Append to `FXChain.swift`, outside the class:

```swift
extension FXChain {
    /// Encode the whole chain into `cb`, ping-ponging between `input` and `scratch`.
    ///
    /// A chain only ever reads the IMMEDIATELY PREVIOUS stage, so a pair of textures covers any
    /// depth — the same argument that justifies the master ping-pong. Metal's automatic hazard
    /// tracking handles the write-after-read across passes within one command buffer.
    ///
    /// The mix pass is not an extra cost: every stage must copy its output out of the VVMTLPool
    /// texture the engine returns (the aliasing hazard documented on `TextureCopyPass`), and
    /// `encodeLayer` performs that copy while also applying the stage's mix and blend mode.
    ///
    /// Returns the texture holding the final result — `input` itself when nothing encoded.
    nonisolated func encode(input: MTLTexture,
                            scratch: MTLTexture,
                            renderSize: MTLSize,
                            compositor: Compositor,
                            preserveAlpha: Bool,
                            in cb: MTLCommandBuffer) -> MTLTexture {
        var source = input
        var target = scratch
        for stage in renderStages() {
            // `primaryInput: source` is what makes this a CHAIN: the stage's first image input is
            // the previous stage's result, not whatever its router would otherwise supply.
            // A transient render failure passes this stage's input through — never black.
            guard let produced = stage.core.renderOffscreen(size: renderSize, in: cb,
                                                            primaryInput: source) else {
                continue
            }
            compositor.encodeLayer(source: produced, backdrop: source, destination: target,
                                   opacity: stage.mix, mode: stage.blendMode,
                                   preserveAlpha: preserveAlpha, in: cb)
            swap(&source, &target)
        }
        return source
    }
}
```

- [ ] **Step 5: Wire the deck chain**

In `Deck.swift`, add the chain and the scratch texture, and extend `render`:

```swift
    /// This deck's FX chain. Its output is what the deck contributes AND what its monitor shows —
    /// the operator cues the finished look.
    let fx = FXChain()

    /// The chain's ping-pong partner. Allocated alongside the owned output, so a chain of any
    /// depth costs exactly one extra texture per deck.
    nonisolated(unsafe) private var fxScratch: MTLTexture?
```

```swift
    nonisolated func render(in cb: MTLCommandBuffer,
                            renderSize: MTLSize,
                            ownedSize: MTLSize,
                            compositor: Compositor?) -> MTLTexture? {
        guard let engineTexture = unit.renderOffscreen(size: renderSize, in: cb) else { return nil }
        if renderOwnedOutput?.width != ownedSize.width
            || renderOwnedOutput?.height != ownedSize.height {
            renderOwnedOutput = Self.makeOutputTexture(device: device, size: ownedSize)
            fxScratch = Self.makeOutputTexture(device: device, size: ownedSize)
        }
        guard let owned = renderOwnedOutput, let copyPass else { return nil }
        copyPass.encode(from: engineTexture, to: owned, in: cb)
        guard let compositor, let scratch = fxScratch else { return owned }
        // Stages rasterise at the deck's CURRENT size, so a cued deck's chain is cheap too. The
        // mix pass writes into the owned-size targets and upscales by sampling.
        // preserveAlpha: the deck's contribution is a LAYER — forcing it opaque here would change
        // how it composites into the master.
        return fx.encode(input: owned, scratch: scratch, renderSize: renderSize,
                         compositor: compositor, preserveAlpha: true, in: cb)
    }
```

- [ ] **Step 6: Pass the compositor from the frame graph**

`InstrumentRenderer.compositor` is `private let`. In `renderFrame`, capture it before the deck loop and pass it:

```swift
            if let tex = deck.render(in: cb, renderSize: renderSize, ownedSize: liveRes.size,
                                     compositor: compositor) {
```

- [ ] **Step 7: Run to verify they pass** — Expected: PASS, 155.

- [ ] **Step 8: MUTATION TEST — ping-pong parity**

Temporarily delete the `swap(&source, &target)` line. Re-run `FXChainTests`.
Expected: `testTwoStagesApplyInOrderAndTheParityIsRight` and `testOneStageTransformsTheImage` **FAIL**. Restore.

- [ ] **Step 9: Commit**

```bash
git add App/ARShader/FXChain.swift App/ARShader/Deck.swift \
        App/ARShader/InstrumentRenderer.swift App/ARShaderTests/FXChainTests.swift \
        App/ARShaderTests/Fixtures/invert_filter.fs App/ARShaderTests/Fixtures/half_bright_filter.fs
git commit -m "feat(fx): encode deck chains as a ping-pong; the mix pass IS the pool copy"
```

---

### Task 9: The master FX chain

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift`
- Test: `App/ARShaderTests/FrameGraphTests.swift`

**Interfaces:**
- Produces: `InstrumentRenderer.masterFX: FXChain`

- [ ] **Step 1: Write the failing tests**

```swift
    // MARK: master FX

    private func loadedMasterStage(_ fixtureName: String) throws -> FXStage {
        let stage = FXStage(device: device, queue: queue, clock: RenderClock())
        let done = expectation(description: "compile \(fixtureName)")
        stage.unit.onCompileFinished = { done.fulfill() }
        stage.unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        stage.unit.onCompileFinished = nil
        return stage
    }

    func testAMasterFXStageProcessesTheProgramOutput() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        renderer.masterFX.append(try loadedMasterStage("invert_filter"))
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 0.0, accuracy: 0.03, "red inverted is cyan")
        XCTAssertEqual(rgb.y, 1.0, accuracy: 0.03)
    }

    func testAnEmptyMasterChainLeavesTheProgramUnchanged() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        let rgb = try renderAndRead()
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02)
    }

    func testBlackoutStillWinsOverTheMasterChain() throws {
        // The master chain runs at step 4, BEFORE the gate. Blackout withdraws the texture, so no
        // pipeline stands between the panic button and darkness.
        try load(.one, "solid_red")
        renderer.masterFX.append(try loadedMasterStage("invert_filter"))
        mixer.toggleBlackoutLatch()
        renderer.renderFrame()
        XCTAssertNil(renderer.programTexture(), "blackout withdraws the texture, chain or no chain")
    }

    func testTheMasterChainStillUsesOneCommandBuffer() throws {
        try load(.one, "solid_red")
        renderer.masterFX.append(try loadedMasterStage("invert_filter"))
        renderer.masterFX.append(try loadedMasterStage("half_bright_filter"))
        let before = renderer.committedBufferCount
        renderer.renderFrame()
        XCTAssertEqual(renderer.committedBufferCount - before, 1)
    }
```

- [ ] **Step 2: Run to verify they fail** — Expected: FAIL, no `masterFX`.

- [ ] **Step 3: Implement**

Add the property beside `decks`:

```swift
    /// The master FX chain: runs on the composited program feed, BEFORE the blackout gate. It
    /// needs no gate of its own and no new textures — it ping-pongs the existing master pair.
    let masterFX = FXChain()
```

In `renderFrame`, immediately after the layer-composite loop and before `masterIndex = current`:

```swift
        // 4. Master FX — ping-pongs the SAME master pair, so an unbounded chain here costs no
        //    additional memory. preserveAlpha is FALSE: the master is opaque by contract.
        if let compositor {
            let result = masterFX.encode(input: masters[current], scratch: masters[1 - current],
                                         renderSize: liveRes.size, compositor: compositor,
                                         preserveAlpha: false, in: cb)
            current = (result === masters[0]) ? 0 : 1
        }
```

`liveRes` must be visible here — it is captured before the first `lock.unlock()`; confirm it is still in scope at this point and hoist the `let` if not.

- [ ] **Step 4: Run to verify they pass** — Expected: PASS, 159.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/InstrumentRenderer.swift App/ARShaderTests/FrameGraphTests.swift
git commit -m "feat(fx): a master FX chain on the program feed, before the blackout gate"
```

---

### Task 10: The FX surface

**Files:**
- Create: `App/ARShader/FXChainView.swift`
- Modify: `App/ARShader/InstrumentView.swift`, `App/ARShader/LibraryPanelView.swift`
- Test: `App/ARShaderTests/LibraryPanelTests.swift`

**Interfaces:**
- Produces: `LibraryTarget` enum; `FXChainView(title:chain:stats:)`

- [ ] **Step 1: Write the failing test**

Add to `App/ARShaderTests/LibraryPanelTests.swift`:

```swift
    func testLibraryTargetsCoverEveryDeckAndEveryChain() {
        XCTAssertEqual(LibraryTarget.allCases.count, 5,
                       "two decks, two deck chains, one master chain")
        XCTAssertEqual(LibraryTarget.allCases.map(\.shortLabel),
                       ["A", "A FX", "B", "B FX", "MST FX"])
    }
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL, `cannot find 'LibraryTarget'`.

- [ ] **Step 3: Add `LibraryTarget`**

In `LibraryPanelView.swift`, above `LibrarySelection`:

```swift
/// Where a clicked library shader goes. Clicking loads onto a deck, or APPENDS a stage to a chain.
enum LibraryTarget: Hashable, CaseIterable, Identifiable {
    case deck(DeckID)
    case deckFX(DeckID)
    case masterFX

    static var allCases: [LibraryTarget] {
        [.deck(.one), .deckFX(.one), .deck(.two), .deckFX(.two), .masterFX]
    }

    var id: Self { self }

    /// Short enough for a five-way segmented picker in a 300pt panel.
    var shortLabel: String {
        switch self {
        case .deck(let d):   return d.displayName
        case .deckFX(let d): return "\(d.displayName) FX"
        case .masterFX:      return "MST FX"
        }
    }
}
```

- [ ] **Step 4: Retarget the picker and the click**

```swift
            Picker("Load onto", selection: $target) {
                ForEach(LibraryTarget.allCases) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
```

and the row action:

```swift
                Button {
                    load(entry.url)
                } label: { /* unchanged */ }
```

```swift
    /// A deck REPLACES its shader; a chain APPENDS a stage.
    private func load(_ url: URL) {
        switch target {
        case .deck(let id):
            instrument.deck(id).unit.load(url: url)
        case .deckFX(let id):
            append(url, to: instrument.deck(id).fx)
        case .masterFX:
            append(url, to: instrument.renderer.masterFX)
        }
    }

    private func append(_ url: URL, to chain: FXChain) {
        let stage = FXStage(device: instrument.device, queue: instrument.queue,
                            clock: instrument.renderer.clock)
        // Republish once the scene lands, so a stage starts encoding as soon as it compiles rather
        // than waiting for an unrelated mutation.
        stage.unit.onCompileFinished = { [weak chain] in chain?.stageDidChangeScene() }
        chain.append(stage)
        stage.unit.load(url: url)
    }
```

Change the binding type on `LibraryPanelView` from `@Binding var targetDeck: DeckID` to `@Binding var target: LibraryTarget`, and in `InstrumentView` change `@State private var libraryTarget: DeckID = .one` to `@State private var libraryTarget: LibraryTarget = .deck(.one)`.

- [ ] **Step 5: Create `FXChainView`**

```swift
import SwiftUI

/// One FX chain: an ordered, unbounded stack of stages.
///
/// Stage count is shown because it is a FACT the operator can act on. No per-chain milliseconds:
/// cost inside a single command buffer cannot be honestly attributed to one chain, and a number
/// the engine did not measure is not worth showing.
struct FXChainView: View {
    let title: String
    @ObservedObject var chain: FXChain
    @ObservedObject var stats: RenderStatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(chain.stages.count) FX")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(budgetColor)
                    .help(budgetHelp)
            }
            if chain.stages.isEmpty {
                Text("Load a shader with this chain selected in the library.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(chain.stages.enumerated()), id: \.element.id) { index, stage in
                FXStageRow(chain: chain, stage: stage, index: index)
            }
            .onMove { chain.move(from: $0, to: $1) }
        }
    }

    /// Amber/red track the MEASURED global frame time, never a per-chain estimate. A chain with no
    /// stages is never blamed for the frame.
    private var budgetColor: Color {
        guard chain.stages.count > 0, let fps = stats.stats?.fps else { return .secondary }
        if fps < 30 { return .red }
        if fps < 54 { return .orange }
        return .secondary
    }

    private var budgetHelp: String {
        "Stages in this chain. The colour tracks the measured frame rate for the whole "
        + "instrument — cost inside one command buffer cannot be attributed to a single chain."
    }
}

/// One stage row: on/off, name, Mix, blend, reorder, remove — and its generated controls behind a
/// disclosure triangle so a deep chain stays readable.
struct FXStageRow: View {
    @ObservedObject var chain: FXChain
    @ObservedObject var stage: FXStage
    let index: Int
    @State private var expanded = false

    init(chain: FXChain, stage: FXStage, index: Int) {
        self.chain = chain
        self.stage = stage
        self.index = index
        self._unit = ObservedObject(wrappedValue: stage.unit)
    }

    @ObservedObject private var unit: ShaderUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Toggle("", isOn: Binding(get: { stage.isEnabled },
                                         set: { chain.setEnabled($0, for: stage) }))
                    .labelsHidden().toggleStyle(.checkbox)
                    .help("Off skips this stage entirely — no render, no cost")
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                Text(unit.shaderName ?? (unit.isLoading ? "loading…" : "—"))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .help(unit.shaderName ?? "No shader")
                if stage.isGenerator {
                    Text("GEN").font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 3)
                        .background(.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                        .help("No image input — this shader REPLACES the feed rather than "
                              + "processing it. With Mix and a blend mode that is a usable move.")
                }
                Spacer()
                Button { chain.moveUp(index) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.plain).help("Move earlier in the chain")
                Button { chain.moveDown(index) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.plain).help("Move later in the chain")
                Button { chain.remove(stage.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Remove this stage")
            }
            HStack(spacing: 4) {
                Text("Mix").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { stage.mix },
                                      set: { chain.setMix($0, for: stage) }), in: 0...1)
                Text(String(format: "%.2f", stage.mix))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Picker("", selection: Binding(get: { stage.blendMode },
                                          set: { chain.setBlendMode($0, for: stage) })) {
                Section("Standard") {
                    ForEach(BlendMode.allCases.filter(\.isW3CSeparable)) {
                        Text($0.displayName).tag($0)
                    }
                }
                Section("Extended") {
                    ForEach(BlendMode.allCases.filter { !$0.isW3CSeparable }) {
                        Text($0.displayName).tag($0)
                    }
                }
            }
            .labelsHidden().controlSize(.small)
            if let error = unit.compileError {
                Text(error).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            if expanded {
                ShaderControlsView(unit: unit).frame(maxHeight: 220)
            }
            Divider()
        }
    }
}
```

- [ ] **Step 6: Add the third strip**

In `InstrumentView.deckStrips`:

```swift
    private var deckStrips: some View {
        HStack(spacing: 0) {
            ForEach(MixerState.layerOrder) { id in
                DeckStripView(id: id, unit: instrument.deck(id).unit, mixer: mixer,
                              fx: instrument.deck(id).fx, stats: stats)
                Divider()
            }
            masterStrip
        }
        .frame(minWidth: 620)
    }

    /// The master FX chain reads exactly like a deck chain — one mental model for both.
    private var masterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MASTER").font(.system(size: 12, weight: .bold, design: .monospaced))
            Text("Applied to the program feed, before blackout.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                FXChainView(title: "MASTER FX", chain: instrument.renderer.masterFX, stats: stats)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

and in `DeckStripView`, add `let fx: FXChain`, `@ObservedObject var stats: RenderStatsModel`, and put the chain below the blend picker:

```swift
            Divider()
            FXChainView(title: "FX", chain: fx, stats: stats)
            Divider()
            ShaderControlsView(unit: unit)
```

- [ ] **Step 7: Run tests** — Expected: PASS, 160.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(ui): FX chain strips, a master column, and library targets for both"
```

---

### Task 11: Full regression + live capture gate

- [ ] **Step 1: ARShaderTests** — expected 160, all green.
- [ ] **Step 2: TrueISFEditor** — expected 514 (3 skipped), identical to baseline.
- [ ] **Step 3: ShadertoyISFKit** — `swift test --package-path ShadertoyISFKit 2>&1 | tail -5`; expected 312.
- [ ] **Step 4: ASK, then install** via `scripts/run-instrument.sh`.
- [ ] **Step 5: Binary freshness** — grep an ASCII marker (`"No image input"` is >15 chars and ASCII).
- [ ] **Step 6: LIVE CAPTURE** — screenshot showing: a deck strip with an FX stage loaded and its name visible, the Mix slider, the master column, and the RENDER SCALE / CUE SCALE readouts.
- [ ] **Step 7: Commit** any fixes the capture surfaces.

---

### Task 12: Smoke report and hand-off

- [ ] **Step 1:** Write `docs/reports/live-smoke-instrument-m2-phase2.md` with legs stated as falsifiable hypotheses, following the Milestone 1 report's shape: chain applies, order matters, Mix dries out, blend per stage, disable costs nothing, master chain reaches the projector, blackout still wins, render scale visibly trades sharpness for GPU ms.
- [ ] **Step 2:** File deferred reviews as action items in `~/.claude/c-suite/inbox/action-items.json` (Client Success on the FX surface; the standing native-Swift exception makes Mechanic a manual review).
- [ ] **Step 3:** Commit.

---

## Self-Review

**Spec coverage.** §2 Render Scale → Tasks 1–3. §3.1 ping-pong → Task 8. §3.2 mix-is-the-copy + `preserveAlpha` → Tasks 6, 8. §3.3 frame graph step 4 → Task 9. §3.4 types → Tasks 5, 7. §3.5 threading → Task 7. §3.6 surface → Task 10. §3.7 budget indicator → Task 10 (`FXChainView.budgetColor`). §3.8 failure table → Tasks 7 (filtered mirror), 8 (`continue` on nil), 9 (blackout test). §5 testing → every task; both mutation tests at Tasks 6 and 8; both live captures at Tasks 5 and 11. §6 gate → Task 4. §7 process → Global Constraints.

**Placeholders.** None: every code step carries real code, every test step real assertions.

**Type consistency.** `RenderScale.applied(to:)` used identically in Tasks 1–3 and 2. `encodeLayer(...preserveAlpha:in:)` defined in Task 6 and called with that label in Tasks 8 and 9. `FXChain.encode(input:scratch:renderSize:compositor:preserveAlpha:in:)` defined in Task 8 and called with the same labels in Tasks 8 and 9. `ShaderUnit.core` declared `nonisolated let` in Task 5 and read by `FXStageSnapshot` in Task 7. `Deck.render(in:renderSize:ownedSize:compositor:)` gains its fourth argument in Task 8 and the call site is updated in the same task. `stageDidChangeScene()` defined in Task 7, called in Task 10.

**One deliberate ordering note.** Task 2 leaves a temporary Cue picker so the app compiles between tasks; Task 3 replaces it. That is a two-task seam, not a placeholder — the intermediate state builds and passes.
