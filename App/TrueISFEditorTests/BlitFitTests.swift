import XCTest
import Metal

/// Aspect-fit math for the preview display pass (A3). Pure; no Metal device needed.
final class BlitFitTests: XCTestCase {
    // MARK: scale (letterbox/pillarbox NDC factors)

    func test_scale_equalAspect_isUnity() {
        let s = BlitFit.scale(textureSize: MTLSize(width: 640, height: 480, depth: 1),
                              drawableSize: CGSize(width: 1280, height: 960))
        XCTAssertEqual(s.x, 1, accuracy: 0.001)
        XCTAssertEqual(s.y, 1, accuracy: 0.001)
    }

    func test_scale_wideView_pillarboxes() {
        // 4:3 texture into a wider 16:9 view → bars left/right: x < 1, y == 1.
        let s = BlitFit.scale(textureSize: MTLSize(width: 640, height: 480, depth: 1),
                              drawableSize: CGSize(width: 1600, height: 900))
        XCTAssertLessThan(s.x, 1.0)
        XCTAssertEqual(s.y, 1, accuracy: 0.001)
    }

    func test_scale_tallView_letterboxes() {
        // 4:3 texture into a tall view → bars top/bottom: x == 1, y < 1.
        let s = BlitFit.scale(textureSize: MTLSize(width: 640, height: 480, depth: 1),
                              drawableSize: CGSize(width: 480, height: 640))
        XCTAssertEqual(s.x, 1, accuracy: 0.001)
        XCTAssertLessThan(s.y, 1.0)
    }

    func test_scale_degenerateSizes_areSafe() {
        let s = BlitFit.scale(textureSize: MTLSize(width: 0, height: 0, depth: 1),
                              drawableSize: CGSize(width: 0, height: 0))
        XCTAssertEqual(s.x, 1, accuracy: 0.001)
        XCTAssertEqual(s.y, 1, accuracy: 0.001)
    }

    // MARK: inscribe (largest aspect-correct rect inside a drawable)

    func test_inscribe_wideDrawable_isHeightLimited() {
        // 4:3 into 1600x900 → height-limited 1200x900.
        let sz = BlitFit.inscribe(aspect: 4.0 / 3.0, in: CGSize(width: 1600, height: 900))
        XCTAssertEqual(sz.height, 900)
        XCTAssertEqual(sz.width, 1200)
    }

    func test_inscribe_tallDrawable_isWidthLimited() {
        // 4:3 into 480x640 → width-limited 480x360.
        let sz = BlitFit.inscribe(aspect: 4.0 / 3.0, in: CGSize(width: 480, height: 640))
        XCTAssertEqual(sz.width, 480)
        XCTAssertEqual(sz.height, 360)
    }

    func test_inscribe_clampsToAtLeastOne() {
        let sz = BlitFit.inscribe(aspect: 4.0 / 3.0, in: CGSize(width: 0, height: 0))
        XCTAssertGreaterThanOrEqual(sz.width, 1)
        XCTAssertGreaterThanOrEqual(sz.height, 1)
    }
}
