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

    func test_buildsRequestURL_withIDAndKey() {
        let url = ShadertoyClient.apiURL(id: "Ms2SD1", key: "ABC123")
        XCTAssertEqual(url.absoluteString, "https://www.shadertoy.com/api/v1/shaders/Ms2SD1?key=ABC123")
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
        let shader = try await client.fetchShader(id: "Ms2SD1")
        XCTAssertEqual(shader.info.name, "Test Single")
        XCTAssertEqual(fetcher.calls, 2)
    }

    // #6: retry on 5xx, then surface httpError if it persists.
    func test_fetch_retriesOn500_thenThrowsHTTPError() async throws {
        let fetcher = SequenceFetcher([.success((Data(), 500))])
        let client = ShadertoyClient(key: "k", fetcher: fetcher)
        do {
            _ = try await client.fetchShader(id: "Ms2SD1")
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
