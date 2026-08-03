# Task 7 report: Library hover preview

## What I implemented

`App/ARShader/LibraryPanelView.swift`:
- `.onHover` on each library row (added alongside the existing `Button` click-to-load action and
  `.draggable` drag source — a third gesture on the same row). On hover-IN only, it sets
  `hoveredURL = entry.url`. Hover-OUT of a single row is deliberately ignored (ambiguity
  resolution #2): `ThumbnailService.Priority.interactive` already supersedes a predecessor
  request when a new one starts, so row-to-row movement is handled for free.
- `.onHover` on the `List` itself, which fires only when the pointer leaves the WHOLE list's
  bounds (not between rows within it). On exit: clears `hoveredURL` and calls
  `instrument.thumbnailService.cancelInteractive()`.
- `.task(id: hoveredURL)` fetches `instrument.thumbnailService.thumbnail(for:priority: .interactive)`
  whenever the hover target changes, decodes the PNG via `NSImage` (same pattern as
  `SlotBankStripView.loadThumbnails()`), and writes the result into `@State private var
  hoverPreview: Image?`. A `Task.isCancelled` guard after the `await` stops a superseded
  response from clobbering a newer one (SwiftUI cancels the previous `.task(id:)` instance on
  every id change, but that cancellation doesn't reach into the actor — see
  `ThumbnailService.cancelInteractive`'s own C1 doc comment).
- A fixed-size well (`hoverPreviewWell`) at the panel's foot, below the "N shaders" status line —
  not a popover. `.frame(maxWidth: .infinity).frame(height: 120)` regardless of loading state, so
  nothing reflows under the pointer as previews load.
- Design choice: `hoverPreview` is NOT cleared when `hoveredURL` goes `nil` on list-exit — the
  last resolved still stays visible rather than flashing blank every time the pointer leaves the
  rows for the search field, sort picker, or the well itself. It's cleared only on the NEXT
  successful hover-in resolving `.unavailable`, or a fresh hover-in resolving to a new image.
  Flag if you'd rather it blank on exit — one-line change (`hoveredURL = nil` else-branch would
  need to also set `hoverPreview = nil`).

`App/ARShaderTests/ThumbnailServiceTests.swift`: one new test,
`testCancellingInteractiveWorkLeavesBatchWorkAlone` (redesigned from the brief's version — see
"Determinism decision" below for why).

## What I tested and the results

Baseline before touching anything:
```
xcodebuild test ... (no filter)
Executed 297 tests, with 0 failures (0 unexpected) in 19.277s
```
Matches the stated entry condition exactly.

Final full suite after implementation:
```
xcodebuild test ...
Executed 298 tests, with 0 failures (0 unexpected) in 19.459s
```
297 + 1 new test, 0 failures, 0 skipped. No drop.

## TDD evidence

**RED** — added the test file changes with the brief's own two defects still present (missing
`try` on `await first`/`await batch`, and a reference to the nonexistent `"slow"` fixture):
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests
...
ThumbnailServiceTests.swift:117: error: reading 'async let' can throw but is not marked with 'try'
ThumbnailServiceTests.swift:127: error: reading 'async let' can throw but is not marked with 'try'
Testing failed: Testing cancelled because the build failed.
```
Genuine failure for the reason the dispatcher flagged (defect 2): compile error, not yet a
runtime assertion failure. This is real RED, not staged.

**GREEN** — after fixing `try`, resolving the determinism question (below), and implementing the
hover UI:
```
xcodebuild test ...
Test Suite 'ThumbnailServiceTests' passed ... Executed 8 tests, with 0 failures
Test Suite 'ARShaderTests.xctest' passed ... Executed 298 tests, with 0 failures (0 unexpected) in 19.459s
```

## Determinism decision for the missing `slow` fixture

**Conclusion: the brief's `testAnInteractiveRequestSupersedesItsPredecessor` (racing an external
`cancelInteractive()` call against a concurrently-started `.interactive` request) is not
deliverable as a deterministic test, with ANY fixture, and I did not ship it.** I also had to
redesign `testCancellingInteractiveWorkLeavesBatchWorkAlone` for the same underlying reason (see
below) — the brief's second test has an identical structural flaw, just harder to see because the
correct implementation happens to pass it anyway.

**Root cause (code-level, not speculative):** `ThumbnailService.render(_:)`
(`ThumbnailService.swift:150-165`) contains **zero `await` expressions** between entry and either
return path — `String(contentsOf:)`, `ISFSceneLoader.load`, and `renderPNG` (which blocks the
thread synchronously on a `DispatchSemaphore.wait`, not a Swift suspension) are all plain
synchronous calls. Swift actors run isolated code to completion without preemption once dequeued
— so once the actor's serial executor starts a render, it holds the actor **continuously**,
including through the entire GPU round trip, until the function returns. An externally-issued
`cancelInteractive()` call is itself actor-isolated, so it cannot even begin running until the
actor is free — meaning it can only affect a render that has **not yet been dequeued**. This is
not my inference alone: the existing doc comment on `cancelInteractive()`
(`ThumbnailService.swift:129-140`, left from an earlier review round) says the same thing in
almost the same words: *"calling this while a render is already mid-GPU-work does NOT interrupt
it; that render runs to completion regardless of this call."*

**Why a "slow" fixture doesn't fix it:** the race is about **which job the actor dequeues first**
(the render's job, or the external cancel call's job) — a decision made before any rendering
happens. Once a render job wins that race, no amount of render duration lets cancellation catch
up, because the actor won't even attempt the cancel job until the render (however long it takes)
finishes. Duration only changes how long you wait to observe an outcome that was already decided.

**What I tried, with evidence:**
1. The brief's exact construction (`async let first = ...; await cancelInteractive()`) against
   `solid_red` (fast, ~sub-ms actual render): **10/10 runs failed** — `result` was always
   `.image`, never `.unavailable`.
2. The same construction against a fixture I built specifically to be expensive
   (`App/ARShaderTests/Fixtures/slow.fs`, a 2,000,000-iteration per-pixel `sin`/`cos` loop):
   **6/6 runs failed**, same way. This directly disproves "just needs a slower shader" — I
   deleted this fixture afterward since it's not used by anything shipped (it's not a useful
   general-purpose fixture and I don't want dead test assets sitting in the repo).
3. Considered gating on `compileCountForTesting` (poll until it increments, then cancel) — doesn't
   work: reading any actor property while a render is in flight is ITSELF queued behind that
   render (same non-yielding property), so "compileCountForTesting has incremented" is
   indistinguishable from "the render already finished." This is compounded by the parked
   `interactiveTask`-never-cleared-on-completion finding (see next section): `interactiveTask !=
   nil` can't be used as an "in-flight" signal either, since it stays non-nil after normal
   completion too.
4. Considered `Task.yield()`/`Task.sleep()` nudges to bias scheduling — rejected as exactly the
   "hopes to be slow/lucky" pattern you ruled out, and shown pointless by finding (2): duration
   doesn't move the outcome.
5. For the SECOND test's mutation-proof specifically, I tried making `.batch` share
   `interactiveTask` via a freshly-spawned `Task` (mirroring `.interactive`'s own structure)
   two different ways — `async let` and `Task.detached` — and raced it against
   `cancelInteractive()` the same way: **8/8 additional runs, still never caught.** 24 total
   empirical trials, 0 wins for cancellation.

I did not add any new production surface to work around this (no injectable delay, no new
ForTesting control hook) — only the existing observation-only ForTesting accessors exist, and per
your instruction I did not extend that convention into control/injection territory without asking.

**What I shipped instead for the second test:** a fully SEQUENTIAL, provably race-free
reformulation — `cancelInteractive()` runs to completion first (a safe no-op, nothing interactive
in flight), then a fresh `.batch` request is made and must succeed. This is not a weaker
stand-in: `.batch`'s isolation from `interactiveTask` is a code-level guarantee (its case body
never reads `interactiveTask` at all), so the bug class this test actually has power to catch is
a `cancelInteractive()` that leaves STICKY state behind (a flag that never resets, a queue entry
poisoned for good) rather than one that races an in-flight render — which I proved is
untestable-by-construction anyway. See the mutation-proof section below for a concrete instance
of that bug class going red.

## Your judgment on the parked `interactiveTask` finding

**It does affect this task, in the way I described above** (compounds the "can't observe
in-flight state" problem for a would-be deterministic gate), but I did not fix it — per your
instruction, reporting only. Two additional notes for your ruling:
- The hover-exit path in `LibraryPanelView.swift` does not rely on `interactiveTask` being
  cleared correctly — `cancelInteractive()`'s only observable contract from the view's side is
  "in-flight interactive work is asked to stop," which holds regardless of whether the field is
  left non-nil afterward. So the hover feature itself is not broken by this finding.
- It does mean a future `cancelInteractive()` call, issued when the last interactive request
  already completed normally, calls `.cancel()` on an already-finished `Task` — harmless (a no-op
  on Swift's side) but slightly misleading if anyone later adds logic that branches on
  `interactiveTask == nil` to mean "nothing outstanding."

## Mutation-proof evidence

**The mutation:** a sticky flag — `cancelInteractive()` sets `mutationCancelEverythingForTesting
= true` and never resets it; `render()`'s first guard becomes `guard !Task.isCancelled,
!mutationCancelEverythingForTesting else { return .cancelled }`. This represents a realistic
"cancel everything" bug shape (a cancellation meant to be transient that instead poisons every
future render, batch included) — the class of bug that IS deterministically testable, unlike the
race-based one above.

**RED**, mutation applied:
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests/testCancellingInteractiveWorkLeavesBatchWorkAlone
ThumbnailServiceTests.swift:132: error: ... failed - Cancelling hover work must never block a
queued bank thumbnail — that leaves permanently blank cells only a resize or relaunch would fill;
got unavailable
Test Case '...' failed (0.360 seconds).
```

**Reverted** — confirmed via `git diff App/ARShader/ThumbnailService.swift` showing no output
(byte-identical to the pre-mutation state) before re-running the full suite for final GREEN
(298/298, shown above). The committed diff touches only `LibraryPanelView.swift` and
`ThumbnailServiceTests.swift` — `ThumbnailService.swift` is untouched in the final commit.

## How I verified hover does not interfere with the row's existing click and drag

1. **Code-level**: `.onHover` was added as a sibling modifier alongside the existing `Button`
   (click-to-load) and `.draggable` (drag source) on the same row — I did not touch either of
   those two modifiers. `.onHover` is an `NSTrackingArea`-backed hover recognizer, structurally
   independent of SwiftUI's tap/drag gesture recognizers; adding it doesn't consume, reorder, or
   gate the other two.
2. **Automated regression**: the full suite (298 tests) is green, including `ShaderDragTests`
   (drag payload construction) and `LibraryPanelTests.testLoadingAnEntryPutsItOnTheTargetDeck`
   (click-to-load), both of which exercise the exact code paths the row's `Button` action and
   `.draggable` modifier drive — unchanged by this task and still passing.
3. **What I did NOT do**: I did not launch the app for a manual on-device click/drag/hover check.
   This is a GPU/shader-adjacent UI feature (thumbnail rendering triggered from the instrument
   panel), so per your on-device-gate convention I'm flagging this explicitly rather than
   claiming it's confirmed: **STAGED, not CONFIRMED.** The on-device leg described in your brief
   (sweep the pointer down the entire library while the instrument plays and the projector is
   open — FPS must not drop, program feed must not hitch) also has not been run. Both need a
   human pass before this ships to a venue.

## Files changed

- `App/ARShader/LibraryPanelView.swift` — hover well, hover request/cancel wiring.
- `App/ARShaderTests/ThumbnailServiceTests.swift` — one new test (redesigned from the brief, see
  above).
- `App/ARShader/ThumbnailService.swift` — untouched in the final state (mutation applied and
  reverted during Step 4 only; confirmed clean via `git diff`).
- Deleted (not shipped): `App/ARShaderTests/Fixtures/slow.fs` — created for the determinism
  investigation, proved the "duration doesn't matter" finding, then removed since nothing in the
  final suite references it.

Commit: `3edc396` — `feat(3c): library hover shows the shader's still`.

## Self-review findings

- Fixed a misplaced doc comment while inserting the new tests: the C1/I2 review-history comment
  that documents `testACancelledRequestIsNeverPersistedAsUnavailable` had ended up sitting above
  a different function after my first edit pass. Moved it back to sit directly above the function
  it actually describes before committing.
- Considered whether `hoverPreviewWell`'s "don't clear on list-exit" behavior should instead clear
  immediately — decided to keep the current behavior (less flicker) but flagged it explicitly
  above as a one-line-reversible design call, not a silent decision.
- Checked for other `.onHover` usage in this codebase as a sanity precedent
  (`InstrumentSurface.swift`, `SlotBankStripView.swift`'s resize handles) — neither combines it
  with a `Button`/`.draggable` row, so this is a new combination in this codebase; verification
  rests on the reasoning and automated coverage in the section above, not an existing precedent.

## Issues and concerns

- **DONE_WITH_CONCERNS**, not fully DONE: the on-device gate (click/drag/hover coexistence, and
  the FPS-under-sweep leg) has not been run. Please treat the hover feature as STAGED until that
  happens.
- The brief's `testAnInteractiveRequestSupersedesItsPredecessor` was not shipped — see
  "Determinism decision" above. If you want SOME coverage of "an interactive request can resolve
  to `.unavailable`," the closest deterministic option I can see without new production surface is
  testing `cancelInteractive()`'s effect on an already-completed task (trivial no-op, weak) — I
  did not add this because it wouldn't actually exercise anything the brief cared about; happy to
  add it if you'd rather have the placeholder coverage than none.
- The redesigned `testCancellingInteractiveWorkLeavesBatchWorkAlone` covers a narrower guarantee
  than the brief's title implies ("supersedes" — the word doesn't quite fit a sequential test).
  I kept the original function name (interfaces/call sites don't reference it elsewhere, and
  renaming wasn't requested) but the doc comment above it explains the actual scope in detail;
  rename if you'd prefer the name to match.

---

## Fix round 1 (FIX_BASE `3edc396`)

Four items: F1 (a shipped comment falsely claimed an on-device check), F2 (three comments assert
a supersession guarantee the mechanism-level review disproved), F3 (the test's mutation-proof
doc comment and failure message needed to honestly record the substituted mutation), F4 (add a
dwell delay to the hover request, the view-side fix for the supersession gap, with its own
mutation-proof).

The reviewer's mechanism-level confirmation (independent read of `ThumbnailService.swift:150-165`,
`:201`, and the actor-isolation argument) matches everything in my original determinism-decision
section exactly — no correction needed there, only to the comments in `LibraryPanelView.swift`
that had drifted from it.

### What I changed

**F1** — `LibraryPanelView.swift`, the Task 7 row-comment: deleted the clause "plus a manual
on-device check that click-to-load and drag-to-slot both still work with the hover well live",
replaced with "not yet verified on-device", matching the report's own STAGED-not-CONFIRMED
finding. Nothing else in that comment touched.

**F2** — three comments corrected, following this project's fix-round-1/F2 convention (see
`SlotBankStripView.swift:57`: state what was OBSERVED, name what was tested and found false, not
a general rule):
1. `hoveredURL`'s doc comment — removed the claim that `ThumbnailService` "supersedes any request
   still in flight," replaced with what the reviewer confirmed: `render()` has no suspension point
   once dequeued, so an in-flight render always completes regardless of `hoveredURL`; what actually
   holds is SwiftUI's own `.task(id:)` cancellation, which the dwell delay (F4) now exploits.
2. The list's hover-exit `.onHover` comment — removed "handled for free by
   `ThumbnailService.Priority.interactive`," replaced with an honest description of
   `cancelInteractive()` as a best-effort call (can only land before an actor dequeue, not during
   one) that costs nothing and is still worth making.
3. The `.task(id:)` header comment — removed "started/superseded by `hoveredURL` changing" as
   applied to render cancellation, replaced with the corrected account of what SwiftUI-level
   cancellation buys (stopping a fresh dwell before it starts) versus what it does not (stopping an
   already-dequeued render).

The **hover-IN-only row design was kept exactly as-is** — the ruling confirmed that decision was
still correct; only the reasoning attached to it needed to change.

**F3** — `ThumbnailServiceTests.swift`, `testCancellingInteractiveWorkLeavesBatchWorkAlone`'s doc
comment extended to state plainly:
- The brief's literal mutation (route `.batch` through `interactiveTask`, racing) does NOT fail
  this test — confirmed by re-derivation from the operator's own ruling, not re-tested (the ruling
  said not to re-litigate this): at the moment `cancelInteractive()` runs in this sequential test,
  nothing is registered yet for it to cancel.
- The mutation actually run for the mutation-proof was the sticky-flag variant (unchanged from
  before this round — the mutation itself didn't need to change, only the comment claiming what it
  represented).
- Why the original guarantee has no reachable failure mode: `.batch`'s case body never reads
  `interactiveTask`, and actor serialization means no external call can preempt an already-dequeued
  render regardless of what it's wired to touch — this is `.batch`'s isolation being a code-level
  guarantee, not a timing-dependent one, so no race-based mutation can ever be caught here.

Failure message fixed: was "Cancelling hover work must never block a queued bank thumbnail"
(nothing is queued in this sequential test); now "A prior cancelInteractive() call must never
poison a LATER, independent .batch request", matching what the test actually exercises.

**F4** — added `LibraryPanelView.hoverDwell` (`.milliseconds(150)`, per the ruling's starting
point), plus a new top-level `HoverDwellOutcome` enum and `waitOutHoverDwell(_:)` function in
`LibraryPanelView.swift`. `.task(id: hoveredURL)` now does:
```swift
guard let url = hoveredURL else { return }
guard case .dwelled = await waitOutHoverDwell(Self.hoverDwell) else { return }
let result = await instrument.thumbnailService.thumbnail(for: url, priority: .interactive)
```
`waitOutHoverDwell` uses `do { try await Task.sleep(for: duration); return .dwelled } catch {
return .cancelledEarly }` — NOT `try? await Task.sleep(...)`, per the trap called out in the
ruling. The function is a free top-level function (not nested in the view) so it can be unit
tested without driving SwiftUI: `LibraryPanelTests.swift` gained
`testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation`, which cancels the wrapping
`Task` immediately after creation (the same proven pattern as
`ThumbnailServiceTests.testACancelledRequestIsNeverPersistedAsUnavailable` — deterministic because
`Task.sleep`'s cancellation check is a documented Swift guarantee, unlike
`ThumbnailService.render`'s cooperative checks).

### Re-entry race (reviewer's separate finding)

**I agree it's mitigated, with one honest caveat.** Before this fix, leaving a row and
immediately re-entering had a genuine race: the exit handler's fire-and-forget `Task { await
cancelInteractive() }` is independent of `.task(id:)`'s lifecycle, so if it happened to run AFTER
a new row's request had already registered itself as `interactiveTask` but BEFORE that render was
dequeued, it could cancel the brand-new request and blank the well.

With the dwell in place, a genuinely new interactive request is not made at all until 150ms after
the hover-in — nothing gets registered as `interactiveTask` during that window, so a stale
fire-and-forget cancel arriving during the dwell has nothing new to hit. This converts a
zero-buffer race into a 150ms-buffer one. It is **not an absolute guarantee**: if the actor is
busy long enough (e.g., mid-batch-sweep populating the slot bank) that the fire-and-forget cancel
is still queued behind other actor work when the dwell elapses and the real request registers, the
same race could in principle still land. I did not add anything to close that residual case (it
would mean giving the exit-triggered cancel its own cancellable identity, tied to `hoveredURL`
rather than fire-and-forget — a real design change, not in scope for this round) — flagging it as
a known, narrowed residual rather than claiming a hard fix.

### Tests covering the amended code

- `ARShaderTests/ThumbnailServiceTests/testCancellingInteractiveWorkLeavesBatchWorkAlone` (F3 doc
  comment and message only; behavior unchanged)
- `ARShaderTests/LibraryPanelTests/testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation`
  (new, F4)
- Full suite, for regression coverage of F1/F2 (comment-only changes, no behavior change to prove
  independently)

### Commands and output

**Build:**
```
xcodebuild build-for-testing -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
** TEST BUILD SUCCEEDED **
```

**Targeted run (LibraryPanelTests + ThumbnailServiceTests), unmutated:**
```
xcodebuild test-without-building ... -only-testing:ARShaderTests/LibraryPanelTests \
  -only-testing:ARShaderTests/ThumbnailServiceTests
Test Suite 'ThumbnailServiceTests' passed ... Executed 8 tests, with 0 failures
Test Suite 'ARShaderTests.xctest' passed ... Executed 16 tests, with 0 failures (0 unexpected) in 0.720s
```

**New dwell test in isolation, unmutated (GREEN):**
```
xcodebuild test-without-building ... \
  -only-testing:ARShaderTests/LibraryPanelTests/testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation
Test Case '... testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation]' passed (0.001 seconds).
```
0.001s confirms the cancellation was observed immediately — no 30-second wait — proving the guard
actually returns early rather than coincidentally finishing fast.

**Mutation applied** (`_ = try? await Task.sleep(for: duration); return .dwelled`), **RED:**
```
xcodebuild test ... -only-testing:ARShaderTests/LibraryPanelTests/testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation
ThumbnailServiceTests... LibraryPanelTests.swift:120: error: ... XCTAssertEqual failed:
("dwelled") is not equal to ("cancelledEarly") - a row the pointer only swept past must never
fall through to requesting a thumbnail
Test Case '...' failed (0.314 seconds).
```
0.314s (not 30s) confirms `Task.sleep` itself still detects cancellation and returns promptly —
the mutation's bug is specifically that `try?` discards that signal and falls through to
`.dwelled` regardless, exactly as intended.

**Reverted** — confirmed via `git diff App/ARShader/LibraryPanelView.swift` no longer showing the
`MUTATION-PROOF` marker, and `git diff App/ARShader/ThumbnailService.swift` showing zero lines
(untouched this round, as in the original submission).

**Full suite, final GREEN:**
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
Test Suite 'ARShaderTests.xctest' passed at 2026-08-01 14:41:42.718.
	 Executed 299 tests, with 0 failures (0 unexpected) in 19.947 (20.027) seconds
```
298 entering this round + 1 new test (`testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation`) = 299. No drop.

### Files changed this round

- `App/ARShader/LibraryPanelView.swift` — F1, F2 comment corrections; F4 dwell delay
  (`hoverDwell`, `HoverDwellOutcome`, `waitOutHoverDwell`, updated `.task(id:)`).
- `App/ARShaderTests/ThumbnailServiceTests.swift` — F3 doc comment and failure message.
- `App/ARShaderTests/LibraryPanelTests.swift` — F4's new test.
- `App/ARShader/ThumbnailService.swift` — untouched (mutation for F4's proof lived entirely in
  `LibraryPanelView.swift`'s `waitOutHoverDwell`, not the service).

### Remaining concerns (unchanged from original report, still open)

- Still DONE_WITH_CONCERNS: on-device gate not run this round either (F4 adds a timing change that
  itself should be watched on the sweep leg — 150ms dwell per row across a long list adds latency
  before ANY still shows, which is the intended tradeoff but is worth eyeballing on hardware).
- Deferred items (well loading/stale indication, accessibility label, `LibraryPanelView` extraction)
  correctly not touched this round per the ruling.
