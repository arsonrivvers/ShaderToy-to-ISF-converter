import XCTest

@MainActor
final class SurfaceLayoutTests: XCTestCase {

    /// Invariant 1 — an untouched show-mode round trip is the identity.
    func testShowModeRoundTripWithNoEditRestoresEverything() {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        layout.setExpanded(true, for: .deck(.one, .fx))
        layout.setExpanded(false, for: .deck(.two, .parameters))
        let before = layout.arrangement

        layout.toggleShowMode()
        XCTAssertTrue(layout.showMode)
        XCTAssertNil(layout.openPanel, "Show mode closes the panel")
        XCTAssertFalse(layout.isExpanded(.deck(.one, .fx)), "Show mode collapses every section")

        layout.toggleShowMode()
        XCTAssertFalse(layout.showMode)
        XCTAssertEqual(layout.arrangement, before,
                       "An untouched round trip restores the arrangement exactly")
    }

    /// Invariant 2 — a deliberate edit during a show is never silently thrown away.
    func testEditingASectionInShowModeExitsShowModeAndKeepsTheEdit() {
        let layout = SurfaceLayout()
        layout.setExpanded(true, for: .deck(.one, .parameters))
        layout.toggleShowMode()

        layout.setExpanded(true, for: .deck(.one, .fx))

        XCTAssertFalse(layout.showMode, "Touching a section leaves show mode")
        XCTAssertTrue(layout.isExpanded(.deck(.one, .fx)), "The edit stands")
        XCTAssertFalse(layout.isExpanded(.deck(.one, .parameters)),
                       "Sections show mode collapsed stay collapsed — the snapshot is discarded")

        // A later show-mode cycle must not resurrect the pre-show arrangement.
        layout.toggleShowMode()
        layout.toggleShowMode()
        XCTAssertFalse(layout.isExpanded(.deck(.one, .parameters)))
    }

    /// Invariant 2b — the same guarantee through the OTHER door.
    ///
    /// The rail stays live during a show on purpose, so opening Library mid-set is anticipated.
    /// Without this, a later ⌘⇧P fires the restore branch and re-expands the whole patch
    /// arrangement on stage. None of the other invariants name this transition, so its absence
    /// was invisible to the coverage table until PM spec review caught it.
    func testOpeningAPanelInShowModeExitsShowModeAndKeepsIt() {
        let layout = SurfaceLayout()
        layout.setExpanded(true, for: .deck(.one, .parameters))
        layout.toggleShowMode()
        XCTAssertNil(layout.openPanel)

        layout.select(panel: .library)

        XCTAssertFalse(layout.showMode, "Reaching for a tool leaves show mode")
        XCTAssertEqual(layout.openPanel, .library)
        XCTAssertFalse(layout.isExpanded(.deck(.one, .parameters)),
                       "Sections show mode collapsed stay collapsed")

        // The next ⌘⇧P must COLLAPSE-AND-CLOSE, not restore the pre-show arrangement.
        layout.toggleShowMode()
        XCTAssertTrue(layout.showMode)
        XCTAssertNil(layout.openPanel)
        XCTAssertFalse(layout.isExpanded(.deck(.one, .parameters)),
                       "The discarded snapshot must not resurrect the patch arrangement mid-song")
    }

    /// Invariant 3 — an arrangement survives a relaunch.
    func testArrangementEncodesAndDecodesUnchanged() throws {
        let layout = SurfaceLayout()
        layout.select(panel: .settings)
        layout.setPanelWidth(331)
        layout.setExpanded(true, for: .deck(.two, .sources))
        layout.setExpanded(false, for: .masterFX)

        let data = try JSONEncoder().encode(layout.arrangement)
        let decoded = try JSONDecoder().decode(Arrangement.self, from: data)

        XCTAssertEqual(decoded, layout.arrangement)
    }

    /// Invariant 4 — the rail's toggle semantics.
    func testSelectingTheOpenPanelClosesItAndADifferentOneSwaps() {
        let layout = SurfaceLayout()
        XCTAssertNil(layout.openPanel, "The panel host starts with nothing forced open")

        layout.select(panel: .library)
        XCTAssertEqual(layout.openPanel, .library)

        layout.select(panel: .settings)
        XCTAssertEqual(layout.openPanel, .settings, "A different icon swaps rather than closing")

        layout.select(panel: .settings)
        XCTAssertNil(layout.openPanel, "The active icon closes the panel")
    }

    /// Invariant 5 — one deck's sections are not another's.
    func testCollapsingOneDecksSectionLeavesTheOtherDeckAlone() {
        let layout = SurfaceLayout()
        layout.setExpanded(true, for: .deck(.one, .fx))
        layout.setExpanded(true, for: .deck(.two, .fx))

        layout.setExpanded(false, for: .deck(.one, .fx))

        XCTAssertFalse(layout.isExpanded(.deck(.one, .fx)))
        XCTAssertTrue(layout.isExpanded(.deck(.two, .fx)),
                      "SectionKey carries the DeckID — deck B is untouched")
    }

    /// Invariant 6 — blackout is structurally out of reach.
    func testShowModeCannotAffectBlackout() {
        let mixer = MixerState()
        mixer.toggleBlackoutLatch()
        XCTAssertTrue(mixer.isBlackedOut)

        let layout = SurfaceLayout()
        layout.toggleShowMode()
        layout.toggleShowMode()

        XCTAssertTrue(mixer.isBlackedOut,
                      "SurfaceLayout has no representation of blackout, so it cannot change it")
    }

    /// The drag can never starve the panel. Clamped in the model, not the gesture handler.
    func testPanelWidthClampsToItsFloor() {
        let layout = SurfaceLayout()

        layout.setPanelWidth(40)
        XCTAssertEqual(layout.panelWidth, SurfaceLayout.minPanelWidth,
                       "Dragging the divider past the floor pins it, it does not starve the panel")

        layout.setPanelWidth(420)
        XCTAssertEqual(layout.panelWidth, 420, "Above the floor the drag is honoured exactly")
    }

    /// Every collapsible section the surface has, and nothing else.
    func testTheCollapsibleSetIsExactlyTheConfigurationSections() {
        XCTAssertEqual(Set(SectionKey.all), Set([
            .deck(.one, .sources), .deck(.one, .fx), .deck(.one, .parameters),
            .deck(.two, .sources), .deck(.two, .fx), .deck(.two, .parameters),
            .masterFX,
        ]), "Performance controls are not collapsible and must never appear here")
    }
}
