### Task 6: Drag and drop — deck monitor → slot

**Files:**
- Modify: `App/ARShader/MonitorView.swift` — deck tiles become drag SOURCES
- Test: `App/ARShaderTests/ShaderDragTests.swift` — capture-carries-values test

**Interfaces:**
- Consumes: `ShaderDrag` and `ShaderDrag.accepts` from Task 5, unchanged; `Instrument.currentPreset(of:)` (`Instrument.swift:138`).
- Produces: nothing new. This task adds one `.draggable` and the test that it carries the values.

This restores the capability Task 4 removed with the SOURCE picker, and **must land in the same
review cycle as Task 4** — between them there is no way to capture a look at all.

`MonitorTile` is keyed by `MonitorSource` (`InstrumentRenderer.swift:7-19`). Only deck tiles get
`.draggable`; **PROGRAM does not**, because `Instrument.currentPreset(of:)` takes a `DeckID` and
there is no such thing as the master's shader — the program feed is a composite of two decks and an
FX chain, and a "look" of it is not a `Preset`. Do not widen `currentPreset` to make this work.

- [ ] **Step 1: Write the failing test**

```swift
    /// Dragging a deck monitor to a slot must capture the LOOK — the shader AND the values dialled
    /// into it. A capture that carried only the URL would recall at header defaults, which is
    /// exactly the re-dialling-on-stage problem the slot bank exists to remove.
    func testADeckDragCarriesTheDialledValuesNotJustTheURL() throws {
        let snapshot = ParamSnapshot(params: ["speed": .float(0.87)])
        let drag = ShaderDrag(source: .deck(.one), url: url, snapshot: snapshot)
        let captured = Preset.capturing(url: drag.url,
                                        snapshot: try XCTUnwrap(drag.snapshot))
        XCTAssertEqual(captured.snapshot.params["speed"], .float(0.87))
    }
```

- [ ] **Step 2: Run it — expect PASS or FAIL depending on Task 5's shape.** If it already passes, that is fine and expected: Task 5 built the payload. Its value here is as a regression guard on the `snapshot` field surviving future edits — say so in the commit rather than pretending it was red first.

- [ ] **Step 3: Make deck tiles draggable**

In `MonitorTile`, for deck sources only:

```swift
            .draggable(dragPayload ?? ShaderDrag(source: .slot, url: URL(fileURLWithPath: "/"),
                                                 snapshot: nil))
```

is WRONG — a sentinel payload would be a rejected-drag that still starts a drag. Instead gate the
modifier itself, so a deck with no shader loaded is simply not draggable:

```swift
    @ViewBuilder
    private func draggableIfCapturable<V: View>(_ view: V) -> some View {
        if case .deck(let id) = source, let preset = instrument.currentPreset(of: id) {
            view.draggable(ShaderDrag(source: .deck(id), url: preset.shaderURL,
                                      snapshot: preset.snapshot))
        } else {
            view
        }
    }
```

`currentPreset(of:)` returns nil when the deck has no file behind it (`Instrument.swift:140`), so an
empty deck is not a drag source and no empty capture is possible.

- [ ] **Step 4: Run the full suite.**

- [ ] **Step 5: Mutation-prove.** Change the `.draggable` payload to pass `snapshot: nil`. Expected: `testADeckDragCarriesTheDialledValuesNotJustTheURL` still passes (it tests the type, not the view), so **add a second assertion at the view seam** — a test that builds the payload the way `draggableIfCapturable` does and asserts the snapshot is non-nil for a deck with a loaded shader. If you cannot make that test fail under the mutation, report it as structurally untestable rather than claiming a proof you do not have.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/MonitorView.swift App/ARShaderTests/ShaderDragTests.swift
git commit -m "feat(3c): drag a deck monitor to a slot to capture the live look"
```

---

