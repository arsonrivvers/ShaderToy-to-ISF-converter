import XCTest
@testable import TrueISFEditor

/// M31 — the pop-out output window recompiled on every keystroke; updates route through a
/// debouncer so a typing burst produces one recompile.
@MainActor
final class DebouncerTests: XCTestCase {
    func testBurstCoalescesToOneCall_withLatestValue() async throws {
        let d = Debouncer(delayNanos: 50_000_000)
        var calls: [String] = []
        d.call { calls.append("a") }
        d.call { calls.append("b") }
        d.call { calls.append("c") }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls, ["c"], "only the last call of a burst may fire")
    }

    func testSpacedCallsBothFire() async throws {
        let d = Debouncer(delayNanos: 30_000_000)
        var calls = 0
        d.call { calls += 1 }
        try await Task.sleep(nanoseconds: 120_000_000)
        d.call { calls += 1 }
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(calls, 2)
    }

    func testCancelStopsPendingCall() async throws {
        let d = Debouncer(delayNanos: 50_000_000)
        var calls = 0
        d.call { calls += 1 }
        d.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(calls, 0)
    }
}
