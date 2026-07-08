import XCTest
@testable import ShadertoyISFKit

private struct StubFetcher: DataFetching {
    let result: Result<(Data, Int), Error>
    func fetch(_ url: URL) async throws -> (Data, Int) {
        switch result { case .success(let v): return v; case .failure(let e): throw e }
    }
}

/// Returns a scripted sequence of results across successive calls; counts how many were made.
private final class SequenceFetcher: DataFetching, @unchecked Sendable {
    private var results: [Result<(Data, Int), Error>]
    private(set) var calls = 0
    init(_ results: [Result<(Data, Int), Error>]) { self.results = results }
    func fetch(_ url: URL) async throws -> (Data, Int) {
        calls += 1   // retry loop awaits each call serially, so no concurrent access
        let r = results.count > 1 ? results.removeFirst() : results[0]
        switch r { case .success(let v): return v; case .failure(let e): throw e }
    }
}

private enum FakeNetErr: Error { case down }

final class ShadertoyClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        return try Data(contentsOf: try XCTUnwrap(url))
    }

    func test_buildsRequestURL_withIDAndKey() throws {
        let url = try ShadertoyClient.apiURL(id: "Ms2SD1", key: "ABC123")
        XCTAssertEqual(url.absoluteString, "https://www.shadertoy.com/api/v1/shaders/Ms2SD1?key=ABC123")
    }

    // C2 — a malformed id must surface as a handled error, not crash on force-unwrap.
    func test_apiURL_malformedID_throwsInsteadOfCrashing() {
        XCTAssertThrowsError(try ShadertoyClient.apiURL(id: "bad id#frag", key: "k")) { e in
            XCTAssertEqual(e as? ShadertoyClientError, .invalidShaderID)
        }
    }

    func test_fetch_decodesShader() async throws {
        let data = try fixture("single_pass")
        let client = ShadertoyClient(key: "k", fetcher: StubFetcher(result: .success((data, 200))))
        let shader = try await client.fetchShader(id: "Ms2SD1")
        XCTAssertEqual(shader.info.name, "Test Single")
    }

    func test_fetch_emptyShaderError_mapsToNotAccessible() async throws {
        // Shadertoy returns {"Error":"Shader not found"} for private/non-API shaders.
        let data = Data(#"{"Error":"Shader not found"}"#.utf8)
        let client = ShadertoyClient(key: "k", fetcher: StubFetcher(result: .success((data, 200))))
        do {
            _ = try await client.fetchShader(id: "Ms2SD1")
            XCTFail("expected error")
        } catch let error as ShadertoyClientError {
            XCTAssertEqual(error, .shaderNotAccessible)
        }
    }

    // #6: retry once on a transient network error, then succeed.
    func test_fetch_retriesOnceOnTransientNetworkError() async throws {
        let data = try fixture("single_pass")
        let fetcher = SequenceFetcher([.failure(FakeNetErr.down), .success((data, 200))])
        let client = ShadertoyClient(key: "k", fetcher: fetcher)
        let shader = try await client.fetchShader(id: "Ms2SD1", retryDelayNanos: 0)
        XCTAssertEqual(shader.info.name, "Test Single")
        XCTAssertEqual(fetcher.calls, 2)
    }

    // N16 — the transient retry waits before re-hitting the API (an immediate 429 retry almost
    // certainly 429s again). Exercised with a tiny delay so the suite stays fast.
    func test_fetch_429_retriesAfterBackoff_thenSucceeds() async throws {
        let data = try fixture("single_pass")
        let fetcher = SequenceFetcher([.success((Data(), 429)), .success((data, 200))])
        let client = ShadertoyClient(key: "k", fetcher: fetcher)
        let shader = try await client.fetchShader(id: "Ms2SD1", retryDelayNanos: 1_000)
        XCTAssertEqual(shader.info.name, "Test Single")
        XCTAssertEqual(fetcher.calls, 2)
    }

    // #6: retry on 5xx, then surface httpError if it persists.
    func test_fetch_retriesOn500_thenThrowsHTTPError() async throws {
        let fetcher = SequenceFetcher([.success((Data(), 500))])
        let client = ShadertoyClient(key: "k", fetcher: fetcher)
        do {
            _ = try await client.fetchShader(id: "Ms2SD1", retryDelayNanos: 0)
            XCTFail("expected httpError")
        } catch ShadertoyClientError.httpError(let s) {
            XCTAssertEqual(s, 500)
            XCTAssertEqual(fetcher.calls, 2)   // tried twice
        }
    }

    // #6: a definitive error (not-accessible) is NOT retried.
    func test_fetch_notAccessible_isNotRetried() async {
        let fetcher = SequenceFetcher([.success((Data(#"{"Error":"x"}"#.utf8), 200))])
        let client = ShadertoyClient(key: "k", fetcher: fetcher)
        _ = try? await client.fetchShader(id: "Ms2SD1")
        XCTAssertEqual(fetcher.calls, 1)
    }
}
