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
        let c = MonitorViewport.Coordinator()
        c.renderer = renderer
        return c
    }

    func testALiveMonitorPullsAFreshTextureEveryDraw() throws {
        let coordinator = makeCoordinator()
        var pulls = 0
        for _ in 0..<3 {
            _ = coordinator.currentTexture { pulls += 1; return nil }
        }
        XCTAssertEqual(pulls, 3)
    }

    func testAFrozenMonitorStopsPullingAndKeepsItsLastFrame() throws {
        let coordinator = makeCoordinator()
        renderer.renderFrame()
        let live = renderer.rawMasterTexture()

        // One live pull to seed the cache, then freeze.
        _ = coordinator.currentTexture { live }
        coordinator.isFrozen = true

        var pullsWhileFrozen = 0
        let held = coordinator.currentTexture { pullsWhileFrozen += 1; return nil }
        XCTAssertEqual(pullsWhileFrozen, 0, "A frozen monitor must not ask the renderer for more")
        XCTAssertTrue(held === live, "It keeps showing the frame the operator froze")
    }

    func testAnOffMonitorReportsNoTextureAtAll() throws {
        let coordinator = makeCoordinator()
        renderer.renderFrame()
        _ = coordinator.currentTexture { self.renderer.rawMasterTexture() }
        coordinator.isOff = true

        var pulls = 0
        let tex = coordinator.currentTexture { pulls += 1; return nil }
        XCTAssertNil(tex, "Off must render black, not the last frame")
        XCTAssertEqual(pulls, 0)
    }

    func testOffWinsOverFreeze() throws {
        let coordinator = makeCoordinator()
        renderer.renderFrame()
        _ = coordinator.currentTexture { self.renderer.rawMasterTexture() }
        coordinator.isFrozen = true
        coordinator.isOff = true
        XCTAssertNil(coordinator.currentTexture { nil })
    }

    func testUnfreezingResumesPulling() throws {
        let coordinator = makeCoordinator()
        coordinator.isFrozen = true
        _ = coordinator.currentTexture { XCTFail("should not pull while frozen"); return nil }
        coordinator.isFrozen = false
        var pulls = 0
        _ = coordinator.currentTexture { pulls += 1; return nil }
        XCTAssertEqual(pulls, 1)
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
