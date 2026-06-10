import Metal

/// A source of image data for a filter shader's image input. Conformers vend a Metal texture each
/// frame (test patterns and library shaders render into the caller's command buffer; camera returns
/// its latest captured frame).
@MainActor
protocol ImageSource: AnyObject {
    var displayName: String { get }
    /// Returns a texture for this frame, rendering into `cb` if needed. Nil ⇒ leave the input unbound.
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?
}

/// The "no source" selection: the filter input is left unbound (engine default / black).
@MainActor
final class NoneSource: ImageSource {
    var displayName: String { "None" }
    func texture(size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? { nil }
}
