import XCTest
@testable import TrueISFEditor

@MainActor
final class RemixParentResolverTests: XCTestCase {
    func test_pastedISF_returnsVerbatim() async throws {
        let r = RemixParentResolver(currentEditorSource: { nil }, fetchShadertoy: { _ in "X" })
        let out = try await r.resolve(.pastedISF("/*{}*/ body"))
        XCTAssertEqual(out, "/*{}*/ body")
    }
    func test_currentEditor_usesClosure_orThrows() async throws {
        let r = RemixParentResolver(currentEditorSource: { "/*{E}*/" }, fetchShadertoy: { _ in "X" })
        let editorOut = try await r.resolve(.currentEditor)
        XCTAssertEqual(editorOut, "/*{E}*/")
        let empty = RemixParentResolver(currentEditorSource: { nil }, fetchShadertoy: { _ in "X" })
        do { _ = try await empty.resolve(.currentEditor); XCTFail("expected throw") }
        catch RemixParentError.noEditorShader {} catch { XCTFail("wrong error: \(error)") }
    }
    func test_libraryFile_readsFromDisk() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("remix-test-\(UUID().uuidString).fs")
        try "/*{L}*/ lib".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let r = RemixParentResolver(currentEditorSource: { nil }, fetchShadertoy: { _ in "X" })
        let libOut = try await r.resolve(.libraryFile(url))
        XCTAssertEqual(libOut, "/*{L}*/ lib")
    }
    func test_shadertoyLink_delegatesToFetchClosure() async throws {
        let r = RemixParentResolver(currentEditorSource: { nil },
                                    fetchShadertoy: { url in "ISF for \(url)" })
        let linkOut = try await r.resolve(.shadertoyLink("https://shadertoy.com/view/abc"))
        XCTAssertEqual(linkOut, "ISF for https://shadertoy.com/view/abc")
    }
}
