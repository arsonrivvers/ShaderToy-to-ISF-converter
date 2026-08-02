import XCTest
@testable import ARShader

/// Fix-round-1, F1. `ShaderDragTests` already covers `ShaderDrag.accepts` thoroughly as a pure
/// function, but nothing exercised the view SEAM that actually calls it: the `.dropDestination`
/// action and `isTargeted` highlight inside `SlotBankStripView`'s `ForEach`. Mutating `on: .slot`
/// → `on: .deck(.one)`, or `isSlotFilled: bank.slots[index] != nil` → `isSlotFilled: false`, at
/// that call site left all 292 prior tests green — the never-overwrite invariant was correct as a
/// function and unenforced as a call site.
///
/// These tests call `SlotBankStripView.wouldAccept`/`wouldHighlight` directly — the same
/// "testable seam on the view struct itself, no rendering" pattern `SlotRecallTargetTests`
/// already uses on `recallTargets` and `InstrumentView.liveResolution` uses for its own testable
/// pure function. `SlotBankStripView` is a plain struct; calling a method on it touches no
/// SwiftUI machinery and needs no host view.
@MainActor
final class SlotBankStripViewDropSeamTests: XCTestCase {
    private let libraryDrag = ShaderDrag(source: .library, url: URL(fileURLWithPath: "/tmp/a.fs"),
                                         snapshot: nil)

    private func makeView() -> (view: SlotBankStripView, instrument: Instrument) {
        let instrument = Instrument()
        return (SlotBankStripView(instrument: instrument, layout: instrument.surfaceLayout),
                instrument)
    }

    private func fill(_ instrument: Instrument, slot index: Int) {
        instrument.slotBank.capture(
            Preset.capturing(url: URL(fileURLWithPath: "/tmp/filled-\(index).fs"),
                             snapshot: ParamSnapshot(params: [:])),
            into: index)
    }

    // MARK: wouldAccept — the drop action's own decision, through the real call site

    func testWouldAcceptAnEmptySlot() {
        let (view, _) = makeView()
        XCTAssertTrue(view.wouldAccept(libraryDrag, at: 0))
    }

    /// The mutation-proof target: this must go red if `wouldAccept` stops asking about `.slot`,
    /// or stops asking whether THIS slot is filled.
    func testWouldRejectAFilledSlotWithoutOption() {
        let (view, instrument) = makeView()
        fill(instrument, slot: 0)
        XCTAssertFalse(view.wouldAccept(libraryDrag, at: 0),
                       "a filled slot must reject a drop with no ⌥ held")
    }

    /// A different slot's fill state must not leak into this one's decision — evidence
    /// `isSlotFilled:` is read per-index rather than hardcoded.
    func testFillingOneSlotDoesNotAffectAnothersAcceptance() {
        let (view, instrument) = makeView()
        fill(instrument, slot: 0)
        XCTAssertTrue(view.wouldAccept(libraryDrag, at: 1),
                     "slot 1 is still empty — slot 0 filling must not leak into its decision")
    }

    // MARK: wouldHighlight — must agree with wouldAccept, not re-derive it

    func testWouldHighlightAnEmptySlot() {
        let (view, _) = makeView()
        XCTAssertTrue(view.wouldHighlight(at: 0))
    }

    func testWouldNotHighlightAFilledSlotWithoutOption() {
        let (view, instrument) = makeView()
        fill(instrument, slot: 0)
        XCTAssertFalse(view.wouldHighlight(at: 0),
                       "highlighting a target that would reject the drop is worse than no "
                       + "highlight on a strip of eight visually identical cells")
    }

    // MARK: loadThumbnails — cancellation (final-review F2)

    /// The `.task(id: bank.slots)` doc comment claims a restart cancels the sweep still in flight.
    /// It did not: awaiting an actor method is not a cancellation point, so a cancelled sweep ran
    /// to completion and issued every remaining `.batch` request anyway — three quick captures put
    /// four concurrent sweeps on one actor with hover queued behind all of them.
    ///
    /// Deterministic, not racy: this test is `@MainActor` and `Task { }` inherits that actor, so
    /// the child task cannot begin until this method suspends. `cancel()` on the line after the
    /// task is created therefore always lands BEFORE the loop's first iteration, and a correct
    /// implementation issues exactly zero requests.
    func testACancelledThumbnailSweepStopsRatherThanRunningToCompletion() async throws {
        let (view, instrument) = makeView()
        // A real fixture, not a made-up path: an unreadable URL fails before the transpile, so
        // `compileCountForTesting` would read 0 either way and the test could not fail.
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "solid_red", withExtension: "fs", subdirectory: "Fixtures"))
        instrument.slotBank.capture(
            Preset.capturing(url: url, snapshot: ParamSnapshot(params: [:])), into: 0)

        let sweep = Task { await view.loadThumbnails() }
        sweep.cancel()
        await sweep.value

        let compiles = await instrument.thumbnailService.compileCountForTesting
        XCTAssertEqual(compiles, 0,
                       "a cancelled sweep must issue NO further requests — each one holds the "
                       + "thumbnail actor for a full transpile, offscreen render and PNG encode, "
                       + "and a library hover queues behind every one of them")
    }
}
