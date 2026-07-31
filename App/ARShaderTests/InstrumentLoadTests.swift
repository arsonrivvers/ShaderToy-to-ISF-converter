import XCTest
@testable import ARShader

@MainActor
final class InstrumentLoadTests: XCTestCase {

    /// A real, compilable ISF file on disk. The unit reads the file, so a fake path will not do.
    /// Non-private: Task 5's capture tests reuse this to produce loadable fixtures.
    func makeShaderFile(_ name: String = "probe") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).fs")
        try """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [
            { "NAME": "speed", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 }
        ] }*/
        void main() { gl_FragColor = vec4(speed, 0.0, 0.0, 1.0); }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// An `.fs` file that reads fine but fails to compile — same uncompilable body already proven
    /// to fail in ShaderUnitTests (Fixtures/broken.fs: an undefined GLSL symbol). Non-private:
    /// the coordinator's fix-round-1 test reuses this too.
    func makeUncompilableShaderFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).fs")
        try """
        /*{ "ISFVSN": "2.0", "DESCRIPTION": "Deliberately uncompilable.", "INPUTS": [] }*/
        void main() { gl_FragColor = this_symbol_does_not_exist(1.0); }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// `sourceURL` is now stamped in `apply`'s success path, after the background compile —
    /// so tests must await `onCompileFinished` rather than asserting right after `load(url:)`.
    /// Same shape as Task 5's brief helper.
    private func loadAndWait(_ unit: ShaderUnit, _ url: URL) async {
        await withCheckedContinuation { continuation in
            var resumed = false
            unit.onCompileFinished = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            unit.load(url: url)
        }
        unit.onCompileFinished = nil
    }

    func testAFreshUnitHasNoSourceURL() {
        let instrument = Instrument()
        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "Nothing has been loaded, so there is no file behind the deck")
    }

    func testLoadingFromAURLRetainsIt() async throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        await loadAndWait(instrument.deck(.one).unit, url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url,
                       "Capture needs the URL, and lastPathComponent is not enough — filenames "
                       + "are not unique across the corpus")
    }

    /// Judgment call (Task 4 brief step 5): the brief's two required tests never exercise the
    /// `load(source:name:)` clear. Without this, a unit loaded from a URL and then reloaded from
    /// bare source (e.g. a Remix result with no file behind it) would keep reporting the stale
    /// URL, and a capture built from it would wrongly claim a file the running shader no longer
    /// has behind it.
    func testLoadingFromSourceAfterAURLClearsIt() async throws {
        let instrument = Instrument()
        let url = try makeShaderFile()
        await loadAndWait(instrument.deck(.one).unit, url)
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, url, "sanity: the URL load landed")

        let done = expectation(description: "compile inline source")
        instrument.deck(.one).unit.onCompileFinished = { done.fulfill() }
        instrument.deck(.one).unit.load(source: """
        /*{ "DESCRIPTION": "test", "ISFVSN": "2", "INPUTS": [] }*/
        void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }
        """, name: "inline")
        await fulfillment(of: [done], timeout: 30)
        instrument.deck(.one).unit.onCompileFinished = nil

        XCTAssertNil(instrument.deck(.one).unit.sourceURL,
                     "A source-loaded unit has no file behind it and must not still claim the "
                     + "previous URL")
    }

    /// The regression this fix (coordinator round 1) exists to prevent: `sourceURL` used to be
    /// stamped synchronously in `load(url:)`, disagreeing with `shaderName` whenever the compile
    /// then failed. `apply` deliberately leaves `shaderName` and the rendering scene on the
    /// previous shader when a compile fails — "compile first, swap only on success" — and
    /// `sourceURL` must honor the same rule, or Task 5's capture would store a shader that does
    /// not compile.
    func testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying() async throws {
        let instrument = Instrument()
        let good = try makeShaderFile("good")
        await loadAndWait(instrument.deck(.one).unit, good)

        let bad = try makeUncompilableShaderFile()
        await loadAndWait(instrument.deck(.one).unit, bad)

        XCTAssertNotNil(instrument.deck(.one).unit.compileError, "the failure must be reported")
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL, good,
                       "A failed compile leaves the previous shader playing, so sourceURL must "
                       + "still name it — capture reads this, and would otherwise store a shader "
                       + "that does not compile")
    }

    /// Round 2: `unload()` (the Clear button's target, `InstrumentView.swift:72`) reset
    /// `shaderName` but not `sourceURL`, so a cleared deck kept naming its last file — capture
    /// would then read a `sourceURL` for a deck with nothing playing.
    func testUnloadingClearsTheSourceURLAsWellAsTheName() async throws {
        let instrument = Instrument()
        let unit = instrument.deck(.one).unit
        await loadAndWait(unit, try makeShaderFile("loaded"))
        XCTAssertNotNil(unit.sourceURL)

        unit.unload()

        XCTAssertNil(unit.sourceURL,
                     "A cleared deck has nothing playing, so it must not still name a file — "
                     + "capture reads sourceURL to decide whether there is anything to capture")
        XCTAssertNil(unit.shaderName, "The two must agree about what is up")
    }

    // MARK: Task 5 — the load seam

    /// Awaits one compile, which is asynchronous — the unit compiles on a background queue and
    /// fires `onCompileFinished` back on the main actor. Distinct name from `loadAndWait` above:
    /// that one takes a bare `ShaderUnit`, this one drives `Instrument.load(_:onto:thenApply:)`.
    private func loadTargetAndWait(_ instrument: Instrument, _ url: URL,
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
        await loadTargetAndWait(instrument, try makeShaderFile("first"), onto: .deck(.one))
        await loadTargetAndWait(instrument, try makeShaderFile("second"), onto: .deck(.one))
        XCTAssertEqual(instrument.deck(.one).unit.sourceURL?.lastPathComponent.hasPrefix("second"),
                       true, "A deck REPLACES; it does not accumulate")
    }

    func testAnFXTargetAppendsAStage() async throws {
        let instrument = Instrument()
        let before = instrument.renderer.masterFX.stages.count
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .masterFX)
        XCTAssertEqual(instrument.renderer.masterFX.stages.count, before + 1,
                       "An FX target APPENDS a stage; it does not replace the chain")
    }

    /// Coordinator fix round 1, MINOR 2: this test cannot actually distinguish "applied after the
    /// compile lands" from "applied at any other time" — `ParamStore.applySnapshot` keeps
    /// unknown-to-the-shader names regardless of when it runs, and `syncInputs` then keeps
    /// same-typed survivors, so this assertion would pass even if the snapshot were (wrongly)
    /// applied synchronously before the compile started. The message below states only what this
    /// actually proves, not the stronger ordering claim the original message made.
    func testASnapshotIsAppliedAfterTheCompileLands() async throws {
        let instrument = Instrument()
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        XCTAssertEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"],
                       .float(0.25),
                       "Once Instrument.load's compile has settled, the deck's exported snapshot "
                       + "must reflect the values passed to thenApply")
    }

    /// The collision the PM review caught. Assign only the snapshot handler and this goes red.
    func testAnFXLoadWithASnapshotStillRepublishesTheChain() async throws {
        let instrument = Instrument()
        var republishes = 0
        instrument.renderer.masterFX.onSceneRepublishedForTesting = { republishes += 1 }
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .masterFX,
                          thenApply: ParamSnapshot(params: ["speed": .float(0.3)]))
        XCTAssertGreaterThan(republishes, 0,
                             "onCompileFinished is single-owner: a snapshot handler that replaces "
                             + "the chain republish silently stops the FX stage updating")
        instrument.renderer.masterFX.onSceneRepublishedForTesting = nil
    }

    /// The stale one-shot. Without the clear, `onCompileFinished` keeps pointing at the closure
    /// that applied THIS load's snapshot, so a later load that bypasses `Instrument.load` entirely
    /// (a future MIDI reload, an edit-and-recompile path — anything that calls `ShaderUnit.load`
    /// directly) would re-fire it and force this preset's values back onto an unrelated shader.
    ///
    /// Deviation from the brief's literal test: the brief compared param values after a SECOND
    /// `instrument.load(...)` call, but that path always calls `attach` again first, which
    /// unconditionally overwrites `onCompileFinished` before the second compile can even start —
    /// so that comparison can never observe a stale one-shot regardless of whether the clear runs.
    /// Worse, both loads used `makeShaderFile()`, which always declares the same `"speed"` input;
    /// `ParamStore.syncInputs`'s deliberate, separately-tested "same-typed survivor must be kept"
    /// behavior (`ParamStoreTests.testSyncInputsPrunesVanishedAndTypeChanged_keepsSurvivors`) then
    /// carries `0.25` into the second shader ANYWAY, on every run, whether or not the one-shot is
    /// cleared — so the brief's assertion fails unconditionally for a reason unrelated to this
    /// task. Asserting on `onCompileFinished` directly tests the actual invariant and is
    /// independent of that unrelated mechanism.
    func testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues() async throws {
        let instrument = Instrument()
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        XCTAssertNil(instrument.deck(.one).unit.onCompileFinished,
                     "A later load that bypasses Instrument.load must not re-fire this load's "
                     + "snapshot onto whatever it compiles next")
    }

    /// Falsifiable because Instrument OWNS surfaceLayout and load() could therefore reach it.
    func testLoadingDoesNotEndShowMode() async throws {
        let instrument = Instrument()
        instrument.surfaceLayout.toggleShowMode()
        XCTAssertTrue(instrument.surfaceLayout.showMode)
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        XCTAssertTrue(instrument.surfaceLayout.showMode,
                      "Loading a shader is a performance action. Only deliberate LAYOUT actions "
                      + "end a show.")
    }

    func testCurrentPresetIsNilUntilSomethingIsLoaded() {
        XCTAssertNil(Instrument().currentPreset(of: .one))
    }

    func testCurrentPresetCapturesTheLiveValues() async throws {
        let instrument = Instrument()
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        instrument.deck(.one).unit.params.set("speed", .float(0.8))
        let preset = try XCTUnwrap(instrument.currentPreset(of: .one))
        XCTAssertEqual(preset.snapshot.params["speed"], .float(0.8),
                       "Capture takes what is dialled NOW, not the header defaults")
    }

    // MARK: coordinator fix round 1

    /// IMPORTANT 1: `onCompileFinished` fires on ALL THREE outcomes — unreadable file, compile
    /// failure, success — but a failed compile deliberately leaves the previous shader playing
    /// (compile-first-swap-on-success). Applying `thenApply`'s snapshot unconditionally would
    /// mutate that still-playing shader: `applySnapshot` REPLACES `values` wholesale, so the
    /// operator's dialled value would be destroyed by a load that never even took effect.
    func testAFailedLoadWithASnapshotLeavesTheDialledValueOfTheStillPlayingShaderUntouched() async throws {
        let instrument = Instrument()
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .deck(.one))
        instrument.deck(.one).unit.params.set("speed", .float(0.77))

        await loadTargetAndWait(instrument, try makeUncompilableShaderFile(), onto: .deck(.one),
                          thenApply: ParamSnapshot(params: ["speed": .float(0.1)]))

        XCTAssertNotNil(instrument.deck(.one).unit.compileError, "sanity: the load did fail")
        XCTAssertEqual(instrument.deck(.one).unit.params.exportSnapshot().params["speed"],
                       .float(0.77),
                       "A failed compile must not let the snapshot mutate the shader that is "
                       + "still playing")
    }

    /// IMPORTANT 2: every `Instrument()` in this suite would otherwise read and overwrite the
    /// operator's REAL slot bank in `UserDefaults.standard`. Confirms the harness gate in
    /// `Instrument.init()` routes to `InMemoryKeyValueStore` instead (coordinator fix round 2 —
    /// round 1's `UserDefaults(suiteName:)` isolated the KEY but still littered a real
    /// ~/Library/Preferences file per instance) — a capture on a fresh test instrument must not
    /// move the real key at all.
    func testAFreshInstrumentUnderTheHarnessDoesNotWriteTheRealSlotBank() {
        let before = UserDefaults.standard.data(forKey: SlotBankStore.key)
        let instrument = Instrument()
        instrument.slotBank.capture(
            Preset.capturing(url: URL(fileURLWithPath: "/tmp/coordinator-fix-round-1.fs"),
                             snapshot: ParamSnapshot(params: [:])),
            into: 0)
        let after = UserDefaults.standard.data(forKey: SlotBankStore.key)
        XCTAssertEqual(before, after,
                       "Instrument() under the test harness must not read or write the operator's "
                       + "real slot bank")
    }

    /// MINOR 1: the FX half of the one-shot invariant. On `.deck` targets `ongoing` is nil, so
    /// `testTheOneShotIsClearedSoALaterLoadDoesNotReplayOldValues` above (asserting
    /// `onCompileFinished == nil`) can't see this path — on `.masterFX`, `ongoing` is NON-nil, so
    /// after the one-shot fires, `onCompileFinished` is reinstalled to `{ fn() }`, not nil. This
    /// drives a SECOND compile directly through that reinstalled closure (bypassing
    /// `Instrument.load`, which would just call `attach` fresh again) and asserts it republishes
    /// the chain but does NOT re-apply the retired snapshot over a value dialled afterward.
    func testTheFXOneShotReinstallsRepublishOnlyNotTheRetiredSnapshot() async throws {
        let instrument = Instrument()
        await loadTargetAndWait(instrument, try makeShaderFile(), onto: .masterFX,
                          thenApply: ParamSnapshot(params: ["speed": .float(0.25)]))
        let stage = try XCTUnwrap(instrument.renderer.masterFX.stages.last)
        stage.unit.params.set("speed", .float(0.6))

        let republished = expectation(description: "reinstalled closure republishes the chain")
        instrument.renderer.masterFX.onSceneRepublishedForTesting = { republished.fulfill() }
        stage.unit.load(url: try makeShaderFile("refresh"))
        await fulfillment(of: [republished], timeout: 30)
        instrument.renderer.masterFX.onSceneRepublishedForTesting = nil

        XCTAssertEqual(stage.unit.params.exportSnapshot().params["speed"], .float(0.6),
                       "The reinstalled closure must republish the chain but not re-apply the "
                       + "retired snapshot over a value dialled after the load settled")
    }
}
