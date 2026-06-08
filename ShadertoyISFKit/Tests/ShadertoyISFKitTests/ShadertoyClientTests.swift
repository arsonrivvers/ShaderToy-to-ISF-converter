import XCTest
@testable import ShadertoyISFKit

private struct StubFetcher: DataFetching {
    let result: Result<(Data, Int), Error>
    func fetch(_ url: URL) async throws -> (Data, Int) {
        switch result { case .success(let v): return v; case .failure(let e): throw e }
    }
}

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
}
