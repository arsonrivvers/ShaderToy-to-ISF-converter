import XCTest
@testable import TrueISFEditor

/// Canonical fake provider (same shape as RemixGeneratorTests). Returns a scripted ISF per call or throws.
@MainActor
private final class FakeProvider: AssistProvider {
    var scripts: [Result<String, Error>]
    private var i = 0
    init(_ scripts: [Result<String, Error>]) { self.scripts = scripts }
    func run(prompt: String, system: String, model: String?, timeout: TimeInterval,
             onEvent: @escaping @Sendable (String) -> Void) async throws -> String {
        defer { i += 1 }
        switch scripts[min(i, scripts.count - 1)] {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

@MainActor
final class RemixStudioModelTests: XCTestCase {
    private let isf = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }"
    private func model(_ scripts: [Result<String, Error>]) -> RemixStudioModel {
        let provider = FakeProvider(scripts)
        return RemixStudioModel(generator: RemixGenerator(makeProvider: { provider }, model: nil))
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

    func test_markCompileResult_updatesStatus_inBatchAndLineage() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let id = m.currentBatch[0].id
        m.markCompileResult(id: id, valid: false, error: "bad GLSL")
        XCTAssertEqual(m.currentBatch[0].status, .failed("bad GLSL"))
        XCTAssertEqual(m.lineage.node(id)?.status, .failed("bad GLSL"))
        m.markCompileResult(id: id, valid: true, error: nil)
        XCTAssertEqual(m.currentBatch[0].status, .compiled)
    }

    func test_favorites_toggle_throughModel() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let id = m.currentBatch[0].id
        m.toggleFavorite(id)
        XCTAssertTrue(m.lineage.isFavorite(id))
        XCTAssertEqual(m.favoriteNodes.map(\.id), [id])
    }

    func test_promoteToParent_setsParentToExistingNode_noNewSeed() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()
        let childID = m.currentBatch[0].id
        m.promoteToParent(.a, nodeID: childID)
        XCTAssertEqual(m.parentAID, childID)
    }

    func test_stepBack_restoresPreviousParents() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 1
        await m.generate()                       // round 1, parent = seed
        let seedID = m.parentAID
        let childID = m.currentBatch[0].id
        m.promoteToParent(.a, nodeID: childID)
        await m.generate()                       // round 2, parent = child
        XCTAssertEqual(m.parentAID, childID)
        m.stepBack()
        XCTAssertEqual(m.parentAID, seedID)      // restored to the round-1 config
    }
}
