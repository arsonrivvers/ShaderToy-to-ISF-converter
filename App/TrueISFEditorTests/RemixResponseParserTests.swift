import XCTest
@testable import TrueISFEditor

final class RemixResponseParserTests: XCTestCase {
    func test_extracts_fencedGLSLBlock() {
        let out = "Here you go:\n```glsl\n/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }\n```\nDone."
        let isf = RemixResponseParser.extractISF(out)
        XCTAssertEqual(isf, "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(1.0); }")
    }
    func test_extracts_rawHeaderToEnd_whenNoFence() {
        let out = "/*{ \"ISFVSN\":\"2.0\" }*/\nvoid main(){ gl_FragColor=vec4(0.0); }"
        XCTAssertEqual(RemixResponseParser.extractISF(out), out)
    }
    func test_returnsNil_whenNoISF() {
        XCTAssertNil(RemixResponseParser.extractISF("I couldn't do that."))
    }
}
