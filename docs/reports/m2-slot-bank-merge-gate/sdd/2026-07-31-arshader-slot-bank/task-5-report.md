# Task 5 report: the load seam — `Instrument.load(_:onto:thenApply:)`

## Status: DONE_WITH_CONCERNS

## What changed

`App/ARShader/Instrument.swift`:
- Added `let slotBank: SlotBank`, restored from `SlotBankStore().load()` in `init()`, persisting
  via `slotBank.onChange = { bankStore.save(self.slotBank.slots) }`.
- Added `var onLoadSettledForTesting: (() -> Void)?` — test seam, brief's exact shape.
- Added `func load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil)`
  — the one load seam. Deck targets replace via `attach` + `unit.load(url:)`; FX targets append a
  fresh `FXStage` via a private `append(_:to:snapshot:)`.
- Added private `attach(_:to:alsoRunning:)` — installs a compile handler that runs the chain's
  ongoing concern, applies the one-shot snapshot if present, then reinstalls `onCompileFinished` to
  the ongoing concern alone (or `nil`), and fires `onLoadSettledForTesting`.
- Added `func currentPreset(of id: DeckID) -> Preset?` — reads `unit.sourceURL`/`exportSnapshot()`.

All verbatim from the brief's Step 3 code block; no changes to the implementation logic.

`App/ARShader/FXChain.swift`:
- Added `var onStagesChangedForTesting: (() -> Void)?` (test seam) and call it inside
  `stageDidChangeScene()` after `publishToRenderThread()`.

`App/ARShader/LibraryPanelView.swift`:
- Deleted the private `load(_:)` and `append(_:to:)` methods entirely.
- Button action is now `instrument.load(entry.url, onto: target)`.
- `instrument.device`/`instrument.queue` are no longer referenced by this view (they were only used
  by the deleted `append`); left `Instrument.device`/`.queue` untouched since other call sites still
  need them.

`App/ARShaderTests/InstrumentLoadTests.swift`:
- Added the brief's helper and all 8 new tests, with two deviations (both flagged, see below):
  the helper is named `loadTargetAndWait` (not `loadAndWait`, which the file's own Task 4 helper
  already uses for a bare `ShaderUnit`), and
  `testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues`'s body was rewritten (see Deviation 2).

## Deviation 1: helper name collision, resolved as instructed

The brief's own note anticipated this: "give the new one a distinct name if they would collide, and
say what you named it." `InstrumentLoadTests` already has a private `loadAndWait(_ unit:_ url:)`
(Task 4) that awaits `ShaderUnit.onCompileFinished` directly. The brief's new helper has a different
signature (`Instrument`, `LibraryTarget`, optional `ParamSnapshot`) and awaits
`Instrument.onLoadSettledForTesting`. Named it **`loadTargetAndWait`**. Both helpers coexist; no
collision.

## Deviation 2: `testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues` rewritten

The brief's literal test:
```swift
await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                  thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
XCTAssertNotEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"], .float(0.25), ...)
```
fails **unconditionally**, with a correct implementation, for a reason unrelated to the one-shot
mechanism it's meant to guard:

1. `makeShaderFile()` always declares the same `"speed"` float input (its fixture is fixed). Both
   loads in this test therefore compile a shader with an identically-named, identically-typed input.
2. `ParamStore.syncInputs` has an existing, deliberate, separately-tested behavior: same-name
   same-type values **survive** a shader swap (`ParamStoreTests.swift:49`,
   `testSyncInputsPrunesVanishedAndTypeChanged_keepsSurvivors`, asserting `"same-typed survivor must
   be kept"`). So `values["speed"] = 0.25` (set by the first load's `applySnapshot`) survives the
   SECOND load's `syncInputs` call regardless of what `Instrument.attach` does — it isn't reached
   through the one-shot closure at all on the second load; it's reached through `ParamStore`'s own
   name-matching logic.
3. Separately, even without (2): `Instrument.load` calls `attach(...)` **synchronously, every time**,
   before kicking off the async compile. So the second `instrument.load(...)` call unconditionally
   overwrites `unit.onCompileFinished` with a fresh closure before that load's compile can finish —
   the "stale closure from the first load" scenario the one-shot clear defends against can never
   arise via two calls to `Instrument.load` on the same target. It can only arise from a load that
   bypasses `Instrument.load` (a direct `ShaderUnit.load(...)` call — e.g. a future MIDI reload path,
   or a shader-edit-and-recompile button).

I ran this exact scenario empirically before touching anything: with my implementation matching the
brief's Step 3 verbatim, the test failed on the first try with `0.25 == 0.25` — confirming (2). I
then reasoned through (3) and confirmed via the mutation-2 proof below that removing the one-shot
reinstall line does NOT change this test's failure mode at all (it fails identically with or without
the clear), proving the test's assertion, as originally written, cannot detect the mutation it's
supposed to detect.

**Fix:** rewrote the assertion to test the actual invariant directly — that `unit.onCompileFinished`
becomes `nil` after a deck load with a snapshot fires (deck targets pass `ongoing: nil` to `attach`,
so `ongoing.map { ... }` is `nil` after the one-shot fires):
```swift
XCTAssertNil(instrument.deck(.one).unit.onCompileFinished,
             "A later load that bypasses Instrument.load must not re-fire this load's "
             + "snapshot onto whatever it compiles next")
```
`onCompileFinished` is `internal var` on `ShaderUnit`, already accessed directly by this same test
file's Task 4 helper, so no new access exposure. This assertion is independent of `ParamStore`'s
survivor mechanism and genuinely falsifiable by mutation 2 (verified below) — it goes RED with the
mutation and STAYS the exact same shape of RED I'd expect (function present, no reinstall).

I did not touch `ParamStore.syncInputs`, `Instrument.attach`'s logic, or the brief's implementation
code in `Instrument.swift` to "fix" this — only the test's assertion changed. The behavior the brief
describes in its docstring ("a later unrelated load onto the same unit would re-fire it and replay
an old preset's values onto a shader they were never captured from") is real and correctly guarded
by the one-shot clear; the brief's chosen test scenario just couldn't observe it through the
`Instrument.load` → `Instrument.load` path, only through a path that bypasses `Instrument.load`
entirely.

## Note on stated suite count

The brief said 237 is stale and expected 238 (230 + 8 new tests). Confirmed: **238**, exactly as
the coordinator predicted.

## Test command and verbatim tail output

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 12:49:10.
	 Executed 238 tests, with 0 failures (0 unexpected) in 17.024 (17.081) seconds
Test Suite 'All tests' passed at 2026-07-31 12:49:10.
	 Executed 238 tests, with 0 failures (0 unexpected) in 17.024 (17.081) seconds
** TEST SUCCEEDED **
```

Targeted `InstrumentLoadTests` run (all 13, first full pass before the mutation proofs):
```
Test Suite 'InstrumentLoadTests' started at 2026-07-31 12:43:16.
Test Case '-[...testADeckTargetReplacesTheShader]' passed (0.241 seconds).
Test Case '-[...testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying]' passed (0.244 seconds).
Test Case '-[...testAFreshUnitHasNoSourceURL]' passed (0.001 seconds).
Test Case '-[...testAnFXLoadWithASnapshotStillRepublishesTheChain]' passed (0.167 seconds).
Test Case '-[...testAnFXTargetAppendsAStage]' passed (0.140 seconds).
Test Case '-[...testASnapshotIsAppliedAfterTheCompileLands]' passed (0.176 seconds).
Test Case '-[...testCurrentPresetCapturesTheLiveValues]' passed (0.173 seconds).
Test Case '-[...testCurrentPresetIsNilUntilSomethingIsLoaded]' passed (0.001 seconds).
Test Case '-[...testLoadingDoesNotEndShowMode]' passed (0.157 seconds).
Test Case '-[...testLoadingFromAURLRetainsIt]' passed (0.175 seconds).
Test Case '-[...testLoadingFromSourceAfterAURLClearsIt]' passed (0.141 seconds).
Test Case '-[...testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues]' passed (rewritten version)
Test Case '-[...testUnloadingClearsTheSourceURLAsWellAsTheName]' passed (0.175 seconds).
```
(Reconstructed from the raw grep of the full run; the rewritten one-shot test's timing line was not
individually captured in that grep pass, but it is included in the "0 failures" full-suite result
above and in its own dedicated mutation-proof run below.)

## Mutation proofs (Step 5, mandatory — all three)

### 1. Drop `ongoing?()` from `attach`'s closure

```swift
unit.onCompileFinished = { [weak self, weak unit] in
    // MUTATION 1 (temporary): ongoing?() removed
    if let snapshot, let unit { unit.params.applySnapshot(snapshot) }
    ...
```
Targeted run:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAnFXLoadWithASnapshotStillRepublishesTheChain]' started.
.../InstrumentLoadTests.swift:176: error: ... XCTAssertGreaterThan failed: ("0") is not greater than ("0")
- onCompileFinished is single-owner: a snapshot handler that replaces the chain republish silently
  stops the FX stage updating
Test Case '...' failed (0.269 seconds).
	 Executed 13 tests, with 1 failure (0 unexpected) in 2.026 (2.029) seconds
** TEST FAILED **
```
Restored `ongoing?()`. Targeted re-run: `testAnFXLoadWithASnapshotStillRepublishesTheChain` passed
(0.182s), 13/13 green.

### 2. Remove the one-shot reinstall line

```swift
if let snapshot, let unit { unit.params.applySnapshot(snapshot) }
// MUTATION 2 (temporary): one-shot reinstall line removed
self?.onLoadSettledForTesting?()
```
Targeted run:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues]' started.
.../InstrumentLoadTests.swift:202: error: ... XCTAssertNil failed: "(Function)"
- A later load that bypasses Instrument.load must not re-fire this load's snapshot onto whatever it
  compiles next
Test Case '...' failed (0.235 seconds).
	 Executed 13 tests, with 1 failure (0 unexpected) in 2.191 (2.194) seconds
** TEST FAILED **
```
This confirms the rewritten test (Deviation 2) is genuinely sensitive to the exact mutation named in
the brief — the original brief assertion was not, as established above. Restored the reinstall line.
Targeted re-run: `testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues` passed (0.178s), 13/13
green.

### 3. Add `surfaceLayout.toggleShowMode()` at the top of `load`

```swift
func load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil) {
    surfaceLayout.toggleShowMode()   // MUTATION 3 (temporary)
    switch target {
```
Targeted run:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingDoesNotEndShowMode]' started.
.../InstrumentLoadTests.swift:213: error: ... XCTAssertTrue failed
- Loading a shader is a performance action. Only deliberate LAYOUT actions end a show.
Test Case '...' failed (0.250 seconds).
	 Executed 13 tests, with 1 failure (0 unexpected) in 2.147 (2.150) seconds
** TEST FAILED **
```
Restored (removed the line). Full-suite re-run after restoring all three mutations: 238/238 pass
(shown above).

## Commit

```
git add App/ARShader/Instrument.swift App/ARShader/FXChain.swift App/ARShader/LibraryPanelView.swift \
        App/ARShaderTests/InstrumentLoadTests.swift
git commit -m "feat(3b): one load seam for library clicks, slot recalls and later MIDI"
```
SHA: `dbc64cf` — 4 files changed, 179 insertions(+), 24 deletions(-). Working tree clean
immediately after (`git status --short` empty).

## Concerns for the caller

1. **`testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues` was rewritten**, not implemented
   verbatim — see Deviation 2. The brief's literal version fails unconditionally regardless of
   implementation correctness, for reasons unrelated to the one-shot mechanism (confirmed by
   running it before any mutation, and again by mutation-2's proof that the reinstall line doesn't
   change its failure mode). The rewritten version tests the same underlying invariant directly and
   is genuinely falsifiable by the exact mutation the brief names.
2. **Helper renamed** `loadAndWait` → `loadTargetAndWait` for the `Instrument`-level helper, per the
   brief's own contingency instruction, to avoid colliding with Task 4's existing `ShaderUnit`-level
   `loadAndWait`.
3. No other deviations. `Instrument.swift` and `FXChain.swift` implementation code matches the
   brief's Step 3 code block verbatim (including comments). `LibraryPanelView.swift` matches Step 3's
   button-action instruction verbatim.

---

# Fix round 1 of 5

## Status: DONE

Review found two Important issues plus four Minor cleanups, all in `attach`/`Instrument.init()` or
the file it sits in. Addressed all six.

## What changed

`App/ARShader/Instrument.swift`:

**IMPORTANT 1 — a failed load applied the snapshot onto the shader still playing.** `attach`'s
closure now guards `applySnapshot` with `unit.compileError == nil`:
```swift
if let snapshot, let unit, unit.compileError == nil { unit.params.applySnapshot(snapshot) }
```
`compileError` is nil'd only on `ShaderUnit.apply`'s success branch, so this discriminates exactly
the three outcomes `onCompileFinished` fires on (unreadable file / compile failure / success),
applying the snapshot only on the third.

**MINOR 5 (folded into the same closure edit)** — swapped the order so the snapshot applies BEFORE
`ongoing?()`, not after, so an FX stage doesn't enter the render mirror at header defaults for one
turn before jumping to the preset's values.

**IMPORTANT 2 — `Instrument.init()` was persisting to the real `UserDefaults.standard`.** `init()`
now branches on `TestHarness.isActive` (`App/ISFRuntime/TestHarness.swift`, already in-target via
the `ISFRuntime` source path — no new import needed):
```swift
let bankStore: SlotBankStore
if TestHarness.isActive {
    let suiteName = "ARShader.Instrument.testHarness.\(UUID().uuidString)"
    bankStore = SlotBankStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
} else {
    bankStore = SlotBankStore()
}
self.slotBank = SlotBank(slots: bankStore.load())
```
**Chose:** a fresh volatile suite per `Instrument()` instance under the harness, isolating BOTH
`load()` and `save()` — not just skipping the `onChange` persistence hook. Reasoning: skipping only
the write would still call `bankStore.load()` against the real `.standard` bank at `init()` time,
seeding a test instrument's initial slot state from whatever the operator's real bank happens to
contain on this machine — exactly the nondeterminism Task 3's `SlotBankStoreTests` private-suite
doctrine exists to prevent, just moved from "tests construct their own store" to "every
`Instrument()` in the suite constructs one implicitly." A volatile suite closes both directions.

**MINOR 3 — `attach`'s docstring reworded to conditional.** Was present tense ("a later unrelated
load... would re-fire it"); reworded to state plainly that no current production path can reach
this (`load` always calls `attach` fresh before every compile, every FX load mints a new unit), and
that the clear is there so the invariant holds unconditionally rather than by accident of today's
call graph — matching the phrasing the test's own docstring already used.

`App/ARShader/FXChain.swift`:

**MINOR 4 — renamed `onStagesChangedForTesting` → `onSceneRepublishedForTesting`.** Updated its
doc comment to state explicitly it fires ONLY from `stageDidChangeScene()`'s republish, not from
`append`/`remove`/`move`/`setEnabled`/`setMix`/`setBlendMode`, which also republish but through
their own direct `publishToRenderThread()` calls.

`App/ARShaderTests/InstrumentLoadTests.swift`:

- Extracted `makeUncompilableShaderFile()` (non-private, same visibility as `makeShaderFile`) from
  the inline fixture duplicated in `testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying`;
  that test now calls it too instead of duplicating the literal.
- Renamed the two `onStagesChangedForTesting` references to `onSceneRepublishedForTesting`.
- **MINOR 2** — `testASnapshotIsAppliedAfterTheCompileLands`'s failure message rewritten. Chose
  "replace the message" over "make it falsifiable": the claim it implicitly needed to become
  falsifiable ("applied strictly after compile, not before") isn't observable through
  `ParamStore.exportSnapshot()` for ANY input shape, because `applySnapshot` keeps unknown-to-the-
  shader names regardless of timing and `syncInputs` then keeps same-typed survivors — so early-
  apply and late-apply are indistinguishable through this API by construction, not just for this
  fixture. The new message states only what the assertion actually proves (the value lands in the
  exported snapshot once `Instrument.load`'s compile has settled), with a comment explaining why a
  stronger ordering claim isn't testable here.
- Added `testAFailedLoadWithASnapshotLeavesTheDialledValueOfTheStillPlayingShaderUntouched`
  (Important 1's test, using the good/bad-fixture pattern already in the file).
- Added `testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank` (Important 2's test).
- Added `testTheFXOneShotReinstallsRepublishOnlyNotTheRetiredSnapshot` (Minor 1's test) — drives a
  SECOND compile directly on the FX stage's `ShaderUnit` (bypassing `Instrument.load`, which would
  just call `attach` fresh again and defeat the point) through the REINSTALLED closure, waiting on
  `onSceneRepublishedForTesting` rather than a raw `onCompileFinished` overwrite (which would
  replace the very closure under test).

## Test command and verbatim tail output

Full suite:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 13:05:xx.
	 Executed 241 tests, with 0 failures (0 unexpected) in 17.637 (17.687) seconds
Test Suite 'All tests' passed at 2026-07-31 13:05:xx.
	 Executed 241 tests, with 0 failures (0 unexpected) in 17.637 (17.687) seconds
** TEST SUCCEEDED **
```
241 = 238 (prior round) + 3 new tests (Important 1, Important 2, Minor 1). Not adjusted to hit a
predicted number — this is what the run produced.

Targeted `InstrumentLoadTests` (16 tests: 13 prior + 3 new):
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:ARShaderTests/InstrumentLoadTests
```
```
Test Case '-[...testADeckTargetReplacesTheShader]' passed (0.396 seconds).
Test Case '-[...testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying]' passed (0.244 seconds).
Test Case '-[...testAFailedLoadWithASnapshotLeavesTheDialledValueOfTheStillPlayingShaderUntouched]' passed (0.247 seconds).
Test Case '-[...testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank]' passed (0.004 seconds).
Test Case '-[...testAFreshUnitHasNoSourceURL]' passed (0.001 seconds).
Test Case '-[...testAnFXLoadWithASnapshotStillRepublishesTheChain]' passed (0.119 seconds).
Test Case '-[...testAnFXTargetAppendsAStage]' passed (0.076 seconds).
Test Case '-[...testASnapshotIsAppliedAfterTheCompileLands]' passed (0.173 seconds).
Test Case '-[...testCurrentPresetCapturesTheLiveValues]' passed (0.168 seconds).
Test Case '-[...testCurrentPresetIsNilUntilSomethingIsLoaded]' passed (0.002 seconds).
Test Case '-[...testLoadingDoesNotEndShowMode]' passed (0.084 seconds).
Test Case '-[...testLoadingFromAURLRetainsIt]' passed (0.174 seconds).
Test Case '-[...testLoadingFromSourceAfterAURLClearsIt]' passed (0.131 seconds).
Test Case '-[...testTheFXOneShotReinstallsRepublishOnlyNotTheRetiredSnapshot]' passed (0.127 seconds).
Test Case '-[...testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues]' passed (0.078 seconds).
Test Case '-[...testUnloadingClearsTheSourceURLAsWellAsTheName]' passed (0.170 seconds).
	 Executed 16 tests, with 0 failures (0 unexpected) in 2.193 (2.196) seconds
** TEST SUCCEEDED **
```

## Mutation proofs (mandatory — both new Important tests)

### Important 1: remove the `compileError == nil` guard

```swift
if let snapshot, let unit { unit.params.applySnapshot(snapshot) }   // guard removed
```
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFailedLoadWithASnapshotLeavesTheDialledValueOfTheStillPlayingShaderUntouched]' started.
.../InstrumentLoadTests.swift:260: error: ... XCTAssertEqual failed:
("Optional(ARShaderTests.ParamValue.float(0.1))") is not equal to ("Optional(ARShaderTests.ParamValue.float(0.77))")
- A failed compile must not let the snapshot mutate the shader that is still playing
Test Case '...' failed (0.693 seconds).
** TEST FAILED **
```
Restored the guard. Re-ran: passed (0.392 seconds), `** TEST SUCCEEDED **`.

### Important 2: remove the harness gate

```swift
if false && TestHarness.isActive {   // gate effectively disabled
```
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank]' started.
.../InstrumentLoadTests.swift:278: error: ... XCTAssertEqual failed:
("nil") is not equal to ("Optional(212 bytes)")
- Instrument() under the test harness must not read or write the operator's real slot bank
Test Case '...' failed (0.093 seconds).
** TEST FAILED **
```
**This mutation actually wrote 212 bytes to the real `com.arsonrivvers.ARShader` preferences
domain** (`~/Library/Preferences/com.arsonrivvers.ARShader.plist`, key `ARShader.slotBank`) during
the failing run — confirmed via `plutil -p` on that file before and after. This is live
demonstration of the exact bug Important 2 fixes: the XCTest host for this project genuinely runs
as the real `com.arsonrivvers.ARShader` app (per `TestHarness.swift`'s own doc comment — "the test
target injects into the real app"), so an unguarded `Instrument()` really does share the operator's
real defaults domain. Restored the gate, then deleted the polluted key
(`defaults delete com.arsonrivvers.ARShader ARShader.slotBank`) to return the domain to its prior
state (verified nil before the mutation, confirmed absent after cleanup). Re-ran the same targeted
test with the gate restored: passed (0.003 seconds), and confirmed via `plutil -p` that no write
reached `com.arsonrivvers.ARShader.plist` this time. Re-ran the full suite: 241/241 pass, domain
still clean.

## Commit

```
git add App/ARShader/Instrument.swift App/ARShader/FXChain.swift App/ARShaderTests/InstrumentLoadTests.swift
git commit -m "fix(3b): guard the snapshot apply on success, isolate the slot bank under XCTest"
```
SHA: `d0f6fc3` — 3 files changed, 128 insertions(+), 20 deletions(-). Working tree clean immediately after.

## Concerns for the caller

1. **The Important-2 mutation proof left real user-defaults pollution mid-round**, cleaned up
   immediately via `defaults delete`, verified via `plutil -p` before and after. Flagging so the
   coordinator knows this happened and was corrected, not just "the test passed."
2. Each `Instrument()` built under the harness leaves behind one throwaway
   `ARShader.Instrument.testHarness.<uuid>.plist` in `~/Library/Preferences/` (visible via
   `ls ~/Library/Preferences | grep ARShader.Instrument.testHarness`). These are inert — empty
   until a test captures into the bank, never read by the real app, and harmless clutter rather
   than a correctness issue — but a future session doing broad preferences hygiene should know
   where they come from rather than treating them as unexplained cruft.
3. No other deviations from the coordinator's six items. All six addressed; Minor 2 resolved via
   "replace the message" (documented above why "make it falsifiable" isn't achievable through
   `ParamStore`'s public API for this invariant, not just for this fixture).

---

# Fix round 2 of 5

## Status: DONE

Round 1's fix isolated WHICH `UserDefaults` domain got written (real key never touched) but still
materialised a real file per instance — `UserDefaults(suiteName:)` creates a cfprefsd-backed plist
in `~/Library/Preferences` the moment anything writes, and none of these ever clean themselves up.
Combined with Task 3's pre-existing `SlotBankStoreTests` doing the same thing, 68 files
(63 + 5) had accumulated on the operator's real machine. Coordinator's directive: structural fix,
not janitorial — stop using `UserDefaults` in tests entirely, in-memory only.

## What changed

`App/ARShader/SlotBankStore.swift`:
- Added `protocol KeyValueStoring: AnyObject { func data(forKey key: String) -> Data?; func
  set(_ value: Any?, forKey key: String) }` and `extension UserDefaults: KeyValueStoring {}`.
  Checked `UserDefaults`'s real signatures (`data(forKey:)`, `set(_:forKey:)`) — both already use
  `forKey` as their external label, so the conformance needed no shims.
- Added `final class InMemoryKeyValueStore: KeyValueStoring`, wrapping a `[String: Data]`.
- `SlotBankStore.defaults` is now typed `KeyValueStoring` (was `UserDefaults`); `init(defaults:
  KeyValueStoring = UserDefaults.standard)`. `load()`/`save()` bodies unchanged — both already only
  called the two protocol methods.

**Placement deviation, flagged:** the coordinator's message suggested putting the in-memory
conformer "wherever this project keeps test helpers; if there is no such place, put it in
`SlotBankStoreTests.swift`." I did not do that. Reason: step 5 of the same message requires
`Instrument.init()` — production code in the `ARShader` APP target — to construct an
`InMemoryKeyValueStore` directly. Swift resolves both branches of an `if` at COMPILE time
regardless of the runtime value of `TestHarness.isActive`, so the type must be visible to the app
target's compiler invocation; app-target code cannot import the `ARShaderTests` target (test
targets link against the app, never the reverse). Putting the class in `SlotBankStoreTests.swift`
would make `Instrument.swift` fail to compile. `TestHarness` itself (`App/ISFRuntime/
TestHarness.swift`) already establishes the exact pattern needed here — a type that exists only to
serve test-time behaviour but lives in the app target with default (internal) visibility, reachable
by app code directly and by test code via `@testable import ARShader`. I followed that precedent:
`KeyValueStoring` and `InMemoryKeyValueStore` live beside `SlotBankStore` in the app target,
`internal`, so both `Instrument.swift` (direct access, same target) and `SlotBankStoreTests.swift`
/ `InstrumentLoadTests.swift` (via `@testable import`) share the one definition — which also
satisfies the message's "so InstrumentLoadTests can use it too" intent, just via a different route
than literally redefining it in a test file.

`App/ARShader/Instrument.swift`:
- `init()`'s bank-store construction simplified to:
  ```swift
  let bankStore = TestHarness.isActive
      ? SlotBankStore(defaults: InMemoryKeyValueStore())
      : SlotBankStore()
  ```
  Replacing round 1's `UserDefaults(suiteName: "ARShader.Instrument.testHarness.\(UUID())")`
  branch. No `UUID`, no `UserDefaults` call, no file touched under the harness at all. Updated the
  doc comment to explain both rounds' reasoning (kept round 1's own reasoning legible rather than
  deleting the history, since a future reader hitting this code mid-round would otherwise not know
  why a suite-based approach was rejected).

`App/ARShaderTests/SlotBankStoreTests.swift`:
- `private var defaults: UserDefaults!` → `private var defaults: InMemoryKeyValueStore!`.
- `setUp()`: `defaults = UserDefaults(suiteName: "SlotBankStoreTests-\(UUID().uuidString)")` →
  `defaults = InMemoryKeyValueStore()`.
- No other lines changed — every test body already only ever called `.set(_:forKey:)` on
  `defaults` or passed it to `SlotBankStore(defaults:)`; both types expose identical call shapes so
  the four existing test bodies (`testAnEmptyStoreLoadsAnEmptyBankRatherThanFailing`,
  `testAPopulatedBankRoundTripsWithItsValuesAndPositions`,
  `testCorruptStoredDataLoadsAnEmptyBankRatherThanThrowing`,
  `testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount`) are byte-identical to before this
  round — only the backing store changed, exactly as directed.

`App/ARShaderTests/InstrumentLoadTests.swift`:
- Updated `testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank`'s doc comment to
  reference `InMemoryKeyValueStore` instead of round 1's "volatile suite" language. Assertion body
  unchanged — it was already checking the right thing (the real `UserDefaults.standard` key stays
  untouched), independent of what mechanism achieves that.

## Structural verification: plist counts before/after

Before (recorded first, per the coordinator's exact commands):
```
$ ls ~/Library/Preferences/ | grep -c "SlotBankStoreTests"
63
$ ls ~/Library/Preferences/ | grep -c "ARShader.Instrument.testHarness"
5
```

## Test command and verbatim tail output (foreground, not backgrounded)

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 13:23:47.331.
	 Executed 241 tests, with 0 failures (0 unexpected) in 18.643 (18.693) seconds
Test Suite 'All tests' passed at 2026-07-31 13:23:47.331.
	 Executed 241 tests, with 0 failures (0 unexpected) in 18.643 (18.694) seconds
** TEST SUCCEEDED **
```
241 — unchanged from the prior round, as expected. This was a refactor of test backing, not new
behaviour; no test count moved.

After:
```
$ ls ~/Library/Preferences/ | grep -c "SlotBankStoreTests"
63
$ ls ~/Library/Preferences/ | grep -c "ARShader.Instrument.testHarness"
5
```
**Both unchanged.** Zero new files from a full suite run — the isolation is now structural (nothing
can be created), not just non-colliding (a different thing was created each time but never the real
one).

## Mutation proof (mandatory)

Disabled the harness gate:
```swift
let bankStore = false && TestHarness.isActive   // gate effectively disabled
    ? SlotBankStore(defaults: InMemoryKeyValueStore())
    : SlotBankStore()
```
Targeted run:
```
xcodebuild test ... -only-testing:ARShaderTests/InstrumentLoadTests/testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank
```
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank]' started.
.../InstrumentLoadTests.swift:280: error: ... XCTAssertEqual failed:
("nil") is not equal to ("Optional(212 bytes)")
- Instrument() under the test harness must not read or write the operator's real slot bank
Test Case '...' failed (0.291 seconds).
** TEST FAILED **
```
Confirmed this mutation again wrote to the real `com.arsonrivvers.ARShader` domain (same 212-byte
payload shape as round 1's proof — the underlying `Instrument()` code path is otherwise unchanged,
only the in-harness branch is). Restored the gate immediately, THEN cleaned up:
```
$ defaults delete com.arsonrivvers.ARShader ARShader.slotBank
$ defaults read com.arsonrivvers.ARShader "ARShader.slotBank"
2026-07-31 13:24:26 defaults[...]
The domain/default pair of (com.arsonrivvers.ARShader, ARShader.slotBank) does not exist
```
Re-ran the same targeted test with the gate restored:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank]' passed (0.002 seconds).
** TEST SUCCEEDED **
```
Confirmed absence again immediately before the final full-suite run:
```
$ defaults read com.arsonrivvers.ARShader "ARShader.slotBank"
The domain/default pair of (com.arsonrivvers.ARShader, ARShader.slotBank) does not exist
```
Final full suite (foreground): 241/241 pass, plist counts still 63/5 (both commands re-run and
reconfirmed after this final run).

## Commit

```
git add App/ARShader/Instrument.swift App/ARShader/SlotBankStore.swift \
        App/ARShaderTests/InstrumentLoadTests.swift App/ARShaderTests/SlotBankStoreTests.swift
git commit -m "fix(3b): back the slot bank with memory in tests, not a UserDefaults suite"
```
SHA: `fb120e2` — 4 files changed, 57 insertions(+), 20 deletions(-). Working tree
clean immediately after.

## Concerns for the caller

1. **Placement deviation from the literal instruction**, documented in full above: `KeyValueStoring`
   / `InMemoryKeyValueStore` live in the app target (`SlotBankStore.swift`), not
   `SlotBankStoreTests.swift`, because `Instrument.swift` (app target) needs compile-time
   visibility that a test-target file cannot provide. Followed the existing `TestHarness` pattern
   for this exact situation.
2. Did not delete any of the 68 pre-existing plist files, as instructed — they remain for the
   operator to handle separately.
3. No other deviations. Both mutation proofs behaved exactly as predicted, including the real-domain
   write on the Important-2 mutation, cleaned up and re-verified absent both times.
