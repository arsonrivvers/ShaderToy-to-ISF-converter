# Scoped re-review — final fix wave, m2-slot-bank (`9b21ad4..7fff542`)

Read-only. No build, no test run. Everything below marked VERIFIED (read in the source at HEAD or
derived mechanically from it) or INFERRED.

---

## 1. VERDICT

**MERGE AFTER 1 FIX** — F7's `isResolvingPreview` flag is cleared by a *superseded* hover task while
a newer request is still outstanding, so the well reverts to "settled at full opacity" in exactly the
cold-cache slow-scan case F7 was landed to fix. 2–3 lines. Everything else in the wave is clean; F1,
F3, F4 and the four deviations all hold up under independent verification.

One residual filed rather than fixed (F1's permanent persistence lockout, §4.2) and one correction to
the F11 refusal's *reasoning* that does not change its *conclusion* (§3.1).

---

## 2. PER-ITEM

| Item | Verdict | Clause |
|---|---|---|
| F1 | ADDRESSED | per-element `FailablePreset` + `map` (positions preserved), `loadFailed` guards the only write path, NaN sanitised, `assertionFailure` gone. New latent defect, §4.2. |
| F2 | ADDRESSED | `guard !Task.isCancelled` at `SlotBankStripView.swift:288`; test is deterministic by actor-inheritance, not by hope. |
| F3 | ADDRESSED | one-deep, cannot resurrect over live content, menu item present only when armed, persists like every other write. |
| F4 | ADDRESSED | re-read is under the same already-held lock; no second lock exists; skip path is defined black. |
| F5 | ADDRESSED | `.measured("slots")` on the real strip; ceiling 146pt vs measured 131pt; height-only mutation proved. |
| F6 | ADDRESSED | seeding landed and defaults on; the deleted assertion was correctly deleted (and the review's underlying hazard is itself unreachable — §3.2). |
| F7 | **PARTIAL** | mapping is correct and pinned; the flag's lifecycle is broken — §4.1. |
| F8 | ADDRESSED | defaulted parameter; production call sites unchanged; the two pre-existing assertions pinned to `withOption: false`. |
| F9 | ADDRESSED | guard on the RESOLVED size; empty `masters` still allocates (`masters.first` nil ≠ target). |
| F10 | ADDRESSED | deleted, in-file note, plan snippet annotated. Suite −1 as expected. |
| F12 | ADDRESSED | `Button` → `Text`; `.draggable`, `.help`, `.onHover`, `.contentShape` all retained; no orphaned `instrument.load` path (3 live call sites remain, all drop targets). Device-verifiable only (leg 35). |
| F13a | ADDRESSED | positive `=== bgCmdQueue` assertion added. |
| F13b | ADDRESSED | `cacheDirectoryForTesting`, pure string comparison. |
| F13c | ADDRESSED | `Info.plist:17` (file is 26 lines — the brief's `:104` and the review's `:93` were both wrong; implementer's correction is right). Test asserts against `Bundle.main`, so code/plist drift is caught. |
| F13d | ADDRESSED | `loadGeneration += 1` **and** `isLoading = false`; the second line is correct and cannot strand the spinner the other way (§3.4). |
| F14 | ADDRESSED | both sites annotated in place; `SurfaceGeometryTests:311` left alone as directed. |

---

## 3. THE FOUR DEVIATIONS

### 3.1 F11 REFUSED — correct conclusion, wrong supporting reason, larger true defect

**Mechanism VERIFIED.** `vendor/prebuilt/ISFMSLKit.framework/Headers/ISFMSLCache.h` opens
`NS_ASSUME_NONNULL_BEGIN` at `:15` and closes at `:88`; `@property (class,strong) ISFMSLCache * primary;`
is at `:58`, inside it. Swift therefore imports it non-optional and both `if … == nil` bodies in
`ensureGlobals` are statically unreachable. The refusal is **correct**: there is no check-then-set
race to synchronise, and a lock would have been ceremony over dead code.

**Correction to the implementer's reasoning.** It claims `ensureGlobals` "works today only because
`InstrumentRenderer.init` pre-sets `VVMTLPool.global`". That is false. `VVMTLPool.h` also has
`NS_ASSUME_NONNULL_BEGIN` at `:21` / `END` at `:119`, with `@property (class,strong,readwrite) VVMTLPool * global;`
at `:38` — so `InstrumentRenderer.swift:201`'s `if VVMTLPool.global == nil { … }` is the *same* dead
pattern. Nothing in this repo ever installs either global.

**What is actually true (VERIFIED by exhaustive grep, no truncation):**

- `ISFMSLCache.primary` is assigned at exactly 3 sites — `ISFSceneLoader.swift:32`,
  `ISFSceneSource.swift:45`, `MetalPreviewController.swift:63` — all three behind a statically-false
  `== nil` guard. **It is never installed, in either target.**
- `VVMTLPool.global` is assigned at exactly 4 sites — the same three files plus
  `InstrumentRenderer.swift:201` — all four behind the same dead guard. **Also never installed.**
- The vendored header states the intent outright: *"Class singleton, NULL BY DEFAULT — if you want to
  use this you need to populate it yourself."* (`ISFMSLCache.h:57`), and *"nil by default, and must be
  populated manually"* (`VVMTLPool.h:37`).
- So `ensureGlobals`'s doc comment ("`loadURL:` fails SILENTLY without these") is **false as written**:
  neither global has ever been installed and both targets render correctly. The function is dead in
  its entirety, not merely racy.

**(b) Does every ISF compile pay full cost?** INFERRED, yes. `ISFMSLCache` is the on-disk MSL /
binary-archive cache; with `primary` nil, `ISFMSLSafeBridge.mm`'s `[[ISFMSLScene alloc] initWithDevice:]`
+ `loadURL:` has no archive to consult, so every scene creation pays a full GLSL→SPIRV→MSL transpile
plus Metal compile. Likewise `VVMTLPool.global` nil means no shared texture pooling. I cannot see
inside the prebuilt framework to confirm the internal fallback, so this is inference from the header
contract, not verification. **It bears directly on smoke leg 28** — the thumbnail sweep's per-shader
cost is a full compile every time a shader is first seen, and the launch-time bank sweep pays it 40×
on a cold PNG cache. Filed, per the brief; not proposed as a fix here.

### 3.2 F6 DELETED — correct, and the review's hazard is itself unreachable

**Seeding VERIFIED.** `slotBankSurface(instrument:layout:isFilled:)` (`SurfaceGeometryTests.swift:406`)
defaults `isFilled: true` and captures into slot 0 before constructing the view; all four callers
(`:442`, `:455`, `:465`, `:538`) take the default, and row 0 / column 0 is the cell
`RenderedCellWidthKey` reports from. The filled branches now laid out on every run: the 0.22 plate,
the name plate (`preset?.name`), `state.borderColor`, the badge `Group`, `helpText`'s filled path and
the filled `accessibilityLabel`.

**The deletion was right.** `SlotCell` is wrapped in `.frame(width: cellWidth, height: cellWidth * 9/16)`
at the `ForEach` call site (`SlotBankStripView.swift:427`), which reports exactly that size to its
parent regardless of the child — so `measuredRenderedCellWidth` is structurally immovable from inside
the cell. VERIFIED by reading the modifier chain, independent of the implementer's mutation.

**Was there a third option?** No useful one, and the review's own failure scenario is unreachable:
the ZStack carries `.aspectRatio(16/9, contentMode: .fit)` and then `.clipShape(RoundedRectangle(...))`
*inside* the fixed frame, so an overflowing `.fill` thumbnail is clipped and cannot reach a
neighbour's hit area. An achievable assertion would have required new instrumentation *inside*
production `SlotCell` (a preference reporting the ZStack's own size) purely to observe a value the
frame already pins — the L77 smell the review itself flagged. Deletion is the correct call.

**Two honest gaps the wave discloses only partially.** The seeded URL is `/tmp/harness-filled-slot.fs`,
which does not exist, so `isAvailable` is false and the cell renders in the **`.unavailable`** state.
The `if let thumbnail` branch — the *specific* thing the review's F6 rationale named — is still never
laid out (nothing loads thumbnails in a static harness render), and the live-deck capsule badge branch
is not either. The fix-wave report's own list is accurate and does not claim otherwise, but the item's
motivating scenario is not covered. Not worth acting on given the clipping argument above; worth
knowing.

### 3.3 F1 `map` vs `compactMap` — correct, and the deviation is load-bearing

VERIFIED. `decoded.map { $0?.value }` (`SlotBankStore.swift:93`) preserves index alignment;
`compactMap` would have dropped both the JSON-`null` empty slots *and* the failed elements, shifting
every later look left — on a bank fired by position, that silently moves every look to the wrong pad.
`ParamSnapshot`'s `compactMapValues` precedent is on a dictionary where the key *is* the position, so
the hazard genuinely does not transfer. The `lost` count at `:94` correctly distinguishes
"element was JSON null" (not a loss) from "element was present and unreadable" (a loss).

Decoder mechanics VERIFIED: the `try?` is inside `FailablePreset.init(from:)`, so the unkeyed
container's element decode *returns successfully* and its index advances — one bad element cannot
desynchronise the rest of the array.

### 3.4 F13c's `:17` and F13d's second line — both correct

- `Info.plist` is 26 lines; `UTTypeIdentifier` is at `:17`. Both cited line numbers upstream were
  wrong. VERIFIED.
- F13d's `isLoading = false` **cannot** strand the spinner hidden while a load is genuinely in flight.
  VERIFIED by reading `ShaderUnit.load`/`apply`: the statement runs synchronously in `load(url:)`
  after `loadGeneration += 1`, at which instant the only in-flight compile belongs to a now-superseded
  generation whose `apply` will fail the `guard generation == loadGeneration` at `:110` and never set
  `isLoading` again. `pendingSourceURL` is deliberately not reset and cannot leak, for the same reason.

---

## 4. NEW BREAKAGE

### 4.1 F7 — the resolving flag is cleared by a superseded task (**the one fix**)

`LibraryPanelView.swift:223-238`. `isResolvingPreview` is a single `@State` flag set to `true` after
the dwell and cleared by a `defer` — but `.task(id: hoveredURL)`'s cancellation does not stop the
awaited render (the review established `ThumbnailService.render` has no suspension point), so a
superseded instance survives to run its own `defer`.

**Failure scenario (VERIFIED by reading, reachable today):** cold thumbnail cache; render ≈ several
hundred ms; dwell 150 ms.

1. Pointer rests on row A → dwell → `isResolvingPreview = true` → suspends in `thumbnail(A)`.
2. At t≈200 ms pointer moves to row B. Instance 1 is cancelled but stays suspended. Instance 2 dwells
   150 ms, sets the flag `true` again (no-op), suspends in `thumbnail(B)` behind A on the actor.
3. Render A finishes → instance 1 resumes → hits `guard !Task.isCancelled` → returns → **its `defer`
   sets `isResolvingPreview = false`** while B is still outstanding.
4. Well state flips to `.settled`: the previous row's still, at full opacity, no spinner, for the whole
   of render B.

That is precisely the defect F7 exists to remove, in precisely the scenario the review cited as its
motivation ("a deliberate slow scan on a cold cache"), and it is *actively worse* than pre-F7: the
spinner appears and then vanishes mid-wait, which reads as "resolved" rather than as "no signal".

Smoke leg 28 is the stated reason F7 was pulled into this wave. As shipped, leg 28 will be judged
against a well that still lies in the case it was meant to cover.

**Fix (2–3 lines, no new surface):** give the flag a generation.

```swift
@State private var previewGeneration = 0
…
previewGeneration += 1
let generation = previewGeneration
isResolvingPreview = true
defer { if previewGeneration == generation { isResolvingPreview = false } }
```

The existing three `wellState` tests still apply unchanged; the lifecycle remains untestable without
hosting the view, as the wave report already discloses.

### 4.2 F1 — `loadFailed` can lock persistence off permanently and silently (file, do not fix now)

Answering the brief's question directly: **yes, there is a path where `loadFailed` sticks true and the
operator can never save again — and it is the exact schema-migration scenario F1 was written for.**

`loadFailed` is set only in `load()`, never cleared, and `load()` is called once per process from
`Instrument.init`. It is therefore re-derived from the *same stored bytes* on every launch. Nothing in
the app clears the key, and `lastFailureReasonForTesting` has **no production consumer** (VERIFIED by
grep: only `SlotBankStoreTests`, plus the unrelated `ThumbnailService` property of the same name).

**Failure scenario:** a future build adds a non-optional property to `Preset` — which `Preset`'s own
doc comment says to expect, and which is the trigger F1 cites. Every stored element now fails
`FailablePreset`'s decode → `lost == 40` → `loadFailed = true` → 40 empty slots *and* `save()` refuses
for the session. The operator captures eight looks during a set, quits, relaunches: same bytes, same
failure, all eight gone. Repeat forever. No message anywhere. Recovery requires
`defaults delete <bundle> ARShader.slotBank` from Terminal.

Compared with pre-wave behaviour this trades "lose the old bank once, keep persisting" for "keep the
old bank forever, never persist again". Defensible as the safer half of the trade — but it is a second
bug, not the absence of one, and the review's own F1 text offered the escape valve the implementer did
not take (*"or write to a `ARShader.slotBank.recovered` key first"*).

**Not merge-blocking:** unreachable with today's shipped `Preset` schema and today's binary. It needs
either a future schema change or genuine byte corruption. File it with a one-line remedy — write to a
`.recovered` side key and clear `loadFailed`, or surface the reason in the UI — so the next build that
changes `Preset` does not ship the lockout.

### 4.3 Everything else — no breakage found

- **Concurrency:** the wave introduces **zero** new `Task`s, `Task.detached` or `DispatchQueue` uses in
  `App/ARShader/` (VERIFIED: `git diff 9b21ad4..7fff542 -- App/ARShader/ | grep '^+'` for those
  constructs returns nothing). No new retain cycles: `Instrument`'s `onChange` closure is `[weak self]`
  (`Instrument.swift:109`), and the closure now captures the `SlotBankStore` *class* instance — which is
  the whole point of the struct→class change, since a struct copy would carry a pre-`loadFailed` value.
  VERIFIED.
- **`didRasteriseDecksForTesting`:** nil in production, never written there. In the test it forms a
  transient renderer↔closure cycle broken on the next line; no throwing call sits between, so it cannot
  leak on a failure path. Inert.
- **F4 deadlock:** `liveResolutionLocked()` (`InstrumentRenderer.swift:313-314`) reads three stored
  properties and takes no lock; the re-read at `:495` is inside the second lock region (`:482`–`:543`).
  There is no second lock anywhere in the frame path. The test's callback fires in the *unlocked* window
  (`:443`–`:482`), so flipping `isProgramLive` from it acquires the lock cleanly. VERIFIED.
- **F4 "black, not garbage":** `clearToOpaqueBlack(masters[current], in: cb)` runs *before* the staleness
  branch and `masterIndex = current` afterwards, so the presented master is a cleared texture in every
  case. The implementer's supporting claim also holds *because of F9*: `reallocateMastersLocked()` now
  no-ops when the resolved size is unchanged, so `compositeRes != liveRes` implies a reallocation
  actually happened and `masters` really does hold undefined contents. VERIFIED.
- **F3 undo cannot resurrect over live content:** `slots` is `private(set)`; `capture`, `clear` and
  `undo` are its only mutators; `capture(into:)` disarms an undoable at the same index and `undo()`
  disarms itself. So `undo()` can only ever write into an index that is currently nil (or, for
  `.replaced`, into the replacement it is explicitly undoing). A capture into a *different* index leaves
  the undo armed and correct. VERIFIED. Menu item presence is gated by `if let undoTitle`
  (`SlotBankStripView.swift:735`), fed from `bank.undoable?.menuTitle` on an `@ObservedObject` bank
  (`:104`), so it appears and disappears live. `undo()` → `onChange` → `save()` → refuses under
  `loadFailed`, consistent with every other write.
- **Deployment target:** nothing above macOS 13.0. `ProgressView`/`.controlSize` (10.15+), `UTType`
  (11+), `Bundle.object(forInfoDictionaryKey:)`, `Task.isCancelled`, `addTeardownBlock` all fine.
- **Test accounting:** +27 / −1 reconciles exactly (4 renderer, 3 library panel, 1 drag, 1 shader unit,
  5 store, 4 drop-seam, 7 slot bank, 1 geometry, 1 thumbnail service; −1 recall target) → 299 + 26 = 325.
  No test weakened: the two edited drop-seam assertions gained an explicit `withOption: false`, which
  *removes* an ambient-state dependency; the thumbnail queue test gained a positive assertion. Nothing
  skipped.
- **New tests hit real production call sites.** `wouldAccept`/`wouldHighlight`/`loadThumbnails` are the
  real view methods; `renderFrame`/`isProgramLive`/`previewScale` are the real renderer; `wellState` is
  the single source `hoverPreviewWell` itself calls; the UTI test reads the host app's real `Info.plist`.
  I found **no** new test that cannot fail. The weakest is `testOptionDoesNotChangeAnEmptySlotsAnswer`
  (falsifiable — `ShaderDrag.accepts` rejecting an empty slot under ⌥ breaks it — but low value).

### 4.4 Mutation-proof audit — all quotes reconcile

I cross-checked every quoted line number against the shipped tests, and against the tree as it stood at
the commit each mutation was run on.

- 24 of 26 quoted line numbers land exactly on the assertion the report attributes to them, at the
  call-start line, with matching message text. Including the two that look wrong at HEAD and are not:
  the F2 proof's `:99` is the `XCTAssertEqual(compiles, 0, …)` line **at `26cdbd7`** (F8's tests, added
  later in `0428584`, pushed it to `:135`); the F6 probe's `SlotBankStripView.swift:752` is inside
  `helpText`'s filled branch **at `df48a58`** (F8's doc comment, added later, pushed it to `:766`).
  Both are provenance-consistent, which is the opposite of a substituted mutation.
- The two `SurfaceGeometryTests` quotes (`:493`, `:545`) use call-*end* lines where every other quote
  uses call-*start*, a consistent +2 offset against a file that is byte-identical from `df48a58` to
  HEAD. Most likely a 2-line edit above the tests between running the mutation and committing. Not a
  substitution: the **numbers** cross-check arithmetically and exactly — `268.125 × 9/16 = 150.82`,
  `+ 41pt` measured chrome `= 191.82`, matching the quoted `191.8203125`; and the header-padding
  mutation's `+72pt` on the measured 131pt strip gives the quoted `203.0`. Fabricated output does not
  land on two independent identities.
- Ceiling constant checks out: `maxCellWidth (160) × 9/16 + 56 = 146.0`, matching every quoted
  comparison value.

### 4.5 Two cosmetic notes, not findings

- `LibraryPanelView.swift:183` still opens *"a row that already carries a click (the Button action)"* —
  the Button it names was removed by F12 in the same commit.
- The F14 correction block in `2026-08-01-arshader-responsive-surface-design.md` swallows the section's
  next sentence into the blockquote (*"…doc comment. Vertical space is the scarce resource…"*).

### 4.6 Evidence is not in the repo

`7fff542`'s message says it committed the fix-wave report, but `.gitignore:18` ignores `.superpowers/`.
The report — and this re-review — are on disk and untracked. Do not merge on the assumption that the
mutation evidence travels with the branch.

---

## 5. RESIDUALS FOR THE DEVICE SESSION

Phrased as things the operator can look for.

1. **Leg 28, hover well.** As shipped, expect the spinner to appear and then *vanish* while the well is
   still showing the previous row's image, on a cold folder scanned slowly. That is §4.1, not a
   thumbnail-service problem. If §4.1 is fixed first, the assertion becomes: *the spinner stays up
   continuously from the moment the dwell fires until the correct still appears.*
2. **Leg 35, library row.** Click a row repeatedly: nothing at all happens. Then, from the same row,
   (a) drag it onto deck A — it loads; (b) rest the pointer on it — the well resolves. Both gestures now
   have no fallback, so if either fails on device the panel is unusable, not merely degraded. Only
   structurally verified here (SwiftUI `List` + plain `Text` + `.contentShape`), never run.
3. **F4, projector open.** With PREVIEW SCALE at 25%, open the projector while something is playing.
   Hypothesis that can fail: *exactly one black frame appears, never a small image in the corner of a
   black frame.* If a garbage frame appears instead of black, the reallocation-before-clear ordering is
   wrong.
4. **F3, undo placement.** The "Undo clear slot N" item appears in **every** cell's context menu, not
   just the affected one. Deliberate (the cleared cell is the least likely one to be right-clicked next)
   but it is a judgement call — right-click an unrelated cell after a clear and decide whether the item
   reads as confusing.
5. **First-load latency.** Per §3.1, no MSL cache is installed in either target, so every first sight of
   a shader pays a full transpile + Metal compile, and the launch-time 40-slot sweep pays it once per
   distinct shader. If leg 28's cold-folder timings look worse than expected, that is the cause, not the
   thumbnail service's concurrency policy.
