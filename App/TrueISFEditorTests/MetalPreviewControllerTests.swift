import XCTest

@MainActor
final class MetalPreviewControllerTests: XCTestCase {
    let goodISF = """
    /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [] }*/
    void main() { gl_FragColor = vec4(1.0); }
    """
    // ES3 dynamic-loop pattern WebGL1 rejects but ISFMSLKit accepts.
    let es3ISF = """
    /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [{"NAME":"n","TYPE":"long","DEFAULT":4}] }*/
    void main() { vec3 c=vec3(0.0); for (int i=0;i<int(n);i++){ c+=vec3(0.1); } gl_FragColor=vec4(c,1.0); }
    """

    func testGoodISFCompiles() async throws {
        let c = MetalPreviewController()
        c.load(isf: goodISF)
        try await waitUntil { c.compileValid == true }
        XCTAssertTrue(c.compileValid)
        XCTAssertNil(c.compileError)
    }

    func testES3ISFCompiles() async throws {
        let c = MetalPreviewController()
        c.load(isf: es3ISF)
        try await waitUntil { c.compileValid == true }
        XCTAssertTrue(c.compileValid, "ISFMSLKit should accept ES3 dynamic loops")
    }

    func testBadISFReportsError() async throws {
        let c = MetalPreviewController()
        c.load(isf: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ this is not glsl }")
        try await waitUntil { c.compileError != nil }
        XCTAssertFalse(c.compileValid)
        XCTAssertNotNil(c.compileError)
    }

    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
