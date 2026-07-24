import XCTest
@testable import TrueISFEditor

private actor ParentLoadCancellationProbe {
    private(set) var started = false
    private(set) var cancelled = false

    func markStarted() { started = true }
    func markCancelled() { cancelled = true }
}

@MainActor
final class RemixParentLoadStateTests: XCTestCase {
    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func request(slot: ParentSlot = .b) -> RemixParentRequest {
        RemixParentRequest(
            id: requestID,
            slot: slot,
            spec: .shadertoyLink("https://www.shadertoy.com/view/abc123"),
            displayInput: "abc123"
        )
    }

    func test_request_retainsTargetAndInputAcrossVerification() {
        let request = request()
        let state = RemixParentLoadState.fetching(request)
            .transitioning(to: .verificationRequired, requestID: request.id)
            .transitioning(to: .waitingForHuman, requestID: request.id)

        XCTAssertEqual(state.request?.slot, .b)
        XCTAssertEqual(state.request?.displayInput, "abc123")
    }

    func test_confirmedClearance_resumesExactlyOnce() {
        let request = request()
        let waiting = RemixParentLoadState.waitingForHuman(request)
        let resumed = waiting.transitioning(to: .cleared, requestID: request.id)

        XCTAssertEqual(resumed, .resuming(request))
        XCTAssertEqual(
            resumed.transitioning(to: .cleared, requestID: request.id),
            .resuming(request)
        )
    }

    func test_staleCompletionToken_isIgnored() {
        let request = request()
        let state = RemixParentLoadState.fetching(request)

        XCTAssertEqual(
            state.transitioning(to: .succeeded, requestID: UUID()),
            state
        )
    }

    func test_cancel_preservesInputAndTargetForRetry() {
        let request = request()
        let cancelled = RemixParentLoadState.fetching(request).cancelled()

        XCTAssertEqual(cancelled, .cancelled(request))
        XCTAssertEqual(cancelled.request, request)
    }

    func test_furtherVerification_returnsWaitingStateNotSuccess() {
        let request = request()
        let state = RemixParentLoadState.resuming(request)
            .transitioning(to: .verificationRequired, requestID: request.id)
            .transitioning(to: .waitingForHuman, requestID: request.id)

        XCTAssertEqual(state, .waitingForHuman(request))
    }

    func test_success_returnsFocusTargetForOriginatingParentControl() {
        let request = request(slot: .a)
        let state = RemixParentLoadState.succeeded(slot: .a, requestID: request.id)

        XCTAssertEqual(state.focusTarget, .parentSource(.a))
    }

    func test_snapshotRoundTrip_reconstructsLiveShadertoyRequestWithSameIdentity() throws {
        let request = request()
        let snapshot = request.snapshot(phase: .verificationRequired)
        let restored = try XCTUnwrap(RemixParentRequest(snapshot: snapshot))

        XCTAssertEqual(restored, request)
        XCTAssertEqual(snapshot.phase, .verificationRequired)
    }

    func test_verificationRequired_waitsBeyondNetworkTimeoutUntilLegitimateClearance() async throws {
        var elapsed: TimeInterval = 0
        var states: [WebKitShaderFetcher.State] = []

        try await WebKitShaderFetcher.waitForReadiness(
            timeout: 20,
            now: { elapsed },
            sleep: { elapsed += 10 },
            pageInfo: {
                elapsed < 60
                    ? (title: "Just a moment...", host: "www.shadertoy.com")
                    : (title: "Shader abc123", host: "www.shadertoy.com")
            },
            onState: { states.append($0) }
        )

        XCTAssertGreaterThan(elapsed, 20)
        XCTAssertEqual(states, [.verificationRequired, .cleared])
    }

    func test_noninteractiveLoad_keepsBoundedNetworkTimeout() async {
        var elapsed: TimeInterval = 0

        do {
            try await WebKitShaderFetcher.waitForReadiness(
                timeout: 20,
                now: { elapsed },
                sleep: { elapsed += 10 },
                pageInfo: { (title: "", host: "") },
                onState: { _ in }
            )
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? WebFetchError, .challengeTimeout)
        }
    }

    func test_cancelParentLoad_cancelsOwnedTaskAndIgnoresLateResult() async throws {
        let probe = ParentLoadCancellationProbe()
        let resolver = RemixParentResolver(
            currentEditorSource: { nil },
            fetchShadertoy: { _, onState in
                onState(.verificationRequired)
                await probe.markStarted()
                do {
                    try await Task.sleep(for: .seconds(60))
                    return "unexpected on-time result"
                } catch is CancellationError {
                    await probe.markCancelled()
                    return "late ISF"
                }
            }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-parent-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { fatalError("unused") }, model: nil),
            sessionStore: RemixSessionStore(
                fileURL: directory.appendingPathComponent("session.json")
            )
        )
        let request = request()

        model.loadParent(request, from: resolver)
        while await !probe.started { await Task.yield() }
        XCTAssertEqual(model.parentLoadState, .waitingForHuman(request))

        XCTAssertEqual(model.cancelParentLoad(), .parentSource(.b))
        while await !probe.cancelled { await Task.yield() }
        XCTAssertEqual(model.parentLoadState, .cancelled(request))
        XCTAssertEqual(model.pendingParentRequest, request.snapshot(phase: .waitingForHuman))

        await Task.yield()
        XCTAssertNil(model.parentBID)
        XCTAssertEqual(model.parentLoadState, .cancelled(request))
    }

    func test_startNewSession_invalidatesParentLoadBeforeLateResultReturns() async throws {
        let probe = ParentLoadCancellationProbe()
        let resolver = RemixParentResolver(
            currentEditorSource: { nil },
            fetchShadertoy: { _, onState in
                onState(.verificationRequired)
                await probe.markStarted()
                do {
                    try await Task.sleep(for: .seconds(60))
                    return "unexpected on-time result"
                } catch is CancellationError {
                    await probe.markCancelled()
                    return "late ISF"
                }
            }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-parent-new-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { fatalError("unused") }, model: nil),
            sessionStore: RemixSessionStore(
                fileURL: directory.appendingPathComponent("session.json")
            )
        )

        model.loadParent(request(), from: resolver)
        while await !probe.started { await Task.yield() }
        model.startNewSession()
        while await !probe.cancelled { await Task.yield() }
        for _ in 0..<100 { await Task.yield() }

        XCTAssertNil(model.parentAID)
        XCTAssertNil(model.parentBID)
        XCTAssertEqual(model.parentLoadState, .idle)
        XCTAssertNil(model.pendingParentRequest)
    }
}
