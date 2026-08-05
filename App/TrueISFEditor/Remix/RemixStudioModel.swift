import Foundation
import Combine
import CoreGraphics

/// Which parent slot a source/child fills.
enum ParentSlot: String, Codable, Equatable, Hashable { case a, b }

enum RemixVerificationContinuationResult: Equatable {
    case foregrounded(requestID: UUID, slot: ParentSlot)
    case restarted(RemixParentRequest)
    case unavailable
}

enum RemixPreviewSurface: Hashable {
    case canvas
    case inspector
}

struct RemixPreviewReservation: Hashable {
    let nodeID: String
    let surface: RemixPreviewSurface
}

struct RemixChildViewItem: Identifiable, Equatable {
    let run: RemixChildRunRecord
    let artifact: RemixNode?
    let preview: RemixPreviewState?
    var id: String { run.id }
}

/// Owns the Remix Studio state and drives the Module 1 generator. Parents are real lineage nodes
/// (external sources become round-0 "seed" nodes) so children record true parent ids from round 1.
@MainActor
final class RemixStudioModel: ObservableObject {
    typealias AutosaveScheduler = (@escaping @MainActor () -> Void) -> Void

    @Published private(set) var parentAID: String?
    @Published private(set) var parentBID: String?
    @Published var mode: RemixMode = .crossover { didSet { scheduleAutosave() } }
    @Published var steer: String = "" { didSet { scheduleAutosave() } }
    @Published var batchSize: Int = 5 { didSet { scheduleAutosave() } }
    @Published var maxLivePreviews: Int = 4
    @Published private(set) var currentRuns: [RemixChildRunRecord] = []
    @Published private(set) var batchHistory: [RemixBatchRecord] = []
    @Published private(set) var lineage = RemixLineage()
    @Published private(set) var isGenerating = false
    /// Live, merged terminal of every child's provider output, each line tagged by child id.
    @Published private(set) var transcript: [String] = []
    /// Lineage-tree selection; the right rail's action strip renders while non-nil.
    @Published var selectedNodeID: String? { didSet { scheduleAutosave() } }
    @Published var workspace = RemixWorkspaceState() { didSet { scheduleAutosave() } }
    @Published private(set) var activity = RemixActivityState.idle
    @Published private(set) var pendingParentRequest: RemixParentRequestSnapshot?
    @Published private(set) var parentLoadState = RemixParentLoadState.idle
    @Published private(set) var recoveryNotice: URL?
    @Published private(set) var previewStates: [String: RemixPreviewState] = [:]
    @Published private(set) var activeProviderChildIDs: Set<String> = []
    @Published private(set) var frozenPreviewIDs: Set<String> = []
    @Published private(set) var reduceMotionPlaybackEnabled = false
    /// One static frame per node id, captured at compile time — the tree's row swatches.
    @Published private(set) var snapshots: [String: CGImage] = [:]

    private static let settingsKey = "remixCrossoverSettings"
    @Published var crossoverSettings = RemixCrossoverSettings() {
        didSet {
            persistSettings()
            scheduleAutosave()
        }
    }

    private let generator: RemixGenerator
    private let sessionStore: RemixSessionStore
    private let defaults: UserDefaults
    private let autosaveScheduler: AutosaveScheduler
    private var generationTask: Task<Void, Never>?
    private var localRecoveryTask: Task<Void, Never>?
    private var activeBatchController: RemixBatchRunController?
    private var round = 0
    private var seedCounter = 0
    private var parentHistory: [(String?, String?)] = []
    private var isRestoring = false
    private var autosaveScheduled = false
    private var autosaveToken = 0
    private var sessionIdentity = UUID()
    private var activeParentRequestID: UUID?
    private var parentLoadTask: Task<Void, Never>?

    init(
        generator: RemixGenerator,
        sessionStore: RemixSessionStore? = nil,
        defaults: UserDefaults = .standard,
        autosaveScheduler: AutosaveScheduler? = nil
    ) {
        self.generator = generator
        self.defaults = defaults
        self.sessionStore = sessionStore ?? Self.productionSessionStore()
        self.autosaveScheduler = autosaveScheduler ?? Self.scheduleProductionAutosave
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(RemixCrossoverSettings.self, from: data) {
            self.crossoverSettings = decoded
        }
        restoreSession()
    }

    // MARK: derived

    var parentIDs: [String] { [parentAID, parentBID].compactMap { $0 } }
    var parentSources: [String] { parentIDs.compactMap { lineage.node($0)?.isfSource } }
    var canGenerate: Bool {
        guard !isGenerating, localRecoveryTask == nil else { return false }
        let needed = (mode == .crossover) ? 2 : 1
        return parentSources.count >= needed
    }
    /// Children of the current batch still awaiting a reply — for the terminal's "N generating" header.
    /// If this stays > 0 while the transcript goes quiet, generation is likely hung.
    var currentBatch: [RemixNode] {
        RemixBatchRecord(round: round, runs: currentRuns).nodes
    }
    var generatingCount: Int { currentRuns.filter { !$0.stage.isTerminal }.count }
    var runSummary: RemixRunSummary { RemixRunSummary(records: currentRuns) }
    var canStopGeneration: Bool {
        isGenerating && activeBatchController?.hasStoppableWork == true
    }
    var childViewItems: [RemixChildViewItem] {
        currentRuns.map { run in
            let artifact = run.artifactID.flatMap { lineage.node($0) }
            return RemixChildViewItem(
                run: run,
                artifact: artifact,
                preview: artifact.flatMap { previewStates[$0.id] }
            )
        }
    }

    // MARK: parents

    /// Set a parent from an external ISF source: creates a round-0 seed node and points the slot at it.
    /// `label` is the human display name for the tree (library entry name / "editor" / "pasted").
    func setParent(_ slot: ParentSlot, isf: String, label: String? = nil) {
        let id = "seed-\(seedCounter)"; seedCounter += 1
        // Round-0 seeds have no generation mode; .crossover is a placeholder value, not lineage fact.
        let node = RemixNode(id: id, isfSource: isf, parents: [], mode: .crossover,
                             steer: "", directive: "seed", round: 0, status: .compiled, label: label)
        lineage.insert(node)
        switch slot { case .a: parentAID = id; case .b: parentBID = id }
        scheduleAutosave()
    }

    /// Promote an existing lineage node (a child) to a parent slot — no new seed.
    func promoteToParent(_ slot: ParentSlot, nodeID: String) {
        switch slot { case .a: parentAID = nodeID; case .b: parentBID = nodeID }
        scheduleAutosave()
    }

    func clearParent(_ slot: ParentSlot) {
        switch slot { case .a: parentAID = nil; case .b: parentBID = nil }
        scheduleAutosave()
    }

    func loadParent(
        _ request: RemixParentRequest,
        from resolver: RemixParentResolver
    ) {
        parentLoadTask?.cancel()
        activeParentRequestID = request.id
        parentLoadState = .fetching(request)
        pendingParentRequest = Self.persistedParentRequest(request, phase: .fetching)
        persistSession()
        parentLoadTask = Task { [weak self] in
            await self?.performParentLoad(request, from: resolver)
        }
    }

    private func performParentLoad(
        _ request: RemixParentRequest,
        from resolver: RemixParentResolver
    ) async {
        do {
            let isf = try await resolver.resolve(request.spec) { [weak self] state in
                self?.receiveParentFetchState(state, requestID: request.id)
            }
            guard activeParentRequestID == request.id else { return }
            parentLoadState = parentLoadState.transitioning(
                to: .converting,
                requestID: request.id
            )
            pendingParentRequest = Self.persistedParentRequest(request, phase: .converting)
            persistSession()
            guard activeParentRequestID == request.id else { return }
            setParent(request.slot, isf: isf, label: Self.parentLabel(for: request.spec))
            parentLoadState = parentLoadState.transitioning(
                to: .succeeded,
                requestID: request.id
            )
            pendingParentRequest = nil
            activeParentRequestID = nil
            parentLoadTask = nil
            activity = .idle
            persistSession()
        } catch {
            guard activeParentRequestID == request.id else { return }
            parentLoadState = .failed(request, message: String(describing: error))
            pendingParentRequest = Self.persistedParentRequest(request, phase: .waitingForHuman)
            activeParentRequestID = nil
            parentLoadTask = nil
            persistSession()
        }
    }

    @discardableResult
    func cancelParentLoad() -> RemixParentFocusTarget? {
        guard let request = parentLoadState.request else { return nil }
        parentLoadTask?.cancel()
        parentLoadTask = nil
        activeParentRequestID = nil
        parentLoadState = .cancelled(request)
        pendingParentRequest = Self.persistedParentRequest(request, phase: .waitingForHuman)
        activity = .cancelled
        persistSession()
        return parentLoadState.focusTarget
    }

    @discardableResult
    func continueParentVerification(
        from resolver: RemixParentResolver
    ) -> RemixVerificationContinuationResult {
        guard let request = parentLoadState.request else { return .unavailable }
        if activeParentRequestID == request.id {
            guard resolver.foregroundVerification() else { return .unavailable }
            return .foregrounded(requestID: request.id, slot: request.slot)
        }
        loadParent(request, from: resolver)
        return .restarted(request)
    }

    // MARK: generation

    /// Start a round as an owned outer task. Stop closes only the controller's provider launch gate;
    /// the outer task remains alive until every stable slot reaches a terminal record.
    func startGeneration() {
        guard canGenerate, generationTask == nil else { return }
        generationTask = Task { [weak self] in
            await self?.generate()
            self?.generationTask = nil
        }
    }

    /// Stop provider launches without cancelling the outer scheduler or accepted local work.
    func cancelGeneration() {
        activeBatchController?.stop()
        let now = Date()
        for index in currentRuns.indices where currentRuns[index].stage == .queued {
            _ = currentRuns[index].transition(to: .cancelled, at: now)
        }
        activity = .cancelled
        persistSession()
    }

    func generate() async {
        guard canGenerate else { return }
        let generationIdentity = sessionIdentity
        parentHistory.append((parentAID, parentBID))
        round += 1
        let r = round
        let pids = parentIDs
        isGenerating = true
        activity = .generating(total: batchSize, completed: 0, lastEventAt: nil)
        transcript = []
        let pool = RemixDirectives.catalog.filter(crossoverSettings.enabledDirectives.contains)
        let directives = RemixDirectives.pick(batchSize, seed: r, from: pool)
        let queuedAt = Date()
        currentRuns = (0..<batchSize).map { slot in
            RemixChildRunRecord(
                id: "r\(r)-\(slot)",
                round: r,
                slot: slot,
                request: RemixGenerationRequestSnapshot(
                    parentIDs: pids,
                    parentSources: parentSources,
                    mode: mode,
                    steer: steer,
                    directive: directives[slot],
                    settings: crossoverSettings
                ),
                queuedAt: queuedAt
            )
        }
        batchHistory.append(RemixBatchRecord(round: r, runs: currentRuns))
        let controller = RemixBatchRunController(launchableChildIDs: currentRuns.map(\.id))
        activeBatchController = controller
        persistSession()
        await generator.generate(
            records: currentRuns,
            controller: controller,
            onUpdate: { [weak self] update in
                guard let self, self.sessionIdentity == generationIdentity else { return }
                self.applyPipelineUpdate(update)
                self.updateBatchRecord(round: r, runs: self.currentRuns)
                self.activity = .generating(
                    total: self.runSummary.totalCount,
                    completed: self.runSummary.terminalCount,
                    lastEventAt: self.runSummary.latestProviderActivity
                )
                self.persistSession()
            },
            onLog: { [weak self] id, line in
                Task { @MainActor in
                    guard let self, self.sessionIdentity == generationIdentity else { return }
                    self.appendLog(id, line)
                }
            }
        )
        guard sessionIdentity == generationIdentity else { return }
        activeBatchController = nil
        isGenerating = false
        let failed = currentRuns.filter { $0.stage == .failed }.count
        let cancelled = currentRuns.filter { $0.stage == .cancelled }.count
        if cancelled > 0 {
            activity = .cancelled
        } else if failed > 0 {
            activity = .partialFailure(total: currentRuns.count, failed: failed)
        } else {
            activity = .completed(failed: 0)
        }
        updateBatchRecord(round: r, runs: currentRuns)
        persistSession()
    }

    /// Retry one failed or interrupted slot from its captured request. An explicit steer override
    /// creates a new immutable snapshot by replacing only the steer field.
    func retryChild(id: String, steerOverride: String? = nil) async {
        guard !isGenerating,
              let batchIndex = batchHistory.lastIndex(where: {
                  $0.requestsByNodeID[id] != nil
              }),
              let storedRequest = batchHistory[batchIndex].requestsByNodeID[id],
              let currentIndex = currentRuns.firstIndex(where: { $0.id == id }),
              Self.isRetryable(currentRuns[currentIndex].stage)
        else {
            return
        }
        let request = RemixGenerationRequestSnapshot(
            parentIDs: storedRequest.parentIDs,
            parentSources: storedRequest.parentSources,
            mode: storedRequest.mode,
            steer: steerOverride ?? storedRequest.steer,
            directive: storedRequest.directive,
            settings: storedRequest.settings
        )

        let prior = currentRuns[currentIndex]
        currentRuns[currentIndex] = RemixChildRunRecord(
            id: prior.id,
            round: prior.round,
            slot: prior.slot,
            request: request,
            queuedAt: Date()
        )
        if let artifactID = prior.artifactID {
            previewStates.removeValue(forKey: artifactID)
        }
        isGenerating = true
        activity = .generating(total: 1, completed: 0, lastEventAt: nil)
        let controller = RemixBatchRunController(launchableChildIDs: [currentRuns[currentIndex].id])
        activeBatchController = controller
        persistSession()

        let generationIdentity = sessionIdentity
        await generator.generate(
            records: [currentRuns[currentIndex]],
            controller: controller,
            onUpdate: { [weak self] update in
                guard let self, self.sessionIdentity == generationIdentity else { return }
                self.applyPipelineUpdate(update)
                self.persistSession()
            },
            onLog: { [weak self] childID, line in
                Task { @MainActor in
                    guard let self, self.sessionIdentity == generationIdentity else { return }
                    self.appendLog(childID, line)
                }
            }
        )
        guard sessionIdentity == generationIdentity else { return }
        activeBatchController = nil
        isGenerating = false
        let durableRetry = currentRuns[currentIndex]
        batchHistory.append(RemixBatchRecord(round: durableRetry.round, runs: [durableRetry]))
        activity = .completed(failed: currentRuns[currentIndex].stage == .failed ? 1 : 0)
        persistSession()
    }

    func retryFailed() async {
        let ids = currentRuns.compactMap { run -> String? in
            run.stage == .failed ? run.id : nil
        }
        for id in ids {
            await retryChild(id: id)
        }
    }

    func retryInterruptedBatch() async {
        let ids = currentRuns.compactMap { run -> String? in
            run.stage == .interrupted ? run.id : nil
        }
        for id in ids {
            await retryChild(id: id)
        }
    }

    private func updateBatchRecord(round: Int, runs: [RemixChildRunRecord]) {
        guard let index = batchHistory.lastIndex(where: { $0.round == round }) else { return }
        batchHistory[index] = RemixBatchRecord(round: round, runs: runs)
    }

    private static func isRetryable(_ stage: RemixChildRunRecord.Stage) -> Bool {
        stage == .interrupted || stage == .failed || stage == .cancelled
    }

    /// The .generating placeholder cards for a round, with the same ids (`r{round}-{slot}`) and directives
    /// the generator will use — so each placeholder is replaced in place when its child lands.
    static func makePlaceholders(round: Int, size: Int, parents: [String], pool: [String],
                                 mode: RemixMode) -> [RemixNode] {
        let directives = RemixDirectives.pick(size, seed: round, from: pool)
        return (0..<size).map { slot in
            RemixNode(id: "r\(round)-\(slot)", isfSource: "", parents: parents, mode: mode,
                      steer: "", directive: directives[slot], round: round, status: .generating)
        }
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(crossoverSettings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    /// Monotonic count of transcript lines dropped from the front — lets the view build STABLE row
    /// ids (`dropped + offset`); raw enumeration offsets shift once the bound starts dropping.
    private(set) var transcriptDropped = 0

    /// Append one provider output line to the merged terminal, tagged by child id and memory-bounded.
    /// Raw stream-JSON is humanized first (N28) — internals never reach the user surface.
    func appendLog(_ id: String, _ line: String) {
        if let index = currentRuns.firstIndex(where: { $0.id == id }),
           !currentRuns[index].stage.isTerminal {
            currentRuns[index].lastEventAt = Date()
        }
        guard let display = AssistTranscriptFormatter.display(line) else { return }
        let before = transcript.count
        transcript.appendBounded("[\(id)] \(display)", max: 2000)
        transcriptDropped += before + 1 - transcript.count
    }

    func applyPipelineUpdate(_ update: RemixPipelineUpdate) {
        switch update {
        case .record(let record):
            if let index = currentRuns.firstIndex(where: { $0.id == record.id }) {
                guard !currentRuns[index].stage.isTerminal else { return }
                currentRuns[index] = record
            } else {
                guard batchHistory.isEmpty else { return }
                currentRuns.append(record)
            }
            if record.stage.isTerminal {
                activeProviderChildIDs.remove(record.id)
            }
        case .artifact(let artifact, let record):
            if let index = currentRuns.firstIndex(where: { $0.id == record.id }) {
                guard !currentRuns[index].stage.isTerminal else { return }
                currentRuns[index] = record
            } else {
                guard batchHistory.isEmpty else { return }
                currentRuns.append(record)
            }
            activeProviderChildIDs.remove(record.id)
            lineage.insert(artifact)
            previewStates[artifact.id] = previewStates[artifact.id] ?? RemixPreviewState(
                stage: .pending,
                attempt: 0,
                diagnostic: nil,
                updatedAt: Date()
            )
        case .processLiveness(let childID, let isAlive):
            guard let run = currentRuns.first(where: { $0.id == childID }),
                  !run.stage.isTerminal
            else {
                activeProviderChildIDs.remove(childID)
                return
            }
            if isAlive {
                activeProviderChildIDs.insert(childID)
            } else {
                activeProviderChildIDs.remove(childID)
            }
        }
    }

    func markPreviewAvailable(artifactID: String) {
        guard lineage.node(artifactID) != nil else { return }
        var state = previewStates[artifactID] ?? RemixPreviewState(
            stage: .pending,
            attempt: 0,
            diagnostic: nil,
            updatedAt: Date()
        )
        state.stage = .available
        state.diagnostic = nil
        state.updatedAt = Date()
        previewStates[artifactID] = state
        persistSession()
    }

    func markPreviewFailed(artifactID: String, diagnostic: String) {
        guard lineage.node(artifactID) != nil else { return }
        var state = previewStates[artifactID] ?? RemixPreviewState(
            stage: .pending,
            attempt: 0,
            diagnostic: nil,
            updatedAt: Date()
        )
        state.stage = .failed
        state.diagnostic = RemixPreviewState.boundedDiagnostic(diagnostic)
        state.updatedAt = Date()
        previewStates[artifactID] = state
        persistSession()
    }

    func retryPreview(artifactID: String) {
        guard var state = previewStates[artifactID] else { return }
        state.stage = .pending
        state.attempt += 1
        state.diagnostic = nil
        state.updatedAt = Date()
        previewStates[artifactID] = state
        persistSession()
    }

    func compileDiagnostic(for id: String) -> String? {
        if let current = currentRuns.first(where: { $0.id == id }) {
            return current.failureBoundary == .compile ? current.compileDiagnostic : nil
        }
        return batchHistory.reversed()
            .lazy
            .flatMap(\.runs)
            .first(where: { $0.id == id && $0.failureBoundary == .compile })?
            .compileDiagnostic
    }

    func compileSalvageActions(for id: String) -> [RemixCompileSalvageAction] {
        guard compileDiagnostic(for: id) != nil else { return [] }
        return [
            .viewCompileSummary,
            .openSourceInEditorToFix,
            .copyDiagnostic,
            .retryThisChild,
        ]
    }

    func compileSummary(for id: String) -> String? {
        guard let diagnostic = compileDiagnostic(for: id) else { return nil }
        return "Compile summary for \(id)\n\(diagnostic)"
    }

    func previewFailureActions(for id: String) -> [RemixPreviewFailureAction] {
        guard previewStates[id]?.stage == .failed else { return [] }
        return [.retryPreview, .openInEditor]
    }

    // MARK: live-preview cap (performance)

    /// Strict live-renderer budget. Reservations identify both the node and its UI surface because
    /// the canvas and inspector can host separate Metal controllers for the same node.
    func livePreviewReservations(
        reduceMotion: Bool = false
    ) -> Set<RemixPreviewReservation> {
        guard !workspace.previewsPaused,
              (!reduceMotion || reduceMotionPlaybackEnabled),
              maxLivePreviews > 0
        else {
            return []
        }
        var eligible = currentBatch.filter {
            $0.status == .compiled
                && !frozenPreviewIDs.contains($0.id)
                && previewStates[$0.id]?.stage != .failed
        }
        if let selectedNodeID,
           !eligible.contains(where: { $0.id == selectedNodeID }),
           let selected = lineage.node(selectedNodeID),
           selected.status == .compiled,
           previewStates[selectedNodeID]?.stage != .failed,
           !frozenPreviewIDs.contains(selectedNodeID) {
            eligible.append(selected)
        }
        let eligibleIDs = Set(eligible.map(\.id))
        let canvasIDs = Set(currentBatch.map(\.id))
        var priority: [RemixPreviewReservation] = []
        func append(_ id: String?, on surface: RemixPreviewSurface) {
            guard let id, eligibleIDs.contains(id) else { return }
            if surface == .canvas, !canvasIDs.contains(id) { return }
            let reservation = RemixPreviewReservation(nodeID: id, surface: surface)
            guard !priority.contains(reservation) else { return }
            priority.append(reservation)
        }
        append(workspace.heroChildID, on: .canvas)
        workspace.comparedChildIDs.forEach { append($0, on: .canvas) }
        append(workspace.focusedChildID, on: .canvas)
        append(selectedNodeID, on: .canvas)
        append(selectedNodeID, on: .inspector)
        eligible.reversed()
            .filter { lineage.isFavorite($0.id) }
            .forEach { append($0.id, on: .canvas) }
        eligible.reversed().forEach { append($0.id, on: .canvas) }
        return Set(priority.prefix(maxLivePreviews))
    }

    func livePreviewIDs(reduceMotion: Bool = false) -> Set<String> {
        Set(livePreviewReservations(reduceMotion: reduceMotion).map(\.nodeID))
    }

    func shouldAnimate(_ id: String, reduceMotion: Bool = false) -> Bool {
        livePreviewIDs(reduceMotion: reduceMotion).contains(id)
    }

    func shouldAnimate(
        _ id: String,
        on surface: RemixPreviewSurface,
        reduceMotion: Bool = false
    ) -> Bool {
        livePreviewReservations(reduceMotion: reduceMotion).contains(
            RemixPreviewReservation(nodeID: id, surface: surface)
        )
    }

    func setPreviewFrozen(_ frozen: Bool, for id: String) {
        if frozen {
            frozenPreviewIDs.insert(id)
        } else {
            frozenPreviewIDs.remove(id)
        }
    }

    func explicitlyPlayPreviews() {
        reduceMotionPlaybackEnabled = true
        workspace.previewsPaused = false
    }

    // MARK: selection

    func routeCanvasCommand(_ command: RemixKeyboardCommand, columns: Int) {
        let childIDs = currentBatch.map(\.id)
        switch command {
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            workspace.moveFocus(command, columns: columns, childIDs: childIDs)
        case .toggleComparison:
            if let id = focusedReadyArtifactID { workspace.toggleComparison(id) }
        case .favorite:
            if let id = focusedReadyArtifactID { toggleFavorite(id) }
        case .hero:
            if let id = focusedReadyArtifactID { workspace.showHero(id) }
        case .promoteA:
            if let id = focusedReadyArtifactID { promoteToParent(.a, nodeID: id) }
        case .promoteB:
            if let id = focusedReadyArtifactID { promoteToParent(.b, nodeID: id) }
        case .exitCanvasMode:
            workspace.showGrid()
        }
    }

    var focusedReadyArtifactID: String? {
        guard let focusedID = workspace.focusedChildID,
              let run = currentRuns.first(where: { $0.id == focusedID }),
              run.stage == .ready,
              let artifactID = run.artifactID,
              lineage.node(artifactID) != nil
        else {
            return nil
        }
        return artifactID
    }

    func toggleFavorite(_ id: String) {
        lineage.toggleFavorite(id)
        scheduleAutosave()
    }

    func storeSnapshot(id: String, image: CGImage) { snapshots[id] = image }

    func treeRows(collapsed: Set<String>, favoritesOnly: Bool) -> [RemixTreeRow] {
        RemixTreeBuilder.flatten(lineage, collapsed: collapsed, favoritesOnly: favoritesOnly)
    }

    var canUndoParentChange: Bool {
        parentHistory.count >= 2
    }

    var undoParentChangeReason: String? {
        canUndoParentChange ? nil : "No prior parent configuration is available."
    }

    /// Restores only the parent ids used by the prior round. Lineage, favorites, batches,
    /// activity, selection, diagnostics, and snapshots remain untouched.
    func undoParentChange() {
        guard canUndoParentChange else { return }
        parentHistory.removeLast()
        (parentAID, parentBID) = parentHistory[parentHistory.count - 1]
        scheduleAutosave()
    }

    // MARK: session persistence

    func restoreSession() {
        isRestoring = true
        defer { isRestoring = false }
        do {
            switch try sessionStore.load() {
            case .noSession:
                break
            case .corruptPayload(let quarantinedURL):
                recoveryNotice = quarantinedURL
            case .session(let session):
                round = session.round
                seedCounter = session.seedCounter
                parentAID = session.parentAID
                parentBID = session.parentBID
                parentHistory = session.parentHistory.map { ($0.parentAID, $0.parentBID) }
                mode = session.mode
                steer = session.steer
                batchSize = session.batchSize
                currentRuns = session.currentRuns
                batchHistory = session.batchHistory
                let artifactIDs = Set(
                    (currentRuns + batchHistory.flatMap(\.runs))
                        .filter { $0.stage == .ready }
                        .compactMap(\.artifactID)
                )
                lineage = session.lineage.retainingArtifacts(withIDs: artifactIDs)
                workspace = session.workspace
                selectedNodeID = session.selectedLineageNodeID
                crossoverSettings = session.crossoverSettings
                activity = Self.restoredActivity(session.activity)
                pendingParentRequest = Self.restoredParentRequest(session.pendingParentRequest)
                if let pendingParentRequest,
                   let request = RemixParentRequest(snapshot: pendingParentRequest) {
                    parentLoadState = .waitingForHuman(request)
                } else {
                    parentLoadState = .idle
                }
                transcript = session.transcript
                previewStates = session.previewStates
                activeProviderChildIDs = []
                normalizeRestoredRuns()
                initializeMissingPreviewStates()
                isGenerating = false
                scheduleLocalRecovery()
            }
        } catch {
            // The store already quarantines malformed payloads. Other I/O failures leave the
            // in-memory defaults intact so the studio remains usable.
        }
    }

    private func normalizeRestoredRuns() {
        let now = Date()
        for index in currentRuns.indices {
            let stage = currentRuns[index].stage
            switch stage {
            case .queued, .starting, .thinking, .receiving, .retrying:
                currentRuns[index].stage = .interrupted
                currentRuns[index].lastEventAt = now
                currentRuns[index].terminalAt = now
            case .extracting, .compiling:
                guard let candidate = currentRuns[index].candidateSource,
                      case .success = RemixResponseParser.extractCandidate(candidate)
                else {
                    currentRuns[index].stage = .interrupted
                    currentRuns[index].lastEventAt = now
                    currentRuns[index].terminalAt = now
                    continue
                }
                currentRuns[index].terminalAt = nil
            case .ready, .failed, .cancelled, .interrupted:
                break
            }
        }
    }

    private func initializeMissingPreviewStates() {
        let restoredRuns = currentRuns + batchHistory.flatMap(\.runs)
        for run in restoredRuns where run.stage == .ready {
            guard let artifactID = run.artifactID,
                  lineage.node(artifactID) != nil,
                  previewStates[artifactID] == nil
            else {
                continue
            }
            previewStates[artifactID] = RemixPreviewState(
                stage: .pending,
                attempt: 0,
                diagnostic: nil,
                updatedAt: Date()
            )
        }
    }

    private func scheduleLocalRecovery() {
        let recoverable = currentRuns.filter {
            ($0.stage == .extracting || $0.stage == .compiling) && $0.candidateSource != nil
        }
        guard !recoverable.isEmpty else { return }
        let recoveryIdentity = sessionIdentity
        localRecoveryTask = Task { [weak self] in
            guard let self else { return }
            for record in recoverable {
                guard self.sessionIdentity == recoveryIdentity else { return }
                await self.generator.resumeLocal(record: record) { [weak self] update in
                    guard let self, self.sessionIdentity == recoveryIdentity else { return }
                    self.applyPipelineUpdate(update)
                }
            }
            guard self.sessionIdentity == recoveryIdentity else { return }
            self.updateBatchRecord(round: self.round, runs: self.currentRuns)
            self.localRecoveryTask = nil
            self.persistSession()
        }
    }

    func persistSession() {
        guard !isRestoring else { return }
        autosaveScheduled = false
        autosaveToken += 1
        let session = RemixSession(
            round: round,
            seedCounter: seedCounter,
            parentAID: parentAID,
            parentBID: parentBID,
            parentHistory: parentHistory.map {
                RemixParentConfiguration(parentAID: $0.0, parentBID: $0.1)
            },
            mode: mode,
            steer: steer,
            batchSize: batchSize,
            currentRuns: currentRuns,
            batchHistory: batchHistory,
            lineage: lineage,
            workspace: workspace,
            selectedLineageNodeID: selectedNodeID,
            crossoverSettings: crossoverSettings,
            activity: activity,
            pendingParentRequest: pendingParentRequest,
            transcript: transcript,
            previewStates: previewStates
        )
        try? sessionStore.save(session)
    }

    func startNewSession() {
        generationTask?.cancel()
        activeBatchController?.stop()
        activeBatchController = nil
        localRecoveryTask?.cancel()
        localRecoveryTask = nil
        activeParentRequestID = nil
        parentLoadTask?.cancel()
        parentLoadTask = nil
        sessionIdentity = UUID()
        autosaveScheduled = false
        isRestoring = true
        parentAID = nil
        parentBID = nil
        mode = .crossover
        steer = ""
        batchSize = 5
        currentRuns = []
        batchHistory = []
        lineage = RemixLineage()
        isGenerating = false
        transcript = []
        selectedNodeID = nil
        workspace = RemixWorkspaceState()
        activity = .idle
        pendingParentRequest = nil
        parentLoadState = .idle
        recoveryNotice = nil
        previewStates = [:]
        activeProviderChildIDs = []
        snapshots = [:]
        round = 0
        seedCounter = 0
        parentHistory = []
        transcriptDropped = 0
        isRestoring = false
        persistSession()
    }

    private func scheduleAutosave() {
        guard !isRestoring, !autosaveScheduled else { return }
        autosaveScheduled = true
        autosaveToken += 1
        let scheduledToken = autosaveToken
        autosaveScheduler { [weak self] in
            guard let self, self.autosaveToken == scheduledToken else { return }
            self.persistSession()
        }
    }

    private static func scheduleProductionAutosave(
        _ action: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private static func restoredParentRequest(
        _ request: RemixParentRequestSnapshot?
    ) -> RemixParentRequestSnapshot? {
        guard let request else { return nil }
        switch request.phase {
        case .fetching, .resuming, .converting:
            return RemixParentRequestSnapshot(
                id: request.id,
                slot: request.slot,
                source: request.source,
                displayInput: request.displayInput,
                phase: .waitingForHuman
            )
        case .verificationRequired, .waitingForHuman:
            return request
        }
    }

    private func receiveParentFetchState(
        _ state: WebKitShaderFetcher.State,
        requestID: UUID
    ) {
        guard activeParentRequestID == requestID,
              let request = parentLoadState.request
        else {
            return
        }
        switch state {
        case .loading:
            break
        case .verificationRequired:
            parentLoadState = parentLoadState.transitioning(
                to: .verificationRequired,
                requestID: requestID
            )
            activity = .verificationRequired(slot: request.slot, requestID: requestID)
            pendingParentRequest = request.snapshot(phase: .verificationRequired)
            parentLoadState = parentLoadState.transitioning(
                to: .waitingForHuman,
                requestID: requestID
            )
            pendingParentRequest = request.snapshot(phase: .waitingForHuman)
        case .cleared:
            parentLoadState = parentLoadState.transitioning(to: .cleared, requestID: requestID)
            if case .resuming = parentLoadState {
                activity = .resuming(slot: request.slot, requestID: requestID)
                pendingParentRequest = request.snapshot(phase: .resuming)
            }
        case .failed(let message):
            parentLoadState = parentLoadState.transitioning(
                to: .failed(message),
                requestID: requestID
            )
        }
        persistSession()
    }

    private static func parentLabel(for spec: ParentSpec) -> String {
        switch spec {
        case .pastedISF:
            return "pasted"
        case .libraryFile(let url):
            return url.deletingPathExtension().lastPathComponent
        case .shadertoyLink:
            return "shadertoy"
        case .currentEditor:
            return "editor"
        }
    }

    private static func persistedParentRequest(
        _ request: RemixParentRequest,
        phase: RemixParentRequestPhase
    ) -> RemixParentRequestSnapshot? {
        guard case .shadertoyLink = request.spec else { return nil }
        return request.snapshot(phase: phase)
    }

    private static func restoredActivity(_ activity: RemixActivityState) -> RemixActivityState {
        switch activity {
        case .generating, .quiet, .resuming:
            return .interrupted
        default:
            return activity
        }
    }

    private static func productionSessionStore() -> RemixSessionStore {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrueISFEditor/RemixStudio", isDirectory: true)
        return RemixSessionStore(fileURL: directory.appendingPathComponent("session.json"))
    }
}
