import XCTest
import Metal
import CoreVideo
@testable import TrueISFEditor

/// Phase 1 tail: C9 (camera frame pinning), C10 (idle session stop), M34 (event pulse latch),
/// M43 (imported title), N28 (transcript humanization).
final class Phase1TailTests: XCTestCase {

    // MARK: C9 / C10 — CameraFrameProvider

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &pb)
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pb)
    }

    func testIngestedFrameComesBackPinned() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        let provider = try XCTUnwrap(CameraFrameProvider(device: device))
        XCTAssertNil(provider.currentFrame(), "no frames ingested yet")
        provider.ingest(pixelBuffer: try makePixelBuffer())
        let frame = try XCTUnwrap(provider.currentFrame())
        // The pin is the C9 contract: texture AND its CVMetalTexture backing travel together.
        XCTAssertEqual(frame.texture.width, 64)
        XCTAssertEqual(CVMetalTextureGetTexture(frame.backing)?.width, 64)
    }

    func testSessionIdleStopsAfterTimeoutAndRestartsOnAccess() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        var clock: CFTimeInterval = 100
        let provider = try XCTUnwrap(CameraFrameProvider(device: device, now: { clock }))
        _ = provider.currentFrame()                       // consumer touch at t=100
        provider.ingest(pixelBuffer: try makePixelBuffer())
        XCTAssertFalse(provider.isIdleStoppedForTesting, "recent access → keeps running")

        clock = 100 + CameraFrameProvider.idleStopSeconds + 1
        provider.ingest(pixelBuffer: try makePixelBuffer())   // heartbeat sees stale access
        XCTAssertTrue(provider.isIdleStoppedForTesting, "no consumer for >timeout → stops")

        _ = provider.currentFrame()                       // consumer returns
        XCTAssertFalse(provider.isIdleStoppedForTesting, "access restarts the session")
    }

    // MARK: M34 — event pulse

    @MainActor
    func testDefaultPulseEventSendsTrueThenFalse() async {
        let fake = FakePreviewEngine()
        fake.pulseEvent("bang")
        XCTAssertEqual(fake.lastInput?.0, "bang")
        XCTAssertEqual(fake.lastInput?.1, "true")
        await Task.yield()                                 // let the reset turn run
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.lastInput?.1, "false", "default path resets on the next turn")
    }

    // MARK: M43 — imported document title

    @MainActor
    func testImportedDocumentShowsSuggestedName() {
        let vm = EditorViewModel(file: .untitled(source: EditorViewModel.blankTemplate))
        vm.loadImported(isf: EditorViewModel.blankTemplate, warnings: [], suggestedName: "Plasma Storm")
        XCTAssertEqual(vm.file.displayName, "Plasma Storm.fs")
        XCTAssertTrue(vm.file.needsSaveAs, "still unsaved — the name is a suggestion, not a URL")
    }

    func testUntitledWithoutSuggestionKeepsClassicTitle() {
        XCTAssertEqual(ISFFile.untitled(source: "x").displayName, "Untitled.fs")
        XCTAssertEqual(ISFFile.untitled(source: "x", suggestedName: "already.fs").displayName, "already.fs")
    }

    // MARK: N28 — transcript humanization

    func testTranscriptFormatterHumanizesStreamJSON() {
        XCTAssertEqual(
            AssistTranscriptFormatter.display(#"{"type":"system","subtype":"init","model":"opus"}"#),
            "session started · opus")
        XCTAssertNil(AssistTranscriptFormatter.display(#"{"type":"system","subtype":"other"}"#))
        XCTAssertEqual(
            AssistTranscriptFormatter.display(
                #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the shader."},{"type":"tool_use","name":"read_file"}]}}"#),
            "Looking at the shader.\n→ read_file")
        XCTAssertEqual(
            AssistTranscriptFormatter.display(#"{"type":"result","duration_ms":12340.0}"#),
            "done in 12.3s")
        // The exact leak CS screenshotted: token/cost internals must be dropped.
        XCTAssertNil(AssistTranscriptFormatter.display(
            #"{"type":"user","ephemeral_5m_input_tokens":123,"costUSD":0.56663,"uuid":"abc"}"#))
        // Non-JSON CLI output passes through.
        XCTAssertEqual(AssistTranscriptFormatter.display("plain progress line"), "plain progress line")
        XCTAssertNil(AssistTranscriptFormatter.display("   "))
    }
}
