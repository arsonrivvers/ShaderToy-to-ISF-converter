import XCTest
@testable import ShadertoyISFKit

final class HeaderBuilderTests: XCTestCase {
    func test_singlePass_noBuffers_noInputs() throws {
        let json = HeaderBuilder.build(description: "d", credit: "by tester",
            imageInputNames: [], includeMouse: false, bufferNames: [])
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(obj["ISFVSN"] as? String, "2.0")
        XCTAssertNil(obj["PASSES"])   // single pass: omit PASSES entirely
        XCTAssertEqual((obj["INPUTS"] as? [Any])?.count ?? 0, 0)
    }

    func test_image_and_mouse_inputs() throws {
        let json = HeaderBuilder.build(description: "d", credit: "c",
            imageInputNames: ["iChannel0img"], includeMouse: true, bufferNames: [])
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let inputs = obj["INPUTS"] as! [[String: Any]]
        XCTAssertTrue(inputs.contains { $0["NAME"] as? String == "iChannel0img" && $0["TYPE"] as? String == "image" })
        XCTAssertTrue(inputs.contains { $0["NAME"] as? String == "mouse" && $0["TYPE"] as? String == "point2D" })
    }

    func test_mouseInput_defaultsToCentered_soItIsEngagedAtRest() throws {
        // iMouse.z maps from mouse.x; a [0,0] default leaves mouse-gated shaders
        // (e.g. `if(iMouse.z < 0.01) ...`) permanently disengaged. Centered keeps z > 0.
        let json = HeaderBuilder.build(description: "d", credit: "c",
            imageInputNames: [], includeMouse: true, bufferNames: [])
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let inputs = obj["INPUTS"] as! [[String: Any]]
        let mouse = try XCTUnwrap(inputs.first { $0["NAME"] as? String == "mouse" })
        let def = try XCTUnwrap(mouse["DEFAULT"] as? [Double])
        XCTAssertEqual(def, [0.5, 0.5])
    }

    func test_buffers_producePersistentFloatPasses_plusFinalEmpty() throws {
        let json = HeaderBuilder.build(description: "d", credit: "c",
            imageInputNames: [], includeMouse: false, bufferNames: ["bufA", "bufB"])
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let passes = obj["PASSES"] as! [[String: Any]]
        XCTAssertEqual(passes.count, 3)
        XCTAssertEqual(passes[0]["TARGET"] as? String, "bufA")
        XCTAssertEqual(passes[0]["PERSISTENT"] as? Bool, true)
        XCTAssertEqual(passes[0]["FLOAT"] as? Bool, true)
        XCTAssertNil(passes[2]["TARGET"])   // final empty pass
    }
}
