import AppKit
import Combine

/// Shared surface implemented by both preview engines. A later coordinator binds to
/// concrete engines (which keep their own @Published fields) and re-publishes state.
@MainActor
protocol PreviewEngine: AnyObject {
    var compileValid: Bool { get }
    var compileError: String? { get }
    var compileErrorLine: Int? { get }
    var inputs: [ISFPreviewInput] { get }
    var nsView: NSView { get }

    func load(isf: String)
    func setInput(_ name: String, _ jsonValue: String)
    func setRenderSize(width: Int?, height: Int?)

    /// Publisher the coordinator subscribes to so it can re-publish this engine's compile state.
    var compileStateWillChange: ObservableObjectPublisher { get }
}
