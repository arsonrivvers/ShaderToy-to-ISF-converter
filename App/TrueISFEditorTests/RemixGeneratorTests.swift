import XCTest
@testable import TrueISFEditor

/// Fake provider: returns a scripted ISF per call, or throws, keyed by call index.
@MainActor
private final class FakeProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    private(set) var lastTimeout: TimeInterval = 0
    private var i = 0
    init(_ scripts: [Result<String, Error>]) { self.scripts = scripts }
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        defer { i += 1 }
        lastTimeout = timeout
        switch scripts[min(i, scripts.count - 1)] {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

@MainActor
final class RemixGeneratorTests: XCTestCase {
    private let isf = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }"

    func test_generate_emitsOneChildPerBatchSlot() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil)
        var children: [RemixNode] = []
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 4, round: 1) {
            children.append($0)
        }
        XCTAssertEqual(children.count, 4)
        XCTAssertTrue(children.allSatisfy { $0.isfSource.contains("gl_FragColor") })
        XCTAssertEqual(Set(children.map(\.directive)).count, 4)   // distinct directives
    }

    func test_generate_partialFailure_marksThatChildFailed_othersOK() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```"), .failure(AssistRunError.timedOut)])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil)
        var children: [RemixNode] = []
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 2, round: 1) {
            children.append($0)
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.filter { if case .failed = $0.status { return true } else { return false } }.count, 1)
    }

    func test_generate_passesConfiguredTimeoutToProvider() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil, maxConcurrent: 2, timeout: 420)
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 1, round: 1) { _ in }
        XCTAssertEqual(provider.lastTimeout, 420)
    }

    func test_generate_noISFInResponse_marksFailed() async {
        let provider = FakeProvider([.success("I couldn't.")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil)
        var children: [RemixNode] = []
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 1, round: 1) {
            children.append($0)
        }
        XCTAssertEqual(children.count, 1)
        if case .failed = children[0].status {} else { XCTFail("expected .failed") }
    }
}
