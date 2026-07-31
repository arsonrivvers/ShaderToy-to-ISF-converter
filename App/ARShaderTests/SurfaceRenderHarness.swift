import AppKit
import SwiftUI

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
    /// specified: xcodebuild does not forward environment into a hosted macOS unit-test process on
    /// this toolchain. Verified, not assumed — a diagnostic run with the variable set both as a
    /// parent-process export AND as a `TEST_RUNNER_`-prefixed build setting saw
    /// `ProcessInfo.processInfo.environment` contain NEITHER. The documented switch could never
    /// have fired, so baselines could never have been recorded.
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
