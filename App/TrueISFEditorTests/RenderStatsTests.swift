import XCTest
@testable import TrueISFEditor

final class RenderStatsTests: XCTestCase {

    func testNoSnapshotBeforeIntervalElapses() {
        var acc = RenderStatsAccumulator(interval: 0.5)
        XCTAssertNil(acc.frame(at: 0.0))      // opens the window
        XCTAssertNil(acc.frame(at: 0.1))
        XCTAssertNil(acc.frame(at: 0.4))
    }

    func testFPSIsFramesOverElapsedWindow() throws {
        var acc = RenderStatsAccumulator(interval: 0.5)
        XCTAssertNil(acc.frame(at: 0.0))
        // 30 frames at 60 Hz land exactly on the 0.5s window edge.
        var snapshot: RenderStats?
        for i in 1...30 {
            snapshot = acc.frame(at: Double(i) / 60.0) ?? snapshot
        }
        let stats = try XCTUnwrap(snapshot)
        XCTAssertEqual(stats.fps, 60.0, accuracy: 0.01)
        XCTAssertNil(stats.gpuMs)   // no GPU samples reported
    }

    func testGPUTimeAveragesAcrossWindow() throws {
        var acc = RenderStatsAccumulator(interval: 0.5)
        XCTAssertNil(acc.frame(at: 0.0))
        acc.addGPUTime(seconds: 0.002)
        acc.addGPUTime(seconds: 0.004)
        let stats = try XCTUnwrap(acc.frame(at: 0.6))
        XCTAssertEqual(try XCTUnwrap(stats.gpuMs), 3.0, accuracy: 0.001)   // mean of 2ms and 4ms
    }

    func testZeroOrNegativeGPUDurationIsIgnored() throws {
        // gpuStartTime/gpuEndTime read 0 on some failure paths → duration 0 must not skew the mean.
        var acc = RenderStatsAccumulator(interval: 0.5)
        XCTAssertNil(acc.frame(at: 0.0))
        acc.addGPUTime(seconds: 0)
        acc.addGPUTime(seconds: -1)
        acc.addGPUTime(seconds: 0.002)
        let stats = try XCTUnwrap(acc.frame(at: 0.6))
        XCTAssertEqual(try XCTUnwrap(stats.gpuMs), 2.0, accuracy: 0.001)
    }

    func testWindowRestartsAfterSnapshot() throws {
        var acc = RenderStatsAccumulator(interval: 0.5)
        XCTAssertNil(acc.frame(at: 0.0))
        XCTAssertNotNil(acc.frame(at: 0.6))
        // New window: nothing until another interval elapses, then fps reflects only new frames.
        XCTAssertNil(acc.frame(at: 0.7))
        XCTAssertNil(acc.frame(at: 0.8))
        let stats = try XCTUnwrap(acc.frame(at: 1.2))
        XCTAssertEqual(stats.fps, 3.0 / 0.6, accuracy: 0.01)
    }

    func testResetDropsTheOpenWindow() throws {
        var acc = RenderStatsAccumulator(interval: 0.5)
        XCTAssertNil(acc.frame(at: 0.0))
        acc.addGPUTime(seconds: 0.002)
        acc.reset()
        // Post-reset the first frame only reopens the window — even far past the old interval.
        XCTAssertNil(acc.frame(at: 10.0))
        let stats = try XCTUnwrap(acc.frame(at: 10.6))
        XCTAssertNil(stats.gpuMs)   // pre-reset GPU sample must not leak into the new window
    }

    func testReadoutLabelFormatting() {
        XCTAssertEqual(RenderStats(fps: 59.94, gpuMs: 1.26).readoutLabel, "60 FPS · 1.3 ms GPU")
        XCTAssertEqual(RenderStats(fps: 30.2, gpuMs: nil).readoutLabel, "30 FPS")
    }
}
