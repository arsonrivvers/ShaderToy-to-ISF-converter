import XCTest
@testable import TrueISFEditor

final class CaptureInputPlanTests: XCTestCase {
    func testEmptyObjectIsAnEmptyPlan() {
        switch CaptureInputPlan.parse(json: "{}", known: ["a"]) {
        case .success(let plan): XCTAssertTrue(plan.isEmpty)
        case .failure(let e): XCTFail("expected empty plan, got \(e)")
        }
    }

    func testFloatValueBecomesAFloatFragment() {
        switch CaptureInputPlan.parse(json: "{\"photic\":1.0}", known: ["photic"]) {
        case .success(let plan):
            XCTAssertEqual(plan.count, 1)
            XCTAssertEqual(plan[0].name, "photic")
            // Must round-trip as a floating-point fragment: an integer fragment routes to
            // ISFMSLSceneVal.create(withLong:) and silently sets the wrong value type.
            XCTAssertTrue(plan[0].jsonValue.contains("."), "got \(plan[0].jsonValue)")
            XCTAssertEqual(Double(plan[0].jsonValue), 1.0)
        case .failure(let e): XCTFail("unexpected failure \(e)")
        }
    }

    func testBoolValueBecomesABoolFragment() {
        switch CaptureInputPlan.parse(json: "{\"invertPage\":true}", known: ["invertPage"]) {
        case .success(let plan): XCTAssertEqual(plan[0].jsonValue, "true")
        case .failure(let e): XCTFail("unexpected failure \(e)")
        }
    }

    /// The whole reason this is a typed guard: a mistyped input name would otherwise leave the
    /// shader at its DEFAULT and the screening would report on a state nobody performs in.
    func testUnknownNameFailsAndNamesTheOffender() {
        switch CaptureInputPlan.parse(json: "{\"phottic\":1.0}", known: ["photic"]) {
        case .success: XCTFail("an unknown input name must not be silently ignored")
        case .failure(let e): XCTAssertTrue(e.contains("phottic"), "error must name it: \(e)")
        }
    }

    func testUnknownNameFailsEvenWhenOtherNamesAreValid() {
        switch CaptureInputPlan.parse(json: "{\"photic\":1.0,\"nope\":0.0}", known: ["photic"]) {
        case .success: XCTFail("a partially valid map must still fail")
        case .failure(let e): XCTAssertTrue(e.contains("nope"))
        }
    }

    func testMalformedJSONFails() {
        switch CaptureInputPlan.parse(json: "{\"photic\":", known: ["photic"]) {
        case .success: XCTFail("malformed JSON must fail")
        case .failure(let e): XCTAssertFalse(e.isEmpty)
        }
    }

    func testNonObjectJSONFails() {
        switch CaptureInputPlan.parse(json: "[1,2,3]", known: ["photic"]) {
        case .success: XCTFail("a non-object must fail")
        case .failure(let e): XCTAssertFalse(e.isEmpty)
        }
    }

    func testPlanIsOrderedByNameForReproducibleLogs() {
        switch CaptureInputPlan.parse(json: "{\"b\":1.0,\"a\":2.0}", known: ["a", "b"]) {
        case .success(let plan): XCTAssertEqual(plan.map(\.name), ["a", "b"])
        case .failure(let e): XCTFail("unexpected failure \(e)")
        }
    }
}
