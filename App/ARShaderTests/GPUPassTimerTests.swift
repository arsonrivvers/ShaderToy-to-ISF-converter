import XCTest
import Metal

/// Capability probe for per-element GPU timing.
///
/// Per-pane GPU milliseconds need a timestamp sampled at arbitrary points INSIDE the frame's single
/// command buffer — the ISF render happens inside `ISFMSLSafeRenderAtTime`, so its render-pass
/// descriptors are not ours to attach stage-boundary counters to. Sampling from a blit encoder is
/// the way in. This records what the machine actually supports rather than assuming.
final class GPUPassTimerTests: XCTestCase {
    func testRecordTimestampSamplingSupport() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let timestampSet = device.counterSets?.first { $0.name == MTLCommonCounterSet.timestamp.rawValue }
        print("""
        ── GPU counter capability ──
          device:            \(device.name)
          counterSets:       \(device.counterSets?.map(\.name) ?? [])
          timestamp set:     \(timestampSet != nil ? "present" : "ABSENT")
          atStageBoundary:   \(device.supportsCounterSampling(.atStageBoundary))
          atDrawBoundary:    \(device.supportsCounterSampling(.atDrawBoundary))
          atBlitBoundary:    \(device.supportsCounterSampling(.atBlitBoundary))
          atDispatchBoundary:\(device.supportsCounterSampling(.atDispatchBoundary))
          atTileDispatchBoundary:\(device.supportsCounterSampling(.atTileDispatchBoundary))
        """)
        // Not an assertion about support — a record of it. The feature branches on this.
        XCTAssertNotNil(device.counterSets, "a Metal device always reports a counter set list")
    }

    /// Why per-element metering does NOT use counter sampling.
    ///
    /// The obvious design was `MTLBlitCommandEncoder.sampleCounters` bracketing each element,
    /// which needs `.atBlitBoundary`. Measured on Apple M5 Max: **false**. Only `.atStageBoundary`
    /// is available, and that attaches to render-pass descriptors — which for the dominant cost
    /// (the ISF render, inside `ISFMSLSafeRenderAtTime`) are not ours to touch.
    ///
    /// So metering splits the frame into one command buffer per element and uses
    /// `gpuStartTime`/`gpuEndTime`, the same measurement the global readout already trusts.
    /// If a future machine gains blit-boundary sampling this test will start failing, which is
    /// the point: it is a standing invitation to revisit the decision, not a permanent claim.
    func testBlitBoundarySamplingIsUnavailableWhichIsWhyMeteringSplitsBuffers() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        XCTAssertFalse(device.supportsCounterSampling(.atBlitBoundary),
                       "If this now passes, per-element timing could be done in ONE buffer — "
                       + "revisit InstrumentRenderer.meteringEnabled.")
    }
}
