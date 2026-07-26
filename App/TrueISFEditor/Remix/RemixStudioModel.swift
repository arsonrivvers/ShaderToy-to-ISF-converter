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
    @Published private(set) var currentBatch: [RemixNode] = []
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
    @Published private(set) var compileDiagnosticsByNodeID: [String: String] = [:]
    @Published private(set) var previewFailuresByNodeID: [String: String] = [:]
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
    private var round = 0
    private var seedCounter = 0
    private var history: [(String?, String?)] = []   // parent (A,B) configs for step-back
    private var isRestoring = false
    private var autosaveScheduled = false
    private var autosaveToken = 0
    private var sessionIdentity = UUID()
    private var activeGenerationID: UUID?
    private var cancelledGenerationIDs: Set<UUID> = []
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
        guard !isGenerating else { return false }
        let needed = (mode == .crossover) ? 2 : 1
        return parentSources.count >= needed
    }
    /// Children of the current batch still awaiting a reply — for the terminal's "N generating" header.
    /// If this stays > 0 while the transcript goes quiet, generation is likely hung.
    var generatingCount: Int { currentBatch.filter { $0.status == .generating }.count }

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

    /// Start a round as an owned, cancellable task so the UI can stop it. Cancelling the task
    /// propagates through the generator's task group to terminate every in-flight provider CLI.
    func startGeneration() {
        guard canGenerate, generationTask == nil else { return }
        generationTask = Task { [weak self] in
            await self?.generate()
            self?.generationTask = nil
        }
    }

    /// Stop an in-flight batch. Children that were mid-generation resolve as `.failed("cancelled")`.
    func cancelGeneration() {
        if let activeGenerationID {
            cancelledGenerationIDs.insert(activeGenerationID)
        }
        generationTask?.cancel()
        activity = .cancelled
        persistSession()
    }

    func generate() async {
        guard canGenerate, !Task.isCancelled else { return }
        let generationIdentity = sessionIdentity
        let generationID = UUID()
        activeGenerationID = generationID
        history.append((parentAID, parentBID))
        round += 1
        let r = round
        let pids = parentIDs
        isGenerating = true
        activity = .generating(total: batchSize, completed: 0, lastEventAt: nil)
        transcript = []
        // Seed the gallery with .generating placeholders up front so cards (⚙) and the "N generating"
        // header appear immediately — otherwise nothing shows until a child returns (~37s+ each).
        let pool = RemixDirectives.catalog.filter(crossoverSettings.enabledDirectives.contains)
        currentBatch = Self.makePlaceholders(round: r, size: batchSize, parents: pids, pool: pool,
                                             mode: mode)
        let requestSnapshots = Dictionary(
            uniqueKeysWithValues: currentBatch.map { placeholder in
                (
                    placeholder.id,
                    RemixGenerationRequestSnapshot(
                        parentIDs: pids,
                        parentSources: parentSources,
                        mode: mode,
                        steer: steer,
                        directive: placeholder.directive,
                        settings: crossoverSettings
                    )
                )
            }
        )
        batchHistory.append(
            RemixBatchRecord(
                round: r,
                nodes: currentBatch,
                requestsByNodeID: requestSnapshots
            )
        )
        persistSession()
        await generator.generate(
            parents: parentSources, mode: mode, steer: steer, batchSize: batchSize, round: r,
            settings: crossoverSettings, pool: pool,
            onChild: { [weak self] node in
                guard let self, self.sessionIdentity == generationIdentity else { return }
                var n = node
                n.parents = pids             // record true parent ids in the lineage graph
                if let i = self.currentBatch.firstIndex(where: { $0.id == n.id }) {
                    self.currentBatch[i] = n // replace the placeholder in place
                } else {
                    self.currentBatch.append(n)
                }
                self.lineage.insert(n)
                self.updateBatchRecord(round: r, nodes: self.currentBatch)
                let completed = self.currentBatch.filter { $0.status != .generating }.count
                if !self.cancelledGenerationIDs.contains(generationID) {
                    self.activity = .generating(
                        total: self.currentBatch.count,
                        completed: completed,
                        lastEventAt: Date()
                    )
                }
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
        isGenerating = false
        activeGenerationID = nil
        let wasCancelled = cancelledGenerationIDs.remove(generationID) != nil
        let failed = currentBatch.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
        if wasCancelled {
            activity = .cancelled
        } else if failed > 0 {
            activity = .partialFailure(total: currentBatch.count, failed: failed)
        } else {
            activity = .completed(failed: 0)
        }
        updateBatchRecord(round: r, nodes: currentBatch)
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
              let currentIndex = currentBatch.firstIndex(where: { $0.id == id }),
              Self.isRetryable(currentBatch[currentIndex].status)
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

        var placeholder = currentBatch[currentIndex]
        placeholder.status = .generating
        currentBatch[currentIndex] = placeholder
        lineage.insert(placeholder)
        compileDiagnosticsByNodeID.removeValue(forKey: id)
        previewFailuresByNodeID.removeValue(forKey: id)
        isGenerating = true
        activity = .generating(total: 1, completed: 0, lastEventAt: nil)
        persistSession()

        let generationIdentity = sessionIdentity
        let child = await generator.generateChild(
            id: id,
            request: request,
            onLog: { [weak self] childID, line in
                Task { @MainActor in
                    guard let self, self.sessionIdentity == generationIdentity else { return }
                    self.appendLog(childID, line)
                }
            }
        )
        guard sessionIdentity == generationIdentity else { return }
        replaceRetriedNode(child, batchIndex: batchIndex)
        isGenerating = false
        activity = .completed(failed: Self.isFailed(child.status) ? 1 : 0)
        persistSession()
    }

    func retryFailed() async {
        let ids = currentBatch.compactMap { node -> String? in
            Self.isFailed(node.status) ? node.id : nil
        }
        for id in ids {
            await retryChild(id: id)
        }
    }

    func retryInterruptedBatch() async {
        let ids = currentBatch.compactMap { node -> String? in
            node.status == .interrupted ? node.id : nil
        }
        for id in ids {
            await retryChild(id: id)
        }
    }

    private func replaceRetriedNode(_ child: RemixNode, batchIndex: Int) {
        if let index = currentBatch.firstIndex(where: { $0.id == child.id }) {
            currentBatch[index] = child
        }
        lineage.insert(child)
        var nodes = batchHistory[batchIndex].nodes
        if let index = nodes.firstIndex(where: { $0.id == child.id }) {
            nodes[index] = child
        }
        batchHistory[batchIndex] = RemixBatchRecord(
            round: batchHistory[batchIndex].round,
            nodes: nodes,
            requestsByNodeID: batchHistory[batchIndex].requestsByNodeID
        )
    }

    private func updateBatchRecord(round: Int, nodes: [RemixNode]) {
        guard let index = batchHistory.lastIndex(where: { $0.round == round }) else { return }
        batchHistory[index] = RemixBatchRecord(
            round: round,
            nodes: nodes,
            requestsByNodeID: batchHistory[index].requestsByNodeID
        )
    }

    private static func isRetryable(_ status: RemixNode.Status) -> Bool {
        status == .interrupted || isFailed(status)
    }

    private static func isFailed(_ status: RemixNode.Status) -> Bool {
        if case .failed = status { return true }
        return false
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
        guard let display = AssistTranscriptFormatter.display(line) else { return }
        let before = transcript.count
        transcript.appendBounded("[\(id)] \(display)", max: 2000)
        transcriptDropped += before + 1 - transcript.count
    }

    /// Card preview reports the real compile outcome; update status in the batch and the lineage.
    func markCompileResult(id: String, valid: Bool, error: String?) {
        guard var node = lineage.node(id) else { return }
        let diagnostic = error ?? "compile failed"
        node.status = valid ? .compiled : .failed(diagnostic)
        if valid {
            compileDiagnosticsByNodeID.removeValue(forKey: id)
        } else {
            compileDiagnosticsByNodeID[id] = diagnostic
        }
        previewFailuresByNodeID.removeValue(forKey: id)
        lineage.insert(node)
        if let i = currentBatch.firstIndex(where: { $0.id == id }) { currentBatch[i] = node }
        for batchIndex in batchHistory.indices {
            if let nodeIndex = batchHistory[batchIndex].nodes.firstIndex(where: { $0.id == id }) {
                batchHistory[batchIndex].nodes[nodeIndex] = node
            }
        }
        if !valid {
            activity = .childFailed(id: id, message: "Compile failed: \(diagnostic)")
        }
        persistSession()
    }

    func compileDiagnostic(for id: String) -> String? {
        guard let node = lineage.node(id),
              case .failed = node.status
        else {
            return nil
        }
        return compileDiagnosticsByNodeID[id]
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

    func markPreviewFailure(id: String, message: String) {
        guard lineage.node(id)?.status == .compiled else { return }
        previewFailuresByNodeID[id] = message
    }

    func previewFailureActions(for id: String) -> [RemixPreviewFailureAction] {
        guard previewFailuresByNodeID[id] != nil else { return [] }
        return [.retryPreview, .openInEditor]
    }

    /// Requests a renderer-only retry by clearing its failure latch. The card observes this
    /// published dictionary and rebuilds its preview without touching provider or generation state.
    func retryPreview(id: String) {
        previewFailuresByNodeID.removeValue(forKey: id)
    }

    // MARK: live-preview cap (performance)

    /// Strict live-preview budget. User context is prioritized before favorites and recency;
    /// failed and explicitly frozen children are never scheduled.
    func livePreviewIDs(reduceMotion: Bool = false) -> Set<String> {
        guard !workspace.previewsPaused,
              (!reduceMotion || reduceMotionPlaybackEnabled),
              maxLivePreviews > 0
        else {
            return []
        }
        let eligible = currentBatch.filter {
            $0.status == .compiled && !frozenPreviewIDs.contains($0.id)
        }
        let eligibleIDs = Set(eligible.map(\.id))
        var priority: [String] = []
        func append(_ id: String?) {
            guard let id, eligibleIDs.contains(id), !priority.contains(id) else { return }
            priority.append(id)
        }
        append(workspace.heroChildID)
        workspace.comparedChildIDs.forEach { append($0) }
        append(workspace.focusedChildID)
        eligible.reversed()
            .filter { lineage.isFavorite($0.id) }
            .forEach { append($0.id) }
        eligible.reversed().forEach { append($0.id) }
        return Set(priority.prefix(maxLivePreviews))
    }

    func shouldAnimate(_ id: String, reduceMotion: Bool = false) -> Bool {
        livePreviewIDs(reduceMotion: reduceMotion).contains(id)
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
            if let id = workspace.focusedChildID { workspace.toggleComparison(id) }
        case .favorite:
            if let id = workspace.focusedChildID { toggleFavorite(id) }
        case .hero:
            if let id = workspace.focusedChildID { workspace.showHero(id) }
        case .promoteA:
            if let id = workspace.focusedChildID { promoteToParent(.a, nodeID: id) }
        case .promoteB:
            if let id = workspace.focusedChildID { promoteToParent(.b, nodeID: id) }
        case .exitCanvasMode:
            workspace.showGrid()
        }
    }

    func toggleFavorite(_ id: String) {
        lineage.toggleFavorite(id)
        scheduleAutosave()
    }

    func storeSnapshot(id: String, image: CGImage) { snapshots[id] = image }

    func treeRows(collapsed: Set<String>, favoritesOnly: Bool) -> [RemixTreeRow] {
        RemixTreeBuilder.flatten(lineage, collapsed: collapsed, favoritesOnly: favoritesOnly)
    }

    /// Restore the parent config from the previous round. `generate()` records the config it used
    /// before each round, so the top of `history` is the current round's config — discard it and
    /// restore the one beneath. No-op until at least two rounds have run.
    func stepBack() {
        guard history.count >= 2 else { return }
        history.removeLast()                       // drop the current round's config
        (parentAID, parentBID) = history[history.count - 1]
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
                history = session.parentHistory.map { ($0.parentAID, $0.parentBID) }
                mode = session.mode
                steer = session.steer
                batchSize = session.batchSize
                currentBatch = session.currentBatch
                batchHistory = session.batchHistory
                lineage = session.lineage
                workspace = session.workspace
                selectedNodeID = session.selectedLineageNodeID
                crossoverSettings = session.crossoverSettings
                activity = Self.restoredActivity(session.activity)
                compileDiagnosticsByNodeID = session.compileDiagnosticsByNodeID ?? [:]
                pendingParentRequest = Self.restoredParentRequest(session.pendingParentRequest)
                if let pendingParentRequest,
                   let request = RemixParentRequest(snapshot: pendingParentRequest) {
                    parentLoadState = .waitingForHuman(request)
                } else {
                    parentLoadState = .idle
                }
                transcript = session.transcript
                isGenerating = false
            }
        } catch {
            // The store already quarantines malformed payloads. Other I/O failures leave the
            // in-memory defaults intact so the studio remains usable.
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
            parentHistory: history.map {
                RemixParentConfiguration(parentAID: $0.0, parentBID: $0.1)
            },
            mode: mode,
            steer: steer,
            batchSize: batchSize,
            currentBatch: currentBatch,
            batchHistory: batchHistory,
            lineage: lineage,
            workspace: workspace,
            selectedLineageNodeID: selectedNodeID,
            crossoverSettings: crossoverSettings,
            activity: activity,
            compileDiagnosticsByNodeID: compileDiagnosticsByNodeID,
            pendingParentRequest: pendingParentRequest,
            transcript: transcript
        )
        try? sessionStore.save(session)
    }

    func startNewSession() {
        generationTask?.cancel()
        activeParentRequestID = nil
        parentLoadTask?.cancel()
        parentLoadTask = nil
        sessionIdentity = UUID()
        activeGenerationID = nil
        cancelledGenerationIDs = []
        autosaveScheduled = false
        isRestoring = true
        parentAID = nil
        parentBID = nil
        mode = .crossover
        steer = ""
        batchSize = 5
        currentBatch = []
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
        compileDiagnosticsByNodeID = [:]
        previewFailuresByNodeID = [:]
        snapshots = [:]
        round = 0
        seedCounter = 0
        history = []
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
