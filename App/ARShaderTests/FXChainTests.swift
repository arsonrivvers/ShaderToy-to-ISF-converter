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
}
