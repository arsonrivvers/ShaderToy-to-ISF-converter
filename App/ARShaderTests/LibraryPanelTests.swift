import XCTest
import Metal

@MainActor
final class LibraryPanelTests: XCTestCase {
    private func makeModel(with names: [String]) throws -> (LibraryModel, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arshader-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in names {
            try """
            /*{
                "ISFVSN": "2.0",
                "DESCRIPTION": "library fixture",
                "CATEGORIES": ["Test"],
                "INPUTS": []
            }*/

            void main() { gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0); }
            """.write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8)
        }
        let model = LibraryModel()
        model.addFolder(dir, title: "Test")
        return (model, dir)
    }

    func testSearchRequiresEveryTokenToMatch() throws {
        let (model, dir) = try makeModel(with: [
            "AR_Genuary2026_Day14.fs", "AR_Genuary2026_Day02.fs", "AR_Devolution_Kindling.fs"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let selection = LibrarySelection()
        selection.query = "genuary 14"
        XCTAssertEqual(selection.results(in: model).map(\.name), ["AR_Genuary2026_Day14.fs"])

        selection.query = "genuary"
        XCTAssertEqual(selection.results(in: model).count, 2)

        selection.query = ""
        XCTAssertEqual(selection.results(in: model).count, 3)
    }

    func testSearchIsCaseInsensitiveAndOrderIndependent() throws {
        let (model, dir) = try makeModel(with: ["AR_Genuary2026_Day14.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let selection = LibrarySelection()
        selection.query = "14 GENUARY"
        XCTAssertEqual(selection.results(in: model).count, 1)
    }

    func testSortOrderIsHonoured() throws {
        let (model, dir) = try makeModel(with: ["b.fs", "a.fs", "c.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let selection = LibrarySelection()
        selection.sort = .name
        XCTAssertEqual(selection.results(in: model).map(\.name), ["a.fs", "b.fs", "c.fs"])
    }

    func testLoadingAnEntryPutsItOnTheTargetDeck() throws {
        let (model, dir) = try makeModel(with: ["loadme.fs"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())

        let entry = try XCTUnwrap(model.filtered(query: "loadme").first)
        let done = expectation(description: "load")
        deck.unit.onCompileFinished = { done.fulfill() }
        deck.unit.load(url: entry.url)
        wait(for: [done], timeout: 30)

        XCTAssertNil(deck.unit.compileError)
        XCTAssertEqual(deck.unit.shaderName, "loadme.fs")
    }

    // MARK: the hover well's loading state (final-review F7)

    /// The defect: while a request was outstanding the well kept the PREVIOUS shader's still at
    /// full opacity, presenting it as a settled answer for the row now under the pointer. On a cold
    /// cache a deliberate slow scan could leave it seconds behind and still look correct. Smoke leg
    /// 28 judges exactly this behaviour on device, and a well that cannot say "still working" makes
    /// the leg unjudgeable.
    ///
    /// `wellState` is the production mapping — `hoverPreviewWell` calls this same function for its
    /// opacity and its spinner, so this is a gate on the decision, not a re-derivation of it.
    func testAStaleStillIsNotPresentedAsSettledWhileARequestIsOutstanding() {
        XCTAssertEqual(LibraryPanelView.wellState(hasPreview: true, isResolving: true), .resolving,
                       "holding a PREVIOUS row's still while a new request is out must never read "
                       + "as the answer for the row under the pointer")
        XCTAssertLessThan(LibraryPanelView.WellState.resolving.imageOpacity,
                          LibraryPanelView.WellState.settled.imageOpacity,
                          "and the distinction has to be visible, not merely modelled")
        XCTAssertTrue(LibraryPanelView.WellState.resolving.showsProgress)
    }

    func testASettledStillIsShownAtFullStrength() {
        XCTAssertEqual(LibraryPanelView.wellState(hasPreview: true, isResolving: false), .settled)
        XCTAssertEqual(LibraryPanelView.WellState.settled.imageOpacity, 1)
        XCTAssertFalse(LibraryPanelView.WellState.settled.showsProgress,
                       "a spinner over a settled still would be a permanent lie")
    }

    /// An empty well with a request out must still say "working": before anything has ever
    /// resolved, this is the operator's only signal that the hover did anything at all.
    func testAnEmptyWellStillReportsAnOutstandingRequest() {
        XCTAssertEqual(LibraryPanelView.wellState(hasPreview: false, isResolving: true), .resolving)
        XCTAssertEqual(LibraryPanelView.wellState(hasPreview: false, isResolving: false), .empty)
        XCTAssertFalse(LibraryPanelView.WellState.empty.showsProgress)
    }

    func testLibraryTargetsCoverEveryDeckAndEveryChain() {
        XCTAssertEqual(LibraryTarget.allCases.count, 5,
                       "two decks, two deck chains, one master chain")
        XCTAssertEqual(LibraryTarget.allCases.map(\.shortLabel),
                       ["A", "A FX", "B", "B FX", "MST FX"])
    }

    func testAnUnreadableEntryReportsRatherThanCrashing() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let deck = Deck(id: .one, device: device, queue: queue, clock: RenderClock())
        deck.unit.load(url: URL(fileURLWithPath: "/nonexistent/nope.fs"))
        XCTAssertNotNil(deck.unit.compileError)
        XCTAssertNil(deck.unit.shaderName)
    }

    func testTheInstrumentLibraryIsSkippedUnderTheTestHarness() {
        // The suite must never scan the user's real folders: a persisted folder in a TCC-protected
        // location would block the run behind a permission prompt.
        XCTAssertTrue(TestHarness.isActive)
        let model = LibraryModel()
        model.loadInstrumentLibraries()
        XCTAssertTrue(model.sources.isEmpty)
    }

    /// F4, fix round 1 on task 7: `LibraryPanelView`'s hover dwell delay only does its job — a row
    /// the pointer merely sweeps past never reaches `ThumbnailService` — if cancelling the dwell
    /// is OBSERVED, not swallowed. `try? await Task.sleep(...)` would catch the thrown
    /// `CancellationError` and fall through to `.dwelled` regardless, making the whole guard a
    /// no-op while still looking correct.
    ///
    /// Deterministic by the same proven pattern as
    /// `ThumbnailServiceTests.testACancelledRequestIsNeverPersistedAsUnavailable`: cancel the
    /// wrapping task immediately after creation, before it has any chance to run, so
    /// `Task.sleep`'s own cancellation check reads true before the sleep can elapse. No scheduling
    /// race — `Task.sleep` checking cancellation promptly is a documented Swift guarantee, unlike
    /// `ThumbnailService.render`'s cooperative `Task.isCancelled` checks (see
    /// `ThumbnailServiceTests`' determinism-decision doc comments for why THOSE can't be tested
    /// this way).
    func testHoverDwellReturnsCancelledEarlyRatherThanSwallowingCancellation() async throws {
        let task = Task { await waitOutHoverDwell(.seconds(30)) }
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelledEarly,
                       "a row the pointer only swept past must never fall through to requesting "
                       + "a thumbnail")
    }
}
