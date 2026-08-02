# ARShader Modulation and Expression Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any time-varying source drive any parameter of the instrument through one compiled
expression per destination, with per-destination shaping, and ship a manual stub source that is a
real performance control — so the whole layer is playable on device before any audio code exists.

**Architecture:** A pure evaluator (`ModulationEngine.evaluate(bindings, snapshot, bases,
previous) -> ModulationOutcome`) with no Metal, SwiftUI or audio dependency, mirroring
`SurfaceLayout`'s shape from phase 3a. Around it, the same two-half arrangement `MixerState`,
`FXChain` and `SourceRouter` already use: an `@MainActor` `ModulationModel` owns the operator's
ledger and persistence, and publishes a compiled mirror to a lock-guarded `ModulationRuntime` that
the display-link thread ticks once per frame. Modulated values never travel back through
`ParamStore`, `@Published` or `UserDefaults` — the runtime writes ISF inputs straight into
`MetalRenderCore.withScene`, and the frame graph reads mixer/FX overrides at the existing
render-mirror read points.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest, XcodeGen (`App/project.yml`), macOS 13+, Metal /
ISFMSLKit (read only — this slice adds no shader code).

**Spec:** `docs/superpowers/specs/2026-08-01-arshader-modulation-expression-layer-design.md`

## Global Constraints

- **Every new file lives in `App/ARShader/`, never `App/ISFRuntime/`.** `ISFRuntime` compiles into
  TrueISFEditor too; instrument modulation state must not leak there. `project.yml` already sweeps
  `path: ARShader` into both the `ARShader` and `ARShaderTests` targets, so **no `project.yml`
  edit is needed for any task in this plan** — but the project must still be regenerated (below).
- **Regenerate the project after adding any file:** `cd App && xcodegen generate`. The
  `.xcodeproj` is generated and gitignored; a stale one silently omits new sources.
- **Build and test with an explicit non-Desktop derived-data path:** `-derivedDataPath
  /tmp/arshader-ddata-mod`. The repo lives under `~/Desktop`, where Defender DLP has stalled test
  hosts pre-`main`.
- **`xcodebuild test` launches a second ARShader window via `TEST_HOST`, and
  `scripts/run-instrument.sh` QUITS any running ARShader.** Tell the operator before running
  either. Use `build-for-testing` when you only need to confirm something compiles — it launches
  no window.
- **Execution happens in the worktree `.worktrees/m2-modulation` on branch `m2-modulation`.** A
  concurrent session is live in `.worktrees/m2-slot-bank` (phase 3b/3c). **Never touch that
  worktree.** Never `git add -A` in this repo — explicit paths only. A modified
  the prior-art dossier under `docs/arshader/` in the main checkout belongs to that
  session.
- **Known merge-conflict surface with `m2-slot-bank`** (measured 2026-08-01 against the merge
  base): `FXChain.swift`, `ShaderUnit.swift`, `SurfaceLayout.swift`, `InstrumentView.swift`,
  `Instrument.swift`. All five are additive on that branch, so conflicts will be textual rather
  than semantic — but this slice should rebase onto 3b/3c after they land rather than the other
  way round, because 3c is further along. `LibraryPanelView.swift` is *not* on this list: this
  plan reads it (the sole `FXStage` construction site, and the destination-filter reference in
  Task 12) but never modifies it. (PM spec review, 2026-08-01, finding 2.)
- **Baseline gate counts:** record the executed counts *before* Task 1 changes anything and treat
  them as a floor no later task may reduce. Source-counted, `ARShaderTests` declares **207**
  `func test…`. **EXECUTED BASELINE, measured 2026-08-01 on `m2-modulation` @ `bd0b9c1`:
  `Executed 207 tests, with 0 failures (0 unexpected) in 15.870s` — `** TEST SUCCEEDED **`.**
  Declared and executed agree, so **207 is the floor**; no later task may report fewer. Task 1
  Step 8 expects 211.
- **Blackout has no destination address.** No `ModDestination` case names it, and the applier's
  exhaustive `switch` has no branch that could reach `MixerState.isBlackedOut`. This is the
  mechanism, not a convention — the same structural exclusion phase 3a gave it for show mode.
- **Modulated values bypass persistence and the UI-update path entirely.** No modulated value may
  be written through `ParamStore.set`, a `@Published` property, or `UserDefaults`. Persisted:
  expression text, target mode, enabled flag, and base values. Never persisted: evaluated output.
- **Every gate in spec §9.1 ships with its mutation demonstrated.** A test that cannot fail is
  worse than no test. Task 13 collects the evidence; each task performs its own mutation run at
  the point the gate is written.
- **Deliberate vocabulary boundary.** The expression language is exactly spec §2's list. The prior-art system's
  own shipped expressions used a conditional, as prior-art research recorded
  — and this language has no conditional and no comparison operators. Gating is done by
  multiplication against `valid(...)` or a `step`-shaped arithmetic idiom. Adding `if`/comparisons
  is a tuning-surface-slice decision, not this one's.

## Scope note the spec does not state (read before Task 1)

Spec §4.1 argues that `FXStage.id` must be serialised with the chain and restored into the rebuilt
stage, because otherwise a binding persisted as `deck.a.fx.<uuid>.mix` resolves once and never
again. That argument is correct, **and nothing in `master` persists an FX chain at all** —
`FXStage` is constructed in exactly one place (`LibraryPanelView.swift:65`), there is no `Codable`
chain type, and `SurfaceLayoutStore` is the only `UserDefaults` writer in the instrument. Phase
3b's `Preset` captures a shader URL plus a `ParamSnapshot`; it does not capture a chain either.

So Task 1 delivers the *precondition* §4.1 actually needs — an injectable, resolvable stage
identity — and does not invent chain persistence, which belongs to whichever slice first restores
a chain (3c's presets are the likely home, and spec §10.3 defers exactly that question). Until
then an FX binding whose stage id is not present resolves as **skipped**, which is the §4.2
behaviour this plan implements anyway. This is stated here so the gap is visible rather than
discovered at the on-device gate.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| Modify `App/ARShader/FXStage.swift` | `id` becomes injectable and persisted-capable | 1 |
| Modify `App/ARShader/FXChain.swift` | `stage(id:)` lookup; snapshot carries the id; the mix-zero skip moves to encode time | 1 |
| Create `App/ARShader/ModDestination.swift` | The address space, its string form, and the blackout exclusion | 2 |
| Create `App/ARShader/ModSource.swift` | Output kinds, the registry, the per-frame snapshot, staleness and idle values | 3 |
| Create `App/ARShader/ManualSource.swift` | The permanent stub provider: trigger, LFO, tap tempo | 4 |
| Create `App/ARShader/Expression.swift` | Tokeniser, parser, `ExprNode`, compile errors as values | 5 |
| Create `App/ARShader/ExpressionFunctions.swift` | Math + the motion vocabulary (`spring`, `spring_v`, `stagger`, `anticipate`, `loop_noise`) | 6 |
| Create `App/ARShader/ExpressionEvaluator.swift` | Evaluate a node against a snapshot; `ref`/`since`/`valid`/`time`/`dt`/`frame`/`self` | 6 |
| Create `App/ARShader/ModulationEngine.swift` | `ModBinding`, `CompiledBinding`, modes, clamping, NaN containment, skipped bindings, `self` = previous frame | 7 |
| Create `App/ARShader/ModulationRuntime.swift` | Lock-guarded mirror; base registry; ISF sinks; `tick`; mixer/FX appliers | 8 |
| Create `App/ARShader/ModulationModel.swift` | `@MainActor` ledger: set/get/list/clear, rename-safe rewriting, publish to runtime | 9 |
| Create `App/ARShader/ModulationStore.swift` | Versioned, corrupt-tolerant `UserDefaults` persistence | 9 |
| Modify `App/ARShader/InstrumentRenderer.swift` | Tick the runtime once per frame; apply mixer and FX overrides | 10 |
| Modify `App/ARShader/ShaderUnit.swift` | Register ISF-input bases + sinks on compile; drop them on unload | 10 |
| Modify `App/ARShader/MixerState.swift`, `Instrument.swift` | Publish bases; expose the crossfader to the render mirror; own the model/runtime/manual source | 10 |
| Create `App/ARShader/DrivenControl.swift` | `DrivenState`, the `MOD` badge, the clear-driver affordance | 11 |
| Modify `App/ARShader/FXChainView.swift`, `ShaderControlsView.swift`, `InstrumentView.swift` | Driven state visible; `absolute` gestures ignored | 11 |
| Create `App/ARShader/ModulationPanelView.swift` | Source strip + binding ledger, behind a new rail panel | 12 |
| Modify `App/ARShader/SurfaceLayout.swift`, `InstrumentView.swift` | `PanelID.modulation` case + panel wiring | 12 |
| Create `App/ARShaderTests/FXStageIdentityTests.swift` | Stable-ID gate + the index-addressing mutation | 1 |
| Create `App/ARShaderTests/ModDestinationTests.swift` | Address round-trip + blackout exclusion | 2 |
| Create `App/ARShaderTests/ModSourceTests.swift` | Registry, `since`, staleness, idle values | 3 |
| Create `App/ARShaderTests/ManualSourceTests.swift` | Phase integration, LFO shapes, tap tempo | 4 |
| Create `App/ARShaderTests/ExpressionTests.swift` | Parse, precedence, errors-as-values | 5 |
| Create `App/ARShaderTests/ExpressionEvaluatorTests.swift` | Vocabulary, motion functions, NaN production | 6 |
| Create `App/ARShaderTests/ModulationEngineTests.swift` | Frame coherence, modes, clamping, NaN containment, skipped, `self` | 7 |
| Create `App/ARShaderTests/ModulationRuntimeTests.swift` | Mirror publish, sinks, mixer/FX appliers, the `dt` clamp | 8 |
| Create `App/ARShaderTests/ModulationModelTests.swift` | Ledger edits, compile errors kept, persistence, rename rewriting | 9 |
| Create `App/ARShaderTests/ModulationWiringTests.swift` | Bases published, one tick per frame, modulated layers reach the composite | 10 |
| Create `App/ARShaderTests/DrivenControlTests.swift` | Ownership: gestures ignored, never silently cleared | 11 |
| Create `App/ARShaderTests/ModulationPanelTests.swift` | Rail case, picker catalogue, source list | 12 |
| Create `App/ARShaderTests/ModulationPerformanceTests.swift` | 64 routes under 0.5 ms | 13 |
| Create `docs/reports/modulation-mutation-evidence.md` | Every §9.1 gate's mutation, demonstrated | 13 |
| Create `docs/reports/live-smoke-instrument-m2-modulation.md` | Operator-signed on-device gate | 14 |

---

## Task 1: FX stage identity survives a rebuild

**Files:**
- Modify: `App/ARShader/FXStage.swift:11`, `App/ARShader/FXStage.swift:16-19`
- Modify: `App/ARShader/FXChain.swift:6-10`, `App/ARShader/FXChain.swift:77-85`,
  `App/ARShader/FXChain.swift:108-130`
- Test: `App/ARShaderTests/FXStageIdentityTests.swift`

**Interfaces:**
- Consumes: `FXStage`, `FXChain`, `FXStageSnapshot`, `ShaderUnit`, `RenderClock` as they stand.
- Produces:
  - `FXStage.init(id: UUID = UUID(), device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock)`
  - `FXStage.id: UUID` (now a stored, injectable `let`)
  - `FXChain.stage(id: UUID) -> FXStage?`
  - `FXStageSnapshot.id: UUID`
  - `FXChain.renderStages()` now includes stages whose `mix == 0` (still excludes disabled ones);
    the zero-mix skip happens inside `encode`.
  Tasks 8, 10, 11 and 12 use exactly these names.

- [x] **Step 1: Record the baseline gate counts**

Announce to the operator first — this launches a second ARShader window via `TEST_HOST`.

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test 2>&1 | tail -5
```

Write the reported `Executed N tests` figure into the plan's Global Constraints as the floor. Every
later task must not reduce it.

- [x] **Step 2: Write the failing test**

Create `App/ARShaderTests/FXStageIdentityTests.swift`:

```swift
import XCTest
import Metal

/// Spec §4.1 — bindings address FX stages by a STABLE id, never by index, and that id must be
/// restorable into a rebuilt stage rather than regenerated.
@MainActor
final class FXStageIdentityTests: XCTestCase {

    private func makeChain() throws -> (FXChain, MTLDevice, MTLCommandQueue, RenderClock) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        return (FXChain(), device, queue, RenderClock())
    }

    /// The gate: a restored id resolves to the stage it named, and the ARRAY INDEX does not.
    ///
    /// Mutation that must fail this test: address by index instead of id — replace the
    /// `chain.stage(id:)` lookups below with `chain.stages[0]` / `chain.stages[1]` and the
    /// post-reorder assertions invert.
    func testAStageIsFoundByItsIdAcrossAReorder() throws {
        let (chain, device, queue, clock) = try makeChain()
        let first = FXStage(device: device, queue: queue, clock: clock)
        let second = FXStage(device: device, queue: queue, clock: clock)
        chain.append(first)
        chain.append(second)
        chain.setMix(0.25, for: first)
        chain.setMix(0.75, for: second)

        chain.moveDown(0)

        XCTAssertEqual(chain.stages.first?.id, second.id, "The reorder happened")
        XCTAssertEqual(chain.stage(id: first.id)?.mix, 0.25,
                       "A binding addressing the first stage still finds the first stage")
        XCTAssertEqual(chain.stage(id: second.id)?.mix, 0.75)
    }

    /// The relaunch half of §4.1: a chain rebuilt with the SAME ids resolves bindings made in an
    /// earlier session. Without an injectable id this cannot even be expressed.
    func testARebuiltStageCarriesTheIdItWasGiven() throws {
        let (chain, device, queue, clock) = try makeChain()
        let persisted = UUID()

        let rebuilt = FXStage(id: persisted, device: device, queue: queue, clock: clock)
        chain.append(rebuilt)
        chain.setMix(0.4, for: rebuilt)

        XCTAssertEqual(rebuilt.id, persisted,
                       "The id is restored, not regenerated — a binding persisted as "
                       + "deck.a.fx.\(persisted).mix must resolve on the NEXT launch too")
        XCTAssertEqual(chain.stage(id: persisted)?.mix, 0.4)
    }

    func testAnUnknownIdResolvesToNothingRatherThanTheWrongStage() throws {
        let (chain, device, queue, clock) = try makeChain()
        chain.append(FXStage(device: device, queue: queue, clock: clock))

        XCTAssertNil(chain.stage(id: UUID()),
                     "An unresolvable binding is skipped (§4.2), never silently retargeted")
    }

    /// A stage at zero mix must still be VISIBLE to modulation — an offset-mode driver on a
    /// dry stage is how a kick brings an effect in. The zero-mix skip is a render-time decision
    /// now, not a publish-time one.
    func testAZeroMixStageStaysInTheRenderMirrorAndADisabledOneDoesNot() throws {
        let (chain, device, queue, clock) = try makeChain()
        let stage = FXStage(device: device, queue: queue, clock: clock)
        chain.append(stage)

        chain.setMix(0, for: stage)
        XCTAssertEqual(chain.renderStages().map(\.id), [stage.id],
                       "Zero mix is skipped at encode time, so modulation can still raise it")

        chain.setEnabled(false, for: stage)
        XCTAssertTrue(chain.renderStages().isEmpty,
                      "Off still means off — no render, no cost, no modulation")
    }
}
```

- [x] **Step 3: Run the tests to verify they fail**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/FXStageIdentityTests 2>&1 | tail -25
```

Expected: compile failure — `FXStage` has no `init(id:device:queue:clock:)`, `FXChain` has no
`stage(id:)`, `FXStageSnapshot` has no `id`.

- [x] **Step 4: Make the stage id injectable**

In `App/ARShader/FXStage.swift`, replace line 11 and the initialiser at lines 16–19:

```swift
    /// Stable across `move(from:to:)`, `moveUp`, `moveDown` — and, because it is injectable,
    /// across a relaunch too once something restores a chain. Spec §4.1: a binding persisted as
    /// `deck.a.fx.<uuid>.mix` resolves on the session it was made in and NEVER again if this is
    /// regenerated on rebuild, and nothing anywhere would report the failure.
    let id: UUID
    let unit: ShaderUnit

    /// Builds its own unit so a stage can never be constructed with a ROUTED primary input — the
    /// chain drives that slot.
    ///
    /// `id` defaults to a fresh UUID: every existing call site (`LibraryPanelView`) keeps working
    /// unchanged, and a future restore passes the persisted one.
    init(id: UUID = UUID(), device: MTLDevice, queue: MTLCommandQueue, clock: RenderClock) {
        self.id = id
        self.unit = ShaderUnit(device: device, queue: queue, clock: clock,
                               reservesPrimaryInput: true)
    }
```

- [x] **Step 5: Carry the id into the render mirror and move the zero-mix skip**

In `App/ARShader/FXChain.swift`, add `id` to the snapshot (lines 6–10):

```swift
struct FXStageSnapshot: @unchecked Sendable {
    let id: UUID
    let core: MetalRenderCore
    let mix: Double
    let blendMode: BlendMode
}
```

Replace `publishToRenderThread()` (lines 77–85):

```swift
    /// The mirror carries every ENABLED stage, including ones at zero mix.
    ///
    /// Zero mix used to be filtered out here. It cannot be any more: an `offset`-mode binding on a
    /// dry stage is how an effect gets brought in by a kick, and a stage filtered out at publish
    /// time is invisible to modulation. "Skipped entirely" is now decided in `encode`, one line
    /// later and with the modulated mix in hand — the cost is identical.
    private func publishToRenderThread() {
        let snapshot = stages
            .filter(\.isEnabled)
            .map { FXStageSnapshot(id: $0.id, core: $0.unit.core, mix: $0.mix,
                                   blendMode: $0.blendMode) }
        renderLock.lock()
        renderCache = snapshot
        renderLock.unlock()
        objectWillChange.send()
    }

    /// The stage a binding names, or nil when it is not in this chain — an unresolvable binding is
    /// retained and reported skipped (§4.2), never retargeted onto whatever sits at that index.
    func stage(id: UUID) -> FXStage? { stages.first { $0.id == id } }
```

In `encode` (line 116), skip the dry stages that `publishToRenderThread` no longer filters:

```swift
        for stage in renderStages() {
            guard stage.mix > 0 else { continue }   // dry: no render, no cost (was a publish filter)
```

- [x] **Step 6: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/FXStageIdentityTests 2>&1 | tail -20
```

Expected: PASS, 4 tests.

- [x] **Step 7: Prove the stable-ID gate can fail**

Temporarily replace `chain.stage(id: first.id)?.mix` with `chain.stages[0].mix` and
`chain.stage(id: second.id)?.mix` with `chain.stages[1].mix` in
`testAStageIsFoundByItsIdAcrossAReorder`. Re-run the command from Step 6.

Expected: FAIL — `0.75` is not `0.25`. Revert the mutation and re-run to confirm PASS. Record the
observed failure line in the Task 13 evidence table.

- [x] **Step 8: Run the full suite**

```bash
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test 2>&1 | tail -5
```

Expected: the Step 1 baseline plus 4 = **211**, all passing.

**Plan correction, made during execution 2026-08-01.** This step originally read "`FXChainTests` in
particular must still pass — it exercises the publish filter this task changed." That was wrong, and
the first full run proved it: **211 tests, 1 failure**, at `FXChainTests.swift:67`
(`testAZeroMixStageWithdrawsItselfToo`), which asserted `renderStages().isEmpty` for a zero-mix
stage — *precisely* the contract Step 5 deliberately inverts. A test asserting the old behaviour
cannot survive the change that replaces it; the plan should have said so and scheduled the rewrite.

Resolution: that test was **rewritten, not deleted**, as
`testAZeroMixStageStaysInTheMirrorButCostsNothingToEncode`. Its intent — never pay for an invisible
pass — is unchanged and now asserted where the behaviour actually lives, and end-to-end rather than
by proxy: the dry stage IS published (so modulation can raise it), and running a zero-mix
`invert_filter` over a red input through `encode` returns red. Test count is unaffected (211), so
the 207 floor holds.

- [x] **Step 9: Commit**

```bash
git add App/ARShader/FXStage.swift App/ARShader/FXChain.swift \
        App/ARShaderTests/FXStageIdentityTests.swift
git commit -m "feat(mod): FX stages carry an injectable, resolvable identity"
```

---

## Task 2: The destination address space

**Files:**
- Create: `App/ARShader/ModDestination.swift`
- Test: `App/ARShaderTests/ModDestinationTests.swift`

**Interfaces:**
- Consumes: `DeckID` from `App/ARShader/Deck.swift`, `BlendMode` from
  `App/ISFRuntime/BlendMath.swift`.
- Produces:
  - `enum FXParam: Hashable, Codable, Sendable { case mix, input(String) }`
  - `enum ModDestination: Hashable, Codable, Sendable` with cases `deckInput(DeckID, String)`,
    `deckOpacity(DeckID)`, `deckBlend(DeckID)`, `deckFX(DeckID, UUID, FXParam)`,
    `masterFX(UUID, FXParam)`, `crossfader`
  - `ModDestination.address: String`, `ModDestination.init?(address: String)`
  - `ModDestination.displayName: String`
  - `enum ModFXScope: Hashable, Sendable { case deck(DeckID), master }` and
    `ModDestination.fxScope: ModFXScope?`
  Tasks 7–12 use exactly these names.

- [x] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModDestinationTests.swift`:

```swift
import XCTest

/// Spec §4 — the three address spaces, their string form, and the one thing that has no address.
final class ModDestinationTests: XCTestCase {

    private let stage = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!

    func testEveryAddressRoundTripsThroughItsStringForm() {
        let all: [ModDestination] = [
            .deckInput(.one, "speed"),
            .deckInput(.two, "warp amount"),
            .deckOpacity(.one),
            .deckBlend(.two),
            .deckFX(.one, stage, .mix),
            .deckFX(.two, stage, .input("threshold")),
            .masterFX(stage, .mix),
            .masterFX(stage, .input("gain")),
            .crossfader,
        ]
        for destination in all {
            XCTAssertEqual(ModDestination(address: destination.address), destination,
                           "\(destination.address) must survive the round trip it is persisted in")
        }
    }

    /// The literal strings the spec writes down. A refactor that changes them silently orphans
    /// every persisted binding, so they are pinned rather than merely round-tripped.
    func testTheAddressStringsAreTheOnesTheSpecNames() {
        XCTAssertEqual(ModDestination.deckInput(.one, "speed").address, "deck.a.input.speed")
        XCTAssertEqual(ModDestination.deckOpacity(.two).address, "deck.b.opacity")
        XCTAssertEqual(ModDestination.deckBlend(.one).address, "deck.a.blend")
        XCTAssertEqual(ModDestination.crossfader.address, "mixer.crossfader")
        XCTAssertEqual(ModDestination.deckFX(.one, stage, .mix).address,
                       "deck.a.fx.\(stage.uuidString).mix")
        XCTAssertEqual(ModDestination.masterFX(stage, .input("gain")).address,
                       "master.fx.\(stage.uuidString).input.gain")
    }

    func testMalformedAddressesParseToNothingRatherThanAWrongDestination() {
        for bad in ["", "deck.c.opacity", "deck.a.fx.not-a-uuid.mix", "mixer.blackout",
                    "deck.a.input", "master.fx.\(stage.uuidString)", "deck.a.opacity.extra"] {
            XCTAssertNil(ModDestination(address: bad), "\(bad) must not resolve to anything")
        }
    }

    /// Spec §4.3 — blackout is structurally unreachable, exactly as phase 3a made it unreachable
    /// from show mode. This is the falsifiable version: the catalogue the UI offers and the applier
    /// can write is pinned to an explicit set, so a blackout case joining it fails here.
    func testTheAddressableCatalogueIsExactlyTheSpecsAndExcludesBlackout() {
        let catalogue = ModDestination.catalogue(
            deckInputs: [.one: ["speed"], .two: []],
            deckFX: [.one: [stage: ["threshold"]], .two: [:]],
            masterFX: [:])

        XCTAssertEqual(Set(catalogue), Set([
            .crossfader,
            .deckOpacity(.one), .deckBlend(.one),
            .deckOpacity(.two), .deckBlend(.two),
            .deckInput(.one, "speed"),
            .deckFX(.one, stage, .mix), .deckFX(.one, stage, .input("threshold")),
        ]))
        XCTAssertFalse(catalogue.contains { $0.address.lowercased().contains("black") },
                       "An expression that can kill the output mid-set is a defect with no upside")
    }

    func testTheFXScopeIsCarriedByTheAddressRatherThanInferred() {
        XCTAssertEqual(ModDestination.deckFX(.two, stage, .mix).fxScope, .deck(.two))
        XCTAssertEqual(ModDestination.masterFX(stage, .mix).fxScope, .master)
        XCTAssertNil(ModDestination.crossfader.fxScope)
    }

    func testAnAddressEncodesAsItsStringSoStoredBindingsAreReadable() throws {
        let destination = ModDestination.deckFX(.one, stage, .input("threshold"))
        let data = try JSONEncoder().encode(destination)

        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       "\"\(destination.address)\"",
                       "One string, not a nested object — the persisted form IS the address")
        XCTAssertEqual(try JSONDecoder().decode(ModDestination.self, from: data), destination)
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: compile failure — `cannot find 'ModDestination' in scope`. (`build-for-testing` opens
no window; use it whenever a step only needs to see a compile fail.)

- [x] **Step 3: Write the implementation**

Create `App/ARShader/ModDestination.swift`:

```swift
import Foundation

/// Which parameter of an FX stage a binding drives.
///
/// `mix` is the stage's own wet/dry; `input` is one of its hosted shader's ISF inputs. Blend mode
/// is deliberately NOT here: spec §4 gives blend an address on the DECK only, where it is one of
/// two mixer choices, rather than on every stage of an unbounded chain.
enum FXParam: Hashable, Codable, Sendable {
    case mix
    case input(String)
}

/// Which chain an FX destination lives in. Carried by the address rather than inferred at apply
/// time — deck A's stage and the master's stage are different destinations even if a rebuilt
/// chain ever handed them the same id.
enum ModFXScope: Hashable, Sendable {
    case deck(DeckID)
    case master
}

/// Everything a binding may drive.
///
/// **Blackout has no case, by construction (spec §4.3).** Phase 3a made blackout structurally
/// unreachable from show mode — no `SectionKey`, no `PanelID` — rather than promising not to touch
/// it. The same reasoning applies with more force here: an expression that can kill the output
/// mid-set is a defect with no upside. The applier's `switch` over this enum is exhaustive, so
/// there is no branch that could reach `MixerState.isBlackedOut` even by mistake.
///
/// The persisted form is the ADDRESS STRING, not a nested object: it is what the operator reads in
/// the ledger, what a rename rewrites, and what a diff shows.
enum ModDestination: Hashable, Sendable {
    case deckInput(DeckID, String)
    case deckOpacity(DeckID)
    case deckBlend(DeckID)
    case deckFX(DeckID, UUID, FXParam)
    case masterFX(UUID, FXParam)
    case crossfader
}

extension ModDestination {
    var address: String {
        switch self {
        case .deckInput(let deck, let name):   return "deck.\(deck.addressLetter).input.\(name)"
        case .deckOpacity(let deck):           return "deck.\(deck.addressLetter).opacity"
        case .deckBlend(let deck):             return "deck.\(deck.addressLetter).blend"
        case .deckFX(let deck, let id, let p):
            return "deck.\(deck.addressLetter).fx.\(id.uuidString).\(p.addressSuffix)"
        case .masterFX(let id, let p):         return "master.fx.\(id.uuidString).\(p.addressSuffix)"
        case .crossfader:                      return "mixer.crossfader"
        }
    }

    /// Parses the string form. Returns nil for anything it does not recognise — an unparsable
    /// stored address is dropped on decode rather than becoming a destination that writes
    /// somewhere unintended.
    init?(address: String) {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "mixer":
            guard parts.count == 2, parts[1] == "crossfader" else { return nil }
            self = .crossfader
        case "deck":
            guard parts.count >= 3, let deck = DeckID(addressLetter: parts[1]) else { return nil }
            switch parts[2] {
            case "opacity":
                guard parts.count == 3 else { return nil }
                self = .deckOpacity(deck)
            case "blend":
                guard parts.count == 3 else { return nil }
                self = .deckBlend(deck)
            case "input":
                guard let name = Self.joinedName(parts, from: 3) else { return nil }
                self = .deckInput(deck, name)
            case "fx":
                guard parts.count >= 5, let id = UUID(uuidString: parts[3]),
                      let param = FXParam(addressParts: parts, from: 4) else { return nil }
                self = .deckFX(deck, id, param)
            default:
                return nil
            }
        case "master":
            guard parts.count >= 4, parts[1] == "fx", let id = UUID(uuidString: parts[2]),
                  let param = FXParam(addressParts: parts, from: 3) else { return nil }
            self = .masterFX(id, param)
        default:
            return nil
        }
    }

    /// ISF input names may contain dots, so the tail is rejoined rather than required to be one
    /// component. Empty tails are rejected — `deck.a.input.` names nothing.
    private static func joinedName(_ parts: [String], from index: Int) -> String? {
        guard parts.count > index else { return nil }
        let name = parts[index...].joined(separator: ".")
        return name.isEmpty ? nil : name
    }

    var fxScope: ModFXScope? {
        switch self {
        case .deckFX(let deck, _, _): return .deck(deck)
        case .masterFX:               return .master
        default:                      return nil
        }
    }

    /// What the ledger shows. Shorter than the address, and never the raw UUID.
    var displayName: String {
        switch self {
        case .deckInput(let d, let n):     return "\(d.displayName) · \(n)"
        case .deckOpacity(let d):          return "\(d.displayName) · opacity"
        case .deckBlend(let d):            return "\(d.displayName) · blend"
        case .deckFX(let d, _, let p):     return "\(d.displayName) FX · \(p.displayName)"
        case .masterFX(_, let p):          return "Master FX · \(p.displayName)"
        case .crossfader:                  return "Crossfader"
        }
    }

    /// Every destination a given instrument state can offer. The UI lists this and the applier
    /// writes only these — so blackout's absence from the enum is also its absence from the
    /// surface.
    static func catalogue(deckInputs: [DeckID: [String]],
                          deckFX: [DeckID: [UUID: [String]]],
                          masterFX: [UUID: [String]]) -> [ModDestination] {
        var out: [ModDestination] = [.crossfader]
        for deck in DeckID.allCases {
            out.append(.deckOpacity(deck))
            out.append(.deckBlend(deck))
            out.append(contentsOf: (deckInputs[deck] ?? []).map { .deckInput(deck, $0) })
            for (stage, inputs) in deckFX[deck] ?? [:] {
                out.append(.deckFX(deck, stage, .mix))
                out.append(contentsOf: inputs.map { .deckFX(deck, stage, .input($0)) })
            }
        }
        for (stage, inputs) in masterFX {
            out.append(.masterFX(stage, .mix))
            out.append(contentsOf: inputs.map { .masterFX(stage, .input($0)) })
        }
        return out
    }
}

extension ModDestination: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = ModDestination(address: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown destination \(raw)"))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(address)
    }
}

extension FXParam {
    var addressSuffix: String {
        switch self {
        case .mix:            return "mix"
        case .input(let name): return "input.\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .mix:            return "mix"
        case .input(let name): return name
        }
    }

    fileprivate init?(addressParts parts: [String], from index: Int) {
        guard parts.count > index else { return nil }
        if parts[index] == "mix" {
            guard parts.count == index + 1 else { return nil }
            self = .mix
            return
        }
        guard parts[index] == "input", parts.count > index + 1 else { return nil }
        let name = parts[(index + 1)...].joined(separator: ".")
        guard !name.isEmpty else { return nil }
        self = .input(name)
    }
}

extension DeckID {
    /// Decks are "A" and "B" on the surface and 1 / 2 in the layer stack; addresses use the
    /// lowercase letter, which is what the spec writes and what the operator reads.
    var addressLetter: String { self == .one ? "a" : "b" }

    init?(addressLetter: String) {
        switch addressLetter {
        case "a": self = .one
        case "b": self = .two
        default:  return nil
        }
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModDestinationTests 2>&1 | tail -20
```

Expected: PASS, 6 tests.

- [x] **Step 5: Prove the blackout gate can fail**

Temporarily add `out.append(.deckOpacity(.one))`-style noise is not the mutation — the real one is
a blackout address. Add a case `case blackout` to `ModDestination`, give it
`address = "mixer.blackout"`, and append it in `catalogue`. Re-run Step 4.

Expected: FAIL on both `testTheAddressableCatalogueIsExactlyTheSpecs…` assertions. Revert and
re-run to confirm PASS. Record it in the Task 13 evidence table.

- [x] **Step 6: Commit**

```bash
git add App/ARShader/ModDestination.swift App/ARShaderTests/ModDestinationTests.swift
git commit -m "feat(mod): the destination address space, with blackout structurally excluded"
```

---

## Task 3: The source registry

**Files:**
- Create: `App/ARShader/ModSource.swift`
- Test: `App/ARShaderTests/ModSourceTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum ModOutputKind: String, Codable, Sendable { case continuous, counter, scalar, phase }`
  - `struct ModOutputDescriptor: Sendable, Equatable` — `address`, `kind`, `range`, `provenance`,
    `staleAfter`
  - `struct ModReading: Sendable, Equatable` — `value`, `isValid`, `age`, `secondsSinceIncrement`
  - `struct ModSnapshot: Sendable` — `now`, `dt`, `frame`, `reading(_ address: String) -> ModReading?`,
    `addresses: [String]`
  - `final class ModSourceRegistry: @unchecked Sendable` — `register(_:now:)`, `publish(_:to:now:)`,
    `increment(_:now:)`, `heartbeat(_:now:)`, `snapshot(now:dt:frame:)`, `descriptors()`
  Tasks 4, 6, 7, 8 and 12 use exactly these names.

- [x] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModSourceTests.swift`:

```swift
import XCTest

/// Spec §3 (the provider-neutral contract), §2.2 (`since`) and §7 (idle on loss).
final class ModSourceTests: XCTestCase {

    private func makeRegistry() -> ModSourceRegistry {
        let registry = ModSourceRegistry()
        registry.register(ModOutputDescriptor(address: "stub/level", kind: .continuous,
                                              range: 0...1, provenance: "Test",
                                              staleAfter: 0.5), now: 0)
        registry.register(ModOutputDescriptor(address: "stub/kick", kind: .counter,
                                              range: 0...Double.greatestFiniteMagnitude,
                                              provenance: "Test", staleAfter: 0.5), now: 0)
        return registry
    }

    func testAPublishedValueIsReadBackFromTheSnapshot() {
        let registry = makeRegistry()
        registry.publish(0.75, to: "stub/level", now: 1.0)

        let reading = registry.snapshot(now: 1.0, dt: 1.0 / 60, frame: 1).reading("stub/level")

        XCTAssertEqual(reading?.value, 0.75)
        XCTAssertTrue(reading?.isValid == true)
    }

    /// §2.2 — `since` is seconds since the COUNTER last incremented, and it is what makes one
    /// kick drive a 2 ms strobe and a 2 s swell at the same time with no per-route state.
    func testSinceMeasuresFromTheLastIncrementNotTheLastPublish() {
        let registry = makeRegistry()
        registry.increment("stub/kick", now: 10.0)

        registry.heartbeat("stub/kick", now: 10.25)
        let quarterSecondLater = registry.snapshot(now: 10.25, dt: 1.0 / 60, frame: 2)
        XCTAssertEqual(quarterSecondLater.reading("stub/kick")?.secondsSinceIncrement ?? 0,
                       0.25, accuracy: 1e-9,
                       "A heartbeat keeps the source LIVE without pretending an event happened")

        registry.increment("stub/kick", now: 10.5)
        let afterSecondHit = registry.snapshot(now: 10.5, dt: 1.0 / 60, frame: 3)
        XCTAssertEqual(afterSecondHit.reading("stub/kick")?.secondsSinceIncrement ?? 1, 0,
                       accuracy: 1e-9)
    }

    /// §2.2 — before the first increment, `since` measures from REGISTRATION, so an expression is
    /// never handed a negative or an absurd number on the first frame.
    func testSinceBeforeTheFirstIncrementMeasuresFromRegistration() {
        let registry = makeRegistry()

        let reading = registry.snapshot(now: 3.0, dt: 1.0 / 60, frame: 1).reading("stub/kick")

        XCTAssertEqual(reading?.secondsSinceIncrement ?? -1, 3.0, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(reading?.secondsSinceIncrement ?? -1, 0,
                                    "`since` is monotonic within a frame and never negative")
    }

    /// §7 — a lost source publishes a DEFINED idle value and flags itself invalid. Decaying to
    /// idle rather than freezing is deliberate: a frozen shader reads as a broken app.
    func testALostContinuousSourceReadsZeroAndInvalidRatherThanItsLastValue() {
        let registry = makeRegistry()
        registry.publish(0.9, to: "stub/level", now: 1.0)

        let reading = registry.snapshot(now: 1.6, dt: 1.0 / 60, frame: 9).reading("stub/level")

        XCTAssertEqual(reading?.value, 0, "continuous idles to 0")
        XCTAssertFalse(reading?.isValid == true)
        XCTAssertEqual(reading?.age ?? 0, 0.6, accuracy: 1e-9)
    }

    /// §7 — a counter FREEZES rather than idling to zero: the count of kicks so far is still true
    /// when the provider goes away.
    func testALostCounterFreezesRatherThanResetting() {
        let registry = makeRegistry()
        registry.increment("stub/kick", now: 1.0)
        registry.increment("stub/kick", now: 1.1)

        let reading = registry.snapshot(now: 5.0, dt: 1.0 / 60, frame: 99).reading("stub/kick")

        XCTAssertEqual(reading?.value, 2, "the counter holds its count")
        XCTAssertFalse(reading?.isValid == true)
    }

    /// A provider with no heartbeat concept — the manual source is always there — declares
    /// `staleAfter: .infinity` and never goes invalid. Liveness is not faked for it.
    func testAProviderWithNoHeartbeatConceptIsAlwaysValid() {
        let registry = ModSourceRegistry()
        registry.register(ModOutputDescriptor(address: "manual/lfo", kind: .continuous,
                                              range: 0...1, provenance: "Manual",
                                              staleAfter: .infinity), now: 0)
        registry.publish(0.5, to: "manual/lfo", now: 0)

        XCTAssertTrue(registry.snapshot(now: 3_600, dt: 1.0 / 60, frame: 1)
                        .reading("manual/lfo")?.isValid == true)
    }

    func testAnUnknownAddressReadsAsNothing() {
        XCTAssertNil(makeRegistry().snapshot(now: 0, dt: 0, frame: 0).reading("audio/kick"))
    }

    /// One frozen generation per frame (§5.1): a value published AFTER a snapshot is taken must
    /// not appear in it, or two destinations bound to one source can read it a frame apart.
    func testASnapshotIsFrozenAgainstLaterPublishes() {
        let registry = makeRegistry()
        registry.publish(0.2, to: "stub/level", now: 1.0)

        let snapshot = registry.snapshot(now: 1.0, dt: 1.0 / 60, frame: 1)
        registry.publish(0.8, to: "stub/level", now: 1.0)

        XCTAssertEqual(snapshot.reading("stub/level")?.value, 0.2,
                       "The frame's snapshot is a value, not a live view of the registry")
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'ModSourceRegistry' in scope`.

- [x] **Step 3: Write the implementation**

Create `App/ARShader/ModSource.swift`:

```swift
import Foundation

/// What a source output MEANS, which is what decides its idle value and whether `since()` applies.
enum ModOutputKind: String, Codable, Sendable {
    /// 0..1, continuously updated. Idles to 0.
    case continuous
    /// Monotonically increasing event count. `since()` is defined for this kind and no other.
    /// Freezes on loss — the count so far is still true.
    case counter
    /// Unbounded (dB, ratios). Idles to 0.
    case scalar
    /// 0..1 wrapping. Holds its last value on loss.
    case phase
}

/// The declared contract for one output. This is the provider-neutral shape the prior-art dossier
/// argues for (spec §3): audio, MIDI, OSC, a beat clock and future sensors all publish through it
/// with no engine change.
struct ModOutputDescriptor: Sendable, Equatable {
    let address: String
    let kind: ModOutputKind
    let range: ClosedRange<Double>
    /// Which provider — for display and diagnostics.
    let provenance: String
    /// How long without a heartbeat before the output counts as lost. `.infinity` for providers
    /// with no heartbeat concept (the manual source is always there); liveness is never faked.
    let staleAfter: Double
}

/// One output as an expression sees it this frame.
struct ModReading: Sendable, Equatable {
    /// Idle-substituted when the source is lost (§7).
    let value: Double
    let isValid: Bool
    /// Seconds since the last real update.
    let age: Double
    /// Seconds since the counter last incremented; for non-counter kinds, seconds since
    /// registration. Never negative, monotonic within a frame.
    let secondsSinceIncrement: Double
}

/// One frozen generation of every source value (spec §5.1). A VALUE, not a live view: without
/// this, two destinations bound to the same source can read it a frame apart and visibly drift —
/// a sync failure that presents as a detector problem and is not one.
struct ModSnapshot: Sendable {
    let now: Double
    let dt: Double
    let frame: Int
    private let readings: [String: ModReading]

    init(now: Double, dt: Double, frame: Int, readings: [String: ModReading]) {
        self.now = now
        self.dt = dt
        self.frame = frame
        self.readings = readings
    }

    func reading(_ address: String) -> ModReading? { readings[address] }
    var addresses: [String] { readings.keys.sorted() }
}

/// The registry of named providers and their outputs.
///
/// `@unchecked Sendable` behind one lock, exactly as `MetalRenderCore` and `InstrumentRenderer`
/// are: providers publish from whatever thread they live on (the manual source from main, a future
/// audio tap from its own callback), and the display-link thread snapshots.
final class ModSourceRegistry: @unchecked Sendable {
    private struct Entry {
        let descriptor: ModOutputDescriptor
        var value: Double
        var count: Double
        var lastUpdate: Double
        var lastIncrement: Double
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// Registering the same address twice REPLACES the descriptor and keeps nothing — a provider
    /// reloading must not inherit a stale value from its previous life.
    func register(_ descriptor: ModOutputDescriptor, now: Double) {
        lock.lock(); defer { lock.unlock() }
        entries[descriptor.address] = Entry(descriptor: descriptor, value: 0, count: 0,
                                            lastUpdate: now, lastIncrement: now)
    }

    func unregister(_ address: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: address)
    }

    func publish(_ value: Double, to address: String, now: Double) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[address] else { return }
        entry.value = value
        entry.lastUpdate = now
        entries[address] = entry
    }

    /// The counter idiom: one increment is one event. `since()` measures from here.
    func increment(_ address: String, now: Double) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[address] else { return }
        entry.count += 1
        entry.value = entry.count
        entry.lastUpdate = now
        entry.lastIncrement = now
        entries[address] = entry
    }

    /// "I am still here" without claiming an event happened. A counter that has been quiet for
    /// ten seconds is not lost; a provider that stopped delivering buffers is.
    func heartbeat(_ address: String, now: Double) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[address] else { return }
        entry.lastUpdate = now
        entries[address] = entry
    }

    func descriptors() -> [ModOutputDescriptor] {
        lock.lock(); defer { lock.unlock() }
        return entries.values.map(\.descriptor).sorted { $0.address < $1.address }
    }

    func snapshot(now: Double, dt: Double, frame: Int) -> ModSnapshot {
        lock.lock()
        let current = entries
        lock.unlock()

        var readings: [String: ModReading] = [:]
        readings.reserveCapacity(current.count)
        for (address, entry) in current {
            let age = max(0, now - entry.lastUpdate)
            let isValid = age <= entry.descriptor.staleAfter
            readings[address] = ModReading(
                value: isValid ? entry.value : Self.idleValue(for: entry),
                isValid: isValid,
                age: age,
                secondsSinceIncrement: max(0, now - entry.lastIncrement))
        }
        return ModSnapshot(now: now, dt: dt, frame: frame, readings: readings)
    }

    /// §7 — the defined idle value per kind. Decaying to idle rather than freezing is deliberate
    /// for the continuous kinds: a frozen shader reads as a broken app, a still one reads as
    /// stopped music, and only the second is true.
    private static func idleValue(for entry: Entry) -> Double {
        switch entry.descriptor.kind {
        case .continuous, .scalar: return 0
        case .counter, .phase:     return entry.value
        }
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModSourceTests 2>&1 | tail -20
```

Expected: PASS, 8 tests.

- [x] **Step 5: Prove the frame-coherence gate can fail**

**CORRECTED 2026-08-02 — the originally prescribed mutation does not fail this test.** It said to
drop the `let current = entries` copy and iterate `entries` directly after the unlock. That was
run: it PASSES, 8/8. The copy buys THREAD safety, not frame coherence — either way `readings` is
still built eagerly inside `snapshot()`, so a publish that happens afterwards cannot reach it. A
mutation that passes is not evidence, and recording it as proven would have been exactly the
un-failable-gate problem §9.1 exists to catch.

The gate's real subject is that `ModSnapshot` holds a **value**. So mutate it into a live view:
give `ModSnapshot` a `private let live: ModSourceRegistry?`, have `reading(_:)` prefer
`live.liveReading(address, now: now)` (a lock-guarded lookup that recomputes from `entries`), and
pass `live: self` from `snapshot(now:dt:frame:)`. Re-run Step 4.

Expected: FAIL on `testASnapshotIsFrozenAgainstLaterPublishes` — the snapshot reports `0.8`. Revert,
re-run to confirm PASS, and record it in the Task 13 evidence table.

- [x] **Step 6: Commit**

```bash
git add App/ARShader/ModSource.swift App/ARShaderTests/ModSourceTests.swift
git commit -m "feat(mod): the source registry, its per-frame snapshot and the idle-on-loss doctrine"
```

---

## Task 4: The manual source — a real performance control

**Files:**
- Create: `App/ARShader/ManualSource.swift`
- Test: `App/ARShaderTests/ManualSourceTests.swift`

**Interfaces:**
- Consumes: `ModSourceRegistry`, `ModOutputDescriptor`, `ModOutputKind` from Task 3.
- Produces:
  - `enum LFOShape: String, CaseIterable, Codable, Sendable { case sine, triangle, saw, square }`
  - `final class ManualSourceRuntime: @unchecked Sendable` — `init(registry:now:)`,
    `setLFO(rate:shape:)`, `setBeatPeriod(_:)`, `trigger(now:)`, `tick(now:dt:)`
  - `@MainActor final class ManualSource: ObservableObject` — `lfoRate`, `lfoShape`, `tempoBPM`,
    `trigger()`, `tap(at:)`, `runtime`
  - Addresses published: `manual/trigger` (counter), `manual/lfo` (continuous), `manual/tap`
    (phase)
  Tasks 10 and 12 use exactly these names.

- [x] **Step 1: Write the failing test**

Create `App/ARShaderTests/ManualSourceTests.swift`:

```swift
import XCTest

/// Spec §3.1 — the stub provider ships in this slice and stays permanently. It is a legitimate
/// live control: hitting the trigger on the downbeat is a real technique, and it gives `since()`
/// envelopes with no audio in existence.
final class ManualSourceTests: XCTestCase {

    private func makeRuntime() -> (ManualSourceRuntime, ModSourceRegistry) {
        let registry = ModSourceRegistry()
        return (ManualSourceRuntime(registry: registry, now: 0), registry)
    }

    func testTheProviderRegistersItsThreeOutputsWithTheRightKinds() {
        let (_, registry) = makeRuntime()

        let byAddress = Dictionary(uniqueKeysWithValues:
            registry.descriptors().map { ($0.address, $0) })

        XCTAssertEqual(byAddress["manual/trigger"]?.kind, .counter)
        XCTAssertEqual(byAddress["manual/lfo"]?.kind, .continuous)
        XCTAssertEqual(byAddress["manual/tap"]?.kind, .phase)
        XCTAssertEqual(byAddress.count, 3)
    }

    func testTheTriggerIncrementsSoSinceCanShapeIt() {
        let (runtime, registry) = makeRuntime()

        runtime.trigger(now: 4.0)
        runtime.tick(now: 4.5, dt: 0.5)

        let reading = registry.snapshot(now: 4.5, dt: 0.5, frame: 1).reading("manual/trigger")
        XCTAssertEqual(reading?.value, 1)
        XCTAssertEqual(reading?.secondsSinceIncrement ?? 0, 0.5, accuracy: 1e-9)
    }

    /// §5.2 — rate-driven motion INTEGRATES phase. Multiplying a live rate by absolute time makes
    /// a rate change jump the phase discontinuously, which on a strobe is a visible glitch.
    func testChangingTheLFORateDoesNotJumpThePhase() {
        let (runtime, registry) = makeRuntime()
        runtime.setLFO(rate: 1.0, shape: .saw)

        for _ in 0..<25 { runtime.tick(now: 0, dt: 0.01) }   // 0.25 s at 1 Hz -> phase 0.25
        let before = registry.snapshot(now: 0.25, dt: 0.01, frame: 25).reading("manual/lfo")?.value

        runtime.setLFO(rate: 8.0, shape: .saw)
        runtime.tick(now: 0.26, dt: 0.01)
        let after = registry.snapshot(now: 0.26, dt: 0.01, frame: 26).reading("manual/lfo")?.value

        XCTAssertEqual(before ?? -1, 0.25, accuracy: 1e-6)
        XCTAssertEqual(after ?? -1, 0.33, accuracy: 1e-6,
                       "One 0.01 s step at 8 Hz advances 0.08 from where the phase ALREADY was — "
                       + "a rate multiplied by absolute time would have jumped to 2.08 -> 0.08")
    }

    func testEachLFOShapeSpansItsFullRangeOverOneCycle() {
        for shape in LFOShape.allCases {
            let (runtime, registry) = makeRuntime()
            runtime.setLFO(rate: 1.0, shape: shape)
            var seen: [Double] = []
            for step in 0..<100 {
                runtime.tick(now: Double(step) * 0.01, dt: 0.01)
                let value = registry.snapshot(now: Double(step) * 0.01, dt: 0.01, frame: step)
                    .reading("manual/lfo")?.value ?? .nan
                seen.append(value)
            }
            XCTAssertLessThanOrEqual(seen.min() ?? 1, 0.05, "\(shape) reaches its floor")
            XCTAssertGreaterThanOrEqual(seen.max() ?? 0, 0.95, "\(shape) reaches its ceiling")
            XCTAssertTrue(seen.allSatisfy { $0 >= 0 && $0 <= 1 }, "\(shape) stays inside 0...1")
        }
    }

    /// Tap tempo: two taps set the period, and the phase keeps running at that period after the
    /// operator stops tapping (§3.1 — "holds last tempo when tapping stops").
    @MainActor
    func testTwoTapsSetTheTempoAndThePhaseKeepsRunningAfterwards() {
        let registry = ModSourceRegistry()
        let source = ManualSource(registry: registry, now: 0)

        source.tap(at: 10.0)
        source.tap(at: 10.5)
        XCTAssertEqual(source.tempoBPM, 120, accuracy: 0.001, "0.5 s per beat is 120 BPM")

        source.runtime.tick(now: 10.75, dt: 0.25)
        let phase = registry.snapshot(now: 10.75, dt: 0.25, frame: 1).reading("manual/tap")?.value
        XCTAssertEqual(phase ?? -1, 0.5, accuracy: 1e-6, "half a beat after the last tap")
    }

    @MainActor
    func testAFirstTapAloneChangesNothingAndAStaleTapStartsOver() {
        let registry = ModSourceRegistry()
        let source = ManualSource(registry: registry, now: 0)
        let initial = source.tempoBPM

        source.tap(at: 1.0)
        XCTAssertEqual(source.tempoBPM, initial, "One tap is not an interval")

        source.tap(at: 20.0)
        XCTAssertEqual(source.tempoBPM, initial,
                       "A 19 s gap is someone coming back to it, not a 3 BPM tempo")
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'ManualSourceRuntime' in scope`.

- [x] **Step 3: Write the implementation**

Create `App/ARShader/ManualSource.swift`:

```swift
import Foundation
import Combine

enum LFOShape: String, CaseIterable, Codable, Sendable {
    case sine, triangle, saw, square
}

/// The render-thread half of the manual provider: it integrates phase and publishes into the
/// registry. Split from `ManualSource` for the same reason `MixerState` keeps a render mirror —
/// the operator's controls are `@Published` main-actor state and the display-link thread may not
/// read them.
final class ManualSourceRuntime: @unchecked Sendable {
    static let triggerAddress = "manual/trigger"
    static let lfoAddress = "manual/lfo"
    static let tapAddress = "manual/tap"

    private let registry: ModSourceRegistry
    private let lock = NSLock()
    // ── lock-guarded ──
    private var rate: Double = 1.0
    private var shape: LFOShape = .sine
    private var lfoPhase: Double = 0
    private var beatPeriod: Double = 0.5
    private var beatPhase: Double = 0

    init(registry: ModSourceRegistry, now: Double) {
        self.registry = registry
        // `.infinity`: the manual source is always there. A heartbeat would be theatre.
        registry.register(ModOutputDescriptor(address: Self.triggerAddress, kind: .counter,
                                              range: 0...Double.greatestFiniteMagnitude,
                                              provenance: "Manual", staleAfter: .infinity),
                          now: now)
        registry.register(ModOutputDescriptor(address: Self.lfoAddress, kind: .continuous,
                                              range: 0...1, provenance: "Manual",
                                              staleAfter: .infinity), now: now)
        registry.register(ModOutputDescriptor(address: Self.tapAddress, kind: .phase,
                                              range: 0...1, provenance: "Manual",
                                              staleAfter: .infinity), now: now)
    }

    func setLFO(rate: Double, shape: LFOShape) {
        lock.lock(); defer { lock.unlock() }
        self.rate = max(0, rate)
        self.shape = shape
    }

    /// Seconds per beat. Clamped away from zero: a zero period is a division by zero on the very
    /// next frame, and there is no tempo it could sensibly mean.
    func setBeatPeriod(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        beatPeriod = max(0.05, seconds)
    }

    /// A button press. Incrementing a counter is all it does — every `since()` envelope bound to
    /// it shapes that one edge independently.
    func trigger(now: Double) {
        registry.increment(Self.triggerAddress, now: now)
    }

    /// One frame. Phase INTEGRATES (§5.2): `phase += rate * dt`, so a rate change never jumps.
    func tick(now: Double, dt: Double) {
        lock.lock()
        lfoPhase = (lfoPhase + rate * dt).truncatingRemainder(dividingBy: 1.0)
        if lfoPhase < 0 { lfoPhase += 1 }
        beatPhase = (beatPhase + dt / beatPeriod).truncatingRemainder(dividingBy: 1.0)
        if beatPhase < 0 { beatPhase += 1 }
        let lfoValue = Self.value(of: shape, at: lfoPhase)
        let beat = beatPhase
        lock.unlock()

        registry.publish(lfoValue, to: Self.lfoAddress, now: now)
        registry.publish(beat, to: Self.tapAddress, now: now)
        registry.heartbeat(Self.triggerAddress, now: now)
    }

    /// Resets the beat phase to the downbeat — what a tap MEANS.
    func alignBeat(now: Double) {
        lock.lock(); beatPhase = 0; lock.unlock()
    }

    /// All shapes span the full 0...1 so a destination's range is used, whichever is chosen.
    static func value(of shape: LFOShape, at phase: Double) -> Double {
        switch shape {
        case .sine:     return 0.5 - 0.5 * cos(2 * .pi * phase)
        case .triangle: return phase < 0.5 ? phase * 2 : (1 - phase) * 2
        case .saw:      return phase
        case .square:   return phase < 0.5 ? 0 : 1
        }
    }
}

/// The operator's half: the controls a panel binds to, plus tap-tempo timing.
@MainActor
final class ManualSource: ObservableObject {
    /// A tap gap longer than this is someone coming back to the button, not a tempo.
    static let maxTapInterval: Double = 2.0

    let runtime: ManualSourceRuntime

    @Published var lfoRate: Double = 1.0 { didSet { pushLFO() } }
    @Published var lfoShape: LFOShape = .sine { didSet { pushLFO() } }
    @Published private(set) var tempoBPM: Double = 120

    private var lastTap: Double?

    init(registry: ModSourceRegistry, now: Double) {
        self.runtime = ManualSourceRuntime(registry: registry, now: now)
        pushLFO()
        runtime.setBeatPeriod(60.0 / tempoBPM)
    }

    func trigger(now: Double = CACurrentMediaTime()) { runtime.trigger(now: now) }

    /// Two taps inside `maxTapInterval` set the tempo; every tap realigns the downbeat, which is
    /// what makes tapping along feel like it is doing something even before a second tap lands.
    func tap(at now: Double = CACurrentMediaTime()) {
        defer { lastTap = now }
        runtime.alignBeat(now: now)
        guard let previous = lastTap else { return }
        let interval = now - previous
        guard interval > 0, interval <= Self.maxTapInterval else { return }
        tempoBPM = 60.0 / interval
        runtime.setBeatPeriod(interval)
    }

    private func pushLFO() { runtime.setLFO(rate: lfoRate, shape: lfoShape) }
}
```

Add `import QuartzCore` at the top of the file alongside `Foundation` — `CACurrentMediaTime` is
declared there.

- [x] **Step 4: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ManualSourceTests 2>&1 | tail -20
```

Expected: PASS, 6 tests.

- [x] **Step 5: Commit**

```bash
git add App/ARShader/ManualSource.swift App/ARShaderTests/ManualSourceTests.swift
git commit -m "feat(mod): the manual source — trigger, integrated-phase LFO, tap tempo"
```

---

## Task 5: The expression parser

**Files:**
- Create: `App/ARShader/Expression.swift`
- Test: `App/ARShaderTests/ExpressionTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `indirect enum ExprNode: Equatable, Sendable` — `.number(Double)`, `.identifier(String)`,
    `.string(String)`, `.negate(ExprNode)`, `.binary(ExprOp, ExprNode, ExprNode)`,
    `.call(String, [ExprNode])`
  - `enum ExprOp: String, Sendable { case add, subtract, multiply, divide }`
  - `struct ExpressionError: Error, Equatable` — `message: String`, `offset: Int`
  - `enum ExprSignature` — `arity(of:) -> ClosedRange<Int>?`, `takesSourceAddress(_:) -> Bool`,
    `identifiers: Set<String>`, `functionNames: [String]`
  - `enum ExprParser { static func compile(_ text: String) throws -> ExprNode }`
  Tasks 6, 7 and 12 use exactly these names.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ExpressionTests.swift`:

```swift
import XCTest

/// Spec §2 — expressions are stored as text and compiled on set. A malformed one REMAINS SAVED
/// and inactive with its error visible (§7): losing a half-written driver to a fat-fingered paren
/// is unacceptable in a live tool, so compile failure is a value, never a discard.
final class ExpressionTests: XCTestCase {

    func testANumberIsAnExpression() throws {
        XCTAssertEqual(try ExprParser.compile("0.25"), .number(0.25))
        XCTAssertEqual(try ExprParser.compile("  3 "), .number(3))
    }

    func testMultiplicationBindsTighterThanAddition() throws {
        XCTAssertEqual(try ExprParser.compile("1 + 2 * 3"),
                       .binary(.add, .number(1), .binary(.multiply, .number(2), .number(3))))
    }

    func testSubtractionIsLeftAssociative() throws {
        XCTAssertEqual(try ExprParser.compile("10 - 3 - 2"),
                       .binary(.subtract, .binary(.subtract, .number(10), .number(3)),
                               .number(2)))
    }

    func testParenthesesOverridePrecedence() throws {
        XCTAssertEqual(try ExprParser.compile("(1 + 2) * 3"),
                       .binary(.multiply, .binary(.add, .number(1), .number(2)), .number(3)))
    }

    func testUnaryMinusParsesInFrontOfAnyPrimary() throws {
        XCTAssertEqual(try ExprParser.compile("-time"), .negate(.identifier("time")))
        XCTAssertEqual(try ExprParser.compile("2 * -3"),
                       .binary(.multiply, .number(2), .negate(.number(3))))
    }

    /// The shape the whole slice exists for (§2.2).
    func testTheDecayIdiomParses() throws {
        XCTAssertEqual(try ExprParser.compile(#"exp(-since("audio/kick") / 0.002)"#),
                       .call("exp", [.negate(.binary(.divide,
                                                     .call("since", [.string("audio/kick")]),
                                                     .number(0.002)))]))
    }

    func testTheOffsetIdiomFromTheResearchNoteParses() throws {
        XCTAssertNoThrow(try ExprParser.compile(#"0.2 + ref("hand/pinch") * 2.0"#))
        XCTAssertNoThrow(try ExprParser.compile(#"min(1, max(0, ref("audio/hat") * 1.6))"#))
    }

    func testEveryIdentifierAndFunctionTheSpecListsIsAccepted() throws {
        for identifier in ["time", "dt", "frame", "self"] {
            XCTAssertNoThrow(try ExprParser.compile(identifier), identifier)
        }
        for name in ["sin", "cos", "abs", "sqrt", "floor", "ceil", "exp", "log"] {
            XCTAssertNoThrow(try ExprParser.compile("\(name)(1)"), name)
        }
        XCTAssertNoThrow(try ExprParser.compile("clamp(0.5, 0, 1)"))
        XCTAssertNoThrow(try ExprParser.compile("min(1, 2)"))
        XCTAssertNoThrow(try ExprParser.compile("max(1, 2)"))
        XCTAssertNoThrow(try ExprParser.compile("pow(2, 3)"))
        XCTAssertNoThrow(try ExprParser.compile("spring(0.1, 1, 60, 6)"))
        XCTAssertNoThrow(try ExprParser.compile("spring_v(0.1, 0, 4, 1, 60, 6)"))
        XCTAssertNoThrow(try ExprParser.compile("stagger(2, 8, 0.4, 0)"))
        XCTAssertNoThrow(try ExprParser.compile("anticipate(0.5, 1.7)"))
        XCTAssertNoThrow(try ExprParser.compile("loop_noise(time, 4, 0.3, 7)"))
        XCTAssertNoThrow(try ExprParser.compile(#"valid("manual/lfo")"#))
    }

    func testAnUnknownNameIsACompileErrorRatherThanASilentZero() {
        XCTAssertThrowsError(try ExprParser.compile("wobble(1)")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Unknown function 'wobble'")
        }
        XCTAssertThrowsError(try ExprParser.compile("beat")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Unknown name 'beat'")
        }
    }

    func testTheWrongNumberOfArgumentsIsACompileError() {
        XCTAssertThrowsError(try ExprParser.compile("clamp(1, 2)")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message,
                           "clamp takes 3 arguments, got 2")
        }
    }

    /// `ref`, `since` and `valid` name a SOURCE, and a source address is a string. Passing a
    /// number is caught at compile time, where the operator can see it, rather than evaluating to
    /// something arbitrary every frame.
    func testSourceFunctionsRequireAStringAndOthersRejectOne() {
        XCTAssertThrowsError(try ExprParser.compile("ref(1)")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message,
                           "ref takes a quoted source address")
        }
        XCTAssertThrowsError(try ExprParser.compile(#"sin("audio/kick")"#)) { error in
            XCTAssertEqual((error as? ExpressionError)?.message,
                           "A quoted address is only valid in ref, since or valid")
        }
    }

    func testUnbalancedInputReportsWhereItWentWrong() {
        XCTAssertThrowsError(try ExprParser.compile("(1 + 2")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Expected ')'")
            XCTAssertEqual((error as? ExpressionError)?.offset, 6)
        }
        XCTAssertThrowsError(try ExprParser.compile("1 +")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Expected a value")
        }
        XCTAssertThrowsError(try ExprParser.compile("1 2")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Unexpected '2'")
        }
        XCTAssertThrowsError(try ExprParser.compile("")) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Expected a value")
        }
        XCTAssertThrowsError(try ExprParser.compile(#"ref("unterminated)"#)) { error in
            XCTAssertEqual((error as? ExpressionError)?.message, "Unterminated string")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'ExprParser' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/ARShader/Expression.swift`:

```swift
import Foundation

enum ExprOp: String, Equatable, Sendable {
    case add = "+", subtract = "-", multiply = "*", divide = "/"
}

/// A compiled expression. A tree of values with no evaluation logic — `ExpressionEvaluator` walks
/// it, and the parser is free of anything that could produce a number.
indirect enum ExprNode: Equatable, Sendable {
    case number(Double)
    /// `time`, `dt`, `frame`, `self`.
    case identifier(String)
    /// A quoted source address. Only ever an argument of `ref`, `since` or `valid`.
    case string(String)
    case negate(ExprNode)
    case binary(ExprOp, ExprNode, ExprNode)
    case call(String, [ExprNode])
}

/// A compile failure as a VALUE. Spec §7: a malformed expression remains saved and inactive with
/// its error visible.
struct ExpressionError: Error, Equatable {
    let message: String
    /// Character offset into the source text, for the caret the panel draws.
    let offset: Int
}

/// The vocabulary, as spec §2 lists it and no wider.
///
/// There is deliberately no conditional and no comparison operator, even though the prior-art system's own
/// shipped expressions had a conditional. Gating here is arithmetic —
/// multiplying by `valid(...)`, or by a 0/1 shape built from the math that IS here. Widening the
/// language is a tuning-surface decision, not this slice's.
enum ExprSignature {
    static let identifiers: Set<String> = ["time", "dt", "frame", "self"]

    /// Name -> permitted argument count. A range, because `min`/`max` are variadic in spirit but
    /// pinned to two here so an arity mistake is still caught.
    private static let arities: [String: ClosedRange<Int>] = [
        "ref": 1...1, "since": 1...1, "valid": 1...1,
        "sin": 1...1, "cos": 1...1, "abs": 1...1, "sqrt": 1...1,
        "floor": 1...1, "ceil": 1...1, "exp": 1...1, "log": 1...1,
        "min": 2...2, "max": 2...2, "pow": 2...2, "clamp": 3...3,
        "spring": 4...4, "spring_v": 6...6, "stagger": 4...4,
        "anticipate": 2...2, "loop_noise": 4...4,
    ]

    private static let sourceFunctions: Set<String> = ["ref", "since", "valid"]

    static func arity(of name: String) -> ClosedRange<Int>? { arities[name] }
    static func takesSourceAddress(_ name: String) -> Bool { sourceFunctions.contains(name) }
    /// Sorted, for the panel's completion list.
    static var functionNames: [String] { arities.keys.sorted() }
}

/// Recursive descent over the grammar:
///
///     expr    := term (('+' | '-') term)*
///     term    := unary (('*' | '/') unary)*
///     unary   := '-' unary | primary
///     primary := number | string | ident '(' args ')' | ident | '(' expr ')'
enum ExprParser {
    static func compile(_ text: String) throws -> ExprNode {
        var parser = Parser(text: Array(text))
        let node = try parser.parseExpression()
        try parser.expectEnd()
        return node
    }

    private struct Parser {
        let text: [Character]
        var index = 0

        mutating func parseExpression() throws -> ExprNode {
            var left = try parseTerm()
            while let op = peekOperator(in: [.add, .subtract]) {
                index += 1
                left = .binary(op, left, try parseTerm())
            }
            return left
        }

        mutating func parseTerm() throws -> ExprNode {
            var left = try parseUnary()
            while let op = peekOperator(in: [.multiply, .divide]) {
                index += 1
                left = .binary(op, left, try parseUnary())
            }
            return left
        }

        mutating func parseUnary() throws -> ExprNode {
            skipSpace()
            if current == "-" {
                index += 1
                return .negate(try parseUnary())
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> ExprNode {
            skipSpace()
            guard let character = current else { throw error("Expected a value") }
            if character == "(" {
                index += 1
                let inner = try parseExpression()
                skipSpace()
                guard current == ")" else { throw error("Expected ')'") }
                index += 1
                return inner
            }
            if character == "\"" { throw error("A quoted address is only valid in ref, since or valid") }
            if character.isNumber || character == "." { return .number(try parseNumber()) }
            if character.isLetter || character == "_" { return try parseNameOrCall() }
            throw error("Unexpected '\(character)'")
        }

        mutating func parseNumber() throws -> Double {
            let start = index
            while let c = current, c.isNumber || c == "." { index += 1 }
            guard let value = Double(String(text[start..<index])) else {
                throw ExpressionError(message: "Unexpected '\(String(text[start..<index]))'",
                                      offset: start)
            }
            return value
        }

        mutating func parseNameOrCall() throws -> ExprNode {
            let start = index
            while let c = current, c.isLetter || c.isNumber || c == "_" { index += 1 }
            let name = String(text[start..<index])
            skipSpace()
            guard current == "(" else {
                guard ExprSignature.identifiers.contains(name) else {
                    throw ExpressionError(message: "Unknown name '\(name)'", offset: start)
                }
                return .identifier(name)
            }
            guard let arity = ExprSignature.arity(of: name) else {
                throw ExpressionError(message: "Unknown function '\(name)'", offset: start)
            }
            index += 1   // consume '('
            var arguments: [ExprNode] = []
            skipSpace()
            if current != ")" {
                repeat {
                    arguments.append(try parseArgument(of: name))
                    skipSpace()
                    guard current == "," else { break }
                    index += 1
                } while true
            }
            skipSpace()
            guard current == ")" else { throw error("Expected ')'") }
            index += 1
            guard arity.contains(arguments.count) else {
                throw ExpressionError(
                    message: "\(name) takes \(arity.lowerBound) argument"
                        + (arity.lowerBound == 1 ? "" : "s") + ", got \(arguments.count)",
                    offset: start)
            }
            return .call(name, arguments)
        }

        /// `ref` / `since` / `valid` take a quoted address and nothing else; every other function
        /// takes an expression and never a string.
        mutating func parseArgument(of function: String) throws -> ExprNode {
            skipSpace()
            if ExprSignature.takesSourceAddress(function) {
                guard current == "\"" else {
                    throw error("\(function) takes a quoted source address")
                }
                return .string(try parseString())
            }
            return try parseExpression()
        }

        mutating func parseString() throws -> String {
            index += 1   // consume the opening quote
            let start = index
            while let c = current, c != "\"" { index += 1 }
            guard current == "\"" else {
                throw ExpressionError(message: "Unterminated string", offset: start)
            }
            let value = String(text[start..<index])
            index += 1
            return value
        }

        mutating func expectEnd() throws {
            skipSpace()
            if let c = current { throw ExpressionError(message: "Unexpected '\(c)'", offset: index) }
        }

        // ── cursor ──

        var current: Character? { index < text.count ? text[index] : nil }

        mutating func skipSpace() {
            while let c = current, c == " " || c == "\t" || c == "\n" { index += 1 }
        }

        mutating func peekOperator(in allowed: [ExprOp]) -> ExprOp? {
            skipSpace()
            guard let c = current, let op = ExprOp(rawValue: String(c)),
                  allowed.contains(op) else { return nil }
            return op
        }

        func error(_ message: String) -> ExpressionError {
            ExpressionError(message: message, offset: index)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ExpressionTests 2>&1 | tail -20
```

Expected: PASS, 12 tests. If an offset assertion disagrees by one, fix the TEST to the offset the
parser actually reports and note it — the caret position is a UI nicety, the message is the
contract.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/Expression.swift App/ARShaderTests/ExpressionTests.swift
git commit -m "feat(mod): the expression grammar, with compile failures as values"
```

---

## Task 6: The function library and the evaluator

**Files:**
- Create: `App/ARShader/ExpressionFunctions.swift`
- Create: `App/ARShader/ExpressionEvaluator.swift`
- Test: `App/ARShaderTests/ExpressionEvaluatorTests.swift`

**Interfaces:**
- Consumes: `ExprNode`, `ExprOp`, `ExprSignature` (Task 5); `ModSnapshot`, `ModReading` (Task 3).
- Produces:
  - `enum MotionFunctions` — `spring(t:mass:stiffness:damping:)`,
    `springV(t:x0:v0:mass:stiffness:damping:)`, `stagger(index:count:span:style:)`,
    `anticipate(t:bias:)`, `loopNoise(t:period:radius:seed:)`
  - `struct ExprContext: Sendable` — `snapshot: ModSnapshot`, `selfValue: Double`
  - `enum ExpressionEvaluator { static func evaluate(_ node: ExprNode, in context: ExprContext) -> Double }`
  Task 7 uses exactly these names.

**Note on provenance.** Only the NAMES of the motion functions came from prior-art research; it
listed them and nothing more. The formulas below are ours. They are pinned by tests precisely
because nothing external defines them — a later change to `spring`'s damping convention would
silently retune every patch an operator had dialled in.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ExpressionEvaluatorTests.swift`:

```swift
import XCTest

/// Spec §2 vocabulary, §2.2 `since`, §7 non-finite production (containment is the ENGINE's job,
/// Task 7 — the evaluator is allowed to return NaN and the test pins that it does).
final class ExpressionEvaluatorTests: XCTestCase {

    private func snapshot(now: Double = 10, dt: Double = 1.0 / 60, frame: Int = 600,
                          readings: [String: ModReading] = [:]) -> ModSnapshot {
        ModSnapshot(now: now, dt: dt, frame: frame, readings: readings)
    }

    private func evaluate(_ text: String, snapshot: ModSnapshot? = nil,
                          selfValue: Double = 0) throws -> Double {
        let node = try ExprParser.compile(text)
        return ExpressionEvaluator.evaluate(
            node, in: ExprContext(snapshot: snapshot ?? self.snapshot(), selfValue: selfValue))
    }

    private func live(_ value: Double, sinceIncrement: Double = 0) -> ModReading {
        ModReading(value: value, isValid: true, age: 0, secondsSinceIncrement: sinceIncrement)
    }

    func testArithmeticAndPrecedence() throws {
        XCTAssertEqual(try evaluate("1 + 2 * 3"), 7, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("(1 + 2) * 3"), 9, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("10 - 3 - 2"), 5, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("-2 * -3"), 6, accuracy: 1e-12)
    }

    func testTheBuiltInIdentifiers() throws {
        let snap = snapshot(now: 12.5, dt: 0.02, frame: 750)
        XCTAssertEqual(try evaluate("time", snapshot: snap), 12.5, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("dt", snapshot: snap), 0.02, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("frame", snapshot: snap), 750, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("self", snapshot: snap, selfValue: 0.42), 0.42, accuracy: 1e-12)
    }

    func testRefSinceAndValidReadTheSnapshot() throws {
        let snap = snapshot(readings: ["audio/kick": live(3, sinceIncrement: 0.5)])
        XCTAssertEqual(try evaluate(#"ref("audio/kick")"#, snapshot: snap), 3, accuracy: 1e-12)
        XCTAssertEqual(try evaluate(#"since("audio/kick")"#, snapshot: snap), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try evaluate(#"valid("audio/kick")"#, snapshot: snap), 1, accuracy: 1e-12)
    }

    /// §7 — an absent or lost source is 0 through `ref` and 0 through `valid`, so the arithmetic
    /// gating idiom (`ref(x) * valid(x)`) works without a conditional in the language.
    func testAnAbsentSourceReadsZeroAndInvalid() throws {
        XCTAssertEqual(try evaluate(#"ref("audio/kick")"#), 0, accuracy: 1e-12)
        XCTAssertEqual(try evaluate(#"valid("audio/kick")"#), 0, accuracy: 1e-12)
        let lost = ModReading(value: 0, isValid: false, age: 9, secondsSinceIncrement: 9)
        XCTAssertEqual(try evaluate(#"valid("audio/kick")"#,
                                    snapshot: snapshot(readings: ["audio/kick": lost])), 0)
    }

    /// §2.2 — the whole reason the slice exists. One source, two time constants, independent
    /// shaping, zero per-route state.
    ///
    /// Mutation that must fail this test: change either time constant in the expressions below.
    func testOneCounterDrivesAStrobeAndASwellFromTheSameEdge() throws {
        let snap = snapshot(readings: ["audio/kick": live(1, sinceIncrement: 0.004)])

        let strobe = try evaluate(#"exp(-since("audio/kick") / 0.002)"#, snapshot: snap)
        let swell = try evaluate(#"exp(-since("audio/kick") / 2.0)"#, snapshot: snap)

        XCTAssertEqual(strobe, exp(-2), accuracy: 1e-9)
        XCTAssertLessThan(strobe, 0.14, "2 ms constant: two time constants in, it is nearly out")
        XCTAssertGreaterThan(swell, 0.99, "2 s constant: 4 ms in, it has barely moved")
    }

    func testTheMathVocabulary() throws {
        XCTAssertEqual(try evaluate("sin(0)"), 0, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("cos(0)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("abs(0 - 3)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("clamp(5, 0, 1)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("clamp(-5, 0, 1)"), 0, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("min(2, 7)"), 2, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("max(2, 7)"), 7, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("sqrt(9)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("floor(1.9)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("ceil(1.1)"), 2, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("exp(0)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("log(1)"), 0, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("pow(2, 10)"), 1024, accuracy: 1e-9)
    }

    /// The evaluator PRODUCES non-finite values rather than hiding them. Containment is a single
    /// choke point at the engine boundary (§7), and a guard in two places is a guard that drifts.
    func testDivisionByZeroAndDomainErrorsProduceNonFiniteValues() throws {
        XCTAssertTrue(try evaluate("1 / 0").isInfinite)
        XCTAssertTrue(try evaluate("sqrt(0 - 1)").isNaN)
        XCTAssertTrue(try evaluate("log(0)").isInfinite)
    }

    func testSpringRisesToOneAndSettlesThere() {
        XCTAssertEqual(MotionFunctions.spring(t: 0, mass: 1, stiffness: 60, damping: 6), 0,
                       accuracy: 1e-9, "A spring starts where it was")
        XCTAssertEqual(MotionFunctions.spring(t: 10, mass: 1, stiffness: 60, damping: 6), 1,
                       accuracy: 1e-3, "and ends at its target")
        let overshoot = (1...200).map {
            MotionFunctions.spring(t: Double($0) * 0.005, mass: 1, stiffness: 200, damping: 4)
        }.max() ?? 0
        XCTAssertGreaterThan(overshoot, 1.05, "An underdamped spring overshoots — that is the point")
    }

    func testSpringVStartsAtItsDisplacementAndDecaysToZero() {
        XCTAssertEqual(MotionFunctions.springV(t: 0, x0: 0, v0: 4, mass: 1, stiffness: 60,
                                               damping: 6), 0, accuracy: 1e-9)
        XCTAssertEqual(MotionFunctions.springV(t: 0, x0: 0.5, v0: 0, mass: 1, stiffness: 60,
                                               damping: 6), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MotionFunctions.springV(t: 20, x0: 0.5, v0: 4, mass: 1, stiffness: 60,
                                               damping: 6), 0, accuracy: 1e-3)
    }

    func testStaggerSpreadsAcrossItsSpanAndSurvivesDegenerateCounts() {
        XCTAssertEqual(MotionFunctions.stagger(index: 0, count: 5, span: 0.4, style: 0), 0)
        XCTAssertEqual(MotionFunctions.stagger(index: 4, count: 5, span: 0.4, style: 0), 0.4,
                       accuracy: 1e-12)
        XCTAssertEqual(MotionFunctions.stagger(index: 0, count: 1, span: 0.4, style: 0), 0,
                       "One element has nothing to stagger against — never a divide by zero")
        XCTAssertEqual(MotionFunctions.stagger(index: 0, count: 5, span: 0.4, style: 1), 0.4,
                       accuracy: 1e-12, "style 1 is centre-out: the edges go last")
        XCTAssertEqual(MotionFunctions.stagger(index: 0, count: 5, span: 0.4, style: 2), 0.4,
                       accuracy: 1e-12, "style 2 is reversed")
    }

    func testAnticipateDipsBelowZeroBeforeReachingOne() {
        XCTAssertEqual(MotionFunctions.anticipate(t: 0, bias: 1.7), 0, accuracy: 1e-12)
        XCTAssertEqual(MotionFunctions.anticipate(t: 1, bias: 1.7), 1, accuracy: 1e-12)
        XCTAssertLessThan(MotionFunctions.anticipate(t: 0.2, bias: 1.7), 0,
                          "It winds up before it moves — that is what anticipation is")
    }

    func testLoopNoiseIsSeamlessBoundedAndDeterministic() {
        let atZero = MotionFunctions.loopNoise(t: 0, period: 4, radius: 0.3, seed: 7)
        let atPeriod = MotionFunctions.loopNoise(t: 4, period: 4, radius: 0.3, seed: 7)
        XCTAssertEqual(atZero, atPeriod, accuracy: 1e-9, "It loops — that is its whole job")
        XCTAssertEqual(MotionFunctions.loopNoise(t: 1.3, period: 4, radius: 0.3, seed: 7),
                       MotionFunctions.loopNoise(t: 1.3, period: 4, radius: 0.3, seed: 7),
                       "Deterministic: the same patch looks the same at the next show")
        XCTAssertNotEqual(MotionFunctions.loopNoise(t: 1.3, period: 4, radius: 0.3, seed: 7),
                          MotionFunctions.loopNoise(t: 1.3, period: 4, radius: 0.3, seed: 8),
                          accuracy: 1e-12, "and the seed does something")
        for step in 0..<400 {
            let value = MotionFunctions.loopNoise(t: Double(step) * 0.01, period: 4,
                                                  radius: 0.3, seed: 7)
            XCTAssertLessThanOrEqual(abs(value), 0.3 + 1e-9, "radius is a bound, not a suggestion")
        }
    }

    func testTheMotionFunctionsAreReachableFromAnExpression() throws {
        XCTAssertEqual(try evaluate("spring(10, 1, 60, 6)"), 1, accuracy: 1e-3)
        XCTAssertEqual(try evaluate("anticipate(1, 1.7)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("stagger(4, 5, 0.4, 0)"), 0.4, accuracy: 1e-12)
        XCTAssertEqual(try evaluate("loop_noise(0, 4, 0.3, 7)"),
                       MotionFunctions.loopNoise(t: 0, period: 4, radius: 0.3, seed: 7),
                       accuracy: 1e-12)
        XCTAssertEqual(try evaluate("spring_v(0, 0.5, 0, 1, 60, 6)"), 0.5, accuracy: 1e-9)
    }

    /// The composition the spec calls out: a physical bounce off the same edge a decay uses.
    func testSinceComposesWithTheMotionVocabulary() throws {
        let snap = snapshot(readings: ["audio/kick": live(1, sinceIncrement: 0.05)])
        let bounced = try evaluate(#"spring_v(since("audio/kick"), 0, 4, 1, 60, 6)"#,
                                   snapshot: snap)
        XCTAssertEqual(bounced, MotionFunctions.springV(t: 0.05, x0: 0, v0: 4, mass: 1,
                                                        stiffness: 60, damping: 6),
                       accuracy: 1e-12)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'MotionFunctions' in scope`.

- [ ] **Step 3: Write the motion library**

Create `App/ARShader/ExpressionFunctions.swift`:

```swift
import Foundation

/// The easing equations the expression vocabulary exposes.
///
/// Only the NAMES came from prior-art research, which listed `spring`, `spring_v`, `stagger`,
/// `anticipate`, `loop_noise` and no semantics. These formulas are ours, which is exactly why
/// they are pinned by tests: nothing external defines them, so a change to the damping convention
/// would silently retune every patch an operator had already dialled in.
enum MotionFunctions {

    /// Unit-step response of a damped harmonic oscillator: 0 at t=0, settling on 1.
    ///
    /// `mass`, `stiffness` and `damping` are the physical parameters an operator can reason about
    /// (heavier is slower; stiffer is faster; more damping overshoots less).
    static func spring(t: Double, mass: Double, stiffness: Double, damping: Double) -> Double {
        1 - freeResponse(t: t, x0: 1, v0: 0, mass: mass, stiffness: stiffness, damping: damping)
    }

    /// Free response from an initial displacement and velocity, decaying to 0. This is the one to
    /// hang off `since()`: `spring_v(since("audio/kick"), 0, 4, 1, 60, 6)` is a kick-driven bounce.
    static func springV(t: Double, x0: Double, v0: Double,
                        mass: Double, stiffness: Double, damping: Double) -> Double {
        freeResponse(t: t, x0: x0, v0: v0, mass: mass, stiffness: stiffness, damping: damping)
    }

    private static func freeResponse(t: Double, x0: Double, v0: Double,
                                     mass: Double, stiffness: Double,
                                     damping: Double) -> Double {
        // Degenerate parameters are clamped rather than allowed to divide by zero: an operator
        // typing 0 into a mass field should get a stiff spring, not a NaN in a uniform.
        let m = max(mass, 1e-6)
        let k = max(stiffness, 1e-6)
        let c = max(damping, 0)
        guard t > 0 else { return x0 }
        let omega0 = (k / m).squareRoot()
        let zeta = c / (2 * (k * m).squareRoot())
        if zeta < 1 {                                   // underdamped — overshoots and rings
            let omegaD = omega0 * (1 - zeta * zeta).squareRoot()
            let envelope = exp(-zeta * omega0 * t)
            return envelope * (x0 * cos(omegaD * t)
                               + ((v0 + zeta * omega0 * x0) / omegaD) * sin(omegaD * t))
        } else if abs(zeta - 1) < 1e-9 {                // critically damped
            return exp(-omega0 * t) * (x0 + (v0 + omega0 * x0) * t)
        } else {                                        // overdamped
            let root = omega0 * (zeta * zeta - 1).squareRoot()
            let r1 = -zeta * omega0 + root
            let r2 = -zeta * omega0 - root
            let a = (v0 - r2 * x0) / (r1 - r2)
            let b = x0 - a
            return a * exp(r1 * t) + b * exp(r2 * t)
        }
    }

    /// A per-element delay in seconds, for driving N things out of step from one source.
    ///
    /// `style`: 0 = in order, 1 = centre outwards, 2 = reversed. Anything else falls back to 0
    /// rather than erroring — a typo in a style number must not take the patch down mid-set.
    static func stagger(index: Double, count: Double, span: Double, style: Double) -> Double {
        let n = max(1, floor(count))
        guard n > 1 else { return 0 }
        let i = min(max(0, floor(index)), n - 1)
        let last = n - 1
        switch Int(floor(style)) {
        case 1:
            // Centre-out: the middle element goes first, the edges last.
            let centre = last / 2
            return span * (abs(i - centre) / max(centre, 1e-9))
        case 2:
            return span * ((last - i) / last)
        default:
            return span * (i / last)
        }
    }

    /// Back-ease: winds up below zero before reaching 1. `bias` is how far it winds up.
    static func anticipate(t: Double, bias: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * ((bias + 1) * x - bias)
    }

    /// Value noise sampled around a circle, so `t` and `t + period` are the same point — it loops
    /// with no seam. Bounded by `radius`, deterministic in `seed`.
    static func loopNoise(t: Double, period: Double, radius: Double, seed: Double) -> Double {
        let p = max(period, 1e-6)
        let lattice = 16.0                      // samples around the circle
        var phase = (t / p).truncatingRemainder(dividingBy: 1.0)
        if phase < 0 { phase += 1 }
        let scaled = phase * lattice
        let cell = floor(scaled)
        let frac = scaled - cell
        let smooth = frac * frac * (3 - 2 * frac)
        let a = hash(Int(cell) % Int(lattice), seed: seed)
        let b = hash(Int(cell + 1) % Int(lattice), seed: seed)
        return radius * ((a + (b - a) * smooth) * 2 - 1)
    }

    /// Deterministic 0..1 hash. Integer mixing rather than `sin(x) * 43758` — that idiom is
    /// platform-dependent at the last bits, and this must be identical between a test and a show.
    private static func hash(_ index: Int, seed: Double) -> Double {
        var x = UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(bitPattern: Int64(seed.rounded())) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        return Double(x % 1_000_000) / 1_000_000
    }
}
```

- [ ] **Step 4: Write the evaluator**

Create `App/ARShader/ExpressionEvaluator.swift`:

```swift
import Foundation

/// Everything an expression may read this frame.
struct ExprContext: Sendable {
    let snapshot: ModSnapshot
    /// What `self` reads — LAST frame's value for this destination (spec §5.3).
    let selfValue: Double
}

/// Walks a compiled `ExprNode`. Returns a Double that MAY be non-finite: containment is a single
/// choke point at the engine boundary (`ModulationEngine`, spec §7), because a guard in two places
/// is a guard that drifts.
enum ExpressionEvaluator {
    static func evaluate(_ node: ExprNode, in context: ExprContext) -> Double {
        switch node {
        case .number(let value):
            return value
        case .string:
            return 0                 // only reachable as a ref/since/valid argument, handled below
        case .identifier(let name):
            switch name {
            case "time":  return context.snapshot.now
            case "dt":    return context.snapshot.dt
            case "frame": return Double(context.snapshot.frame)
            case "self":  return context.selfValue
            default:      return 0   // the parser rejects any other name
            }
        case .negate(let inner):
            return -evaluate(inner, in: context)
        case .binary(let op, let left, let right):
            let l = evaluate(left, in: context)
            let r = evaluate(right, in: context)
            switch op {
            case .add:      return l + r
            case .subtract: return l - r
            case .multiply: return l * r
            case .divide:   return l / r
            }
        case .call(let name, let arguments):
            return call(name, arguments, in: context)
        }
    }

    private static func call(_ name: String, _ arguments: [ExprNode],
                             in context: ExprContext) -> Double {
        // ref / since / valid take the address literally — the parser guarantees a `.string`.
        if ExprSignature.takesSourceAddress(name) {
            guard case .string(let address)? = arguments.first else { return 0 }
            let reading = context.snapshot.reading(address)
            switch name {
            case "ref":   return reading?.value ?? 0
            case "since": return reading?.secondsSinceIncrement ?? 0
            case "valid": return (reading?.isValid ?? false) ? 1 : 0
            default:      return 0
            }
        }
        let a = arguments.map { evaluate($0, in: context) }
        switch name {
        case "sin":   return sin(a[0])
        case "cos":   return cos(a[0])
        case "abs":   return abs(a[0])
        case "sqrt":  return a[0].squareRoot()      // negative -> NaN, contained by the engine
        case "floor": return floor(a[0])
        case "ceil":  return ceil(a[0])
        case "exp":   return exp(a[0])
        case "log":   return log(a[0])
        case "min":   return Swift.min(a[0], a[1])
        case "max":   return Swift.max(a[0], a[1])
        case "pow":   return pow(a[0], a[1])
        case "clamp": return Swift.min(Swift.max(a[0], a[1]), a[2])
        case "spring":
            return MotionFunctions.spring(t: a[0], mass: a[1], stiffness: a[2], damping: a[3])
        case "spring_v":
            return MotionFunctions.springV(t: a[0], x0: a[1], v0: a[2], mass: a[3],
                                           stiffness: a[4], damping: a[5])
        case "stagger":
            return MotionFunctions.stagger(index: a[0], count: a[1], span: a[2], style: a[3])
        case "anticipate":
            return MotionFunctions.anticipate(t: a[0], bias: a[1])
        case "loop_noise":
            return MotionFunctions.loopNoise(t: a[0], period: a[1], radius: a[2], seed: a[3])
        default:
            return 0                                 // unreachable: the parser rejects the name
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ExpressionEvaluatorTests 2>&1 | tail -25
```

Expected: PASS, 15 tests.

- [ ] **Step 6: Prove the `since()` decay-shape gate can fail**

Temporarily change `0.002` to `0.02` in `testOneCounterDrivesAStrobeAndASwellFromTheSameEdge`.
Re-run Step 5.

Expected: FAIL — `strobe` is now ~0.82, not below 0.14. Revert, re-run to confirm PASS, record it
in the Task 13 evidence table.

- [ ] **Step 7: Commit**

```bash
git add App/ARShader/ExpressionFunctions.swift App/ARShader/ExpressionEvaluator.swift \
        App/ARShaderTests/ExpressionEvaluatorTests.swift
git commit -m "feat(mod): the math and motion vocabulary, and the evaluator over it"
```

---

## Task 7: The engine — modes, clamping, containment, skipping

**Files:**
- Create: `App/ARShader/ModulationEngine.swift`
- Test: `App/ARShaderTests/ModulationEngineTests.swift`

**Interfaces:**
- Consumes: `ModDestination` (Task 2), `ModSnapshot` (Task 3), `ExprNode`, `ExprParser`,
  `ExpressionError` (Task 5), `ExprContext`, `ExpressionEvaluator` (Task 6).
- Produces:
  - `enum ModTargetMode: String, Codable, Sendable { case absolute, offset }`
  - `struct ModBinding: Equatable, Codable, Sendable` — `destination`, `text`, `mode`, `isEnabled`
  - `struct CompiledBinding: Sendable` — `binding`, `node: ExprNode?`, `error: String?`,
    `init(_ binding: ModBinding)`
  - `struct ModBase: Sendable, Equatable` — `value: Double`, `range: ClosedRange<Double>`
  - `struct ModulationOutcome: Sendable` — `values: [ModDestination: Double]`,
    `skipped: Set<ModDestination>`, `nonFinite: Set<ModDestination>`, `failed: Set<ModDestination>`
  - `enum ModulationEngine { static func evaluate(_:snapshot:bases:previous:) -> ModulationOutcome }`
  - `ModTargetMode.default(for: ModDestination) -> ModTargetMode`
  Tasks 8–12 use exactly these names.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModulationEngineTests.swift`:

```swift
import XCTest

/// Spec §2.1 (modes), §4.2 (skipped), §5.1 (one snapshot), §5.3 (cycles), §6.2 (one expression),
/// §7 (containment and clamping).
final class ModulationEngineTests: XCTestCase {

    private let opacity = ModDestination.deckOpacity(.one)
    private let crossfader = ModDestination.crossfader

    private func snapshot(now: Double = 5, dt: Double = 1.0 / 60, frame: Int = 300,
                          kick sinceIncrement: Double? = nil) -> ModSnapshot {
        var readings: [String: ModReading] = [:]
        if let sinceIncrement {
            readings["audio/kick"] = ModReading(value: 1, isValid: true, age: 0,
                                                secondsSinceIncrement: sinceIncrement)
        }
        return ModSnapshot(now: now, dt: dt, frame: frame, readings: readings)
    }

    private func compiled(_ text: String, _ destination: ModDestination,
                          mode: ModTargetMode = .absolute) -> CompiledBinding {
        CompiledBinding(ModBinding(destination: destination, text: text, mode: mode,
                                   isEnabled: true))
    }

    private func unitBase(_ value: Double) -> ModBase {
        ModBase(value: value, range: 0...1)
    }

    /// §2.1 — `absolute` OWNS the destination.
    func testAbsoluteModeReplacesTheBase() {
        let outcome = ModulationEngine.evaluate(
            [compiled("0.25", opacity)], snapshot: snapshot(),
            bases: [opacity: unitBase(0.9)], previous: [:])

        XCTAssertEqual(outcome.values[opacity], 0.25)
    }

    /// §2.1 — `offset` keeps the operator's hand live. A hand on the fader and a kick on the
    /// envelope COMPOSE rather than fight.
    ///
    /// Mutation that must fail this test: let `offset` write the base — return the expression
    /// value alone, ignoring `bases[destination]`.
    func testOffsetModeAddsToTheBaseAndLeavesTheBaseAlone() {
        var bases = [opacity: unitBase(0.6)]
        let bindings = [compiled("0.25", opacity, mode: .offset)]

        let outcome = ModulationEngine.evaluate(bindings, snapshot: snapshot(), bases: bases,
                                                previous: [:])
        XCTAssertEqual(outcome.values[opacity] ?? 0, 0.85, accuracy: 1e-12)

        // The operator moves the fader; the same expression now rides the NEW base.
        bases[opacity] = unitBase(0.2)
        let after = ModulationEngine.evaluate(bindings, snapshot: snapshot(), bases: bases,
                                              previous: [:])
        XCTAssertEqual(after.values[opacity] ?? 0, 0.45, accuracy: 1e-12,
                       "The base stays live — the engine never writes back into it")
    }

    /// §7 — out of range is clamped at the destination in BOTH modes, using its declared range.
    func testBothModesClampToTheDestinationRange() {
        let over = ModulationEngine.evaluate([compiled("5", opacity)], snapshot: snapshot(),
                                             bases: [opacity: unitBase(0.5)], previous: [:])
        XCTAssertEqual(over.values[opacity], 1)

        let under = ModulationEngine.evaluate([compiled("0 - 5", opacity, mode: .offset)],
                                              snapshot: snapshot(),
                                              bases: [opacity: unitBase(0.5)], previous: [:])
        XCTAssertEqual(under.values[opacity], 0)
    }

    /// §7 — NaN and infinity NEVER reach a Metal uniform. The destination holds its last finite
    /// value and the binding is flagged.
    ///
    /// Mutation that must fail this test: remove the `isFinite` guard and write the raw value.
    func testNonFiniteResultsAreContainedAndFlagged() {
        let previous = [opacity: 0.42]

        let outcome = ModulationEngine.evaluate([compiled("0 / 0", opacity)],
                                                snapshot: snapshot(),
                                                bases: [opacity: unitBase(0.9)],
                                                previous: previous)

        XCTAssertEqual(outcome.values[opacity], 0.42,
                       "The last finite value holds — a NaN in a uniform is a black frame with "
                       + "no error anywhere")
        XCTAssertTrue(outcome.nonFinite.contains(opacity))
        XCTAssertTrue(outcome.values.values.allSatisfy(\.isFinite))
    }

    func testWithNoPreviousValueAContainedResultFallsBackToTheBase() {
        let outcome = ModulationEngine.evaluate([compiled("1 / 0", opacity)],
                                                snapshot: snapshot(),
                                                bases: [opacity: unitBase(0.3)], previous: [:])
        XCTAssertEqual(outcome.values[opacity], 0.3)
        XCTAssertTrue(outcome.nonFinite.contains(opacity))
    }

    /// §4.2 — a binding whose destination is not currently resolvable is RETAINED and reported
    /// skipped, never deleted. Swapping the original shader back restores it.
    ///
    /// Mutation that must fail this test: drop unresolvable bindings instead of reporting them.
    func testAnUnresolvableDestinationIsSkippedRatherThanDropped() {
        let vanished = ModDestination.deckInput(.one, "gone")

        let outcome = ModulationEngine.evaluate([compiled("0.5", vanished)],
                                                snapshot: snapshot(), bases: [:], previous: [:])

        XCTAssertTrue(outcome.skipped.contains(vanished))
        XCTAssertNil(outcome.values[vanished], "Nothing is written to a destination that is gone")
    }

    /// §7 — a malformed expression stays saved and INACTIVE with its error visible.
    func testACompileFailureIsInactiveAndReportedRatherThanLost() {
        let broken = CompiledBinding(ModBinding(destination: opacity, text: "exp(-since(",
                                                mode: .absolute, isEnabled: true))

        XCTAssertNotNil(broken.error)
        XCTAssertEqual(broken.binding.text, "exp(-since(", "The text the operator typed is kept")

        let outcome = ModulationEngine.evaluate([broken], snapshot: snapshot(),
                                                bases: [opacity: unitBase(0.7)], previous: [:])
        XCTAssertTrue(outcome.failed.contains(opacity))
        XCTAssertNil(outcome.values[opacity], "An inactive binding writes nothing")
    }

    func testADisabledBindingWritesNothingAndIsNotAFailure() {
        let disabled = CompiledBinding(ModBinding(destination: opacity, text: "0.25",
                                                  mode: .absolute, isEnabled: false))

        let outcome = ModulationEngine.evaluate([disabled], snapshot: snapshot(),
                                                bases: [opacity: unitBase(0.7)], previous: [:])

        XCTAssertNil(outcome.values[opacity])
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    /// §5.3 — `self` reads LAST frame's value. One frame of latency is imperceptible; the
    /// alternative is a cycle detector that rejects a patch mid-set.
    ///
    /// Mutation that must fail this test: feed the value being computed this frame into `self`.
    func testSelfReadsThePreviousFrameSoARampIsLinearRatherThanCompounding() {
        let binding = [compiled("self + 0.1", opacity)]
        let bases = [opacity: unitBase(0)]

        var previous: [ModDestination: Double] = [:]
        var trace: [Double] = []
        for frame in 0..<4 {
            let outcome = ModulationEngine.evaluate(binding, snapshot: snapshot(frame: frame),
                                                    bases: bases, previous: previous)
            trace.append(outcome.values[opacity] ?? -1)
            previous = outcome.values
        }

        XCTAssertEqual(trace, [0.1, 0.2, 0.30000000000000004, 0.4].map { $0 },
                       "Exactly one step per FRAME — never several within one")
    }

    /// §5.1 — every destination bound to one source reads the SAME generation of it.
    ///
    /// Mutation that must fail this test: re-read the registry per binding instead of evaluating
    /// against one frozen snapshot (see `ModSourceTests` for the registry half of this gate).
    func testEveryBindingSeesTheSameGenerationOfASource() {
        let snap = snapshot(kick: 0.5)
        let a = ModDestination.deckOpacity(.one)
        let b = ModDestination.deckOpacity(.two)

        let outcome = ModulationEngine.evaluate(
            [compiled(#"since("audio/kick")"#, a), compiled(#"since("audio/kick")"#, b)],
            snapshot: snap,
            bases: [a: ModBase(value: 0, range: 0...10), b: ModBase(value: 0, range: 0...10)],
            previous: [:])

        XCTAssertEqual(outcome.values[a], outcome.values[b])
        XCTAssertEqual(outcome.values[a] ?? -1, 0.5, accuracy: 1e-12)
    }

    /// §2.1 — performance controls default to `offset`, everything else to `absolute`.
    func testTheDefaultModePerDestinationIsTheOneTheSpecNames() {
        XCTAssertEqual(ModTargetMode.default(for: .crossfader), .offset)
        XCTAssertEqual(ModTargetMode.default(for: .deckOpacity(.one)), .offset)
        XCTAssertEqual(ModTargetMode.default(for: .deckFX(.one, UUID(), .mix)), .offset)
        XCTAssertEqual(ModTargetMode.default(for: .masterFX(UUID(), .mix)), .offset)
        XCTAssertEqual(ModTargetMode.default(for: .deckInput(.one, "speed")), .absolute)
        XCTAssertEqual(ModTargetMode.default(for: .deckBlend(.one)), .absolute)
        XCTAssertEqual(ModTargetMode.default(for: .deckFX(.one, UUID(), .input("warp"))), .absolute)
    }

    /// §6.2 — one expression per destination, so "what drives this?" always has ONE answer.
    func testABindingIsCodableSoItSurvivesARelaunch() throws {
        let binding = ModBinding(destination: .deckFX(.two, UUID(), .input("threshold")),
                                 text: #"clamp(ref("manual/lfo"), 0, 1)"#,
                                 mode: .offset, isEnabled: true)

        let data = try JSONEncoder().encode(binding)
        XCTAssertEqual(try JSONDecoder().decode(ModBinding.self, from: data), binding)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'ModulationEngine' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/ARShader/ModulationEngine.swift`:

```swift
import Foundation

/// Spec §2.1. `absolute` is the prior-art system's behaviour — the expression IS the value. `offset` keeps the
/// operator's base live, so a hand on the fader and a kick on the envelope compose rather than
/// fight.
enum ModTargetMode: String, Codable, Sendable {
    case absolute, offset

    /// Performance controls default to `offset`; everything else to `absolute`.
    static func `default`(for destination: ModDestination) -> ModTargetMode {
        switch destination {
        case .crossfader, .deckOpacity:      return .offset
        case .deckFX(_, _, .mix), .masterFX(_, .mix): return .offset
        case .deckInput, .deckBlend, .deckFX, .masterFX: return .absolute
        }
    }
}

/// What the operator wrote. The persisted unit — text, mode, enabled flag, and the address it
/// drives. Never the evaluated output (§8).
struct ModBinding: Equatable, Codable, Sendable {
    let destination: ModDestination
    var text: String
    var mode: ModTargetMode
    var isEnabled: Bool
}

/// A binding with its expression compiled, or with the compile error that stopped it.
///
/// §7 — compile failures are STORED, not dropped: losing a half-written driver to a fat-fingered
/// paren is unacceptable in a live tool, so this type always carries the operator's text whether
/// or not it parsed.
struct CompiledBinding: Sendable {
    let binding: ModBinding
    let node: ExprNode?
    let error: String?

    init(_ binding: ModBinding) {
        self.binding = binding
        do {
            self.node = try ExprParser.compile(binding.text)
            self.error = nil
        } catch let failure as ExpressionError {
            self.node = nil
            self.error = failure.message
        } catch {
            self.node = nil
            self.error = "\(error)"
        }
    }
}

/// A destination's live base value and declared bounds, as of this frame. Published by whoever
/// owns the destination (the mixer, a chain, a shader's header) — the engine never reads
/// main-actor state itself.
struct ModBase: Sendable, Equatable {
    var value: Double
    var range: ClosedRange<Double>
}

/// What one frame of evaluation produced, and everything the ledger needs to explain itself.
struct ModulationOutcome: Sendable {
    var values: [ModDestination: Double] = [:]
    /// Bindings whose destination is not currently resolvable — retained, reported, never
    /// deleted (§4.2).
    var skipped: Set<ModDestination> = []
    /// Bindings whose expression produced NaN or infinity this frame. The destination held its
    /// last finite value (§7).
    var nonFinite: Set<ModDestination> = []
    /// Bindings that did not compile. Saved and inactive with the error visible (§7).
    var failed: Set<ModDestination> = []
}

/// The pure heart of the slice: no audio, GPU, view or Metal dependency, mirroring
/// `SurfaceLayout`'s shape from phase 3a. Every invariant in spec §9.1 is testable here with
/// nothing running.
enum ModulationEngine {
    static func evaluate(_ bindings: [CompiledBinding],
                         snapshot: ModSnapshot,
                         bases: [ModDestination: ModBase],
                         previous: [ModDestination: Double]) -> ModulationOutcome {
        var outcome = ModulationOutcome()
        outcome.values.reserveCapacity(bindings.count)

        for compiled in bindings {
            let destination = compiled.binding.destination
            guard compiled.binding.isEnabled else { continue }
            guard let node = compiled.node else {
                outcome.failed.insert(destination)
                continue
            }
            guard let base = bases[destination] else {
                outcome.skipped.insert(destination)
                continue
            }

            // §5.3 — `self` is LAST frame's value, so a cycle costs one frame of latency rather
            // than a cycle detector that rejects a patch mid-set.
            let selfValue = previous[destination] ?? base.value
            let raw = ExpressionEvaluator.evaluate(
                node, in: ExprContext(snapshot: snapshot, selfValue: selfValue))

            // §7 — the one and only containment point. NaN and infinity never reach a uniform.
            guard raw.isFinite else {
                outcome.nonFinite.insert(destination)
                outcome.values[destination] = previous[destination] ?? base.value
                continue
            }

            let combined = compiled.binding.mode == .offset ? base.value + raw : raw
            outcome.values[destination] = min(max(combined, base.range.lowerBound),
                                              base.range.upperBound)
        }
        return outcome
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModulationEngineTests 2>&1 | tail -25
```

Expected: PASS, 12 tests. If `testSelfReadsThePreviousFrame…` fails only on floating-point
representation, compare element-wise with `accuracy: 1e-12` instead of `XCTAssertEqual` on the
array — the CONTRACT is one step per frame, not the exact bit pattern.

- [ ] **Step 5: Prove four gates can fail**

Run each mutation, confirm the named test fails, revert, confirm PASS. Record all four in the
Task 13 evidence table.

| Mutation | Test that must fail |
|---|---|
| In `evaluate`, use `raw` for both modes (drop the `base.value +`) | `testOffsetModeAddsToTheBase…` |
| Delete the `guard raw.isFinite` block | `testNonFiniteResultsAreContainedAndFlagged` |
| Replace `outcome.skipped.insert` with `continue` alone | `testAnUnresolvableDestinationIsSkipped…` |
| Use `outcome.values[destination] ?? base.value` for `selfValue` | `testSelfReadsThePreviousFrame…` |

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/ModulationEngine.swift App/ARShaderTests/ModulationEngineTests.swift
git commit -m "feat(mod): the pure engine — modes, clamping, NaN containment, skipped bindings"
```

---

## Task 8: The runtime — the render thread's half

**Files:**
- Create: `App/ARShader/ModulationRuntime.swift`
- Test: `App/ARShaderTests/ModulationRuntimeTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2, 3, 6 and 7; `LayerParams`, `DeckID`, `BlendMode`,
  `CrossfadeMacro` from the existing code.
- Produces:
  - `final class ModulationRuntime: @unchecked Sendable`
    - `init(sources: ModSourceRegistry = ModSourceRegistry())`
    - `let sources: ModSourceRegistry`
    - main thread: `publishBindings(_ [CompiledBinding])`,
      `publishBase(_ value: Double, range: ClosedRange<Double>, for: ModDestination)`,
      `removeBase(for: ModDestination)`, `removeBases(matching: (ModDestination) -> Bool)`,
      `setSink(_ sink: (@Sendable (Double) -> Void)?, for: ModDestination)`
    - render thread: `tick(now: Double)`, `value(for: ModDestination) -> Double?`,
      `modulatedLayers(_ base: [LayerParams], crossfader: Double) -> [LayerParams]`,
      `fxMix(base: Double, stage: UUID, scope: ModFXScope) -> Double`
    - either: `outcome() -> ModulationOutcome`, `isDriven(_ destination: ModDestination) -> Bool`
  Tasks 10–13 use exactly these names.

**Threading contract (state it in the file's doc comment).** One `NSLock` guards every field, the
same coarse-over-clever arrangement `MetalRenderCore`, `InstrumentRenderer`, `MixerState`,
`FXChain` and `SourceRouter` all use. Sinks are `@Sendable` closures that capture only
`MetalRenderCore` (itself `@unchecked Sendable` behind its own lock) — never a `ShaderUnit`, a
`ParamStore` or anything `@MainActor`.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModulationRuntimeTests.swift`:

```swift
import XCTest

/// Spec §5.1 (one tick per frame), §5.2 (the app clock), §8 (values bypass persistence and the UI
/// path), plus the mixer and FX appliers.
final class ModulationRuntimeTests: XCTestCase {

    private let opacity = ModDestination.deckOpacity(.one)

    private func makeRuntime() -> ModulationRuntime {
        let runtime = ModulationRuntime()
        runtime.sources.register(ModOutputDescriptor(address: "stub/level", kind: .continuous,
                                                     range: 0...1, provenance: "Test",
                                                     staleAfter: .infinity), now: 0)
        return runtime
    }

    private func binding(_ text: String, _ destination: ModDestination,
                         mode: ModTargetMode = .absolute) -> CompiledBinding {
        CompiledBinding(ModBinding(destination: destination, text: text, mode: mode,
                                   isEnabled: true))
    }

    func testATickResolvesBoundDestinationsAndLeavesUnboundOnesAlone() {
        let runtime = makeRuntime()
        runtime.publishBase(0.5, range: 0...1, for: opacity)
        runtime.publishBindings([binding("0.8", opacity)])

        runtime.tick(now: 1.0)

        XCTAssertEqual(runtime.value(for: opacity), 0.8)
        XCTAssertNil(runtime.value(for: .deckOpacity(.two)))
        XCTAssertTrue(runtime.isDriven(opacity))
        XCTAssertFalse(runtime.isDriven(.deckOpacity(.two)))
    }

    /// `dt` is derived from the app clock the renderer already owns, and the FIRST tick has no
    /// previous time to subtract — it must be 0, not a huge number from process start.
    func testTheFirstTickReportsZeroDeltaAndLaterOnesTheRealInterval() {
        let runtime = makeRuntime()
        let probe = ModDestination.deckOpacity(.two)
        runtime.publishBase(0, range: 0...10, for: probe)
        runtime.publishBindings([binding("dt", probe)])

        runtime.tick(now: 100.0)
        XCTAssertEqual(runtime.value(for: probe), 0, "The first frame has no interval")

        runtime.tick(now: 100.02)
        XCTAssertEqual(runtime.value(for: probe) ?? -1, 0.02, accuracy: 1e-9)
    }

    /// A stall must not produce a giant `dt` that jumps every integrator across the room.
    func testAHugeGapIsClampedRatherThanPassedThrough() {
        let runtime = makeRuntime()
        let probe = ModDestination.deckOpacity(.two)
        runtime.publishBase(0, range: 0...10, for: probe)
        runtime.publishBindings([binding("dt", probe)])

        runtime.tick(now: 0)
        runtime.tick(now: 30)

        XCTAssertLessThanOrEqual(runtime.value(for: probe) ?? 99, 0.1,
                                 "A 30 s hitch is a stall, not a 30 s frame")
    }

    /// §8 — a modulated ISF input reaches the scene through a SINK, never through `ParamStore`,
    /// `@Published` or `UserDefaults`.
    func testAModulatedShaderInputIsWrittenThroughItsSink() {
        let runtime = makeRuntime()
        let destination = ModDestination.deckInput(.one, "speed")
        let received = Locked<[Double]>([])
        runtime.setSink({ value in received.mutate { $0.append(value) } }, for: destination)
        runtime.publishBase(0.1, range: 0...2, for: destination)
        runtime.publishBindings([binding("1.5", destination)])

        runtime.tick(now: 1.0)
        runtime.tick(now: 1.02)

        XCTAssertEqual(received.value, [1.5],
                       "Written once — an unchanged value must not be pushed every frame")
    }

    func testAChangedValueIsPushedAndAClearedBindingRestoresTheBase() {
        let runtime = makeRuntime()
        let destination = ModDestination.deckInput(.one, "speed")
        let received = Locked<[Double]>([])
        runtime.setSink({ value in received.mutate { $0.append(value) } }, for: destination)
        runtime.publishBase(0.1, range: 0...2, for: destination)

        runtime.publishBindings([binding(#"ref("stub/level") * 2"#, destination)])
        runtime.sources.publish(0.25, to: "stub/level", now: 1.0)
        runtime.tick(now: 1.0)
        runtime.sources.publish(0.75, to: "stub/level", now: 1.02)
        runtime.tick(now: 1.02)

        runtime.publishBindings([])
        runtime.tick(now: 1.04)

        XCTAssertEqual(received.value, [0.5, 1.5, 0.1],
                       "Clearing a driver restores the operator's base — it does not freeze")
        XCTAssertNil(runtime.value(for: destination))
    }

    /// §2.1 / the mixer applier: opacity and the crossfader are recomputed from modulated inputs
    /// through the SAME `CrossfadeMacro` the mixer uses, so a driven fader and a hand-moved one
    /// composite identically.
    func testModulatedOpacityAndCrossfaderFlowThroughTheCrossfadeMacro() {
        let runtime = makeRuntime()
        runtime.publishBase(1.0, range: 0...1, for: .deckOpacity(.one))
        runtime.publishBase(0.0, range: 0...1, for: .crossfader)
        runtime.publishBindings([binding("0.5", .deckOpacity(.one)),
                                 binding("1.0", .crossfader)])
        runtime.tick(now: 1.0)

        let base = [
            LayerParams(deck: .one, userOpacity: 1.0, crossfadeWeight: 1.0,
                        effectiveOpacity: 1.0, blendMode: .normal),
            LayerParams(deck: .two, userOpacity: 1.0, crossfadeWeight: 0.0,
                        effectiveOpacity: 0.0, blendMode: .normal),
        ]
        let modulated = runtime.modulatedLayers(base, crossfader: 0.0)

        XCTAssertEqual(modulated[0].userOpacity, 0.5)
        XCTAssertEqual(modulated[0].crossfadeWeight,
                       CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2, position: 1.0),
                       "The crossfader override is applied through the macro, not by hand")
        XCTAssertEqual(modulated[0].effectiveOpacity,
                       CrossfadeMacro.effectiveOpacity(
                            userOpacity: 0.5,
                            weight: CrossfadeMacro.weight(forLayerIndex: 0, layerCount: 2,
                                                          position: 1.0)))
    }

    func testAnUnmodulatedLayerSetIsReturnedUntouched() {
        let runtime = makeRuntime()
        let base = [LayerParams(deck: .one, userOpacity: 0.4, crossfadeWeight: 1,
                                effectiveOpacity: 0.4, blendMode: .screen)]

        XCTAssertEqual(runtime.modulatedLayers(base, crossfader: 0.25), base,
                       "No bindings must mean no work and no change")
    }

    func testADrivenBlendModeSelectsByIndexAndClampsToTheKnownModes() {
        let runtime = makeRuntime()
        let last = Double(BlendMode.allCases.count - 1)
        runtime.publishBase(0, range: 0...last, for: .deckBlend(.one))
        runtime.publishBindings([binding("2", .deckBlend(.one))])
        runtime.tick(now: 1.0)

        let base = [LayerParams(deck: .one, userOpacity: 1, crossfadeWeight: 1,
                                effectiveOpacity: 1, blendMode: .normal)]

        XCTAssertEqual(runtime.modulatedLayers(base, crossfader: 0).first?.blendMode,
                       BlendMode.allCases[2])
    }

    func testFXMixIsOverriddenPerStageAndScope() {
        let runtime = makeRuntime()
        let deckStage = UUID()
        let masterStage = UUID()
        runtime.publishBase(0, range: 0...1, for: .deckFX(.one, deckStage, .mix))
        runtime.publishBindings([binding("0.7", .deckFX(.one, deckStage, .mix))])
        runtime.tick(now: 1.0)

        XCTAssertEqual(runtime.fxMix(base: 0, stage: deckStage, scope: .deck(.one)), 0.7,
                       "A dry stage can be brought in by a driver — that is why the publish "
                       + "filter moved to encode time")
        XCTAssertEqual(runtime.fxMix(base: 0.3, stage: deckStage, scope: .deck(.two)), 0.3,
                       "Deck B's chain is a different scope")
        XCTAssertEqual(runtime.fxMix(base: 0.3, stage: masterStage, scope: .master), 0.3,
                       "An unbound stage keeps its own mix")
    }

    /// §4.2 — an FX binding whose stage id is not present is reported skipped, not written and
    /// not deleted.
    func testABindingWithNoBaseIsReportedSkipped() {
        let runtime = makeRuntime()
        let ghost = ModDestination.deckFX(.one, UUID(), .mix)
        runtime.publishBindings([binding("0.7", ghost)])

        runtime.tick(now: 1.0)

        XCTAssertTrue(runtime.outcome().skipped.contains(ghost))
        XCTAssertNil(runtime.value(for: ghost))
    }

    func testRemovingBasesForAVanishedShaderLeavesTheBindingsInPlace() {
        let runtime = makeRuntime()
        let input = ModDestination.deckInput(.one, "speed")
        runtime.publishBase(0.1, range: 0...1, for: input)
        runtime.publishBindings([binding("0.5", input)])
        runtime.tick(now: 1.0)
        XCTAssertEqual(runtime.value(for: input), 0.5)

        runtime.removeBases { destination in
            if case .deckInput(.one, _) = destination { return true }
            return false
        }
        runtime.tick(now: 1.02)

        XCTAssertNil(runtime.value(for: input))
        XCTAssertTrue(runtime.outcome().skipped.contains(input),
                      "Swapping the original shader back must restore it, so the binding stays")
    }
}

/// A tiny lock-guarded box, so a `@Sendable` sink closure can record what it received without
/// tripping Swift 6 concurrency checking in the test bundle.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { storage = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return storage }
    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&storage)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'ModulationRuntime' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/ARShader/ModulationRuntime.swift`:

```swift
import Foundation

/// The render thread's half of the modulation layer.
///
/// `@unchecked Sendable` behind ONE coarse lock — the arrangement `MetalRenderCore`,
/// `InstrumentRenderer`, `MixerState`, `FXChain` and `SourceRouter` all use, and required for the
/// same reason: `tick` runs on the display-link thread while the operator edits bindings on main.
///
/// **Nothing here touches main-actor state.** Bases and sinks are PUSHED in from the owners of
/// each destination; the runtime never reaches back for a `@Published` value. Sinks capture only
/// `MetalRenderCore`, which is itself `@unchecked Sendable` behind its own lock — never a
/// `ShaderUnit`, a `ParamStore`, or anything `@MainActor`. This is spec §8's bypass expressed as a
/// type constraint rather than a rule to remember.
final class ModulationRuntime: @unchecked Sendable {
    /// A frame longer than this is a stall, not a frame. Passing a 30 s `dt` into an integrator
    /// throws every LFO across the room; clamping it merely pauses them for one frame.
    static let maxFrameDelta: Double = 0.1

    let sources: ModSourceRegistry

    private let lock = NSLock()
    // ── lock-guarded ──
    private var compiled: [CompiledBinding] = []
    private var bases: [ModDestination: ModBase] = [:]
    private var sinks: [ModDestination: @Sendable (Double) -> Void] = [:]
    private var resolved: [ModDestination: Double] = [:]
    private var lastOutcome = ModulationOutcome()
    private var lastTickTime: Double?
    private var frameIndex = 0
    /// What each sink was last given, so an unchanged value is not pushed every frame — and so a
    /// cleared binding can restore the base exactly once.
    private var sunkValues: [ModDestination: Double] = [:]

    init(sources: ModSourceRegistry = ModSourceRegistry()) {
        self.sources = sources
    }

    // MARK: main thread

    /// Replace the whole binding set. Whole-set rather than incremental: "what drives this?" has
    /// exactly one answer per destination (§6.2), and a set swap cannot leave a stale one behind.
    func publishBindings(_ bindings: [CompiledBinding]) {
        lock.lock(); defer { lock.unlock() }
        compiled = bindings
    }

    /// The live base value and declared bounds for a destination. Called by whoever owns it: the
    /// mixer on every mutation, a chain on every publish, a `ShaderUnit` on compile and on every
    /// operator-set parameter.
    func publishBase(_ value: Double, range: ClosedRange<Double>, for destination: ModDestination) {
        lock.lock(); defer { lock.unlock() }
        bases[destination] = ModBase(value: value, range: range)
    }

    func removeBase(for destination: ModDestination) {
        lock.lock(); defer { lock.unlock() }
        bases.removeValue(forKey: destination)
    }

    /// Drop every base matching a predicate — a shader unloaded, a stage removed. The BINDINGS
    /// stay: §4.2 retains and reports them so swapping the original shader back restores them.
    func removeBases(matching predicate: (ModDestination) -> Bool) {
        lock.lock(); defer { lock.unlock() }
        for destination in bases.keys where predicate(destination) {
            bases.removeValue(forKey: destination)
        }
    }

    func setSink(_ sink: (@Sendable (Double) -> Void)?, for destination: ModDestination) {
        lock.lock(); defer { lock.unlock() }
        sinks[destination] = sink
    }

    // MARK: render thread

    /// Evaluate every binding once, against ONE frozen generation of the sources (§5.1).
    ///
    /// `now` is the app-owned render clock, not wall clock (§5.2), so pause behaves and a shader
    /// recompile does not restart motion.
    func tick(now: Double) {
        lock.lock()
        let dt = min(max(0, now - (lastTickTime ?? now)), Self.maxFrameDelta)
        lastTickTime = now
        frameIndex += 1
        let bindings = compiled
        let currentBases = bases
        let previous = resolved
        let frame = frameIndex
        lock.unlock()

        let snapshot = sources.snapshot(now: now, dt: dt, frame: frame)
        let outcome = ModulationEngine.evaluate(bindings, snapshot: snapshot,
                                                bases: currentBases, previous: previous)

        lock.lock()
        resolved = outcome.values
        lastOutcome = outcome
        // A destination that stopped being driven gets its base back ONCE, so clearing a driver
        // restores the operator's value rather than freezing on the last modulated one.
        var pushes: [(@Sendable (Double) -> Void, Double, ModDestination)] = []
        for (destination, sink) in sinks {
            let target = outcome.values[destination] ?? currentBases[destination]?.value
            guard let target, sunkValues[destination] != target else { continue }
            sunkValues[destination] = target
            pushes.append((sink, target, destination))
        }
        lock.unlock()

        for (sink, value, _) in pushes { sink(value) }
    }

    func value(for destination: ModDestination) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return resolved[destination]
    }

    func isDriven(_ destination: ModDestination) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved[destination] != nil
    }

    func outcome() -> ModulationOutcome {
        lock.lock(); defer { lock.unlock() }
        return lastOutcome
    }

    /// Apply opacity, crossfader and blend overrides to the mixer's own layer set.
    ///
    /// Recomputed through `CrossfadeMacro`, the same path `MixerState.layers()` uses, so a driven
    /// fader and a hand-moved one composite identically. Returns the input untouched when nothing
    /// is driven — the overwhelmingly common case, and it must cost nothing.
    func modulatedLayers(_ base: [LayerParams], crossfader: Double) -> [LayerParams] {
        lock.lock()
        let current = resolved
        lock.unlock()
        guard !current.isEmpty else { return base }

        let position = current[.crossfader] ?? crossfader
        let blendModes = BlendMode.allCases
        return base.enumerated().map { index, layer in
            let opacity = current[.deckOpacity(layer.deck)] ?? layer.userOpacity
            let weight = CrossfadeMacro.weight(forLayerIndex: index, layerCount: base.count,
                                               position: position)
            var mode = layer.blendMode
            if let driven = current[.deckBlend(layer.deck)] {
                let slot = Int(driven.rounded())
                mode = blendModes[min(max(slot, 0), blendModes.count - 1)]
            }
            return LayerParams(
                deck: layer.deck,
                userOpacity: opacity,
                crossfadeWeight: weight,
                effectiveOpacity: CrossfadeMacro.effectiveOpacity(userOpacity: opacity,
                                                                  weight: weight),
                blendMode: mode)
        }
    }

    /// The mix an FX stage should encode at this frame. `base` is the stage's own value, returned
    /// unchanged when nothing drives it.
    func fxMix(base: Double, stage: UUID, scope: ModFXScope) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard !resolved.isEmpty else { return base }
        switch scope {
        case .deck(let deck): return resolved[.deckFX(deck, stage, .mix)] ?? base
        case .master:         return resolved[.masterFX(stage, .mix)] ?? base
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModulationRuntimeTests 2>&1 | tail -25
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/ModulationRuntime.swift App/ARShaderTests/ModulationRuntimeTests.swift
git commit -m "feat(mod): the runtime — one tick per frame, sinks, and the mixer/FX appliers"
```

---

## Task 9: The ledger and its persistence

**Files:**
- Create: `App/ARShader/ModulationModel.swift`
- Create: `App/ARShader/ModulationStore.swift`
- Test: `App/ARShaderTests/ModulationModelTests.swift`

**Interfaces:**
- Consumes: `ModBinding`, `CompiledBinding`, `ModTargetMode` (Task 7), `ModulationRuntime`
  (Task 8), `ModDestination` (Task 2).
- Produces:
  - `struct ModulationSnapshot: Codable, Equatable` — `version: Int`, `bindings: [ModBinding]`
  - `struct ModulationStore` — `static let key`, `init(defaults:)`, `load() -> ModulationSnapshot`,
    `save(_:)`
  - `@MainActor final class ModulationModel: ObservableObject`
    - `init(runtime: ModulationRuntime, store: ModulationStore = ModulationStore())`
    - `bindings: [ModDestination: ModBinding]` (published, private setter)
    - `errors: [ModDestination: String]` (published, private setter)
    - `set(_ text: String, for: ModDestination, mode: ModTargetMode? = nil)`
    - `setMode(_:for:)`, `setEnabled(_:for:)`, `clear(_:)`, `clearAll()`
    - `binding(for:) -> ModBinding?`, `sorted: [ModBinding]`
    - `rewriteSourceReferences(from oldAddress: String, to newAddress: String)`
  Tasks 11–12 use exactly these names.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModulationModelTests.swift`:

```swift
import XCTest

/// Spec §2 (list / get / clear, rename-safe rewriting), §6.2 (one expression per destination),
/// §7 (compile failures stay saved), §8 (what persists and what never does).
@MainActor
final class ModulationModelTests: XCTestCase {

    private let opacity = ModDestination.deckOpacity(.one)

    private func makeDefaults() throws -> UserDefaults {
        let suite = "arshader-modulation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeModel(_ defaults: UserDefaults) -> (ModulationModel, ModulationRuntime) {
        let runtime = ModulationRuntime()
        return (ModulationModel(runtime: runtime, store: ModulationStore(defaults: defaults)),
                runtime)
    }

    func testSettingABindingCompilesItAndPublishesItToTheRuntime() throws {
        let (model, runtime) = makeModel(try makeDefaults())
        runtime.publishBase(0.2, range: 0...1, for: opacity)

        model.set("0.75", for: opacity)
        runtime.tick(now: 1.0)

        XCTAssertEqual(model.binding(for: opacity)?.text, "0.75")
        XCTAssertNil(model.errors[opacity])
        XCTAssertEqual(runtime.value(for: opacity), 0.75)
    }

    /// §2.1 — the mode defaults per destination and an explicit one overrides it.
    func testTheModeDefaultsPerDestinationAndCanBeSetExplicitly() throws {
        let (model, _) = makeModel(try makeDefaults())

        model.set("0.1", for: .deckOpacity(.one))
        XCTAssertEqual(model.binding(for: .deckOpacity(.one))?.mode, .offset)

        model.set("0.1", for: .deckInput(.one, "speed"))
        XCTAssertEqual(model.binding(for: .deckInput(.one, "speed"))?.mode, .absolute)

        model.setMode(.absolute, for: .deckOpacity(.one))
        XCTAssertEqual(model.binding(for: .deckOpacity(.one))?.mode, .absolute)
    }

    /// §6.2 — one expression per destination. Setting a second REPLACES rather than accumulating.
    func testASecondExpressionForADestinationReplacesTheFirst() throws {
        let (model, _) = makeModel(try makeDefaults())

        model.set("0.1", for: opacity)
        model.set("0.9", for: opacity)

        XCTAssertEqual(model.bindings.count, 1)
        XCTAssertEqual(model.binding(for: opacity)?.text, "0.9")
    }

    /// §7 — a malformed expression REMAINS SAVED and inactive with its error visible.
    func testABrokenExpressionIsKeptWithItsErrorAndDrivesNothing() throws {
        let (model, runtime) = makeModel(try makeDefaults())
        runtime.publishBase(0.2, range: 0...1, for: opacity)

        model.set("exp(-since(", for: opacity)
        runtime.tick(now: 1.0)

        XCTAssertEqual(model.binding(for: opacity)?.text, "exp(-since(",
                       "Losing a half-written driver to a fat-fingered paren is unacceptable")
        XCTAssertNotNil(model.errors[opacity])
        XCTAssertNil(runtime.value(for: opacity))
    }

    func testFixingABrokenExpressionClearsItsError() throws {
        let (model, _) = makeModel(try makeDefaults())
        model.set("exp(-since(", for: opacity)
        XCTAssertNotNil(model.errors[opacity])

        model.set("0.5", for: opacity)

        XCTAssertNil(model.errors[opacity])
    }

    func testClearingABindingStopsDrivingAndForgetsTheError() throws {
        let (model, runtime) = makeModel(try makeDefaults())
        runtime.publishBase(0.2, range: 0...1, for: opacity)
        model.set("0.75", for: opacity)
        runtime.tick(now: 1.0)

        model.clear(opacity)
        runtime.tick(now: 1.02)

        XCTAssertNil(model.binding(for: opacity))
        XCTAssertNil(model.errors[opacity])
        XCTAssertNil(runtime.value(for: opacity))
    }

    func testADisabledBindingIsKeptButDrivesNothing() throws {
        let (model, runtime) = makeModel(try makeDefaults())
        runtime.publishBase(0.2, range: 0...1, for: opacity)
        model.set("0.75", for: opacity)

        model.setEnabled(false, for: opacity)
        runtime.tick(now: 1.0)

        XCTAssertEqual(model.binding(for: opacity)?.isEnabled, false)
        XCTAssertNil(runtime.value(for: opacity))
    }

    /// §8 — expression text, mode and the enabled flag persist; evaluated output never does.
    func testBindingsSurviveARelaunch() throws {
        let defaults = try makeDefaults()
        let (model, _) = makeModel(defaults)
        model.set(#"exp(-since("manual/trigger") / 0.25)"#, for: opacity)
        model.set("0.5", for: .deckInput(.two, "warp"))
        model.setEnabled(false, for: .deckInput(.two, "warp"))

        // A SEPARATE model and runtime — this is the relaunch, not a cache read.
        let (reloaded, runtime) = makeModel(defaults)
        runtime.publishBase(0.2, range: 0...1, for: opacity)
        runtime.tick(now: 1.0)

        XCTAssertEqual(reloaded.binding(for: opacity)?.text,
                       #"exp(-since("manual/trigger") / 0.25)"#)
        XCTAssertEqual(reloaded.binding(for: .deckInput(.two, "warp"))?.isEnabled, false)
        XCTAssertNotNil(runtime.value(for: opacity),
                        "A restored binding is live again without the operator retyping it")
    }

    func testCorruptStoredDataDoesNotStopTheInstrumentLaunching() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: ModulationStore.key)

        let (model, _) = makeModel(defaults)

        XCTAssertTrue(model.bindings.isEmpty)
    }

    /// The `ParamStore` doctrine, applied here: one unreadable entry is skipped, it does not take
    /// the whole set down.
    func testOneUnreadableBindingIsSkippedAndTheRestSurvive() throws {
        let defaults = try makeDefaults()
        let json = """
        {"version":1,"bindings":[
          {"destination":"deck.a.opacity","text":"0.5","mode":"offset","isEnabled":true},
          {"destination":"deck.z.nonsense","text":"0.5","mode":"offset","isEnabled":true}
        ]}
        """
        defaults.set(Data(json.utf8), forKey: ModulationStore.key)

        let (model, _) = makeModel(defaults)

        XCTAssertEqual(model.bindings.count, 1)
        XCTAssertEqual(model.binding(for: .deckOpacity(.one))?.text, "0.5")
    }

    /// §2 — renaming a source REWRITES stored expressions so references survive. No caller exists
    /// in this slice (nothing can rename `manual/*`); the audio slice is what will use it, and it
    /// is built and pinned now rather than retrofitted onto persisted patches later.
    func testRenamingASourceRewritesEveryReferenceToIt() throws {
        let (model, _) = makeModel(try makeDefaults())
        model.set(#"exp(-since("audio/kick") / 0.25) + ref("audio/kick")"#, for: opacity)
        model.set(#"ref("audio/snare")"#, for: .deckOpacity(.two))

        model.rewriteSourceReferences(from: "audio/kick", to: "audio/bassdrum")

        XCTAssertEqual(model.binding(for: opacity)?.text,
                       #"exp(-since("audio/bassdrum") / 0.25) + ref("audio/bassdrum")"#)
        XCTAssertEqual(model.binding(for: .deckOpacity(.two))?.text, #"ref("audio/snare")"#,
                       "Only the renamed address is touched")
    }

    func testTheLedgerIsListedInAStableOrder() throws {
        let (model, _) = makeModel(try makeDefaults())
        model.set("0.1", for: .deckOpacity(.two))
        model.set("0.2", for: .crossfader)
        model.set("0.3", for: .deckOpacity(.one))

        XCTAssertEqual(model.sorted.map(\.destination.address),
                       ["deck.a.opacity", "deck.b.opacity", "mixer.crossfader"],
                       "A ledger that reorders itself between frames is unreadable mid-set")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'ModulationModel' in scope`.

- [ ] **Step 3: Write the store**

Create `App/ARShader/ModulationStore.swift`:

```swift
import Foundation

/// The persisted binding set. Versioned flat JSON, per the null_signal preset-codec doctrine that
/// `ParamSnapshot` already follows: one corrupt entry is skipped on decode, never fatal.
struct ModulationSnapshot: Equatable {
    var version: Int = 1
    var bindings: [ModBinding] = []
}

extension ModulationSnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case version, bindings }

    /// Swallows one unreadable binding instead of failing the whole decode — an address from a
    /// future build, or a hand-edited file, must not cost the operator every other driver.
    private struct FailableBinding: Codable {
        let value: ModBinding?
        init(value: ModBinding?) { self.value = value }
        init(from decoder: Decoder) throws { value = try? ModBinding(from: decoder) }
        func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let raw = try c.decodeIfPresent([FailableBinding].self, forKey: .bindings) ?? []
        bindings = raw.compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(bindings.map { FailableBinding(value: $0) }, forKey: .bindings)
    }
}

/// Reads and writes the binding set as one JSON blob, exactly as `SurfaceLayoutStore` does for the
/// arrangement: one key, not N, because the set is restored together or the restore is wrong.
///
/// **Binding scope is instrument-global, and this single flat key is the decision** — spec §10.3
/// asks whether bindings belong to the instrument or to a slot-bank preset, and one unscoped
/// `UserDefaults` key answers it by shape: every binding is live regardless of which preset is
/// loaded. That is the right default for this slice (an operator dialling in a kick→scale routing
/// expects it to survive a shader change), but it is a decision, not a deferral. Re-scoping to
/// per-preset later means adding a preset id to the key or to `ModulationSnapshot` — a migration,
/// so revisit it when phase 3b/3c's `Preset` model lands rather than after operators have patches
/// saved. (PM spec review, 2026-08-01, finding 1.)
struct ModulationStore {
    static let key = "ARShader.modulationBindings"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Any failure — absent, truncated, from a future schema — yields an empty set. A corrupt
    /// patch must never be able to stop the instrument launching.
    func load() -> ModulationSnapshot {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(ModulationSnapshot.self, from: data)
        else { return ModulationSnapshot() }
        return decoded
    }

    func save(_ snapshot: ModulationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Write the model**

Create `App/ARShader/ModulationModel.swift`:

```swift
import Foundation
import Combine

/// The operator's ledger: what drives what, in text.
///
/// `@MainActor` and `ObservableObject` because the panel binds to it. It owns NO evaluated value —
/// every edit recompiles the set and publishes it to the `ModulationRuntime`, which is the only
/// thing the render thread ever reads. That split is spec §8's bypass: an evaluated value has no
/// path back into this object, so it can never reach `UserDefaults` or a `@Published` update.
@MainActor
final class ModulationModel: ObservableObject {
    @Published private(set) var bindings: [ModDestination: ModBinding] = [:]
    /// Compile errors, by destination. Present means saved-and-inactive (§7).
    @Published private(set) var errors: [ModDestination: String] = [:]

    private let runtime: ModulationRuntime
    private let store: ModulationStore

    init(runtime: ModulationRuntime, store: ModulationStore = ModulationStore()) {
        self.runtime = runtime
        self.store = store
        for binding in store.load().bindings {
            bindings[binding.destination] = binding
        }
        republish(persist: false)
    }

    // MARK: reading

    func binding(for destination: ModDestination) -> ModBinding? { bindings[destination] }

    /// Address order, so the ledger does not reshuffle itself between frames.
    var sorted: [ModBinding] {
        bindings.values.sorted { $0.destination.address < $1.destination.address }
    }

    // MARK: editing

    /// Set (or replace) the one expression for a destination. §6.2: one per destination, so "what
    /// drives this?" always has exactly one answer.
    func set(_ text: String, for destination: ModDestination, mode: ModTargetMode? = nil) {
        let resolvedMode = mode
            ?? bindings[destination]?.mode
            ?? ModTargetMode.default(for: destination)
        bindings[destination] = ModBinding(destination: destination, text: text,
                                           mode: resolvedMode,
                                           isEnabled: bindings[destination]?.isEnabled ?? true)
        republish()
    }

    func setMode(_ mode: ModTargetMode, for destination: ModDestination) {
        guard var binding = bindings[destination] else { return }
        binding.mode = mode
        bindings[destination] = binding
        republish()
    }

    func setEnabled(_ isEnabled: Bool, for destination: ModDestination) {
        guard var binding = bindings[destination] else { return }
        binding.isEnabled = isEnabled
        bindings[destination] = binding
        republish()
    }

    func clear(_ destination: ModDestination) {
        bindings.removeValue(forKey: destination)
        errors.removeValue(forKey: destination)
        republish()
    }

    func clearAll() {
        bindings.removeAll()
        errors.removeAll()
        republish()
    }

    /// §2 — renaming a source rewrites stored expressions so references survive; delete and
    /// recreate does not. Textual, because the address only ever appears as a quoted literal
    /// inside `ref` / `since` / `valid` — the parser guarantees it cannot appear anywhere else.
    ///
    /// No caller exists in this slice: nothing can rename `manual/*`. It is built and pinned now
    /// because the alternative is retrofitting it onto patches operators have already saved.
    func rewriteSourceReferences(from oldAddress: String, to newAddress: String) {
        guard oldAddress != newAddress else { return }
        var changed = false
        for (destination, binding) in bindings where binding.text.contains("\"\(oldAddress)\"") {
            var updated = binding
            updated.text = binding.text.replacingOccurrences(of: "\"\(oldAddress)\"",
                                                             with: "\"\(newAddress)\"")
            bindings[destination] = updated
            changed = true
        }
        if changed { republish() }
    }

    // MARK: publishing

    /// Compile the whole set, hand the compiled mirror to the runtime, and persist the TEXT.
    private func republish(persist: Bool = true) {
        let compiled = bindings.values.map(CompiledBinding.init)
        var freshErrors: [ModDestination: String] = [:]
        for entry in compiled where entry.error != nil {
            freshErrors[entry.binding.destination] = entry.error
        }
        errors = freshErrors
        runtime.publishBindings(compiled)
        if persist {
            store.save(ModulationSnapshot(version: 1, bindings: sorted))
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModulationModelTests 2>&1 | tail -25
```

Expected: PASS, 12 tests.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/ModulationModel.swift App/ARShader/ModulationStore.swift \
        App/ARShaderTests/ModulationModelTests.swift
git commit -m "feat(mod): the binding ledger and its versioned, corrupt-tolerant persistence"
```

---

## Task 10: Wiring — one tick per frame, and the overrides the frame graph reads

**Files:**
- Modify: `App/ARShader/InstrumentRenderer.swift:96-210` (own the runtime), `:360-410`
  (tick + modulated layers), `:438-443` (master FX scope)
- Modify: `App/ARShader/MixerState.swift` (base publishing + the crossfader mirror)
- Modify: `App/ARShader/FXChain.swift` (attach, publish stage bases, modulated mix in `encode`)
- Modify: `App/ARShader/ShaderUnit.swift` (register bases and sinks for scalar inputs)
- Modify: `App/ARShader/Instrument.swift` (own the runtime, the manual source and the model)
- Test: `App/ARShaderTests/ModulationWiringTests.swift`

**Interfaces:**
- Consumes: `ModulationRuntime`, `ModulationModel`, `ManualSource`, `ModDestination`, `ModFXScope`.
- Produces:
  - `MixerState.attachModulation(_ runtime: ModulationRuntime)`,
    `MixerState.renderCrossfadePosition() -> Double` (nonisolated)
  - `FXChain.attachModulation(_ runtime: ModulationRuntime, scope: ModFXScope)`
  - `FXChain.encode(input:scratch:renderSize:compositor:preserveAlpha:in:)` unchanged in signature
    — the chain already knows its own scope after `attachModulation`
  - `ShaderUnit.attachModulation(_ runtime: ModulationRuntime, address: @escaping (String) -> ModDestination)`
  - `InstrumentRenderer.init(device:queue:mixer:modulation:compositorOverride:)`
  - `InstrumentRenderer.lastFrameLayers() -> [LayerParams]` (observability)
  - `Instrument.modulation: ModulationModel`, `Instrument.modulationRuntime: ModulationRuntime`,
    `Instrument.manualSource: ManualSource`
  Tasks 11–12 use exactly these names.

**Which inputs are modulatable.** `float` and `long` only — they are the scalar destinations.
`bool`, `point2D`, `color`, `image` and `event` get no address in this slice: an expression
returns one Double, and inventing a component-wise convention for a colour is a tuning-surface
decision the spec does not make. Say so in `ShaderUnit`'s doc comment so the absence reads as a
decision rather than an oversight.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModulationWiringTests.swift`:

```swift
import XCTest
import Metal

/// The seams: the mixer publishes its bases and its crossfader, chains publish their stages, a
/// compiled shader publishes its scalar inputs, and the frame graph ticks exactly once per frame.
@MainActor
final class ModulationWiringTests: XCTestCase {

    private func makeInstrument() throws -> Instrument {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        return Instrument()
    }

    func testTheMixerPublishesItsBasesSoADriverHasSomethingToRideOn() throws {
        let instrument = try makeInstrument()
        let runtime = instrument.modulationRuntime

        instrument.mixer.setOpacity(0.4, for: .one)
        instrument.modulation.set("0.25", for: .deckOpacity(.one), mode: .offset)
        runtime.tick(now: 1.0)

        XCTAssertEqual(runtime.value(for: .deckOpacity(.one)) ?? 0, 0.65, accuracy: 1e-9,
                       "offset rides the operator's CURRENT fader position")

        instrument.mixer.setOpacity(0.1, for: .one)
        runtime.tick(now: 1.02)
        XCTAssertEqual(runtime.value(for: .deckOpacity(.one)) ?? 0, 0.35, accuracy: 1e-9,
                       "and follows it when the hand moves")
    }

    func testTheCrossfaderIsVisibleToTheRenderThread() throws {
        let instrument = try makeInstrument()

        instrument.mixer.crossfadePosition = 0.375

        XCTAssertEqual(instrument.mixer.renderCrossfadePosition(), 0.375,
                       "The applier needs the BASE position, and may not read @Published state")
    }

    func testTheFrameGraphAppliesModulatedLayers() throws {
        let instrument = try makeInstrument()
        instrument.mixer.setOpacity(1.0, for: .one)
        instrument.modulation.set("0.25", for: .deckOpacity(.one), mode: .absolute)

        instrument.renderer.renderFrame()

        let layer = instrument.renderer.lastFrameLayers().first { $0.deck == .one }
        XCTAssertEqual(layer?.userOpacity ?? -1, 0.25, accuracy: 1e-9,
                       "The composite sees the driven value, not the fader's")
    }

    /// §5.1 — ONE tick per frame. Two ticks in a frame would advance `frame`, re-read the sources
    /// and let two destinations bound to one source drift apart.
    ///
    /// Mutation that must fail this test: call `modulation.tick` a second time anywhere in
    /// `renderFrame`.
    func testExactlyOneTickHappensPerRenderedFrame() throws {
        let instrument = try makeInstrument()
        let probe = ModDestination.deckOpacity(.two)
        instrument.modulation.set("frame", for: probe, mode: .absolute)

        instrument.renderer.renderFrame()
        let first = instrument.modulationRuntime.value(for: probe) ?? -1
        instrument.renderer.renderFrame()
        let second = instrument.modulationRuntime.value(for: probe) ?? -1

        XCTAssertEqual(second - first, 1, accuracy: 1e-9)
    }

    func testAChainPublishesItsStagesSoTheirMixCanBeDriven() throws {
        let instrument = try makeInstrument()
        let deck = instrument.deck(.one)
        let stage = FXStage(device: instrument.device, queue: instrument.queue,
                            clock: instrument.renderer.clock)
        deck.fx.append(stage)
        deck.fx.setMix(0.2, for: stage)

        instrument.modulation.set("0.5", for: .deckFX(.one, stage.id, .mix), mode: .absolute)
        instrument.modulationRuntime.tick(now: 1.0)

        XCTAssertEqual(instrument.modulationRuntime.fxMix(base: 0.2, stage: stage.id,
                                                          scope: .deck(.one)), 0.5)
        XCTAssertFalse(instrument.modulationRuntime.outcome().skipped
                        .contains(.deckFX(.one, stage.id, .mix)))
    }

    func testRemovingAStageLeavesTheBindingSkippedRatherThanDeleted() throws {
        let instrument = try makeInstrument()
        let deck = instrument.deck(.one)
        let stage = FXStage(device: instrument.device, queue: instrument.queue,
                            clock: instrument.renderer.clock)
        deck.fx.append(stage)
        instrument.modulation.set("0.5", for: .deckFX(.one, stage.id, .mix))
        instrument.modulationRuntime.tick(now: 1.0)

        deck.fx.remove(stage.id)
        instrument.modulationRuntime.tick(now: 1.02)

        XCTAssertNotNil(instrument.modulation.binding(for: .deckFX(.one, stage.id, .mix)),
                        "Retained — putting the stage back must restore the driver")
        XCTAssertTrue(instrument.modulationRuntime.outcome().skipped
                        .contains(.deckFX(.one, stage.id, .mix)))
    }

    func testACompiledShaderPublishesItsScalarInputsAndTheirRanges() throws {
        let instrument = try makeInstrument()
        let deck = instrument.deck(.one)
        let loaded = expectation(description: "compiled")
        deck.unit.onCompileFinished = { loaded.fulfill() }
        deck.unit.load(source: Self.twoInputShader, name: "wiring-probe.fs")
        wait(for: [loaded], timeout: 10)

        instrument.modulation.set("9", for: .deckInput(.one, "amount"), mode: .absolute)
        instrument.modulationRuntime.tick(now: 1.0)

        XCTAssertEqual(instrument.modulationRuntime.value(for: .deckInput(.one, "amount")), 2.0,
                       "Clamped to the range the HEADER declares, which only the unit knows")
        XCTAssertNil(instrument.modulationRuntime.value(for: .deckInput(.one, "tint")),
                     "A colour input has no scalar address in this slice — by decision")
    }

    func testUnloadingAShaderSkipsItsBindingsAndReloadingRestoresThem() throws {
        let instrument = try makeInstrument()
        let deck = instrument.deck(.one)
        let first = expectation(description: "compiled")
        deck.unit.onCompileFinished = { first.fulfill() }
        deck.unit.load(source: Self.twoInputShader, name: "wiring-probe.fs")
        wait(for: [first], timeout: 10)
        instrument.modulation.set("1", for: .deckInput(.one, "amount"))
        instrument.modulationRuntime.tick(now: 1.0)
        XCTAssertEqual(instrument.modulationRuntime.value(for: .deckInput(.one, "amount")), 1)

        deck.unit.unload()
        instrument.modulationRuntime.tick(now: 1.02)
        XCTAssertTrue(instrument.modulationRuntime.outcome().skipped
                        .contains(.deckInput(.one, "amount")))

        let second = expectation(description: "recompiled")
        deck.unit.onCompileFinished = { second.fulfill() }
        deck.unit.load(source: Self.twoInputShader, name: "wiring-probe.fs")
        wait(for: [second], timeout: 10)
        instrument.modulationRuntime.tick(now: 1.04)

        XCTAssertEqual(instrument.modulationRuntime.value(for: .deckInput(.one, "amount")), 1,
                       "Swapping the original shader back restores the binding (§4.2)")
    }

    /// A minimal ISF with one float input in a non-unit range and one colour input.
    private static let twoInputShader = """
    /*{
      "DESCRIPTION": "modulation wiring probe",
      "CREDIT": "ARShader tests",
      "CATEGORIES": ["test"],
      "INPUTS": [
        { "NAME": "amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 2.0 },
        { "NAME": "tint", "TYPE": "color", "DEFAULT": [1.0, 1.0, 1.0, 1.0] }
      ]
    }*/
    void main() {
        gl_FragColor = vec4(vec3(amount) * tint.rgb, 1.0);
    }
    """
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `value of type 'Instrument' has no member 'modulationRuntime'`.

- [ ] **Step 3: Teach `MixerState` to publish**

In `App/ARShader/MixerState.swift`, add to the lock-guarded mirror section and the mutators:

```swift
    /// Set once at construction by `Instrument`. The mixer PUSHES its base values in; the runtime
    /// never reaches back for `@Published` state.
    private var modulation: ModulationRuntime?

    func attachModulation(_ runtime: ModulationRuntime) {
        modulation = runtime
        publishModulationBases()
    }

    /// Every mixer destination's current base and declared range.
    private func publishModulationBases() {
        guard let modulation else { return }
        let lastBlend = Double(BlendMode.allCases.count - 1)
        modulation.publishBase(crossfadePosition, range: 0...1, for: .crossfader)
        for deck in DeckID.allCases {
            modulation.publishBase(opacity[deck] ?? 1.0, range: 0...1, for: .deckOpacity(deck))
            let index = BlendMode.allCases.firstIndex(of: blendMode[deck] ?? .normal) ?? 0
            modulation.publishBase(Double(index), range: 0...lastBlend, for: .deckBlend(deck))
        }
    }
```

Add `renderCrossfadePosition` to the mirror — the applier needs the BASE position and may not read
`@Published` state from the display-link thread:

```swift
    nonisolated(unsafe) private var renderCrossfade: Double = 0

    /// The crossfader as the render thread sees it. Safe from the display-link thread.
    nonisolated func renderCrossfadePosition() -> Double {
        renderLock.lock(); defer { renderLock.unlock() }
        return renderCrossfade
    }
```

In `publishToRenderThread()`, capture it alongside the layers and call the base publish:

```swift
    private func publishToRenderThread() {
        let snapshot = layers()
        let black = isBlackedOut
        let position = crossfadePosition
        renderLock.lock()
        renderLayerCache = snapshot
        renderBlackout = black
        renderCrossfade = position
        renderLock.unlock()
        publishModulationBases()
    }
```

- [ ] **Step 4: Teach `FXChain` to publish its stages and read a modulated mix**

In `App/ARShader/FXChain.swift`:

```swift
    private var modulation: ModulationRuntime?
    /// Which chain this is. Deck A's stage and the master's stage are different destinations.
    private var scope: ModFXScope?
    /// The render thread's copy of `scope` — `encode` is nonisolated and may not read the
    /// main-actor property.
    nonisolated(unsafe) private var renderScope: ModFXScope?
    nonisolated(unsafe) private var renderModulation: ModulationRuntime?

    func attachModulation(_ runtime: ModulationRuntime, scope: ModFXScope) {
        modulation = runtime
        self.scope = scope
        renderLock.lock()
        renderModulation = runtime
        renderScope = scope
        renderLock.unlock()
        publishToRenderThread()
    }
```

At the end of `publishToRenderThread()`, publish each stage's mix base and drop the ones that left:

```swift
        // Bases for every stage present, and a clean-up for the ones that are not. A binding to a
        // removed stage is RETAINED and reported skipped (§4.2) — putting the stage back restores
        // it — so only the BASE goes, never the binding.
        if let modulation, let scope {
            let present = Set(stages.map(\.id))
            modulation.removeBases { destination in
                switch (destination, scope) {
                case (.deckFX(let deck, let id, .mix), .deck(let owner)):
                    return deck == owner && !present.contains(id)
                case (.masterFX(let id, .mix), .master):
                    return !present.contains(id)
                default:
                    return false
                }
            }
            for stage in stages {
                let destination: ModDestination = switch scope {
                case .deck(let deck): .deckFX(deck, stage.id, .mix)
                case .master:         .masterFX(stage.id, .mix)
                }
                modulation.publishBase(stage.mix, range: 0...1, for: destination)
            }
        }
```

In `encode`, take the modulated mix per stage:

```swift
        renderLock.lock()
        let runtime = renderModulation
        let chainScope = renderScope
        renderLock.unlock()
        var source = input
        var target = scratch
        for stage in renderStages() {
            let mix = (runtime != nil && chainScope != nil)
                ? runtime!.fxMix(base: stage.mix, stage: stage.id, scope: chainScope!)
                : stage.mix
            guard mix > 0 else { continue }   // dry: no render, no cost
            guard let produced = stage.core.renderOffscreen(size: renderSize, in: cb,
                                                            primaryInput: source) else {
                continue
            }
            compositor.encodeLayer(source: produced, backdrop: source, destination: target,
                                   opacity: mix, mode: stage.blendMode,
                                   preserveAlpha: preserveAlpha, in: cb)
            swap(&source, &target)
        }
```

(The `guard mix > 0` replaces the `guard stage.mix > 0` line Task 1 added.)

- [ ] **Step 5: Teach `ShaderUnit` to publish its scalar inputs**

In `App/ARShader/ShaderUnit.swift`, add:

```swift
    /// Modulation wiring. `address` maps an ISF input NAME to the destination this unit's owner
    /// gives it — a deck knows it is deck A, an FX stage knows its chain and its id; the unit
    /// itself knows neither.
    ///
    /// **`float` and `long` only.** They are the scalar destinations, and an expression returns one
    /// Double. `bool`, `point2D`, `color`, `image` and `event` deliberately get no address in this
    /// slice: a component-wise convention for a colour is a tuning-surface decision the spec does
    /// not make, and inventing one here would be the wrong place to make it.
    private var modulation: ModulationRuntime?
    private var modulationAddress: ((String) -> ModDestination)?

    func attachModulation(_ runtime: ModulationRuntime,
                          address: @escaping (String) -> ModDestination) {
        modulation = runtime
        modulationAddress = address
        refreshModulationDestinations()
    }

    /// Register a base + a sink per scalar input, and drop the ones this shader does not have.
    private func refreshModulationDestinations() {
        guard let modulation, let address = modulationAddress else { return }
        let scalars = inputs.filter { $0.type == "float" || $0.type == "long" }
        let live = Set(scalars.map { address($0.name).address })
        // Only this unit's own destinations, and only the ones this shader no longer has.
        modulation.removeBases { destination in
            isMine(destination, address: address) && !live.contains(destination.address)
        }
        for input in scalars {
            let destination = address(input.name)
            let range = Self.range(of: input)
            modulation.publishBase(currentValue(of: input), range: range, for: destination)
            let core = self.core
            let name = input.name
            let isLong = input.type == "long"
            modulation.setSink({ value in
                // §8 — straight into the scene. Never through ParamStore, never @Published, never
                // UserDefaults: phase 3a already had to debounce a UserDefaults write per drag
                // frame, and this would reproduce that at 60 Hz on every bound parameter at once.
                let scene: ISFMSLSceneVal? = isLong
                    ? ISFMSLSceneVal.create(withLong: Int32(value.rounded())) as? ISFMSLSceneVal
                    : ISFMSLSceneVal.create(withFloat: value) as? ISFMSLSceneVal
                if let scene { core.withScene { $0?.setValue(scene, forInputNamed: name) } }
            }, for: destination)
        }
    }

    /// Whether a destination belongs to THIS unit — used so one unit's clean-up never drops
    /// another's bases.
    private func isMine(_ destination: ModDestination,
                        address: (String) -> ModDestination) -> Bool {
        switch destination {
        case .deckInput(_, let name), .deckFX(_, _, .input(let name)),
             .masterFX(_, .input(let name)):
            return address(name) == destination
        default:
            return false
        }
    }

    private func currentValue(of input: ISFPreviewInput) -> Double {
        switch params.value(for: input.name) {
        case .float(let v)?: return v
        case .long(let v)?:  return v
        default:             return (input.defaultValue as? Double) ?? 0
        }
    }

    private static func range(of input: ISFPreviewInput) -> ClosedRange<Double> {
        let lo = (input.min as? Double) ?? 0
        let hi = (input.max as? Double) ?? 1
        return hi > lo ? lo...hi : lo...(lo + 1)
    }
```

Call it from the two places the input set or a base can change — at the end of the success branch
of `apply(_:name:generation:)`, and inside `unload()`:

```swift
        params.replayAll()
        refreshModulationDestinations()
        onCompileFinished?()
```

```swift
    func unload() {
        loadGeneration += 1
        core.setScene(nil, imageInputNames: [])
        shaderName = nil
        inputs = []
        compileError = nil
        params.resetAll()
        refreshModulationDestinations()   // inputs is empty now: every base goes, bindings stay
    }
```

And extend the `params.onSet` hook in `init` so a hand-set base stays live under an `offset`
driver:

```swift
        params.onSet = { [weak self] name, json in
            self?.applyInput(name, json)
            self?.publishModulationBase(named: name)
        }
```

```swift
    /// One input's base changed because the operator moved a control. `offset` bindings ride it
    /// immediately; `absolute` ones are unaffected.
    private func publishModulationBase(named name: String) {
        guard let modulation, let address = modulationAddress,
              let input = inputs.first(where: { $0.name == name }),
              input.type == "float" || input.type == "long" else { return }
        modulation.publishBase(currentValue(of: input), range: Self.range(of: input),
                               for: address(name))
    }
```

- [ ] **Step 6: Tick the runtime in the frame graph**

In `App/ARShader/InstrumentRenderer.swift`, take the runtime in `init` and hold it:

```swift
    /// The modulation layer. Ticked ONCE at the top of every frame (spec §5.1) — two ticks in one
    /// frame would advance `frame`, re-read the sources, and let two destinations bound to the
    /// same source drift apart by a frame.
    private let modulation: ModulationRuntime
```

```swift
    @MainActor
    init(device: MTLDevice, queue: MTLCommandQueue, mixer: MixerState,
         modulation: ModulationRuntime, compositorOverride: CompositorOverride? = nil) {
        self.modulation = modulation
```

Add the observability field beside `deckRasterSizes` — same justification as that one carries:

```swift
    /// The layer set the composite ACTUALLY used last frame, after modulation. Observability, not
    /// decoration: "a driven fader reaches the composite" is the whole claim of the wiring, and
    /// without this it is not assertable — the mixer's own published layers are the same either
    /// way.
    private var lastLayers: [LayerParams] = []
```

```swift
    func lastFrameLayers() -> [LayerParams] {
        lock.lock(); defer { lock.unlock() }
        return lastLayers
    }
```

At the top of `renderFrame()`, replace the first line:

```swift
    func renderFrame() {
        // ONE tick, before anything reads a modulated value. The app-owned render clock, not wall
        // clock (§5.2), so pause behaves and a recompile does not restart motion.
        modulation.tick(now: clock.now)
        let layers = modulation.modulatedLayers(mixer.renderLayers(),
                                                crossfader: mixer.renderCrossfadePosition())
```

Inside the `lock.lock()` block that already sets `deckOutputs`, record the layer set:

```swift
        deckRasterSizes = rasterSizes
        lastLayers = layers
```

- [ ] **Step 7: Own it all in `Instrument`**

In `App/ARShader/Instrument.swift`:

```swift
    /// The modulation layer. The runtime is the render thread's half; the model is the operator's
    /// ledger; the manual source is the stub provider that makes the whole thing playable with no
    /// audio subsystem in existence (spec §3.1).
    let modulationRuntime = ModulationRuntime()
    let manualSource: ManualSource
    let modulation: ModulationModel
```

In `init`, after the renderer exists:

```swift
        self.manualSource = ManualSource(registry: modulationRuntime.sources,
                                         now: CACurrentMediaTime())
        self.renderer = InstrumentRenderer(device: props.device, queue: props.renderQueue,
                                           mixer: mixer, modulation: modulationRuntime)
        self.modulation = ModulationModel(runtime: modulationRuntime)
        mixer.attachModulation(modulationRuntime)
        renderer.masterFX.attachModulation(modulationRuntime, scope: .master)
        for id in DeckID.allCases {
            let deck = renderer.deck(id)
            deck.fx.attachModulation(modulationRuntime, scope: .deck(id))
            deck.unit.attachModulation(modulationRuntime) { .deckInput(id, $0) }
        }
```

`ManualSourceRuntime.tick` needs the frame too — add it beside the modulation tick in
`renderFrame()`. The renderer does not know about `ManualSource`, so hand it the closure in
`Instrument.init`:

```swift
        let manual = manualSource.runtime
        renderer.onBeforeModulationTick = { now, dt in manual.tick(now: now, dt: dt) }
```

and in `InstrumentRenderer`:

```swift
    /// Providers that must advance before the frame's snapshot is taken. Fires on the render
    /// thread. The manual source's LFO and beat phase integrate here (§5.2).
    var onBeforeModulationTick: (@Sendable (Double, Double) -> Void)?
```

```swift
        let now = clock.clockNow()
        onBeforeModulationTick?(now, modulation.frameDelta(before: now))
        modulation.tick(now: now)
```

Add the two small accessors this needs — `RenderClock.now` is already public, so use it directly
as `clock.now`, and add to `ModulationRuntime`:

```swift
    /// The delta `tick(now:)` will use, so a provider integrating ahead of the tick uses the same
    /// one. Does not advance anything.
    func frameDelta(before now: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        return min(max(0, now - (lastTickTime ?? now)), Self.maxFrameDelta)
    }
```

- [ ] **Step 8: Fix the other `InstrumentRenderer` call sites**

`InstrumentRendererTests`, `FrameGraphTests`, `RenderScaleTests`, `CompositorTests` and
`SurfaceRenderHarness` may construct `InstrumentRenderer` directly. Give each one a
`ModulationRuntime()`:

```bash
grep -rn "InstrumentRenderer(" App/ARShaderTests App/ARShader | grep -v "^App/ARShader/Instrument.swift"
```

Update every hit to pass `modulation: ModulationRuntime()`.

- [ ] **Step 9: Run the tests**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModulationWiringTests 2>&1 | tail -25
```

Expected: PASS, 8 tests. Then the full suite:

```bash
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test 2>&1 | tail -5
```

Expected: the Task 1 baseline plus every test added since, all passing.

- [ ] **Step 10: Prove the one-tick-per-frame gate can fail**

Add a second `modulation.tick(now: clock.now)` immediately after the first in `renderFrame()`.
Re-run Step 9's first command.

Expected: FAIL on `testExactlyOneTickHappensPerRenderedFrame` — the delta is 2, not 1. Revert,
re-run to confirm PASS, record it in the Task 13 evidence table.

- [ ] **Step 11: Commit**

```bash
git add App/ARShader/InstrumentRenderer.swift App/ARShader/MixerState.swift \
        App/ARShader/FXChain.swift App/ARShader/ShaderUnit.swift \
        App/ARShader/Instrument.swift App/ARShader/ModulationRuntime.swift \
        App/ARShaderTests/ModulationWiringTests.swift
# plus any test files Step 8 touched

git commit -m "feat(mod): wire the modulation layer into the frame graph"
```

---

## Task 11: A driven control is visibly driven

**Files:**
- Modify: `App/ARShader/FXChainView.swift:105-111` (the Mix slider)
- Modify: `App/ARShader/ShaderControlsView.swift:115-127` (the float slider),
  `:181-199` (the long menu), `:101-111` (`labelRow`)
- Modify: `App/ARShader/InstrumentView.swift` (deck opacity + crossfader in the mixer strip)
- Create: `App/ARShader/DrivenControl.swift` (the one modifier all three use)
- Test: `App/ARShaderTests/DrivenControlTests.swift`

**Interfaces:**
- Consumes: `ModulationModel`, `ModulationRuntime`, `ModDestination`, `ModTargetMode`.
- Produces:
  - `enum DrivenState: Equatable { case free, offset, absolute }`
  - `DrivenState.of(_ destination: ModDestination, model: ModulationModel) -> DrivenState`
  - `struct DrivenBadge: View` — the "MOD" marker plus the clear-driver button
  - `View.driven(_ state: DrivenState, destination:, model:) -> some View`
  Task 12 uses `DrivenState` and `DrivenBadge`.

**The rule (spec §6.1), stated exactly.** In `offset` mode the base is always live and there is no
conflict — the control keeps working. In `absolute` mode the control displays as driven and a
gesture on it is **ignored, not silently clearing the driver**; an explicit clear-driver affordance
sits with the control. Silent clearing destroys work that cannot be recovered; silent ignoring is
merely confusing, and the visible driven state resolves the confusion.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/DrivenControlTests.swift`:

```swift
import XCTest

/// Spec §6.1 — the ownership rule, tested on the MODEL rather than through a view, because that
/// is where the decision lives and it is the only kind of test that has ever been cheap here.
@MainActor
final class DrivenControlTests: XCTestCase {

    private let opacity = ModDestination.deckOpacity(.one)

    private func makeModel() throws -> ModulationModel {
        let suite = "arshader-driven-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ModulationModel(runtime: ModulationRuntime(),
                               store: ModulationStore(defaults: defaults))
    }

    func testAnUnboundControlIsFree() throws {
        XCTAssertEqual(DrivenState.of(opacity, model: try makeModel()), .free)
    }

    func testAnOffsetBoundControlStaysEditable() throws {
        let model = try makeModel()
        model.set("0.1", for: opacity, mode: .offset)

        XCTAssertEqual(DrivenState.of(opacity, model: model), .offset)
        XCTAssertTrue(DrivenState.offset.acceptsGestures,
                      "In offset mode the base is always live — a hand on the fader composes")
    }

    func testAnAbsoluteBoundControlIsShownDrivenAndIgnoresGestures() throws {
        let model = try makeModel()
        model.set("0.1", for: opacity, mode: .absolute)

        XCTAssertEqual(DrivenState.of(opacity, model: model), .absolute)
        XCTAssertFalse(DrivenState.absolute.acceptsGestures)
    }

    /// The half that matters most: a gesture must NOT clear the driver.
    ///
    /// Mutation that must fail this test: make the control's setter call `model.clear(destination)`
    /// when it is driven in absolute mode.
    func testAGestureOnADrivenControlLeavesTheDriverIntact() throws {
        let model = try makeModel()
        model.set(#"exp(-since("manual/trigger") / 0.5)"#, for: opacity, mode: .absolute)

        // What the slider's setter does when the state does not accept gestures: nothing.
        if DrivenState.of(opacity, model: model).acceptsGestures {
            XCTFail("An absolute-driven control must not accept a gesture")
        }

        XCTAssertEqual(model.binding(for: opacity)?.text,
                       #"exp(-since("manual/trigger") / 0.5)"#,
                       "Silent clearing destroys work that cannot be recovered")
    }

    func testTheExplicitClearAffordanceIsTheOnlyWayOut() throws {
        let model = try makeModel()
        model.set("0.1", for: opacity, mode: .absolute)

        model.clear(opacity)

        XCTAssertEqual(DrivenState.of(opacity, model: model), .free)
    }

    /// A disabled binding is not a driver. The control comes back rather than staying locked with
    /// nothing driving it — which would be unrecoverable without opening the panel.
    func testADisabledBindingLeavesTheControlFree() throws {
        let model = try makeModel()
        model.set("0.1", for: opacity, mode: .absolute)
        model.setEnabled(false, for: opacity)

        XCTAssertEqual(DrivenState.of(opacity, model: model), .free)
    }

    /// So is a broken one — a control locked by an expression that cannot run is a dead control.
    func testABindingThatDidNotCompileLeavesTheControlFree() throws {
        let model = try makeModel()
        model.set("exp(-since(", for: opacity, mode: .absolute)

        XCTAssertEqual(DrivenState.of(opacity, model: model), .free)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `cannot find 'DrivenState' in scope`.

- [ ] **Step 3: Write the shared state and the badge**

Create `App/ARShader/DrivenControl.swift`:

```swift
import SwiftUI

/// How a control relates to the modulation layer right now (spec §6.1).
enum DrivenState: Equatable {
    /// Nothing drives it — an ordinary control.
    case free
    /// Driven on top of the operator's value. The control keeps working: the base is always live,
    /// so a hand on the fader and a kick on the envelope compose instead of fighting.
    case offset
    /// The expression OWNS the value. The control shows as driven and a gesture on it is IGNORED,
    /// never silently clearing the driver — losing a patch to a stray touch is unrecoverable,
    /// while a control that will not move is merely confusing, and the badge explains it.
    case absolute

    var acceptsGestures: Bool { self != .absolute }

    /// A binding that is disabled, or that did not compile, is NOT a driver: the control comes
    /// back rather than staying locked with nothing driving it.
    static func of(_ destination: ModDestination, model: ModulationModel) -> DrivenState {
        guard let binding = model.binding(for: destination), binding.isEnabled,
              model.errors[destination] == nil else { return .free }
        return binding.mode == .offset ? .offset : .absolute
    }
}

/// The marker that sits beside a driven control, and the only way out of `absolute`.
struct DrivenBadge: View {
    let state: DrivenState
    let destination: ModDestination
    @ObservedObject var model: ModulationModel

    var body: some View {
        if state != .free {
            HStack(spacing: 3) {
                Text("MOD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 3)
                    .background(.tint.opacity(state == .absolute ? 0.7 : 0.35),
                                in: RoundedRectangle(cornerRadius: 3))
                Button {
                    model.clear(destination)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Clear the driver on \(destination.displayName)")
            }
            .help(state == .absolute
                  ? "Driven: \(model.binding(for: destination)?.text ?? "") — this control is "
                    + "held by its expression. Clear the driver to take it back."
                  : "Driven on top of your value: \(model.binding(for: destination)?.text ?? "")")
        }
    }
}

extension View {
    /// Dim an `absolute`-driven control and stop it taking gestures. `offset` is left fully live.
    func driven(_ state: DrivenState) -> some View {
        disabled(!state.acceptsGestures)
            .opacity(state == .absolute ? 0.55 : 1)
    }
}
```

- [ ] **Step 4: Adopt it in the three control sites**

**`FXChainView.swift`** — the stage row needs the model and its own scope. Add
`@ObservedObject var modulation: ModulationModel` and `let scope: ModFXScope` to both
`FXChainView` and `FXStageRow`, thread them from `InstrumentView`'s two call sites, and wrap the
Mix row:

```swift
            HStack(spacing: 4) {
                Text("Mix").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { stage.mix },
                                      set: { chain.setMix($0, for: stage) }), in: 0...1)
                    .driven(mixState)
                Text(String(format: "%.2f", stage.mix))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                DrivenBadge(state: mixState, destination: mixDestination, model: modulation)
            }
```

```swift
    private var mixDestination: ModDestination {
        switch scope {
        case .deck(let deck): return .deckFX(deck, stage.id, .mix)
        case .master:         return .masterFX(stage.id, .mix)
        }
    }

    private var mixState: DrivenState { .of(mixDestination, model: modulation) }
```

**`ShaderControlsView.swift`** — add `@ObservedObject var modulation: ModulationModel` and
`let address: (String) -> ModDestination` (the same closure the unit was attached with, so a deck's
and a stage's controls resolve to their own addresses). Wrap the float slider and the long menu:

```swift
    @ViewBuilder private func sliderRow(_ input: ISFPreviewInput) -> some View {
        let lo = (input.min as? Double) ?? 0
        let hi = (input.max as? Double) ?? 1
        let fallback = (input.defaultValue as? Double) ?? lo
        let destination = address(input.name)
        let state = DrivenState.of(destination, model: modulation)
        let binding = Binding<Double>(
            get: { if case .float(let v)? = unit.params.value(for: input.name) { return v }
                   return fallback },
            set: { newValue in
                // §6.1 — an absolute-driven control IGNORES the gesture. It does not clear the
                // driver, and it does not write a base nothing will read.
                guard state.acceptsGestures else { return }
                unit.params.set(input.name, .float(newValue))
            })
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: format(binding.wrappedValue), state: state,
                     destination: destination)
            Slider(value: binding, in: lo...max(hi, lo + 0.0001)).driven(state)
        }
    }
```

Extend `labelRow` to carry the badge, and make the double-click reset respect the same rule:

```swift
    private func labelRow(_ name: String, value: String,
                          state: DrivenState = .free,
                          destination: ModDestination? = nil) -> some View {
        HStack(spacing: 5) {
            if unit.params.isModified(name) { Circle().fill(.tint).frame(width: 5, height: 5) }
            Text(name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let destination {
                DrivenBadge(state: state, destination: destination, model: modulation)
            }
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard state.acceptsGestures else { return }
            unit.params.resetToDefault(name)
        }
        .help("Double-click to reset to default")
    }
```

Apply the identical `state` / `guard state.acceptsGestures else { return }` / `.driven(state)`
treatment to `menuRow` (a `long` input is a scalar destination too). `toggleRow`, `pointRow`,
`colorRow` and `pulseRow` are unchanged — those types have no address (Task 10).

**`InstrumentView.swift`** — the mixer strip's deck-opacity sliders and the crossfader get the same
three lines: compute `DrivenState.of(.deckOpacity(id), model: instrument.modulation)` (and
`.crossfader`), `guard state.acceptsGestures else { return }` in the setter, `.driven(state)` on
the control, and a `DrivenBadge` beside it. **The BLACKOUT button gets nothing** — it has no
destination and no `DrivenState`, which is §4.3 showing up in the UI as an absence.

- [ ] **Step 5: Run the tests**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/DrivenControlTests 2>&1 | tail -20
```

Expected: PASS, 7 tests. Then the full suite — `SurfaceGeometryTests` renders the real views and
its PNG baselines will now include the badges:

```bash
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test 2>&1 | tail -8
```

If a baseline comparison fails, confirm the diff is ONLY the new badge (no badge is drawn with no
bindings, so an unbound instrument should be pixel-identical). If a layout shift is real, re-record
the baselines per `SurfaceRenderHarness`'s recording path and commit the new PNGs with a note
saying what changed.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/DrivenControl.swift App/ARShader/FXChainView.swift \
        App/ARShader/ShaderControlsView.swift App/ARShader/InstrumentView.swift \
        App/ARShaderTests/DrivenControlTests.swift
git commit -m "feat(mod): a driven control is visibly driven and never silently cleared"
```

---

## Task 12: The modulation panel

**Files:**
- Create: `App/ARShader/ModulationPanelView.swift`
- Modify: `App/ARShader/SurfaceLayout.swift:7-24` (`PanelID.modulation`)
- Modify: `App/ARShader/InstrumentView.swift:259-268` (`panelContent`)
- Test: `App/ARShaderTests/ModulationPanelTests.swift`

**Interfaces:**
- Consumes: `ModulationModel`, `ManualSource`, `ModulationRuntime`, `ModDestination`,
  `DrivenState`, `DrivenBadge`.
- Produces: `struct ModulationPanelView: View`, `PanelID.modulation`,
  `ModulationPanelModel.destinationCatalogue(for: Instrument) -> [ModDestination]`.

**Deliberately plain.** Spec §10.2 defers the learn-style "touch the parameter, then the source"
gesture to the tuning-panel slice. This panel is the minimum that makes the on-device gate
runnable: the manual source's controls, the list of live sources, and a ledger of bindings with a
destination picker, an expression field, a mode toggle and a clear button. Design comes after the
operator has played with it — the same call phase 3a made for the whole surface.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/ModulationPanelTests.swift`:

```swift
import XCTest

/// The panel's model-level facts. The view itself is exercised by the on-device gate (Task 14);
/// what is testable without a view is what the rail promises and what the picker offers.
@MainActor
final class ModulationPanelTests: XCTestCase {

    /// Phase 3a's premise: a later phase adds a tool by adding ONE case. This is that phase.
    func testTheRailGainsAModulationPanelAndKeepsItsShortcutContract() {
        XCTAssertTrue(PanelID.allCases.contains(.modulation))
        XCTAssertEqual(PanelID.modulation.title, "Modulation")
        XCTAssertFalse(PanelID.modulation.systemImage.isEmpty)

        for (index, panel) in PanelID.allCases.enumerated() where index < 9 {
            XCTAssertEqual(panel.shortcutNumber, index + 1,
                           "\(panel.title) is rail position \(index + 1)")
        }
    }

    /// §4.3 again, at the surface this time: the picker cannot offer what has no address.
    func testTheDestinationPickerNeverOffersBlackout() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        let instrument = Instrument()

        let catalogue = ModulationPanelModel.destinationCatalogue(for: instrument)

        XCTAssertFalse(catalogue.isEmpty)
        XCTAssertFalse(catalogue.contains { $0.address.lowercased().contains("black") })
        XCTAssertTrue(catalogue.contains(.crossfader))
        XCTAssertTrue(catalogue.contains(.deckOpacity(.one)))
    }

    func testTheSourceListShowsWhatTheRegistryActuallyHas() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        let instrument = Instrument()

        let addresses = instrument.modulationRuntime.sources.descriptors().map(\.address)

        XCTAssertEqual(addresses, ["manual/lfo", "manual/tap", "manual/trigger"],
                       "The stub provider ships in this slice and stays permanently (§3.1)")
    }
}
```

Add `import Metal` at the top of the file.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  build-for-testing 2>&1 | tail -15
```

Expected: `type 'PanelID' has no member 'modulation'`.

- [ ] **Step 3: Add the rail case**

In `App/ARShader/SurfaceLayout.swift`:

```swift
    case library, settings, modulation
```

```swift
        case .library:    return "square.grid.2x2"
        case .settings:   return "gearshape"
        case .modulation: return "waveform.path"
```

```swift
        case .library:    return "Library"
        case .settings:   return "Settings"
        case .modulation: return "Modulation"
```

- [ ] **Step 4: Write the panel**

Create `App/ARShader/ModulationPanelView.swift`:

```swift
import SwiftUI

/// What the destination picker may offer. Built from the instrument's LIVE state, so a shader
/// with no inputs contributes nothing and a chain with three stages contributes three mixes.
enum ModulationPanelModel {
    static func destinationCatalogue(for instrument: Instrument) -> [ModDestination] {
        var deckInputs: [DeckID: [String]] = [:]
        var deckFX: [DeckID: [UUID: [String]]] = [:]
        for id in DeckID.allCases {
            let deck = instrument.deck(id)
            deckInputs[id] = scalarNames(deck.unit)
            deckFX[id] = Dictionary(uniqueKeysWithValues:
                deck.fx.stages.map { ($0.id, scalarNames($0.unit)) })
        }
        let masterFX = Dictionary(uniqueKeysWithValues:
            instrument.renderer.masterFX.stages.map { ($0.id, scalarNames($0.unit)) })
        return ModDestination.catalogue(deckInputs: deckInputs, deckFX: deckFX,
                                        masterFX: masterFX)
            .sorted { $0.address < $1.address }
    }

    /// The addressable input types, and only those (see `ShaderUnit.attachModulation`).
    private static func scalarNames(_ unit: ShaderUnit) -> [String] {
        unit.inputs.filter { $0.type == "float" || $0.type == "long" }.map(\.name)
    }
}

/// Sources at the top, the ledger below.
///
/// Deliberately plain (spec §10.2 defers the learn gesture to the tuning-panel slice). This is the
/// minimum that makes the on-device gate playable: a trigger you can hit on the downbeat, an LFO,
/// a tap tempo, and a list of what drives what.
struct ModulationPanelView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject private var model: ModulationModel
    @ObservedObject private var manual: ManualSource
    @State private var newDestination: ModDestination = .crossfader
    @State private var newText = ""

    init(instrument: Instrument) {
        self.instrument = instrument
        self.model = instrument.modulation
        self.manual = instrument.manualSource
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sources
                Divider()
                ledger
                Divider()
                adder
            }
            .padding(12)
        }
    }

    // MARK: sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCES").font(.system(size: 11, weight: .bold, design: .monospaced))
            Button("TRIGGER") { manual.trigger() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .help("manual/trigger — hit it on the downbeat. Every since() envelope bound to "
                      + "it shapes that one edge independently.")
            HStack {
                Text("LFO").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: $manual.lfoRate, in: 0.05...20)
                Text(String(format: "%.2f Hz", manual.lfoRate))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Picker("", selection: $manual.lfoShape) {
                ForEach(LFOShape.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small)
            HStack {
                Button("TAP") { manual.tap() }
                    .help("manual/tap — two taps set the tempo; every tap realigns the downbeat")
                Text(String(format: "%.1f BPM", manual.tempoBPM))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            ForEach(instrument.modulationRuntime.sources.descriptors(), id: \.address) { output in
                Text("\(output.address) · \(output.kind.rawValue)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: ledger

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRIVERS").font(.system(size: 11, weight: .bold, design: .monospaced))
            if model.sorted.isEmpty {
                Text("Nothing is driven. Add a driver below.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(model.sorted, id: \.destination) { binding in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Toggle("", isOn: Binding(get: { binding.isEnabled },
                                                 set: { model.setEnabled($0,
                                                                         for: binding.destination) }))
                            .labelsHidden().toggleStyle(.checkbox)
                        Text(binding.destination.displayName)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .help(binding.destination.address)
                        Spacer()
                        Picker("", selection: Binding(get: { binding.mode },
                                                      set: { model.setMode($0,
                                                                           for: binding.destination) })) {
                            Text("offset").tag(ModTargetMode.offset)
                            Text("absolute").tag(ModTargetMode.absolute)
                        }
                        .labelsHidden().controlSize(.small).frame(width: 92)
                        Button { model.clear(binding.destination) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain).help("Clear this driver")
                    }
                    TextField("expression", text: Binding(
                        get: { binding.text },
                        set: { model.set($0, for: binding.destination) }))
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    if let error = model.errors[binding.destination] {
                        // §7 — saved and inactive with the error visible. The text is never lost.
                        Text(error).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: adder

    private var adder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADD").font(.system(size: 11, weight: .bold, design: .monospaced))
            Picker("", selection: $newDestination) {
                ForEach(ModulationPanelModel.destinationCatalogue(for: instrument),
                        id: \.self) { destination in
                    Text(destination.displayName).tag(destination)
                }
            }
            .labelsHidden().controlSize(.small)
            HStack {
                TextField(#"exp(-since("manual/trigger") / 0.25)"#, text: $newText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button("BIND") {
                    guard !newText.isEmpty else { return }
                    model.set(newText, for: newDestination)
                    newText = ""
                }
            }
            Text("ref(\"a/b\") · since(\"a/b\") · valid(\"a/b\") · time · dt · frame · self")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Text(ExprSignature.functionNames.joined(separator: " · "))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 5: Wire it into the panel host**

In `App/ARShader/InstrumentView.swift`'s `panelContent`:

```swift
        case .modulation:
            ModulationPanelView(instrument: instrument)
```

- [ ] **Step 6: Run the tests**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test 2>&1 | tail -8
```

Expected: everything passes. `SurfaceLayoutTests.testEachPanelsShortcutDigitMatchesItsPosition…`
and `testTheCollapsibleSetIsExactly…` both still hold — the new case is a PANEL, not a section.

- [ ] **Step 7: Commit**

```bash
git add App/ARShader/ModulationPanelView.swift App/ARShader/SurfaceLayout.swift \
        App/ARShader/InstrumentView.swift App/ARShaderTests/ModulationPanelTests.swift
git commit -m "feat(mod): the modulation panel — sources, ledger, and a plain binding adder"
```

---

## Task 13: The performance budget, and the mutation evidence

**Files:**
- Create: `App/ARShaderTests/ModulationPerformanceTests.swift`
- Create: `docs/reports/modulation-mutation-evidence.md`

**Interfaces:**
- Consumes: everything built so far. Produces no new API.

**The budget (spec §9.2).** Evaluating 64 bound routes must cost under **0.5 ms per frame** (3% of
a 16.6 ms budget), measured rather than assumed. Exceeding it moves evaluation off the render
thread — do not silently accept a slower number.

- [ ] **Step 1: Write the budget test**

Create `App/ARShaderTests/ModulationPerformanceTests.swift`:

```swift
import XCTest

/// Spec §9.2 — the frame budget, measured. A modulation layer that costs more than 3% of the
/// frame is not a modulation layer, it is a new bottleneck on the one thread that may not have one.
final class ModulationPerformanceTests: XCTestCase {

    /// 64 routes across every destination shape, each with a non-trivial expression — a decay, a
    /// reference, a clamp and some arithmetic, which is what a real patch looks like.
    private func makeLoadedRuntime() -> ModulationRuntime {
        let runtime = ModulationRuntime()
        runtime.sources.register(ModOutputDescriptor(address: "stub/kick", kind: .counter,
                                                     range: 0...1e9, provenance: "Test",
                                                     staleAfter: .infinity), now: 0)
        runtime.sources.register(ModOutputDescriptor(address: "stub/level", kind: .continuous,
                                                     range: 0...1, provenance: "Test",
                                                     staleAfter: .infinity), now: 0)
        var bindings: [CompiledBinding] = []
        for index in 0..<64 {
            let destination: ModDestination = .deckInput(index % 2 == 0 ? .one : .two,
                                                         "input\(index)")
            runtime.publishBase(0.5, range: 0...1, for: destination)
            let text = #"clamp(0.2 + exp(-since("stub/kick") / 0.35) * ref("stub/level") "#
                + #"* 1.6 + sin(time * 2.0) * 0.1, 0, 1)"#
            bindings.append(CompiledBinding(ModBinding(destination: destination, text: text,
                                                       mode: .offset, isEnabled: true)))
        }
        runtime.publishBindings(bindings)
        return runtime
    }

    func testSixtyFourRoutesEvaluateInsideTheFrameBudget() {
        let runtime = makeLoadedRuntime()
        let frames = 600
        runtime.tick(now: 0)                      // warm: first tick allocates the result dict

        let start = CACurrentMediaTime()
        for frame in 1...frames {
            runtime.tick(now: Double(frame) / 60.0)
        }
        let msPerFrame = (CACurrentMediaTime() - start) / Double(frames) * 1000

        XCTAssertLessThan(msPerFrame, 0.5,
                          String(format: "64 routes cost %.4f ms/frame — the budget is 0.5 ms "
                                 + "(3%% of 16.6). Exceeding it moves evaluation off the render "
                                 + "thread rather than being accepted.", msPerFrame))
        print("MODULATION BUDGET: \(String(format: "%.4f", msPerFrame)) ms/frame for 64 routes")
    }

    /// The unbound case must be free — an instrument with no drivers must not pay for the layer.
    func testAnEmptyRuntimeCostsEssentiallyNothing() {
        let runtime = ModulationRuntime()
        runtime.tick(now: 0)

        let start = CACurrentMediaTime()
        for frame in 1...600 { runtime.tick(now: Double(frame) / 60.0) }
        let msPerFrame = (CACurrentMediaTime() - start) / 600 * 1000

        XCTAssertLessThan(msPerFrame, 0.05)
    }
}
```

Add `import QuartzCore` for `CACurrentMediaTime`.

- [ ] **Step 2: Run it and record the number**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  test -only-testing:ARShaderTests/ModulationPerformanceTests 2>&1 | grep -E "MODULATION BUDGET|passed|failed"
```

Expected: PASS, with the measured figure printed. **Write the measured number into the evidence
doc in Step 3.** If it fails, do not raise the threshold — report the figure and stop; moving
evaluation off the render thread is a design change, not a test tweak.

- [ ] **Step 3: Collect the mutation evidence**

Create `docs/reports/modulation-mutation-evidence.md` and fill in every row from the runs each task
already performed. Spec §9.1 requires each gate to ship with its mutation demonstrated; this is
where that is recorded so a reviewer can see it without re-deriving it.

**The Observed-failure cells below are filled AS EACH TASK RUNS ITS MUTATION, not at Task 13.**
The table does not exist as a file until this task, so "record it in the Task 13 evidence table"
means *write the observed line into this template, in the plan, in the same commit as the task*.
Task 1 did not, and its observation was gone by Task 2 — a table that can only be filled from
memory 12 tasks later is exactly the un-failable-evidence problem §9.1 exists to prevent.

```markdown
# Modulation layer — mutation evidence

Spec §9.1 requires each gate to ship with the mutation that must break it, demonstrated. This
project has twice nearly shipped tests that could not fail (phase 3a's layout harness, phase 3b's
`/tmp/a.fs` fixture and its snapshot-timing assertion), so the demonstration is the deliverable,
not the intention.

| Gate | Mutation applied | Test that failed | Observed failure | Task |
|---|---|---|---|---|
| FX stable IDs | Address by array index instead of id, then reorder | `FXStageIdentityTests.testAStageIsFoundByItsIdAcrossAReorder` | NOT RECORDED at the time of the run — re-run the mutation before Task 13 rather than inventing a line | 1 |
| Blackout exclusion | Add a `blackout` case and put it in the catalogue | `ModDestinationTests.testTheAddressableCatalogueIsExactlyTheSpecs…` | 2 failures. L55 `XCTAssertEqual failed` — catalogue contained `ModDestination.blackout`; L62 `XCTAssertFalse failed - An expression that can kill the output mid-set is a defect with no upside` | 2 |
| Frame coherence (registry) | Make `ModSnapshot` resolve `reading(_:)` from the live registry (NOT "drop the entries copy" — that mutation passes; see Task 3 Step 5) | `ModSourceTests.testASnapshotIsFrozenAgainstLaterPublishes` | L109 `XCTAssertEqual failed: ("Optional(0.8)") is not equal to ("Optional(0.2)") - The frame's snapshot is a value, not a live view of the registry` | 3 |
| `since()` decay shape | Change the time constant from 0.002 to 0.02 | `ExpressionEvaluatorTests.testOneCounterDrivesAStrobeAndASwell…` | | 6 |
| `offset` ownership | Let `offset` write the base (drop `base.value +`) | `ModulationEngineTests.testOffsetModeAddsToTheBase…` | | 7 |
| NaN containment | Remove the `isFinite` guard | `ModulationEngineTests.testNonFiniteResultsAreContainedAndFlagged` | | 7 |
| Skipped bindings | Drop unresolvable bindings instead of reporting them | `ModulationEngineTests.testAnUnresolvableDestinationIsSkipped…` | | 7 |
| Cycle latency | Read this frame's value for `self` instead of the previous | `ModulationEngineTests.testSelfReadsThePreviousFrame…` | | 7 |
| One tick per frame | Tick a second time in `renderFrame` | `ModulationWiringTests.testExactlyOneTickHappensPerRenderedFrame` | | 10 |
| Silent driver clearing | Clear the driver from a gesture on an absolute-driven control | `DrivenControlTests.testAGestureOnADrivenControlLeavesTheDriverIntact` | | 11 |

## Frame budget (spec §9.2)

- 64 routes: **___ ms/frame** (budget 0.5 ms, measured on ___ )
- 0 routes: **___ ms/frame**
```

- [ ] **Step 4: Commit**

```bash
git add App/ARShaderTests/ModulationPerformanceTests.swift \
        docs/reports/modulation-mutation-evidence.md
git commit -m "test(mod): the frame budget, measured, and the mutation evidence for every gate"
```

---

## Task 14: The on-device gate

**Files:**
- Create: `docs/reports/live-smoke-instrument-m2-modulation.md`

**Interfaces:** none — this task runs the instrument and records what the operator saw.

**Why this is a task and not a footnote.** Spec §9.3: this slice has no protocol boundary — no
external API, no hardware, no shell — so correctness is covered in-process and the device gate is
about **musicality**, not function. All five legs run with no audio subsystem in existence, which
is the whole argument for building routing first.

**Announce before running anything here.** `scripts/run-instrument.sh` quits any running ARShader.

- [ ] **Step 1: Pre-flight assertions**

Before involving the operator, confirm the environment is what the legs assume. State each as a
hypothesis that can fail, not as "it works":

```bash
# The staged binary contains THIS build, not an incremental stale one.
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-mod \
  -configuration Debug build 2>&1 | tail -3
strings /tmp/arshader-ddata-mod/Build/Products/Debug/ARShader.app/Contents/MacOS/ARShader \
  | grep -c "Clear the driver on"
```

Expected: `1` or more. **Zero means the binary is stale and no leg below is meaningful** — do not
tell the operator to launch it. (Swift strings of 15 bytes or fewer are small-string-optimised and
invisible to `strings`, which is why the probe is a long one.)

- [ ] **Step 2: Launch and hand over**

```bash
./scripts/run-instrument.sh
```

Tell the operator what changed and how to spot it before handing over the legs: there is a new
**Modulation** icon in the rail (`⌘⌥3`), driven controls carry a small `MOD` badge with an ✕, and
nothing else on the surface has moved.

- [ ] **Step 3: Run the five legs and record verdicts**

Create `docs/reports/live-smoke-instrument-m2-modulation.md`:

```markdown
# Live smoke — ARShader Milestone 2, modulation layer

**Build:** <sha> · **Date:** <date> · **Operator:** <name>

Spec §9.3. No protocol boundary in this slice, so these legs are about musicality, not function.
All five run with no audio subsystem in existence.

## Leg 1 — a 2 ms decay reads as a strobe; a 2 s decay reads as a swell

Bind `deck.a.opacity` to `exp(-since("manual/trigger") / 0.002)` (absolute), then to
`exp(-since("manual/trigger") / 2.0)`. Hit TRIGGER on each.

- Verdict: PASS / FAIL
- What it looked like:

## Leg 2 — grabbing an `offset`-driven fader feels live, not fought

Bind `deck.a.opacity` to `ref("manual/lfo") * 0.3` in **offset** mode. Move the deck A opacity
fader while the LFO runs.

- Verdict: PASS / FAIL
- Notes:

## Leg 3 — grabbing an `absolute`-driven control reads as driven, not broken

Switch the same binding to **absolute**. Try to move the fader. Then use the ✕ beside it.

- Verdict: PASS / FAIL
- Did "it will not move" read as intentional?

## Leg 4 — the frame budget holds with the full route set bound

Load a shader on both decks, add two FX stages, bind as many destinations as the panel offers
(target: the whole catalogue). Watch the FPS / GPU-ms readout.

- FPS before / after:
- Verdict: PASS / FAIL

## Leg 5 — the manual trigger, hit on the beat, is genuinely performable

Play something. Hit TRIGGER (or ⌘⇧T) on the downbeat against a bound decay.

- Verdict: PASS / FAIL
- Is this a control you would actually use? (This is the leg that decides whether the stub source
  stays permanently, as §3.1 claims it will.)

## Open questions this run answers or defers

- §10.1 curve vocabulary — do named helpers (`decay(since, tau, shape)`) beat raw `exp()`?
- §10.2 route creation gesture — is the plain picker tolerable, or is learn-style urgent?
```

- [ ] **Step 4: Commit the signed report**

```bash
git add docs/reports/live-smoke-instrument-m2-modulation.md
git commit -m "docs(mod): on-device gate — five legs, operator-signed"
```

- [ ] **Step 5: Close out**

- Update `docs/reports/modulation-mutation-evidence.md` with the measured budget figures if Task 13
  left them blank.
- Mark the slice **CONFIRMED** only if the operator signed all five legs. Anything unsigned stays
  **STAGED**, and the memory note says so.
- File the deferred reviews that this plan does not run: PM spec review
  (`arshader-mod-layer-pm-spec-review-20260801`) gates execution and should have run BEFORE Task 1;
  CSO (`arshader-public-push-cso-gate-20260801`) gates pushing this public repo.

---

## Self-review record

Run after the plan was written, before it was handed over.

**Spec coverage.** Every numbered section maps to at least one task:

| Spec | Task |
|---|---|
| §2 model, list/get/clear, rename-safe rewriting | 5, 7, 9 |
| §2.1 targeting modes | 7 (engine), 9 (default per destination), 11 (ownership) |
| §2.2 `since()` | 3 (registry), 6 (evaluator), 13 (budget) |
| §3 source contract | 3 |
| §3.1 stub provider | 4, 12 |
| §4 address spaces | 2 |
| §4.1 FX stable IDs | 1 |
| §4.2 bindings survive a vanished input | 7, 8, 10 |
| §4.3 blackout has no address | 2, 11, 12 |
| §5.1 one snapshot per frame | 3, 7, 10 |
| §5.2 app clock, integrated phase | 4, 8, 10 |
| §5.3 cycles read the previous frame | 7 |
| §6.1 driven controls | 11 |
| §6.2 one expression per destination | 9 |
| §7 failure doctrine | 3 (idle), 5 (compile), 7 (NaN, clamp) |
| §8 persistence and the bypass | 8 (sinks), 9 (store) |
| §9.1 mutation-proven gates | every task, collected in 13 |
| §9.2 frame budget | 13 |
| §9.3 on-device gate | 14 |
| §10 open questions | 14 (legs 1 and 3 inform §10.1 and §10.2); **§10.3 is answered by Task 9, not deferred** — one unscoped `UserDefaults` key makes binding scope instrument-global by shape. Revisit against 3b/3c's `Preset` before operators have patches saved; re-scoping later is a migration. (PM spec review, finding 1.) |
| §11 provenance | recorded in Task 6's note — only the motion function NAMES came from prior-art research |

**Gaps found and closed while reviewing:**

1. **§4.1 assumes a chain is rebuilt at relaunch; nothing rebuilds one.** Recorded in the scope
   note above rather than papered over — Task 1 delivers the precondition, and an unresolvable FX
   binding is skipped per §4.2 until chain persistence exists.
2. **The spec's vocabulary has no conditional** although the prior-art system's shipped expressions did.
   Recorded as a Global Constraint so it reads as a boundary, not an omission.
3. **`ShaderUnit` cannot know its own address.** Resolved by having the owner pass the mapping
   closure at attach time (Task 10), which is also what makes an FX stage's inputs addressable.
4. **Only `float` and `long` are modulatable.** The spec does not say which ISF types get
   addresses; inventing a component-wise convention for a colour is a tuning-surface decision, so
   the boundary is stated in Task 10 and pinned by a test.
5. **The mixer's crossfader was not visible to the render thread** — `renderLayers()` carries
   computed weights, not the base position. Task 10 adds `renderCrossfadePosition()`.
6. **A stage at zero mix was invisible to modulation** because `FXChain` filtered it at publish
   time. Task 1 moves the skip to encode time so an `offset` driver can bring a dry stage in.

**Placeholder scan:** clean. Every step carries the code or the exact command it needs; the only
blanks are the measured figures and operator verdicts Tasks 13 and 14 exist to fill in.

**Type consistency:** the names in each task's **Produces** block are the names later tasks use.
Checked: `ModDestination` / `ModFXScope` / `FXParam` (2), `ModOutputDescriptor` / `ModReading` /
`ModSnapshot` / `ModSourceRegistry` (3), `ManualSource` / `ManualSourceRuntime` / `LFOShape` (4),
`ExprNode` / `ExprParser` / `ExprSignature` / `ExpressionError` (5), `ExprContext` /
`ExpressionEvaluator` / `MotionFunctions` (6), `ModBinding` / `CompiledBinding` / `ModBase` /
`ModulationOutcome` / `ModTargetMode` / `ModulationEngine` (7), `ModulationRuntime` (8),
`ModulationModel` / `ModulationStore` / `ModulationSnapshot` (9), `attachModulation` on three
types + `lastFrameLayers` (10), `DrivenState` / `DrivenBadge` (11), `ModulationPanelModel` (12).
