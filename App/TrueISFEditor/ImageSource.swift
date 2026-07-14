import Metal

/// A source of image data for a filter shader's image input. Conformers vend a Metal texture each
/// frame (test patterns and library shaders render into the caller's command buffer; camera returns
/// its latest captured frame).
///
/// Threading: sources are CREATED on the main thread (router/UI), but `texture(size:in:)` is called
/// from the render thread (the display-link loop encoding the frame). Conformers must be safe for
/// that single-consumer cross-thread pattern — internally locked (camera) or touched only by the
/// render thread after init (ISF scene sources).
protocol ImageSource: AnyObject, Sendable {
    var displayName: String { get }
    /// Returns a texture for this frame, rendering into `cb` if needed. Nil ⇒ leave the input unbound.
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?
}

/// The "no source" selection: the filter input is left unbound (engine default / black).
final class NoneSource: ImageSource {
    var displayName: String { "None" }
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? { nil }
}
