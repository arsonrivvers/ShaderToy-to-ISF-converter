import XCTest
@testable import ShadertoyISFKit

final class ChannelBindingTests: XCTestCase {
    func test_textureChannel_becomesImageInput() {
        let input = PassInput(id: "tex0", ctype: .texture, channel: 0)
        let map = ChannelBinding.resolve(inputs: [input], bufferOutputIDToName: [:])
        XCTAssertEqual(map.bindings[0]?.glslName, "iChannel0img")
        XCTAssertEqual(map.bindings[0]?.kind, .texture)
        XCTAssertTrue(map.warnings.isEmpty)
    }

    func test_bufferChannel_resolvesToBufferName() {
        let input = PassInput(id: "bufAout", ctype: .buffer, channel: 0)
        let map = ChannelBinding.resolve(inputs: [input],
                                         bufferOutputIDToName: ["bufAout": "bufA"])
        XCTAssertEqual(map.bindings[0]?.glslName, "bufA")
        XCTAssertEqual(map.bindings[0]?.kind, .buffer)
    }

    func test_unsupportedChannel_warnsAndStubsImage() {
        let input = PassInput(id: "kb", ctype: .keyboard, channel: 1)
        let map = ChannelBinding.resolve(inputs: [input], bufferOutputIDToName: [:])
        XCTAssertEqual(map.bindings[1]?.kind, .unsupported)
        XCTAssertEqual(map.warnings.count, 1)
        XCTAssertEqual(map.warnings[0].severity, .warning)
    }
}
