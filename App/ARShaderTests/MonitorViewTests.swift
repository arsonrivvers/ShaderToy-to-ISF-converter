import XCTest
import MetalKit

@MainActor
final class MonitorViewTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var renderer: InstrumentRenderer!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        renderer = InstrumentRenderer(device: device, queue: queue, mixer: MixerState())
    }

    func testRegisteredMonitorsAreDrawnOncePerFrame() throws {
        let monitor = CountingPresentingView(device: device, queue: queue)
        renderer.registerMonitor(monitor)
        renderer.renderFrame()
        XCTAssertEqual(monitor.drawRequests, 1,
                       "One instrument frame drives exactly one draw per monitor")
        renderer.renderFrame()
        XCTAssertEqual(monitor.drawRequests, 2)
    }

    func testUnregisteredMonitorsStopBeingDrawn() throws {
        let monitor = CountingPresentingView(device: device, queue: queue)
        renderer.registerMonitor(monitor)
        renderer.renderFrame()
        renderer.unregisterMonitor(monitor)
        renderer.renderFrame()
        XCTAssertEqual(monitor.drawRequests, 1)
    }

    func testTheRendererDoesNotRetainMonitors() throws {
        // A monitor list that retains its views leaks a window's worth of Metal state every time a
        // panel closes. Deliberately NOT unregistered before the check: weak registration must be
        // what releases it.
        weak var weakMonitor: CountingPresentingView?
        autoreleasepool {
            let monitor = CountingPresentingView(device: device, queue: queue)
            weakMonitor = monitor
            renderer.registerMonitor(monitor)
        }
        XCTAssertNil(weakMonitor)
        renderer.renderFrame()   // must not crash on the emptied slot
    }

    // MARK: freeze / off

    private func makeCoordinator() -> MonitorViewport.Coordinator {
        let c = MonitorViewport.Coordinator(device: device, queue: queue)
        c.renderer = renderer
        return c
    }

    private func loadDeckOne(_ fixtureName: String) throws {
        let deck = renderer.deck(.one)
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: fixtureName, withExtension: "fs", subdirectory: "Fixtures"))
        let done = expectation(description: "compile \(fixtureName)")
        deck.onCompileFinished = { done.fulfill() }
        deck.load(source: try String(contentsOf: url, encoding: .utf8), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        deck.onCompileFinished = nil
        XCTAssertNil(deck.compileError)
    }

    private func meanRGB(of texture: MTLTexture) throws -> SIMD3<Double> {
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: texture, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testALiveMonitorPullsAFreshTextureEveryDraw() throws {
        let coordinator = makeCoordinator()
        var pulls = 0
        for _ in 0..<3 {
            _ = coordinator.currentTexture { pulls += 1; return nil }
        }
        XCTAssertEqual(pulls, 3)
    }

    /// The bug the Milestone 1 smoke found: freeze held a REFERENCE to a texture that keeps being
    /// overwritten, so the monitor carried on showing live video. A freeze must survive the source
    /// contents changing underneath it.
    func testAFrozenMonitorSurvivesTheSourceContentsChanging() throws {
        try loadDeckOne("solid_red")
        renderer.renderFrame()

        let coordinator = makeCoordinator()
        let renderer = self.renderer!
        coordinator.setFrozen(true) { renderer.monitorTexture(.deck(.one)) }

        // Swap the deck to green and keep rendering — the SAME deck texture object is reused, so
        // a reference-holding freeze would now be showing green.
        try loadDeckOne("solid_green")
        for _ in 0..<5 { renderer.renderFrame() }

        let held = try XCTUnwrap(coordinator.currentTexture { nil })
        let rgb = try meanRGB(of: held)
        XCTAssertEqual(rgb.x, 1.0, accuracy: 0.02, "still the RED frame the operator froze")
        XCTAssertLessThan(rgb.y, 0.02, "if this is green, freeze is holding a reference again")
    }

    func testAFrozenMonitorStopsPullingFromTheRenderer() throws {
        try loadDeckOne("solid_red")
        renderer.renderFrame()
        let coordinator = makeCoordinator()
        let renderer = self.renderer!
        coordinator.setFrozen(true) { renderer.monitorTexture(.deck(.one)) }

        var pullsWhileFrozen = 0
        _ = coordinator.currentTexture { pullsWhileFrozen += 1; return nil }
        XCTAssertEqual(pullsWhileFrozen, 0, "A frozen monitor must not ask the renderer for more")
    }

    func testUnfreezingResumesPulling() throws {
        try loadDeckOne("solid_red")
        renderer.renderFrame()
        let coordinator = makeCoordinator()
        let renderer = self.renderer!
        coordinator.setFrozen(true) { renderer.monitorTexture(.deck(.one)) }
        coordinator.setFrozen(false) { nil }

        var pulls = 0
        _ = coordinator.currentTexture { pulls += 1; return nil }
        XCTAssertEqual(pulls, 1)
        XCTAssertFalse(coordinator.isFrozen)
    }

    func testRepeatedSetFrozenDoesNotRecapture() throws {
        // SwiftUI calls updateNSView freely; only the rising EDGE may capture, or the "frozen"
        // frame would silently advance every layout pass.
        try loadDeckOne("solid_red")
        renderer.renderFrame()
        let coordinator = makeCoordinator()
        let renderer = self.renderer!
        var captures = 0
        for _ in 0..<4 {
            coordinator.setFrozen(true) { captures += 1; return renderer.monitorTexture(.deck(.one)) }
        }
        XCTAssertEqual(captures, 1)
    }

    func testFreezingAnEmptyMonitorLeavesItBlackRatherThanStuck() throws {
        // Deck 2 has no shader: there is nothing to capture, and the tile must not wedge.
        let coordinator = makeCoordinator()
        let renderer = self.renderer!
        coordinator.setFrozen(true) { renderer.monitorTexture(.deck(.two)) }
        XCTAssertNil(coordinator.currentTexture { nil })
    }

    func testAnOffMonitorReportsNoTextureAtAll() throws {
        let coordinator = makeCoordinator()
        renderer.renderFrame()
        coordinator.isOff = true
        var pulls = 0
        let tex = coordinator.currentTexture { pulls += 1; return nil }
        XCTAssertNil(tex, "Off must render black, not the last frame")
        XCTAssertEqual(pulls, 0)
    }

    func testOffWinsOverFreeze() throws {
        try loadDeckOne("solid_red")
        renderer.renderFrame()
        let coordinator = makeCoordinator()
        let renderer = self.renderer!
        coordinator.setFrozen(true) { renderer.monitorTexture(.deck(.one)) }
        coordinator.isOff = true
        XCTAssertNil(coordinator.currentTexture { nil })
    }
}

/// Counts draw requests without needing a window or a drawable.
private final class CountingPresentingView: TexturePresentingView {
    private(set) var drawRequests = 0
    override func draw() {
        drawRequests += 1
        // Deliberately does NOT call super: there is no window, so currentDrawable is nil and the
        // real draw would early-return anyway.
    }
}
