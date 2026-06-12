import XCTest
import CoreGraphics
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

    func test_livePreviewCap_favoritesAlwaysAnimate_othersFillUpToCap() async {
        let m = model([.success("```glsl\n\(isf)\n```")])
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/")
        m.batchSize = 6; m.maxLivePreviews = 4
        await m.generate()
        for n in m.currentBatch { m.markCompileResult(id: n.id, valid: true, error: nil) }
        // No favorites yet: exactly maxLivePreviews animate.
        XCTAssertEqual(m.currentBatch.filter { m.shouldAnimate($0.id) }.count, 4)
        // Favorite two of the frozen ones -> both animate even though we're over the cap.
        let frozen = m.currentBatch.filter { !m.shouldAnimate($0.id) }
        m.toggleFavorite(frozen[0].id); m.toggleFavorite(frozen[1].id)
        XCTAssertTrue(m.shouldAnimate(frozen[0].id))
        XCTAssertTrue(m.shouldAnimate(frozen[1].id))
        XCTAssertGreaterThanOrEqual(m.currentBatch.filter { m.shouldAnimate($0.id) }.count, 4)
    }

    func test_failedChildren_neverAnimate() async {
        let m = model([.success("I couldn't.")])   // no ISF -> generator marks .failed
        m.mode = .mutate; m.setParent(.a, isf: "/*{A}*/"); m.batchSize = 2; m.maxLivePreviews = 4
        await m.generate()
        XCTAssertTrue(m.currentBatch.allSatisfy { !m.shouldAnimate($0.id) })
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
        let ps = RemixStudioModel.makePlaceholders(round: 2, size: 3, parents: ["seed-0"])
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
}
