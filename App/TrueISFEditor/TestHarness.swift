import Foundation

/// True when the app is running as an XCTest TEST_HOST. The test target injects into the real
/// app, so every suite run launches (and terminates) it — anything that would block or disrupt
/// the run on the user's screen gates on this: the ⌘Q discard-confirm modal, window
/// focus-stealing, and first-run sample state.
enum TestHarness {
    static let isActive =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}
