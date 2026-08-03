import XCTest
@testable import TrueISFEditor

@MainActor
private final class PipelineUpdateCollector {
    private(set) var recordsByID: [String: RemixChildRunRecord]
    private(set) var updates: [RemixPipelineUpdate] = []
    private(set) var liveChildIDs: Set<String> = []

    init(records: [RemixChildRunRecord]) {
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    func receive(_ update: RemixPipelineUpdate) {
        updates.append(update)
        switch update {
        case .record(let record):
            recordsByID[record.id] = record
            if record.stage.isTerminal {
                liveChildIDs.remove(record.id)
            }
        case .artifact(_, let record):
            recordsByID[record.id] = record
            liveChildIDs.remove(record.id)
        case .processLiveness(let childID, let isAlive):
            if isAlive {
                liveChildIDs.insert(childID)
            } else {
                liveChildIDs.remove(childID)
            }
        }
    }

    var finalRecords: [RemixChildRunRecord] {
        recordsByID.values.sorted { $0.slot < $1.slot }
    }

    func stages(for childID: String) -> [RemixChildRunRecord.Stage] {
        updates.compactMap { update in
            switch update {
            case .record(let record) where record.id == childID:
                return record.stage
            case .artifact(_, let record) where record.id == childID:
                return record.stage
            default:
                return nil
            }
        }
    }
}

@MainActor
private final class ControlledDetailedProvider: AssistProvider, AssistDetailedProvider {
    enum CancellationBehavior {
        case fail
        case awaitExplicitResolution
    }

    private let cancellationBehavior: CancellationBehavior
    private var continuation: CheckedContinuation<AssistRunResult, Error>?
    private var eventHandler: (@Sendable (AssistRunEvent) -> Void)?
    private var rawLineHandler: (@Sendable (String) -> Void)?
    private(set) var didStart = false
    private(set) var cancellationCount = 0

    init(cancellationBehavior: CancellationBehavior = .fail) {
        self.cancellationBehavior = cancellationBehavior
    }

    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        let result = try await runDetailed(
            prompt: prompt,
            system: system,
            model: model,
            timeout: timeout,
            onEvent: { _ in },
            onRawLine: onEvent
        )
        return result.response
    }

    func runDetailed(
        prompt: String,
        system: String,
        model: String?,
        timeout: TimeInterval,
        onEvent: @escaping @Sendable (AssistRunEvent) -> Void,
        onRawLine: @escaping @Sendable (String) -> Void
    ) async throws -> AssistRunResult {
        didStart = true
        eventHandler = onEvent
        rawLineHandler = onRawLine
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled {
                    cancelProviderTask()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelProviderTask()
            }
        }
    }

    func emit(_ event: AssistRunEvent) {
        eventHandler?(event)
    }

    func emitRawLine(_ line: String) {
        rawLineHandler?(line)
    }

    func succeed(_ response: String, provider: AssistProviderIdentity = .claude) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: AssistRunResult(
            provider: provider,
            response: response,
            source: .assistantMessage,
            observedSuccessfulResult: true,
            completeAssistantResponse: response,
            successfulResultText: "",
            receivedBytes: response.utf8.count,
            eventCount: 1
        ))
    }

    func fail(_ error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    private func cancelProviderTask() {
        cancellationCount += 1
        emit(.cancelled)
        guard cancellationBehavior == .fail, let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }
}

@MainActor
private final class DetailedProviderHarness {
    private let cancellationBehavior: ControlledDetailedProvider.CancellationBehavior
    private(set) var providers: [ControlledDetailedProvider] = []

    init(cancellationBehavior: ControlledDetailedProvider.CancellationBehavior = .fail) {
        self.cancellationBehavior = cancellationBehavior
    }

    func makeProvider() -> AssistProvider {
        let provider = ControlledDetailedProvider(cancellationBehavior: cancellationBehavior)
        providers.append(provider)
        return provider
    }
}

@MainActor
private final class ImmediatePipelineCompiler: RemixCompiling {
    private let result: RemixCompileResult
    private(set) var sources: [String] = []

    init(result: RemixCompileResult = RemixCompileResult(
        isValid: true,
        diagnostic: nil,
        errorLine: nil
    )) {
        self.result = result
    }

    func compile(_ source: String) async -> RemixCompileResult {
        sources.append(source)
        return result
    }
}

@MainActor
private final class ControlledPipelineCompiler: RemixCompiling {
    private var continuation: CheckedContinuation<RemixCompileResult, Never>?
    private(set) var source: String?

    func compile(_ source: String) async -> RemixCompileResult {
        self.source = source
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ result: RemixCompileResult = RemixCompileResult(
        isValid: true,
        diagnostic: nil,
        errorLine: nil
    )) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}

@MainActor
private final class TwoPhaseExtractor {
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private let result: Result<String, RemixResponseError>
    private(set) var wasRequested = false
    private(set) var didStartWork = false

    init(result: Result<String, RemixResponseError>) {
        self.result = result
    }

    func extract(_ response: String) async -> Result<String, RemixResponseError> {
        wasRequested = true
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
        didStartWork = true
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
        return result
    }

    func beginWork() {
        guard let startContinuation else { return }
        self.startContinuation = nil
        startContinuation.resume()
    }

    func finishWork() {
        guard let finishContinuation else { return }
        self.finishContinuation = nil
        finishContinuation.resume()
    }
}

@MainActor
final class RemixBatchRunControllerTests: XCTestCase {
    private let validISF = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }"

    func test_stopBeforeInitialLaunch_createsNoProviderAndCancelsEveryRun() async {
        let harness = DetailedProviderHarness()
        let compiler = ImmediatePipelineCompiler()
        let generator = makeGenerator(harness: harness, compiler: compiler)
        let records = makeRecords(count: 5)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        controller.stop()

        await generator.generate(
            records: records,
            controller: controller,
            onUpdate: updates.receive
        )

        XCTAssertEqual(harness.providers.count, 0)
        XCTAssertTrue(updates.finalRecords.allSatisfy { $0.stage == .cancelled })
        assertSettled(updates)
    }

    func test_stopWithTwoActiveAndThreeQueued_cancelsOnlyActiveAndNeverBackfills() async {
        let harness = DetailedProviderHarness()
        let generator = makeGenerator(harness: harness, compiler: ImmediatePipelineCompiler())
        let records = makeRecords(count: 5)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(
                records: records,
                controller: controller,
                onUpdate: updates.receive
            )
        }

        await assertEventually { harness.providers.count == 2 &&
            harness.providers.allSatisfy(\.didStart)
        }
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        harness.providers[0].emit(.processStarted(pid: 41))
        harness.providers[1].emit(.processStarted(pid: 42))
        await assertEventually {
            controller.activeProviderChildIDs == ["r1-0", "r1-1"]
        }
        controller.stop()
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        await generation.value

        XCTAssertEqual(harness.providers.count, 2)
        XCTAssertEqual(harness.providers.map(\.cancellationCount), [1, 1])
        XCTAssertTrue(updates.finalRecords.allSatisfy { $0.stage == .cancelled })
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        assertSettled(updates)
    }

    func test_stopAfterAuthoritativeResultBeforeExtraction_allowsLocalPipelineToReachReady() async {
        let harness = DetailedProviderHarness()
        let extractor = TwoPhaseExtractor(result: .success(validISF))
        let compiler = ImmediatePipelineCompiler()
        let generator = makeGenerator(
            harness: harness,
            compiler: compiler,
            extractCandidate: extractor.extract
        )
        let records = makeRecords(count: 1)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.first?.didStart == true }
        harness.providers[0].succeed("authoritative response")
        await assertEventually { extractor.wasRequested }
        XCTAssertFalse(extractor.didStartWork)
        XCTAssertFalse(controller.isProviderRegistered(childID: "r1-0"))
        XCTAssertTrue(controller.canLaunch)
        controller.stop()
        extractor.beginWork()
        await assertEventually { extractor.didStartWork }
        extractor.finishWork()
        await generation.value

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.ready])
        XCTAssertEqual(compiler.sources, [validISF])
        assertSettled(updates)
    }

    func test_stopDuringExtraction_allowsExtractionAndCompilationToFinish() async {
        let harness = DetailedProviderHarness()
        let extractor = TwoPhaseExtractor(result: .success(validISF))
        let compiler = ImmediatePipelineCompiler()
        let generator = makeGenerator(
            harness: harness,
            compiler: compiler,
            extractCandidate: extractor.extract
        )
        let records = makeRecords(count: 1)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.first?.didStart == true }
        harness.providers[0].succeed("authoritative response")
        await assertEventually { extractor.wasRequested }
        extractor.beginWork()
        await assertEventually { extractor.didStartWork }
        controller.stop()
        extractor.finishWork()
        await generation.value

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.ready])
        XCTAssertEqual(compiler.sources, [validISF])
        assertSettled(updates)
    }

    func test_stopDuringCompilation_allowsCompilationToFinish() async {
        let harness = DetailedProviderHarness()
        let compiler = ControlledPipelineCompiler()
        let generator = makeGenerator(harness: harness, compiler: compiler)
        let records = makeRecords(count: 1)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.first?.didStart == true }
        harness.providers[0].succeed(validISF)
        await assertEventually { compiler.source == self.validISF }
        controller.stop()
        compiler.finish()
        await generation.value

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.ready])
        XCTAssertTrue(updates.stages(for: "r1-0").contains(.compiling))
        assertSettled(updates)
    }

    func test_providerFailureBackfillsSiblingWhileLaunchGateIsOpen() async {
        let harness = DetailedProviderHarness()
        let generator = makeGenerator(harness: harness, compiler: ImmediatePipelineCompiler())
        let records = makeRecords(count: 3)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.count == 2 &&
            harness.providers.allSatisfy(\.didStart)
        }
        harness.providers[0].fail(AssistAssemblyError.providerFailed("provider zero failed"))
        await assertEventually { harness.providers.count == 3 && harness.providers[2].didStart }
        harness.providers[1].succeed(validISF)
        harness.providers[2].succeed(validISF)
        await generation.value

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.failed, .ready, .ready])
        XCTAssertEqual(updates.finalRecords[0].failureBoundary, .provider)
        XCTAssertFalse(controller.launchGateClosed)
        assertSettled(updates)
    }

    func test_stopWinsRaceBeforeLateAuthoritativeCompletion_andTerminalTransitionStaysCancelled() async {
        let harness = DetailedProviderHarness(cancellationBehavior: .awaitExplicitResolution)
        let generator = makeGenerator(harness: harness, compiler: ImmediatePipelineCompiler())
        let records = makeRecords(count: 1)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.first?.didStart == true }
        controller.stop()
        await assertEventually { harness.providers[0].cancellationCount == 1 }
        harness.providers[0].succeed(validISF)
        await generation.value

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.cancelled])
        XCTAssertFalse(updates.stages(for: "r1-0").contains(.ready))
        assertSettled(updates)
    }

    func test_typedLifecycleEventsDriveLiveness_andLateStartCannotResurrectTerminalRun() async {
        let harness = DetailedProviderHarness()
        let generator = makeGenerator(harness: harness, compiler: ImmediatePipelineCompiler())
        let records = makeRecords(count: 1)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.first?.didStart == true }
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        harness.providers[0].emit(.processStarted(pid: 42))
        await assertEventually { controller.activeProviderChildIDs == ["r1-0"] }
        harness.providers[0].emit(.processExited(0))
        await assertEventually { controller.activeProviderChildIDs.isEmpty }
        harness.providers[0].emit(.processStarted(pid: 43))
        await assertEventually { controller.activeProviderChildIDs == ["r1-0"] }
        harness.providers[0].emit(.timedOut)
        await assertEventually { controller.activeProviderChildIDs.isEmpty }
        harness.providers[0].emit(.processStarted(pid: 44))
        await assertEventually { controller.activeProviderChildIDs == ["r1-0"] }
        harness.providers[0].emit(.cancelled)
        await assertEventually { controller.activeProviderChildIDs.isEmpty }
        harness.providers[0].emit(.processStarted(pid: 45))
        await assertEventually { controller.activeProviderChildIDs == ["r1-0"] }
        harness.providers[0].fail(AssistAssemblyError.providerFailed("provider failed"))
        await generation.value
        let updateCountAtTerminal = updates.updates.count
        harness.providers[0].emit(.processStarted(pid: 99))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.failed])
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        XCTAssertTrue(updates.liveChildIDs.isEmpty)
        XCTAssertEqual(updates.updates.count, updateCountAtTerminal)
        assertSettled(updates)
    }

    func test_providerRetryAndActivityEmitTruthfulOrderedStagesAndRetainEvidence() async {
        let harness = DetailedProviderHarness()
        let generator = makeGenerator(harness: harness, compiler: ImmediatePipelineCompiler())
        let records = makeRecords(count: 1)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.first?.didStart == true }
        harness.providers[0].emit(.thinking)
        await assertEventually { updates.finalRecords[0].stage == .thinking }
        harness.providers[0].emit(.apiRetry(attempt: 2, message: "rate limited"))
        await assertEventually { updates.finalRecords[0].stage == .retrying }
        harness.providers[0].emit(.textDelta(messageID: "m1", blockIndex: 0, text: "abc"))
        await assertEventually { updates.finalRecords[0].stage == .receiving }
        harness.providers[0].succeed(validISF, provider: .codex)
        await generation.value

        let record = updates.finalRecords[0]
        XCTAssertEqual(record.stage, .ready)
        XCTAssertEqual(record.provider, .codex)
        XCTAssertEqual(record.apiRetryCount, 2)
        XCTAssertEqual(record.lastProviderNotice, "rate limited")
        XCTAssertGreaterThanOrEqual(record.receivedBytes, 3)
        XCTAssertEqual(record.diagnosticResponse, validISF)
        XCTAssertEqual(record.candidateSource, validISF)
        XCTAssertEqual(
            updates.stages(for: "r1-0"),
            [.starting, .thinking, .thinking, .retrying, .receiving, .extracting, .compiling, .ready]
        )
        assertSettled(updates)
    }

    func test_responseExtractionAndCompileFailuresRecordExactBoundaries() async {
        let harness = DetailedProviderHarness()
        let compiler = ImmediatePipelineCompiler(result: RemixCompileResult(
            isValid: false,
            diagnostic: "metal rejected candidate",
            errorLine: 7
        ))
        let generator = makeGenerator(
            harness: harness,
            compiler: compiler,
            maxConcurrent: 3,
            extractCandidate: { response in
                switch response {
                case "no candidate": return .failure(.noISFFound)
                case "broken candidate": return .failure(.incompleteSource)
                default: return .success(self.validISF)
                }
            }
        )
        let records = makeRecords(count: 3)
        let updates = PipelineUpdateCollector(records: records)
        let controller = RemixBatchRunController()
        let generation = Task { @MainActor in
            await generator.generate(records: records, controller: controller, onUpdate: updates.receive)
        }

        await assertEventually { harness.providers.count == 3 &&
            harness.providers.allSatisfy(\.didStart)
        }
        harness.providers[0].succeed("no candidate")
        harness.providers[1].succeed("broken candidate")
        harness.providers[2].succeed("compile candidate")
        await generation.value

        XCTAssertEqual(updates.finalRecords.map(\.stage), [.failed, .failed, .failed])
        XCTAssertEqual(updates.finalRecords.map(\.failureBoundary), [.response, .extraction, .compile])
        XCTAssertEqual(updates.finalRecords[2].compileDiagnostic, "metal rejected candidate")
        XCTAssertEqual(compiler.sources, [validISF])
        assertSettled(updates)
    }

    func test_controllerRegistrationDoesNotImplyLiveness_andFinishedTaskRejectsLateStart() async {
        let controller = RemixBatchRunController()
        let task = Task<AssistRunResult, Error> {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw CancellationError()
        }

        controller.registerProviderTask(task, childID: "r1-0")
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        controller.providerProcessStarted(childID: "r1-0")
        XCTAssertEqual(controller.activeProviderChildIDs, ["r1-0"])
        controller.providerProcessExited(childID: "r1-0")
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        XCTAssertTrue(controller.providerFinished(childID: "r1-0"))
        controller.providerProcessStarted(childID: "r1-0")
        XCTAssertTrue(controller.activeProviderChildIDs.isEmpty)
        task.cancel()
        _ = await task.result

        let records = makeRecords(count: 1).map { record in
            var record = record
            _ = record.transition(to: .cancelled, at: Date())
            return record
        }
        let updates = PipelineUpdateCollector(records: records)
        assertSettled(updates)
    }

    private func makeGenerator(
        harness: DetailedProviderHarness,
        compiler: RemixCompiling,
        maxConcurrent: Int = 2,
        extractCandidate: @escaping RemixGenerator.CandidateExtractor = {
            RemixResponseParser.extractCandidate($0)
        }
    ) -> RemixGenerator {
        RemixGenerator(
            makeProvider: harness.makeProvider,
            model: nil,
            maxConcurrent: maxConcurrent,
            systemProvider: { "" },
            compiler: compiler,
            extractCandidate: extractCandidate
        )
    }

    private func makeRecords(count: Int, round: Int = 1) -> [RemixChildRunRecord] {
        (0..<count).map { slot in
            RemixChildRunRecord(
                id: "r\(round)-\(slot)",
                round: round,
                slot: slot,
                request: RemixGenerationRequestSnapshot(
                    parentIDs: ["seed"],
                    parentSources: ["/*{A}*/"],
                    mode: .mutate,
                    steer: "",
                    directive: "directive \(slot)",
                    settings: RemixCrossoverSettings()
                ),
                queuedAt: Date(timeIntervalSince1970: TimeInterval(slot))
            )
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    private func assertEventually(
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let didSatisfy = await waitUntil(timeout: timeout, condition: condition)
        XCTAssertTrue(didSatisfy, file: file, line: line)
    }

    private func assertSettled(
        _ updates: PipelineUpdateCollector,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            updates.finalRecords.allSatisfy(\.stage.isTerminal),
            file: file,
            line: line
        )
        XCTAssertFalse(
            updates.finalRecords.contains { $0.stage == .queued || $0.stage == .starting },
            file: file,
            line: line
        )
    }
}
