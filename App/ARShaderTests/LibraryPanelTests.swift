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

    // MARK: the resolving flag's generation guard (fix round 2, item 1)

    /// A one-shot async gate a test can hold closed until it chooses to open it — lets a test
    /// control the EXACT moment a stand-in render "completes" (and confirm the render call has
    /// actually STARTED, i.e. is genuinely outstanding) without depending on real GPU timing.
    private actor RenderGate {
        private var isArrived = false
        private var arrivedContinuation: CheckedContinuation<Void, Never>?
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        func waitUntilArrived() async {
            if isArrived { return }
            await withCheckedContinuation { arrivedContinuation = $0 }
        }

        func waitToBeReleased() async {
            isArrived = true
            arrivedContinuation?.resume()
            arrivedContinuation = nil
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func release() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    /// The re-review's headline finding (final fix round 2, item 1): `.task(id:)` cancellation does
    /// not stop an already-suspended instance's execution — only its OWN `Task.isCancelled` check
    /// does, and `ThumbnailService.render` has no suspension point that observes it early. So on a
    /// cold cache a superseded instance (row A) can still be mid-render when a newer instance (row
    /// B) starts, sets `isResolvingPreview = true` again, and begins ITS OWN render. Without a
    /// generation guard, A resuming and returning (cancelled or not) would clear the flag while B
    /// is still outstanding — the well would flip to `.settled` on A's stale still for the whole of
    /// B's render, which is worse than no loading state at all: it reads as "resolved" when it is
    /// not.
    ///
    /// This drives `HoverPreviewResolver.resolveHoverPreview` — the actual extracted body of the
    /// `.task(id:)` closure, not a re-derivation of its logic — with two overlapping calls gated by
    /// `RenderGate`, so the exact overlap is reproduced deterministically rather than raced against
    /// real GPU timing. Drives the resolver directly (not `LibraryPanelView`) because `@State`'s
    /// storage only functions inside a live SwiftUI view graph — see `HoverPreviewResolver`'s doc
    /// comment for the empirical confirmation of that constraint, which is why the flag's owner was
    /// moved off `@State` in the first place.
    @MainActor
    func testASupersededHoverInstanceDoesNotClearTheFlagWhileANewerOneIsOutstanding() async throws {
        let resolver = HoverPreviewResolver()
        let urlA = URL(fileURLWithPath: "/tmp/fix-round-2-row-a.fs")
        let urlB = URL(fileURLWithPath: "/tmp/fix-round-2-row-b.fs")
        let gateA = RenderGate()
        let gateB = RenderGate()

        // Row A: dwell has elapsed, the render is genuinely in flight.
        let taskA = Task {
            await resolver.resolveHoverPreview(url: urlA) { _ in
                await gateA.waitToBeReleased()
                return .unavailable
            }
        }
        await gateA.waitUntilArrived()
        XCTAssertTrue(resolver.isResolvingPreview, "sanity: A's request is outstanding")

        // The pointer has moved on — SwiftUI would cancel A's `.task(id:)` instance here. Per the
        // doc comment above, that does NOT stop A's render from running to completion.
        taskA.cancel()

        // Row B: a newer request starts and is ALSO genuinely in flight before A is allowed to
        // finish.
        let taskB = Task {
            await resolver.resolveHoverPreview(url: urlB) { _ in
                await gateB.waitToBeReleased()
                return .unavailable
            }
        }
        await gateB.waitUntilArrived()

        // Let A finish. Its `guard !Task.isCancelled` takes the early-return path — but its
        // `defer` still runs either way, and MUST see its own generation is stale.
        await gateA.release()
        _ = await taskA.value
        XCTAssertTrue(resolver.isResolvingPreview,
                      "row B's request is still outstanding — A finishing (even cancelled) must "
                      + "not clear the flag out from under it")

        // Only once B — the genuinely current request — finishes does the flag clear.
        await gateB.release()
        _ = await taskB.value
        XCTAssertFalse(resolver.isResolvingPreview,
                       "once the LAST outstanding request truly finishes, the flag must clear")
    }
}
