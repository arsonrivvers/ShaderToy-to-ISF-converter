import XCTest
@testable import TrueISFEditor

/// M28/M29 — thumbnail coordinator lifecycle. SwiftUI recycles coordinators across node changes
/// (LazyVGrid + tree slots), so the compile-report latch and the frozen-frame push must both be
/// transition-aware, not fire-once/fire-always.
@MainActor
final class RemixThumbnailTests: XCTestCase {
    private let goodISF = """
    /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [] }*/
    void main() { gl_FragColor = vec4(1.0); }
    """
    private let goodISF2 = """
    /*{ "DESCRIPTION": "t2", "ISFVSN": "2", "INPUTS": [] }*/
    void main() { gl_FragColor = vec4(0.5); }
    """

    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// M28 — a recycled coordinator must deliver the NEW source's compile result after
    /// `sourceChanged()`; before the fix `reported` stayed true forever, so a promoted parent kept
    /// the previous shader's swatch and result.
    func testSourceChanged_reportsTheNewCompile() async throws {
        var compiles = 0
        let coordinator = RemixThumbnailView.Coordinator(
            onCompile: { _, _ in compiles += 1 }, onSnapshot: nil)
        coordinator.observe(coordinator.controller)

        coordinator.loadedISF = goodISF
        coordinator.controller.load(isf: goodISF)
        try await waitUntil { compiles == 1 }

        coordinator.sourceChanged()
        coordinator.loadedISF = goodISF2
        coordinator.controller.load(isf: goodISF2)
        try await waitUntil { compiles == 2 }
        XCTAssertEqual(compiles, 2)
    }

    /// M29 — a paused card pushes a frame only on the animating→frozen TRANSITION; re-pushing on
    /// every SwiftUI update forced one GPU frame per paused card per transcript line.
    func testFrozenFramePush_onlyOnTransition() {
        XCTAssertTrue(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: true, animating: false))
        XCTAssertFalse(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: false, animating: false),
                       "already-frozen card re-rendered per view update")
        XCTAssertFalse(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: true, animating: true))
        XCTAssertFalse(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: false, animating: true))
    }
}
