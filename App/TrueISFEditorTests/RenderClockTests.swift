import XCTest

final class RenderClockTests: XCTestCase {
    func testAdvancesWithSource() {
        var t = 100.0
        let clock = RenderClock(nowSource: { t })
        XCTAssertEqual(clock.now, 0, accuracy: 1e-9)
        t = 103.5
        XCTAssertEqual(clock.now, 3.5, accuracy: 1e-9)
    }

    func testPauseFreezes_resumeContinuesWithoutJump() {
        var t = 10.0
        let clock = RenderClock(nowSource: { t })
        t = 12.0
        clock.pause()
        t = 50.0                                    // wall time races ahead while paused
        XCTAssertEqual(clock.now, 2.0, accuracy: 1e-9)
        clock.resume()
        t = 51.0
        XCTAssertEqual(clock.now, 3.0, accuracy: 1e-9, "resume must not jump")
    }

    func testResetReturnsToZero_evenWhilePaused() {
        var t = 0.0
        let clock = RenderClock(nowSource: { t })
        t = 7.0
        clock.reset()
        XCTAssertEqual(clock.now, 0, accuracy: 1e-9)
        t = 9.0
        clock.pause()
        clock.reset()
        XCTAssertEqual(clock.now, 0, accuracy: 1e-9, "reset while paused pins elapsed to 0")
        clock.resume()
        t = 10.0
        XCTAssertEqual(clock.now, 1.0, accuracy: 1e-9)
    }

    func testDoublePauseAndDoubleResumeAreIdempotent() {
        var t = 0.0
        let clock = RenderClock(nowSource: { t })
        t = 2.0
        clock.pause(); clock.pause()
        XCTAssertEqual(clock.now, 2.0, accuracy: 1e-9)
        clock.resume(); clock.resume()
        t = 3.0
        XCTAssertEqual(clock.now, 3.0, accuracy: 1e-9)
    }
}
