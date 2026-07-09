import XCTest
@testable import TrueISFEditor

/// End-to-end pixel gate through the real ISFMSLKit render path (GPU). Same compile-poll pattern
/// as MetalPreviewControllerTests.
@MainActor
final class PixelGateIntegrationTests: XCTestCase {
    private func compile(_ isf: String, timeout: TimeInterval = 20) async -> MetalPreviewController? {
        let c = MetalPreviewController()
        c.load(isf: isf)
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if c.compileValid { return c }
            if c.compileError != nil { return nil }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }

    private let header = """
    /*{ "DESCRIPTION": "gate test", "CREDIT": "test", "CATEGORIES": ["Generator"], "INPUTS": [] }*/
    """

    func testAnimatedShaderIsOK() async throws {
        let maybe = await compile(header + """

        void main() { gl_FragColor = vec4(fract(isf_FragNormCoord.x + TIME), 0.5, 0.5, 1.0); }
        """)
        let c = try XCTUnwrap(maybe)
        XCTAssertEqual(c.runPixelGate(), .ok)
    }

    func testBlackShaderFailsBlack() async throws {
        let maybe = await compile(header + """

        void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }
        """)
        let c = try XCTUnwrap(maybe)
        XCTAssertEqual(c.runPixelGate(), .black)
    }

    func testStaticShaderWarnsStatic() async throws {
        let maybe = await compile(header + """

        void main() { gl_FragColor = vec4(isf_FragNormCoord.x, 0.3, 0.2, 1.0); }
        """)
        let c = try XCTUnwrap(maybe)
        XCTAssertEqual(c.runPixelGate(), .constant)
    }

    func testNaNShaderFails() async throws {
        // 0.0/0.0 at runtime (TIME*0.0 defeats constant folding). On a float output this is NAN;
        // if the engine output is 8-bit the NaN clamps to black — either way it must FAIL.
        let maybe = await compile(header + """

        void main() { gl_FragColor = vec4(0.0 / max(TIME * 0.0, 0.0)); }
        """)
        let c = try XCTUnwrap(maybe)
        XCTAssertTrue(c.runPixelGate().isFail)
    }

    func testImageInputGetsPatternBound() async throws {
        // Passthrough of the bound pattern: must NOT be black (proves the binding worked).
        // It renders the same static pattern every frame, so STATIC (or OK) is the pass.
        let isf = """
        /*{ "DESCRIPTION": "gate test", "CREDIT": "test", "CATEGORIES": ["Filter"],
            "INPUTS": [{ "NAME": "inputImage", "TYPE": "image" }] }*/

        void main() { gl_FragColor = IMG_NORM_PIXEL(inputImage, isf_FragNormCoord); }
        """
        let maybe = await compile(isf)
        let c = try XCTUnwrap(maybe)
        let v = c.runPixelGate()
        XCTAssertFalse(v.isFail, "bound pattern must prevent false-black (got \(v.rawValue))")
    }
}
