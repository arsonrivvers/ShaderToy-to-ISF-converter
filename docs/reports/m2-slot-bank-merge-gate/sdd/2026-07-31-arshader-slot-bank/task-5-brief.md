### Task 5: The load seam — `Instrument.load(_:onto:thenApply:)`

**Files:**
- Modify: `App/ARShader/Instrument.swift` (add `load`, `currentPreset`, own the `SlotBank`)
- Modify: `App/ARShader/LibraryPanelView.swift:53-72` (delete private `load`/`append`, call the instrument)
- Test: `App/ARShaderTests/InstrumentLoadTests.swift` (extend)

**Interfaces:**
- Consumes: `Preset` (Task 1), `SlotBank` (Task 2), `SlotBankStore` (Task 3), `ShaderUnit.sourceURL` (Task 4), existing `LibraryTarget` and `FXChain`.
- Produces: `Instrument.load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil)`, `Instrument.currentPreset(of deck: DeckID) -> Preset?`, `Instrument.slotBank: SlotBank`.

**This is the task the PM review said was mis-sized.** It is not a same-behaviour lift. `ShaderUnit.onCompileFinished` is a **single-owner optional closure**, and `LibraryPanelView.append` already claims it on every FX stage for `chain?.stageDidChangeScene()`. Layering snapshot-apply on the same hook means whoever assigns second silently drops the first — across three of the picker's five segments. And for FX targets the unit is created *inside* `load`, so a `Void`-returning `load` leaves the caller nothing to hook. `load` therefore owns the composition itself.

- [ ] **Step 1: Write the failing tests**

Add to `InstrumentLoadTests`:

```swift
    /// Awaits one compile, which is asynchronous — the unit compiles on a background queue and
    /// fires `onCompileFinished` back on the main actor.
    private func loadAndWait(_ instrument: Instrument, _ url: URL,
                             onto target: LibraryTarget,
                             thenApply snapshot: ParamSnapshot? = nil) async {
        await withCheckedContinuation { continuation in
            var resumed = false
            instrument.onLoadSettledForTesting = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            instrument.load(url, onto: target, thenApply: snapshot)
        }
        instrument.onLoadSettledForTesting = nil
    }

    func testADeckTargetReplacesTheShader() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile("first"), onto: .deck(.one))
        await loadAndWait(instrument, try makeShaderFile("second"), onto: .deck(.one))
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL?.lastPathComponent.hasPrefix("second"),
                       true, "A deck REPLACES; it does not accumulate")
    }

    func testAnFXTargetAppendsAStage() async throws {
        let instrument = Instrument()
        let before = instrument.renderer.masterFX.stages.count
        await loadAndWait(instrument, try makeShaderFile(), onto: .masterFX)
        XCTAssertEqual(instrument.renderer.masterFX.stages.count, before + 1,
                       "An FX target APPENDS a stage; it does not replace the chain")
    }

    func testASnapshotIsAppliedAfterTheCompileLands() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        XCTAssertEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"],
                       .float(0.25),
                       "Applied before the compile lands, the parameters would not exist to receive it")
    }

    /// The collision the PM review caught. Assign only the snapshot handler and this goes red.
    func testAnFXLoadWithASnapshotStillRepublishesTheChain() async throws {
        let instrument = Instrument()
        var republishes = 0
        instrument.renderer.masterFX.onStagesChangedForTesting = { republishes += 1 }
        await loadAndWait(instrument, try makeShaderFile(), onto: .masterFX,
                          thenApply: ParamSnapshot(params: ["speed": .float(0.3)]))
        XCTAssertGreaterThan(republishes, 0,
                             "onCompileFinished is single-owner: a snapshot handler that replaces "
                             + "the chain republish silently stops the FX stage updating")
        instrument.renderer.masterFX.onStagesChangedForTesting = nil
    }

    /// The stale one-shot. Without the clear, the second load replays the first preset's values.
    func testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        XCTAssertNotEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"],
                          .float(0.25),
                          "A later library load must not inherit a preset's values from an earlier "
                          + "slot recall onto the same deck")
    }

    /// Falsifiable because Instrument OWNS surfaceLayout and load() could therefore reach it.
    func testLoadingDoesNotEndShowMode() async throws {
        let instrument = Instrument()
        instrument.surfaceLayout.toggleShowMode()
        XCTAssertTrue(instrument.surfaceLayout.showMode)
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        XCTAssertTrue(instrument.surfaceLayout.showMode,
                      "Loading a shader is a performance action. Only deliberate LAYOUT actions "
                      + "end a show.")
    }

    func testCurrentPresetIsNilUntilSomethingIsLoaded() {
        XCTAssertNil(Instrument().currentPreset(of: .one))
    }

    func testCurrentPresetCapturesTheLiveValues() async throws {
        let instrument = Instrument()
        await loadAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        instrument.deck(.one).unit.params.set("speed", .float(0.8))
        let preset = try XCTUnwrap(instrument.currentPreset(of: .one))
        XCTAssertEqual(preset.snapshot.params["speed"], .float(0.8),
                       "Capture takes what is dialled NOW, not the header defaults")
    }
```

**Note for the implementer:** `onLoadSettledForTesting` and `FXChain.onStagesChangedForTesting` are test seams you are adding. Keep them `internal var` with a `ForTesting` suffix and a comment saying why they exist. If `ParamStore.set` has a different signature, use the real one — check `App/ISFRuntime/ParamStore.swift` and adjust the test, not the store.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — no `load(_:onto:thenApply:)` on `Instrument`.

- [ ] **Step 3: Write the implementation**

In `Instrument.swift`:

```swift
    /// The slot bank, restored from the last launch, persisting itself on every write.
    let slotBank: SlotBank

    // in init(), after surfaceLayout is set up:
    let bankStore = SlotBankStore()
    self.slotBank = SlotBank(slots: bankStore.load())
    self.slotBank.onChange = { [weak self] in
        guard let self else { return }
        bankStore.save(self.slotBank.slots)
    }

    /// Fired after a load has compiled and any snapshot has been applied. Test seam only — the app
    /// has no use for it, but the compile is asynchronous and a test otherwise has nothing to await.
    var onLoadSettledForTesting: (() -> Void)?

    /// The ONE place a shader becomes loaded. Library clicks, slot recalls and (later) MIDI pads
    /// all arrive here, so the mapping from "a URL plus a target" to "replace a deck / append a
    /// stage" exists once rather than inside a view's private method.
    ///
    /// `thenApply` exists because `ShaderUnit.onCompileFinished` is a SINGLE-OWNER closure that the
    /// FX path already claims for `stageDidChangeScene()`. If the caller set it to apply a
    /// snapshot, whichever assignment ran second would silently drop the other. So this method owns
    /// the composition — and for FX targets it is also the only code that ever sees the freshly
    /// created stage, so the caller could not hook it even if the hook were free.
    func load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil) {
        switch target {
        case .deck(let id):
            let unit = deck(id).unit
            attach(snapshot, to: unit, alsoRunning: nil)
            unit.load(url: url)
        case .deckFX(let id):
            append(url, to: deck(id).fx, snapshot: snapshot)
        case .masterFX:
            append(url, to: renderer.masterFX, snapshot: snapshot)
        }
    }

    private func append(_ url: URL, to chain: FXChain, snapshot: ParamSnapshot?) {
        let stage = FXStage(device: device, queue: queue, clock: renderer.clock)
        attach(snapshot, to: stage.unit, alsoRunning: { [weak chain] in chain?.stageDidChangeScene() })
        chain.append(stage)
        stage.unit.load(url: url)
    }

    /// Installs a compile handler that runs the chain's ongoing concern AND the one-shot snapshot,
    /// then CLEARS the one-shot. Without the clear, a later unrelated load onto the same unit would
    /// re-fire it and replay an old preset's values onto a shader they were never captured from.
    private func attach(_ snapshot: ParamSnapshot?, to unit: ShaderUnit,
                        alsoRunning ongoing: (() -> Void)?) {
        unit.onCompileFinished = { [weak self, weak unit] in
            ongoing?()
            if let snapshot, let unit { unit.params.applySnapshot(snapshot) }
            // One-shot: reinstall the ongoing concern alone, or nothing.
            unit?.onCompileFinished = ongoing.map { fn in { fn() } }
            self?.onLoadSettledForTesting?()
        }
    }

    /// What is on a deck right now, as a capturable preset. Nil when the deck has no file behind it.
    func currentPreset(of id: DeckID) -> Preset? {
        let unit = deck(id).unit
        guard let url = unit.sourceURL else { return nil }
        return Preset.capturing(url: url, snapshot: unit.params.exportSnapshot())
    }
```

In `FXChain.swift`, add next to the existing republish path:

```swift
    /// Test seam: lets a test observe that a stage change was republished. Nil in the app.
    var onStagesChangedForTesting: (() -> Void)?
```
and call `onStagesChangedForTesting?()` inside `stageDidChangeScene()`.

In `LibraryPanelView.swift`, **delete** the private `load(_:)` and `append(_:to:)` methods entirely and change the list's button action to:

```swift
                Button {
                    instrument.load(entry.url, onto: target)
                } label: {
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS. Then run the FULL ARShader suite — the library path changed, so anything that exercised it must still be green.

- [ ] **Step 5: Mutation-prove the three that matter**

1. In `attach`, drop `ongoing?()` from the closure. Expected: `testAnFXLoadWithASnapshotStillRepublishesTheChain` FAILS. Restore.
2. In `attach`, remove the one-shot reinstall line. Expected: `testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues` FAILS. Restore.
3. Add `surfaceLayout.toggleShowMode()` at the top of `load`. Expected: `testLoadingDoesNotEndShowMode` FAILS. Restore.

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/Instrument.swift App/ARShader/FXChain.swift App/ARShader/LibraryPanelView.swift App/ARShaderTests/InstrumentLoadTests.swift
git commit -m "feat(3b): one load seam for library clicks, slot recalls and later MIDI

Not a pure lift. onCompileFinished is single-owner and the FX path already
claims it, so load() owns the composition and clears the one-shot after firing."
```

Expected ARShader count: **238**.

---

