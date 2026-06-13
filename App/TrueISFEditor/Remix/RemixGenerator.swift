import Foundation

/// Fans out `batchSize` concurrent provider calls (capped), one mutation directive each, and emits a
/// RemixNode per slot as it lands. Provider/auth/timeout errors and "no ISF in the reply" both yield a
/// `.failed` node — the batch never aborts as a whole. ID generation is index-based (deterministic for
/// tests; the studio layer can namespace by round).
@MainActor
final class RemixGenerator {
    private let makeProvider: () -> AssistProvider
    private let model: String?
    private let maxConcurrent: Int
    private let timeout: TimeInterval

    /// `maxConcurrent` defaults to 2: each provider call spawns a full Claude/Codex CLI environment, so
    /// 4+ at once thrash the machine and individually blow past the timeout (a single call is ~37s).
    /// `timeout` is per child (from-scratch generation is heavier than an edit — 420s with margin).
    init(makeProvider: @escaping () -> AssistProvider, model: String?,
         maxConcurrent: Int = 2, timeout: TimeInterval = 420) {
        self.makeProvider = makeProvider
        self.model = model
        self.maxConcurrent = maxConcurrent
        self.timeout = timeout
    }

    /// `onLog` receives `(childId, line)` for every raw streaming line each provider emits — used to
    /// drive a live terminal so the user can watch Claude/Codex work and spot a hang. It is called from
    /// the provider's background reader thread, so implementations must hop to their own actor.
    func generate(parents: [String], mode: RemixMode, steer: String, batchSize: Int, round: Int,
                  onChild: @escaping (RemixNode) -> Void,
                  onLog: @escaping @Sendable (String, String) -> Void = { _, _ in }) async {
        let directives = RemixDirectives.pick(batchSize, seed: round)
        let system = RemixPrompt.system()
        await withTaskGroup(of: RemixNode.self) { group in
            var launched = 0
            func launch(_ slot: Int) {
                let directive = directives[slot]
                let labeled = parents.enumerated().map { (label: $0.offset == 0 ? "A" : "B", source: $0.element) }
                let prompt = RemixPrompt.user(parents: labeled, mode: mode, steer: steer, directive: directive)
                let provider = makeProvider()
                let mdl = model
                let to = timeout
                group.addTask { @MainActor in
                    let id = "r\(round)-\(slot)"
                    do {
                        let out = try await provider.run(prompt: prompt, system: system, model: mdl, timeout: to) { line in
                            onLog(id, line)
                        }
                        if let isf = RemixResponseParser.extractISF(out) {
                            return RemixNode(id: id, isfSource: isf, parents: [], mode: mode, steer: steer,
                                             directive: directive, round: round, status: .compiled)
                        }
                        return RemixNode(id: id, isfSource: out, parents: [], mode: mode, steer: steer,
                                         directive: directive, round: round, status: .failed("No ISF in reply"))
                    } catch {
                        return RemixNode(id: id, isfSource: "", parents: [], mode: mode, steer: steer,
                                         directive: directive, round: round, status: .failed("\(error)"))
                    }
                }
            }
            while launched < min(maxConcurrent, batchSize) { launch(launched); launched += 1 }
            for await node in group {
                onChild(node)
                if launched < batchSize { launch(launched); launched += 1 }
            }
        }
    }
}
