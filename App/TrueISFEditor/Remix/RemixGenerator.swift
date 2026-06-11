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

    init(makeProvider: @escaping () -> AssistProvider, model: String?, maxConcurrent: Int = 4) {
        self.makeProvider = makeProvider
        self.model = model
        self.maxConcurrent = maxConcurrent
    }

    func generate(parents: [String], mode: RemixMode, steer: String, batchSize: Int, round: Int,
                  onChild: @escaping (RemixNode) -> Void) async {
        let directives = RemixDirectives.pick(batchSize, seed: round)
        let system = RemixPrompt.system()
        await withTaskGroup(of: RemixNode.self) { group in
            var launched = 0
            func launch(_ slot: Int) {
                let directive = directives[slot]
                let prompt = RemixPrompt.user(parents: parents, mode: mode, steer: steer, directive: directive)
                let provider = makeProvider()
                let mdl = model
                group.addTask { @MainActor in
                    let id = "r\(round)-\(slot)"
                    do {
                        let out = try await provider.run(prompt: prompt, system: system, model: mdl, timeout: 240) { _ in }
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
