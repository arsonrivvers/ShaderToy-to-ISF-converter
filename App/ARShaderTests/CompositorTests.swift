import XCTest
import Metal

@MainActor
final class CompositorTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var compositor: Compositor!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        compositor = try XCTUnwrap(Compositor(device: device))
    }

    /// A small solid-colour texture in the master format.
    private func solid(_ rgb: SIMD3<Double>, size: Int = 16) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat, width: size, height: size,
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: rgb.x, green: rgb.y, blue: rgb.z,
                                                           alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return tex
    }

    private func blank(size: Int = 16) throws -> MTLTexture {
        try solid(SIMD3(0, 0, 0), size: size)
    }

    private func composite(source: SIMD3<Double>, backdrop: SIMD3<Double>,
                           opacity: Double, mode: BlendMode) throws -> SIMD3<Double> {
        let src = try solid(source)
        let back = try solid(backdrop)
        let dest = try blank()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        compositor.encodeLayer(source: src, backdrop: back, destination: dest,
                               opacity: opacity, mode: mode, in: cb)
        cb.commit()
        cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: dest, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    /// The GPU must agree with the Swift reference. Tolerance covers rgba16Float precision.
    func testEveryBlendModeMatchesTheSwiftReference() throws {
        let source = SIMD3<Double>(0.75, 0.5, 0.25)
        let backdrop = SIMD3<Double>(0.25, 0.5, 0.75)
        for mode in BlendMode.allCases {
            for opacity in [0.0, 0.35, 1.0] {
                let gpu = try composite(source: source, backdrop: backdrop,
                                        opacity: opacity, mode: mode)
                let cpu = BlendMath.composite(backdrop: backdrop, source: source,
                                              alpha: opacity, mode: mode)
                XCTAssertEqual(gpu.x, cpu.x, accuracy: 0.005, "\(mode.rawValue) @ \(opacity) red")
                XCTAssertEqual(gpu.y, cpu.y, accuracy: 0.005, "\(mode.rawValue) @ \(opacity) green")
                XCTAssertEqual(gpu.z, cpu.z, accuracy: 0.005, "\(mode.rawValue) @ \(opacity) blue")
            }
        }
    }

    /// The special cases live at the extremes, where the general formula divides by zero.
    func testDodgeAndBurnEdgeCasesMatchTheReference() throws {
        let cases: [(SIMD3<Double>, SIMD3<Double>, BlendMode)] = [
            (SIMD3(1, 1, 1), SIMD3(0.5, 0.5, 0.5), .colorDodge),   // cs == 1 -> 1
            (SIMD3(0.9, 0.9, 0.9), SIMD3(0, 0, 0), .colorDodge),   // cb == 0 -> 0
            (SIMD3(0, 0, 0), SIMD3(0.5, 0.5, 0.5), .colorBurn),    // cs == 0 -> 0
            (SIMD3(0.1, 0.1, 0.1), SIMD3(1, 1, 1), .colorBurn),    // cb == 1 -> 1
        ]
        for (src, back, mode) in cases {
            let gpu = try composite(source: src, backdrop: back, opacity: 1.0, mode: mode)
            let cpu = BlendMath.composite(backdrop: back, source: src, alpha: 1.0, mode: mode)
            XCTAssertEqual(gpu.x, cpu.x, accuracy: 0.005,
                           "\(mode.rawValue) edge case src=\(src.x) back=\(back.x)")
        }
    }

    func testZeroOpacityLeavesTheBackdropExactlyAsItWas() throws {
        let backdrop = SIMD3<Double>(0.2, 0.4, 0.6)
        let out = try composite(source: SIMD3(1, 1, 1), backdrop: backdrop,
                                opacity: 0, mode: .difference)
        XCTAssertEqual(out.x, backdrop.x, accuracy: 0.005)
        XCTAssertEqual(out.y, backdrop.y, accuracy: 0.005)
        XCTAssertEqual(out.z, backdrop.z, accuracy: 0.005)
    }

    func testNormalAtFullOpacityReplacesTheBackdrop() throws {
        let out = try composite(source: SIMD3(0.9, 0.1, 0.3), backdrop: SIMD3(0.1, 0.9, 0.7),
                                opacity: 1, mode: .normal)
        XCTAssertEqual(out.x, 0.9, accuracy: 0.005)
        XCTAssertEqual(out.y, 0.1, accuracy: 0.005)
        XCTAssertEqual(out.z, 0.3, accuracy: 0.005)
    }

    func testOutputIsAlwaysOpaque() throws {
        // The master must stay opaque: a stack that leaks alpha < 1 is how the TouchDesigner
        // build's blackout gate silently failed (Level TOP alpha leak, Phase B).
        let dest = try blank()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        compositor.encodeLayer(source: try solid(SIMD3(1, 1, 1)), backdrop: try blank(),
                               destination: dest, opacity: 0.5, mode: .normal, in: cb)
        cb.commit(); cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: dest, device: device, queue: queue))
        XCTAssertEqual(try XCTUnwrap(TestPixels.meanAlpha(of: readback)), 1.0, accuracy: 0.005)
    }

    // MARK: alpha, mid-chain vs master

    /// A solid colour with an explicit alpha — needed to prove alpha is carried, not invented.
    private func solid(_ rgb: SIMD3<Double>, alpha: Double, size: Int = 16) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat, width: size, height: size,
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: rgb.x, green: rgb.y, blue: rgb.z,
                                                           alpha: alpha)
        rpd.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        return tex
    }

    private func alphaOf(source: MTLTexture, backdrop: MTLTexture, opacity: Double,
                         preserveAlpha: Bool) throws -> Double {
        let dest = try blank()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        compositor.encodeLayer(source: source, backdrop: backdrop, destination: dest,
                               opacity: opacity, mode: .normal,
                               preserveAlpha: preserveAlpha, in: cb)
        cb.commit(); cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: dest, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanAlpha(of: readback))
    }

    func testMidChainMixPreservesAlphaInsteadOfForcingItOpaque() throws {
        // Forcing alpha to 1 is right for the master and WRONG mid-chain: it would silently make
        // any deck carrying an FX stage fully opaque and change how it composites, because layer
        // alpha is src.a * opacity.
        let src = try solid(SIMD3(1, 1, 1), alpha: 0.25)
        let back = try solid(SIMD3(0, 0, 0), alpha: 0.75)
        let mid = try alphaOf(source: src, backdrop: back, opacity: 1.0, preserveAlpha: true)
        XCTAssertEqual(mid, 0.25, accuracy: 0.01, "fully wet ⇒ the stage's own alpha")

        let dry = try alphaOf(source: src, backdrop: back, opacity: 0.0, preserveAlpha: true)
        XCTAssertEqual(dry, 0.75, accuracy: 0.01, "fully dry ⇒ the input's alpha, untouched")
    }

    func testTheMasterPathStillForcesAlphaOpaque() throws {
        let a = try alphaOf(source: try solid(SIMD3(1, 1, 1), alpha: 0.25),
                            backdrop: try solid(SIMD3(0, 0, 0), alpha: 0.3),
                            opacity: 0.5, preserveAlpha: false)
        XCTAssertEqual(a, 1.0, accuracy: 0.005,
                       "The master is opaque by contract — a stack that leaks alpha < 1 is how the "
                       + "TouchDesigner blackout gate silently failed")
    }

    func testPreservingAlphaDoesNotChangeTheColourResult() throws {
        // The RGB path must be bit-for-bit the same on both branches; only the alpha out differs.
        let src = try solid(SIMD3(0.75, 0.5, 0.25), alpha: 1.0)
        let back = try solid(SIMD3(0.25, 0.5, 0.75), alpha: 1.0)
        for mode in BlendMode.allCases {
            let dest1 = try blank(), dest2 = try blank()
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            compositor.encodeLayer(source: src, backdrop: back, destination: dest1,
                                   opacity: 0.6, mode: mode, preserveAlpha: false, in: cb)
            compositor.encodeLayer(source: src, backdrop: back, destination: dest2,
                                   opacity: 0.6, mode: mode, preserveAlpha: true, in: cb)
            cb.commit(); cb.waitUntilCompleted()
            let a = try XCTUnwrap(TestPixels.meanRGB(of: try XCTUnwrap(
                TextureReadback.managedCopy(of: dest1, device: device, queue: queue))))
            let b = try XCTUnwrap(TestPixels.meanRGB(of: try XCTUnwrap(
                TextureReadback.managedCopy(of: dest2, device: device, queue: queue))))
            XCTAssertEqual(a.x, b.x, accuracy: 0.005, "\(mode.rawValue) red")
            XCTAssertEqual(a.y, b.y, accuracy: 0.005, "\(mode.rawValue) green")
            XCTAssertEqual(a.z, b.z, accuracy: 0.005, "\(mode.rawValue) blue")
        }
    }
}
