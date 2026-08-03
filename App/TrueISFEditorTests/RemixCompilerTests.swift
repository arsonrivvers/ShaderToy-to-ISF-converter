import Foundation
import XCTest
@testable import TrueISFEditor

private final class LoaderConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var maximumInFlight = 0

    func compile(_ source: String) -> RemixCompileResult {
        lock.lock()
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        lock.unlock()

        Thread.sleep(forTimeInterval: 0.05)

        lock.lock()
        inFlight -= 1
        lock.unlock()

        return RemixCompileResult(isValid: true, diagnostic: source, errorLine: nil)
    }

    var observedMaximumInFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumInFlight
    }
}

@MainActor
final class RemixCompilerTests: XCTestCase {
    func test_compile_serializesInjectedLoaderOperations() async {
        let probe = LoaderConcurrencyProbe()
        let compiler = NativeRemixCompiler(loaderOperation: probe.compile)

        async let first = compiler.compile("first")
        async let second = compiler.compile("second")
        async let third = compiler.compile("third")
        async let fourth = compiler.compile("fourth")
        let results = await [first, second, third, fourth]

        XCTAssertEqual(probe.observedMaximumInFlight, 1)
        XCTAssertEqual(Set(results.compactMap(\.diagnostic)), ["first", "second", "third", "fourth"])
    }

    func test_compileWithoutMetalDevice_returnsRequiredDiagnostic() async {
        let compiler = NativeRemixCompiler(device: nil)

        let result = await compiler.compile("ignored")

        XCTAssertEqual(
            result,
            RemixCompileResult(
                isValid: false,
                diagnostic: "No Metal device is available.",
                errorLine: nil
            )
        )
    }

    func test_nativeCompiler_compilesValidGeneratorAndRejectsInvalidShader() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NATIVE_REMIX_COMPILER"] == "1",
            "set RUN_NATIVE_REMIX_COMPILER=1 to run native compiler integration test"
        )
        let compiler = NativeRemixCompiler()
        let validGenerator = """
        /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [] }*/
        void main() { gl_FragColor = vec4(1.0); }
        """
        let invalidShader = """
        /*{ "ISFVSN": "2" }*/
        void main() { this is not glsl }
        """

        let validResult = await compiler.compile(validGenerator)
        let invalidResult = await compiler.compile(invalidShader)

        XCTAssertEqual(
            validResult,
            RemixCompileResult(isValid: true, diagnostic: nil, errorLine: nil)
        )
        XCTAssertFalse(invalidResult.isValid)
        XCTAssertNotNil(invalidResult.diagnostic)
        XCTAssertFalse(invalidResult.diagnostic?.isEmpty ?? true)
    }
}
