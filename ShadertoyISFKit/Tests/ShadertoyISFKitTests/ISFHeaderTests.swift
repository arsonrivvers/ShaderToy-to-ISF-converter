import XCTest
@testable import ShadertoyISFKit

final class ISFHeaderTests: XCTestCase {
    private let sample = """
    /*{
      "ISFVSN": "2.0",
      "DESCRIPTION": "demo",
      "CATEGORIES": ["Generator"],
      "INPUTS": [
        { "NAME": "speed", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
        { "NAME": "tint", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] }
      ]
    }*/

    void main() {
        gl_FragColor = vec4(isf_FragNormCoord, 0.0, 1.0);
    }
    """

    // MARK: parse

    func test_parse_extractsInputs() throws {
        let h = try ISFHeader.parse(sample)
        XCTAssertEqual(h.inputs.map(\.name), ["speed", "tint"])
        XCTAssertEqual(h.inputs.map(\.type), ["float", "color"])
    }

    func test_parse_keepsUnmodeledTopLevelKeysInExtra() throws {
        let h = try ISFHeader.parse(sample)
        XCTAssertEqual(h.extra["ISFVSN"], .string("2.0"))
        XCTAssertEqual(h.extra["DESCRIPTION"], .string("demo"))
        XCTAssertEqual(h.extra["CATEGORIES"], .array([.string("Generator")]))
        // INPUTS/PASSES must NOT leak into extra.
        XCTAssertNil(h.extra["INPUTS"])
        XCTAssertNil(h.extra["PASSES"])
    }

    // C3 — a leading license/credit block comment before the ISF header must not defeat detection.
    private let sampleWithLeadingComment = """
    /* MIT License (c) 2021 someone
       see https://example.com (terms apply) */
    /*{
      "ISFVSN": "2.0",
      "INPUTS": [ { "NAME": "speed", "TYPE": "float", "DEFAULT": 0.5 } ]
    }*/

    void main() { gl_FragColor = vec4(1.0); }
    """

    func test_parse_skipsLeadingNonHeaderComment() throws {
        let h = try ISFHeader.parse(sampleWithLeadingComment)
        XCTAssertEqual(h.inputs.map(\.name), ["speed"])
    }

    func test_write_replacesRealHeader_doesNotPrependDuplicate() throws {
        let h = try ISFHeader.parse(sampleWithLeadingComment)
        let out = h.write(into: sampleWithLeadingComment)
        // Exactly one ISF header object (`{` after a `/*`), not two.
        let headerBlocks = out.components(separatedBy: "INPUTS").count - 1
        XCTAssertEqual(headerBlocks, 1, out)
        // The leading license comment is preserved.
        XCTAssertTrue(out.contains("MIT License"), out)
    }

    func test_parse_noHeader_throwsNoHeader() {
        XCTAssertThrowsError(try ISFHeader.parse("void main(){}")) { e in
            XCTAssertEqual(e as? ISFHeaderError, .noHeader)
        }
    }

    func test_parse_malformedJSON_throwsMalformed() {
        let bad = "/*{ \"INPUTS\": [ {oops } }*/\nvoid main(){}"
        XCTAssertThrowsError(try ISFHeader.parse(bad)) { e in
            XCTAssertEqual(e as? ISFHeaderError, .malformed)
        }
    }

    // MARK: round-trip + body preservation

    func test_roundTrip_isStable() throws {
        let h = try ISFHeader.parse(sample)
        let out = h.write(into: sample)
        let h2 = try ISFHeader.parse(out)
        XCTAssertEqual(h, h2)
    }

    func test_write_preservesGLSLBodyByteForByte() throws {
        var h = try ISFHeader.parse(sample)
        h.inputs.append(ISFInput.makeDefault(type: "bool", name: "flip"))
        let out = h.write(into: sample)
        // Everything from `void main()` onward must be identical.
        let bodyStart = sample.range(of: "void main()")!.lowerBound
        let origBody = String(sample[bodyStart...])
        let outBodyStart = out.range(of: "void main()")!.lowerBound
        XCTAssertEqual(String(out[outBodyStart...]), origBody)
    }

    func test_write_unknownPerInputKeyPreserved() throws {
        let src = """
        /*{ "INPUTS": [ { "NAME": "k", "TYPE": "float", "DEFAULT": 0, "IDENTITY": true } ] }*/
        void main(){}
        """
        let h = try ISFHeader.parse(src)
        let out = h.write(into: src)
        let h2 = try ISFHeader.parse(out)
        XCTAssertEqual(h2.inputs.first?.attributes["IDENTITY"], .bool(true))
    }

    func test_write_noHeader_insertsOne() {
        let src = "void main(){ gl_FragColor = vec4(1.0); }"
        var h = ISFHeader.empty
        h.inputs.append(ISFInput.makeDefault(type: "float", name: "speed"))
        let out = h.write(into: src)
        XCTAssertTrue(out.contains("/*{"))
        XCTAssertTrue(out.contains("\"speed\""))
        XCTAssertTrue(out.hasSuffix("void main(){ gl_FragColor = vec4(1.0); }"))
        XCTAssertNoThrow(try ISFHeader.parse(out))
    }

    // MARK: passes

    func test_passes_typedAccessors_roundTrip() throws {
        let src = """
        /*{ "INPUTS": [], "PASSES": [ { "TARGET": "bufA", "PERSISTENT": true, "FLOAT": true }, {} ] }*/
        void main(){}
        """
        let h = try ISFHeader.parse(src)
        XCTAssertEqual(h.passes.count, 2)
        XCTAssertEqual(h.passes[0].target, "bufA")
        XCTAssertTrue(h.passes[0].persistent)
        XCTAssertTrue(h.passes[0].float)
        XCTAssertNil(h.passes[1].target)
        // mutate + round-trip
        var m = h
        m.passes[1].target = "bufB"
        let h2 = try ISFHeader.parse(m.write(into: src))
        XCTAssertEqual(h2.passes[1].target, "bufB")
    }

    func test_emptyPasses_notEmittedAsKey() throws {
        let h = try ISFHeader.parse(sample) // no PASSES
        XCTAssertFalse(h.write(into: sample).contains("PASSES"))
    }

    // MARK: input factory

    func test_makeDefault_seedsTypeAppropriateFields() {
        let f = ISFInput.makeDefault(type: "float", name: "amount")
        XCTAssertEqual(f.type, "float")
        XCTAssertNotNil(f.attributes["DEFAULT"])
        XCTAssertNotNil(f.attributes["MIN"])
        XCTAssertNotNil(f.attributes["MAX"])

        let img = ISFInput.makeDefault(type: "image", name: "inputImage")
        XCTAssertNil(img.attributes["MIN"]) // image has no range
    }
}
