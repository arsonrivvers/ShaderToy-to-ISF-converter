import XCTest
import AppKit
@testable import TrueISFEditor

/// M28/M29 — thumbnail coordinator lifecycle. SwiftUI recycles coordinators across node changes
/// (LazyVGrid + tree slots), so the compile-report latch and the frozen-frame push must both be
/// transition-aware, not fire-once/fire-always.
@MainActor
final class RemixThumbnailTests: XCTestCase {
    private final class RecordingInputSink: TrueISFEditor.RemixPreviewInputApplying {
        var events: [RemixThumbnailView.InputMutation] = []
        func setRemixInput(_ name: String, value: TrueISFEditor.RemixParameterValue) {
            events.append(.set(name, value))
        }
        func resetRemixInput(_ name: String) {
            events.append(.remove(name))
        }
    }
    private let goodISF = """
    /*{ "DESCRIPTION": "t", "ISFVSN": "2", "INPUTS": [] }*/
    void main() { gl_FragColor = vec4(1.0); }
    """
    private let goodISF2 = """
    /*{ "DESCRIPTION": "t2", "ISFVSN": "2", "INPUTS": [] }*/
    void main() { gl_FragColor = vec4(0.5); }
    """

    private func waitUntil(timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async throws {
        let start = Date()
        while !cond() {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// M28 — a recycled coordinator must deliver the NEW source's compile result after
    /// `sourceChanged()`; before the fix `reported` stayed true forever, so a promoted parent kept
    /// the previous shader's swatch and result.
    func testSourceChanged_reportsTheNewCompile() async throws {
        var compiles = 0
        let coordinator = RemixThumbnailView.Coordinator(
            onCompile: { _, _ in compiles += 1 }, onSnapshot: nil)
        coordinator.observe(coordinator.controller)

        coordinator.loadedISF = goodISF
        coordinator.controller.load(isf: goodISF)
        try await waitUntil { compiles == 1 }

        coordinator.sourceChanged()
        coordinator.loadedISF = goodISF2
        coordinator.controller.load(isf: goodISF2)
        try await waitUntil { compiles == 2 }
        XCTAssertEqual(compiles, 2)
    }

    /// M29 — a paused card pushes a frame only on the animating→frozen TRANSITION; re-pushing on
    /// every SwiftUI update forced one GPU frame per paused card per transcript line.
    func testFrozenFramePush_onlyOnTransition() {
        XCTAssertTrue(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: true, animating: false))
        XCTAssertFalse(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: false, animating: false),
                       "already-frozen card re-rendered per view update")
        XCTAssertFalse(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: true, animating: true))
        XCTAssertFalse(RemixThumbnailView.shouldPushFrozenFrame(wasAnimating: false, animating: true))
    }

    func testFailureAfterSuccessfulCompileIsPreviewFailureNotCompileFailure() {
        XCTAssertEqual(
            RemixThumbnailView.classifyReport(
                hasCompiled: true,
                valid: false,
                error: "Metal device unavailable"
            ),
            .previewFailure("Metal device unavailable")
        )
    }

    func testSharedComparisonPreviewPausesOnlyItsRenderLoop() {
        XCTAssertEqual(
            RemixThumbnailView.pausePolicy(hasSharedClock: true),
            .renderLoopOnly
        )
        XCTAssertEqual(
            RemixThumbnailView.pausePolicy(hasSharedClock: false),
            .renderLoopAndClock
        )
    }

    func testCanvasKeyMappingIsFocusScoped() {
        XCTAssertEqual(RemixCanvasKeyRouter.command(for: " ", canvasFocused: true), .toggleComparison)
        XCTAssertEqual(RemixCanvasKeyRouter.command(for: "f", canvasFocused: true), .favorite)
        XCTAssertEqual(RemixCanvasKeyRouter.command(for: "\r", canvasFocused: true), .hero)
        XCTAssertNil(RemixCanvasKeyRouter.command(for: "f", canvasFocused: false))
        XCTAssertFalse(RemixCanvasKeyRouter.shouldHandle(
            canvasFocusActive: true,
            firstResponderIsTextInput: true
        ))
    }

    func testInputUpdateDiffCachesChangesAndRemovals() {
        let coordinator = RemixThumbnailView.Coordinator(
            onCompile: { _, _ in }, onSnapshot: nil
        )
        XCTAssertEqual(
            coordinator.inputMutations(for: ["gain": .float(0.5), "enabled": .bool(true)]),
            [.set("enabled", .bool(true)), .set("gain", .float(0.5))]
        )
        XCTAssertEqual(coordinator.inputMutations(for: ["gain": .float(0.5)]), [.remove("enabled")])
        XCTAssertTrue(coordinator.inputMutations(for: ["gain": .float(0.5)]).isEmpty)
    }

    func testUpdateNSViewProductionSeamAppliesChangesAfterInitialMake() {
        let coordinator = RemixThumbnailView.Coordinator(
            onCompile: { _, _ in }, onSnapshot: nil
        )
        let sink = RecordingInputSink()

        coordinator.applyInputValues(["gain": .float(0.25)], to: sink)
        sink.events.removeAll()
        coordinator.applyInputValues(["gain": .float(0.75), "enabled": .bool(true)], to: sink)

        XCTAssertEqual(
            sink.events,
            [.set("enabled", .bool(true)), .set("gain", .float(0.75))]
        )
    }

    func testUpdateNSViewSourceCallsInputApplicationSeam() throws {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsURL
            .deletingLastPathComponent()
            .appendingPathComponent("TrueISFEditor/Remix/RemixThumbnailView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let updateStart = try XCTUnwrap(source.range(of: "func updateNSView"))
        let helperStart = try XCTUnwrap(
            source.range(of: "static func shouldPushFrozenFrame", range: updateStart.upperBound..<source.endIndex)
        )
        let updateBody = source[updateStart.lowerBound..<helperStart.lowerBound]

        XCTAssertTrue(
            updateBody.contains("context.coordinator.applyInputValues(inputValues, to: controller)")
        )
    }

    func testCanvasKeyMappingRejectsModifiedShortcuts() {
        let accepted: [(String, NSEvent.ModifierFlags, TrueISFEditor.RemixKeyboardCommand)] = [
            (" ", [], .toggleComparison),
            ("f", [.capsLock], .favorite),
            ("\r", [.function], .hero),
            ("\u{1b}", [], .exitCanvasMode),
        ]
        for (characters, modifiers, expected) in accepted {
            XCTAssertEqual(
                RemixCanvasKeyRouter.command(
                    for: characters,
                    modifiers: modifiers,
                    canvasFocused: true
                ),
                expected
            )
        }

        for modifiers: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            XCTAssertNil(RemixCanvasKeyRouter.command(
                for: "f",
                modifiers: modifiers,
                canvasFocused: true
            ))
        }
    }

    func testCanvasWidthPolicyUsesActuallyCompactTwoRowLayout() {
        XCTAssertEqual(RemixCanvasWidthPolicy.presentation(for: 900), .regular)
        XCTAssertEqual(RemixCanvasWidthPolicy.presentation(for: 620), .compact)
    }
}
