import XCTest
import SwiftUI
@testable import ARShader

/// The defect reported on device 2026-08-02: clicking a slot recalled it onto a deck, but the
/// slot bank's live badge (and, by the identical root cause, `MonitorTile`'s drag payload) did
/// not update — only when something UNRELATED redrew the strip (toggling `RECALL TO`, or
/// `RenderStatsModel`'s ~2x/sec republish) did the badge catch up.
///
/// `SlotBankStripView.liveDeck(for:)` and `MonitorTile.dragPayload` both read `ShaderUnit.sourceURL`
/// correctly the whole time; the missing piece was that neither view held a SUBSCRIPTION to that
/// publisher, so SwiftUI had no dependency telling it either view was stale when a load changed
/// it. The fix gives both views `@ObservedObject private var deckAUnit`/`deckBUnit: ShaderUnit` —
/// the exact pattern `DeckStripView.unit` already established for the identical defect class
/// (`InstrumentView.swift`, 2026-07-30: a sibling view holding `@ObservedObject var unit:
/// ShaderUnit` updated correctly while one built from a plain `Deck` local froze on stale data).
///
/// SwiftUI's actual view invalidation cannot be driven from XCTest here — there is no
/// ViewInspector or SnapshotTesting anywhere in this project (confirmed tree-wide by a prior
/// reviewer). What CAN be proven, and is proven below:
///
/// 1. The properties are genuinely wrapped in `@ObservedObject` — not a plain `let`/`var`
///    reference that compiles identically at every call site but never subscribes to anything —
///    via `Mirror` inspecting the compiler-synthesized `_deckAUnit`/`_deckBUnit` backing storage.
///    A property wrapper's backing storage is a real, inspectable stored property distinct from
///    the wrapped-value accessor; a plain `let deckAUnit: ShaderUnit` produces a stored property
///    literally named `deckAUnit`, never `_deckAUnit`, so this check is a genuine mutation gate
///    for "was the property wrapper removed", the exact regression a data-only equality check
///    cannot see (the object reference is identical either way).
/// 2. The wrapped object is the REAL live `ShaderUnit` the production `Instrument`/`Deck` graph
///    mutates, and (through the real production `Instrument.load` call site) reflects a real
///    deck load immediately, matching what `liveDeck(for:)`/`dragPayload` are asked about.
@MainActor
final class DeckObservationSeamTests: XCTestCase {

    // MARK: SlotBankStripView — the @ObservedObject wrapper itself

    func testSlotBankStripViewWrapsDeckAUnitInObservedObject() {
        let instrument = Instrument()
        let view = SlotBankStripView(instrument: instrument, layout: instrument.surfaceLayout)
        let backing = Mirror(reflecting: view).children.first { $0.label == "_deckAUnit" }
        XCTAssertNotNil(backing,
                        "deckAUnit must be an @ObservedObject-wrapped property (backing storage "
                        + "`_deckAUnit`) so a deck load invalidates this view")
        XCTAssertTrue(backing?.value is ObservedObject<ShaderUnit>,
                     "must be wrapped as ObservedObject<ShaderUnit>, not merely present under "
                     + "some other type")
    }

    func testSlotBankStripViewWrapsDeckBUnitInObservedObject() {
        let instrument = Instrument()
        let view = SlotBankStripView(instrument: instrument, layout: instrument.surfaceLayout)
        let backing = Mirror(reflecting: view).children.first { $0.label == "_deckBUnit" }
        XCTAssertNotNil(backing, "deckBUnit must be @ObservedObject-wrapped — see the deckAUnit "
                        + "test for why a plain reference would pass every OTHER test in this "
                        + "file while never fixing the reported defect")
        XCTAssertTrue(backing?.value is ObservedObject<ShaderUnit>)
    }

    // MARK: MonitorTile — the same wrapper, the same reason (the ~500ms-late-draggable symptom)

    func testMonitorTileWrapsDeckAUnitInObservedObject() {
        let instrument = Instrument()
        let tile = MonitorTile(instrument: instrument, source: .deck(.one), label: "DECK A")
        let backing = Mirror(reflecting: tile).children.first { $0.label == "_deckAUnit" }
        XCTAssertNotNil(backing,
                        "MonitorTile.deckAUnit must be @ObservedObject-wrapped so a deck load "
                        + "makes `dragPayload` draggable immediately rather than up to ~500ms "
                        + "late, riding the next renderStats republish")
        XCTAssertTrue(backing?.value is ObservedObject<ShaderUnit>)
    }

    func testMonitorTileWrapsDeckBUnitInObservedObject() {
        let instrument = Instrument()
        let tile = MonitorTile(instrument: instrument, source: .deck(.two), label: "DECK B")
        let backing = Mirror(reflecting: tile).children.first { $0.label == "_deckBUnit" }
        XCTAssertNotNil(backing, "MonitorTile.deckBUnit must be @ObservedObject-wrapped — see "
                        + "the deckAUnit test")
        XCTAssertTrue(backing?.value is ObservedObject<ShaderUnit>)
    }

    // MARK: liveDeck(for:) — correct against a REAL load through the REAL production call site

    /// Not a reimplementation of the load path: this drives the exact same `Instrument.load`
    /// every production call site (library click, slot recall) uses, then asks the view's own
    /// `liveDeck(for:)` — the same method `content`'s `ForEach` calls to decide each cell's
    /// badge — whether it agrees.
    func testLiveDeckReflectsARealDeckALoadThroughTheProductionLoadPath() async throws {
        let instrument = Instrument()
        let view = SlotBankStripView(instrument: instrument, layout: instrument.surfaceLayout)
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "solid_red", withExtension: "fs", subdirectory: "Fixtures"))

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            instrument.onLoadSettledForTesting = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            instrument.load(url, onto: .deck(.one))
        }
        instrument.onLoadSettledForTesting = nil

        let preset = Preset.capturing(url: url, snapshot: ParamSnapshot(params: [:]))
        XCTAssertEqual(view.liveDeck(for: preset), .one,
                       "deckAUnit must report the SAME sourceURL Instrument.load just stamped on "
                       + "the real deck A unit")
        XCTAssertNil(view.liveDeck(for: Preset.capturing(
            url: URL(fileURLWithPath: "/tmp/never-loaded.fs"),
            snapshot: ParamSnapshot(params: [:]))),
                     "a preset that was never loaded onto either deck must not read as live")
    }

    func testLiveDeckDistinguishesDeckAFromDeckB() async throws {
        let instrument = Instrument()
        let view = SlotBankStripView(instrument: instrument, layout: instrument.surfaceLayout)
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "solid_green", withExtension: "fs", subdirectory: "Fixtures"))

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            instrument.onLoadSettledForTesting = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            instrument.load(url, onto: .deck(.two))
        }
        instrument.onLoadSettledForTesting = nil

        let preset = Preset.capturing(url: url, snapshot: ParamSnapshot(params: [:]))
        XCTAssertEqual(view.liveDeck(for: preset), .two,
                       "loaded onto deck B, so deckBUnit — not deckAUnit — must be the match")
    }
}
