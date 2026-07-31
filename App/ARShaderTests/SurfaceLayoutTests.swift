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

    // Invariant 6 — blackout is structurally out of reach — was asserted here by a test that
    // constructed a MixerState SurfaceLayout holds no reference to, so it passed for every possible
    // implementation and would have kept passing even if blackout WERE reachable. Deleted at the
    // final branch review rather than kept: a test that cannot fail is worse than no test, because
    // it reads as coverage on the invariant it names. The same fact is pinned falsifiably by
    // testTheCollapsibleSetIsExactlyTheConfigurationSections, which fails the moment a blackout key
    // joins the collapsible set.

    /// The rail's tooltip and the keyboard shortcut must name the same key.
    ///
    /// They were two independent `index + 1` expressions in two files, so reordering `allCases`
    /// would have left every tooltip advertising a shortcut that did something else — the kind of
    /// wrong that is only discovered mid-set.
    func testEachPanelsShortcutDigitMatchesItsPositionInTheRail() {
        for (index, panel) in PanelID.allCases.enumerated() where index < 9 {
            XCTAssertEqual(panel.shortcutNumber, index + 1,
                           "\(panel.title) is rail position \(index + 1) and must bind ⌘⌥\(index + 1)")
        }
    }

    /// The rail's premise is that a later phase adds a tool by adding one case. Case ten must not
    /// be a crash: `Character("10")` traps, and it would trap at first render, i.e. at launch.
    func testPanelsPastTheNinthHaveNoShortcutRatherThanACrashingOne() {
        for (index, panel) in PanelID.allCases.enumerated() where index >= 9 {
            XCTAssertNil(panel.shortcutNumber,
                         "There is no single-character key equivalent past the ninth panel")
        }
        // Guards the guard: if allCases ever shrinks below the boundary this loop tests nothing,
        // and the assertion above would pass vacuously.
        XCTAssertEqual(PanelID.allCases.compactMap(\.shortcutNumber).count,
                       min(PanelID.allCases.count, 9),
                       "Every panel up to the ninth has a shortcut, and none past it does")
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

    /// The other half of the clamp, and the half that was missing.
    ///
    /// `DragGesture` keeps reporting locations after the pointer leaves the window, so a drag to
    /// the right had no upper bound at all: the panel could be made wider than the window, pushing
    /// the deck strips and the whole mixer strip — BLACKOUT, SHOW MODE and the OUTPUT destination
    /// picker — off-screen. The resize handle went with them, so the mouse could not undo it, and
    /// the arrangement persisted 300ms later and survived relaunch.
    func testPanelWidthClampsToItsCeiling() {
        let layout = SurfaceLayout()

        layout.setPanelWidth(5000, availableWidth: 1600)
        XCTAssertLessThanOrEqual(layout.panelWidth, 800,
                                 "A drag past the window edge must not hand the panel the window")

        layout.setPanelWidth(420, availableWidth: 1600)
        XCTAssertEqual(layout.panelWidth, 420, "Inside the bounds the drag is still honoured exactly")
    }

    /// The floor outranks the ceiling. On a window too narrow for both, the panel keeps its floor
    /// rather than collapsing — the window minimum is what guarantees the rest fits.
    func testTheFloorWinsOnAWindowTooNarrowForBoth() {
        let layout = SurfaceLayout()
        layout.setPanelWidth(5000, availableWidth: 300)
        XCTAssertEqual(layout.panelWidth, SurfaceLayout.minPanelWidth,
                       "A ceiling below the floor must not produce a sub-floor panel")
    }

    /// Even with no window width to clamp against, the width is bounded.
    ///
    /// `availableWidth` defaults to `.infinity` so existing call sites keep compiling, which would
    /// reintroduce the unbounded case by omission. The absolute ceiling makes forgetting it safe.
    func testPanelWidthIsBoundedEvenWithNoWindowWidth() {
        let layout = SurfaceLayout()
        layout.setPanelWidth(99_000)
        XCTAssertEqual(layout.panelWidth, SurfaceLayout.maxPanelWidth,
                       "An unbounded call site must still land on the absolute ceiling")
    }

    /// A non-finite width must never reach persistence.
    ///
    /// `max(260, .nan)` returns 260 and is harmless, but `.infinity` survived the old clamp intact,
    /// and `JSONEncoder` throws on a non-finite Double — which `SurfaceLayoutStore.save()` swallows.
    /// The arrangement would then silently stop persisting for the rest of the session, with the
    /// only symptom appearing at the NEXT launch.
    func testNonFiniteWidthsAreRejectedBeforeTheyCanBreakPersistence() throws {
        let layout = SurfaceLayout()
        layout.setPanelWidth(420)

        layout.setPanelWidth(.infinity)
        XCTAssertEqual(layout.panelWidth, 420, "An infinite drag value is ignored, not stored")

        layout.setPanelWidth(.nan)
        XCTAssertEqual(layout.panelWidth, 420, "A NaN drag value is ignored, not stored")

        XCTAssertNoThrow(try JSONEncoder().encode(layout.arrangement),
                         "The arrangement must always be encodable — an unencodable one fails "
                         + "silently inside save() and stops persisting without a symptom")
    }

    /// Every collapsible section the surface has, and nothing else.
    func testTheCollapsibleSetIsExactlyTheConfigurationSections() {
        XCTAssertEqual(Set(SectionKey.all), Set([
            .deck(.one, .sources), .deck(.one, .fx), .deck(.one, .parameters),
            .deck(.two, .sources), .deck(.two, .fx), .deck(.two, .parameters),
            .masterFX,
        ]), "Performance controls are not collapsible and must never appear here")
    }

    /// The deliberate test of phase 3a's central claim: adding a tool costs one enum case.
    func testTheBankIsTheThirdRailPanelAndBindsCommandOptionThree() {
        XCTAssertEqual(PanelID.allCases.count, 3, "library, settings, bank")
        XCTAssertEqual(PanelID.bank.shortcutNumber, 3,
                       "The rail's premise is that a new tool costs one case and inherits ⌘⌥N")
        XCTAssertFalse(PanelID.bank.title.isEmpty)
    }

    func testOpeningTheBankSwapsRatherThanStacking() {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        layout.select(panel: .bank)
        XCTAssertEqual(layout.openPanel, .bank, "The rail swaps one panel; it never shows two")
    }
}
