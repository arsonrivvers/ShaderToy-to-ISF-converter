import XCTest
@testable import TrueISFEditor
import ShadertoyISFKit

@MainActor
final class HeaderAuthoringModelTests: XCTestCase {
    private let validSrc = "/*{ \"INPUTS\": [] }*/\nvoid main(){ gl_FragColor = vec4(1.0); }"

    func test_syncFromText_states() {
        let m = HeaderAuthoringModel()
        m.syncFromText(validSrc)
        XCTAssertEqual(m.state, .valid)
        m.syncFromText("void main(){}")
        XCTAssertEqual(m.state, .noHeader)
        m.syncFromText("/*{ bad json }*/\nvoid main(){}")
        XCTAssertEqual(m.state, .malformed)
    }

    func test_guiMutation_emitsRewrite_andHasNoFeedbackLoop() {
        let m = HeaderAuthoringModel()
        var rewrites: [String] = []
        m.onRewrite = { rewrites.append($0) }
        m.syncFromText(validSrc)

        m.update { $0.inputs.append(.makeDefault(type: "float", name: "speed")) }
        XCTAssertEqual(rewrites.count, 1)
        XCTAssertTrue(rewrites[0].contains("\"speed\""))
        XCTAssertEqual(m.header.inputs.map(\.name), ["speed"])
        // GLSL body preserved through the rewrite.
        XCTAssertTrue(rewrites[0].contains("gl_FragColor = vec4(1.0);"))

        // If the host echoed our write back through syncFromText, it must NOT trigger another rewrite.
        m.syncFromText(rewrites[0])
        XCTAssertEqual(rewrites.count, 1)
        XCTAssertEqual(m.header.inputs.map(\.name), ["speed"])
    }

    func test_update_fromNoHeader_insertsHeader() {
        let m = HeaderAuthoringModel()
        var out: String?
        m.onRewrite = { out = $0 }
        m.syncFromText("void main(){ gl_FragColor = vec4(0.0); }")
        XCTAssertEqual(m.state, .noHeader)
        m.update { $0.inputs.append(.makeDefault(type: "bool", name: "flip")) }
        XCTAssertEqual(m.state, .valid)
        XCTAssertTrue(out?.contains("/*{") == true)
        XCTAssertTrue(out?.contains("\"flip\"") == true)
        XCTAssertTrue(out?.contains("gl_FragColor = vec4(0.0);") == true)
    }

    func test_update_refusesToWriteOverMalformed() {
        let m = HeaderAuthoringModel()
        var rewrites = 0
        m.onRewrite = { _ in rewrites += 1 }
        m.syncFromText("/*{ not valid }*/\nvoid main(){}")
        XCTAssertEqual(m.state, .malformed)
        m.update { $0.inputs.append(.makeDefault(type: "float", name: "x")) }
        XCTAssertEqual(rewrites, 0)   // never writes over JSON it couldn't parse
    }

    func test_nameValidation() {
        let m = HeaderAuthoringModel()
        m.syncFromText("/*{ \"INPUTS\": [ {\"NAME\":\"a\",\"TYPE\":\"float\"}, {\"NAME\":\"b\",\"TYPE\":\"float\"} ] }*/\nvoid main(){}")
        XCTAssertTrue(m.nameIsValid("c", atInputIndex: 0))
        XCTAssertTrue(m.nameIsValid("a", atInputIndex: 0))   // unchanged own name is fine
        XCTAssertFalse(m.nameIsValid("b", atInputIndex: 0))  // collides with input 1
        XCTAssertFalse(m.nameIsValid("  ", atInputIndex: 0)) // empty
    }
}
