import XCTest

final class FetchStrategyTests: XCTestCase {
    func test_noKey_usesWebView() { XCTAssertEqual(FetchStrategy.select(hasKey: false), .webView) }
    func test_withKey_usesApi() { XCTAssertEqual(FetchStrategy.select(hasKey: true), .api) }
}
