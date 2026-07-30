import XCTest

@MainActor
final class MixerStateTests: XCTestCase {
    func testDefaultsAreBothDecksFullyUpWithNormalBlend() {
        let mixer = MixerState()
        XCTAssertEqual(mixer.opacity[.one], 1.0)
        XCTAssertEqual(mixer.opacity[.two], 1.0)
        XCTAssertEqual(mixer.blendMode[.one], .normal)
        XCTAssertEqual(mixer.blendMode[.two], .normal)
        XCTAssertEqual(mixer.crossfadePosition, 0.0,
                       "The instrument boots showing deck A, not a half-and-half blend")
    }

    func testLayersCarryBothTheUserValueAndTheEffectiveValue() {
        let mixer = MixerState()
        mixer.setOpacity(0.8, for: .one)
        mixer.crossfadePosition = 0.5

        let layers = mixer.layers()
        XCTAssertEqual(layers.count, 2)
        let a = layers[0]
        XCTAssertEqual(a.deck, .one)
        XCTAssertEqual(a.userOpacity, 0.8, accuracy: 1e-12,
                       "The fader the operator set is never overwritten")
        XCTAssertEqual(a.crossfadeWeight, 0.5, accuracy: 1e-12)
        XCTAssertEqual(a.effectiveOpacity, 0.4, accuracy: 1e-12)
    }

    func testLayersAreOrderedDeckOneThenDeckTwo() {
        // Layer order IS composite order: deck 1 onto black, deck 2 onto the result.
        XCTAssertEqual(MixerState().layers().map(\.deck), [.one, .two])
    }

    func testBlackoutLatchToggles() {
        let mixer = MixerState()
        XCTAssertFalse(mixer.isBlackedOut)
        mixer.toggleBlackoutLatch()
        XCTAssertTrue(mixer.isBlackedOut)
        mixer.toggleBlackoutLatch()
        XCTAssertFalse(mixer.isBlackedOut)
    }

    func testMomentaryHoldBlacksOutAndReleases() {
        let mixer = MixerState()
        mixer.beginBlackoutHold()
        XCTAssertTrue(mixer.isBlackedOut)
        mixer.endBlackoutHold()
        XCTAssertFalse(mixer.isBlackedOut)
    }

    func testReleasingAMomentaryHoldDoesNotCancelAnEngagedLatch() {
        // The failure this prevents: latch blackout on, someone taps the momentary key, and
        // releasing it puts the room back in light.
        let mixer = MixerState()
        mixer.toggleBlackoutLatch()
        mixer.beginBlackoutHold()
        mixer.endBlackoutHold()
        XCTAssertTrue(mixer.isBlackedOut, "The latch is still engaged")
    }

    func testOpacityIsClampedOnTheWayIn() {
        let mixer = MixerState()
        mixer.setOpacity(5, for: .one)
        XCTAssertEqual(mixer.opacity[.one], 1.0)
        mixer.setOpacity(-5, for: .two)
        XCTAssertEqual(mixer.opacity[.two], 0.0)
    }

    // MARK: the render-thread mirror

    func testTheRenderMirrorTracksEveryMutation() {
        // The render thread never reads the @Published properties. If a mutation forgets to
        // republish, the picture silently stops following the controls.
        let mixer = MixerState()
        XCTAssertEqual(mixer.renderLayers().map(\.deck), [.one, .two])

        mixer.setOpacity(0.25, for: .one)
        XCTAssertEqual(mixer.renderLayers()[0].userOpacity, 0.25, accuracy: 1e-12)

        mixer.crossfadePosition = 1.0
        XCTAssertEqual(mixer.renderLayers()[0].effectiveOpacity, 0.0, accuracy: 1e-12)
        XCTAssertEqual(mixer.renderLayers()[1].effectiveOpacity, 1.0, accuracy: 1e-12)

        mixer.setBlendMode(.screen, for: .two)
        XCTAssertEqual(mixer.renderLayers()[1].blendMode, .screen)

        mixer.toggleBlackoutLatch()
        XCTAssertTrue(mixer.isBlackedOutForRender())
        mixer.toggleBlackoutLatch()
        XCTAssertFalse(mixer.isBlackedOutForRender())
    }

    func testTheRenderMirrorAgreesWithTheMainThreadView() {
        let mixer = MixerState()
        mixer.setOpacity(0.6, for: .one)
        mixer.setOpacity(0.3, for: .two)
        mixer.crossfadePosition = 0.35
        mixer.setBlendMode(.difference, for: .one)
        XCTAssertEqual(mixer.renderLayers(), mixer.layers())
    }

    func testClampingTheCrossfaderStillPublishesToTheRenderThread() {
        // The didSet re-entry path (clamp, then return early) must not skip the mirror update.
        let mixer = MixerState()
        mixer.crossfadePosition = 5.0
        XCTAssertEqual(mixer.crossfadePosition, 1.0, accuracy: 1e-12)
        XCTAssertEqual(mixer.renderLayers()[1].crossfadeWeight, 1.0, accuracy: 1e-12,
                       "A clamped assignment must still reach the render mirror")
    }
}
