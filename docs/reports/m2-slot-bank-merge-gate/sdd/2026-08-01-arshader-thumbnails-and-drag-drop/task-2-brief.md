### Task 2: The preview/program split

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift` — new `isProgramLive` property; one line in `renderFrame()`; `reallocateMastersLocked()`
- Modify: `App/ARShader/OutputWindowController.swift` — push program-live state into the renderer
- Modify: `App/ARShader/OutputDestination.swift` — retire `OutputSharpness.isProjectingUpscaled`
- Modify: `App/ARShader/InstrumentView.swift:473-478` — remove the now-dead `projectingUpscaled` warning
- Test: `App/ARShaderTests/FrameGraphTests.swift`, `App/ARShaderTests/InstrumentRendererTests.swift`, `App/ARShaderTests/OutputDestinationTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1. This task is independent of the whole UI arc and is deliberately first-after-the-service.
- Produces: `InstrumentRenderer.isProgramLive: Bool` (lock-guarded, settable from the main actor, reallocates the master pair on change).

**Do this early.** It is the riskiest change in the phase and touches nothing the UI tasks touch.

Today `renderFrame()` computes, at `InstrumentRenderer.swift:371`:

```swift
let liveRes = renderScale.applied(to: outRes)
```

and *everything* derives from it — deck rasterisation (`line 397`), cue size (`line 377`,
`cueScale.applied(to: liveRes)`), master FX (`line 440`, `renderSize: liveRes.size`), and the master
pair's own allocation in `reallocateMastersLocked()` (`line 288`). So the entire behavioural change
is that one expression becoming conditional. There is no second rule to keep in sync.

- [ ] **Step 1: Write the four failing tests**

Add to `App/ARShaderTests/FrameGraphTests.swift`. They use the existing `setUpWithError` harness
(`device`/`queue`/`mixer`/`renderer`) and the existing `load(_:_:)` helper with the `solid_red` /
`solid_green` fixtures — do not invent new ones.

```swift
    // MARK: The preview/program split (phase 3c task 2)

    func testWithOutputLiveALiveDeckIgnoresPreviewScale() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0                     // deck 1 LIVE
        renderer.previewScale = RenderScale(percent: 25)
        renderer.isProgramLive = true                   // the projector is open
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920,
                       "With the projector open, a live deck rasterises full size whatever "
                       + "PREVIEW SCALE says — the operator's rule is that the projector is "
                       + "never affected, ever.")
    }

    func testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale() throws {
        renderer.outputResolution = RenderSize(width: 1920, height: 1080)
        renderer.previewScale = RenderScale(percent: 25)
        renderer.isProgramLive = true
        renderer.renderFrame()
        let tex = try XCTUnwrap(renderer.rawMasterTexture())
        XCTAssertEqual(tex.width, 1920)
        XCTAssertEqual(tex.height, 1080,
                       "The master is pinned WITH the decks, on the same condition — a pinned "
                       + "master over scaled decks would composite an upscale every frame.")
    }

    func testOpeningTheOutputDoesNotCostTheCueSaving() throws {
        try load(.one, "solid_red")
        try load(.two, "solid_green")
        mixer.crossfadePosition = 0                     // deck 1 live, deck 2 cued
        renderer.previewScale = RenderScale(percent: 100)
        renderer.cueRenderScale = RenderScale(percent: 25)
        renderer.isProgramLive = true
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920,
                       "the live deck pays full price")
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.two)).width, 480,
                       "the cued deck is not on the projector, so opening it must not make the "
                       + "cued deck full size too")
    }

    func testClosingTheOutputRestoresPreviewScale() throws {
        try load(.one, "solid_red")
        mixer.crossfadePosition = 0
        renderer.previewScale = RenderScale(percent: 25)
        renderer.isProgramLive = true
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 1920)

        renderer.isProgramLive = false                  // projector closed again
        renderer.renderFrame()
        XCTAssertEqual(try XCTUnwrap(renderer.deckRasterSize(.one)).width, 480,
                       "Closing the output must give the saving back — this is not a one-way "
                       + "latch, and the operator closes the projector constantly while building.")
    }
```

- [ ] **Step 2: Run them and watch them fail to COMPILE**

Run the ARShader scheme (see Global Constraints for the full command).
Expected: build failure, `value of type 'InstrumentRenderer' has no member 'isProgramLive'`.
That is the correct first failure — the property does not exist yet.

- [ ] **Step 3: Add `isProgramLive` to the renderer**

In `App/ARShader/InstrumentRenderer.swift`, beside the existing stored render state, add the backing
field next to `renderScale` / `cueScale`, and this property in the exact shape of `previewScale`
(lines 239-262) — it guards the no-op set and reallocates, because a change of program-live state
changes the master size:

```swift
    /// Whether the program feed is actually going somewhere — the output window is open on a screen
    /// or floating. Set from the main actor by `OutputWindowController`; read under the lock during
    /// the frame.
    ///
    /// This is the ONLY thing that lifts `previewScale` off the live chain. The operator's rule is
    /// that the projector is never affected by a preview control, ever; while nothing is projected
    /// there is no image to protect and the saving is free. Pinning the master on the SAME
    /// condition as the decks (rather than unconditionally) is what stops a scaled deck being
    /// composited into a full-size target every frame while output is closed.
    var isProgramLive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return programLive }
        set {
            lock.lock()
            guard newValue != programLive else { lock.unlock(); return }
            programLive = newValue
            reallocateMastersLocked()
            lock.unlock()
        }
    }
```

with the backing store declared alongside `renderScale`:

```swift
    private var programLive = false
```

`false` is the correct default: `OutputDestination.launchDefault` is `.off`, so the renderer and the
output controller agree at launch without anyone having to synchronise them.

- [ ] **Step 4: Make the one behavioural change**

`InstrumentRenderer.swift:371`, inside `renderFrame()`, after `let outRes = masterResolution`:

```swift
        // The whole preview/program split, in one expression. With the projector open the live
        // chain ignores PREVIEW SCALE entirely; with it closed, PREVIEW SCALE governs exactly as
        // it always has. Deck rasterisation, cue size, master FX and the master pair's own
        // allocation all derive from this, so there is no second rule that can drift out of sync.
        let liveRes = programLive ? outRes : renderScale.applied(to: outRes)
```

Note it reads `programLive` (the backing field) directly, not `isProgramLive` — the lock is already
held at that point, and going through the property would deadlock.

And the same conditional in `reallocateMastersLocked()` (line 288), which currently reads
`resolution: renderScale.applied(to: masterResolution)`:

```swift
    private func reallocateMastersLocked() {
        let live = programLive ? masterResolution : renderScale.applied(to: masterResolution)
        let fresh = Self.makeMasterPair(device: device, resolution: live)
        if fresh.count == 2 {
            masters = fresh
            masterIndex = 0
        }
    }
```

- [ ] **Step 5: Run the new tests AND the seven existing ones**

Run the ARShader scheme. Expected: the four new tests PASS, and **all seven of these pass unchanged**:
`testRenderScaleResizesTheMaster`, `testMasterIsFixedAt1920x1080`,
`testRenderScaleAppliesToALiveDeckNotJustACuedOne`,
`testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame`,
`testCueScaleIsAFractionOfTheLiveRenderNotOfTheOutput`,
`testTheInstrumentStillRendersCorrectlyAtAReducedRenderScale`,
`testSettingTheSameRenderScaleIsANoOp`.

They pass because `programLive` defaults to `false` and none of them opens an output — they were
all *already* testing the output-closed row without saying so. **If any of the seven fails, stop and
report; do not "fix" it by editing its assertions.** A failure there means the conditional went the
wrong way round.

- [ ] **Step 6: Make the seven tests state their precondition**

Add one line to each of the six that set a scale (not `testSettingTheSameRenderScaleIsANoOp`, which
is orthogonal), immediately before `renderFrame()`:

```swift
        renderer.isProgramLive = false      // output closed: PREVIEW SCALE governs the live chain
```

This changes no behaviour — it is already the default. It exists because an implicit assumption that
happens to hold is one refactor away from a test that passes for the wrong reason, and this codebase
has already shipped exactly that failure (see the `stubMonitorIdealHeight` comment in
`SurfaceGeometryTests.swift`).

- [ ] **Step 7: Wire the output controller to the renderer**

In `App/ARShader/OutputWindowController.swift`, `setDestination(_:)` (lines 40-43) is the seam — the
whole class is `@MainActor`, so this runs on the main actor and the renderer property is
lock-guarded for exactly this crossing:

```swift
    func setDestination(_ destination: OutputDestination) {
        self.destination = destination
        // The renderer has no knowledge of OutputDestination and must not gain any — it needs one
        // bit, not a concept. Setting it here rather than in applyDestination's branches keeps it
        // beside the published value it mirrors, so the two can never disagree.
        instrument.renderer.isProgramLive = destination != .off
        applyDestination()
    }
```

Check `toggleFullscreen()` (lines 46-54) — the agent-mapped call graph says it routes through
`setDestination`, so it is covered. **Verify that before moving on**; if any path sets `destination`
without going through `setDestination`, it needs the same line, and that is a defect to report.

- [ ] **Step 8: Retire the upscale warning**

`OutputSharpness.isProjectingUpscaled(destination:scale:)` (`OutputDestination.swift:74-84`) is now
structurally false: the only state that made it true — output open at a reduced scale — no longer
reduces the scale. Replace the whole enum body with a test-facing statement of that fact rather than
deleting it silently, so a future change that reintroduces the hazard fails a test instead of
shipping:

```swift
enum OutputSharpness {
    /// Once TRUE when the program output was live and the chain rasterised below the typed output
    /// resolution. Phase 3c made that unreachable: `InstrumentRenderer.isProgramLive` lifts
    /// PREVIEW SCALE off the whole live chain the moment output opens, so an open projector is
    /// always rasterising at full size.
    ///
    /// Kept, and kept false, deliberately. It is the assertion that the hazard is gone; a change
    /// that lets a preview control reach the projector again turns this true and fails
    /// `testProjectingAnUpscaleIsUnreachable`.
    static func isProjectingUpscaled(destination: OutputDestination, scale: RenderScale) -> Bool {
        false
    }
}
```

Then remove `projectingUpscaled` (`InstrumentView.swift:473-478`) and the warning UI it drives.
Follow its usage to the view that renders it and remove that too — a warning that can never fire is
worse than none, because it teaches the operator to ignore the spot it occupied.

- [ ] **Step 9: Add the unreachability test**

In `App/ARShaderTests/OutputDestinationTests.swift`:

```swift
    /// Phase 3c: a preview control can no longer reach the projector, so this must hold for EVERY
    /// combination rather than only the ones a UI happens to produce today.
    func testProjectingAnUpscaleIsUnreachable() {
        let destinations: [OutputDestination] = [.off, .floating, .screen(id: "1")]
        for destination in destinations {
            for percent in RenderScale.presets {
                XCTAssertFalse(
                    OutputSharpness.isProjectingUpscaled(destination: destination,
                                                         scale: RenderScale(percent: percent)),
                    "\(destination) at \(percent)% must not be an upscale")
            }
        }
    }
```

- [ ] **Step 10: Mutation-prove the new gates**

Two mutations, each run and then REVERTED:

1. In `renderFrame()`, change the conditional to `let liveRes = renderScale.applied(to: outRes)`
   (i.e. remove the pin). Expected: `testWithOutputLiveALiveDeckIgnoresPreviewScale` and
   `testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale` FAIL.
2. Change it to `let liveRes = outRes` (i.e. pin unconditionally). Expected:
   `testClosingTheOutputRestoresPreviewScale` and `testRenderScaleResizesTheMaster` FAIL.

Both mutations must produce failures. If mutation 2 produces none, the output-closed row is untested
and the saving could silently disappear. Record both results in the commit message.

- [ ] **Step 11: Full ARShader suite, then commit**

```bash
git add App/ARShader/InstrumentRenderer.swift App/ARShader/OutputWindowController.swift \
        App/ARShader/OutputDestination.swift App/ARShader/InstrumentView.swift \
        App/ARShaderTests/FrameGraphTests.swift App/ARShaderTests/InstrumentRendererTests.swift \
        App/ARShaderTests/OutputDestinationTests.swift
git commit -m "feat(3c): PREVIEW SCALE can no longer reach the projector

The live chain ignores PREVIEW SCALE while the program feed is open and
follows it while closed — one expression in renderFrame(), from which deck
rasterisation, cue size, master FX and the master pair's allocation all
already derive.

All seven existing render-scale tests pass unchanged: launchDefault is .off,
so every one of them was already testing the output-closed row. Six now say
so explicitly."
```

---

