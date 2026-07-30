import XCTest

/// Expected values are computed by hand from the W3C Compositing and Blending Level 1 formulas
/// (§blending, separable blend modes). No implementation was consulted.
final class BlendMathTests: XCTestCase {
    private let acc = 1e-9

    func testNormalReturnsTheSource() {
        XCTAssertEqual(BlendMath.blend(.normal, backdrop: 0.2, source: 0.8), 0.8, accuracy: acc)
    }

    func testMultiply() {
        XCTAssertEqual(BlendMath.blend(.multiply, backdrop: 0.5, source: 0.5), 0.25, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.multiply, backdrop: 1.0, source: 0.3), 0.3, accuracy: acc)
    }

    func testScreen() {
        // Cb + Cs - Cb*Cs
        XCTAssertEqual(BlendMath.blend(.screen, backdrop: 0.5, source: 0.5), 0.75, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.screen, backdrop: 0.0, source: 0.4), 0.4, accuracy: acc)
    }

    func testDarkenAndLighten() {
        XCTAssertEqual(BlendMath.blend(.darken, backdrop: 0.3, source: 0.7), 0.3, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.lighten, backdrop: 0.3, source: 0.7), 0.7, accuracy: acc)
    }

    func testHardLightBothBranches() {
        // Cs <= 0.5 -> Multiply(Cb, 2*Cs) = 0.4 * 0.6 = 0.24
        XCTAssertEqual(BlendMath.blend(.hardLight, backdrop: 0.4, source: 0.3), 0.24, accuracy: acc)
        // Cs > 0.5 -> Screen(Cb, 2*Cs - 1) = 0.4 + 0.5 - 0.2 = 0.7
        XCTAssertEqual(BlendMath.blend(.hardLight, backdrop: 0.4, source: 0.75), 0.7, accuracy: acc)
    }

    func testOverlayIsHardLightWithSwappedArguments() {
        // overlay(Cb=0.25, Cs=0.75) == hardLight(Cb=0.75, Cs=0.25) = Multiply(0.75, 0.5) = 0.375
        XCTAssertEqual(BlendMath.blend(.overlay, backdrop: 0.25, source: 0.75), 0.375, accuracy: acc)
        for cb in stride(from: 0.0, through: 1.0, by: 0.1) {
            for cs in stride(from: 0.0, through: 1.0, by: 0.1) {
                XCTAssertEqual(BlendMath.blend(.overlay, backdrop: cb, source: cs),
                               BlendMath.blend(.hardLight, backdrop: cs, source: cb),
                               accuracy: acc)
            }
        }
    }

    func testColorDodgeIncludingItsTwoSpecialCases() {
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.0, source: 0.9), 0.0, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.5, source: 1.0), 1.0, accuracy: acc)
        // min(1, Cb / (1 - Cs)) = min(1, 0.5/0.5) = 1
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.5, source: 0.5), 1.0, accuracy: acc)
        // min(1, 0.2/0.75) = 0.2666...
        XCTAssertEqual(BlendMath.blend(.colorDodge, backdrop: 0.2, source: 0.25),
                       0.2 / 0.75, accuracy: acc)
    }

    func testColorBurnIncludingItsTwoSpecialCases() {
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 1.0, source: 0.1), 1.0, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 0.5, source: 0.0), 0.0, accuracy: acc)
        // 1 - min(1, (1-0.5)/0.5) = 0
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 0.5, source: 0.5), 0.0, accuracy: acc)
        // 1 - min(1, (1-0.8)/0.5) = 1 - 0.4 = 0.6
        XCTAssertEqual(BlendMath.blend(.colorBurn, backdrop: 0.8, source: 0.5), 0.6, accuracy: acc)
    }

    func testSoftLightBothBranchesAndTheDFunctionSplit() {
        // Cs <= 0.5: Cb - (1 - 2Cs) * Cb * (1 - Cb) = 0.25 - 0.5 * 0.25 * 0.75 = 0.15625
        XCTAssertEqual(BlendMath.blend(.softLight, backdrop: 0.25, source: 0.25),
                       0.15625, accuracy: acc)
        // Cs > 0.5, Cb <= 0.25: D(Cb) = ((16*0.16 - 12) * 0.16 + 4) * 0.16 = 0.398336
        //          B = 0.16 + (2*0.75 - 1) * (0.398336 - 0.16) = 0.279168
        XCTAssertEqual(BlendMath.blend(.softLight, backdrop: 0.16, source: 0.75),
                       0.279168, accuracy: 1e-9)
        // Cs > 0.5, Cb > 0.25: D(Cb) = sqrt(0.49) = 0.7
        //          B = 0.49 + (2*1.0 - 1) * (0.7 - 0.49) = 0.7
        XCTAssertEqual(BlendMath.blend(.softLight, backdrop: 0.49, source: 1.0), 0.7, accuracy: acc)
    }

    func testDifferenceAndExclusion() {
        XCTAssertEqual(BlendMath.blend(.difference, backdrop: 0.75, source: 0.25), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.exclusion, backdrop: 0.5, source: 0.5), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.exclusion, backdrop: 1.0, source: 1.0), 0.0, accuracy: acc)
    }

    // MARK: compositing over an opaque backdrop

    func testAlphaZeroLeavesTheBackdropUntouched() {
        let cb = SIMD3<Double>(0.2, 0.4, 0.6)
        let result = BlendMath.composite(backdrop: cb, source: SIMD3(1, 1, 1),
                                         alpha: 0, mode: .multiply)
        XCTAssertEqual(result.x, cb.x, accuracy: acc)
        XCTAssertEqual(result.y, cb.y, accuracy: acc)
        XCTAssertEqual(result.z, cb.z, accuracy: acc)
    }

    func testAlphaOneGivesThePureBlendResult() {
        let result = BlendMath.composite(backdrop: SIMD3(0.5, 0.5, 0.5),
                                         source: SIMD3(0.5, 0.5, 0.5),
                                         alpha: 1, mode: .multiply)
        XCTAssertEqual(result.x, 0.25, accuracy: acc)
    }

    func testPartialAlphaInterpolatesBackdropTowardTheBlend() {
        // Co = (1 - a)*Cb + a*B(Cb, Cs) = 0.5*0.5 + 0.5*0.25 = 0.375
        let result = BlendMath.composite(backdrop: SIMD3(0.5, 0.5, 0.5),
                                         source: SIMD3(0.5, 0.5, 0.5),
                                         alpha: 0.5, mode: .multiply)
        XCTAssertEqual(result.x, 0.375, accuracy: acc)
    }

    func testEveryModeHasAStableShaderIndex() {
        // The MSL switch is indexed by this value; reordering allCases silently remaps every
        // operator's saved blend selection.
        XCTAssertEqual(BlendMode.allCases.map(\.shaderIndex),
                       Array(0..<Int32(BlendMode.allCases.count)))
        XCTAssertEqual(BlendMode.normal.shaderIndex, 0)
        XCTAssertEqual(BlendMode.allCases.count, 19)
    }

    func testTheTwelveW3CModesKeepTheirOriginalIndices() {
        // The extended set was APPENDED. If anyone ever interleaves a new mode, this pins the
        // damage: every saved blend selection would silently point at a different mode.
        let w3c: [BlendMode] = [.normal, .multiply, .screen, .overlay, .darken, .lighten,
                                .colorDodge, .colorBurn, .hardLight, .softLight,
                                .difference, .exclusion]
        XCTAssertEqual(w3c.map(\.shaderIndex), Array(0..<12))
        XCTAssertTrue(w3c.allSatisfy(\.isW3CSeparable))
        XCTAssertEqual(BlendMode.allCases.filter(\.isW3CSeparable), w3c)
    }

    // MARK: extended set

    func testAddIsClampedLinearDodge() {
        XCTAssertEqual(BlendMath.blend(.add, backdrop: 0.3, source: 0.4), 0.7, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.add, backdrop: 0.8, source: 0.9), 1.0, accuracy: acc,
                       "must clamp, not wrap")
        XCTAssertEqual(BlendMath.blend(.add, backdrop: 0.0, source: 0.0), 0.0, accuracy: acc)
    }

    func testSubtractIsClampedAtZero() {
        XCTAssertEqual(BlendMath.blend(.subtract, backdrop: 0.7, source: 0.2), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.subtract, backdrop: 0.2, source: 0.7), 0.0, accuracy: acc)
    }

    func testLinearBurn() {
        // cb + cs - 1
        XCTAssertEqual(BlendMath.blend(.linearBurn, backdrop: 0.8, source: 0.7), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.linearBurn, backdrop: 0.2, source: 0.3), 0.0, accuracy: acc)
    }

    func testVividLightSwitchesBetweenBurnAndDodge() {
        // cs <= 0.5 -> ColorBurn(cb, 2cs). cs=0.25 -> burn(0.5, 0.5) = 0
        XCTAssertEqual(BlendMath.blend(.vividLight, backdrop: 0.5, source: 0.25), 0.0, accuracy: acc)
        // cs > 0.5 -> ColorDodge(cb, 2cs-1). cs=0.75 -> dodge(0.5, 0.5) = 1
        XCTAssertEqual(BlendMath.blend(.vividLight, backdrop: 0.5, source: 0.75), 1.0, accuracy: acc)
    }

    func testPinLight() {
        // cs <= 0.5 -> min(cb, 2cs);  cs > 0.5 -> max(cb, 2cs-1)
        XCTAssertEqual(BlendMath.blend(.pinLight, backdrop: 0.8, source: 0.25), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.pinLight, backdrop: 0.2, source: 0.9), 0.8, accuracy: acc)
    }

    func testHardMixIsBinary() {
        XCTAssertEqual(BlendMath.blend(.hardMix, backdrop: 0.6, source: 0.6), 1.0, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.hardMix, backdrop: 0.2, source: 0.3), 0.0, accuracy: acc)
        for cb in stride(from: 0.0, through: 1.0, by: 0.1) {
            for cs in stride(from: 0.0, through: 1.0, by: 0.1) {
                let v = BlendMath.blend(.hardMix, backdrop: cb, source: cs)
                XCTAssertTrue(v == 0 || v == 1, "hard mix must land on 0 or 1, got \(v)")
            }
        }
    }

    func testDivideIncludingTheZeroSourceCase() {
        XCTAssertEqual(BlendMath.blend(.divide, backdrop: 0.25, source: 0.5), 0.5, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.divide, backdrop: 0.8, source: 0.2), 1.0, accuracy: acc,
                       "clamped at 1")
        XCTAssertEqual(BlendMath.blend(.divide, backdrop: 0.5, source: 0.0), 1.0, accuracy: acc)
        XCTAssertEqual(BlendMath.blend(.divide, backdrop: 0.0, source: 0.0), 0.0, accuracy: acc,
                       "0/0 stays black rather than flashing white")
    }
}
