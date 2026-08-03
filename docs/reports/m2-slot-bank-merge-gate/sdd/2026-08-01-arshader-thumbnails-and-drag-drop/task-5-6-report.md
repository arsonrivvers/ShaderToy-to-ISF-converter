# Task 5 + 6 report: drag and drop — library/deck → slot/deck/FX

Branch `m2-slot-bank`, worktree `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank`.

## Task 5: drag and drop from the library

### What I implemented

- **`App/ARShader/ShaderDrag.swift`** (new) — `ShaderDrag`, a `Codable`/`Transferable`/`Sendable`
  payload (`source`, `url`, `snapshot`) plus the pure `ShaderDrag.accepts(_:on:isSlotFilled:withOption:)`
  never-overwrite rule, written verbatim from the brief. No SwiftUI import, matching `SlotBank`'s
  doctrine. Registers `UTType.arshaderDrag` (`com.arshader.shader-drag`).
- **`App/ARShader/Info.plist`** — added `UTExportedTypeDeclarations` for the custom UTType. See
  "Deviation 1" below for why this landed here instead of `project.yml`.
- **`App/ARShader/LibraryPanelView.swift`** — removed the "Load onto" segmented picker and its
  `@Binding var target: LibraryTarget` / init parameter entirely. Removed the row `Button` and its
  `instrument.load(entry.url, onto: target)` action; rows are now a plain `Text` with
  `.draggable(ShaderDrag(source: .library, url: entry.url, snapshot: nil))`. The unrelated sort-order
  `Picker` at the top of the panel is untouched.
- **`App/ARShader/InstrumentView.swift`**:
  - Removed `@State private var libraryTarget` and updated the `.library` case of `panelContent` to
    `LibraryPanelView(instrument: instrument)`.
  - `DeckStripView` gained an `instrument: Instrument` property/init parameter (it previously had no
    way to reach `Instrument.load`), threaded through from `InstrumentView.deckStrips`.
  - Both `FXChainView` call sites (`DeckStripView`'s FX section, `InstrumentView.masterStrip`) now
    pass `instrument:` and `target: .deckFX(id)` / `target: .masterFX`.
- **`App/ARShader/FXChainView.swift`** — `FXChainView` gained `instrument: Instrument` and
  `target: LibraryTarget` (always `.deckFX`/`.masterFX` in practice; `.deck` is handled in the switch
  for completeness but never actually reached from a call site). The whole chain body is now a
  `.dropDestination(for: ShaderDrag.self)` that accepts a library drag and calls
  `instrument.load(drag.url, onto: target, thenApply: drag.snapshot)` — the existing
  `Instrument.load(_:onto:thenApply:)` FX-append seam, no new append path. A light accent-colour
  highlight shows while a compatible drag hovers.
- **`App/ARShader/MonitorView.swift`** — deck `MonitorTile`s (never PROGRAM) are now drop targets via
  `dropDestinationIfDeck`, calling `instrument.load(drag.url, onto: .deck(id), thenApply: drag.snapshot)`.
  Added `import AppKit` for `NSEvent.modifierFlags`.
- **`App/ARShader/SlotBankStripView.swift`** — each `SlotCell` in the `ForEach` is now a
  `.dropDestination(for: ShaderDrag.self)`: accepted drops call `bank.capture` directly (the one
  write path); refused drops set `rejectedSlot = index`, which drives a brief `.offset` shake on the
  cell, cleared after 400ms. `isTargeted` is filtered through the SAME `!isSlotFilled || option`
  predicate `accepts` uses for a `.slot` destination (see "isTargeted filtering" below for why this
  is sound without knowing the drag's source). `SlotCell` gained `isTargeted`/`isRejected` params
  driving a highlight ring / shake respectively. Fixed the two flagged stale strings (see "Stale
  copy" below) and removed the now-dead "Replace with SOURCE deck" context menu item.

### isTargeted filtering (why it's sound without resolving the drag's source)

SwiftUI's `.dropDestination(for:action:isTargeted:)` gives `isTargeted` only a `Bool` — no access to
the hovering item's value, which is resolved only when `action` runs at drop time. So a hover
callback cannot literally ask "would `accepts` say yes to *this* drag?" — it doesn't know the drag's
`source` yet. For a `.slot` destination specifically this doesn't matter: `accepts` reduces to the
identical `!isSlotFilled || option` predicate for BOTH legal sources (`.library` and `.deck`) once the
destination is `.slot` — the `.slot`-sourced case is unreachable in practice (no view ever calls
`.draggable` with `source: .slot`). So filtering on `!isSlotFilled || option` alone is exact for
slots. For FX/deck destinations I did not attempt the same filtering — a deck-sourced drag would
still light up an FX-chain highlight it will then be rejected for at drop time, because only the
source (unknowable at hover) distinguishes accept from reject there. macOS's default drag "snap
back" on a refused drop is the fallback signal there, per the brief's "no-entry cursor is the
baseline" framing.

### Deviations from the brief (verified against the code)

1. **Custom UTType lives in `ARShader/Info.plist`, not `project.yml`.** This target sets
   `GENERATE_INFOPLIST_FILE: NO` and `INFOPLIST_FILE: ARShader/Info.plist` — there is no xcodegen
   `info:` block for `project.yml` to extend; the plist is hand-maintained and just referenced by
   path. Confirmed by reading `project.yml`'s `ARShader` target settings before editing.
2. **`project.yml` itself needed no edit.** Adding `ShaderDrag.swift`/`ShaderDragTests.swift` only
   required running `xcodegen generate` to pick the new files up into `project.pbxproj` — confirmed
   this was necessary, not optional: I built `build-for-testing` BEFORE regenerating and it reported
   `** TEST BUILD SUCCEEDED **` even though `ShaderDrag` didn't exist yet, because
   `ShaderDragTests.swift` was silently absent from the compiled `SwiftFileList` (verified by
   grepping it). `TrueISFEditor.xcodeproj/` is gitignored (`.gitignore:6`), so no project file needed
   staging either time.
3. **No baselines were re-recorded (brief Step 9 predicted they would).** `testSurfaceBaselines`
   renders `stubSurfaceForBaselines`, which hosts a fixed `Color.gray` in the panel slot regardless of
   `layout.openPanel` — it never instantiates the real `LibraryPanelView`. Removing the picker changed
   nothing this harness observes. Verified empirically rather than assumed: ran the full suite with no
   `RECORD` sentinel present and `testSurfaceBaselines` passed unchanged against the three committed
   PNGs (see GREEN evidence below).
4. **Stale `SlotCell` copy** (deferred finding named in the dispatch): `helpText`'s empty-slot string
   ("Click to capture the SOURCE deck…") and the context menu's "Replace with SOURCE deck" both named
   a control Task 4 deleted. Fixed the help text to describe the drag gesture. The context menu item
   could not be honestly relabeled — it triggered the same no-op `capture(into:)` before and after,
   and a menu item that reads as an action but does nothing when clicked is worse than one that
   doesn't exist — so I removed it, keeping "Clear slot". I did **not** touch `SlotCell.activate()`'s
   `⌥`-click branch (still routes to the same no-op `capture(into:)`) or the empty-cell click path —
   rewiring or removing those is a bigger behavioural change than "fix the copy," and nothing in the
   brief's interface list touches them. I did update `capture(into:)`'s own doc comment (it explicitly
   said "SlotCell itself is untouched," which stopped being true) and the adjacent "⌥-click to
   replace" help text for the filled-slot case, since leaving it unfixed right next to the string I
   did fix would have been a new inconsistency I introduced.

### TDD evidence

**RED** — `xcodebuild ... build-for-testing` with `ShaderDragTests.swift` written but `ShaderDrag.swift`
not yet created:
```
error: cannot find type 'ShaderDrag' in scope
... (30 similar errors across every test using ShaderDrag)
** TEST BUILD FAILED **
```
Expected: the type genuinely didn't exist yet.

**GREEN** — after creating `ShaderDrag.swift` and regenerating the project:
```
xcodebuild ... test -only-testing:ARShaderTests/ShaderDragTests
Executed 9 tests, with 0 failures (0 unexpected) in 0.228 seconds
** TEST SUCCEEDED **
```
(9, not 7, because I wrote Task 6's two brief-specified tests up front too — see Task 6 below.)

**Full suite after all Task 5 view wiring:**
```
xcodebuild ... test
Executed 290 tests, with 0 failures (0 unexpected) in 19.7s
** TEST SUCCEEDED **
```
290 = 281 baseline + 9 new. No drop, no loss. `testSurfaceBaselines` and
`testLibraryTargetsCoverEveryDeckAndEveryChain` both passed unchanged (grepped explicitly from the
log).

### Mutation-proof evidence (Step 8 — "the single most important mutation proof in the phase")

Changed `ShaderDrag.accepts`'s `.library` branch from `return !isSlotFilled || option` to
`return true` unconditionally:
```
Test Case '-[ARShaderTests.ShaderDragTests testADropOnAFilledSlotIsRejectedWithoutOption]' failed
XCTAssertFalse failed
```
Exactly the predicted test, exactly the predicted failure. Reverted; confirmed full suite green again
(290/290) before committing.

### Commit

`438e103` — `feat(3c): drag and drop from the library; a drop never overwrites a filled slot`

---

## Task 6: drag a deck monitor to a slot

### What I implemented

- **`App/ARShader/MonitorView.swift`** — `MonitorTile.draggableIfCapturable` gates `.draggable` on
  deck sources only, attaching `ShaderDrag(source: .deck(id), url: preset.shaderURL,
  snapshot: preset.snapshot)` when `Instrument.currentPreset(of: id)` returns non-nil (a deck with a
  compiled shader), and passing the view through untouched otherwise — no sentinel payload for an
  empty deck. PROGRAM (`MonitorSource.master`) is never wrapped: `dragPayload` returns nil for it by
  construction (`currentPreset` only takes a `DeckID`).
- Extracted the payload-construction line into a new `static func dragPayload(for:instrument:) ->
  ShaderDrag?` (see "Step 5" below for why).

### TDD evidence

**Step 1/2 — brief-predicted, not a red phase.** `testADeckDragCarriesTheDialledValuesNotJustTheURL`
(the test the brief specifies verbatim) passed the moment I wrote `ShaderDragTests.swift`, before any
Task 6 production code existed, because it only exercises the `ShaderDrag`/`Preset` types Task 5
already built. Per the brief's own Step 2 ("If it already passes, that is fine and expected... say so
rather than pretending it was red first") — this is exactly that case, stated honestly rather than
manufactured.

**Step 5 — the harder half, and where I found a real problem.** I first wrote a "view-seam" test
(`testDeckMonitorDragPayloadCarriesTheCurrentPresetsSnapshot`) that called
`instrument.currentPreset(of:)` and hand-built a `ShaderDrag` from it — intending it to mirror what
`draggableIfCapturable` does. I ran the required mutation (hardcode `snapshot: nil` in the
`.draggable(...)` call inside `draggableIfCapturable`) and the test **still passed**:
```
Test Case '...testDeckMonitorDragPayloadCarriesTheCurrentPresetsSnapshot]' passed (0.239 seconds)
```
This is exactly the trap the dispatch called out — "this project has shipped three consecutive
rounds of tests-that-cannot-fail." My test never called the mutated code; it reconstructed the same
value independently, so it was structurally unable to fail regardless of what the view did. Per the
brief's own instruction ("If you cannot make that test fail under the mutation, report it as
structurally untestable... Claiming a proof you do not have is not [accepted]") I did not report this
as untestable — I fixed it: extracted the one line that decides which `snapshot` goes into the
payload out of `draggableIfCapturable` into `MonitorTile.dragPayload(for:instrument:)`, a static,
`View`-free function (mirroring `ShaderDrag.accepts`'s own "no SwiftUI import" doctrine). The
production `draggableIfCapturable` now calls `Self.dragPayload(...)`, so it IS the code under test.
Rewrote the test to call `MonitorTile.dragPayload(for: .deck(.one), instrument: instrument)` directly
— the actual call site, not a parallel reconstruction — and added two small gate tests
(`testMonitorDragPayloadIsNilForAnEmptyDeck`, `testMonitorDragPayloadIsNilForProgram`).

Re-ran the SAME mutation against the fixed test:
```
Test Case '...testDeckMonitorDragPayloadCarriesTheCurrentPresetsSnapshot]'
error: XCTAssertNotNil failed - a deck monitor drag must carry the dialled values
error: XCTAssertEqual failed: ("nil") is not equal to ("Optional(...float(0.42))")
Test Case '...' failed (0.282 seconds)
```
Red, exactly as it should be. Reverted `snapshot: nil` back to `snapshot: preset.snapshot`; confirmed
green again.

**Full suite after the fix:**
```
xcodebuild ... test
Executed 292 tests, with 0 failures (0 unexpected) in 19.5s
** TEST SUCCEEDED **
```
292 = 290 (end of Task 5) + 2 new (the empty-deck and PROGRAM nil-payload gates).

### Mutation-proof evidence

Documented above — this task's Step 5 mutation proof IS the finding: my first attempt at it exposed a
tests-that-cannot-fail defect in my own test, which I then fixed by making the code testable
(extracting `dragPayload`) rather than writing a stronger-looking test that still wouldn't have
called the mutated line. Reverted after confirming red; confirmed the full suite is green again
(292/292) before committing.

### Commit

`4932bdb` — `feat(3c): drag a deck monitor to a slot to capture the live look`

---

## Files changed

- `App/ARShader/ShaderDrag.swift` (new)
- `App/ARShader/Info.plist`
- `App/ARShader/LibraryPanelView.swift`
- `App/ARShader/InstrumentView.swift`
- `App/ARShader/FXChainView.swift`
- `App/ARShader/MonitorView.swift`
- `App/ARShader/SlotBankStripView.swift`
- `App/ARShaderTests/ShaderDragTests.swift` (new)

No changes to `App/project.yml` or `App/ARShaderTests/Baselines/` (both deviations explained above).
`App/TrueISFEditor.xcodeproj/` is gitignored and was regenerated locally via `xcodegen generate` to
pick up the two new source files — nothing to stage there.

## Self-review

- **Completeness**: both tasks' Files lists are covered. The stale `SlotCell` copy and
  `libraryTarget` removal (both explicitly named in the dispatch) are done — grepped the whole tree
  for `libraryTarget`, `"SOURCE deck"`, and stale `LibraryPanelView(instrument:target:)` call sites
  after finishing: zero hits outside history.
- **Quality**: `dragPayload`, `dropDestinationIfDeck`, `draggableIfCapturable`, `targetedSlot`,
  `rejectedSlot` names describe exactly what they do. `FXChainView.dragDestination`'s `.deck` switch
  arm is unreachable in practice (no call site passes `target: .deck(_)`) but kept for exhaustiveness
  since `LibraryTarget` is a 3-case enum reused wholesale rather than a narrower type invented for
  this one struct.
- **Discipline**: did not touch `SlotCell.activate()`'s click-based capture path or `SlotBank`/
  `Instrument` beyond what the briefs specify. Did not add a rejection shake to FX/deck drop targets
  (not asked for; the brief's shake snippet is slot-specific, and macOS's default drag snap-back
  already signals rejection elsewhere).
- **Testing**: TDD followed for both tasks (Task 5 genuinely red before `ShaderDrag` existed; Task 6
  genuinely caught and fixed a non-failing test before committing, which is the finding worth
  flagging above). Both mutation proofs pass/fail exactly as predicted and were reverted. Suite count
  progression is accounted for at every step (281 → 290 → 292), with an explicit check that
  `testSurfaceBaselines` was not silently re-recording.

## Issues and concerns

- **`isTargeted` highlighting on FX/deck drop targets is not acceptance-filtered**, unlike slots — a
  deck-sourced drag will light up an FX chain's or another deck's highlight before being rejected at
  drop. This is a structural limit of `.dropDestination`'s `isTargeted` callback (no access to the
  hovering item's value before drop resolves it), not an oversight; explained in detail above. The
  brief's "must not fire for a target that would reject" requirement is fully met for slots (the
  location it calls "the single most important mutation proof in the phase") and not fully met for
  FX/deck targets, where the drop itself is still correctly rejected and snaps back.
- **`SlotCell`'s empty-cell click and ⌥-click still silently no-op** through `capture(into:)`. This
  was already true after Task 4 and is unchanged by this work — only the copy describing these
  affordances was fixed (Task 4's SOURCE-deck references are gone). Fully rewiring or removing the
  click-based capture path was judged out of scope for a "fix the copy" deferred finding; flagging it
  here in case a future task wants to revisit it.
- Live on-device confirmation of the drag gestures (actual mouse drags in a running app) was not
  performed — this was a unit-test-level implementation task. Per the project's on-device gate
  doctrine, this should be flagged STAGED for a real drag-and-drop smoke test before being called
  CONFIRMED.

---

# Fix round 1 report

FIX_BASE `4932bdb`. Six Important findings, three with operator rulings. Fixed commit: `aba0283`.

## What I changed, per finding

**F1 (decisive) — extracted the slot drop decision into a tested seam.** Added
`ShaderDrag.accepts(source:on:isSlotFilled:withOption:)` (`ShaderDrag.swift`) — a `Source`-only
overload the original `ShaderDrag`-taking `accepts` now forwards to. Added
`SlotBankStripView.wouldAccept(_:at:)` and `wouldHighlight(at:)` (both non-`private`, same
"testable seam on the view struct, no rendering" pattern `recallTargets` already uses). The
`.dropDestination` action now calls `wouldAccept(drag, at: index)` with the real drag; the
`isTargeted` closure calls `wouldHighlight(at: index)`, which routes through `wouldAccept` with a
placeholder `.library`-sourced probe drag (sound because `accepts` returns the identical
`!isSlotFilled || option` result for every legal source once destination is `.slot` — proven by
the existing `ShaderDragTests`, and now also exercised directly). The two closures no longer
contain two independent implementations of the invariant.

**F2 (operator ruling: accept, document only) — no code change.** Added doc comments directly on
the `isTargeted:` closures in `FXChainView.swift` and `MonitorView.swift`'s `dropDestinationIfDeck`
stating: `isTargeted` receives only a `Bool`, SwiftUI resolves the hovering item's value only
inside `action` at drop time, so a deck-sourced drag lights up FX/other-deck targets it will be
correctly rejected from a moment later. Named `DropDelegate`/`DropInfo.itemProviders(for:)` as the
tested-and-rejected alternative (an API rollback off `Transferable`/`.dropDestination`, which the
brief specified deliberately) and pointed at `SlotBankStripView.wouldHighlight` as the one target
where this IS filtered correctly.

**F3 (operator ruling, overrides brief) — restored the library row `Button`.** `LibraryPanelView`'s
row is a `Button` again (`buttonStyle(.plain)`, action `instrument.load(entry.url, onto: .deck(.one))`)
with `.draggable(...)` still attached — drag and tap coexist. Not configurable: no target picker
reintroduced. Updated the struct's own doc comment to mention both gestures.
`SlotBankStripView.swift`'s "matching `LibraryPanelView`'s row pattern" comment needed NO edit — it
is accurate again now that the row is a `Button` once more; checked this explicitly rather than
assuming.

**F4 — restored the per-row tooltip.** `.help(...)` on the library row now carries both the full
name (unreadable once `.truncationMode(.middle)` cuts it) and the drag/click hint in one string,
per the finding's "carry both" instruction.

**F5 — fixed the stale FX-chain empty-state copy.** `"Load a shader with this chain selected in
the library."` → `"Drag a shader here to add it to the chain."`

**F6 (operator ruling) — ⌥-click now recalls; dead `onCapture` plumbing removed entirely.**
`SlotCell.activate()` is now `private func activate() { onRecall() }` — one line, no modifier
branch. Removed: `SlotCell`'s `onCapture: () -> Void` property, the
`onCapture: { capture(into: index) }` argument at the `SlotCell(...)` call site, and
`SlotBankStripView.capture(into:)` (the empty no-op method) entirely — not left wired with an
explanatory comment, per the finding's explicit instruction. An empty-slot click is still safe
with no guard, because `SlotBankStripView.recall(_:)` already no-ops when `SlotBank.recall`
returns nil for an empty slot. Fixed the one dangling doc-comment reference to `capture(into:)`
elsewhere in the file (the type-level "SOURCE removed" comment near the top).

## Tests covering the amended code

- **F1**: new file `App/ARShaderTests/SlotBankStripViewDropSeamTests.swift` (5 tests) —
  `testWouldAcceptAnEmptySlot`, `testWouldRejectAFilledSlotWithoutOption`,
  `testFillingOneSlotDoesNotAffectAnothersAcceptance`, `testWouldHighlightAnEmptySlot`,
  `testWouldNotHighlightAFilledSlotWithoutOption`. These call `SlotBankStripView.wouldAccept`/
  `wouldHighlight` directly — the actual production call site, not a reconstruction of it.
- **F2**: doc-comment only, no test (none applicable — the finding explicitly asked for
  documentation, not a behavior change).
- **F3/F4/F5**: covered by build success + the existing `LibraryPanelTests` suite (unchanged,
  still green) plus manual reading of the diff; no new unit test was appropriate for SwiftUI
  view-body wiring (button action target, tooltip string, static copy) that this codebase's
  existing patterns don't unit-test at that granularity either (e.g. no test asserts
  `FXChainView`'s empty-state string today). Flagged in "Issues and concerns" below.
- **F6**: covered by build success and the full suite; no existing test asserted the old ⌥-click
  behavior (confirmed by running the full suite BEFORE writing any new test for this round — still
  292/292 green with the old behavior gone), so none needed updating. No new unit test added
  either, for the same reason as F3/F4/F5: this is view-body gesture wiring, not logic the
  codebase's existing seams make testable without a bigger structural change than this fix round's
  scope.

## Commands and output

**Build after all six fixes:**
```
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing
** TEST BUILD SUCCEEDED **
```

**New F1 tests, isolated:**
```
xcodebuild ... test -only-testing:ARShaderTests/SlotBankStripViewDropSeamTests
Executed 5 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

**F1 mutation 1 — `on: .slot` → `on: .deck(.one)` inside `wouldAccept`:**
```
error: ...SlotBankStripViewDropSeamTests.swift:69: XCTAssertFalse failed
  (testWouldNotHighlightAFilledSlotWithoutOption)
error: ...SlotBankStripViewDropSeamTests.swift:46: XCTAssertFalse failed
  (testWouldRejectAFilledSlotWithoutOption)
** TEST FAILED **
```
Both the drop-accept test AND the highlight test went red — proving `wouldHighlight` really routes
through `wouldAccept` rather than being a parallel implementation. Reverted.

**F1 mutation 2 — `isSlotFilled: bank.slots[index] != nil` → `isSlotFilled: false` inside
`wouldAccept`:**
```
error: ...SlotBankStripViewDropSeamTests.swift:69: XCTAssertFalse failed
  (testWouldNotHighlightAFilledSlotWithoutOption)
error: ...SlotBankStripViewDropSeamTests.swift:46: XCTAssertFalse failed
  (testWouldRejectAFilledSlotWithoutOption)
** TEST FAILED **
```
Same two tests, red again. Reverted.

**Full suite after every fix and both reverts:**
```
xcodebuild ... test
Executed 297 tests, with 0 failures (0 unexpected) in 20.4s
** TEST SUCCEEDED **
```
297 = 292 (entering this round) + 5 new (`SlotBankStripViewDropSeamTests`). Grepped the log
explicitly for `testSurfaceBaselines` and `testLibraryTargetsCoverEveryDeckAndEveryChain` —
both still pass unchanged. Also confirmed via a full-suite run BEFORE adding any new test that
F3's and F6's behavior changes broke nothing already in the suite (still 292/292 at that point),
so no existing test needed updating — stated explicitly per the coordinator's instruction rather
than letting the count move silently.

## Files changed (commit `aba0283`)

- `App/ARShader/ShaderDrag.swift`
- `App/ARShader/SlotBankStripView.swift`
- `App/ARShader/FXChainView.swift`
- `App/ARShader/MonitorView.swift`
- `App/ARShader/LibraryPanelView.swift`
- `App/ARShaderTests/SlotBankStripViewDropSeamTests.swift` (new)
- `docs/superpowers/plans/2026-08-01-arshader-thumbnails-and-drag-drop.md` — already modified by
  the reviewer/operator before I started this round (smoke legs 34b/35/35b), not by me; included
  in this commit because it belongs with F3's fix, not because I authored the change.

## Self-review

- All six findings addressed; the three operator rulings implemented exactly as stated (deck-A
  default with no configurability, F2 documented not fixed, ⌥-click merged into recall with the
  plumbing actually removed rather than commented).
- Re-checked the one place the coordinator flagged as conditional ("update
  `SlotBankStripView.swift:604`'s comment IF it still claims..."): it doesn't need updating,
  because F3 restored the exact pattern it describes. Verified by reading it after F3 landed
  rather than assuming.
- Grepped the whole tree for `onCapture`, `capture(into:`, `"SOURCE deck"`, and `"Load onto"` after
  finishing: the only remaining `onCapture` hit is inside a doc comment narrating the fix, not live
  code; the only remaining `"Load onto"` hits are the RECALL TO picker (a different, still-existing
  control) and this fix's own comment.
- Did not touch `SlotCell`'s context menu ("Clear slot" only, from the previous round) — F6 didn't
  ask for a change there and it wasn't affected.

## Issues and concerns

- F3/F4/F5/F6 have no NEW unit test, unlike F1. These are SwiftUI view-body changes (a button
  action target, a tooltip string, a Text literal, a one-line gesture simplification) that this
  codebase does not unit-test at that granularity anywhere else either — there is no existing
  precedent (e.g. no test asserts `DeckStripView`'s "Clear" button text or `FXChainView`'s old
  empty-state copy). I did not invent a new testing mechanism for this fix round given its scope;
  flagging this so the reviewer can judge whether that consistency is sufficient or whether a
  smoke/E2E leg (the plan doc's legs 32-35b) is the intended coverage for this class of change —
  which appears to be the coordinator's own model, given they described legs 35/35b as the
  keyboard/VoiceOver-reachability coverage for F3 rather than asking for a unit test.
- F2's accepted limitation is now the second thing in this phase (after the on-device gate) that
  is explicitly "known, not going to be fixed under this API choice." Both are now recorded in
  doc comments at their exact call sites, not just in a plan document, so a future reader hits the
  explanation at the code, not just in the smoke-leg table.
