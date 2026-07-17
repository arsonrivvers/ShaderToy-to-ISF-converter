import XCTest
@testable import TrueISFEditor

@MainActor
final class OutputWindowManagerTests: XCTestCase {
    func testIsOpenTracksShowAndClose() {
        let manager = OutputWindowManager()
        XCTAssertFalse(manager.isOpen)

        manager.show(source: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ gl_FragColor=vec4(1.0); }")
        XCTAssertTrue(manager.isOpen)

        manager.close()
        // NSWindow.close() posts willClose synchronously on the main thread.
        XCTAssertFalse(manager.isOpen)

        // Reopening the SAME retained window (isReleasedWhenClosed=false) must flip it back.
        manager.show(source: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ gl_FragColor=vec4(1.0); }")
        XCTAssertTrue(manager.isOpen)
        manager.close()
    }
}
