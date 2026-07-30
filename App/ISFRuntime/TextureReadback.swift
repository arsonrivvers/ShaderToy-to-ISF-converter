import Metal

/// Blit a GPU-private texture into a CPU-readable copy. Every pixel-verification path needs this
/// (VVMTLPool textures are `.private` and cannot be read directly), and each one used to open-code
/// it. Synchronous: commits its own command buffer and waits.
enum TextureReadback {
    static func managedCopy(of texture: MTLTexture,
                            device: MTLDevice,
                            queue: MTLCommandQueue) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height,
            mipmapped: false)
        desc.storageMode = .managed
        guard let readback = device.makeTexture(descriptor: desc),
              let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, to: readback)
        blit.synchronize(resource: readback)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return readback
    }
}
