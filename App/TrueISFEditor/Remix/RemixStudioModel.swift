import Foundation
import Combine
import CoreGraphics

/// Which parent slot a source/child fills.
enum ParentSlot { case a, b }

/// Owns the Remix Studio state and drives the Module 1 generator. Parents are real lineage nodes
/// (external sources become round-0 "seed" nodes) so children record true parent ids from round 1.
@MainActor
final class RemixStudioModel: ObservableObject {
    @Published private(set) var parentAID: String?
    @Published private(set) var parentBID: String?
    @Published var mode: RemixMode = .crossover
    @Published var steer: String = ""
    @Published var batchSize: Int = 5
    @Published var maxLivePreviews: Int = 4
    @Published private(set) var currentBatch: [RemixNode] = []
    @Published private(set) var lineage = RemixLineage()
    @Published private(set) var isGenerating = false
    /// Live, merged terminal of every child's provider output, each line tagged by child id.
    @Published private(set) var transcript: [String] = []
    /// Lineage-tree selection; the right rail's action strip renders while non-nil.
    @Published var selectedNodeID: String?
    /// One static frame per node id, captured at compile time — the tree's row swatches.
    @Published private(set) var snapshots: [String: CGImage] = [:]

    private static let settingsKey = "remixCrossoverSettings"
    @Published var crossoverSettings = RemixCrossoverSettings() { didSet { persistSettings() } }

    private let generator: RemixGenerator
    private var generationTask: Task<Void, Never>?
    private var round = 0
    private var seedCounter = 0
    private var history: [(String?, String?)] = []   // parent (A,B) configs for step-back

    init(generator: RemixGenerator) {
        self.generator = generator
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(RemixCrossoverSettings.self, from: data) {
            self.crossoverSettings = decoded
        }
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
    }

    /// Promote an existing lineage node (a child) to a parent slot — no new seed.
    func promoteToParent(_ slot: ParentSlot, nodeID: String) {
        switch slot { case .a: parentAID = nodeID; case .b: parentBID = nodeID }
    }

    func clearParent(_ slot: ParentSlot) {
        switch slot { case .a: parentAID = nil; case .b: parentBID = nil }
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
    func cancelGeneration() { generationTask?.cancel() }

    func generate() async {
        guard canGenerate else { return }
        history.append((parentAID, parentBID))
        round += 1
        let r = round
        let pids = parentIDs
        isGenerating = true
        transcript = []
        // Seed the gallery with .generating placeholders up front so cards (⚙) and the "N generating"
        // header appear immediately — otherwise nothing shows until a child returns (~37s+ each).
        let pool = RemixDirectives.catalog.filter(crossoverSettings.enabledDirectives.contains)
        currentBatch = Self.makePlaceholders(round: r, size: batchSize, parents: pids, pool: pool,
                                             mode: mode)
        await generator.generate(
            parents: parentSources, mode: mode, steer: steer, batchSize: batchSize, round: r,
            settings: crossoverSettings, pool: pool,
            onChild: { [weak self] node in
                guard let self else { return }
                var n = node
                n.parents = pids             // record true parent ids in the lineage graph
                if let i = self.currentBatch.firstIndex(where: { $0.id == n.id }) {
                    self.currentBatch[i] = n // replace the placeholder in place
                } else {
                    self.currentBatch.append(n)
                }
                self.lineage.insert(n)
            },
            onLog: { [weak self] id, line in
                Task { @MainActor in self?.appendLog(id, line) }
            }
        )
        isGenerating = false
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
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    /// Monotonic count of transcript lines dropped from the front — lets the view build STABLE row
    /// ids (`dropped + offset`); raw enumeration offsets shift once the bound starts dropping.
    private(set) var transcriptDropped = 0

    /// Append one provider output line to the merged terminal, tagged by child id and memory-bounded.
    func appendLog(_ id: String, _ line: String) {
        let before = transcript.count
        transcript.appendBounded("[\(id)] \(line)", max: 2000)
        transcriptDropped += before + 1 - transcript.count
    }

    /// Card preview reports the real compile outcome; update status in the batch and the lineage.
    func markCompileResult(id: String, valid: Bool, error: String?) {
        guard var node = lineage.node(id) else { return }
        node.status = valid ? .compiled : .failed(error ?? "compile failed")
        lineage.insert(node)
        if let i = currentBatch.firstIndex(where: { $0.id == id }) { currentBatch[i] = node }
    }

    // MARK: live-preview cap (performance)

    /// Favorites always animate; remaining slots up to `maxLivePreviews` go to the most-recent
    /// compiled, non-favorite children. Everything else freezes a single frame. Failed children
    /// never animate.
    func livePreviewIDs() -> Set<String> {
        let compiled = currentBatch.filter { $0.status == .compiled }
        var live = Set(compiled.filter { lineage.isFavorite($0.id) }.map(\.id))
        let slots = max(0, maxLivePreviews - live.count)
        let fillers = compiled.filter { !live.contains($0.id) }.suffix(slots)
        live.formUnion(fillers.map(\.id))
        return live
    }

    func shouldAnimate(_ id: String) -> Bool { livePreviewIDs().contains(id) }

    // MARK: selection

    func toggleFavorite(_ id: String) { lineage.toggleFavorite(id) }

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
    }
}
