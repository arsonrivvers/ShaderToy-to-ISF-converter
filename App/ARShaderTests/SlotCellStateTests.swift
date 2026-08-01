import XCTest
@testable import ARShader

@MainActor
final class SlotCellStateTests: XCTestCase {
    private func preset(_ path: String = "/tmp/a.fs") -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: path), snapshot: ParamSnapshot(params: [:]))
    }

    func testAnEmptySlotIsIdle() {
        XCTAssertEqual(SlotCellState.of(preset: nil, isAvailable: false, liveOn: nil), .idle)
    }

    func testAFilledSlotWhoseFileIsGoneIsUnavailable() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: false, liveOn: nil),
                       .unavailable)
    }

    /// Unavailable OUTRANKS live. A slot whose file vanished while its shader is still playing
    /// must not draw as a healthy live slot — the operator would fire it and get nothing.
    func testUnavailableOutranksLive() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: false, liveOn: .one),
                       .unavailable)
    }

    func testAFilledAvailableSlotPlayingOnADeckIsLiveOnThatDeck() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: true, liveOn: .two),
                       .live(.two))
    }

    func testAFilledAvailableSlotNotPlayingIsIdle() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: true, liveOn: nil), .idle)
    }
}
