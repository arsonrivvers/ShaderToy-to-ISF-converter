import XCTest
@testable import TrueISFEditor

final class RemixComparisonCoordinatorTests: XCTestCase {
    private func isf(_ inputs: [[String: String]]) -> String {
        let data = try! JSONSerialization.data(
            withJSONObject: ["ISFVSN": "2.0", "INPUTS": inputs],
            options: [.sortedKeys]
        )
        return "/*\(String(decoding: data, as: UTF8.self))*/\nvoid main(){}"
    }

    private func isfWithDefaults(_ inputs: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(
            withJSONObject: ["ISFVSN": "2.0", "INPUTS": inputs],
            options: [.sortedKeys]
        )
        return "/*\(String(decoding: data, as: UTF8.self))*/\nvoid main(){}"
    }

    func test_twoUp_usesOneSharedClockAndResolution() {
        var time = 10.0
        let coordinator = RemixComparisonCoordinator(nowSource: { time })
        coordinator.setRenderSize(width: 1280, height: 720)
        time = 12.5

        XCTAssertTrue(coordinator.clock === coordinator.clockForPreview("left"))
        XCTAssertTrue(coordinator.clock === coordinator.clockForPreview("right"))
        XCTAssertEqual(coordinator.renderSize, RemixRenderSize(width: 1280, height: 720))
        XCTAssertEqual(coordinator.clock.now, 2.5, accuracy: 0.001)
    }

    func test_compatibleInputs_propagateToBothPreviews() {
        let sourceA = isf([["NAME": "gain", "TYPE": "float"]])
        let sourceB = isf([["NAME": "gain", "TYPE": "float"]])
        let coordinator = RemixComparisonCoordinator()

        coordinator.configure(leftISF: sourceA, rightISF: sourceB)
        coordinator.setSharedValue(.float(0.75), for: "gain")

        XCTAssertEqual(coordinator.value(for: "gain", previewID: "left"), .float(0.75))
        XCTAssertEqual(coordinator.value(for: "gain", previewID: "right"), .float(0.75))
        XCTAssertEqual(coordinator.valuesForRenderer("left"), ["gain": .float(0.75)])
        XCTAssertEqual(coordinator.valuesForRenderer("right"), ["gain": .float(0.75)])
    }

    func test_incompatibleInputs_areReportedAndRemainPerChild() {
        let sourceA = isf([["NAME": "gain", "TYPE": "float"]])
        let sourceB = isf([["NAME": "gain", "TYPE": "bool"]])
        let coordinator = RemixComparisonCoordinator()

        coordinator.configure(leftISF: sourceA, rightISF: sourceB)
        coordinator.setValue(.float(0.25), for: "gain", previewID: "left")
        coordinator.setValue(.bool(true), for: "gain", previewID: "right")

        XCTAssertEqual(coordinator.value(for: "gain", previewID: "left"), .float(0.25))
        XCTAssertEqual(coordinator.value(for: "gain", previewID: "right"), .bool(true))
        XCTAssertEqual(
            coordinator.incompatibilityExplanation(for: "gain"),
            "gain stays per child because its types differ: float and bool."
        )
        XCTAssertEqual(coordinator.valuesForRenderer("left"), ["gain": .float(0.25)])
        XCTAssertEqual(coordinator.valuesForRenderer("right"), ["gain": .bool(true)])
    }

    func test_inputPresentInOnlyOneChildIsIncompatibleAndExplained() {
        let coordinator = RemixComparisonCoordinator()
        coordinator.configure(
            leftISF: isf([["NAME": "gain", "TYPE": "float"]]),
            rightISF: isf([])
        )

        XCTAssertEqual(coordinator.incompatibleInputNames, ["gain"])
        XCTAssertEqual(
            coordinator.incompatibilityExplanation(for: "gain"),
            "gain stays per child because it is only available in the left child."
        )
    }

    func test_typedParameterValuesProduceRendererJSON() {
        XCTAssertEqual(RemixParameterValue.float(0.75).rendererJSON, "0.75")
        XCTAssertEqual(RemixParameterValue.bool(true).rendererJSON, "true")
        XCTAssertEqual(RemixParameterValue.point(0.2, 0.4).rendererJSON, "[0.2,0.4]")
    }

    func test_configureSeedsCanonicalSharedDefaultsUsingISFTypes() {
        let left = isfWithDefaults([
            ["NAME": "gain", "TYPE": "float", "DEFAULT": 0.25],
            ["NAME": "enabled", "TYPE": "bool", "DEFAULT": true],
            ["NAME": "count", "TYPE": "long"],
            ["NAME": "origin", "TYPE": "point2D", "DEFAULT": [0.2, 0.4]],
            ["NAME": "tint", "TYPE": "color", "DEFAULT": [1.0, 0.5, 0.25, 1.0]],
        ])
        let right = isfWithDefaults([
            ["NAME": "gain", "TYPE": "float", "DEFAULT": 0.9],
            ["NAME": "enabled", "TYPE": "bool", "DEFAULT": false],
            ["NAME": "count", "TYPE": "long", "DEFAULT": 8],
            ["NAME": "origin", "TYPE": "point2D", "DEFAULT": [0.8, 0.9]],
            ["NAME": "tint", "TYPE": "color", "DEFAULT": [0.0, 0.0, 0.0, 1.0]],
        ])
        let coordinator = RemixComparisonCoordinator()
        coordinator.configure(leftISF: left, rightISF: right)

        XCTAssertEqual(coordinator.value(for: "gain", previewID: "left"), .float(0.25))
        XCTAssertEqual(coordinator.value(for: "enabled", previewID: "right"), .bool(true))
        XCTAssertEqual(coordinator.value(for: "count", previewID: "left"), .integer(0))
        XCTAssertEqual(coordinator.value(for: "origin", previewID: "right"), .point(0.2, 0.4))
        XCTAssertEqual(coordinator.value(for: "tint", previewID: "left"), .color(1, 0.5, 0.25, 1))
    }

    func test_supportedControlKindsNeverTreatEventOrImageAsFloat() {
        XCTAssertEqual(RemixComparisonCoordinator.controlKind(for: "bool"), .bool)
        XCTAssertEqual(RemixComparisonCoordinator.controlKind(for: "float"), .float)
        XCTAssertEqual(RemixComparisonCoordinator.controlKind(for: "long"), .long)
        XCTAssertEqual(RemixComparisonCoordinator.controlKind(for: "point2D"), .point2D)
        XCTAssertEqual(RemixComparisonCoordinator.controlKind(for: "color"), .color)
        XCTAssertEqual(
            RemixComparisonCoordinator.controlKind(for: "event"),
            .unsupported("Events are momentary and stay per child.")
        )
        XCTAssertEqual(
            RemixComparisonCoordinator.controlKind(for: "image"),
            .unsupported("Image sources stay per child.")
        )
    }

    func test_pauseAndReset_applyAtomicallyToBothPreviews() {
        var time = 20.0
        let coordinator = RemixComparisonCoordinator(nowSource: { time })
        time = 23.0
        coordinator.setPaused(true)
        time = 30.0
        XCTAssertEqual(coordinator.clockForPreview("left").now, 3, accuracy: 0.001)
        XCTAssertEqual(coordinator.clockForPreview("right").now, 3, accuracy: 0.001)

        coordinator.resetTime()
        XCTAssertEqual(coordinator.clockForPreview("left").now, 0, accuracy: 0.001)
        XCTAssertEqual(coordinator.clockForPreview("right").now, 0, accuracy: 0.001)
    }
}
