import XCTest
import Combine

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

    /// M25 — a compile still in flight when a newer load() starts must be dropped, not published:
    /// loading bad-then-good back-to-back may never surface the stale bad result. (Both loads happen
    /// before either applyCompile lands, so without a generation token the bad error publishes
    /// transiently over the good source.)
    func testStaleCompileFromSupersededLoad_isNeverPublished() async throws {
        let c = MetalPreviewController()
        var publishedErrors: [String] = []
        let sub = c.$compileError.sink { if let e = $0 { publishedErrors.append(e) } }
        defer { sub.cancel() }
        c.load(isf: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ this is not glsl }")
        c.load(isf: goodISF)   // supersedes before the bad compile can land
        try await waitUntil { c.compileValid == true }
        XCTAssertTrue(publishedErrors.isEmpty,
                      "superseded load's error leaked through: \(publishedErrors)")
    }

    func testBadISFReportsError() async throws {
        let c = MetalPreviewController()
        c.load(isf: "/*{ \"ISFVSN\":\"2\" }*/ void main(){ this is not glsl }")
        try await waitUntil { c.compileError != nil }
        XCTAssertFalse(c.compileValid)
        XCTAssertNotNil(c.compileError)
    }

    func testParsesInputs() async throws {
        let isf = """
        /*{ "ISFVSN":"2", "INPUTS":[
          {"NAME":"level","TYPE":"float","DEFAULT":0.5,"MIN":0.0,"MAX":1.0},
          {"NAME":"on","TYPE":"bool","DEFAULT":true},
          {"NAME":"tint","TYPE":"color","DEFAULT":[1,0,0,1]}
        ]}*/
        void main(){ gl_FragColor = tint * level * (on?1.0:0.0); }
        """
        let c = MetalPreviewController()
        c.load(isf: isf)
        try await waitUntil { c.inputs.count == 3 }
        XCTAssertEqual(Set(c.inputs.map { $0.name }), ["level","on","tint"])
        XCTAssertEqual(c.inputs.first { $0.name == "level" }?.type, "float")
    }

    func testRendersTextureForGoodShader() async throws {
        let c = MetalPreviewController()
        c.setRenderSize(width: 64, height: 64, fitToWindow: false)
        c.load(isf: goodISF)
        try await waitUntil { c.compileValid }
        let tex = c.renderOnce()
        XCTAssertNotNil(tex)
        XCTAssertEqual(tex?.width, 64)
    }

    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
