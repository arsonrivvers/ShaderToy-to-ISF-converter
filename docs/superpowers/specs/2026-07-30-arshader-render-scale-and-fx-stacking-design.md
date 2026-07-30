# ARShader Milestone 2, phase 2 — Render Scale and stacked FX chains

**Date:** 2026-07-30
**Status:** design approved by the operator; implementation plan to follow
**Supersedes nothing.** Extends the Milestone 1 instrument (`c75e480..93385c0`).

Sources: the signed live smoke `docs/reports/live-smoke-instrument-m1.md` items 7 and 8, and an
FPS observation the operator raised while playing (below).

---

## 1. Why this is two parts

The requested feature is stacked FX chains — multiple `.fs` per deck (smoke item 7) and a master
chain on the program output (item 8). Mid-design the operator reported that the same shader
(`AR_ChaosCubes_v04_beta.fs`, a multi-pass feedback shader) reads **104 FPS · 13.7 ms GPU** in
TrueISFEditor and **31 FPS · 62.8 ms GPU** in ARShader.

FX chains multiply per-frame GPU cost. Building an unbounded chain feature onto a frame that may
already be well over budget (62.8 ms against a 16.7 ms budget at 60 fps) would ship the
frame-budget indicator permanently red, and any
later render-size fix would rework the FX code. So Part A lands first and is measured; Part B
follows through an explicit gate (§6).

### What is already known about the FPS gap

Confirmed by reading the code, not inferred:

- **The two apps are not rendering the same number of pixels.** With **Fit** checked — it is, in
  the operator's screenshot — `MetalRenderCore.targetSizeLocked` returns
  `BlitFit.inscribe(aspect:in: drawableSize)`. The editor's `1920 × 1080` fields supply the
  *aspect ratio*; the render size is the preview pane's drawable. ARShader has no Fit:
  `InstrumentRenderer.renderFrame` asks the deck for `outRes.size`, so a live deck rasterises the
  full typed output resolution every frame.
- **ARShader encodes work the editor does not**, all at full output resolution: the
  `TextureCopyPass` from engine output into the deck's owned texture, the opaque-black master
  clear, `Compositor.encodeLayer` for each live layer, and three `MTKView` presents per frame
  (DECK A / DECK B / PROGRAM) against the editor's one.
- **Cue is inert in the operator's configuration.** `renderFrame` applies the cue size only when
  `layer.effectiveOpacity > 0` is false. Deck A was live at 1.00, so `Cue 25%` was scoping a case
  the operator was not in — which is why turning it down changed nothing.
- **The editor's 104 FPS flatters itself.** 104 FPS is a 9.6 ms frame period against a reported
  13.7 ms GPU. GPU time exceeding the frame period means frames overlap on the GPU and the
  accumulator is measuring *submission* cadence, not completed throughput; the editor's real
  ceiling there is ~73 FPS. Both apps use the same `RenderStatsAccumulator`, so the comparison is
  not invalid — but the honest statement of the gap is **13.7 ms vs 62.8 ms**, not 104 vs 31.

**This is not a diagnosis.** Those factors may account for 4.6×; they may not. §6 is the
measurement that decides, and Part A is the instrument that performs it — sweeping Render Scale
holds the output resolution (and therefore the projector and the master allocation) fixed while
changing only what gets rasterised. Typing into OUTPUT RES to measure would change the deliverable
in order to measure it.

---

## 2. Part A — Render Scale and Cue Scale

`CueQuality` (a five-case enum, applied only to non-contributing decks) is **replaced** by
`RenderScale`: a typed, clamped percentage. Presets move into a menu, exactly as `RenderSize` did —
typing the number is the primary control, the menu is a convenience.

| Control | Drives | Default |
|---|---|---|
| **OUTPUT RES** | the nominal output: projector window size, typed W × H | 1920 × 1080 |
| **RENDER SCALE** | what live decks **and the master/program composite** rasterise at | 100% |
| **CUE SCALE** | what decks that are not contributing rasterise at | 50% |

### Sizing rules

- **Owned textures** — each deck's output texture, each chain's scratch texture, and the
  `masters[2]` pair — are allocated at `outputResolution × renderScale`.
- **Rasterisation size varies per frame**: a live deck draws at `output × renderScale`; a
  non-contributing deck draws at `output × cueScale` and upscales into its owned texture.
- The master composite and the master FX chain rasterise at the masters' size, i.e.
  `output × renderScale`.

This preserves the Milestone 1 invariant and the reason for it: **starting a fade reallocates
nothing.** Only a change to **output resolution or Render Scale** reallocates, and both are rare
operator actions, never in the steady-state frame. **Cue Scale reallocates nothing at all** — it
changes only how many pixels a cued deck rasterises before upscaling into its existing owned
texture, which is exactly why it is safe to drop very low.

The projector and the monitors already sample-and-upscale through linear-filtered fullscreen
passes, so a scaled master reaches a 1920 × 1080 projector for free. *Verify this on
`ProgramView` / `TexturePresentingView` during implementation rather than assuming it.*

### Surface

Each scale field displays the pixel size it resolves to, so low-scale softness is a number the
operator set rather than a surprise on a wall. (The example below shows Cue Scale typed down to
25%; its default is 50%.)

```
OUTPUT RES
 [1920] × [1080]  [Set]
 2.1 MP

RENDER SCALE  [ 100 ]%
 → rasterising 1920×1080

CUE SCALE     [  25 ]%
 → cued decks 480×270
```

`RenderScale` clamps to **5%–100%**. Values above 100% would be supersampling — genuine free
anti-aliasing at four times the cost — and are deliberately out of scope (§8).

---

## 3. Part B — stacked FX chains

Unbounded chains, per the operator's call over fixed slots.

### 3.1 Texture strategy: a ping-pong pair, not a pool

The prior session's handoff proposed a size-keyed reusable texture pool on the premise that each
stage needs its own owned texture. It does not. A linear chain only ever reads the **immediately
previous** stage, so a ping-pong pair covers any depth — the same argument that already justifies
`masters[2]`. Metal's automatic hazard tracking handles the write-after-read across render passes
within one command buffer.

- Each deck gains **one** scratch texture. The chain alternates `owned → scratch → owned → …`,
  and `Deck.render` returns whichever holds the final result. Both are deck-owned and stable
  across frames, so the monitors' later-command-buffer reads stay valid.
- The master chain **reuses the existing `masters[2]` pair** and needs no new texture at all.

**Two new textures for the entire feature, at any chain depth.** Adding a stage allocates nothing.

### 3.2 The mix pass is the copy

Every stage must copy its output out of the `VVMTLPool` texture the ISF engine returns — the
aliasing hazard already documented on `TextureCopyPass` and fixed once in `ISFSceneSource`. If that
copy is `Compositor.encodeLayer` rather than `TextureCopyPass.encode` — source = stage output,
backdrop = stage input — the copy *becomes* the mix.

Per-stage **Mix (dry→wet)** and **all 19 blend modes** therefore cost no additional GPU pass, and
reuse blend math that `CompositorTests` already pins against `BlendMath`.

**One change is required.** `Compositor` currently forces `alpha = 1.0` ("The master is opaque by
contract. Never propagate a layer's alpha into it."). That is right for the master and wrong
mid-chain: it would silently make any deck carrying an FX stage fully opaque and change how it
composites, since layer alpha is `src.a * opacity`. Add a `preserveAlpha` uniform; mid-chain the
stage result carries `a = mix(backdrop.a, source.a, mix)`. Both behaviours get test coverage.

### 3.3 Frame graph

One command buffer per frame, as today.

```
1. per deck:  ISF render (live → output×renderScale, cued → output×cueScale)
                 ──copy──▶ owned
              FX chain:  stage reads owned    ─▶ writes scratch
                         stage reads scratch  ─▶ writes owned      … alternating
                         result = owned or scratch, by parity
2. masters[current] cleared to OPAQUE BLACK                          [unchanged]
3. composite each contributing layer, ping-ponging masters[]         [unchanged]
4. MASTER FX chain, ping-ponging the SAME masters[] pair             [new]
5. blackout gate: programTexture() returns nil                       [unchanged, still last]
```

Blackout stays a final gate with no pipeline between the panic button and darkness. The master
chain sitting at step 4 needs no second gate: blackout **withdraws** the texture.

Per stage: one ISF render plus one mix pass.

### 3.4 Types

`ShaderUnit` is extracted from `Deck` — the compiled scene (`MetalRenderCore`), `ParamStore`,
`SourceRouter`, compile state, and the load/unload/`pulseEvent` surface, including the
compile-first-swap-only-on-success doctrine ("on stage, the shader that is already up is the one
thing you cannot afford to lose").

| Type | Composition |
|---|---|
| `ShaderUnit` | `@MainActor ObservableObject`; owns the scene, params, image routing, compile state |
| `Deck` | `ShaderUnit` + `id` + owned output + scratch + `FXChain` |
| `FXStage` | `ShaderUnit` + `isEnabled` + `mix` + `blendMode` |
| `FXChain` | `[FXStage]` + append / remove / move + a lock-guarded render mirror |
| `ShaderControlsView` | today's `DeckControlsView`, retargeted at a `ShaderUnit`, reused by both |

The alternative — writing `FXStage` fresh and leaving `Deck` untouched — was rejected: it
duplicates ~110 lines including the failed-compile doctrine, in two places, drifting. Reusing
`ISFSceneSource` as the stage was also rejected: it has no `ParamStore` (so no generated controls),
compiles synchronously in `init`, and blocks on `waitUntilCompleted` for a probe frame — the
launch-freeze bug by construction.

### 3.5 Threading — no new model

`FXChain` mirrors `MixerState` exactly: `@Published` state for the UI, and an `NSLock`-guarded
immutable snapshot republished on every mutation, read from the display-link thread by
`renderStages()`. Each stage's `MetalRenderCore` is already `@unchecked Sendable` behind its own
lock.

**Nothing on the render path becomes `@MainActor`, and `MainActor.assumeIsolated` appears
nowhere.** It is a runtime assertion and traps off-actor; that cost the previous session a crash on
frame one.

### 3.6 Surface

The deck-strip row becomes three columns: **DECK A | DECK B | MASTER**. Master FX reads exactly
like a deck chain, so there is one mental model. Phase 3's panel system restructures this area
anyway, which is what makes it cheap to place here now.

Each chain is a list of stage rows: name, on/off, **Mix**, blend picker, **▲▼**, **✕**, and drag to
reorder. Buttons *and* drag, per the operator: the buttons are the reliable path under stage
lighting, drag is the one that feels right. Each stage's generated controls sit behind a disclosure
triangle.

The library's *Load onto* picker gains `A FX`, `B FX`, `Master FX` alongside `Deck A` / `Deck B`;
clicking a shader appends a stage to the selected target. This reuses the existing browser and adds
no second picker surface.

A stage whose shader has no filter image input (a generator) is marked as such — it replaces the
feed rather than processing it, which with Mix and a blend mode available is a usable move rather
than a mistake.

### 3.7 Frame-budget indicator

Each chain shows its **stage count** and goes amber then red **in sync with the measured global
frame time**.

No per-chain millisecond figure is displayed. Cost inside a single command buffer cannot be
honestly attributed to one chain, and displaying a number the engine did not measure is the same
class of error as a fabricated counter. Real per-chain timing would need
`MTLCounterSampleBuffer` timestamps at pass boundaries; that is out of scope (§8).

### 3.8 Failure behaviour — never black

| Condition | Behaviour |
|---|---|
| Stage fails to compile | Previous scene keeps rendering; the error shows on that stage's row |
| Stage render returns nil | The stage passes its input through for that frame |
| Stage disabled, or Mix = 0 | Skipped entirely — no ISF render, no mix pass |
| Empty or all-disabled chain | Pure passthrough; encodes zero passes; byte-identical to today |
| `Compositor` failed to build | Chains skip entirely; the existing black-master failure floor is unchanged |

**One consequence to state rather than discover:** because a disabled or zero-mix stage is skipped
entirely, a *time-dependent or PERSISTENT-buffer* effect (trails, feedback) stops advancing while
it is at zero, so raising the mix resumes from a stale buffer rather than a live one. This is the
cheap behaviour and is believed to be the right one mid-set; §9 records it as reversible.

---

## 4. Behaviour decided by the operator

| Question | Decision |
|---|---|
| Per-stage controls | On/off, **Mix**, and a blend mode from the same 19 |
| Deck monitor tap | **Post-FX** — the monitor shows what the deck is contributing |
| Adding a stage | Extend the library's *Load onto* picker |
| Budget guard | Readout colour **plus** a per-chain hint (stage count only) |
| Master FX placement | Third strip: A \| B \| MASTER |
| Reorder | ▲▼ buttons **and** drag |
| Scale knobs | Two: Render Scale and Cue Scale, both typed percentages |

---

## 5. Testing

| Suite | Covers |
|---|---|
| `RenderScaleTests` | clamping at 5% / 100%, `applied(to:)` resolution math, preset parity |
| `ShaderUnitTests` | today's `DeckTests` behaviours, migrated: compile-first-swap-on-success, generation supersession, param replay, unload |
| `FXChainTests` | append / remove / move ordering; disabled and Mix-0 stages encode **zero** passes; empty chain is identity; ping-pong parity at odd and even depth |
| `CompositorTests` | extended for `preserveAlpha`: alpha preserved mid-chain, forced to 1 on the master |
| Pixel tests | through the existing `TextureReadback` / `TestPixels`: Mix 0 ≡ input; Mix 1 + Normal ≡ stage output; a one-stage chain changes pixels |

**Two mutation tests**, each of which must fail a test when reinstated:

1. flip the ping-pong parity
2. drop the `preserveAlpha` flag

**Two live-capture gates**, which are not test passes:

1. after the `ShaderUnit` extraction — this refactor has exactly the shape of the Milestone 1
   defect where `DeckStripView` stopped observing its model and froze at its initial value while
   104 tests stayed green
2. after the FX strip lands

The Milestone 1 record is unambiguous on this point: five of six defects were found by running the
app, not by testing it, on a codebase with 950 green tests. The suite protects against regression,
not against "was it ever wired up."

---

## 6. The gate between Part A and Part B

Part A ships. Then, on `AR_ChaosCubes_v04_beta.fs` at OUTPUT RES 1920 × 1080, sweep **Render Scale
100 / 75 / 50 / 25** and record **GPU ms** (not FPS — see §1).

- **Cost falls roughly with pixel count** → no regression exists; the apps were never drawing the
  same pixels. Part B proceeds, and Render Scale is the permanent lever.
- **Cost does not scale** → something structural is wrong in the frame graph. Bisect it before
  stacking anything on it, under `superpowers:systematic-debugging`.

Record the numbers in `docs/reports/`, not only in conversation.

---

## 7. Process constraints

- `scripts/run-instrument.sh` **quits the running app before installing.** Never reinstall while
  the operator is playing without saying so first.
- Build with an explicit `-derivedDataPath` and verify the staged binary contains the change
  before any "relaunch" claim. Use **ASCII** markers: `strings` cannot see literals containing
  multi-byte glyphs.
- Say what is running through long build cycles.

---

## 8. Out of scope

- **Chain persistence** (saving and recalling chains). Nothing in the instrument persists yet —
  not output resolution, not cue. Consistent, and a separate decision.
- **Supersampling** (Render Scale above 100%).
- **Per-chain GPU attribution** via `MTLCounterSampleBuffer`.
- **Occlusion pause** — tracked separately as `arshader-instrument-occlusion-pause-20260730`.
- **The collapsible panel system and library show-prep depth** — Milestone 2 phase 3, deliberately
  after this so the panels are designed once against the finished feature set.

## 9. Open questions

1. Should a Mix-0 stage keep rendering so PERSISTENT/feedback effects stay live? Cheaper not to;
   reversible in one line if the stale-buffer resume proves annoying in practice (§3.8).
2. Does Render Scale want a keyboard shortcut, so it can be dropped mid-set without reaching for a
   text field?
3. Projector legs 15–18 remain unrun on real hardware
   (`arshader-m1-live-smoke-confirmed-gate-20260730`). Part A changes what the projector receives —
   an upscaled master — so those legs matter more after this than before.
