import XCTest
import CoreGraphics
@testable import TrueISFEditor

/// Canonical fake provider (same shape as RemixGeneratorTests). Returns a scripted ISF per call or throws.
@MainActor
private final class FakeProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    private var i = 0
    private(set) var prompts: [String] = []
    init(_ scripts: [Result<String, Error>]) { self.scripts = scripts }
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        defer { i += 1 }
        prompts.append(prompt)
        switch scripts[min(i, scripts.count - 1)] {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

@MainActor
private final class SuspendedProvider: AssistProvider {
    private(set) var didStart = false
    private var continuation: CheckedContinuation<String, Error>?

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        didStart = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(with source: String) {
        continuation?.resume(returning: source)
        continuation = nil
    }
}

@MainActor
private final class DeterministicAutosaveScheduler {
    private(set) var scheduledCount = 0
    private var pending: (@MainActor () -> Void)?

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduledCount += 1
        pending = action
    }

    func runPending() {
        let action = pending
        pending = nil
        action?()
    }
}

@MainActor
private final class StudioDetailedProvider: AssistProvider, AssistDetailedProvider {
    private var continuation: CheckedContinuation<AssistRunResult, Error>?
    private var eventHandler: (@Sendable (AssistRunEvent) -> Void)?
    private(set) var isReady = false

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        (try await runDetailed(
            prompt: prompt, system: system, model: model, timeout: timeout,
            onEvent: { _ in }, onRawLine: onEvent
        )).response
    }

    func runDetailed(
        prompt: String,
        system: String,
        model: String?,
        timeout: TimeInterval,
        onEvent: @escaping @Sendable (AssistRunEvent) -> Void,
        onRawLine: @escaping @Sendable (String) -> Void
    ) async throws -> AssistRunResult {
        eventHandler = onEvent
        isReady = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func emit(_ event: AssistRunEvent) { eventHandler?(event) }

    func succeed(_ response: String) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: AssistRunResult(
            provider: .claude,
            response: response,
            source: .assistantMessage,
            observedSuccessfulResult: true,
            completeAssistantResponse: response,
            successfulResultText: nil,
            receivedBytes: response.utf8.count,
            eventCount: 1
        ))
    }

    private func cancel() {
        guard let continuation else { return }
        self.continuation = nil
        eventHandler?(.cancelled)
        continuation.resume(throwing: CancellationError())
    }
}

@MainActor
private final class StudioProviderHarness {
    private(set) var providers: [StudioDetailedProvider] = []
    func makeProvider() -> AssistProvider {
        let provider = StudioDetailedProvider()
        providers.append(provider)
        return provider
    }
}

@MainActor
private final class StudioCompiler: RemixCompiling {
    private(set) var sources: [String] = []
    func compile(_ source: String) async -> RemixCompileResult {
        sources.append(source)
        return RemixCompileResult(isValid: true, diagnostic: nil, errorLine: nil)
    }
}

@MainActor
final class RemixStudioModelTests: XCTestCase {
    private let isf = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }"
    private func model(_ scripts: [Result<String, Error>]) -> RemixStudioModel {
        let provider = FakeProvider(scripts)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-model-legacy-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: RemixSessionStore(
                fileURL: directory.appendingPathComponent("session.json")
            )
        )
    }

    func test_pipelineUpdatesPreserveStableSlotsFirstTerminalWinsAndTrackOnlyTypedLiveness() {
        let m = model([.success(isf)])
        let request = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-0"],
            parentSources: [isf],
            mode: .mutate,
            steer: "",
            directive: "test",
            settings: RemixCrossoverSettings()
        )
        var first = RemixChildRunRecord(
            id: "r1-0", round: 1, slot: 0, request: request,
            stage: .receiving, queuedAt: Date(timeIntervalSince1970: 1)
        )
        let second = RemixChildRunRecord(
            id: "r1-1", round: 1, slot: 1, request: request,
            stage: .receiving, queuedAt: Date(timeIntervalSince1970: 1)
        )
        m.applyPipelineUpdate(.record(first))
        m.applyPipelineUpdate(.record(second))
        XCTAssertEqual(m.currentRuns.map(\.id), ["r1-0", "r1-1"])
        XCTAssertTrue(m.activeProviderChildIDs.isEmpty)

        m.applyPipelineUpdate(.processLiveness(childID: "r1-0", isAlive: true))
        XCTAssertEqual(m.activeProviderChildIDs, ["r1-0"])
        m.applyPipelineUpdate(.processLiveness(childID: "r1-1", isAlive: false))
        XCTAssertEqual(m.activeProviderChildIDs, ["r1-0"])

        _ = first.fail(boundary: .provider, message: "first terminal", at: Date())
        m.applyPipelineUpdate(.record(first))
        XCTAssertTrue(m.activeProviderChildIDs.isEmpty)

        var lateReady = first
        lateReady.candidateSource = isf
        lateReady.stage = .compiling
        lateReady.terminalAt = nil
        _ = lateReady.finishReady(artifactID: "r1-0", at: Date())
        let lateArtifact = RemixNode(
            artifactID: "r1-0", isfSource: isf, parents: ["seed-0"],
            mode: .mutate, steer: "", directive: "test", round: 1
        )
        m.applyPipelineUpdate(.artifact(lateArtifact, record: lateReady))
        XCTAssertEqual(m.currentRuns[0].stage, .failed)
        XCTAssertNil(m.lineage.node("r1-0"))
    }

    func test_providerExitTimeoutAndCancellationLivenessUpdatesAllClearTransientLiveSet() {
        let m = model([.success(isf)])
        let request = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-0"], parentSources: [isf], mode: .mutate,
            steer: "", directive: "test", settings: RemixCrossoverSettings()
        )
        let record = RemixChildRunRecord(
            id: "r1-0", round: 1, slot: 0, request: request,
            stage: .receiving, queuedAt: Date(timeIntervalSince1970: 1)
        )
        m.applyPipelineUpdate(.record(record))

        for terminalProviderEvent in ["process exit", "timeout", "cancellation"] {
            m.applyPipelineUpdate(.processLiveness(childID: record.id, isAlive: true))
            XCTAssertEqual(m.activeProviderChildIDs, [record.id], terminalProviderEvent)
            m.applyPipelineUpdate(.processLiveness(childID: record.id, isAlive: false))
            XCTAssertTrue(m.activeProviderChildIDs.isEmpty, terminalProviderEvent)
        }
    }

    func test_generationPublishesStableSlotsShowsFirstReadyPayoffAndStopSettlesEverySlot() async throws {
        let harness = StudioProviderHarness()
        let compiler = StudioCompiler()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-stable-runs-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let m = RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: harness.makeProvider,
                model: nil,
                maxConcurrent: 2,
                compiler: compiler
            ),
            sessionStore: RemixSessionStore(
                fileURL: directory.appendingPathComponent("session.json")
            )
        )
        m.mode = .mutate
        m.setParent(.a, isf: isf)
        m.batchSize = 5
        m.startGeneration()

        try await waitUntil { harness.providers.count == 2 }
        try await waitUntil { m.runSummary.stageCounts[.thinking] == 2 }
        try await waitUntil { harness.providers.allSatisfy(\.isReady) }
        harness.providers.forEach {
            $0.emit(.processStarted(pid: 42))
            $0.emit(.textDelta(messageID: "m", blockIndex: 0, text: "chunk"))
        }
        try await waitUntil { m.runSummary.stageCounts[.receiving] == 2 }
        XCTAssertEqual(m.currentRuns.map(\.id), ["r1-0", "r1-1", "r1-2", "r1-3", "r1-4"])
        XCTAssertEqual(m.runSummary.stageCounts[.queued], 3)
        XCTAssertEqual(
            m.runSummary.stageCounts[.receiving],
            2,
            "stages: \(m.currentRuns.map(\.stage))"
        )
        XCTAssertNil(m.lineage.node("r1-0"))

        harness.providers[0].succeed("```glsl\n\(isf)\n```")
        try await waitUntil { m.currentRuns.first?.stage == .ready }
        XCTAssertTrue(m.isGenerating)
        XCTAssertNotNil(m.lineage.node("r1-0"))

        m.cancelGeneration()
        try await waitUntil { !m.isGenerating }
        XCTAssertTrue(m.currentRuns.allSatisfy(\.stage.isTerminal))
    }

    func test_restoreV1EmptyResultRecoversThreeArtifactsInStableSlotOrderWithoutProvider() async throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "remix-2026-08-01-empty-result-session-v1",
            withExtension: "json"
        ))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-v1-local-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sessionURL = directory.appendingPathComponent("session.json")
        try FileManager.default.copyItem(at: fixtureURL, to: sessionURL)
        let provider = FakeProvider([.success(isf)])
        let compiler = StudioCompiler()

        let m = RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: { provider },
                model: nil,
                compiler: compiler
            ),
            sessionStore: RemixSessionStore(fileURL: sessionURL)
        )

        try await waitUntil {
            ["r1-0", "r1-1", "r1-3"].allSatisfy { id in
                m.currentRuns.first(where: { $0.id == id })?.stage == .ready
            }
        }
        XCTAssertEqual(compiler.sources, [
            "/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"Recovered r1-0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }",
            "/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"Recovered r1-1\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }",
            "/*{ \"ISFVSN\": \"2.0\", \"DESCRIPTION\": \"Recovered r1-3\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }",
        ])
        XCTAssertTrue(provider.prompts.isEmpty)
        XCTAssertNotNil(m.lineage.node("r1-0"))
        XCTAssertNotNil(m.lineage.node("r1-1"))
        XCTAssertNotNil(m.lineage.node("r1-3"))
    }

    func test_restoreSchemaV2InterruptsProviderStagesAndResumesOnlyCompleteLocalCandidates() async throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "remix-schema-v2-mid-batch",
            withExtension: "json"
        ))
        var session = try JSONDecoder().decode(
            RemixSession.self,
            from: Data(contentsOf: fixtureURL)
        )
        session.currentRuns[5].candidateSource = completeISF("extracting restore")
        session.currentRuns[6].candidateSource = completeISF("compiling restore")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-v2-local-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = RemixSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        try store.save(session)
        let provider = FakeProvider([.success(isf)])
        let compiler = StudioCompiler()

        let m = RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: { provider }, model: nil, compiler: compiler
            ),
            sessionStore: store
        )

        try await waitUntil { m.currentRuns.allSatisfy(\.stage.isTerminal) }
        XCTAssertEqual(m.currentRuns.map(\.stage), [
            .interrupted, .interrupted, .interrupted, .interrupted, .interrupted, .ready, .ready,
        ])
        XCTAssertEqual(compiler.sources, [
            completeISF("extracting restore"),
            completeISF("compiling restore"),
        ])
        XCTAssertTrue(provider.prompts.isEmpty)
        XCTAssertTrue(m.activeProviderChildIDs.isEmpty)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func completeISF(_ description: String) -> String {
        "/*{ \"ISFVSN\":\"2.0\", \"DESCRIPTION\":\"\(description)\" }*/\n"
            + "void main(){ gl_FragColor=vec4(1.0); }"
    }

    private func installCompileFailure(
        on model: RemixStudioModel,
        id: String = "r1-0",
        message: String
    ) {
        let request = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-0"],
            parentSources: [isf],
            mode: .mutate,
            steer: "",
            directive: "test",
            settings: RemixCrossoverSettings()
        )
        var run = RemixChildRunRecord(
            id: id,
            round: 1,
            slot: 0,
            request: request,
            stage: .compiling,
            queuedAt: Date(timeIntervalSince1970: 1),
            candidateSource: isf
        )
        XCTAssertTrue(run.fail(boundary: .compile, message: message, at: Date()))
        model.applyPipelineUpdate(.record(run))
    }

    func test_setParent_createsSeedNode_inLineage() {
        let m = model([.success(isf)])
        m.setParent(.a, isf: "/*{A}*/ a")
        XCTAssertNotNil(m.parentAID)
        XCTAssertEqual(m.lineage.node(m.parentAID!)?.isfSource, "/*{A}*/ a")
        XCTAssertEqual(m.lineage.node(m.parentAID!)?.round, 0)
    }

    func test_canGenerate_requires_twoParents_forCrossover_oneForMutate() {
        let m = model([.success(isf)])
        m.mode = .crossover
        m.setParent(.a, isf: "a")
        XCTAssertFalse(m.canGenerate)          // crossover needs both
        m.setParent(.b, isf: "b")
        XCTAssertTrue(m.canGenerate)
        m.mode = .mutate                       // mutate needs only A
        let m2 = model([.success(isf)]); m2.mode = .mutate; m2.setParent(.a, isf: "a")
        XCTAssertTrue(m2.canGenerate)
    }

    func test_generate_streamsChildren_recordsParentIDs_andInsertsIntoLineage() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .crossover
        m.setParent(.a, isf: "/*{A}*/"); m.setParent(.b, isf: "/*{B}*/")
        m.batchSize = 4
        await m.generate()
        XCTAssertEqual(m.currentBatch.count, 4)
        let pids = [m.parentAID!, m.parentBID!]
        XCTAssertTrue(m.currentBatch.allSatisfy { $0.parents == pids })
        XCTAssertTrue(m.currentBatch.allSatisfy { m.lineage.node($0.id) != nil })
        XCTAssertFalse(m.isGenerating)
    }

    func test_rendererFailureDoesNotRewriteReadyRunOrArtifact() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let id = m.currentBatch[0].id
        m.markPreviewFailed(artifactID: id, diagnostic: "renderer failed")
        XCTAssertEqual(m.currentBatch[0].status, .compiled)
        XCTAssertEqual(m.currentRuns[0].stage, .ready)
        XCTAssertEqual(m.lineage.node(id)?.status, .compiled)
        XCTAssertEqual(m.previewStates[id]?.stage, .failed)
    }

    func test_favorites_toggle_throughModel() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let id = m.currentBatch[0].id
        m.toggleFavorite(id)
        XCTAssertTrue(m.lineage.isFavorite(id))
        XCTAssertEqual(m.treeRows(collapsed: [], favoritesOnly: true).map(\.id), [id])
    }

    func test_promoteToParent_setsParentToExistingNode_noNewSeed() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let childID = m.currentBatch[0].id
        m.promoteToParent(.a, nodeID: childID)
        XCTAssertEqual(m.parentAID, childID)
    }

    func test_livePreviewCap_neverExceededAndPrioritizesHeroComparisonFocusThenFavorites() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 6; m.maxLivePreviews = 4
        await m.generate()
        for n in m.currentBatch { m.markPreviewAvailable(artifactID: n.id) }
        let ids = m.currentBatch.map(\.id)
        m.workspace.heroChildID = ids[0]
        m.workspace.comparedChildIDs = [ids[1], ids[2]]
        m.workspace.focusedChildID = ids[3]
        m.toggleFavorite(ids[4])
        m.toggleFavorite(ids[5])

        XCTAssertEqual(m.livePreviewIDs(reduceMotion: false), Set(ids.prefix(4)))
        XCTAssertEqual(m.livePreviewIDs(reduceMotion: false).count, m.maxLivePreviews)
    }

    func test_livePreviewBudget_honorsPauseReduceMotionFailureAndExplicitFreeze() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 4; m.maxLivePreviews = 4
        await m.generate()
        for n in m.currentBatch { m.markPreviewAvailable(artifactID: n.id) }
        let ids = m.currentBatch.map(\.id)

        m.setPreviewFrozen(true, for: ids[0])
        m.markPreviewFailed(artifactID: ids[1], diagnostic: "bad")
        XCTAssertFalse(m.livePreviewIDs(reduceMotion: false).contains(ids[0]))
        XCTAssertFalse(m.livePreviewIDs(reduceMotion: false).contains(ids[1]))
        XCTAssertTrue(m.livePreviewIDs(reduceMotion: true).isEmpty)
        m.explicitlyPlayPreviews()
        XCTAssertFalse(m.livePreviewIDs(reduceMotion: true).isEmpty)
        m.workspace.previewsPaused = true
        XCTAssertTrue(m.livePreviewIDs(reduceMotion: false).isEmpty)
    }

    func test_canvasModeChangesKeepFocusAndComparisonIndependent() {
        let m = model([.success(isf)])
        m.workspace.focusedChildID = "focused"
        m.workspace.comparedChildIDs = ["left", "right"]
        m.workspace.canvasMode = .hero
        m.workspace.canvasMode = .grid

        XCTAssertEqual(m.workspace.focusedChildID, "focused")
        XCTAssertEqual(m.workspace.comparedChildIDs, ["left", "right"])
    }

    func test_keyboardCommandsRouteThroughFocusedChild() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 2
        await m.generate()
        let ids = m.currentBatch.map(\.id)
        m.workspace.focusedChildID = ids[0]

        m.routeCanvasCommand(.favorite, columns: 2)
        XCTAssertTrue(m.lineage.isFavorite(ids[0]))
        m.routeCanvasCommand(.toggleComparison, columns: 2)
        XCTAssertEqual(m.workspace.comparedChildIDs, [ids[0]])
        m.routeCanvasCommand(.hero, columns: 2)
        XCTAssertEqual(m.workspace.heroChildID, ids[0])
        m.routeCanvasCommand(.promoteA, columns: 2)
        XCTAssertEqual(m.parentAID, ids[0])
        m.routeCanvasCommand(.moveRight, columns: 2)
        XCTAssertEqual(m.workspace.focusedChildID, ids[1])
    }

    func test_failedChildren_neverAnimate() async {
        let m = model([.success("I couldn't.")])   // no ISF -> generator marks .failed
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 2; m.maxLivePreviews = 4
        await m.generate()
        XCTAssertTrue(m.currentBatch.allSatisfy { !m.shouldAnimate($0.id) })
    }

    func test_selectedLineagePreviewSharesGlobalBudgetAndHonorsPauseReduceMotionAndZeroCap() async throws {
        let m = model(Array(repeating: .success("```glsl\n\(isf)\n```"), count: 5))
        m.mode = .mutate
        m.setParent(.a, isf: "/*{A}*/")
        let seedID = try XCTUnwrap(m.parentAID)
        m.batchSize = 5
        m.maxLivePreviews = 4
        await m.generate()
        m.selectedNodeID = seedID

        XCTAssertTrue(m.shouldAnimate(seedID, reduceMotion: false))
        XCTAssertEqual(m.livePreviewIDs(reduceMotion: false).count, 4)

        m.workspace.previewsPaused = true
        XCTAssertFalse(m.shouldAnimate(seedID, reduceMotion: false))

        m.workspace.previewsPaused = false
        XCTAssertFalse(m.shouldAnimate(seedID, reduceMotion: true))

        m.explicitlyPlayPreviews()
        XCTAssertTrue(m.shouldAnimate(seedID, reduceMotion: true))

        m.maxLivePreviews = 0
        XCTAssertFalse(m.shouldAnimate(seedID, reduceMotion: false))
    }

    func test_historicalSelectionDoesNotDisplaceHeroAtCapOne() async throws {
        let m = model(Array(repeating: .success("```glsl\n\(isf)\n```"), count: 2))
        m.mode = .mutate
        m.setParent(.a, isf: "/*{A}*/")
        let historicalID = try XCTUnwrap(m.parentAID)
        m.batchSize = 2
        await m.generate()
        let heroID = try XCTUnwrap(m.currentBatch.first?.id)
        m.selectedNodeID = historicalID
        m.workspace.heroChildID = heroID
        m.maxLivePreviews = 1

        XCTAssertEqual(m.livePreviewIDs(reduceMotion: false), Set([heroID]))
        XCTAssertFalse(m.shouldAnimate(historicalID, reduceMotion: false))
    }

    func test_historicalSelectionDoesNotDisplaceComparedPairAtCapTwo() async throws {
        let m = model(Array(repeating: .success("```glsl\n\(isf)\n```"), count: 3))
        m.mode = .mutate
        m.setParent(.a, isf: "/*{A}*/")
        let historicalID = try XCTUnwrap(m.parentAID)
        m.batchSize = 3
        await m.generate()
        let compared = Array(m.currentBatch.prefix(2).map(\.id))
        m.selectedNodeID = historicalID
        m.workspace.comparedChildIDs = compared
        m.maxLivePreviews = 2

        XCTAssertEqual(m.livePreviewIDs(reduceMotion: false), Set(compared))
        XCTAssertFalse(m.shouldAnimate(historicalID, reduceMotion: false))
    }

    func test_historicalSelectionUsesOnlySlotRemainingAfterCanvasPriorities() async throws {
        let m = model(Array(repeating: .success("```glsl\n\(isf)\n```"), count: 4))
        m.mode = .mutate
        m.setParent(.a, isf: "/*{A}*/")
        let historicalID = try XCTUnwrap(m.parentAID)
        m.batchSize = 4
        await m.generate()
        let ids = m.currentBatch.map(\.id)
        m.selectedNodeID = historicalID
        m.workspace.heroChildID = ids[0]
        m.workspace.comparedChildIDs = [ids[1], ids[2]]
        m.workspace.focusedChildID = ids[3]
        m.maxLivePreviews = 4

        XCTAssertEqual(m.livePreviewIDs(reduceMotion: false), Set(ids))
        XCTAssertFalse(m.shouldAnimate(historicalID, reduceMotion: false))

        m.maxLivePreviews = 5
        XCTAssertTrue(m.shouldAnimate(historicalID, reduceMotion: false))

        m.workspace.previewsPaused = true
        XCTAssertTrue(m.livePreviewIDs(reduceMotion: false).isEmpty)
        m.workspace.previewsPaused = false
        XCTAssertTrue(m.livePreviewIDs(reduceMotion: true).isEmpty)
        m.maxLivePreviews = 0
        XCTAssertTrue(m.livePreviewIDs(reduceMotion: false).isEmpty)
    }

    func test_selectedCanvasChildAndInspectorRequireSeparatePreviewReservations() async throws {
        let m = model(Array(repeating: .success("```glsl\n\(isf)\n```"), count: 2))
        m.mode = .mutate
        m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 2
        await m.generate()
        let selectedID = try XCTUnwrap(m.currentBatch.first?.id)
        m.workspace.heroChildID = selectedID
        m.selectedNodeID = selectedID
        m.maxLivePreviews = 1

        XCTAssertTrue(
            m.shouldAnimate(selectedID, on: .canvas, reduceMotion: false)
        )
        XCTAssertFalse(
            m.shouldAnimate(selectedID, on: .inspector, reduceMotion: false)
        )
        XCTAssertEqual(m.livePreviewReservations(reduceMotion: false).count, 1)
    }

    func test_inspectorDuplicateAnimatesOnlyWhenASeparateSlotRemains() async throws {
        let m = model(Array(repeating: .success("```glsl\n\(isf)\n```"), count: 2))
        m.mode = .mutate
        m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 2
        await m.generate()
        let selectedID = try XCTUnwrap(m.currentBatch.first?.id)
        m.workspace.heroChildID = selectedID
        m.selectedNodeID = selectedID
        m.maxLivePreviews = 2

        XCTAssertEqual(
            m.livePreviewReservations(reduceMotion: false),
            Set([
                RemixPreviewReservation(nodeID: selectedID, surface: .canvas),
                RemixPreviewReservation(nodeID: selectedID, surface: .inspector),
            ])
        )
        XCTAssertEqual(m.livePreviewReservations(reduceMotion: false).count, 2)
        XCTAssertTrue(
            m.shouldAnimate(selectedID, on: .inspector, reduceMotion: false)
        )
    }

    func test_appendLog_tagsByChildId_andBoundsMemory() {
        let m = model([.success(isf)])
        m.appendLog("r1-0", "thinking…")
        XCTAssertEqual(m.transcript.last, "[r1-0] thinking…")
        for i in 0..<2100 { m.appendLog("r1-0", "line \(i)") }
        XCTAssertLessThanOrEqual(m.transcript.count, 2000)        // bounded
        XCTAssertEqual(m.transcript.last, "[r1-0] line 2099")     // keeps the newest
    }

    func test_generate_clearsStaleTranscript() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        m.appendLog("old", "stale line from a previous round")
        await m.generate()
        XCTAssertFalse(m.transcript.contains("[old] stale line from a previous round"))
    }

    func test_makePlaceholders_areGenerating_withMatchingIdsAndDirectives() {
        let ps = RemixStudioModel.makePlaceholders(round: 2, size: 3, parents: ["seed-0"], pool: RemixDirectives.catalog, mode: .crossover)
        XCTAssertEqual(ps.count, 3)
        XCTAssertEqual(ps.map(\.id), ["r2-0", "r2-1", "r2-2"])          // ids match the generator
        XCTAssertTrue(ps.allSatisfy { $0.status == .generating })
        XCTAssertTrue(ps.allSatisfy { $0.parents == ["seed-0"] })
        XCTAssertEqual(ps.map(\.directive), RemixDirectives.pick(3, seed: 2))  // directives match
    }

    func test_generate_doesNotDuplicate_placeholdersReplacedInPlace() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 3
        await m.generate()
        XCTAssertEqual(m.currentBatch.count, 3)                          // not 6 (placeholders replaced)
        XCTAssertTrue(m.currentBatch.allSatisfy { $0.status != .generating })
    }

    func test_generatingCount_zeroAfterBatchCompletes() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 3
        await m.generate()
        XCTAssertEqual(m.generatingCount, 0)   // all replies landed -> none left generating
    }

    func test_retryChild_replacesOnlyFailedSlotUsingStoredRequestAfterControlsChange() async throws {
        let provider = FakeProvider([
            .success("```glsl\n\(isf)\n```"),
            .failure(AssistRunError.timedOut(partialStdout: "")),
            .success("```glsl\n\(isf.replacingOccurrences(of: "1.0", with: "0.5"))\n```"),
        ])
        let fixture = try restorationFixture(saveInitialSession: false)
        let m = RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: { provider },
                model: nil,
                maxConcurrent: 1,
                systemProvider: { "" }
            ),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        var originalSettings = RemixCrossoverSettings()
        originalSettings.balance = 0.8
        originalSettings.variation = 0.9
        originalSettings.setSource(.b, for: .motion)
        m.mode = .crossover
        m.steer = "original steer"
        m.crossoverSettings = originalSettings
        m.batchSize = 2
        m.setParent(.a, isf: "ORIGINAL_SOURCE_A")
        m.setParent(.b, isf: "ORIGINAL_SOURCE_B")
        await m.generate()
        let originalBatch = m.currentBatch
        let failedID = try XCTUnwrap(originalBatch.first { node in
            if case .failed = node.status { return true }
            return false
        }?.id)
        let request = try XCTUnwrap(m.batchHistory.last?.requestsByNodeID[failedID])

        m.mode = .mutate
        m.steer = "changed steer"
        m.crossoverSettings = RemixCrossoverSettings()
        m.clearParent(.a)
        m.clearParent(.b)
        await m.retryChild(id: failedID, steerOverride: nil)

        XCTAssertEqual(m.currentBatch.count, originalBatch.count)
        for original in originalBatch where original.id != failedID {
            XCTAssertEqual(m.currentBatch.first { $0.id == original.id }, original)
        }
        let retried = try XCTUnwrap(m.currentBatch.first { $0.id == failedID })
        XCTAssertEqual(retried.status, .compiled)
        XCTAssertEqual(retried.parents, request.parentIDs)
        XCTAssertEqual(retried.mode, request.mode)
        XCTAssertEqual(retried.steer, request.steer)
        XCTAssertEqual(retried.directive, request.directive)
        XCTAssertTrue(provider.prompts.last?.contains("ORIGINAL_SOURCE_A") == true)
        XCTAssertTrue(provider.prompts.last?.contains("ORIGINAL_SOURCE_B") == true)
        XCTAssertTrue(provider.prompts.last?.contains("original steer") == true)
        XCTAssertFalse(provider.prompts.last?.contains("changed steer") == true)
        XCTAssertTrue(provider.prompts.last?.contains("80% toward Parent B") == true)
        XCTAssertTrue(provider.prompts.last?.contains("Take the motion primarily from Parent B") == true)
    }

    func test_retryChild_steerOverrideChangesOnlyStoredSteer() async throws {
        let provider = FakeProvider([
            .failure(AssistRunError.timedOut(partialStdout: "")),
            .success("```glsl\n\(isf)\n```"),
        ])
        let fixture = try restorationFixture(saveInitialSession: false)
        let m = RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: { provider },
                model: nil,
                maxConcurrent: 1,
                systemProvider: { "" }
            ),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        m.mode = .mutate
        m.steer = "original steer"
        m.batchSize = 1
        m.setParent(.a, isf: "ORIGINAL_SOURCE")
        await m.generate()
        let id = try XCTUnwrap(m.currentBatch.first?.id)
        let original = try XCTUnwrap(m.batchHistory.last?.requestsByNodeID[id])

        await m.retryChild(id: id, steerOverride: "retry steer")

        let updated = try XCTUnwrap(m.batchHistory.last?.requestsByNodeID[id])
        XCTAssertEqual(updated.parentIDs, original.parentIDs)
        XCTAssertEqual(updated.parentSources, original.parentSources)
        XCTAssertEqual(updated.mode, original.mode)
        XCTAssertEqual(updated.directive, original.directive)
        XCTAssertEqual(updated.settings, original.settings)
        XCTAssertEqual(updated.steer, "original steer")
        XCTAssertTrue(provider.prompts.last?.contains("retry steer") == true)
        XCTAssertFalse(provider.prompts.last?.contains("original steer") == true)
    }

    func test_retryChildClearsCurrentCompileDiagnosticWithoutRewritingOriginalHistory() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        var session = fixture.session
        let request = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-4"], parentSources: [isf], mode: .mutate,
            steer: "original", directive: "original", settings: session.crossoverSettings
        )
        var failed = RemixChildRunRecord(
            id: "r7-1", round: 7, slot: 1, request: request, stage: .compiling,
            queuedAt: Date(timeIntervalSince1970: 1), candidateSource: isf
        )
        XCTAssertTrue(failed.fail(
            boundary: .compile, message: "old compile failure", at: Date(timeIntervalSince1970: 2)
        ))
        session.currentRuns = [failed]
        session.batchHistory = [RemixBatchRecord(round: 7, runs: [failed])]
        try fixture.store.save(session)
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        XCTAssertEqual(model.compileDiagnostic(for: failed.id), "old compile failure")

        await model.retryChild(id: failed.id)

        XCTAssertEqual(model.currentRuns.first?.stage, .ready)
        XCTAssertNil(model.compileDiagnostic(for: failed.id))
        XCTAssertEqual(
            model.batchHistory.first?.runs.first?.compileDiagnostic,
            "old compile failure"
        )
    }

    func test_activeBatchPersistsRequestSnapshotsBeforeAnyReply() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let provider = SuspendedProvider()
        let m = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        m.mode = .mutate
        m.steer = "persist before reply"
        m.batchSize = 1
        m.setParent(.a, isf: "ORIGINAL_SOURCE")

        let generation = Task { await m.generate() }
        while !provider.didStart { await Task.yield() }
        let persisted = try loadedSession(fixture.store)

        let batch = try XCTUnwrap(persisted.batchHistory.first)
        let request = try XCTUnwrap(
            batch.requestsByNodeID["r1-0"]
        )
        XCTAssertEqual(request.parentSources, ["ORIGINAL_SOURCE"])
        XCTAssertEqual(request.steer, "persist before reply")

        generation.cancel()
        provider.finish(with: "```glsl\n\(isf)\n```")
        await generation.value
    }

    func test_retryFailedAndInterruptedBatch_touchOnlyTheirScopedStatuses() async throws {
        let fixture = try restorationFixture()
        var session = fixture.session
        let request = RemixGenerationRequestSnapshot(
            parentIDs: ["seed-4"], parentSources: ["RESTORED_PARENT"], mode: .mutate,
            steer: "original steer", directive: "original directive",
            settings: session.crossoverSettings
        )
        var ready = RemixChildRunRecord(
            id: "r7-0", round: 7, slot: 0, request: request, stage: .compiling,
            queuedAt: Date(timeIntervalSince1970: 1), candidateSource: isf
        )
        XCTAssertTrue(ready.finishReady(artifactID: "r7-0", at: Date(timeIntervalSince1970: 2)))
        var failed = RemixChildRunRecord(
            id: "r7-1", round: 7, slot: 1, request: request, stage: .receiving,
            queuedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertTrue(failed.fail(
            boundary: .provider, message: "provider failed", at: Date(timeIntervalSince1970: 2)
        ))
        let interrupted = RemixChildRunRecord(
            id: "r7-2", round: 7, slot: 2, request: request, stage: .interrupted,
            queuedAt: Date(timeIntervalSince1970: 1),
            terminalAt: Date(timeIntervalSince1970: 2)
        )
        session.currentRuns = [ready, failed, interrupted]
        session.batchHistory = [RemixBatchRecord(round: 7, runs: session.currentRuns)]
        try fixture.store.save(session)
        let provider = FakeProvider([
            .success("```glsl\n\(isf)\n```"),
            .success("```glsl\n\(isf)\n```"),
        ])
        let m = RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: { provider },
                model: nil,
                maxConcurrent: 1,
                systemProvider: { "" }
            ),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )

        await m.retryFailed()
        XCTAssertEqual(m.currentRuns.map(\.stage), [.ready, .ready, .interrupted])
        XCTAssertEqual(provider.prompts.count, 1)

        await m.retryInterruptedBatch()
        XCTAssertEqual(m.currentRuns.map(\.stage), [.ready, .ready, .ready])
        XCTAssertEqual(provider.prompts.count, 2)
    }

    func test_restoredInterruptedBatchRetainsGenerationRequestSnapshots() throws {
        let fixture = try restorationFixture()
        var session = fixture.session
        var interrupted = session.currentBatch[0]
        interrupted.status = .generating
        let request = RemixGenerationRequestSnapshot(
            parentIDs: interrupted.parents,
            parentSources: ["RESTORED_PARENT"],
            mode: interrupted.mode,
            steer: interrupted.steer,
            directive: interrupted.directive,
            settings: session.crossoverSettings
        )
        session.currentBatch = [interrupted]
        session.batchHistory = [
            RemixBatchRecord(
                round: interrupted.round,
                nodes: [interrupted],
                requestsByNodeID: [interrupted.id: request]
            )
        ]
        try fixture.store.save(session)

        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        XCTAssertEqual(restored.currentBatch[0].status, .interrupted)
        XCTAssertEqual(
            restored.batchHistory[0].requestsByNodeID[interrupted.id],
            request
        )
    }

    func test_undoParentChange_restoresPreviousParentsWithoutDeletingSessionState() async throws {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()                       // round 1, parent = seed
        let seedID = m.parentAID
        let childID = m.currentBatch[0].id
        m.toggleFavorite(childID)
        m.selectedNodeID = childID
        m.promoteToParent(.a, nodeID: childID)
        await m.generate()                       // round 2, parent = child
        m.markPreviewFailed(
            artifactID: m.currentBatch[0].id,
            diagnostic: "renderer unavailable"
        )
        let lineageBefore = m.lineage
        let batchesBefore = m.batchHistory
        let activityBefore = m.activity
        let snapshotsBefore = m.snapshots
        XCTAssertEqual(m.parentAID, childID)
        XCTAssertTrue(m.canUndoParentChange)
        XCTAssertNil(m.undoParentChangeReason)

        m.undoParentChange()

        XCTAssertEqual(m.parentAID, seedID)      // restored to the round-1 config
        XCTAssertEqual(m.lineage, lineageBefore)
        XCTAssertEqual(m.batchHistory, batchesBefore)
        XCTAssertEqual(m.activity, activityBefore)
        XCTAssertEqual(m.snapshots.count, snapshotsBefore.count)
        XCTAssertTrue(m.lineage.isFavorite(childID))
        XCTAssertEqual(m.selectedNodeID, childID)
    }

    func test_undoParentChange_disabledReasonExplainsWhenNoHistoryExists() {
        let m = model([.success(isf)])

        XCTAssertFalse(m.canUndoParentChange)
        XCTAssertEqual(
            m.undoParentChangeReason,
            "No prior parent configuration is available."
        )
        m.undoParentChange()
        XCTAssertNil(m.parentAID)
        XCTAssertNil(m.parentBID)
    }

    func test_setParent_recordsLabel_onSeedNode() {
        let m = model([.success(isf)])
        m.setParent(.a, isf: "a", label: "plasma")
        XCTAssertEqual(m.lineage.node(m.parentAID!)?.label, "plasma")
        m.setParent(.b, isf: "b")                       // label optional, defaults nil
        XCTAssertNil(m.lineage.node(m.parentBID!)?.label)
    }

    func test_selectedNodeID_defaultsNil_andPublishesSelection() {
        let m = model([.success(isf)])
        XCTAssertNil(m.selectedNodeID)
        m.selectedNodeID = "r1-0"
        XCTAssertEqual(m.selectedNodeID, "r1-0")
    }

    func test_storeSnapshot_cachesByID() {
        let m = model([.success(isf)])
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = ctx.makeImage()!
        m.storeSnapshot(id: "r1-0", image: img)
        XCTAssertNotNil(m.snapshots["r1-0"])
        XCTAssertNil(m.snapshots["r9-9"])
    }

    func test_treeRows_passesThrough_toBuilder() {
        let m = model([.success(isf)])
        m.setParent(.a, isf: "a", label: "plasma")
        let rows = m.treeRows(collapsed: [], favoritesOnly: false)
        XCTAssertEqual(rows.map(\.id), [m.parentAID!])
        XCTAssertEqual(m.treeRows(collapsed: [], favoritesOnly: true), [])  // nothing starred yet
    }

    func test_crossoverSettings_persistAcrossModelInstances() {
        UserDefaults.standard.removeObject(forKey: "remixCrossoverSettings")
        let m1 = model([.success(isf)])
        m1.crossoverSettings.balance = 0.8
        let m2 = model([.success(isf)])               // fresh instance reads persisted blob
        XCTAssertEqual(m2.crossoverSettings.balance, 0.8, accuracy: 0.0001)
        UserDefaults.standard.removeObject(forKey: "remixCrossoverSettings")
    }

    func test_corruptSettingsBlob_fallsBackToDefaults() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: "remixCrossoverSettings")
        let m = model([.success(isf)])
        XCTAssertEqual(m.crossoverSettings.balance, 0.5, accuracy: 0.0001)  // default
        UserDefaults.standard.removeObject(forKey: "remixCrossoverSettings")
    }

    func test_makePlaceholders_directivesMatchGenerator_forReducedPool() {
        let pool = ["lean minimal and restrained", "emphasize bold color and palette shifts"]
        let placeholders = RemixStudioModel.makePlaceholders(round: 2, size: 4, parents: [], pool: pool, mode: .mutate)
        let generatorDirectives = RemixDirectives.pick(4, seed: 2, from: pool)
        XCTAssertEqual(placeholders.map(\.directive), generatorDirectives)
    }

    func test_restoreSession_restoresEverySpecifiedSurface() throws {
        let fixture = try restorationFixture()
        try fixture.store.save(fixture.session)

        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        XCTAssertEqual(restored.parentAID, "seed-4")
        XCTAssertEqual(restored.parentBID, "seed-5")
        XCTAssertEqual(restored.mode, .mutate)
        XCTAssertEqual(restored.steer, "make it crystalline")
        XCTAssertEqual(restored.batchSize, 3)
        XCTAssertEqual(restored.currentBatch, fixture.session.currentBatch)
        XCTAssertEqual(restored.batchHistory, fixture.session.batchHistory)
        XCTAssertEqual(restored.lineage, fixture.session.lineage)
        XCTAssertEqual(restored.workspace, fixture.session.workspace)
        XCTAssertEqual(restored.selectedNodeID, "r7-0")
        XCTAssertEqual(restored.crossoverSettings, fixture.session.crossoverSettings)
        XCTAssertEqual(restored.activity, fixture.session.activity)
        XCTAssertEqual(restored.pendingParentRequest, fixture.session.pendingParentRequest)
        XCTAssertEqual(restored.transcript, fixture.session.transcript)
    }

    func test_restoreThenGenerate_usesCollisionFreeRoundAndSeedIDs() async throws {
        let fixture = try restorationFixture()
        try fixture.store.save(fixture.session)
        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        restored.setParent(.a, isf: "new seed")
        XCTAssertEqual(restored.parentAID, "seed-6")
        restored.mode = .mutate
        restored.batchSize = 1
        await restored.generate()

        XCTAssertEqual(restored.currentBatch.map(\.id), ["r8-0"])
    }

    func test_restorePreservesUndoParentHistory() throws {
        let fixture = try restorationFixture()
        try fixture.store.save(fixture.session)
        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        XCTAssertTrue(restored.canUndoParentChange)
        restored.undoParentChange()

        XCTAssertEqual(restored.parentAID, "seed-2")
        XCTAssertEqual(restored.parentBID, "seed-3")
    }

    func test_restorePendingShadertoyRequest_preservesUUIDSlotSourceAndTypedPhase() throws {
        let fixture = try restorationFixture()
        try fixture.store.save(fixture.session)

        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        XCTAssertEqual(restored.pendingParentRequest?.id, fixture.requestID)
        XCTAssertEqual(restored.pendingParentRequest?.slot, .b)
        XCTAssertEqual(
            restored.pendingParentRequest?.source,
            .shadertoyLink("https://www.shadertoy.com/view/abc123")
        )
        XCTAssertEqual(restored.pendingParentRequest?.phase, .verificationRequired)
        XCTAssertFalse(restored.isGenerating)
    }

    func test_startNewSession_clearsSessionButKeepsUserDefaultsProviderChoice() throws {
        let fixture = try restorationFixture()
        fixture.defaults.set("codex", forKey: "assistProvider")
        try fixture.store.save(fixture.session)
        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        restored.startNewSession()

        XCTAssertNil(restored.parentAID)
        XCTAssertNil(restored.parentBID)
        XCTAssertTrue(restored.currentBatch.isEmpty)
        XCTAssertTrue(restored.batchHistory.isEmpty)
        XCTAssertTrue(restored.lineage.allNodes.isEmpty)
        XCTAssertEqual(restored.workspace, RemixWorkspaceState())
        XCTAssertNil(restored.selectedNodeID)
        XCTAssertEqual(restored.activity, .idle)
        XCTAssertNil(restored.pendingParentRequest)
        XCTAssertEqual(fixture.defaults.string(forKey: "assistProvider"), "codex")
    }

    func test_modelPersistsAfterEveryNamedMutation() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let restored = storedModel(
            store: fixture.store,
            defaults: fixture.defaults,
            autosaveScheduler: { $0() }
        )

        restored.setParent(.a, isf: "source A", label: "A")
        XCTAssertEqual(try loadedSession(fixture.store).parentAID, "seed-0")

        restored.toggleFavorite("seed-0")
        XCTAssertTrue(try loadedSession(fixture.store).lineage.isFavorite("seed-0"))

        restored.selectedNodeID = "seed-0"
        XCTAssertEqual(try loadedSession(fixture.store).selectedLineageNodeID, "seed-0")

        var layout = restored.workspace
        layout.showHero("seed-0")
        restored.workspace = layout
        XCTAssertEqual(try loadedSession(fixture.store).workspace.canvasMode, .hero)

        restored.mode = .mutate
        restored.batchSize = 1
        await restored.generate()
        let childID = try XCTUnwrap(restored.currentBatch.first?.id)
        XCTAssertEqual(try loadedSession(fixture.store).currentBatch.first?.id, childID)

        restored.markPreviewFailed(artifactID: childID, diagnostic: "renderer unavailable")
        let previewFailure = try loadedSession(fixture.store)
        let readyRun = try XCTUnwrap(previewFailure.currentRuns.first)
        XCTAssertNotNil(previewFailure.lineage.node(childID))
        XCTAssertEqual(readyRun.stage, .ready)
        XCTAssertEqual(previewFailure.previewStates[childID]?.stage, .failed)
        XCTAssertEqual(
            previewFailure.previewStates[childID]?.diagnostic,
            "renderer unavailable"
        )

        restored.cancelGeneration()
        XCTAssertEqual(try loadedSession(fixture.store).activity, .cancelled)

        restored.promoteToParent(.a, nodeID: childID)
        await restored.generate()
        restored.undoParentChange()
        XCTAssertEqual(try loadedSession(fixture.store).parentAID, "seed-0")
    }

    func test_compileFailureRetainsSourceDiagnosticAndExposesSalvageActions() throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let model = storedModel(store: fixture.store, defaults: fixture.defaults)
        let childID = "r1-0"
        installCompileFailure(on: model, id: childID, message: "line 8: unknown symbol")

        XCTAssertEqual(model.currentRuns.first?.candidateSource, isf)
        XCTAssertEqual(model.compileDiagnostic(for: childID), "line 8: unknown symbol")
        XCTAssertEqual(
            model.compileSalvageActions(for: childID),
            [
                .viewCompileSummary,
                .openSourceInEditorToFix,
                .copyDiagnostic,
                .retryThisChild,
            ]
        )
    }

    func test_compileFailurePersistsCanonicalRunEvidence() throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let model = storedModel(store: fixture.store, defaults: fixture.defaults)
        let childID = "r1-0"
        installCompileFailure(on: model, id: childID, message: "line 12: bad uniform")
        model.persistSession()

        let saved = try loadedSession(fixture.store)
        XCTAssertNil(saved.lineage.node(childID))
        XCTAssertEqual(saved.currentRuns.first?.stage, .failed)
        XCTAssertEqual(saved.currentRuns.first?.failureBoundary, .compile)
        XCTAssertEqual(saved.currentRuns.first?.failureMessage, "line 12: bad uniform")
        XCTAssertEqual(saved.currentRuns.first?.compileDiagnostic, "line 12: bad uniform")

        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)
        XCTAssertEqual(restored.compileDiagnostic(for: childID), "line 12: bad uniform")
        XCTAssertEqual(
            restored.compileSalvageActions(for: childID),
            [
                .viewCompileSummary,
                .openSourceInEditorToFix,
                .copyDiagnostic,
                .retryThisChild,
            ]
        )
    }

    func test_restoredCompileFailureFindsCanonicalRunEvidenceWithoutLineageCopy() throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        var session = fixture.session
        var failedRun = try XCTUnwrap(session.currentRuns.first)
        XCTAssertTrue(failedRun.fail(
            boundary: .compile,
            message: "line 9: invalid sampler",
            at: Date(timeIntervalSince1970: 9)
        ))
        session.currentRuns = [failedRun]
        session.batchHistory = [RemixBatchRecord(round: failedRun.round, runs: [failedRun])]
        XCTAssertNil(session.lineage.node(failedRun.id))
        try fixture.store.save(session)

        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        XCTAssertEqual(restored.compileDiagnostic(for: failedRun.id), "line 9: invalid sampler")
        XCTAssertEqual(
            restored.compileSalvageActions(for: failedRun.id),
            [
                .viewCompileSummary,
                .openSourceInEditorToFix,
                .copyDiagnostic,
                .retryThisChild,
            ]
        )
    }

    func test_restoreLegacySessionWithoutCompileDiagnosticsDefaultsToEmpty() throws {
        let fixture = try restorationFixture()
        var legacySession = fixture.session
        legacySession.compileDiagnosticsByNodeID = nil
        try fixture.store.save(legacySession)

        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

        XCTAssertNil(restored.compileDiagnostic(for: "r7-0"))
        XCTAssertEqual(restored.compileSalvageActions(for: "r7-0"), [])
    }

    func test_compileFailureRemainsInAggregateSummaryAfterUnrelatedSuccess() throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let model = storedModel(store: fixture.store, defaults: fixture.defaults)
        installCompileFailure(on: model, id: "r1-0", message: "line 3: syntax error")
        let request = try XCTUnwrap(model.currentRuns.first?.request)
        var ready = RemixChildRunRecord(
            id: "r1-1", round: 1, slot: 1, request: request, stage: .compiling,
            queuedAt: Date(timeIntervalSince1970: 1), candidateSource: isf
        )
        XCTAssertTrue(ready.finishReady(artifactID: ready.id, at: Date(timeIntervalSince1970: 2)))
        model.applyPipelineUpdate(.artifact(
            RemixNode(
                artifactID: ready.id, isfSource: isf, parents: request.parentIDs,
                mode: request.mode, steer: request.steer, directive: request.directive, round: 1
            ),
            record: ready
        ))

        XCTAssertEqual(model.runSummary.stageCounts[.failed], 1)
        XCTAssertEqual(model.runSummary.stageCounts[.ready], 1)
        XCTAssertEqual(model.runSummary.terminalCount, 2)
        XCTAssertEqual(model.compileDiagnostic(for: "r1-0"), "line 3: syntax error")
        XCTAssertEqual(
            model.runSummary.activitySummary(activeProviderCount: 0).compactStatus,
            "2 of 2 complete · 0 active · 0 queued"
        )
    }

    func test_unparseableProviderReplyDoesNotExposeCompileSalvageActions() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let provider = FakeProvider([.success("This reply contains no shader source.")])
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        model.mode = .mutate
        model.batchSize = 1
        model.setParent(.a, isf: "seed")

        await model.generate()

        let childID = try XCTUnwrap(model.currentBatch.first?.id)
        XCTAssertEqual(model.currentBatch.first?.status, .failed("No ISF in reply"))
        XCTAssertNil(model.compileDiagnostic(for: childID))
        XCTAssertEqual(model.compileSalvageActions(for: childID), [])
    }

    func test_compileSummaryIsVisibleContentNotOnlySelection() {
        let m = model([.success("```glsl\n\(isf)\n```")])
        let id = "r1-0"
        installCompileFailure(on: m, id: id, message: "line 7: bad token")

        XCTAssertEqual(
            m.compileSummary(for: id),
            "Compile summary for \(id)\nline 7: bad token"
        )
    }

    func test_previewFailureHasRendererScopedActions() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let model = storedModel(store: fixture.store, defaults: fixture.defaults)
        model.mode = .mutate
        model.batchSize = 1
        model.setParent(.a, isf: "seed")
        await model.generate()
        let childID = try XCTUnwrap(model.currentBatch.first?.id)

        model.markPreviewFailed(artifactID: childID, diagnostic: "Metal device unavailable")

        XCTAssertEqual(model.previewStates[childID]?.diagnostic, "Metal device unavailable")
        XCTAssertEqual(model.previewFailureActions(for: childID), [.retryPreview, .openInEditor])
        XCTAssertEqual(model.currentBatch.first?.status, .compiled)
    }

    func test_retryPreviewDoesNotInvokeProviderOrChangeGenerationStatus() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        model.mode = .mutate
        model.batchSize = 1
        model.setParent(.a, isf: "seed")
        await model.generate()
        let childID = try XCTUnwrap(model.currentBatch.first?.id)
        let providerCallCount = provider.prompts.count
        let activityBeforeRetry = model.activity
        let statusBeforeRetry = model.currentBatch.first?.status
        model.markPreviewFailed(artifactID: childID, diagnostic: "renderer stopped")

        model.retryPreview(artifactID: childID)

        XCTAssertEqual(model.previewStates[childID]?.stage, .pending)
        XCTAssertNil(model.previewStates[childID]?.diagnostic)
        XCTAssertEqual(provider.prompts.count, providerCallCount)
        XCTAssertEqual(model.activity, activityBeforeRetry)
        XCTAssertEqual(model.currentBatch.first?.status, statusBeforeRetry)
    }

    func test_restoreSession_normalizesActiveRequestAndStandaloneActivityToNonRunningState() throws {
        let activePhases: [RemixParentRequestPhase] = [.fetching, .resuming, .converting]
        for phase in activePhases {
            let fixture = try restorationFixture()
            var session = fixture.session
            session.pendingParentRequest = RemixParentRequestSnapshot(
                id: fixture.requestID,
                slot: .b,
                source: .shadertoyLink("abc123"),
                displayInput: "abc123",
                phase: phase
            )
            session.activity = phase == .resuming
                ? .resuming(slot: .b, requestID: fixture.requestID)
                : .generating(total: 1, completed: 0, lastEventAt: nil)
            try fixture.store.save(session)

            let restored = storedModel(store: fixture.store, defaults: fixture.defaults)

            XCTAssertEqual(restored.pendingParentRequest?.phase, .waitingForHuman)
            XCTAssertEqual(restored.activity, .interrupted)
            XCTAssertFalse(restored.isGenerating)
        }
    }

    func test_startNewSession_blocksLateGenerationCallbacksFromRepopulatingClearedState() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let provider = SuspendedProvider()
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        model.mode = .mutate
        model.batchSize = 1
        model.setParent(.a, isf: "seed")

        let generation = Task { await model.generate() }
        while !provider.didStart { await Task.yield() }
        model.startNewSession()
        provider.finish(with: "```glsl\n\(isf)\n```")
        await generation.value

        XCTAssertTrue(model.currentBatch.isEmpty)
        XCTAssertTrue(model.batchHistory.isEmpty)
        XCTAssertTrue(model.lineage.allNodes.isEmpty)
        XCTAssertTrue(model.activeProviderChildIDs.isEmpty)
        XCTAssertEqual(model.activity, .idle)
        XCTAssertNil(model.parentAID)
        XCTAssertEqual(try loadedSession(fixture.store).activity, .idle)
        XCTAssertTrue(try loadedSession(fixture.store).currentBatch.isEmpty)
    }

    func test_cancelActiveGeneration_keepsCancelledTerminalStateAfterLateChildAndCompletion() async throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let provider = SuspendedProvider()
        let model = RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: fixture.store,
            defaults: fixture.defaults
        )
        model.mode = .mutate
        model.batchSize = 1
        model.setParent(.a, isf: "seed")

        model.startGeneration()
        while !provider.didStart { await Task.yield() }
        model.cancelGeneration()
        XCTAssertEqual(model.activity, .cancelled)

        provider.finish(with: "```glsl\n\(isf)\n```")
        while model.isGenerating { await Task.yield() }

        XCTAssertEqual(model.activity, .cancelled)
        XCTAssertEqual(try loadedSession(fixture.store).activity, .cancelled)
    }

    func test_routineAutosavesCoalesceAndLifecycleTransitionsFlushImmediately() throws {
        let fixture = try restorationFixture(saveInitialSession: false)
        let scheduler = DeterministicAutosaveScheduler()
        let model = storedModel(
            store: fixture.store,
            defaults: fixture.defaults,
            autosaveScheduler: scheduler.schedule
        )

        model.mode = .mutate
        model.steer = "first"
        model.steer = "final"
        model.selectedNodeID = "selection"

        XCTAssertEqual(scheduler.scheduledCount, 1)
        guard case .noSession = try fixture.store.load() else {
            return XCTFail("Routine mutations should wait for the bounded autosave")
        }

        scheduler.runPending()
        XCTAssertEqual(try loadedSession(fixture.store).steer, "final")
        XCTAssertEqual(try loadedSession(fixture.store).selectedLineageNodeID, "selection")

        model.startNewSession()
        XCTAssertEqual(try loadedSession(fixture.store).activity, .idle)
        XCTAssertEqual(try loadedSession(fixture.store).steer, "")
    }

    private struct RestorationFixture {
        let directory: URL
        let store: RemixSessionStore
        let defaults: UserDefaults
        let requestID: UUID
        let session: RemixSession
    }

    private func restorationFixture(saveInitialSession: Bool = true) throws -> RestorationFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "RemixStudioModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        var lineage = RemixLineage()
        for index in 2...5 {
            lineage.insert(RemixNode(
                id: "seed-\(index)",
                isfSource: "seed \(index)",
                parents: [],
                mode: .crossover,
                steer: "",
                directive: "seed",
                round: 0,
                status: .compiled
            ))
        }
        let child = RemixNode(
            id: "r7-0",
            isfSource: isf,
            parents: ["seed-4"],
            mode: .mutate,
            steer: "make it crystalline",
            directive: "prismatic",
            round: 7,
            status: .compiled
        )
        lineage.insert(child)
        var workspace = RemixWorkspaceState()
        workspace.showHero(child.id)
        var settings = RemixCrossoverSettings()
        settings.balance = 0.75
        let requestID = UUID()
        let request = RemixParentRequestSnapshot(
            id: requestID,
            slot: .b,
            source: .shadertoyLink("https://www.shadertoy.com/view/abc123"),
            displayInput: "abc123",
            phase: .verificationRequired
        )
        let session = RemixSession(
            round: 7,
            seedCounter: 6,
            parentAID: "seed-4",
            parentBID: "seed-5",
            parentHistory: [
                RemixParentConfiguration(parentAID: "seed-2", parentBID: "seed-3"),
                RemixParentConfiguration(parentAID: "seed-4", parentBID: "seed-5"),
            ],
            mode: .mutate,
            steer: "make it crystalline",
            batchSize: 3,
            currentBatch: [child],
            batchHistory: [RemixBatchRecord(round: 7, nodes: [child], requestsByNodeID: [:])],
            lineage: lineage,
            workspace: workspace,
            selectedLineageNodeID: child.id,
            crossoverSettings: settings,
            activity: .completed(failed: 0),
            pendingParentRequest: request,
            transcript: ["restored log"]
        )
        return RestorationFixture(
            directory: directory,
            store: RemixSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            defaults: defaults,
            requestID: requestID,
            session: session
        )
    }

    private func storedModel(
        store: RemixSessionStore,
        defaults: UserDefaults,
        autosaveScheduler: RemixStudioModel.AutosaveScheduler? = nil
    ) -> RemixStudioModel {
        let provider = FakeProvider([.success("```glsl\n\(isf)\n```")])
        return RemixStudioModel(
            generator: RemixGenerator(makeProvider: { provider }, model: nil),
            sessionStore: store,
            defaults: defaults,
            autosaveScheduler: autosaveScheduler
        )
    }

    private func loadedSession(_ store: RemixSessionStore) throws -> RemixSession {
        guard case let .session(session) = try store.load() else {
            throw NSError(domain: "RemixStudioModelTests", code: 1)
        }
        return session
    }

    func test_continueVerification_foregroundsExistingChallengeWithoutRestartingRequest() async {
        let m = model([.success(isf)])
        var foregroundCount = 0
        let resolver = RemixParentResolver(
            currentEditorSource: { nil },
            fetchShadertoy: { _, onState in
                onState(.verificationRequired)
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return "unreachable"
            },
            foregroundVerification: {
                foregroundCount += 1
                return true
            }
        )
        let request = RemixParentRequest(
            slot: .b,
            spec: .shadertoyLink("abc123"),
            displayInput: "abc123"
        )
        m.loadParent(request, from: resolver)
        await Task.yield()

        let result = m.continueParentVerification(from: resolver)

        XCTAssertEqual(result, .foregrounded(requestID: request.id, slot: .b))
        XCTAssertEqual(foregroundCount, 1)
        XCTAssertEqual(m.parentLoadState.request, request)
        _ = m.cancelParentLoad()
    }

    func test_continueVerification_afterRestoreRestartsExactTypedRequest() async throws {
        let fixture = try restorationFixture()
        try fixture.store.save(fixture.session)
        let restored = storedModel(store: fixture.store, defaults: fixture.defaults)
        var fetchInput: String?
        let fetchStarted = expectation(description: "restored fetch started")
        let resolver = RemixParentResolver(
            currentEditorSource: { nil },
            fetchShadertoy: { input in
                fetchInput = input
                fetchStarted.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return "unreachable"
            }
        )

        let result = restored.continueParentVerification(from: resolver)
        await fulfillment(of: [fetchStarted], timeout: 1)

        let expected = try XCTUnwrap(RemixParentRequest(snapshot: fixture.session.pendingParentRequest!))
        guard case .shadertoyLink(let expectedFetchInput) = expected.spec else {
            return XCTFail("Expected restored Shadertoy request")
        }
        XCTAssertEqual(result, .restarted(expected))
        XCTAssertEqual(restored.parentLoadState.request, expected)
        XCTAssertEqual(fetchInput, expectedFetchInput)
        _ = restored.cancelParentLoad()
    }
}
