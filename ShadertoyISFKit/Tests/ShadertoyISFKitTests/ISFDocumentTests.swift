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

    func test_serialize_escapesLiteralCommentTerminatorsWithoutChangingMetadata() throws {
        let original = "one */ two */ three"
        let doc = ISFDocument(
            headerJSON: #"{"DESCRIPTION":"one */ two */ three"}"#,
            glslBody: "void main() {}")

        let text = doc.fileText
        XCTAssertEqual(text.components(separatedBy: "*/").count - 1, 1,
                       "only the final ISF wrapper terminator may remain literal")

        let headerStart = try XCTUnwrap(text.range(of: "/*")).upperBound
        let headerEnd = try XCTUnwrap(text.range(of: "*/")).lowerBound
        let encoded = String(text[headerStart..<headerEnd])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        XCTAssertEqual(object["DESCRIPTION"] as? String, original)
    }

    func test_serialize_doesNotDoubleEscapeAlreadySafeJSON() {
        let doc = ISFDocument(
            headerJSON: #"{"DESCRIPTION":"already *\/ safe"}"#,
            glslBody: "void main() {}")

        XCTAssertTrue(doc.fileText.contains(#""DESCRIPTION":"already *\/ safe""#))
        XCTAssertFalse(doc.fileText.contains(#"*\\/"#),
                       "an already escaped slash must not gain a second backslash")
    }
}
