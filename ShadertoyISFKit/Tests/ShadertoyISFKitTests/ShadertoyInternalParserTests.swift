import XCTest
@testable import ShadertoyISFKit

final class ShadertoyInternalParserTests: XCTestCase {
    private func fixture(_ n: String) throws -> Data {
        let url = Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Fixtures")
        return try Data(contentsOf: try XCTUnwrap(url))
    }

    func test_parsesArrayResponse_toFirstShader() throws {
        let shader = try ShadertoyInternalParser.parse(try fixture("internal_seascape"))
        XCTAssertEqual(shader.info.name, "Seascape")
        XCTAssertEqual(shader.renderpass.count, 1)
        XCTAssertEqual(shader.renderpass[0].type, .image)
    }

    func test_emptyArray_throwsNotFound() {
        let data = Data("[]".utf8)
        XCTAssertThrowsError(try ShadertoyInternalParser.parse(data)) { error in
            XCTAssertEqual(error as? ShadertoyInternalParserError, .shaderNotFound)
        }
    }

    func test_errorObject_throwsNotFound() {
        // Internal endpoint sometimes returns an error object instead of an array.
        let data = Data(#"{"Error":"Shader not found"}"#.utf8)
        XCTAssertThrowsError(try ShadertoyInternalParser.parse(data)) { error in
            XCTAssertEqual(error as? ShadertoyInternalParserError, .shaderNotFound)
        }
    }
}
