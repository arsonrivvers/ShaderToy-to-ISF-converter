import XCTest
@testable import TrueISFEditor

@MainActor
final class AppQuitGuardTests: XCTestCase {
    /// Headless test mode: the test target's TEST_HOST is the real app, so every suite run
    /// terminates it. A dirty document must NOT pop the discard-confirm modal under XCTest —
    /// an unclicked modal blocks the harness until it kills the host.
    func testTerminatesImmediatelyUnderTestHarnessEvenWhenDirty() {
        let quitGuard = AppQuitGuard()
        var confirmAsked = false
        quitGuard.hasUnsavedChanges = { true }
        quitGuard.confirmDiscard = { confirmAsked = true; return false }

        XCTAssertEqual(quitGuard.applicationShouldTerminate(NSApp), .terminateNow,
                       "quit guard must never block termination under the test harness")
        XCTAssertFalse(confirmAsked, "discard-confirm alert must not run under the test harness")
    }

    /// The host must be an accessory process under XCTest — no dock icon, no activation, no
    /// focus stealing from whatever the user is doing while suites run.
    func testHostRunsAsAccessoryProcessUnderTestHarness() {
        XCTAssertEqual(NSApp.activationPolicy(), .accessory,
                       "test host must not present as a regular foreground app")
    }

    /// Library scan must stay inside the app bundle under XCTest: scanning the user's real ISF
    /// folders (and persisted added folders) from a test host triggers TCC permission prompts
    /// on the user's screen and touches real user data.
    func testStandardLibrariesStayInBundleUnderTestHarness() {
        let library = LibraryModel()
        library.loadStandardLibraries()
        let bundleRoot = Bundle.main.resourcePath ?? "/nonexistent"
        for source in library.sources {
            XCTAssertTrue(source.url.path.hasPrefix(bundleRoot),
                          "unexpected non-bundle library source under test: \(source.url.path)")
        }
    }

    /// The host shares the user's real defaults domain — adding folders from a test must never
    /// rewrite the user's persisted added-folders list.
    func testAddFolderDoesNotTouchRealDefaultsUnderTestHarness() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitguard-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        LibraryModel().addFolder(dir)
        let persisted = UserDefaults.standard.array(forKey: "TrueISFEditor.addedFolders") as? [String] ?? []
        XCTAssertFalse(persisted.contains(dir.path),
                       "test-added folder leaked into the user's real defaults")
    }
}
