import AppKit
import SwiftUI
import XCTest

/// Frames reported by self-measuring test content, keyed by name.
///
/// A `PreferenceKey` rather than an `NSView` walk: SwiftUI does not create a backing `NSView` per
/// view, so walking `subviews` for accessibility identifiers finds nothing. This mirrors the
/// `PanelLeadingEdgeKey` mechanism already used in `InstrumentSurface`.
struct MeasuredFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Report this view's frame, in the named coordinate space, under `name`.
    func measured(_ name: String, in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: MeasuredFramesKey.self,
                                       value: [name: proxy.frame(in: .named(space))])
            }
        )
    }
}

/// Mutable capture box for the preference callback.
///
/// File-scope rather than nested inside `frames(_:size:)`: Swift forbids a class nested in a
/// generic function ("type 'Box' cannot be nested in generic function"). `@unchecked Sendable`
/// because `onPreferenceChange`'s action is `@Sendable`; every access is on the main actor.
private final class FrameBox: @unchecked Sendable {
    var frames: [String: CGRect] = [:]
}

/// Mutable capture box for `SurfaceRenderHarness.preferenceValue`, generic over any `PreferenceKey`.
/// Same file-scope-class-not-nested-in-a-generic-function constraint as `FrameBox`, and the same
/// `@unchecked Sendable` reasoning: every access happens on the main actor, synchronously, inside
/// `onPreferenceChange`'s callback.
private final class PreferenceBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Renders a SwiftUI view into a real laid-out AppKit view tree and returns what the layout did.
///
/// Why this exists: every defect that reached the operator for three sessions was invisible to
/// assertions on state — a `ScrollView` collapsed to zero height, dropdowns lost among sliders, a
/// button slab. This measures geometry instead.
///
/// Every view measured here must be pure SwiftUI: the live monitors are Metal-backed and cannot
/// render in a unit test, which is exactly why `InstrumentSurface` is generic over its content.
@MainActor
enum SurfaceRenderHarness {

    /// Host `view`, lay it out at `size`, and return every frame reported via `measured(_:in:)`.
    ///
    /// Returns an EMPTY dictionary if preference delivery never happened. Callers must
    /// `XCTUnwrap` their lookups so that shows up as a failure rather than a silent pass.
    static func frames<V: View>(_ view: V, size: CGSize) -> [String: CGRect] {
        let box = FrameBox()

        let instrumented = view
            .frame(width: size.width, height: size.height)
            .onPreferenceChange(MeasuredFramesKey.self) { box.frames = $0 }

        let host = NSHostingView(rootView: instrumented)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Preference delivery happens on a SwiftUI update pass; give the run loop a turn so the
        // onPreferenceChange callback has fired before we read.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        return box.frames
    }

    /// Host `view`, lay it out at `size`, and return the final value reported through `key` —
    /// generalised from `frames(_:size:)`'s `MeasuredFramesKey`-only capture so a caller can read
    /// ANY `PreferenceKey` a production view reports, not only the test-only measurement one.
    ///
    /// Needed for task 4C's cell-width and row-pitch gates: those read `DrawnCellWidthKey` and
    /// `DrawnRowHeightKey`, both reported by the REAL `SlotBankStripView` (not a stub), WITHOUT
    /// wrapping it in `.fixedSize` — `.fixedSize` asks a view for its IDEAL size, an unconstrained
    /// query that decouples the result from the actual window width being tested, which is exactly
    /// the axis these two gates need to observe.
    ///
    /// **Loops to a fixed point rather than laying out twice.** `SlotBankStripView`'s cell width is
    /// itself fed by a `@State` var written from a DIFFERENT preference
    /// (`CellsRegionWidthKey`) that only resolves after the FIRST layout pass — so the value this
    /// function reports depends on a SECOND pass having already happened, and `DrawnCellWidthKey`
    /// (fed by the cell width computed from THAT) needs a pass after that again. Two fixed
    /// `layoutSubtreeIfNeeded()` calls (`frames(_:size:)`'s technique) measured `DrawnCellWidthKey`
    /// stuck at the floor at every window width, including 2560pt — not a real result, an
    /// under-settled harness. Looping until the reported value stops changing is what actually
    /// reaches what production converges to.
    ///
    /// **Capped AND fails loudly on non-convergence (fix round 1, F4).** A previous version of this
    /// comment claimed the cap alone made "a genuinely unstable preference chain fail loudly instead
    /// of hanging" — it did not: the loop silently returned whatever `box.value` happened to hold
    /// after the last iteration, cap reached or not, so an oscillating chain would have reported a
    /// plausible-looking number instead of failing. Now it does what the comment always claimed: if
    /// the loop exhausts every iteration without two consecutive reads agreeing, it calls `XCTFail`
    /// with the two disagreeing values before returning — the exact guard task 4C's own
    /// measure → `@Environment` → resize → re-measure chain would need if a future change reintroduced
    /// an oscillation instead of a converging settle.
    static func preferenceValue<V: View, K: PreferenceKey>(
        _ view: V, key: K.Type, size: CGSize
    ) -> K.Value where K.Value: Equatable {
        let box = PreferenceBox<K.Value>(K.defaultValue)

        let instrumented = view
            .frame(width: size.width, height: size.height)
            .onPreferenceChange(K.self) { box.value = $0 }

        let host = NSHostingView(rootView: instrumented)
        host.frame = CGRect(origin: .zero, size: size)

        var previous: K.Value?
        var converged = false
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
            if let previous, previous == box.value {
                converged = true
                break
            }
            previous = box.value
        }
        if !converged {
            XCTFail("SurfaceRenderHarness.preferenceValue(\(K.self)) did not converge in 10 "
                     + "settle passes — last two reads were \(String(describing: previous)) and "
                     + "\(box.value). Either a genuinely unstable preference chain (fix it) or a "
                     + "settle count that needs raising, not a value to trust silently.")
        }
        return box.value
    }

    static func png<V: View>(_ view: V, size: CGSize) -> Data? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Committed baseline PNGs. Derived from `#filePath`, so recording writes into the SOURCE tree
    /// — the copy that gets committed — rather than into a build product that the next clean wipes.
    static var baselinesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Baselines")
    }

    /// Presence of this file switches `compareBaseline` from gating to recording.
    ///
    /// A file rather than the `ARSHADER_RECORD_BASELINES=1` environment variable the brief
    /// specified. Measured, not assumed: a diagnostic run set the variable BOTH as a parent-process
    /// shell export AND as a `TEST_RUNNER_`-prefixed build setting, and the hosted test process saw
    /// `ProcessInfo.processInfo.environment` contain neither. Those two routes are ruled out on
    /// this toolchain (Xcode 26.1.1); env delivery in general is NOT — XcodeGen can declare
    /// `schemes.ARShader.test.environmentVariables`, which bakes the value into the scheme and was
    /// not tried.
    ///
    /// The sentinel is kept anyway, on its own merits rather than as a fallback: an environment
    /// variable cannot make a recording run announce itself, and this can (below).
    ///
    /// A recording run is also made structurally unable to look like a passing one: the caller
    /// consumes the sentinel and fails the test outright (see `testSurfaceBaselines`). So a
    /// forgotten sentinel cannot quietly turn the gate off — it turns it loud instead.
    static var recordSentinel: URL { baselinesDirectory.appendingPathComponent("RECORD") }

    static var isRecording: Bool {
        FileManager.default.fileExists(atPath: recordSentinel.path)
    }

    /// Compare against a committed baseline, or record it when the sentinel is present.
    /// Returns nil on success, or a human-readable reason on failure.
    ///
    /// **These baselines are machine-specific, and they are NOT the load-bearing gate.** The
    /// geometry assertions in `SurfaceGeometryTests` are; these are supplementary.
    ///
    /// Two reasons to re-record rather than investigate when all of them go red at once:
    /// - The comparison is **byte-exact**, with no pixel tolerance, so any antialiasing or
    ///   control-metric change across a macOS point release turns every baseline red together.
    /// - They are recorded at the **display's backing scale** — currently 2x, i.e. 3200x2000 PNGs
    ///   for a 1600x1000 logical view. A 1x display, a different window-server context, or CI will
    ///   produce a different pixel size and fail for a reason that has nothing to do with layout.
    ///
    /// So: valid for the display configuration they were recorded on. On a different machine or in
    /// CI they must be re-recorded (see `recordSentinel`) — and if it is ONLY these that are red
    /// while the geometry tests stay green, the layout is fine and the environment changed.
    static func compareBaseline(_ data: Data, named name: String) -> String? {
        let file = baselinesDirectory.appendingPathComponent("\(name).png")

        if isRecording {
            do {
                try FileManager.default.createDirectory(
                    at: baselinesDirectory, withIntermediateDirectories: true)
                try data.write(to: file)
            } catch {
                // Surfaced, not swallowed: a silently failed write is how "recorded" baselines
                // turn out not to exist, and the next run blames a missing file instead.
                return "Could not record \(name) at \(file.path): \(error)"
            }
            return nil
        }
        guard let baseline = try? Data(contentsOf: file) else {
            return "No baseline for \(name) at \(file.path). Record by creating "
                + "\(recordSentinel.path) and re-running."
        }
        return baseline == data ? nil : "\(name) differs from its baseline."
    }
}
