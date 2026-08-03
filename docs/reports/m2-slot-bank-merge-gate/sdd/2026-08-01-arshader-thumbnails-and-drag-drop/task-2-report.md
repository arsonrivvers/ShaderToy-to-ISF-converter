# Task 2 report: the preview/program split

## What was implemented

Exactly the brief's Step 1–11, with two brief-inaccuracies found and corrected (documented below),
plus one adjacent stale-doc-comment fix found in self-review.

1. **`InstrumentRenderer.isProgramLive: Bool`** — new lock-guarded property, same shape as
   `previewScale` (no-op guard, reallocates master pair on change), backed by `private var
   programLive = false`.
2. **The one behavioural change** in `renderFrame()`:
   `let liveRes = programLive ? outRes : renderScale.applied(to: outRes)` — deck rasterisation, cue
   size, and master FX all derive from `liveRes`, exactly as the brief describes.
3. **The matching change** in `reallocateMastersLocked()`:
   `let live = programLive ? masterResolution : renderScale.applied(to: masterResolution)` — this
   governs the master pair's own texture *allocation* size, which is a **separate expression** from
   #2 (see the mutation-proof section — this matters for what actually failed under each mutation).
4. **`OutputWindowController.setDestination(_:)`** now sets
   `instrument.renderer.isProgramLive = destination != .off` before calling `applyDestination()`.
   Verified `toggleFullscreen()` routes through `setDestination` in both branches (open and close),
   and verified `destination` (the `@Published private(set)` property) is assigned nowhere else in
   the file — no second path needed the same line. No defect found here.
5. **`OutputSharpness.isProjectingUpscaled`** now always returns `false`, kept (not deleted) with a
   doc comment stating it is a deliberate assertion. Its stale caller-facing doc comment (which
   described the old MANUAL-scale-warns-on-open-projector behaviour as current) was also updated to
   describe it as retired history rather than present behaviour.
6. **`InstrumentView.projectingUpscaled`** and the warning UI it drove were removed: the
   `projectingUpscaled` computed property, the `warning: String?` parameter on `scaleField(...)` and
   its callers, and the `if let warning { Text(warning)... }` block inside `scaleField`. The PREVIEW
   SCALE help text (which referenced "the warning") was updated to state the new rule directly
   instead of pointing at now-deleted UI.
7. **`testProjectingAnUpscaleIsUnreachable`** added to `OutputDestinationTests.swift`, iterating every
   `OutputDestination` × every `RenderScale.presets` value.
8. **`testProjectingBelowFullScaleIsFlagged`** (pre-existing) removed — see "brief inaccuracies"
   below; it asserted the exact TRUE case Step 8 retires and would otherwise directly contradict
   `testProjectingAnUpscaleIsUnreachable`.

## TDD evidence

**RED** — `xcodebuild test ... -only-testing:ARShaderTests/FrameGraphTests` (full command in Global
Constraints) after adding the four Step-1 tests, before touching `InstrumentRenderer.swift`:

```
/…/FrameGraphTests.swift:426: error: value of type 'InstrumentRenderer' has no member 'isProgramLive'
/…/FrameGraphTests.swift:437: error: value of type 'InstrumentRenderer' has no member 'isProgramLive'
/…/FrameGraphTests.swift:452: error: value of type 'InstrumentRenderer' has no member 'isProgramLive'
/…/FrameGraphTests.swift:465: error: value of type 'InstrumentRenderer' has no member 'isProgramLive'
/…/FrameGraphTests.swift:469: error: value of type 'InstrumentRenderer' has no member 'isProgramLive'
** TEST FAILED ** (build failure, testing cancelled)
```
Exactly the expected first failure — the property doesn't exist yet.

**GREEN** — after Steps 3–4 (property + the two conditional edits):

```
Test Suite 'FrameGraphTests' passed … Executed 35 tests, with 0 failures (0 unexpected)
Test Suite 'InstrumentRendererTests' passed … Executed 3 tests, with 0 failures (0 unexpected)
```
All four new tests pass, and all seven pre-existing render-scale tests pass **unchanged**.

## Explicit confirmation: all seven pre-existing render-scale tests pass

Ran individually via `-only-testing:` and again in the full 272-test suite. All seven pass, named
individually:

1. `testRenderScaleResizesTheMaster` — PASS
2. `testMasterIsFixedAt1920x1080` — PASS
3. `testRenderScaleAppliesToALiveDeckNotJustACuedOne` — PASS
4. `testALiveAndACuedDeckRasteriseAtDifferentScalesInTheSameFrame` — PASS
5. `testCueScaleIsAFractionOfTheLiveRenderNotOfTheOutput` — PASS
6. `testTheInstrumentStillRendersCorrectlyAtAReducedRenderScale` — PASS
7. `testSettingTheSameRenderScaleIsANoOp` — PASS

No conditional went the wrong way round; no "fix by editing assertions" was needed.

## Step 6: precondition lines

Added `renderer.isProgramLive = false // output closed: PREVIEW SCALE governs the live chain`
immediately before `renderFrame()` in all six of tests #1–6 above (not #7,
`testSettingTheSameRenderScaleIsANoOp`, per the brief). This changed no behaviour — verified by the
full suite staying at 0 failures before and after.

## Files changed

- `App/ARShader/InstrumentRenderer.swift` — `isProgramLive` property, `programLive` backing field,
  the `renderFrame()` conditional, the `reallocateMastersLocked()` conditional, and (self-review fix)
  the stale `previewScale` doc comment.
- `App/ARShader/OutputWindowController.swift` — `setDestination` sets `isProgramLive`.
- `App/ARShader/OutputDestination.swift` — `OutputSharpness.isProjectingUpscaled` retired to always
  `false`; its outer doc comment updated to describe the retired behaviour as history.
- `App/ARShader/InstrumentView.swift` — `projectingUpscaled` and the warning UI removed; `scaleField`
  no longer takes a `warning` parameter; PREVIEW SCALE help text updated.
- `App/ARShaderTests/FrameGraphTests.swift` — four new tests, six precondition lines.
- `App/ARShaderTests/InstrumentRendererTests.swift` — one precondition line.
- `App/ARShaderTests/OutputDestinationTests.swift` — `testProjectingAnUpscaleIsUnreachable` added
  (type-corrected, see below); `testProjectingBelowFullScaleIsFlagged` removed.

## Step 10: both mutation-proof results

Both mutations were run, observed, and reverted. **Both produced real test failures**, satisfying the
brief's hard requirement. However, the *specific* tests the brief named as failing were wrong for
both mutations — I verified this empirically rather than assuming the brief's prediction, and I'm
reporting it rather than silently rewriting the brief's claim to match. The root cause: the brief's
own Step 4 code introduces the conditional as **two separate literal expressions** — one in
`renderFrame()` (governs deck/FX render *size*) and one in `reallocateMastersLocked()` (governs the
master pair's own texture *allocation* size). They're driven by the same `programLive`/`renderScale`
state and can't drift in the sense of disagreeing about policy, but a mutation to only one of the two
lines does not affect tests that depend on the other line.

**Mutation 1** — `renderFrame()`: `let liveRes = renderScale.applied(to: outRes)` (pin removed).
Command: `xcodebuild test … -only-testing:ARShaderTests/FrameGraphTests`.

Brief predicted: `testWithOutputLiveALiveDeckIgnoresPreviewScale` and
`testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale` fail.

Actually observed (2 tests failed, matching the brief's failure *count* but not both names):
```
FrameGraphTests.swift:433: testWithOutputLiveALiveDeckIgnoresPreviewScale — ("480") is not equal to ("1920")
FrameGraphTests.swift:472: testClosingTheOutputRestoresPreviewScale — ("480") is not equal to ("1920")
Executed 35 tests, with 2 failures (0 unexpected)
```
`testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale` **passed** under this mutation — it asserts
`rawMasterTexture()` pixel dimensions, which are set at allocation time by
`reallocateMastersLocked()`, untouched by this mutation. `testClosingTheOutputRestoresPreviewScale`
failed instead, because it also asserts the DECK's raster size, which the mutated line does control.

**Mutation 2** — `renderFrame()`: `let liveRes = outRes` (pinned unconditionally).
Command: same.

Brief predicted: `testClosingTheOutputRestoresPreviewScale` and `testRenderScaleResizesTheMaster` fail.

Actually observed (3 distinct tests failed, 5 assertion failures total):
```
FrameGraphTests.swift:476: testClosingTheOutputRestoresPreviewScale — ("1920") is not equal to ("480")
FrameGraphTests.swift:403/404: testCueScaleIsAFractionOfTheLiveRenderNotOfTheOutput — 2 assertions
FrameGraphTests.swift:341/343: testRenderScaleAppliesToALiveDeckNotJustACuedOne — 2 assertions
Executed 35 tests, with 5 failures (0 unexpected)
```
`testRenderScaleResizesTheMaster` **passed** under this mutation, for the same reason as above (it's
gated by `reallocateMastersLocked()`, not `renderFrame()`'s line).

**Additional verification (beyond the brief's Step 10, done to confirm the above diagnosis rather than
just assert it):** mutated `reallocateMastersLocked()` instead —
`let live = renderScale.applied(to: masterResolution)` (pin removed there) — and reverted immediately
after observing:
```
FrameGraphTests.swift:445/446: testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale — 2 assertions
Executed 35 tests, with 2 failures (0 unexpected); InstrumentRendererTests: 0 failures
```
This confirms `testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale` and
`testRenderScaleResizesTheMaster` are gated by `reallocateMastersLocked()`'s copy of the conditional,
not `renderFrame()`'s — both expressions are independently covered by the new/existing test suite,
just not by the exact mutations Step 10 named.

All three mutations were reverted; the file matches the intended implementation (verified via
`git diff HEAD~2` showing only the intended net changes, and the final full-suite run below).

## Second brief inaccuracy: `testProjectingAnUpscaleIsUnreachable`'s literal code doesn't compile

The brief's Step 9 code was:
```swift
for percent in RenderScale.presets {
    XCTAssertFalse(OutputSharpness.isProjectingUpscaled(destination: destination,
                                                         scale: RenderScale(percent: percent)), …)
}
```
`RenderScale.presets` is `[RenderScale]` (`App/ISFRuntime/RenderScale.swift:42`), not `[Int]`, so
`RenderScale(percent: percent)` doesn't type-check (`percent: Int` expected, `RenderScale` given).
Fixed by iterating `RenderScale.presets` directly and passing each preset straight through:
```swift
for scale in RenderScale.presets {
    XCTAssertFalse(OutputSharpness.isProjectingUpscaled(destination: destination, scale: scale),
                   "\(destination) at \(scale.percent)% must not be an upscale")
}
```
Confirmed this is what the brief meant (not a different intended API): `RenderScale.presets` is the
only preset list in the codebase and its whole purpose per its own doc comment is "offered in the
presets menu," which is exactly what this test wants to sweep.

## Third issue found in self-review: conflicting pre-existing test

Not mentioned anywhere in the brief: after Step 8 makes `isProjectingUpscaled` unconditionally
`false`, the pre-existing test `testProjectingBelowFullScaleIsFlagged`
(`OutputDestinationTests.swift`, asserting `XCTAssertTrue(...)` for `.screen(id: "2")` at 25% and
`.floating` at 99%) becomes a guaranteed failure — it directly contradicts
`testProjectingAnUpscaleIsUnreachable`, which asserts `XCTAssertFalse` for the conceptually identical
case (`.floating`/`.screen` at low percentages). I removed it rather than flip its assertions, since
its entire scenario (a live, non-.off destination reading `true`) is now structurally impossible per
Step 8's own doc comment ("Kept, and kept false, deliberately"), and a flipped version would be a
pure duplicate of `testProjectingAtFullScaleIsNotFlagged` / `testProjectingAnUpscaleIsUnreachable`.

## Self-review findings

- **Fixed**: `previewScale`'s doc comment in `InstrumentRenderer.swift` (lines ~247–250, pre-edit)
  claimed "while the projector is open this scales the projected image too" and pointed at
  `OutputSharpness.isProjectingUpscaled` for "a visible warning for exactly that case." Both claims
  are now false — this is precisely the behaviour this task retires. Rewrote it to state the new
  rule and point at `isProgramLive`. Caught by re-reading the property this task's central change
  lives beside, not flagged by any test (it's a doc comment).
- **Checked and clean**: no other file references `projectingUpscaled` or the removed `warning`
  parameter (`grep -rn` returned nothing). No stray absolute paths introduced. No `git add -A` used —
  every commit staged explicit paths only.
- **Test-honesty check**: re-ran the full 272-test suite after the final doc-comment fix (not just
  after the feature commit) to make sure the last edit didn't regress anything — 0 failures both
  times.
- **Considered and declined**: leaving the `renderFrame()` comment's "there is no second rule that
  can drift out of sync" as-is (brief's exact text) even though mutation testing shows there are
  literally two separate expressions. Judged defensible: both expressions encode the same *policy*
  (driven by the same `programLive` state), so "rule" reads as singular at the concept level even
  though the code has two textual copies. Documented the physical duplication in this report instead
  of editing brief-specified prose.

## Concerns

- The two copies of the `programLive ? A : B` conditional (`renderFrame()` and
  `reallocateMastersLocked()`) are a small future foot-gun: a change to one without the other would
  compile fine and only show up as a failure in whichever tests happen to touch the untouched path
  (as this task's own mutation-proof accidentally demonstrated). Not fixing it — the brief explicitly
  specifies duplicating it this way and doing anything else (extracting a shared helper) would be
  scope creep beyond Task 2 — but flagging it for anyone reading this later.
- No UI task depends on this work per the brief ("touches nothing the UI tasks touch"), so no
  downstream check was needed here.

## Full suite result

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
…
Test Suite 'ARShaderTests.xctest' passed … Executed 272 tests, with 0 failures (0 unexpected)
```
268 baseline + 4 new render-scale tests + 1 new unreachability test − 1 removed obsolete test = 272.

## Commits

- `218d17f` — `feat(3c): PREVIEW SCALE can no longer reach the projector`
- `711971c` — `docs(3c): fix previewScale's doc comment for the preview/program split`

---

# Fix round 1 of 5 — I1, I2, I3

Reviewer returned SPEC ✅, 6 quality findings (0 Critical, 3 Important, 3 Minor). Fixed the three
Important (I1–I3) per the controller's rulings below. The three Minor are explicitly untouched,
deferred to final branch review.

**Controller rulings applied:**
- I1 and I3 both originate in the brief itself (Step 4's two literal copies; Step 8's
  keep-it-returning-`false` design). Where the fix contradicts the brief's pasted code, **the fix
  governs**.
- I2 is new work the brief did not request, but is a direct consequence of the brief's change in a
  block the brief already touched — ruled in scope.

## I1 — extract `liveResolutionLocked()` so there's really only one rule

**The problem, in the reviewer's words:** `renderFrame()`'s comment claimed the master pair's own
allocation "derives from this, so there is no second rule that can drift out of sync" — but it
didn't derive from `liveRes`; `reallocateMastersLocked()` held an independent literal copy of the
same conditional at a different line. My own Task-2 Mutation 1 had already surfaced this (mutating
only `renderFrame()`'s copy left `testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale` green) but
I fixed the comment's honesty by documenting the discrepancy in the report rather than fixing the
actual duplication. The reviewer correctly named this as the real fix.

**What I changed:** `App/ARShader/InstrumentRenderer.swift` — added
`private func liveResolutionLocked() -> RenderSize` (lock-held, reads the backing `programLive`
directly, exactly as the brief's Step 4 code did) and call it from BOTH `renderFrame()` and
`reallocateMastersLocked()`. Neither call site holds its own copy of the conditional anymore.

**Covering tests:** the existing `FrameGraphTests`/`InstrumentRendererTests` suite — no new tests
needed, since this is a pure refactor of already-covered logic. Ran the full render-scale test group
before and after to confirm zero behavioural change:

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:ARShaderTests/FrameGraphTests -only-testing:ARShaderTests/InstrumentRendererTests
…
Executed 35 tests, with 0 failures (0 unexpected)
Executed 3 tests, with 0 failures (0 unexpected)
```

**Re-ran Mutation 1 against the extracted helper** (mutated `liveResolutionLocked()`'s body to
`renderScale.applied(to: masterResolution)`, dropping the pin, then reverted):

```
xcodebuild test … -only-testing:ARShaderTests/FrameGraphTests
…
FrameGraphTests.swift:433: testWithOutputLiveALiveDeckIgnoresPreviewScale — ("480") is not equal to ("1920")
FrameGraphTests.swift:445/446: testWithOutputLiveTheMasterIsFullSizeAtAnyPreviewScale — ("480")≠("1920"), ("270")≠("1080")
Executed 35 tests, with 4 failures (0 unexpected)
```
Both tests the brief originally predicted for Mutation 1 now fail — plus
`testClosingTheOutputRestoresPreviewScale`, a bonus catch. This is the exact result task-2's report
said the brief's Mutation 1 SHOULD have produced. Reverted immediately after observing.

## I2 — both scale readouts now show the size the chain actually rasterises at

**The problem:** `InstrumentView`'s PREVIEW SCALE and CUE SCALE readouts computed `resolved:` from
`previewScale`/`cueScale` unconditionally, so with the projector open at PREVIEW 25%, the strip read
"→ rasterising 480×270" while the chain (per I1's own logic) was actually at 1920×1080 — a false
number on the one surface an operator reaches for mid-set, right under a tooltip that now says the
opposite of what the number shows.

**What I changed:** `App/ARShader/InstrumentView.swift` —
- Added `static func liveResolution(programLive:previewScale:outputResolution:) -> RenderSize`,
  mirroring `InstrumentRenderer.liveResolutionLocked()`'s logic on the view side. Marked `internal`
  (not `private`) specifically so a test can call it — SwiftUI gives no way to read back rendered
  text, so this pure function is the testable surface for what the readouts display.
- `scalePickers` now computes `let live = Self.liveResolution(programLive: output.destination != .off, …)`
  once, and both `scaleField` calls use it: PREVIEW SCALE's `resolved:` is `live` directly; CUE
  SCALE's is `cueRenderScale.applied(to: live)` (unchanged composition, just now built on the correct
  base). `output.destination` is already `@Published` on the `@ObservedObject output`, and
  `!= .off` is exactly the boolean `OutputWindowController.setDestination` pushes into
  `isProgramLive` — no new plumbing, confirmed by re-reading `setDestination` (already wired in the
  original task-2 work).
- Updated PREVIEW SCALE's help text, which used to say "opening it pins this chain to full size
  regardless of what this reads" — that clause is now false (the readout DOES reflect it), so it now
  says "opening it pins this chain to full size, and the size shown below updates to reflect that."

**Testability — honest statement, not a claimed proof I don't have:** SwiftUI view bodies cannot be
rendered or introspected in this project's XCTest setup (no ViewInspector or similar; confirmed no
existing test does this for any view in the codebase — `grep` for `InstrumentView` in
`ARShaderTests/` found only an unrelated comment mention). What I CAN and DID prove is the pure
computation both readouts are built from. I did NOT prove that `scalePickers`'s SwiftUI body actually
calls `liveResolution` correctly and passes its result to both `scaleField` calls — that's verified
by code review (pasted diff below), not by a running test. This is the "if the view structure
genuinely does not [permit a full proof], say so explicitly" case the reviewer asked for.

**New test file:** `App/ARShaderTests/InstrumentViewLiveResolutionTests.swift` (3 tests) —
`testWithOutputClosedTheReadoutFollowsPreviewScale`,
`testWithOutputOpenThePreviewScaleReadoutShowsFullSizeNotTheTypedPercentage`,
`testTheCueReadoutComposesOntoTheSameLiveResolutionAsThePreviewReadout` (this last one reproduces the
CUE row's exact composition — `cueScale.applied(to: liveResolution(...))` — so it pins both rows'
math, not just the preview row's).

New file required regenerating the (gitignored, locally-derived) `.xcodeproj` via `xcodegen generate`
so the test target picks it up — confirmed `App/TrueISFEditor.xcodeproj` is git-ignored
(`.gitignore:6`) and regenerating produced no tracked diff, only the new test file itself needed
`git add`.

```
xcodebuild test … -only-testing:ARShaderTests/InstrumentViewLiveResolutionTests
…
Executed 3 tests, with 0 failures (0 unexpected)
```

## I3 — deleted `OutputSharpness` and its three tests

**Repo-wide grep, before deleting** (both app targets — `TrueISFEditor` and `ARShader` — searched
from repo root, no `head`, no path narrowing):
```
grep -rn "OutputSharpness" . --include="*.swift"
```
Result (4 lines, all within the two files I then edited):
```
App/ARShaderTests/OutputDestinationTests.swift:16
App/ARShaderTests/OutputDestinationTests.swift:21
App/ARShaderTests/OutputDestinationTests.swift:32
App/ARShader/OutputDestination.swift:76
```
Zero references outside those two files — confirmed zero production call sites (`isProjectingUpscaled`
had never been called from any view, renderer, or controller; its only callers were its own tests).

**What I changed:**
- `App/ARShader/OutputDestination.swift` — deleted the `OutputSharpness` enum entirely (its doc
  comment's own safety claim — "a change that lets a preview control reach the projector again turns
  this true and fails `testProjectingAnUpscaleIsUnreachable`" — was false: it returned a hardcoded
  `false` with zero coupling to `InstrumentRenderer.programLive`, so gutting the actual pin in
  `renderFrame()` during I1's Mutation-1 re-run left all three `OutputSharpness` tests green).
  Replaced with a short retirement comment explaining why and naming the real regression guards.
- `App/ARShaderTests/OutputDestinationTests.swift` — deleted its three now-tautological tests:
  `testALowScaleIsFreeWhileOutputIsClosed`, `testProjectingAtFullScaleIsNotFlagged`,
  `testProjectingAnUpscaleIsUnreachable`.

**Repo-wide grep, after deleting** (same command, unrestricted, full result pasted — zero-result
count confirmed):
```
grep -rn "OutputSharpness\|isProjectingUpscaled" . --include="*.swift"
```
Result (1 line — my own retirement comment's prose mention, not a declaration or call site):
```
App/ARShader/OutputDestination.swift:69:// `OutputSharpness` (the "is the projector upscaled" warning check) lived here until phase 3c
```
Zero actual code references remain. (Two documentation files under `docs/superpowers/` also mention
`OutputSharpness` in historical plan/spec prose — left untouched as out-of-scope history, not code.)

**Covering tests / command:**
```
xcodebuild test … -only-testing:ARShaderTests/OutputDestinationTests \
  -only-testing:ARShaderTests/FrameGraphTests -only-testing:ARShaderTests/InstrumentRendererTests
…
Executed 11 tests, with 0 failures (0 unexpected)   # OutputDestinationTests: 14 -> 11
Executed 35 tests, with 0 failures (0 unexpected)   # FrameGraphTests
Executed 3 tests, with 0 failures (0 unexpected)    # InstrumentRendererTests
```

## Suite-count arithmetic (stated plainly, per the reviewer's instruction)

- Before this round: 272 tests (task-2's original commit).
- I3 removes 3 tests (`OutputDestinationTests` 14 → 11): **272 → 269.**
- I2 adds 3 tests (`InstrumentViewLiveResolutionTests` 0 → 3): **269 → 272.**
- **Net: 272 → 272 — unchanged, and that is coincidence of magnitude, not of meaning.** The 3
  removed tests had zero discriminating power (they passed under both correct code and the buggy
  mutation). The 3 added tests catch a real bug (I2) that shipped in the original task-2 commit. Full
  suite confirms 272/272 green after both changes:

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
…
Test Suite 'ARShaderTests.xctest' passed … Executed 272 tests, with 0 failures (0 unexpected)
```

## Deferred (untouched this round, per controller instruction)

- Minor 1 — `previewScale`'s setter reallocating the master pair even when the size is unchanged.
- Minor 2 — the one-frame race when the projector opens mid-`renderFrame()`.
- Minor 3 — `isProgramLive` mirroring the operator's request rather than whether a window is
  actually up.

## Files changed this round

- `App/ARShader/InstrumentRenderer.swift` — I1: extracted `liveResolutionLocked()`.
- `App/ARShader/InstrumentView.swift` — I2: extracted `liveResolution(...)`, wired both readouts
  through it, updated PREVIEW SCALE help text.
- `App/ARShader/OutputDestination.swift` — I3: deleted `OutputSharpness`.
- `App/ARShaderTests/OutputDestinationTests.swift` — I3: deleted 3 tautological tests.
- `App/ARShaderTests/InstrumentViewLiveResolutionTests.swift` — I2: new file, 3 tests.

## Commit (fix round 1)

- `18e73d8` — `fix(3c): round-1 review fixes for the preview/program split (I1-I3)`
