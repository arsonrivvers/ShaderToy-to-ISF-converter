# Live smoke — ARShader Milestone 2, phase 3c (thumbnails, drag-and-drop, hover preview)

**Status: PENDING — suites green, legs written and UNRUN.**

**This report supersedes `live-smoke-instrument-m2-phase3b.md`.** Phase 3b's legs are not a separate
list to run afterwards — 3c's numbering reuses them (legs 1–16, 18, 19 are 3b's, verbatim), so
running this document runs both. 3b's leg 17 ("Hidden looks are always marked") was signed on device
2026-07-31 and is deliberately absent here; that signature was never written back into the 3b report.

Also folds in the **phase 3a fix re-smoke** (legs 37–39, merged to master unsigned) and the phase 3b
smoke gate in full.

- **Build under test:** `~/Applications/ARShader.app`, installed 2026-08-02 from
  `/tmp/arshader-ddata-bank` (never `/tmp/arshader-ddata` — concurrent sessions work in the main
  checkout). It replaced a build from **2026-07-31**, which was four tasks stale.
  Under Xcode 26 the real code is in `ARShader.debug.dylib` (5.9MB), not the 58KB
  `Contents/MacOS/ARShader` stub. The installed dylib is byte-identical to the build product
  (sha256 `06f4aea8…`), and carries three string literals unique to this session's work:
  `Undo clear slot`, `original bytes preserved under`, and `persistence continues normally`,
  plus Task 9's `deckAUnit`/`deckBUnit` observation properties (24 symbols each, `nm`).
  **Reinstalled at `b61658c`** — an earlier install at `1839027` predated Task 9's live-badge fix,
  so leg 22 run against it would have "confirmed" a bug that was already fixed.
  **Verified with `nm` and `strings`, not by assumption** — note that Swift's mangler compresses
  repeated substrings, so a nested type like `SlotBank.UndoableSlotChange` appears as
  `SlotBankC08UndoableE6Change`, and an exact-substring symbol probe for it returns nothing even
  though the type is present. Long string literals are the more reliable freshness check.
- **Branch:** `m2-slot-bank` @ `41ca066`, 66 commits ahead of merge-base `02fbcd4`
- **Automated suites, all run 2026-08-02 in the foreground:**
  - **ARShader: 327 tests, 326 passed, 1 failed, 0 skipped.** The one failure is
    `testSteadyStateAllocatesNoNewTextures`, a known **pre-existing** intermittent hang (~2 of 7
    runs) unrelated to this branch — it dates to `67048d9`, Milestone 1. It now fails fast in 30s
    with a named message instead of stalling for minutes; root cause is filed and open
    (`arshader-steadystate-test-intermittent-hang-20260802`). On runs where it does not trigger,
    the suite is **327/327 in ~22s**.
  - **TrueISFEditor: TEST SUCCEEDED**, 0 skipped.
  - **ShadertoyISFKit: 312 tests, 0 failures.**
  - ⚠️ **Never judge an xcodebuild run from the console tail.** After a host restart it prints a
    per-launch summary (`Executed 175 tests, with 0 failures`) that reads as green when the run in
    fact FAILED and the real total was 327. Use
    `xcrun xcresulttool get test-results summary --path <bundle>.xcresult`.

**No leg below has been run.** Everything in this branch is **STAGED** until you run them; nothing
here is CONFIRMED. Five tasks in this branch have never been seen on device at all.

---

## First: what changed since the build you are running

The app currently in `~/Applications` is from **task 3**. Five tasks have landed since, plus two
review-driven fix waves. If you open this build expecting the one you last used, several things have
moved — this section exists so an invisible change does not read as "nothing happened".

**The slot bar is much shorter.** Cells were ~207pt tall and are now 54pt. This is the change you
asked for on device ("I can see us shrinking this bar a lot"). Cells now also **scale with the
window** between a 96pt floor and a 160pt ceiling, instead of being pinned at one size.

**The SOURCE picker is gone.** It used to choose which deck a capture read from. You now capture by
**dragging a deck's monitor into a slot**, which says the same thing with the gesture instead of a
control. **RECALL TO** survives but is now just **A | B** — it can no longer target an FX chain.

**Drag-and-drop is the new gesture layer, and it is the point of the whole phase.**
- Drag a **library row** onto a deck, onto a deck's FX section, onto MASTER FX, or onto an empty slot.
- Drag a **deck's monitor** into a slot to bottle the look you just dialled.
- A drop that would **overwrite a filled slot is refused** and shakes. Hold **⌥** to mean it.

**Clicking a library row now does nothing at all.** Drag is the only pointer path to load. This
reverted twice during review; the current rule is the original one, per your ruling.

**The library has a hover preview.** Rest the pointer on a row and a still of that shader resolves in
a well at the foot of the panel. It waits ~150ms so sweeping the list costs nothing.

**Slots show pictures**, sampled at t=2.0s, cached to disk, and surviving relaunch.

**From the merge-gate reviews, things you can only notice by looking for them:**
- **Clearing a slot is undoable** — one deep, via "Undo clear" in the cell's context menu.
- **Opening the projector no longer shows a malformed frame.** It shows one black frame instead.
- **The hover well says when it is still working** rather than showing you the previous row's still
  at full opacity as if it were the answer.
- **A bank this build cannot read is never destroyed** — the original bytes are backed up before
  anything is written over them.

---

## How to run this

Work the **Tier 1** legs first. They are the new, the destructive, and the fix-wave-touched — enough
to sign the merge. **Tier 2** is the regression sweep and can be a second sitting. You do not have to
do all 44 in one go.

Mark each leg **PASS**, **FAIL**, or **SKIP** with a note. A FAIL is not a failure of the session —
it is the session working.

---

## Tier 1 — enough to sign the merge

Destructive paths, the new gesture layer, and everything a fix wave touched.

| # | Leg | Hypothesis | Result |
|---|---|---|---|
| 32 | **A drag never destroys a look** | Dial a look, capture it, then drag a DIFFERENT library shader onto that filled slot. **The drop is refused, the slot is unchanged, and you see it refuse** — cursor during the drag, and a shake on the attempt. Then ⌥-drag the same shader: now it replaces | UNRUN |
| 46 | **Clearing a slot is undoable** | **New — added by the merge-gate review.** Right-click a filled slot ▸ Clear. Then right-click ▸ **Undo clear**: the look returns, to the SAME pad, with its dialled values. Also worth your eye: the Undo item appears on **every** cell's menu, not only the one you cleared. That is deliberate — say if it reads wrong | UNRUN |
| 4 | Recall never overwrites | Click a filled slot ten times. It recalls ten times and its contents never change | UNRUN |
| 5 | Replace and Clear are deliberate | ⌥-click replaces; hover ▸ Replace replaces; hover ▸ Clear empties. The hover-revealed Replace sits OUTSIDE the recall click target | UNRUN |
| 14 | Shrinking never destroys a look | Capture into row 2, shrink to one row, grow back: the look is there, unchanged | UNRUN |
| 18 | A failed compile does not corrupt a slot | Recall a slot whose shader has been edited into something that will not compile. The previous shader keeps playing, its dialled values are NOT overwritten, and a subsequent capture names the shader actually PLAYING | UNRUN |
| 8 | The bank persists | Quit and relaunch: every captured look is back, and so are the row count and the collapsed state | UNRUN |
| 19 | The suite never touches the real bank | After running the automated suite, relaunch: the operator's bank is untouched | UNRUN |
| 35 | Clicking a library row does NOTHING | Click a library row repeatedly: no deck changes, no FX stage appends, nothing at all happens. Then drag the same row onto deck A: it loads. **Both are now the only ways the library works** — a regression in either breaks the panel outright, and neither has ever been run | UNRUN |
| 47 | **Opening the projector shows ONE black frame** | **New — added by the merge-gate review (F4).** Set PREVIEW SCALE to 25%, then open the projector on the external display. You should see **exactly one black frame** — never a small image sitting in the corner of a black frame. A corner image means the fix did not hold | UNRUN |
| 48 | **The hover well never lies** | **New — added by the merge-gate review (F7).** With a COLD thumbnail cache, rest on a library row, then move to another and rest again. The "still working" state must stay up **continuously** until the correct still appears. If the indicator appears, vanishes, and leaves you looking at the PREVIOUS row's picture, that is the bug this leg exists for | UNRUN |
| 28 | Thumbnails never cost a frame | With the instrument playing and output OPEN, sweep the pointer down the whole library. **FPS must not drop and the program feed must not hitch.** This is the leg the entire GPU-queue isolation exists for | UNRUN |
| 36 | Projector is never soft | Open the output on the external display. Set PREVIEW SCALE to 25%. **The projected image stays sharp** while the app's monitor tiles get cheap. Close the output: the saving comes back. This is the phase's behavioural correction and the one leg with a wall as its assertion | UNRUN |
| 23 | Idle vs live survives a photo | **The finding-8 leg.** Use a near-monochrome shader (an ASCII one) AND a fully saturated one. Both must read as clearly live-vs-idle. Saturation is no longer the carrier — if you cannot tell, that is a real defect, not a preference. **Load-bearing: the slot bank has no automated colour/contrast coverage at all, so this leg is the only thing standing behind it** | UNRUN |
| 24 | Unavailable is obvious and keeps its picture | Rename a captured shader's file, relaunch: that cell is dimmed with a warning glyph, **still shows its last thumbnail**, and does not fire. You can tell WHICH look is broken | UNRUN |
| 33 | Deck monitor to slot captures the look | Dial deck B well off defaults, drag B's monitor to an empty slot, change B, then fire the slot: the dialled values come back | UNRUN |

---

## Tier 2 — the regression sweep

| # | Leg | Hypothesis | Result |
|---|---|---|---|
| 1 | Strip is always there | The bank is a strip under the monitors, not a panel. No third rail icon, no shortcut opens it. `⌘⌥1`/`⌘⌥2` still reach Library and Settings | UNRUN |
| 2 | Capture names the look | Clicking an empty cell captures the loaded shader and the cell takes that shader's name | UNRUN |
| 3 | Recall restores the LOOK | Dial a parameter well off its default before capturing. Recall: the shader loads AND the dialled values come back | UNRUN |
| 6 | Capture reads the deck you dragged | **Superseded by task 5 — the SOURCE picker is gone.** Re-scoped: dragging DECK B's monitor to a slot captures B's look, whatever is on A | UNRUN |
| 7 | RECALL TO picks the write target | **Re-scoped by task 4** — RECALL TO is now A\|B only. Set it to B and fire a slot: it loads onto deck B, never onto an FX chain | UNRUN |
| 9 | A missing file is dark, not destroyed | Rename a captured shader's file on disk, relaunch: the slot draws unavailable, clicking does nothing, and the slot is still there. Rename back: it works again | UNRUN |
| 10 | Eight cells legible at full width | At a normal window size all eight cells in a row are readable | UNRUN |
| 11 | Cells never overlap when narrow | Minimum window, Library panel open at its 260pt floor. Cells scroll horizontally rather than compressing. Clicking the extreme left and right edge of a cell fires THAT cell, never its neighbour | UNRUN |
| 12 | Recall twice does not black-frame | Fire the same slot twice. A brief recompile flash is accepted; a persistent black frame is a defect | UNRUN |
| 13 | Resize adds rows, monitors hold still | Drag the strip's top edge upward: whole rows, up to five. The monitor row does not resize and does not slide | UNRUN |
| 15 | Show mode cannot collapse the bank | Collapse by hand, then `⌘⇧P`: show mode leaves the bank exactly as it is | UNRUN |
| 16 | Collapse remembers the rows | Three rows, collapse, expand: three rows come back | UNRUN |
| 20 | Slots show pictures | Every filled slot draws a still frame of its shader, not a name-only cell. A slot captured this session gets one within a second or two, not on next launch | UNRUN |
| 21 | The still is not black | Sample time is 2.0s specifically because many shaders are black at t=0. Fill eight slots with visually different shaders: eight distinguishable, non-black stills | UNRUN |
| 22 | Live reads as live at a glance | With a slot's shader loaded on deck A, that cell has a coloured border and an **A** badge. Load the same shader on B: the badge follows. This must be readable without leaning in | UNRUN |
| 25 | Thumbnails survive relaunch | Quit and relaunch: stills appear immediately from cache, not regenerated | UNRUN |
| 26 | A broken shader does not stutter | Point a slot at a shader that will not compile. Hover and re-hover its library row repeatedly: no repeated hitch. It compiles once and the failure is remembered | UNRUN |
| 27 | Fixing a shader on disk retries it | Fix that shader in an editor and save. Its thumbnail regenerates rather than staying a permanent placeholder | UNRUN |
| 29 | Library drag to a deck | Drag a library row onto DECK A's monitor: it loads there. Same onto B | UNRUN |
| 30 | Library drag to FX | Drag a library row onto a deck's FX section, and onto MASTER FX: each appends a stage | UNRUN |
| 31 | Library drag to an empty slot | Drop fills it, no confirmation | UNRUN |
| 34 | Rejected drops are visibly rejected | Drag a deck monitor onto MASTER FX, and onto another deck. Both refuse, visibly. Drag a slot anywhere: nothing drags at all | UNRUN |
| 37 | Panel has a ceiling, not just a floor | **Phase 3a fix, merged to master unsigned.** Drag the panel divider hard right, past the window edge: the panel stops at a ceiling clamped against the window rather than starving the deck strips and pushing the mixer off-screen | UNRUN |
| 38 | Window minimum holds | **Phase 3a fix, unsigned.** Shrink the window as far as macOS allows: the mixer strip still fits and nothing is clipped | UNRUN |
| 39 | Panel width survives a window shrink | **Phase 3a fix, unsigned.** Set a wide panel, shrink the window so the panel must give way, then widen the window again: the panel returns to the width you set rather than staying pinned at its floor | UNRUN |
| 45 | The strip scales sensibly, both ways | Resize the window from its minimum to full screen. The cells grow, then **stop** — the strip never dominates the surface as it did before, and never leaves a large display mostly dead space. If the ceiling feels wrong, `maxCellWidth` is the one number to move | UNRUN |
| 49 | **Can you tell which pad is which?** | **New — promoted from a deferred finding.** The slot number is no longer drawn on the cell; it survives only in the tooltip and the accessibility label. You fire this bank **by position**. With eight filled cells, can you hit the right one without reading names or hovering? If not, the number goes back on the cell | UNRUN |

---

## Known and accepted — do not report these as bugs

| # | Leg | What you are judging | Result |
|---|---|---|---|
| 34b | The stray hover highlights are tolerable | **Accepted limitation, ruled 2026-08-01.** Drag a deck monitor slowly across the surface: both FX chains, master FX and the other deck will light up on the way, then refuse the drop. Slots — the only target that can destroy a look — are correctly filtered. Fixing the rest means rolling back the whole drag implementation. **This leg asks only whether it actually bothers you mid-set.** If it does, it gets filed as real work, not improvised | UNRUN |

---

## Notes that may explain what you see

**If a shader's first appearance feels slow, this is why.** Neither `ISFMSLCache.primary` nor
`VVMTLPool.global` is ever installed, in either app — seven assignment sites, all sitting behind
statically-false guards, so `ensureGlobals` is dead code. Every *first* sight of a shader therefore
pays a full transpile plus Metal compile. This predates the branch and is filed
(`arshader-ensureglobals-dead-msl-cache-20260802`); it is a named hypothesis for leg 28, not a
mystery. Cached second sights are unaffected.

**The hover preview's supersession is view-side only.** A request already in flight cannot be
cancelled — the service runs it to completion. The 150ms dwell means a row you merely sweep past
never issues a request at all, which is what keeps a fast scan cheap. A *deliberate slow* scan on a
cold cache will still do real work per row. That is the residual leg 28 measures.

---

## What this report does not cover

- **Client Success review** of the whole instrument surface — deferred, one combined review
  (`arshader-combined-cs-review-20260801`) rather than five stacked per-phase ones.
- **Automated visual coverage of the slot bank** does not exist. Geometry is now gated; colour and
  contrast legibility are not, which is why leg 23 is load-bearing
  (`arshader-slotbank-visual-regression-suite-20260802`).
- **A visible signal when a saved bank cannot be read.** The bytes are backed up and persistence
  continues, but the strip comes up empty with no explanation
  (`arshader-slotbank-load-failure-signal-20260802`). Unreachable with today's schema.
