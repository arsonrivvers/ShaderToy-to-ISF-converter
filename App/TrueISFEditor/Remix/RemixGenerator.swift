import Foundation

@MainActor
private final class RemixChildPipelineState {
    private(set) var record: RemixChildRunRecord
    private let controller: RemixBatchRunController
    private let onUpdate: (RemixPipelineUpdate) -> Void

    init(
        record: RemixChildRunRecord,
        controller: RemixBatchRunController,
        onUpdate: @escaping (RemixPipelineUpdate) -> Void
    ) {
        self.record = record
        self.controller = controller
        self.onUpdate = onUpdate
    }

    func start() -> Bool {
        guard record.transition(to: .starting, at: Date()) else { return false }
        emitRecord()
        return true
    }

    func beginProviderWait() {
        guard record.transition(to: .thinking, at: Date()) else { return }
        emitRecord()
    }

    func handle(_ event: AssistRunEvent) {
        guard !record.stage.isTerminal else { return }
        let now = Date()
        switch event {
        case .processStarted:
            if controller.providerProcessStarted(childID: record.id) {
                onUpdate(.processLiveness(childID: record.id, isAlive: true))
            }
        case .processExited, .timedOut, .cancelled:
            if controller.providerProcessExited(childID: record.id) {
                onUpdate(.processLiveness(childID: record.id, isAlive: false))
            }
        case .thinking:
            if record.stage == .starting || record.stage == .retrying {
                if record.transition(to: .thinking, at: now) { emitRecord() }
            } else {
                record.lastEventAt = now
                emitRecord()
            }
        case .textDelta(_, _, let text):
            record.recordProviderActivity(bytes: text.utf8.count, at: now)
            emitRecord()
        case .assistantMessage(_, _, let blocks):
            if record.stage == .starting || record.stage == .thinking || record.stage == .retrying {
                let bytes = blocks.reduce(0) { $0 + $1.text.utf8.count }
                record.recordProviderActivity(bytes: bytes, at: now)
                emitRecord()
            } else {
                record.lastEventAt = now
                emitRecord()
            }
        case .apiRetry(let attempt, let message):
            record.recordAPIRetry(attempt: attempt, message: message, at: now)
            emitRecord()
        case .sessionStarted, .successfulResult, .errorResult:
            record.lastEventAt = now
            emitRecord()
        }
    }

    func acceptProviderResult(_ result: AssistRunResult) {
        guard !record.stage.isTerminal else { return }
        record.provider = result.provider
        record.receivedBytes = max(record.receivedBytes, result.receivedBytes)
        record.recordDiagnosticResponse(result.response)
    }

    func beginExtraction() -> Bool {
        guard record.transition(to: .extracting, at: Date()) else { return false }
        emitRecord()
        return true
    }

    func retainCandidate(_ source: String) {
        guard !record.stage.isTerminal else { return }
        record.candidateSource = source
    }

    func beginCompilation() -> Bool {
        guard record.transition(to: .compiling, at: Date()) else { return false }
        emitRecord()
        return true
    }

    func fail(boundary: RemixChildRunRecord.FailureBoundary, message: String) {
        guard record.fail(boundary: boundary, message: message, at: Date()) else { return }
        onUpdate(.processLiveness(childID: record.id, isAlive: false))
        emitRecord()
    }

    func cancel() {
        guard record.transition(to: .cancelled, at: Date()) else { return }
        onUpdate(.processLiveness(childID: record.id, isAlive: false))
        emitRecord()
    }

    func finishReady() {
        guard record.finishReady(artifactID: record.id, at: Date()),
              let source = record.candidateSource
        else {
            return
        }
        let artifact = RemixNode(
            artifactID: record.id,
            isfSource: source,
            parents: record.request.parentIDs,
            mode: record.request.mode,
            steer: record.request.steer,
            directive: record.request.directive,
            round: record.round
        )
        onUpdate(.processLiveness(childID: record.id, isAlive: false))
        onUpdate(.artifact(artifact, record: record))
    }

    func emitProviderNotAlive() {
        onUpdate(.processLiveness(childID: record.id, isAlive: false))
    }

    private func emitRecord() {
        onUpdate(.record(record))
    }
}

/// Launch-gated provider scheduler. Provider work is independently cancellable; the outer scheduler
/// remains alive to settle every stable slot, and local parser/compiler work survives Stop after an
/// authoritative result wins the controller registration race.
@MainActor
final class RemixGenerator {
    typealias CandidateExtractor = @MainActor (String) async -> Result<String, RemixResponseError>

    /// Presentation order for a child's parents. Two parents alternate by seed parity (even ⇒ A-first,
    /// odd ⇒ B-first) to defeat first-position anchoring; labels travel with their source so "A"
    /// always names parent-slot-A regardless of print order. Other counts are returned unchanged.
    nonisolated static func orderedParents(
        _ pairs: [(label: String, source: String)],
        seed: Int
    ) -> [(label: String, source: String)] {
        guard pairs.count == 2 else { return pairs }
        return seed % 2 == 0 ? pairs : [pairs[1], pairs[0]]
    }

    private let makeProvider: () -> AssistProvider
    private let modelProvider: () -> String?
    private let systemProvider: () -> String
    private let maxConcurrent: Int
    private let timeout: TimeInterval
    private let compiler: RemixCompiling
    private let extractCandidate: CandidateExtractor

    convenience init(
        makeProvider: @escaping () -> AssistProvider,
        model: String?,
        maxConcurrent: Int = 2,
        timeout: TimeInterval = 420,
        systemProvider: @escaping () -> String = RemixPrompt.system,
        compiler: RemixCompiling? = nil,
        extractCandidate: @escaping CandidateExtractor = {
            RemixResponseParser.extractCandidate($0)
        }
    ) {
        self.init(
            makeProvider: makeProvider,
            modelProvider: { model },
            maxConcurrent: maxConcurrent,
            timeout: timeout,
            systemProvider: systemProvider,
            compiler: compiler,
            extractCandidate: extractCandidate
        )
    }

    init(
        makeProvider: @escaping () -> AssistProvider,
        modelProvider: @escaping () -> String?,
        maxConcurrent: Int = 2,
        timeout: TimeInterval = 420,
        systemProvider: @escaping () -> String = RemixPrompt.system,
        compiler: RemixCompiling? = nil,
        extractCandidate: @escaping CandidateExtractor = {
            RemixResponseParser.extractCandidate($0)
        }
    ) {
        self.makeProvider = makeProvider
        self.modelProvider = modelProvider
        self.maxConcurrent = max(1, maxConcurrent)
        self.timeout = timeout
        self.systemProvider = systemProvider
        // One generator owns exactly one compiler (and therefore one native serial queue) unless a
        // test supplies the single fake seam.
        self.compiler = compiler ?? NativeRemixCompiler()
        self.extractCandidate = extractCandidate
    }

    /// Runs pre-seeded stable records and emits ordered per-child state updates. The supplied
    /// controller is caller-owned so the studio can expose Stop without cancelling this outer task.
    func generate(
        records: [RemixChildRunRecord],
        controller: RemixBatchRunController,
        onUpdate: @escaping (RemixPipelineUpdate) -> Void,
        onInitialSlotScheduled: ((Int) -> Void)? = nil,
        onLog: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) async {
        guard !records.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var nextIndex = 0

            @MainActor func cancelUnlaunched() {
                while nextIndex < records.count {
                    var record = records[nextIndex]
                    nextIndex += 1
                    if record.transition(to: .cancelled, at: Date()) {
                        onUpdate(.processLiveness(childID: record.id, isAlive: false))
                        onUpdate(.record(record))
                    }
                }
            }

            @MainActor func launchNext(onScheduled: ((Int) -> Void)? = nil) -> Bool {
                guard nextIndex < records.count, controller.canLaunch, !Task.isCancelled else {
                    return false
                }
                let record = records[nextIndex]
                nextIndex += 1
                group.addTask { @MainActor [self] in
                    await runChild(
                        record: record,
                        controller: controller,
                        onUpdate: onUpdate,
                        onLog: onLog
                    )
                }
                onScheduled?(record.slot)
                return true
            }

            guard controller.canLaunch, !Task.isCancelled else {
                cancelUnlaunched()
                return
            }
            while nextIndex < min(maxConcurrent, records.count) {
                guard launchNext(onScheduled: onInitialSlotScheduled) else { break }
            }
            while await group.next() != nil {
                if controller.canLaunch, !Task.isCancelled {
                    _ = launchNext()
                }
            }
            cancelUnlaunched()
        }
    }

    /// Compatibility surface used until Task 7 moves the studio model onto durable run records.
    func generate(
        parents: [String],
        mode: RemixMode,
        steer: String,
        batchSize: Int,
        round: Int,
        settings: RemixCrossoverSettings = RemixCrossoverSettings(),
        pool: [String] = RemixDirectives.catalog,
        onChild: @escaping (RemixNode) -> Void,
        onLog: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) async {
        let directives = RemixDirectives.pick(batchSize, seed: round, from: pool)
        let queuedAt = Date()
        let records = (0..<batchSize).map { slot in
            RemixChildRunRecord(
                id: "r\(round)-\(slot)",
                round: round,
                slot: slot,
                request: RemixGenerationRequestSnapshot(
                    parentIDs: [],
                    parentSources: parents,
                    mode: mode,
                    steer: steer,
                    directive: directives[slot],
                    settings: settings
                ),
                queuedAt: queuedAt
            )
        }
        let controller = RemixBatchRunController()
        await generate(
            records: records,
            controller: controller,
            onUpdate: { update in
                switch update {
                case .artifact(let artifact, _):
                    onChild(artifact)
                case .record(let record) where record.stage.isTerminal:
                    if record.stage != .ready {
                        onChild(Self.legacyNode(from: record))
                    }
                case .record, .processLiveness:
                    break
                }
            },
            onLog: onLog
        )
    }

    /// Generate exactly one child into a stable lineage slot. Retry callers supply the immutable
    /// request captured for that slot, so changing studio controls cannot alter retry inputs.
    func generateChild(
        id: String,
        request: RemixGenerationRequestSnapshot,
        onLog: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) async -> RemixNode {
        let record = RemixChildRunRecord(
            id: id,
            round: Self.roundIndex(in: id),
            slot: Self.slotIndex(in: id),
            request: request,
            queuedAt: Date()
        )
        let controller = RemixBatchRunController()
        var finalNode: RemixNode?
        var finalRecord = record
        await generate(
            records: [record],
            controller: controller,
            onUpdate: { update in
                switch update {
                case .artifact(let artifact, let readyRecord):
                    finalNode = artifact
                    finalRecord = readyRecord
                case .record(let updated):
                    finalRecord = updated
                case .processLiveness:
                    break
                }
            },
            onLog: onLog
        )
        return finalNode ?? Self.legacyNode(from: finalRecord)
    }

    private func runChild(
        record: RemixChildRunRecord,
        controller: RemixBatchRunController,
        onUpdate: @escaping (RemixPipelineUpdate) -> Void,
        onLog: @escaping @Sendable (String, String) -> Void
    ) async {
        let state = RemixChildPipelineState(
            record: record,
            controller: controller,
            onUpdate: onUpdate
        )
        guard controller.canLaunch, !Task.isCancelled else {
            state.cancel()
            return
        }
        guard state.start() else { return }

        let request = record.request
        let labeled = request.parentSources.enumerated().map {
            (label: $0.offset == 0 ? "A" : "B", source: $0.element)
        }
        let ordered = Self.orderedParents(
            labeled,
            seed: record.round * 1000 + record.slot
        )
        let prompt = RemixPrompt.user(
            parents: ordered,
            mode: request.mode,
            steer: request.steer,
            directive: request.directive,
            settings: request.settings
        )
        let provider = makeProvider()
        let model = modelProvider()
        let system = systemProvider()
        let (eventStream, eventContinuation) = AsyncStream<AssistRunEvent>.makeStream()
        let eventConsumer = Task { @MainActor in
            for await event in eventStream {
                state.handle(event)
            }
        }
        let providerTask: Task<AssistRunResult, Error> = Task { @MainActor [self] in
            try await runProvider(
                provider,
                prompt: prompt,
                system: system,
                model: model,
                onEvent: { eventContinuation.yield($0) },
                onRawLine: { onLog(record.id, $0) }
            )
        }
        guard controller.registerProviderTask(providerTask, childID: record.id) else {
            eventContinuation.finish()
            await eventConsumer.value
            state.cancel()
            return
        }
        state.beginProviderWait()

        let result: AssistRunResult
        do {
            result = try await withTaskCancellationHandler {
                try await providerTask.value
            } onCancel: {
                providerTask.cancel()
            }
            // This check/removal is the linearization point for provider completion versus Stop.
            let completionWon = controller.providerFinished(childID: record.id)
            state.emitProviderNotAlive()
            eventContinuation.finish()
            await eventConsumer.value
            guard completionWon else {
                state.cancel()
                return
            }
        } catch {
            let completionWon = controller.providerFinished(childID: record.id)
            state.emitProviderNotAlive()
            eventContinuation.finish()
            await eventConsumer.value
            if error is CancellationError || !completionWon {
                state.cancel()
            } else {
                state.fail(boundary: .provider, message: Self.providerFailureMessage(error))
            }
            return
        }

        state.acceptProviderResult(result)
        guard state.beginExtraction() else { return }
        let extraction = await extractCandidate(result.response)
        let candidate: String
        switch extraction {
        case .success(let source):
            candidate = source
            state.retainCandidate(source)
        case .failure(let error):
            let boundary: RemixChildRunRecord.FailureBoundary = error == .noISFFound
                ? .response
                : .extraction
            state.fail(boundary: boundary, message: Self.extractionFailureMessage(error))
            return
        }

        guard state.beginCompilation() else { return }
        let compileResult = await compiler.compile(candidate)
        guard compileResult.isValid else {
            state.fail(
                boundary: .compile,
                message: compileResult.diagnostic ?? "Native compilation failed."
            )
            return
        }
        state.finishReady()
    }

    /// The app factory is temporarily erased to `AssistProvider`. Production runners conform to the
    /// detailed protocol and take the typed path; the legacy branch exists only to keep pre-Task-7
    /// call sites and fakes source-compatible while the studio migration lands.
    private func runProvider(
        _ provider: AssistProvider,
        prompt: String,
        system: String,
        model: String?,
        onEvent: @escaping @Sendable (AssistRunEvent) -> Void,
        onRawLine: @escaping @Sendable (String) -> Void
    ) async throws -> AssistRunResult {
        if let detailed = provider as? AssistDetailedProvider {
            return try await detailed.runDetailed(
                prompt: prompt,
                system: system,
                model: model,
                timeout: timeout,
                onEvent: onEvent,
                onRawLine: onRawLine
            )
        }

        let response = try await provider.run(
            prompt: prompt,
            system: system,
            model: model,
            timeout: timeout,
            onEvent: onRawLine
        )
        return AssistRunResult(
            provider: .claude,
            response: response,
            source: .result,
            observedSuccessfulResult: true,
            completeAssistantResponse: response,
            successfulResultText: response,
            receivedBytes: response.utf8.count,
            eventCount: 1
        )
    }

    private static func legacyNode(from record: RemixChildRunRecord) -> RemixNode {
        let source = record.candidateSource ?? record.diagnosticResponse ?? ""
        let status: RemixNode.Status
        switch record.stage {
        case .ready:
            status = .compiled
        case .interrupted:
            status = .interrupted
        case .cancelled:
            status = .failed("cancelled")
        case .failed:
            status = .failed(record.failureMessage ?? "Generation failed")
        case .queued, .starting, .thinking, .receiving, .retrying, .extracting, .compiling:
            status = .interrupted
        }
        return RemixNode(
            id: record.id,
            isfSource: source,
            parents: record.request.parentIDs,
            mode: record.request.mode,
            steer: record.request.steer,
            directive: record.request.directive,
            round: record.round,
            status: status
        )
    }

    private static func providerFailureMessage(_ error: Error) -> String {
        switch error {
        case AssistAssemblyError.providerFailed(let message):
            return message
        case AssistAssemblyError.noAuthoritativeResponse:
            return "No authoritative provider response."
        default:
            return String(describing: error)
        }
    }

    private static func extractionFailureMessage(_ error: RemixResponseError) -> String {
        switch error {
        case .noISFFound:
            return "No ISF in reply"
        case .incompleteFence:
            return "The provider response ended inside an ISF code fence."
        case .invalidHeader(let message):
            return message
        case .incompleteSource:
            return "The provider response contained an incomplete ISF source."
        }
    }

    private static func roundIndex(in id: String) -> Int {
        guard id.first == "r", let separator = id.firstIndex(of: "-") else { return 0 }
        return Int(id[id.index(after: id.startIndex)..<separator]) ?? 0
    }

    private static func slotIndex(in id: String) -> Int {
        guard let separator = id.firstIndex(of: "-") else { return 0 }
        return Int(id[id.index(after: separator)...]) ?? 0
    }
}
