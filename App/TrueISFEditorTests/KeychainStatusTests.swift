import XCTest
import Security
@testable import TrueISFEditor

/// N24 — a Keychain save failure was an `assertionFailure` (a no-op in release), silently dropping
/// the user's API key. The status now maps to a user-visible message. (No live keychain writes
/// here — the test host shares the real app's keychain service.)
final class KeychainStatusTests: XCTestCase {
    func testSuccessProducesNoMessage() {
        XCTAssertNil(KeychainStore.saveErrorMessage(for: errSecSuccess))
    }

    func testFailureProducesUserVisibleMessage() {
        let msg = KeychainStore.saveErrorMessage(for: errSecNotAvailable)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.lowercased().contains("keychain"), msg!)
    }
}
