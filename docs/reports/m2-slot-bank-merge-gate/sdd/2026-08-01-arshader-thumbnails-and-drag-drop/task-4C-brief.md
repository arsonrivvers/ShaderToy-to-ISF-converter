### Task 4C: Clamp the slot cell instead of fixing it

**Added 2026-08-01**, after the operator asked whether the surface could scale by viewport
percentage. Executes after Task 4 closes and before Task 4B. Full responsive pass is deferred:
`docs/superpowers/specs/2026-08-01-arshader-responsive-surface-design.md`.

**Files:**
- Modify: `App/ARShader/InstrumentSurface.swift` — `SurfaceMetrics` gains a cell size RANGE
- Modify: `App/ARShader/SlotBankStripView.swift` — the cell frame and the row-height derivation
- Test: `App/ARShaderTests/SurfaceGeometryTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SurfaceMetrics.maxCellWidth`, and a `slotStripRowHeight` that is a function of the drawn cell rather than a constant.

**Why.** This surface has now been burned at both extremes in the space of two tasks. Task 3 shipped
`.frame(minWidth: 96, maxWidth: .infinity)` — a floor with infinite growth — and because
`.aspectRatio(16/9)` couples the axes, width percentage drove height: ~207pt cells, ~116pt rows, and
the operator's *"I can see us shrinking this bar a lot."* Task 4 fixed it with
`.frame(width: 96, height: 54)` — exact, forever — which the reviewer immediately flagged as *"cell
area drops ~4.6× in one step to a size never seen on device."* On a large display that is a tiny
strip with dead space beside it.

`.frame(minWidth:idealWidth:maxWidth:)` is `clamp()`. Both failures used only two of the three values.

- [ ] **Step 1: Write the failing tests**

Extend the existing production-coupled test from Task 4's fix round (the one that renders the real
`SlotBankStripView` inside a real `InstrumentSurface`) — do NOT write a new stub.

```swift
    /// The cell grows with the window, and STOPS. Task 3 shipped a floor with infinite growth and
    /// the operator rejected the result on device; task 4 shipped an exact size and the reviewer
    /// flagged that it is tiny on a large display. Both extremes are wrong; this is the range.
    func testTheCellGrowsWithTheWindowUpToItsCeiling() throws {
        let narrow = measuredCellWidth(windowWidth: SurfaceMetrics.minWindowWidth)
        let wide   = measuredCellWidth(windowWidth: 2560)

        XCTAssertEqual(narrow, SurfaceMetrics.minCellWidth, accuracy: 0.5,
                       "At the window minimum the cell sits on its legibility/hit-target floor")
        XCTAssertGreaterThan(wide, narrow,
                             "A wider window must give a bigger cell — a fixed cell wastes a "
                             + "large display, which is what task 4 shipped")
        XCTAssertLessThanOrEqual(wide, SurfaceMetrics.maxCellWidth,
                                 "…but never past the ceiling, or the strip eats the monitors "
                                 + "again — the defect the operator reported on device")
    }

    /// The row height must follow the DRAWN cell, not a constant, or the resize drag desyncs from
    /// what it is dragging. Task 4 found the drag reading 60 against a real ~122pt pitch.
    func testTheRowHeightTracksTheDrawnCell() throws {
        for windowWidth in [SurfaceMetrics.minWindowWidth, 1600, 2560] as [CGFloat] {
            let cell = measuredCellWidth(windowWidth: windowWidth)
            let row  = measuredRowPitch(windowWidth: windowWidth)
            XCTAssertEqual(row, cell * 9.0 / 16.0 + SurfaceMetrics.slotStripCellSpacing,
                           accuracy: 0.5,
                           "row pitch must equal the drawn cell's height plus the row gap")
        }
    }
```

`measuredCellWidth` / `measuredRowPitch` are helpers over the existing harness — reuse whatever Task
4's fix round built rather than inventing a second measurement path.

- [ ] **Step 2: Run — expect failure** (`maxCellWidth` does not exist; the cell is fixed so `wide == narrow`).

- [ ] **Step 3: Add the range**

```swift
    /// The cell's legibility and hit-target floor. Below this the 9pt name is unreadable and, at
    /// ~31pt, hit areas overlapped badly enough that an edge click fired the NEIGHBOURING slot
    /// (phase 3b). Absolute, never a percentage — macOS text scales with the user's system setting,
    /// not with the window.
    static let minCellWidth: CGFloat = 96

    /// The ceiling. Without one, `.aspectRatio(16/9)` turns window width into row HEIGHT and the
    /// strip eats the monitor row — exactly what the operator rejected on device.
    static let maxCellWidth: CGFloat = 160
```

Then the cell frame becomes `.frame(minWidth: .minCellWidth, maxWidth: .maxCellWidth)` with the
aspect ratio deriving height, and **`slotStripRowHeight` becomes a function of the drawn cell width**
rather than a constant. The resize drag divides by it (`SlotBankStripView.swift`, the
`DragGesture`), so a constant that no longer matches the drawn pitch desyncs the drag from what it
is dragging — Task 4 already found exactly that (60 against a real ~122).

- [ ] **Step 4: Run the tests — expect PASS.** Then the full suite plus the three geometry gates.
Nothing about deck rasterisation, master size, or cue behaviour may move.

- [ ] **Step 5: Re-derive `knownCellOverflow`.** Eight cells at the FLOOR is what the window minimum
must accommodate, so the fit arithmetic is unchanged in principle — but re-run it from the shipped
constants rather than assuming, and update the constant to the truth.

- [ ] **Step 6: Mutation-prove**, each run then REVERTED:
  1. Remove the ceiling (`maxWidth: .infinity`). Expected: `testTheCellGrowsWithTheWindowUpToItsCeiling` FAILS on the ceiling assertion — this is task 3's defect, and the test must catch it.
  2. Restore the exact frame (`.frame(width:height:)`). Expected: the same test FAILS on `wide > narrow` — this is task 4's defect, and the test must catch that too.
  3. Freeze `slotStripRowHeight` back to a constant. Expected: `testTheRowHeightTracksTheDrawnCell` FAILS at the non-floor widths.

**A test that catches only one of the two shipped defects is not finished.** Both mutations must go red.

- [ ] **Step 7: Commit**

```bash
git add App/ARShader/InstrumentSurface.swift App/ARShader/SlotBankStripView.swift \
        App/ARShaderTests/SurfaceGeometryTests.swift
git commit -m "feat(3c): clamp the slot cell — grows with the window, stops at a ceiling

Task 3 shipped a floor with infinite growth and the operator rejected it on
device; task 4 shipped an exact size the reviewer flagged as tiny on a large
display. .frame(minWidth:maxWidth:) is clamp(); both extremes used two of the
three values. Row height now follows the drawn cell so the resize drag cannot
desync from its own pitch."
```

**Smoke leg this adds to Task 8:**

| # | Leg | Hypothesis |
|---|---|---|
| 45 | The strip scales sensibly, both ways | Resize the window from its minimum to full screen. The cells grow, then **stop** — the strip never dominates the surface as it did before, and never leaves a large display mostly dead space. If the ceiling feels wrong, `maxCellWidth` is the one number to move |
