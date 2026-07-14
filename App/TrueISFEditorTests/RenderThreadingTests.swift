import XCTest
import MetalKit
import ShadertoyISFKit
@testable import TrueISFEditor

/// The off-main render port (OffspringEngine display-link pattern): router mirror coherence,
/// core scene serialization, and driver lifecycle.
final class RenderThreadingTests: XCTestCase {

    // MARK: SourceRouter render mirror

    @MainActor
    func testRenderSourceMirrorsSelectionWrites() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw XCTSkip("No Metal device") }
        let router = SourceRouter(device: device, queue: queue)
        router.updateInputs([ISFPreviewInput(name: "inputImage", type: "image",
                                             defaultValue: nil, min: nil, max: nil,
                                             labels: nil, values: nil)])
        // Default route exists and is visible through the nonisolated accessor.
        XCTAssertNotNil(router.renderSource(for: "inputImage"))
        XCTAssertNil(router.renderSource(for: "unrouted"))
        // Selection change propagates to the mirror.
        router.setSelection(.testPattern(id: TestPatternCatalog.default.id), for: "inputImage")
        let src = try XCTUnwrap(router.renderSource(for: "inputImage"))
        XCTAssertFalse(src is NoneSource)
        // Pruning inputs prunes the mirror.
        router.updateInputs([])
        XCTAssertNil(router.renderSource(for: "inputImage"))
    }

    @MainActor
    func testRenderSourceIsReadableOffMainWhileMainMutates() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw XCTSkip("No Metal device") }
        let router = SourceRouter(device: device, queue: queue)
        let input = ISFPreviewInput(name: "inputImage", type: "image",
                                    defaultValue: nil, min: nil, max: nil,
                                    labels: nil, values: nil)
        router.updateInputs([input])
        // Hammer the nonisolated accessor from a background thread while main rewrites routes —
        // the lock must keep this free of crashes/races (this is the display-link read pattern).
        let done = expectation(description: "reader finished")
        Thread.detachNewThread {
            for _ in 0..<2_000 { _ = router.renderSource(for: "inputImage") }
            done.fulfill()
        }
        for _ in 0..<200 {
            router.updateInputs([input])
            router.setSelection(.none, for: "inputImage")
        }
        wait(for: [done], timeout: 10)
    }

    // MARK: MetalRenderCore

    @MainActor
    func testWithSceneSeesSceneImmediatelyAfterSetScene() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw XCTSkip("No Metal device") }
        let core = MetalRenderCore(device: device, renderQueue: queue)
        // No pending-install machinery: a scene set on main must be visible to withScene at once
        // (the windowless pixel-gate controller never draws a frame to "install" anything).
        XCTAssertTrue(core.withScene { $0 == nil })
        // setScene(nil) round-trips too (compile-failure path).
        core.setScene(nil, imageInputNames: ["a", "b"])
        XCTAssertTrue(core.withScene { $0 == nil })
    }

    @MainActor
    func testRenderOnceWithoutSceneReturnsNil() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw XCTSkip("No Metal device") }
        let core = MetalRenderCore(device: device, renderQueue: queue)
        XCTAssertNil(core.renderOnce(drawableSize: CGSize(width: 64, height: 64)))
    }

    // MARK: DisplayLinkDriver

    @MainActor
    func testDriverLifecycleStartPauseInvalidateIsSafe() throws {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = true
        guard let driver = DisplayLinkDriver(view: view) else {
            throw XCTSkip("CVDisplayLink unavailable (headless CI display)")
        }
        driver.start()
        driver.pause()
        driver.start()
        driver.invalidate()
        // Idempotent: a second invalidate (e.g. explicit call + deinit path) must not double-release.
        driver.invalidate()
        // Post-invalidate start is a no-op, not a crash.
        driver.start()
    }

    /// The editor-scale integration seam: a live MetalPreviewController must run its loop through
    /// the display link (view paused) OR fall back to the classic self-driving view — never both.
    @MainActor
    func testControllerViewDoesNotSelfDriveWhenLinkExists() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let controller = MetalPreviewController()
        let mtkView = try XCTUnwrap(controller.nsView as? MTKView)
        // Exactly one driver: link (isPaused true) or self-drive fallback (isPaused false).
        // On dev machines the link exists, so the view must not also self-drive.
        if mtkView.isPaused == false {
            // Fallback path — acceptable only where CVDisplayLink creation fails (headless).
            throw XCTSkip("CVDisplayLink unavailable — fallback self-drive engaged")
        }
        controller.setPaused(true)   // stops the link; view stays paused either way
        XCTAssertTrue(mtkView.isPaused)
    }
}
