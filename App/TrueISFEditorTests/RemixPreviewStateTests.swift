import XCTest
@testable import TrueISFEditor

@MainActor
final class RemixPreviewStateTests: XCTestCase {
    private final class CountingProvider: AssistProvider {
        private(set) var callCount = 0

        func run(
            prompt: String,
            system: String,
            model: String?,
            timeout: TimeInterval,
            onEvent: @escaping @Sendable (String) -> Void
        ) async throws -> String {
            callCount += 1
            return ""
        }
    }

    private final class CountingCompiler: RemixCompiling {
        private(set) var sources: [String] = []

        func compile(_ source: String) async -> RemixCompileResult {
            sources.append(source)
            return RemixCompileResult(isValid: true, diagnostic: nil, errorLine: nil)
        }
    }

    func test_readyArtifactPreviewTransitionsAreRendererScopedAndRetryOnlyIncrementsThatArtifact() throws {
        let provider = CountingProvider()
        let compiler = CountingCompiler()
        let model = makeModel(provider: provider, compiler: compiler)
        let ready = readyRecord(id: "r1-0", source: completeISF("ready"))
        let sibling = readyRecord(id: "r1-1", source: completeISF("sibling"))

        model.applyPipelineUpdate(.artifact(artifact(from: ready), record: ready))
        model.applyPipelineUpdate(.artifact(artifact(from: sibling), record: sibling))

        XCTAssertEqual(model.previewStates["r1-0"]?.stage, .pending)
        XCTAssertEqual(model.previewStates["r1-0"]?.attempt, 0)
        model.markPreviewAvailable(artifactID: "r1-0")
        XCTAssertEqual(model.previewStates["r1-0"]?.stage, .available)

        model.markPreviewFailed(artifactID: "r1-0", diagnostic: "Metal device unavailable")
        XCTAssertEqual(model.previewStates["r1-0"]?.stage, .failed)
        XCTAssertEqual(model.previewStates["r1-0"]?.diagnostic, "Metal device unavailable")
        XCTAssertEqual(model.currentRuns.first?.stage, .ready)
        XCTAssertNotNil(model.lineage.node("r1-0"))

        model.retryPreview(artifactID: "r1-0")
        XCTAssertEqual(model.previewStates["r1-0"]?.stage, .pending)
        XCTAssertEqual(model.previewStates["r1-0"]?.attempt, 1)
        XCTAssertEqual(model.previewStates["r1-1"]?.attempt, 0)
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertTrue(compiler.sources.isEmpty)
    }

    func test_rendererDiagnosticIsBoundedByUTF8Bytes() throws {
        let provider = CountingProvider()
        let compiler = CountingCompiler()
        let model = makeModel(provider: provider, compiler: compiler)
        let ready = readyRecord(id: "r1-0", source: completeISF("ready"))
        model.applyPipelineUpdate(.artifact(artifact(from: ready), record: ready))

        model.markPreviewFailed(
            artifactID: ready.id,
            diagnostic: String(repeating: "🫧", count: RemixPreviewState.maximumDiagnosticBytes)
        )

        let diagnostic = try XCTUnwrap(model.previewStates[ready.id]?.diagnostic)
        XCTAssertLessThanOrEqual(diagnostic.utf8.count, RemixPreviewState.maximumDiagnosticBytes)
    }

    func test_literalOversizedJSONBoundsPreviewDiagnosticOnDecodeAndRoundTrip() throws {
        let oversized = String(
            repeating: "🫧",
            count: RemixPreviewState.maximumDiagnosticBytes
        )
        let literalJSON = """
        {"stage":"failed","attempt":3,"diagnostic":"\(oversized)","updatedAt":0}
        """

        let decoded = try JSONDecoder().decode(
            RemixPreviewState.self,
            from: Data(literalJSON.utf8)
        )
        let decodedDiagnostic = try XCTUnwrap(decoded.diagnostic)
        XCTAssertLessThanOrEqual(
            decodedDiagnostic.utf8.count,
            RemixPreviewState.maximumDiagnosticBytes
        )
        XCTAssertNotNil(String(data: Data(decodedDiagnostic.utf8), encoding: .utf8))

        let restored = try JSONDecoder().decode(
            RemixPreviewState.self,
            from: JSONEncoder().encode(decoded)
        )
        let restoredDiagnostic = try XCTUnwrap(restored.diagnostic)
        XCTAssertLessThanOrEqual(
            restoredDiagnostic.utf8.count,
            RemixPreviewState.maximumDiagnosticBytes
        )
        XCTAssertNotNil(String(data: Data(restoredDiagnostic.utf8), encoding: .utf8))
    }

    func test_earlierSchemaV2WithoutPreviewStateDefaultsToEmptyMap() throws {
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "remix-schema-v2-mid-batch",
                withExtension: "json"
            )
        )
        let session = try JSONDecoder().decode(RemixSession.self, from: Data(contentsOf: fixture))
        XCTAssertEqual(session.previewStates, [:])
    }

    private func makeModel(
        provider: CountingProvider,
        compiler: CountingCompiler
    ) -> RemixStudioModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix-preview-state-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RemixStudioModel(
            generator: RemixGenerator(
                makeProvider: { provider },
                model: nil,
                compiler: compiler
            ),
            sessionStore: RemixSessionStore(
                fileURL: directory.appendingPathComponent("session.json")
            )
        )
    }

    private func readyRecord(id: String, source: String) -> RemixChildRunRecord {
        let slot = Int(id.split(separator: "-").last ?? "0") ?? 0
        return RemixChildRunRecord(
            id: id,
            round: 1,
            slot: slot,
            request: RemixGenerationRequestSnapshot(
                parentIDs: ["seed-0"],
                parentSources: [completeISF("parent")],
                mode: .mutate,
                steer: "",
                directive: "test",
                settings: RemixCrossoverSettings()
            ),
            stage: .ready,
            queuedAt: Date(timeIntervalSince1970: 1),
            terminalAt: Date(timeIntervalSince1970: 2),
            candidateSource: source,
            artifactID: id
        )
    }

    private func artifact(from record: RemixChildRunRecord) -> RemixNode {
        RemixNode(
            artifactID: record.id,
            isfSource: record.candidateSource!,
            parents: record.request.parentIDs,
            mode: record.request.mode,
            steer: record.request.steer,
            directive: record.request.directive,
            round: record.round
        )
    }

    private func completeISF(_ description: String) -> String {
        "/*{ \"DESCRIPTION\":\"\(description)\", \"ISFVSN\":\"2\", \"INPUTS\":[] }*/\n"
            + "void main(){ gl_FragColor=vec4(1.0); }"
    }
}
