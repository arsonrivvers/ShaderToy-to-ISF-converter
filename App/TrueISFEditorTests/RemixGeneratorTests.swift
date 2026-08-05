import XCTest
@testable import TrueISFEditor

/// Fake provider: returns a scripted ISF per call, or throws, keyed by call index.
@MainActor
private final class FakeProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    private(set) var lastTimeout: TimeInterval = 0
    private(set) var lastModel: String?
    private(set) var prompts: [String] = []
    private var i = 0
    init(_ scripts: [Result<String, Error>]) { self.scripts = scripts }
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        defer { i += 1 }
        lastTimeout = timeout
        lastModel = model
        prompts.append(prompt)
        switch scripts[min(i, scripts.count - 1)] {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

@MainActor
private final class BlockingProvider: AssistProvider {
    private var continuations: [Int: CheckedContinuation<String, Error>] = [:]
    private var nextID = 0
    private(set) var callCount = 0
    private(set) var cancellationCount = 0

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        let callID = nextID
        nextID += 1
        callCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[callID] = continuation
                if Task.isCancelled {
                    cancel(callID: callID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(callID: callID)
            }
        }
    }

    private func cancel(callID: Int) {
        guard let continuation = continuations.removeValue(forKey: callID) else { return }
        cancellationCount += 1
        continuation.resume(throwing: CancellationError())
    }
}

@MainActor
final class RemixGeneratorTests: XCTestCase {
    private let isf = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }"

    func test_cancelWithTwoActiveAndThreeQueued_terminalizesEverySlotWithoutBackfill() async {
        let provider = BlockingProvider()
        let gen = RemixGenerator(
            makeProvider: { provider },
            model: nil,
            maxConcurrent: 2,
            systemProvider: { "" }
        )
        var children: [RemixNode] = []
        let generation = Task { @MainActor in
            await gen.generate(
                parents: ["/*{A}*/"],
                mode: .mutate,
                steer: "",
                batchSize: 5,
                round: 1,
                onChild: { children.append($0) }
            )
        }

        while provider.callCount < 2 {
            await Task.yield()
        }
        generation.cancel()
        await generation.value

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(provider.cancellationCount, 2)
        XCTAssertEqual(children.count, 5)
        XCTAssertTrue(children.allSatisfy {
            if case .failed("cancelled") = $0.status { return true }
            return false
        })
    }

    func test_generate_emitsOneChildPerBatchSlot() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil, systemProvider: { "" })
        var children: [RemixNode] = []
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 4, round: 1) {
            children.append($0)
        }
        XCTAssertEqual(children.count, 4)
        XCTAssertTrue(children.allSatisfy { $0.isfSource.contains("gl_FragColor") })
        XCTAssertEqual(Set(children.map(\.directive)).count, 4)   // distinct directives
    }

    func test_generate_partialFailure_marksThatChildFailed_othersOK() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```"), .failure(AssistRunError.timedOut(partialStdout: ""))])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil, systemProvider: { "" })
        var children: [RemixNode] = []
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 2, round: 1) {
            children.append($0)
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.filter { if case .failed = $0.status { return true } else { return false } }.count, 1)
    }

    func test_generate_passesConfiguredTimeoutToProvider() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil,
                                 maxConcurrent: 2, timeout: 420, systemProvider: { "" })
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 1, round: 1) { _ in }
        XCTAssertEqual(provider.lastTimeout, 420)
    }

    func test_generate_resolvesModelAtGenerationTime() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        var selectedModel: String? = "gpt-5-codex"
        let gen = RemixGenerator(makeProvider: { provider }, modelProvider: { selectedModel },
                                 maxConcurrent: 1, timeout: 420,
                                 systemProvider: { "" })
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 1, round: 1) { _ in }
        XCTAssertEqual(provider.lastModel, "gpt-5-codex")

        selectedModel = nil
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 1, round: 2) { _ in }
        XCTAssertNil(provider.lastModel)
    }

    func test_generate_noISFInResponse_marksFailed() async {
        let provider = FakeProvider([.success("I couldn't.")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil, systemProvider: { "" })
        var children: [RemixNode] = []
        await gen.generate(parents: ["/*{A}*/"], mode: .mutate, steer: "", batchSize: 1, round: 1) {
            children.append($0)
        }
        XCTAssertEqual(children.count, 1)
        if case .failed = children[0].status {} else { XCTFail("expected .failed") }
    }

    func test_generateChild_usesFixedIDAndImmutableRequestSnapshot() async {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let gen = RemixGenerator(makeProvider: { provider }, model: nil, systemProvider: { "" })
        var settings = RemixCrossoverSettings()
        settings.balance = 0.8
        settings.variation = 0.9
        settings.setSource(.b, for: .motion)
        let request = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-original-a", "seed-original-b"],
            parentSources: ["ORIGINAL_SOURCE_A", "ORIGINAL_SOURCE_B"],
            mode: .crossover,
            steer: "original steer",
            directive: "original directive",
            settings: settings
        )

        let child = await gen.generateChild(id: "r12-3", request: request)

        XCTAssertEqual(child.id, "r12-3")
        XCTAssertEqual(child.round, 12)
        XCTAssertEqual(child.mode, request.mode)
        XCTAssertEqual(child.steer, request.steer)
        XCTAssertEqual(child.directive, request.directive)
        XCTAssertEqual(
            provider.prompts,
            [RemixPrompt.user(
                parents: [
                    (label: "B", source: "ORIGINAL_SOURCE_B"),
                    (label: "A", source: "ORIGINAL_SOURCE_A"),
                ],
                mode: request.mode,
                steer: request.steer,
                directive: request.directive,
                settings: request.settings
            )]
        )
    }

    func test_orderedParents_evenSeed_keepsAFirst() {
        let pairs = [(label: "A", source: "a"), (label: "B", source: "b")]
        let out = RemixGenerator.orderedParents(pairs, seed: 4000)   // even
        XCTAssertEqual(out.map(\.label), ["A", "B"])
    }
    func test_orderedParents_oddSeed_putsBFirst() {
        let pairs = [(label: "A", source: "a"), (label: "B", source: "b")]
        let out = RemixGenerator.orderedParents(pairs, seed: 4001)   // odd
        XCTAssertEqual(out.map(\.label), ["B", "A"])
        XCTAssertEqual(out.first?.source, "b")                       // label travels with source
    }
    func test_orderedParents_singleParent_unchanged() {
        let pairs = [(label: "A", source: "a")]
        XCTAssertEqual(RemixGenerator.orderedParents(pairs, seed: 1).map(\.label), ["A"])
    }
}
