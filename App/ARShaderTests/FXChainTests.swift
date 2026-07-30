import XCTest
import Metal

@MainActor
final class FXChainTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var chain: FXChain!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        chain = FXChain()
    }

    private func makeStage() -> FXStage {
        FXStage(device: device, queue: queue, clock: RenderClock())
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "fs", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A stage whose shader is compiled and ready.
    private func loadedStage(_ fixtureName: String) throws -> FXStage {
        let stage = makeStage()
        let done = expectation(description: "compile \(fixtureName)")
        stage.unit.onCompileFinished = { done.fulfill() }
        stage.unit.load(source: try fixture(fixtureName), name: "\(fixtureName).fs")
        wait(for: [done], timeout: 30)
        stage.unit.onCompileFinished = nil
        XCTAssertNil(stage.unit.compileError, "fixture \(fixtureName) must compile")
        return stage
    }

    func testAFilterStageLeavesItsPrimaryInputUnrouted() throws {
        // A stage must not open a camera session for an input the chain already drives.
        let stage = try loadedStage("invert_filter")
        XCTAssertEqual(stage.unit.imageSources.selection(for: "inputImage"), .none,
                       "the chain feeds this input; the router must not claim it")
    }

    func testAnEmptyChainPublishesNoRenderStages() {
        XCTAssertTrue(chain.renderStages().isEmpty)
    }

    func testAppendingAStagePublishesItToTheRenderThread() {
        chain.append(makeStage())
        XCTAssertEqual(chain.stages.count, 1)
        XCTAssertEqual(chain.renderStages().count, 1)
    }

    func testDisablingAStageWithdrawsItFromTheRenderThread() {
        let s = makeStage()
        chain.append(s)
        chain.setEnabled(false, for: s)
        XCTAssertEqual(chain.stages.count, 1, "it stays in the UI list")
        XCTAssertTrue(chain.renderStages().isEmpty, "but encodes nothing at all")
    }

    func testAZeroMixStageWithdrawsItselfToo() {
        let s = makeStage()
        chain.append(s)
        chain.setMix(0, for: s)
        XCTAssertTrue(chain.renderStages().isEmpty,
                      "paying for an invisible pass mid-set is worse than skipping it")
    }

    func testMixClampsToTheUnitInterval() {
        let s = makeStage()
        chain.append(s)
        chain.setMix(4.2, for: s)
        XCTAssertEqual(s.mix, 1.0)
        chain.setMix(-3, for: s)
        XCTAssertEqual(s.mix, 0.0)
    }

    func testRemoveDropsExactlyOneStage() {
        let a = makeStage(), b = makeStage()
        chain.append(a); chain.append(b)
        chain.remove(a.id)
        XCTAssertEqual(chain.stages.map(\.id), [b.id])
        XCTAssertEqual(chain.renderStages().count, 1)
    }

    func testMoveUpAndDownReorderAndClampAtTheEnds() {
        let a = makeStage(), b = makeStage()
        chain.append(a); chain.append(b)
        chain.moveUp(1)
        XCTAssertEqual(chain.stages.map(\.id), [b.id, a.id])
        chain.moveUp(0)
        XCTAssertEqual(chain.stages.map(\.id), [b.id, a.id], "already first — a no-op, not a crash")
        chain.moveDown(1)
        XCTAssertEqual(chain.stages.map(\.id), [b.id, a.id], "already last — a no-op")
        chain.moveDown(0)
        XCTAssertEqual(chain.stages.map(\.id), [a.id, b.id])
    }

    func testRenderOrderMatchesTheUIOrderAfterAReorder() {
        let a = makeStage(), b = makeStage()
        chain.append(a); chain.append(b)
        chain.moveUp(1)
        XCTAssertEqual(chain.renderStages().map { ObjectIdentifier($0.core) },
                       [ObjectIdentifier(b.unit.core), ObjectIdentifier(a.unit.core)],
                       "the render mirror must be republished on reorder, not just on append")
    }

    // MARK: encoding

    private func texture(_ rgb: SIMD3<Double>) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: InstrumentRenderer.masterFormat, width: 64, height: 64, mipmapped: false)
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
        cb.commit(); cb.waitUntilCompleted()
        return tex
    }

    /// Run the chain over a solid input and read the mean colour of whatever it returns.
    private func runChain(input rgb: SIMD3<Double>) throws -> SIMD3<Double> {
        let input = try texture(rgb)
        let scratch = try texture(SIMD3(0, 0, 0))
        let compositor = try XCTUnwrap(Compositor(device: device))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let out = chain.encode(input: input, scratch: scratch,
                               renderSize: MTLSize(width: 64, height: 64, depth: 1),
                               compositor: compositor, preserveAlpha: true, in: cb)
        cb.commit(); cb.waitUntilCompleted()
        let readback = try XCTUnwrap(
            TextureReadback.managedCopy(of: out, device: device, queue: queue))
        return try XCTUnwrap(TestPixels.meanRGB(of: readback))
    }

    func testAnEmptyChainReturnsItsInputUntouched() throws {
        let out = try runChain(input: SIMD3(0.8, 0.2, 0.4))
        XCTAssertEqual(out.x, 0.8, accuracy: 0.02)
        XCTAssertEqual(out.y, 0.2, accuracy: 0.02)
        XCTAssertEqual(out.z, 0.4, accuracy: 0.02)
    }

    func testAStageReadsTheChainFeedNotItsRoutedSources() throws {
        // Without an explicit primary input, MetalRenderCore binds EVERY image input from the
        // SourceRouter — so `inputImage` would be the camera and the chain feed would never
        // reach the shader. Inverting a known red input is the cheapest proof it arrived.
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.y, 1.0, accuracy: 0.03,
                       "the stage must invert the CHAIN input, not a routed camera frame")
    }

    func testOneStageTransformsTheImage() throws {
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.x, 0.0, accuracy: 0.03, "red inverted is cyan")
        XCTAssertEqual(out.y, 1.0, accuracy: 0.03)
        XCTAssertEqual(out.z, 1.0, accuracy: 0.03)
    }

    func testTwoStagesApplyInOrderAndTheParityIsRight() throws {
        // Invert twice returns the original. This is the ping-pong parity test: if the swap is
        // wrong, an even-depth chain returns the wrong texture and this fails.
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(0.8, 0.2, 0.4))
        XCTAssertEqual(out.x, 0.8, accuracy: 0.03)
        XCTAssertEqual(out.y, 0.2, accuracy: 0.03)
        XCTAssertEqual(out.z, 0.4, accuracy: 0.03)
    }

    func testOddDepthAlsoReturnsTheRightTexture() throws {
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("invert_filter"))
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.y, 1.0, accuracy: 0.03, "three inverts is one invert")
    }

    func testADisabledStageIsSkippedEntirely() throws {
        let s = try loadedStage("invert_filter")
        chain.append(s)
        chain.setEnabled(false, for: s)
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.x, 1.0, accuracy: 0.03, "still red — the stage never ran")
    }

    func testMixHalfSitsBetweenDryAndWet() throws {
        let s = try loadedStage("invert_filter")
        chain.append(s)
        chain.setMix(0.5, for: s)
        let out = try runChain(input: SIMD3(1, 0, 0))
        XCTAssertEqual(out.x, 0.5, accuracy: 0.04, "halfway between red and cyan")
        XCTAssertEqual(out.y, 0.5, accuracy: 0.04)
    }

    func testStageBlendModeApplies() throws {
        // Multiply against its own input: 0.5 * 0.5 = 0.25 on every channel.
        let s = try loadedStage("half_bright_filter")
        chain.append(s)
        chain.setBlendMode(.multiply, for: s)
        let out = try runChain(input: SIMD3(1, 1, 1))
        XCTAssertEqual(out.x, 0.5, accuracy: 0.04)
    }

    func testReorderingChangesTheResultForANonCommutativePair() throws {
        chain.append(try loadedStage("invert_filter"))
        chain.append(try loadedStage("half_bright_filter"))
        let first = try runChain(input: SIMD3(1, 0, 0))   // invert → (0,1,1), half → (0,0.5,0.5)
        chain.moveUp(1)
        let swapped = try runChain(input: SIMD3(1, 0, 0)) // half → (0.5,0,0), invert → (0.5,1,1)
        XCTAssertNotEqual(first.x, swapped.x, accuracy: 0.05,
                          "order must be real, not decorative")
    }
}
