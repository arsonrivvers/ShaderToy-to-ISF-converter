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
        let compiled = session.currentBatch[0]
        var failed = compiled
        failed = RemixNode(
            id: "r7-1", isfSource: "", parents: compiled.parents, mode: .mutate,
            steer: "failed steer", directive: "failed directive", round: 7,
            status: .failed("provider failed")
        )
        let interrupted = RemixNode(
            id: "r7-2", isfSource: "", parents: compiled.parents, mode: .mutate,
            steer: "interrupted steer", directive: "interrupted directive", round: 7,
            status: .interrupted
        )
        let requests = Dictionary(uniqueKeysWithValues: [compiled, failed, interrupted].map { node in
            (
                node.id,
                RemixGenerationRequestSnapshot(
                    parentIDs: node.parents,
                    parentSources: ["RESTORED_PARENT"],
                    mode: node.mode,
                    steer: node.steer,
                    directive: node.directive,
                    settings: session.crossoverSettings
                )
            )
        })
        session.currentBatch = [compiled, failed, interrupted]
        session.batchHistory = [
            RemixBatchRecord(round: 7, nodes: session.currentBatch, requestsByNodeID: requests)
        ]
        var restoredLineage = session.lineage
        restoredLineage.insert(failed)
        restoredLineage.insert(interrupted)
        session.lineage = restoredLineage
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
        XCTAssertEqual(m.currentBatch[0], compiled)
        XCTAssertEqual(m.currentBatch[1].status, .compiled)
        XCTAssertEqual(m.currentBatch[2].status, .interrupted)
        XCTAssertEqual(provider.prompts.count, 1)

        await m.retryInterruptedBatch()
        XCTAssertEqual(m.currentBatch[0], compiled)
        XCTAssertEqual(m.currentBatch[1].status, .compiled)
        XCTAssertEqual(m.currentBatch[2].status, .compiled)
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

        restored.stepBack()

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

        restored.markCompileResult(id: childID, valid: false, error: "bad GLSL")
        XCTAssertEqual(
            try loadedSession(fixture.store).lineage.node(childID)?.status,
            .failed("bad GLSL")
        )

        restored.cancelGeneration()
        XCTAssertEqual(try loadedSession(fixture.store).activity, .cancelled)

        restored.promoteToParent(.a, nodeID: childID)
        await restored.generate()
        restored.stepBack()
        XCTAssertEqual(try loadedSession(fixture.store).parentAID, "seed-0")
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
}
