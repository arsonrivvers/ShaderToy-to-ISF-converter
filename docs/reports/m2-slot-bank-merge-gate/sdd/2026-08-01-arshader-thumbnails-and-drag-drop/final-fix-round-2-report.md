# Final fix round 2 — m2-slot-bank (`7fff542..e318f0a`)

Single implementer, worktree `.worktrees/m2-slot-bank`. Three items from the re-review's merge
gate: the blocker (F7's flag), F1's follow-on lockout, and two cosmetic doc corrections.

**Suite:** ARShader **327** tests, 0 failures, 0 skipped (325 → 327: +1 item 1, +1 net-new item 2).

**Commit:** `e318f0a` on `m2-slot-bank`, parent `7fff542`.

---

## Item 1 (the blocker) — F7's resolving flag cleared by a superseded task — **ADDRESSED, with a deviation**

`App/ARShader/LibraryPanelView.swift`.

**The fix as specified — generation-stamping `isResolvingPreview` in place, as `@State` — does not
work, and I caught this only by testing it.** The re-review's suggested shape compiles and reads
correctly, but a test that constructs a `LibraryPanelView` directly and drives two overlapping
calls (the only way to reach the REAL call site rather than re-derive its logic) observed every
`@State` write as silently discarded — confirmed with debug prints: `previewGeneration += 1`
followed immediately by a print showed `gen=0`, and `isResolvingPreview = true` followed by a
print of the same property showed `false`, **within the same synchronous call**. `@State`'s
storage only exists inside a live SwiftUI view graph; a struct value constructed directly (as any
non-hosting test must) gets a box whose writes go nowhere observable.

**Deviation:** extracted `hoverPreview` / `isResolvingPreview` / `previewGeneration` out of
`LibraryPanelView`'s `@State` into a new `HoverPreviewResolver: ObservableObject`
(`LibraryPanelView.swift:69-128`), following the `LibrarySelection` pattern already in this exact
file (also an `ObservableObject`, also held via `@StateObject`, also directly testable). The view
now holds `@StateObject private var hoverResolver = HoverPreviewResolver()` and reads
`hoverResolver.hoverPreview` / `hoverResolver.isResolvingPreview` in `hoverPreviewWell`.
`@Published` drives the same live view updates `@State` did — no behavioural change, only where
the storage lives. `resolveHoverPreview(url:render:)` is the real body of the `.task(id:)` closure,
with `render` as an injected function (same shape as `SlotBankStore`'s injectable `defaults`) so a
test can substitute a controllable stand-in instead of the real `ThumbnailService` actor call.

The generation guard itself is exactly as specified:
```swift
previewGeneration += 1
let generation = previewGeneration
isResolvingPreview = true
defer { if previewGeneration == generation { isResolvingPreview = false } }
```

**Test:** `LibraryPanelTests.testASupersededHoverInstanceDoesNotClearTheFlagWhileANewerOneIsOutstanding`.
Constructs a `HoverPreviewResolver` directly, drives two overlapping `resolveHoverPreview` calls
gated by a private `RenderGate` actor (a one-shot async gate exposing `waitUntilArrived()` /
`waitToBeReleased()` / `release()`, so the test can confirm each render is genuinely in flight
before proceeding — deterministic by construction, not by hope). Sequence: A starts and is
confirmed in flight → A is cancelled (simulating SwiftUI superseding it) → B starts and is
confirmed in flight (both now outstanding, generation 2 current) → A is released and finishes
(takes the cancelled-early-return path, but its `defer` still runs) → asserts the flag is STILL
true (B is still outstanding) → B is released and finishes → asserts the flag is now false.

**Mutation (reverted):** `defer { if previewGeneration == generation { isResolvingPreview = false } }`
→ `defer { isResolvingPreview = false }`:
```
LibraryPanelTests.swift:241: XCTAssertTrue failed - row B's request is still outstanding — A
    finishing (even cancelled) must not clear the flag out from under it
→ 1 failure, the exact assertion this test exists to pin
```

**Also corrected:** `LibraryPanelView.swift:162-166`'s doc comment on `WellState`, which claimed
the flag's lifecycle "lives inside a `.task(id:)` closure with no seam a unit test can reach" —
true before this fix, false after.

---

## Item 2 — F1's `loadFailed` could lock persistence off permanently — **ADDRESSED, as specified**

`App/ARShader/SlotBankStore.swift`.

On decode failure (both the whole-blob-failure and the lossy-element paths), `load()` now calls
`backUpUnreadableBytes(_:reason:)` (`:125-132`), which:
1. Writes the ORIGINAL raw bytes to a dated backup key (`unreadableBackupKey(on:)`, `:113-117`:
   `"ARShader.slotBank-unreadable-<ISO8601 full date>"` — dated rather than per-failure-unique so
   repeated failures on the same day collapse into one backup key rather than littering a new one
   per launch).
2. Records the backup key in `lastUnreadableBackupKeyForTesting` (new, `:74`, deliberately NOT
   cleared by `save()` — the only handle a test or an operator has on which key holds the bytes).
3. Sets `lastFailureReasonForTesting` with the backup key named in the message.

`save()` (`:134-147`) no longer has any `guard !loadFailed` — the old permanent refusal is gone
entirely. `loadFailed` itself is retained as a purely informational flag (doc comment rewritten,
`:50-60`, to record why the old sticky-refusal design was replaced).

**Necessary consequence, disclosed rather than hidden:** the two existing tests that asserted the
OLD refusal behavior (`testALossyLoadTakesSaveOutOfServiceRatherThanOverwritingTheStoredBytes`,
`testWhollyCorruptStoredDataAlsoTakesSaveOutOfService`) asserted exactly the lockout this item
removes by design. I renamed and rewrote both to assert the NEW contract (the backup key holds the
original bytes) rather than leaving them red or deleting them outright — this is the item's own
stated design ("Net effect: nothing is ever lost, nothing is ever silently refused"), not a
deviation from it. `SlotBankStoreTests.swift`.

**Tests (3 total — the brief's two, plus the renamed pair covers both failure shapes):**
- `testALossyLoadBacksUpTheOriginalBytesUnderADatedKey` — per-element decode failure backs up.
- `testWhollyCorruptStoredDataAlsoBacksUpTheOriginalBytes` — whole-blob decode failure backs up too.
- `testASaveImmediatelyAfterAFailedLoadSucceedsAndIsReadableBack` — save after a failed load
  actually lands on the live key, and a FRESH `SlotBankStore` (not just the in-memory instance)
  reads it back correctly, with `loadFailed` false on that fresh read.

**Mutation proofs (2, both reverted):**

1. Backup write removed (`defaults.set(data, forKey: backupKey)` commented out):
   ```
   SlotBankStoreTests.swift:89:  XCTAssertEqual failed: ("nil") is not equal to
       ("Optional(19 bytes)") - the ORIGINAL bytes... must survive under the backup key
   SlotBankStoreTests.swift:104: XCTAssertEqual failed: ("nil") is not equal to ("Optional(8 bytes)")
   → 2 failures, exactly the two backup tests — nothing else moved
   ```
2. Old permanent refusal reinstated (`guard !loadFailed else { return }` at the top of `save()`):
   ```
   SlotBankStoreTests.swift:119: XCTAssertNotEqual failed - the live key must actually take the
       new capture, not stay refused
   SlotBankStoreTests.swift:124: XCTAssertEqual failed: ("nil") is not equal to
       ("Optional(ParamValue.float(0.6))") - must survive a FRESH load
   SlotBankStoreTests.swift:127: XCTAssertFalse failed - the bytes just written ARE readable
   → 3 failures, all in the one test this guards
   ```

No UI was built for this — backing up and resuming persistence is the whole scope, per the brief.

---

## Item 3 — two cosmetic doc corrections — **ADDRESSED**

a. `LibraryPanelView.swift:194-199` (line moved from `:183` after item 1's edits above it). Was:
   *"a THIRD gesture on a row that already carries a click (the Button action) and a drag."*
   F12 removed the Button in the SAME commit this comment shipped in, so "carries a click" was
   stale from the moment it landed. Corrected to: *"a SECOND gesture on a row that is otherwise
   inert (F12 removed the Button — no click path at all) and carries only a drag."*

b. `docs/superpowers/specs/2026-08-01-arshader-responsive-surface-design.md:29-34`. The blockquote
   (`> ...`) ran directly into the following sentence with no blank line, so CommonMark's lazy
   continuation rule folded *"Vertical space is the scarce resource..."* into the blockquote as
   well. Inserted a blank line after *"Authoritative version: `SurfaceMetrics.maxCellWidth`'s doc
   comment."* so the blockquote terminates there and the following sentence renders as its own
   paragraph, as the surrounding prose clearly intends.

No tests, per the brief.

---

## Verification

```
$ grep -rn "DEBUG\|MUTATION PROBE\|MUTATION:" App/ARShader App/ARShaderTests --include="*.swift"
(no output) → every debug print and mutation probe removed, 0 residual
```

Files touched (exactly the three items, nothing else):
```
App/ARShader/LibraryPanelView.swift
App/ARShader/SlotBankStore.swift
App/ARShaderTests/LibraryPanelTests.swift
App/ARShaderTests/SlotBankStoreTests.swift
docs/superpowers/specs/2026-08-01-arshader-responsive-surface-design.md
```

Final full run, ARShaderTests target, `-derivedDataPath /tmp/arshader-ddata-bank`:
```
Test Suite 'All tests' passed
	 Executed 327 tests, with 0 failures (0 unexpected)
```

## What I did NOT do

- Did not touch `App/ISFRuntime`, TrueISFEditor, or anything outside the three items' files.
- Did not build any UI for item 2's backup signal (explicitly out of scope per the brief — filed
  separately per the re-review).
- Did not run the TrueISFEditor test target — zero files under its target changed, so it is
  provably unaffected; not re-run to keep this round's window tight.
- No on-device verification. Item 1 in particular ("does the well now stay lit continuously through
  a slow cold-cache render") is a device question — the fix is gated by a real mutation-proven
  test either way, but leg 28 is still the on-device word on it.
