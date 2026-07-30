import XCTest

final class BlackoutKeyMonitorTests: XCTestCase {
    private func key(_ code: UInt16, command: Bool = false,
                     down: Bool = true, repeated: Bool = false) -> KeyEventDescriptor {
        KeyEventDescriptor(keyCode: code, hasCommand: command, isDown: down, isRepeat: repeated)
    }

    private let bKey: UInt16 = 11        // kVK_ANSI_B
    private let escapeKey: UInt16 = 53   // kVK_Escape
    private let fKey: UInt16 = 3         // kVK_ANSI_F
    private let aKey: UInt16 = 0         // kVK_ANSI_A

    func testCommandBTogglesTheLatch() {
        XCTAssertEqual(BlackoutKeyMonitor.action(for: key(bKey, command: true)), .toggleLatch)
    }

    func testBareBDoesNothing() {
        // A bare letter key would be swallowed by the library search field — and blackout must not
        // have a "reachable except while typing" caveat.
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(bKey)))
    }

    func testEscapeIsMomentary() {
        XCTAssertEqual(BlackoutKeyMonitor.action(for: key(escapeKey)), .beginHold)
        XCTAssertEqual(BlackoutKeyMonitor.action(for: key(escapeKey, down: false)), .endHold)
    }

    func testAutoRepeatDoesNotRetriggerTheHold() {
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(escapeKey, repeated: true)))
    }

    func testCommandBAutoRepeatDoesNotStrobeTheLatch() {
        // Holding cmd-B must not flash the room.
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(bKey, command: true, repeated: true)))
    }

    func testUnrelatedKeysAreIgnored() {
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(aKey)))
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(aKey, command: true)))
    }

    // MARK: output toggle

    func testCommandShiftFTogglesTheOutputWindow() {
        XCTAssertTrue(BlackoutKeyMonitor.isOutputToggle(key(fKey, command: true), hasShift: true))
    }

    func testCommandFWithoutShiftIsNotTheOutputToggle() {
        XCTAssertFalse(BlackoutKeyMonitor.isOutputToggle(key(fKey, command: true), hasShift: false))
    }

    func testTheOutputToggleIsNotABlackoutAction() {
        // The panic path stays a two-case switch; the output toggle must never reach it.
        XCTAssertNil(BlackoutKeyMonitor.action(for: key(fKey, command: true)))
    }

    func testEscapeIsNotAnOutputToggle() {
        // A panic key that also closed the projector window would be a bad surprise mid-set.
        XCTAssertFalse(BlackoutKeyMonitor.isOutputToggle(key(escapeKey), hasShift: false))
        XCTAssertFalse(BlackoutKeyMonitor.isOutputToggle(key(escapeKey), hasShift: true))
    }

    @MainActor
    func testTheMonitorDrivesTheMixer() {
        let mixer = MixerState()
        let monitor = BlackoutKeyMonitor(mixer: mixer)
        monitor.apply(.toggleLatch)
        XCTAssertTrue(mixer.isBlackedOut)
        monitor.apply(.beginHold)
        monitor.apply(.endHold)
        XCTAssertTrue(mixer.isBlackedOut, "The latch survives a momentary tap")
        monitor.apply(.toggleLatch)
        XCTAssertFalse(mixer.isBlackedOut)
    }
}
