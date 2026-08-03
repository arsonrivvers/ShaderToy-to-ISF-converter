# Final whole-branch review — m2-slot-bank (02fbcd4..9b21ad4, 60 commits)

Reviewer: final merge gate, phases 3b + 3c. Read the full merge diff, the ledger, and the shipped
source. No build, no test run (per brief). Everything below is marked VERIFIED (read in the source
at HEAD) or INFERRED.

---

## 1. VERDICT

**MERGE AFTER FIX WAVE** — 10 items, none Critical, all small. The branch is internally coherent:
the code does what the plan says, the preview/program split is single-sourced, the never-overwrite
invariant is enforced at the one call site that matters, and the responsive clamp is structurally
sound. The fix wave exists because five cheap defects would otherwise reach the operator's device
session, and two of them (F5, F7) change what he would be judging.

---

## 2. FIX WAVE CONTENTS

### F1 — Important — one undecodable slot destroys the whole bank, and the next capture makes it permanent

**Where:** `App/ARShader/SlotBankStore.swift:47-52` (`load()`), `:54-63` (`save()`).

**Defect:** `try? JSONDecoder().decode([Preset?].self, from: data)` is all-or-nothing across the
array — a single malformed element yields an empty bank — and nothing records that the load failed,
so the very next `capture`/`clear` calls `save()` and overwrites the still-present-but-unreadable
bytes.

**Failure scenario:** a later build adds a non-optional field to `Preset` (the type's own doc comment
at `Preset.swift:12-14` says it expects to grow: *"adding a property to a persisted Codable type
later is a migration"*). Operator launches → all 40 slots empty, no message. Operator shrugs, drags
one look into slot 1 → `onChange` → `save()` → every other saved look is gone from
`UserDefaults.standard` with no backup and no undo.

**Why this is a real asymmetry, not a hypothetical:** the codebase already recognised and fixed this
exact class one file over. `Arrangement` (`SurfaceLayout.swift:102-116`) carries a hand-written
`init(from:)` with `decodeIfPresent` *specifically* so a schema addition cannot wipe the operator's
saved arrangement. `ParamSnapshot` (`ParamStore.swift:88-93`) carries a `FailableParamValue` wrapper
*specifically* so one corrupt entry cannot fail the whole decode. `SlotBankStore` — which holds the
only irreplaceable data in the app — got neither.

**Fix:** decode `[FailablePreset?]` using the same wrapper shape as `ParamSnapshot.FailableParamValue`
(`init(from:) { value = try? Preset(from: decoder) }`) and `compactMap`, so one bad element costs one
slot. Additionally: have `load()` set a `loadFailed` flag and have `save()` refuse to overwrite (or
write to a `ARShader.slotBank.recovered` key first) when it is set.

**Secondary, same file, fold in:** `save()`'s encode failure path calls `assertionFailure` — which
*traps* in a debug build. A `ParamValue.float(.nan)` (reachable from a malformed ISF header default
via `attrib.defaultVal.doubleValue` → `syncInputs` → `exportSnapshot`) makes `JSONEncoder` throw.
Set `JSONEncoder().nonConformingFloatEncodingStrategy = .convertToString(...)` or sanitise on
capture.

---

### F2 — Important — `loadThumbnails` ignores cancellation, so the `.task(id:)` guarantee its own doc comment states is false

**Where:** `App/ARShader/SlotBankStripView.swift:275-283`, doc comment at `:252-261`.

**Defect (VERIFIED):** the doc comment at the `.task(id: bank.slots)` call site claims SwiftUI
"restarts this task — cancelling whatever sweep was still in flight". The loop body never checks
`Task.isCancelled`, and `await`ing an actor method is **not** a cancellation point (the actor method
is non-throwing and does not check cancellation on the caller's behalf). A cancelled sweep therefore
runs to completion, issuing every remaining request.

**Failure scenario:** cold thumbnail cache, bank with N filled slots. The operator drags three looks
into slots in quick succession. Each capture mutates `bank.slots`, restarting the task — but the
three older sweeps keep running. Four sweeps now issue up to 4N `.batch` requests, each of which
holds the `ThumbnailService` actor for a full ISF transpile + offscreen render + blocking readback +
PNG encode. A `.interactive` library-hover request queues behind all of them, so the hover preview
(and, on a cold cache, the bank itself) stops responding for many seconds. This compounds directly
with judged item 1 below.

**Fix:** one line at the top of the loop body:

```swift
for preset in bank.slots {
    guard !Task.isCancelled else { return }
    guard let preset, thumbnails[preset.shaderURL] == nil else { continue }
    ...
}
```

---

### F3 — Important — the only permanently-destructive slot gesture is the one with no guard at all

**Where:** `App/ARShader/SlotBankStripView.swift:691-695` (`.contextMenu { Button("Clear slot", role: .destructive, action: onClear) }`), `SlotBank.swift:54-58`, `Instrument.swift:109-112`.

**Defect:** the phase is organised around "a drag must never silently replace a dialled-in look" and
builds real machinery for it (`ShaderDrag.accepts`, the ⌥ gate, `wouldAccept`/`wouldHighlight`, a
shake on rejection, a whole test file for the seam). Meanwhile a single context-menu click calls
`bank.clear(index)`, which fires `onChange` → `bankStore.save(...)` **synchronously and immediately**.
There is no undo anywhere in the app and no confirmation.

**Failure scenario:** mid-set, the operator right-clicks a cell intending to inspect it, the menu
appears under the pointer with one item, and a reflexive second click destroys a dialled-in look —
persisted to disk before the menu has finished dismissing. Recovery: none.

**Fix (cheapest correct form):** add a one-deep undo to `SlotBank` —
`private(set) var lastCleared: (index: Int, preset: Preset)?` set in `clear`, plus
`func undoClear()` that restores it and fires `onChange`. Surface it as a second context-menu item
("Undo clear slot N", shown only when `lastCleared != nil`) and/or `⌘Z` on the strip. ~12 lines,
entirely in the two non-view files, fully testable with no view in play.

---

### F4 — Important — one malformed program frame at the instant the projector opens

**Where:** `App/ARShader/InstrumentRenderer.swift:395-413` (first lock region, `liveRes` captured),
`:447-486` (second lock region, `masters` composited), `:280-289` (`isProgramLive` setter).

**Defect (VERIFIED):** `renderFrame()` captures `liveRes = liveResolutionLocked()` under the first
lock, **unlocks**, renders the decks, then **re-locks** to composite into `masters` and to run
`masterFX.encode(..., renderSize: liveRes.size, ...)`. The `isProgramLive` setter runs on the main
actor and, between those two lock regions, can flip `programLive` and reallocate `masters` to full
output size. That frame then composites deck outputs rasterised at the *scaled* size into
*full-size* masters and runs the master FX chain at the stale scaled `liveRes`.

**Failure scenario:** PREVIEW SCALE at 25%, operator opens the projector. One frame is composited
with a 480×270 render size into 1920×1080 targets — a small image in the corner of an otherwise
black frame — and that frame is what the registered projector view presents (`OutputWindowController.swift:128`
registers the projector's own view in `monitors`, and `renderFrame` draws every registered monitor at
`:533`). One bad frame at 60fps, at the exact moment the audience first sees anything.

The ledger flagged this as a pre-existing race class (line 18) but noted this branch "moves the
trigger to the instant the projector window appears". That is exactly what makes it worth 5 lines.

**Fix:** re-read `liveResolutionLocked()` inside the SECOND lock region and use that value for the
composite and for `masterFX.encode`; if it disagrees with the `liveRes` the decks were rendered at,
skip the composite for this frame (the previous master stays up — one repeated frame instead of one
wrong one).

---

### F5 — Important — nothing gates the slot strip's HEIGHT, the axis the operator actually rejected

**Where:** `App/ARShader/InstrumentSurface.swift` (`maxCellWidth` doc comment, its own closing
paragraph), `App/ARShaderTests/SurfaceGeometryTests.swift:464-504`.

**Defect (VERIFIED, and self-reported in the shipped source):** `maxCellWidth`'s doc comment ends
with *"nothing in this suite bounds the strip's resulting HEIGHT at any window width — the axis that
was actually rejected on device."* Task 3's shipped defect was that `.aspectRatio(16/9)` turned
window width into row height and the operator said *"I can see us shrinking this bar a lot."* Task 4C
added two real rendered-geometry gates — both on WIDTH.

**Failure scenario:** a future change to `maxCellWidth`, to `slotStripCellSpacing`, to the header
padding, or to `layout.bankRows`' default reintroduces a tall bar at wide windows. The suite stays
green (cell width is still clamped correctly) and the operator finds it on device again — the third
time.

**Fix:** one assertion using machinery that already exists. Wrap the `slots:` slot of
`slotBankSurface(...)` in `.measured("slots", in: Self.space)`, read it through
`SurfaceRenderHarness.frames(...)`, and assert at 2560pt that the strip's height is at most
`SurfaceMetrics.maxCellWidth * 9/16 + <named chrome constant>` — i.e. that the ceiling actually
bounds the strip, not just the cell. ~12 lines.

---

### F6 — Minor — no test renders a FILLED slot cell; the whole thumbnail/badge/name branch is unrendered

**Where:** `App/ARShaderTests/SurfaceGeometryTests.swift:398-410` (`slotBankSurface`), `:531-550`
(`stubSurfaceForBaselines`).

**Defect (VERIFIED):** the two rendered-geometry tests construct `Instrument()`, which under
`TestHarness.isActive` backs `SlotBankStore` with `InMemoryKeyValueStore` — so every one of the 40
slots is empty. `SlotCell`'s `if let thumbnail` branch, the badge `Group`, the name plate, the
`.offset`/`.animation` shake and the `state.borderColor` overlay have never been laid out by any
test. The three PNG baselines put `Color.yellow.frame(height: 40)` in the `slots:` slot and
`Color.gray` in the `panel:` slot, so they cover none of it either.

**Failure scenario:** the thumbnail is drawn `.resizable().aspectRatio(16/9, contentMode: .fill)`
inside a ZStack that is then `.aspectRatio(.fit)`-constrained and clipped. A `.fill` child that
overflows its ZStack is the classic way a fixed-frame cell blows out its neighbours' hit areas — on
the one surface whose stated safety property is that an edge click cannot fire the wrong slot. Today
that ships with zero rendered evidence.

**Fix:** seed the harness instrument's bank before rendering — `instrument.slotBank.capture(Preset.capturing(url: <fixture>, snapshot: ParamSnapshot(params: [:])), into: 0)` — inside
`slotBankSurface(...)`, and assert `measuredRenderedCellWidth` is unchanged from the empty case.
~6 lines, and it converts "the filled path has never been laid out" into "the filled path is laid
out on every run."

---

### F7 — Minor — the hover well shows the previous shader's still, with no indication, while a request is outstanding

**Where:** `App/ARShader/LibraryPanelView.swift:221-237` (`hoverPreviewWell`), `:188-198` (`.task(id:)`).

**Defect:** `hoverPreview` is only ever replaced when a request resolves. While one is in flight the
well keeps the PREVIOUS shader's image at full opacity, looking like a settled answer for that row.
Combined with judged item 1 (supersession does not work), on a cold cache a deliberate slow scan can
leave the well seconds behind the pointer while looking correct.

**Why it belongs in this wave and not after:** smoke leg 28 exists to judge exactly this load
behaviour on device. Judging it against a well that cannot say "still working" wastes the leg.

**Fix:** a `@State private var isResolving = false` set around the service call, and
`.opacity(isResolving ? 0.35 : 1)` plus a small `ProgressView` overlay on the well. ~5 lines, fixed
height, no layout change. (Ledger line 92 already scoped it as "free at fixed height".)

---

### F8 — Minor — `wouldAccept` reads `NSEvent.modifierFlags` inline, so the ⌥ branch is untestable through the view seam and the highlight is stale

**Where:** `App/ARShader/SlotBankStripView.swift:146-149`, `:160-163`, `:424-430`.

**Defect (two consequences, one cause):**
1. `SlotBankStripViewDropSeamTests` can only ever exercise `withOption: false` — every assertion in
   that file silently depends on nobody holding ⌥ when the suite runs. **No test anywhere covers
   "⌥ held → a filled slot accepts and overwrites" *through the view seam*** (the pure-function
   version is covered in `ShaderDragTests:31`).
2. `targetedSlot` is computed once, at hover-ENTER (`:429`), from a global flag the operator can
   change at any moment. The drop re-reads it (`:410`), so the two can disagree: a dark cell (which
   on this strip reads as "will reject") can accept and overwrite. Ledger line 75 concluded "no
   data-loss path"; that is right about intent — the operator pressed ⌥ deliberately — but wrong
   that the highlight is therefore adequate. On a strip of eight visually identical cells, the ring
   is the operator's *only* pre-drop signal about a destructive action.

**Fix (do the cheap half now):** add a defaulted parameter —
`func wouldAccept(_ drag: ShaderDrag, at index: Int, withOption option: Bool = NSEvent.modifierFlags.contains(.option))` — and the same on `wouldHighlight`. Production call sites are
unchanged; the ⌥ branch becomes testable immediately; add the two missing seam tests.
**Defer the visual half to the device session:** whether a filled slot should show a distinct
"will replace" ring instead of nothing is an operator judgement, and should be added as a smoke leg
rather than decided here.

---

### F9 — Minor — a control documented as inert while projecting reallocates 16 MB per keystroke

**Where:** `App/ARShader/InstrumentRenderer.swift:253-262` (`previewScale` setter), `:320-326`
(`reallocateMastersLocked`).

**Defect (VERIFIED):** the setter guards on `newValue != renderScale`, then calls
`reallocateMastersLocked()`. While `programLive` is true, `liveResolutionLocked()` ignores
`renderScale` entirely — so the "fresh" pair is the same size as the current one. Two
1920×1080 `rgba16Float` textures ≈ 16 MB, allocated and discarded, per keystroke in the PREVIEW
SCALE field, on a control task 2 deliberately made inert while the projector is up.

**Failure scenario:** operator types "100" into PREVIEW SCALE mid-show with the projector open →
three reallocations, ~48 MB of churn, `masterIndex` reset three times, while the field is documented
to do nothing.

**Fix:** guard inside `reallocateMastersLocked()` on the resolved size actually changing:

```swift
let target = liveResolutionLocked()
guard masters.first?.width != target.width || masters.first?.height != target.height else { return }
```

Same guard fixes `outputResolution` and `isProgramLive`.

---

### F10 — Minor — `testNoRecallTargetIsAnFXChain` cannot fail

**Where:** `App/ARShaderTests/SlotRecallTargetTests.swift:16-22`.

**Defect (VERIFIED):** `LibraryTarget.deck(deck)` is `.deck` by construction, so
`if case .deck = asLibraryTarget { continue }` matches for every possible input and `XCTFail` at
`:20` is unreachable. The ledger (line 47) recorded it as "verbatim from my brief, so spec-compliant"
— spec-compliance is not test value. This is the sixth instance of the tests-that-cannot-fail class
in this phase and the only one still standing at HEAD.

**Fix:** delete it. The falsifiable content is already in `testRecallTargetsAreDecksOnly`'s
`count == 2`. If a replacement is wanted, target the thing that could actually regress: that
`SlotBankStripView.recall(_:)` calls `instrument.load(..., onto: .deck(recallTarget))` and never an
FX target — extract `recallLibraryTarget(for: DeckID) -> LibraryTarget` and pin it.

---

## 3. THE FOUR JUDGED ITEMS

### Item 1 — `.interactive` supersession has never worked

**DOES NOT BLOCK. The 150 ms dwell is sufficient to merge.** But the ledger's mechanism is wrong in
a way that matters for the eventual fix.

**What I verified in the source:**
- `ThumbnailService.render(_:)` (`:150-165`) contains **no suspension point**. `String(contentsOf:)`
  (`:153`) is synchronous; `ISFSceneLoader.load` (`:156`) is synchronous and blocking by its own doc
  comment (`ISFSceneLoader.swift:10-11`); `renderPNG` (`:161`) blocks on
  `DispatchSemaphore.wait` (`:201`). Confirmed — `render` is `async` and never suspends.
- `cancelInteractive()` (`:141-144`) is actor-isolated.
- The `.interactive` branch (`:99-104`) does `interactiveTask?.cancel()` → `Task { await self.render(...) }` → `await task.value`.

**Where the ledger (line 87) is wrong:** it states cancel "ALWAYS fires after render A already
completed and is ALWAYS a no-op", reasoning that `cancelInteractive()` "cannot begin until the actor
is free". The actor **is** free during hover A's `await task.value` — that await suspends the
actor-isolated `thumbnail(A)` job. So hover B *can* enter the actor before render A starts, and if
it does, `interactiveTask?.cancel()` lands on a Task that has not yet run, `Task.isCancelled` reads
true at `:152`, and supersession works perfectly.

**Why it nevertheless never works:** it is a race decided by executor **enqueue order**, not by
preemption. Task_A's `render` job is enqueued at the moment hover A creates it — strictly before
hover B can be enqueued, since hover B happens later in wall-clock time. FIFO ordering on the actor's
executor therefore puts render A ahead of `thumbnail(B)` every time. That is exactly consistent with
task 7's empirical result (24 trials, 0 wins) and explains why fixture duration did not move it.

**Consequence for the fix:** the ledger's framing suggests the fix is "make `cancelInteractive` reach
further." It cannot. Because `render` is already dequeued and never suspends, **no amount of extra
state (a generation counter, a `pendingInteractiveURL`) can shed it** — every such fix races the same
enqueue order and loses identically. The only service-level fix is to introduce a real suspension
point inside `render` (run the transpile off-actor via `Task.detached` and re-enter, checking
cancellation on re-entry). That is architectural and correctly out of scope.

**Is the dwell sufficient?** Yes, for the case that motivated it. VERIFIED: `waitOutHoverDwell`
(`LibraryPanelView.swift:48-55`) uses a real `do/catch`, so a cancelled `Task.sleep` returns
`.cancelledEarly`; `.task(id: hoveredURL)` cancels the previous instance the instant `hoveredURL`
changes. A pointer sweep across N rows therefore issues **zero** requests. Complete fix for a sweep.

**Residual exposure, stated precisely:**
- A *deliberate slow scan* (pointer resting ≥150 ms on each row) issues one request per row, all
  serialized. On a cold cache, ~20 rows × a few hundred ms each = seconds of backlog, during which
  the well shows a stale still with no indication (→ F7).
- A hover during the launch-time `.batch` bank sweep queues behind up to 40 renders (→ F2, which
  multiplies this).
- The GPU and the MSL compiler are shared with the live path even though the command queue is not
  (`bgCmdQueue`, verified at `:85` and pinned by `testTheServiceNeverUsesTheLiveRenderQueue`).

**Bounded by:** the disk cache — every shader renders exactly once, ever. After one pass over a
folder, hovering is instant. The pathological case is first exposure to a cold folder.

**Merge judgement:** ship it. Degrades to a slow preview, never to data loss or a crash, and is
self-limiting. Leg 28 is now the real gate — run it with F7 in place so the well can distinguish
"working" from "settled".

---

### Item 2 — `ISFSceneLoader.load` collapses two failures into one persisted verdict

**DOES NOT BLOCK. The ledger's premise is partly wrong and the blast radius is much smaller than
recorded.**

**What I verified:**
- `ISFSceneLoader.load(source:device:)` (`ISFSceneLoader.swift:37-59`) takes **source text, not a
  URL**. "Could not stage shader source." (`:45`) is a failure to write a temp `.fs` into
  `FileManager.default.temporaryDirectory` — **not** the operator's external volume. The shader file
  has already been read into memory by `ThumbnailService.render` at `:153` before this call. So the
  ledger's characterisation (line 11) of this as "a filesystem transient — slow or ejected external
  volume" is **incorrect**: it is a failure to write to the process's own temp directory, which means
  the disk is full or temp is broken — a condition under which everything else is failing too.
- The second half **does** hold: `ISFMSLSafeCreateAndLoad` (`:50`) returning nil, for any reason
  including a GPU/VRAM allocation failure, is indistinguishable from a compile error at this layer
  and maps to `!isValid` → `.shaderFailed` → **persisted** as a `.failed` file (`ThumbnailService.swift:117-120`,
  `ThumbnailCache.swift:50`). Keyed by path + mtime, so it survives restart and is cleared only by
  editing the shader. There is no UI to clear the cache.
- **The mass-poisoning scenario the ledger describes is not reachable in this branch.** It posits "a
  1,500-shader batch sweep". Nothing in the shipped code sweeps the library: `.batch` requests come
  only from `loadThumbnails`, bounded by `SlotBank.slotCount` (40); `.interactive` comes one at a
  time, gated by a 150 ms dwell. The worst realistic case is a handful of adjacent slots blacklisted
  during one VRAM squeeze.

**What this branch introduced vs inherited:** `ISFSceneLoader.load`'s two-failures-one-verdict mapping
is **inherited** (it predates the branch; `ShaderUnit` has always consumed it). What this branch
introduced is the **persistence** — `ThumbnailCache` writing `.failed` files that outlive the
process. Before this branch a transient scene-creation failure cost you one recompile.

**Blast radius:** thumbnails only. A blacklisted shader still loads, still plays, still recalls
correctly — it just draws a blank plate in its slot and no hover preview. That is cosmetic
degradation that persists, not data loss.

**Merge judgement:** file it. When it is fixed, the cheap correct fix is not to un-collapse
`ISFSceneLoader` (which would change a shared type used by the editor) but to make the persisted
failure **expire**: stamp the `.failed` file and treat one older than, say, 7 days as a miss. Two
lines in `ThumbnailCache.entry`, no cross-target risk. A "Clear thumbnail cache" item in Settings
would be the operator-facing complement.

---

### Item 3 — the slot bank ships with zero automated visual coverage

**DOES NOT BLOCK, but the ledger's FINDING OF RECORD is now only two-thirds true, and the remaining
third is worse than recorded.**

**Still true at HEAD (VERIFIED):**
- `stubSurfaceForBaselines` (`SurfaceGeometryTests.swift:531-550`) puts `Color.yellow.frame(height: 40)`
  in the `slots:` slot and `Color.gray` in the `panel:` slot. So the three PNG baselines
  (`panel-closed`, `panel-library`, `show-mode`) cover **none** of `SlotBankStripView`,
  `SlotCell`, `LibraryPanelView` or the hover well.

**No longer true (task 4C closed it):** "rendered-geometry coverage of the slot strip at zero."
`testTheCellGrowsWithTheWindowUpToItsCeiling` (`:464`) and `testTheRowHeightTracksTheDrawnCell`
(`:496`) instantiate the **real** `SlotBankStripView` inside a **real** `InstrumentSurface` at real
window widths, and `RenderedCellWidthKey` is sourced from a `GeometryReader` attached to the actual
`.frame(width:height:)` call site (`SlotBankStripView.swift:448-458`) — genuine laid-out geometry, not
a re-derivation. That is real coverage and it is correctly scoped.

**Worse than recorded, and the part worth acting on:** every one of those geometry tests renders an
**empty** bank (`Instrument()` under the harness gets an `InMemoryKeyValueStore`, so all 40 slots are
nil). No test in the branch has ever laid out a filled `SlotCell` — no thumbnail image, no badge, no
name plate, no border, no shake. See **F6**.

**What is genuinely uncovered and cannot be cheaply covered:** colour and contrast — live-vs-idle
legibility on a near-monochrome and on a saturated shader, whether `imageOpacity` 0.65-vs-1.0 reads
as a distinction, whether the red unavailable plate is distinguishable from deck B's orange at 9 pt.
Those are judgement calls a pixel diff cannot make. **Smoke leg 23 remains load-bearing** and the
ledger is right about that.

**Merge judgement:** post-merge visual-regression-suite item, with F6 done now as the cheap
down-payment.

---

### Item 4 — task 4's strip-shrink fix is STAGED, not proven

**The mechanism is sound on the argument alone, nothing in the branch defeats it, and the ledger's
"STAGED, not proven" line (40) is now partly superseded by task 4C.**

**Mechanism, re-derived:**
- `SlotCell` is sized by `.frame(width: cellWidth, height: cellWidth * 9/16)` (`SlotBankStripView.swift:401`).
  `.frame(width:height:)` with both dimensions non-nil is documented as proposal-independent: it
  proposes exactly that size to its child and reports exactly that size to its parent, regardless of
  what the parent proposed. The horizontal `ScrollView`'s unbounded proposal on the scroll axis is
  therefore structurally irrelevant to the cell — which was task 3's entire defect.
- `cellWidth` (`:478-485`) is `min(max(ideal, minCellWidth), maxCellWidth)` — a genuine clamp with
  all three values. Bounded to [96, 160] **for any input**, including a garbage or zero
  `contentColumnWidth` (guarded at `:480`). The guarantee does not depend on the measurement being
  correct; it depends only on the clamp. That is the strongest form this fix could take.
- Row pitch is derived from the same `cellWidth` (`:208-210`), so the resize drag cannot desync —
  the task-4 defect (drag reading 60 against a real ~122 pt pitch).
- **No feedback loop is possible** — I checked this specifically, because it is the obvious way a
  measure-then-resize chain goes wrong. `contentColumnWidth` is measured on the content column
  `VStack`, which carries `.frame(maxWidth: .infinity)` (`InstrumentSurface.swift`, content column),
  and `slots()` is `.fixedSize(horizontal: false, vertical: true)` — horizontal is **false**. So the
  strip's own width never influences the column's width. The 4C adjudication (ledger line 60) is
  correct.
- Chrome arithmetic reconciles exactly: `slotStripPadding*2 (16) + slotStripRecallWidth (90) +
  slotStripGapWidth*slotStripGapCount (20) + dividerWidth (1) = 127`, matching the doc comment and
  matching the `content` view's actual modifier stack.

**Empirical status has improved since ledger line 40 was written.** That line predates task 4C and
cites mutation testing against task 4's `.fixedSize`-based harness technique, which was **retired**.
`testTheCellGrowsWithTheWindowUpToItsCeiling` now asserts, through the real strip in the real
surface at two real window widths, that the **rendered** cell is 96 at 1180 pt and strictly larger
(but ≤160) at 2560 pt, and that rendered agrees with computed at both. That is not proof of the
on-device look, but it is no longer "argument only."

**What could still defeat it:** only a change that removes the exact `.frame(width:height:)` or
un-clamps `cellWidth`. Both are now gated. **Nothing else in the 60-commit diff touches the sizing
chain.**

**What the on-device check must look for** (state each as a hypothesis that can fail):

1. *"At full window width with no panel open, the eight cells are wider than at the minimum, and the
   strip is not taller than roughly one and a third times a cell."* Resize from ~1180 pt to full
   1728 pt. Cells must visibly grow (96 → ~160) and stop. If they stay at 96, the `@Environment`
   hand-down is not landing on device.
2. *"The strip's total height stops growing when the cells stop growing."* This is the axis the
   operator actually rejected and the one nothing in the suite gates (→ F5). At 1728 pt the row
   pitch should be ~96 pt and the whole one-row strip ~134 pt.
3. *"At 1728 pt with no panel, no horizontal scrollbar appears."* The arithmetic predicts 1322 pt of
   cells in a 1355 pt region — 33 pt of slack. A scrollbar means the chrome constant is stale.
4. *"At the minimum window with the library panel open, the cells sit at exactly 96 pt and the
   region SCROLLS rather than overlapping."* Predicted: 810 pt needed in ~520 pt available, so
   scrolling is the correct, designed outcome — not a defect.

---

## 4. DEFERRED-BACKLOG TRIAGE

### BLOCKS MERGE
None. (The five Important fix-wave items are cheap-and-before-the-device-session, not
merge-blocking on their own; the wave exists so the operator signs the build that merges.)

### FIX NOW, CHEAP
| Ledger | Item | Fix-wave ID |
|---|---|---|
| L18 | one malformed program frame when the projector opens | **F4** |
| L17 | `previewScale` setter reallocates 16 MB when the size is unchanged | **F9** |
| L47 | `testNoRecallTargetIsAnFXChain` is vacuous | **F10** |
| L75 | ⌥ sampled only at hover-enter | **F8** |
| L92 | no loading/stale state in the hover well | **F7** |
| L29 | zero visual coverage — the *filled-cell* half | **F6** |
| L4 | M8: queue-isolation assertion is negative-only | add `XCTAssertTrue(serviceQueue === RenderProperties.global().bgCmdQueue)` to `testTheServiceNeverUsesTheLiveRenderQueue` (`ThumbnailServiceTests.swift:95-100`) — 1 line |
| L33 | no test pins the thumbnail cache directory under the harness | add `cacheDirectoryForTesting` and assert `Instrument().thumbnailService`'s directory is under `temporaryDirectory` and never `applicationSupportDirectory`. Guards the "a test run evicts the operator's real 2,000-entry cache" defect that F5 (task 3) actually closed and that nothing currently protects — 3 lines, pure string comparison, no I/O |
| L79 | exported UTI `com.arshader.shader-drag` is not under the bundle's own prefix | `Info.plist:93` + `ShaderDrag.swift:68`. 2 lines. Worth doing before an installed build registers a squatted identifier with LaunchServices |
| — | `ShaderUnit.load(url:)`'s unreadable-file path doesn't bump `loadGeneration` (`ShaderUnit.swift:74-79`) | 1 line. Newly reachable from three call sites this branch added (library click, library drag→deck, FX drag): click row A (compile in flight), click deleted row B → error, then A's compile lands, clears `compileError`, swaps the deck **and stamps `sourceURL = A`**, lighting the wrong slot's live badge |

### FILE AND SHIP
| Ledger | Item | Note |
|---|---|---|
| L5 | M9: `renderPNG` returns without committing `cb` on the ISF-render-failure path (`ThumbnailService.swift:195-197`) | still true; low value |
| L6 | M10: `interactiveTask` never cleared on normal completion | still true; **moot** — cancelling a finished task is harmless and, per judged item 1, `cancelInteractive` is a no-op regardless |
| L7 | M11: redundant `isValid, let scene` binding (`:157`) | style |
| L11 | `ISFSceneLoader` collapses two failures | judged item 2; premise corrected; fix = expire `.failed` entries |
| L13 | undiagnosed one-off "123 tests / TEST FAILED" | log not preserved; unsettleable |
| L19 | `isProgramLive` mirrors the request, not reality — `.screen(id:)` with no screens attached pins the chain full-size with nothing projected | still true (`OutputWindowController.setDestination` sets `destination != .off` unconditionally); cost-only |
| L26 | `liveDeck` lights every slot sharing a shader URL | still true (`SlotBankStripView.swift:288-293`); correct fix needs identity beyond URL |
| L27 | live badge rides the ~2x/sec stats republish | still true; same mechanism as the row below |
| L28 | slot number no longer drawn on the cell | still true; **operator judgement — add a device leg**, on a bank fired by position this may matter |
| L29 | zero visual coverage — the colour/contrast half | leg 23 is the gate; post-merge visual-regression suite |
| L34 | per-instance UUID temp thumbnail dirs never cleaned (`Instrument.swift:80-82`) | every harness `Instrument()` leaves an empty dir in `/var/folders`; fix = one shared static temp dir per process |
| L43 | `knownCellOverflow = 3` has zero slack | still true and **deliberately so** — a tight tripwire, not a defect |
| L76 | shake timer is an uncancelled unstructured `Task` (`:413-416`) | cosmetic; two rejections on one index inside 400 ms cut the second shake short |
| L77 | `LibraryTarget.shortLabel` / `allCases` are production-dead | **VERIFIED exhaustively**: `grep -rn "shortLabel" App/` returns exactly 2 hits — the definition (`LibraryPanelView.swift:19`) and `LibraryPanelTests.swift:80`. `LibraryTarget.allCases` returns 3 — the definition and two test lines. A test gating dead code. Delete both, or comment them as reserved |
| L78 | `MonitorTile` observes stats, not the unit — and the drag payload is **frozen at body-evaluation time** | extends the ledger entry: `draggableIfCapturable` (`MonitorView.swift:294-301`) computes `payload` eagerly in the `if let`, so `.draggable`'s autoclosure closes over a value up to ~250–500 ms old. So it is not only "draggable late" — the **captured param values can be stale**. Practically narrow (a mouse drag takes longer than the republish interval), but it is the phase's headline feature capturing the wrong data. Fix = `@ObservedObject` the deck's `ParamStore`. **Deferred deliberately**: that makes a Metal-backed viewport re-evaluate on every slider tick, and this repo's render-path doctrine is one change at a time with on-device observation |
| L80 | `ShaderDragTests` local `url` shadows an instance property "at :917 / :826" | **the citation does not resolve** — the file is 142 lines. Either the line numbers are wrong or the finding is against a different file. Re-derive before acting |
| L83 | 5+6 F3/F4 "no achievable test" claim was too strong | correct as stated; the Button's "always deck A" decision is extractable. Low value |
| L90 | task 7 I3: Step 4's mutation was substituted | closed honestly — `ThumbnailServiceTests.swift:123-147` records exactly what was and was not proven. Correct resting state |
| L91 | hover-exit `cancelInteractive()` is a no-op | brief-mandated cost, no benefit, harmless |
| L93 | `accessibilityIdentifier("libraryPanel.hoverPreview")` has no consumer; no `accessibilityLabel` on the well | still true; the a11y gap is real but this is a personal instrument |
| L94 | `LibraryPanelView` grew ~74 lines | style |
| — | `ISFSceneLoader.ensureGlobals` (`ISFSceneLoader.swift:25-34`) is an unsynchronised check-then-set on two process-global statics | **new finding, pre-existing cause, amplified by this branch.** `VVMTLPool.global` is pre-set in `InstrumentRenderer.init`, but `ISFMSLCache.primary` is not. It is now reached concurrently from the `ThumbnailService` actor's executor thread and from each `ShaderUnit`'s own `compileQueue` (one per unit — deck A, deck B, every FX stage). Two threads can both read nil and both construct an `ISFMSLCache` over the same directory: a data race on a non-atomic static plus two writers on one on-disk MSL cache. Two `ShaderUnit`s already raced before this branch; the launch-time bank sweep makes it routine. **Filed rather than fixed here because `ISFSceneLoader` is shared with the editor target** and touching it is a cross-target change this wave should not carry |
| — | doc rot: `SurfaceGeometryTests.swift:265` and `InstrumentSurface.swift:46,93` reference `InstrumentView.deckStripsContent`, which no longer exists | harmless; fold in if convenient |

### ALREADY RESOLVED / NO LONGER TRUE
| Ledger | Item | Closed by |
|---|---|---|
| L12 | "an unreadable source on a slow/ejected external volume is permanently blacklisted" | **NO LONGER TRUE AS STATED.** `ThumbnailCache.key` (`:23-29`) requires `attributesOfItem(atPath:)`, which throws when the volume is gone — so `store` throws and `try?` swallows it, and **nothing is persisted**. Only a file whose *attributes* are readable but whose *contents* are not can be blacklisted (a permissions edge case), which is a far narrower condition than the entry describes |
| L35 | FINDING FOR OPERATOR: "cells are PINNED at the 96 pt floor at every window width" | **RESOLVED** by task 4C (e663888..72fb22e). `cellWidth` is a clamped range and `testTheCellGrowsWithTheWindowUpToItsCeiling` proves rendered growth 96 → ≤160 |
| L44 | "`minCellWidth` is now a misleading name — it is the cell's exact and only width" | **NO LONGER TRUE.** Task 4C reopened the width axis, so `minCellWidth` is once again a genuine minimum. Superseded by e663888 |
| L45 | stale operator-facing copy ("Click to capture the SOURCE deck", "Replace with SOURCE deck"); `currentPreset(of:)` and `SlotBank.capture` have zero production call sites | **RESOLVED** (4932bdb, aba0283). Exhaustive sweep, no truncation: `grep -rn "SOURCE deck\|onCapture" App/ docs/` → **10 hits, zero in live code** — one historical mention inside a doc comment (`SlotBankStripView.swift:707`) and nine in retired plan/spec docs. `currentPreset` now has a production call site (`MonitorView.swift:284`); `SlotBank.capture` has exactly one (`SlotBankStripView.swift:419`) |
| L46 | "cell area drops ~4.6x in one step to a size never seen on device; the 9 pt name plate eats a quarter of the cell" | **MOSTLY RESOLVED** by e663888. At the operator's real 1728 pt display cells draw ~160×90, not 96×54, so the name plate is ~1/9 of the cell height. Remaining: on-device judgement |
| L48 | `deckStripsContent` widened from private to internal solely for a test | **RESOLVED** by fd2f9f7 — the test was retired and the symbol was folded back into `deckStrips`. Only stale doc references remain (see above) |
| L61 | task 4C F1 — rendered-geometry coverage of the slot strip at zero | **RESOLVED** (1d290ed, 72fb22e). `RenderedCellWidthKey` observes `SlotCell`'s post-frame size; the brief's mutation 2 was run at the real call site and shown red |

---

### The tests-that-cannot-fail class — is it closed?

**Not closed, but no longer growing, and the one survivor is trivial.**

Sweeping the branch's test files for assertions with no reachable failure:

- **`testNoRecallTargetIsAnFXChain`** (`SlotRecallTargetTests.swift:16-22`) — **genuinely cannot
  fail.** Sixth appearance of the class; the only one standing at HEAD. → **F10**.
- **`testRecallTargetsAreDecksOnly`** (`:9-13`) — weak (asserts `DeckID.allCases == DeckID.allCases`
  through a one-line accessor) but **falsifiable**: widening `recallTargets` to `LibraryTarget`
  breaks it, and `count == 2` breaks if `DeckID` gains a case. Keep.
- **`testCancellingInteractiveWorkLeavesBatchWorkAlone`** (`ThumbnailServiceTests.swift:148-157`) —
  is essentially `testAValidShaderProducesAnImage` plus a no-op call. It **can** fail (the sticky-flag
  mutation goes red) so it is not vacuous, and its doc comment states its narrow scope honestly over
  25 lines. Acceptable resting state.
- **`testLibraryTargetsCoverEveryDeckAndEveryChain`** (`LibraryPanelTests.swift:77-82`) — can fail,
  but gates code with no production consumer (L77). Different smell, same family: coverage of dead
  code reads as coverage.
- **The residual seam:** `SlotBankStripViewDropSeamTests` covers `wouldAccept`'s *body*, not the
  `.dropDestination` closure's *use* of it. A mutation replacing `wouldAccept(drag, at: index)` with
  `true` at `SlotBankStripView.swift:410` still leaves the suite green. This is the smallest
  irreducible untested surface given SwiftUI offers no way to drive a drop in a unit test, and the F1
  fix (routing both drop and highlight through the one function) shrank it to a single guard
  expression. **Acceptable — but say so out loud rather than treating the seam as closed.**
- **The real remaining hole is not a vacuous test, it is an unexercised branch:** no test can reach
  `withOption: true` through the view seam, because the flag is read from global `NSEvent` state
  inside `wouldAccept` (→ **F8**), and no test ever lays out a filled cell (→ **F6**).

**Verdict:** the class is *managed*, not closed. Every instance is now either fixed, or documented
in the test's own doc comment with an honest statement of what it does and does not prove. That is
the right resting state for this codebase. F10 removes the last unmanaged one.

---

### Task 4C's F2 — the `PreferenceKey`/`ScrollView` disagreement

**Judged independently. Neither party is fully right; the shipped doc comments are correct; it does
not block; and it is settleable with a ~10-line experiment nobody has run.**

- **The reviewer's refutation is valid but does not reach the claim that matters.** The two cited
  counter-examples (`DrawnCellWidthKey`, `DrawnRowHeightKey`, reported from `SlotBankStripView.body`'s
  top level, whose subtree contains the cells `ScrollView`) do resolve correctly — I verified they are
  ordinary `PreferenceKey`s at `SlotBankStripView.swift:245-246`. But their **values** are
  `cellWidth` and `slotStripRowHeight`, both computed from an `@Environment` value. Neither is a
  measurement that has to propagate *out of or up through* a `ScrollView`. The two failing cases both
  are. So the reviewer refuted the **overgeneralised** claim — correctly, it was false — and left the
  narrow one untouched.
- **The implementer's 60-pass retest disposes of the settle-count hypothesis** for these two specific
  measurements. That is real evidence and it should not be waved away.
- **The narrow claim as shipped is a description, not a mechanism.** "A `PreferenceKey` value
  established by a `GeometryReader` and bubbled up through a `ScrollView` boundary did not reach an
  external listener in this harness" is honest and useful, and the doc comments explicitly disclaim
  generality. That is the correct thing to have written.

**Can it be settled from the code?** No. It needs an experiment.

**What would settle it (name this as the follow-up, do not run it now):** put a `.preference` on a
`Color.clear` that is a **direct child of the `ScrollView`'s content**, reporting a **constant** —
not a `GeometryReader`-derived value — and read it from outside.
- If a **constant** propagates but a **`GeometryReader`-derived** value does not, the boundary is
  the *measurement* (a geometry read inside a lazily/scroll-laid-out container resolving after the
  preference pass), not the `ScrollView` per se.
- If **neither** propagates, the boundary is the `ScrollView`'s own content container.

Either answer converts "observed twice" into "known", and it is ~10 lines in
`SurfaceGeometryTests`. Until then the doc comments are the right record.

---

### The `~207pt` / `~116pt` figure

Confirmed **WRONG** (read off a screenshot image's pixel width, not logical points; the real chain
gives ≈164 pt at 1728 pt). Exhaustive sweep of where it still appears:

- `docs/superpowers/plans/2026-08-01-arshader-thumbnails-and-drag-drop.md:1790` — **still misleading.**
  Bare assertion with no correction attached. Fix: append the correction inline.
- `docs/superpowers/specs/2026-08-01-arshader-responsive-surface-design.md:21` — **still misleading.**
  Same, in the spec that a future reader is most likely to trust. Fix: same.
- `App/ARShader/InstrumentSurface.swift:163` — **correctly annotated.** The `maxCellWidth` doc comment
  quotes the figure and immediately corrects it in bold. Leave.
- `App/ARShaderTests/SurfaceGeometryTests.swift:311` — a coincidental `−207pt` shortfall figure from
  the reverted `minWindowWidth` cascade. **Unrelated number, correctly documented.** Leave.

Two doc fixes, both one sentence. Fold into the wave if convenient; they are not code.

---

## 5. WHAT I COULD NOT SETTLE

1. **Whether `.onHover` on a macOS `List` (NSTableView-backed) fires exit only at the whole-list
   boundary or also on row-to-row transit** (ledger L95). If it fires per-gap, the list-level
   `.onHover` at `LibraryPanelView.swift:171-176` sets `hoveredURL = nil` constantly mid-sweep,
   which restarts `.task(id:)` on every gap — harmless for correctness (the dwell still gates the
   request) but it means `cancelInteractive()` runs continuously. **Needs the device.**

2. **Whether the 150 ms dwell is the right number.** Purely an operator feel judgement. It is a
   single constant (`LibraryPanelView.hoverDwell`) and trivially retuned. **Needs the operator.**

3. **Whether the unconditional 120 pt hover well plus padding fits the library panel at its real
   width** (ledger L95, second half). This is the "ideal width is not minimum width" class of
   question that already cost this phase two fix rounds. **Needs the device.**

4. **Whether `SlotCell`'s live-vs-idle distinction (border colour + 1.0-vs-0.65 opacity) is legible
   on a near-monochrome and on a fully saturated shader.** No pixel test can judge this. **Leg 23,
   needs the device and the operator.**

5. **Whether the slot number's absence from the cell face matters** (ledger L28) on a bank the
   operator fires by position. It survives only in `.help` and the a11y label. **Needs the operator
   — I recommend adding it as an explicit device leg rather than leaving it as a deferred minor.**

6. **The `PreferenceKey`/`ScrollView` mechanism** (task 4C F2). Unresolvable from the code as it
   stands; the decisive experiment is described above. **Needs a run.**

7. **The one-off "123 tests / TEST FAILED"** (ledger L13). Log not preserved; two clean full runs
   since. Undiagnosed, not disproven. **Needs a log I do not have.**

8. **Whether the F4 malformed frame is actually visible on the wall.** I verified the race is real
   and reachable (the two lock regions in `renderFrame` bracket an unlocked window in which
   `isProgramLive`'s setter can reallocate). I could not determine whether the projector window is
   already ordered-front and presenting at that instant, or still being created. The fix is 5 lines
   either way, which is why I put it in the wave rather than trying to settle it. **Needs the
   device to confirm or a targeted `FrameGraphTests` case to reproduce.**

9. **Any claim requiring a build.** I did not run `xcodebuild` or the suite per the brief. The
   established state — 299 tests, 0 failures, 0 skipped at HEAD — is taken as given. Every fix-wave
   item above changes test count or behaviour and needs a run afterwards; F1, F5, F6, F8 and F10
   each add or remove tests.
