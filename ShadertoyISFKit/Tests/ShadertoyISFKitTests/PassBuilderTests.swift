import XCTest
@testable import ShadertoyISFKit

final class PassBuilderTests: XCTestCase {
    private func pass(_ type: PassType, _ name: String, outID: String) -> RenderPass {
        RenderPass(inputs: [], outputs: [PassOutput(id: outID, channel: 0)],
                   code: "void mainImage(out vec4 c, in vec2 f){c=vec4(0.0);}", name: name, type: type)
    }

    func test_ordersBuffersThenImage() {
        let plan = PassBuilder.build(passes: [
            pass(.image, "Image", outID: "img"),
            pass(.buffer, "Buffer A", outID: "a"),
        ])
        XCTAssertEqual(plan.orderedPassNames, ["Buffer A", "Image"])
        XCTAssertEqual(plan.bufferOutputIDToName["a"], "bufA")
    }

    func test_extractsCommon() {
        var common = pass(.common, "Common", outID: "c")
        common = RenderPass(inputs: [], outputs: [], code: "#define PI 3.14", name: "Common", type: .common)
        let plan = PassBuilder.build(passes: [common, pass(.image, "Image", outID: "img")])
        XCTAssertEqual(plan.commonCode, "#define PI 3.14")
        XCTAssertEqual(plan.orderedPassNames, ["Image"])
    }

    func test_orderedBufferNames_matchBodyMapping() {
        // The ordered buffer names are the single source of truth — header PASSES TARGETs and the
        // sampler names in the body both derive from these, so they can never diverge.
        let plan = PassBuilder.build(passes: [
            pass(.buffer, "Buffer A", outID: "a"),
            pass(.buffer, "Buffer B", outID: "b"),
            pass(.buffer, "Buffer C", outID: "c"),
            pass(.buffer, "Buffer D", outID: "d"),
            pass(.image, "Image", outID: "img"),
        ])
        XCTAssertEqual(plan.orderedBufferNames, ["bufA", "bufB", "bufC", "bufD"])
        XCTAssertEqual(plan.bufferOutputIDToName["c"], "bufC")
    }

    func test_soundPass_warnsAndSkips() {
        let plan = PassBuilder.build(passes: [
            pass(.sound, "Sound", outID: "s"),
            pass(.image, "Image", outID: "img"),
        ])
        XCTAssertEqual(plan.orderedPassNames, ["Image"])
        XCTAssertTrue(plan.warnings.contains { $0.message.contains("Sound") })
    }
}
