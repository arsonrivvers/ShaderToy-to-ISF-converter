import XCTest
@testable import ARShader

/// SwiftUI gives no way to read back rendered text, so `InstrumentView.scalePickers` (the PREVIEW
/// SCALE / CUE SCALE readouts) cannot be pinned by rendering it. `InstrumentView.liveResolution` is
/// the pure computation both readouts are built from — this pins THAT, which is the whole testable
/// surface for "does the readout lie while the projector is open" (phase 3c round-1 review, I2).
final class InstrumentViewLiveResolutionTests: XCTestCase {
    func testWithOutputClosedTheReadoutFollowsPreviewScale() {
        let resolved = InstrumentView.liveResolution(
            programLive: false,
            previewScale: RenderScale(percent: 25),
            outputResolution: RenderSize(width: 1920, height: 1080))
        XCTAssertEqual(resolved.width, 480, "closed output: the readout must still show the "
                       + "scaled-down size the chain actually rasterises at")
        XCTAssertEqual(resolved.height, 270)
    }

    func testWithOutputOpenThePreviewScaleReadoutShowsFullSizeNotTheTypedPercentage() {
        // This is the exact bug I2 fixes: with PREVIEW 25% and the projector open, the chain
        // actually rasterises at full size (isProgramLive pins it) — the readout must say 1920,
        // not 480, or an operator reaching for this control mid-set is told a lie.
        let resolved = InstrumentView.liveResolution(
            programLive: true,
            previewScale: RenderScale(percent: 25),
            outputResolution: RenderSize(width: 1920, height: 1080))
        XCTAssertEqual(resolved.width, 1920)
        XCTAssertEqual(resolved.height, 1080)
    }

    func testTheCueReadoutComposesOntoTheSameLiveResolutionAsThePreviewReadout() {
        // The CUE SCALE row's resolved size is `cueRenderScale.applied(to: live)` where `live` is
        // the SAME value the PREVIEW SCALE row shows (InstrumentView.swift `scalePickers`) — so
        // pinning `liveResolution` pins both rows' correctness, not just the preview row's, as long
        // as the two rows are built from the one `live` value rather than two independent
        // computations. Reproduce that composition here exactly as the view does it.
        let liveWithOutputOpen = InstrumentView.liveResolution(
            programLive: true,
            previewScale: RenderScale(percent: 25),
            outputResolution: RenderSize(width: 1920, height: 1080))
        let cueResolved = RenderScale(percent: 50).applied(to: liveWithOutputOpen)
        XCTAssertEqual(cueResolved.width, 960,
                       "cued while projecting: half of the FULL 1920, not half of the scaled 480 "
                       + "PREVIEW SCALE would have given if it were still governing the chain")
        XCTAssertEqual(cueResolved.height, 540)

        let liveWithOutputClosed = InstrumentView.liveResolution(
            programLive: false,
            previewScale: RenderScale(percent: 25),
            outputResolution: RenderSize(width: 1920, height: 1080))
        let cueResolvedClosed = RenderScale(percent: 50).applied(to: liveWithOutputClosed)
        XCTAssertEqual(cueResolvedClosed.width, 240, "closed output: unchanged from before this fix")
        XCTAssertEqual(cueResolvedClosed.height, 135)
    }
}
