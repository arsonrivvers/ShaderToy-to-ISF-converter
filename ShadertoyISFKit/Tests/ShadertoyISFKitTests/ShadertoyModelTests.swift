import XCTest
@testable import ShadertoyISFKit

final class ShadertoyModelTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        return try Data(contentsOf: try XCTUnwrap(url))
    }

    func test_decode_singlePass() throws {
        let data = try loadFixture("single_pass")
        let resp = try JSONDecoder().decode(ShadertoyResponse.self, from: data)
        XCTAssertEqual(resp.shader.info.name, "Test Single")
        XCTAssertEqual(resp.shader.renderpass.count, 1)
        XCTAssertEqual(resp.shader.renderpass[0].type, .image)
        XCTAssertTrue(resp.shader.renderpass[0].code.contains("mainImage"))
    }

    func test_decode_multipass_inputsAndOutputs() throws {
        let data = try loadFixture("multipass_feedback")
        let resp = try JSONDecoder().decode(ShadertoyResponse.self, from: data)
        XCTAssertEqual(resp.shader.renderpass.count, 2)
        let bufA = resp.shader.renderpass[0]
        XCTAssertEqual(bufA.type, .buffer)
        XCTAssertEqual(bufA.outputs.first?.id, "bufAout")
        XCTAssertEqual(bufA.inputs.first?.ctype, .buffer)
        XCTAssertEqual(bufA.inputs.first?.channel, 0)
    }
}
