import XCTest
@testable import TrueISFEditor

@MainActor
final class AppQuitGuardTests: XCTestCase {
    /// The discard-confirm modal is retired until launch readiness. Termination must never block
    /// on a modal sheet in development or under the test host.
    func testTerminatesImmediatelyWithoutDiscardConfirmation() {
        let quitGuard = AppQuitGuard()
        XCTAssertEqual(quitGuard.applicationShouldTerminate(NSApp), .terminateNow,
                       "termination must never block on the retired discard-confirm modal")
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
