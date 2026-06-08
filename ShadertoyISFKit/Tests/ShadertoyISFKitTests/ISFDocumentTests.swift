import XCTest
@testable import ShadertoyISFKit

final class ISFDocumentTests: XCTestCase {
    func test_serialize_wrapsHeaderAndAppendsBody() {
        let doc = ISFDocument(headerJSON: "{\n  \"ISFVSN\" : \"2.0\"\n}", glslBody: "void main() {}")
        let text = doc.fileText
        XCTAssertTrue(text.hasPrefix("/*{"))
        XCTAssertTrue(text.contains("\"ISFVSN\""))
        XCTAssertTrue(text.contains("}*/"))
        XCTAssertTrue(text.contains("void main() {}"))
        // header must come before body
        XCTAssertLessThan(text.range(of: "}*/")!.lowerBound, text.range(of: "void main")!.lowerBound)
    }
}
