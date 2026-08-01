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

    // MARK: Task 7R — slot bank rows and collapse

    private func preset(_ path: String = "/tmp/a.fs") -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: path), snapshot: ParamSnapshot(params: [:]))
    }

    /// The structural invariant the whole design turns on: a resize touches `Arrangement`, never
    /// `SlotBank`. There is no code path from `setBankRows` to the model, so this should be
    /// impossible to fail without someone deliberately wiring resize into the bank.
    func testShrinkingRowsHidesPresetsButNeverDestroysThem() {
        let bank = SlotBank()
        let layout = SurfaceLayout()
        layout.setBankRows(2)
        bank.capture(preset(), into: 15)   // row 2 (indices 8...15)

        layout.setBankRows(1)
        XCTAssertNotNil(bank.slots[15], "A resize must never reach the model")

        layout.setBankRows(2)
        XCTAssertNotNil(bank.slots[15], "…and growing back reveals it unchanged")
    }

    /// `isBankCollapsed` has no `SectionKey`, so `toggleShowMode()` — which iterates
    /// `SectionKey.all` — cannot reach it. Firing slots is performance, the same category as the
    /// crossfader and BLACKOUT, which show mode already leaves alone.
    func testShowModeCannotCollapseTheBank() {
        let layout = SurfaceLayout()
        XCTAssertFalse(layout.isBankCollapsed)
        layout.toggleShowMode()
        XCTAssertTrue(layout.showMode)
        XCTAssertFalse(layout.isBankCollapsed,
                       "Firing slots is performance; show mode collapses configuration only")
    }

    /// The other half of "show mode never touches the bank": a deliberate resize or manual
    /// collapse made WHILE in show mode must survive exiting show mode, exactly like a mid-show
    /// crossfader move would. Restoring `bankRows`/`isBankCollapsed` from the pre-show snapshot on
    /// exit would silently discard that deliberate act — the same failure class `setExpanded`'s
    /// "a deliberate edit is never silently thrown away" rule exists to prevent, just for a field
    /// with no `SectionKey` to trip that rule's own machinery.
    func testResizingOrCollapsingTheBankDuringAShowSurvivesExitingIt() {
        let layout = SurfaceLayout()
        layout.setBankRows(1)
        layout.toggleShowMode()

        layout.setBankRows(3)
        layout.toggleBankCollapsed()

        layout.toggleShowMode()   // exit
        XCTAssertFalse(layout.showMode)
        XCTAssertEqual(layout.bankRows, 3, "A mid-show resize must not be reverted on exit")
        XCTAssertTrue(layout.isBankCollapsed, "A mid-show collapse must not be reverted on exit")
    }

    /// `bankRows` clamps at both ends — a MIDI pad or a corrupt/future-build value can hand it
    /// anything.
    func testBankRowsClampsToItsBounds() {
        let layout = SurfaceLayout()

        layout.setBankRows(0)
        XCTAssertEqual(layout.bankRows, 1, "Below the floor pins to one row")

        layout.setBankRows(99)
        XCTAssertEqual(layout.bankRows, SlotBank.maxRows, "Above the ceiling pins to maxRows")

        layout.setBankRows(3)
        XCTAssertEqual(layout.bankRows, 3, "Inside the bounds the request is honoured exactly")
    }

    /// A stored value outside `1...maxRows` — a hand-edited file, or a bank from a future build
    /// with a bigger grid — must normalise at load, not just at the drag call site.
    func testAStoredBankRowsOutOfRangeNormalisesOnLoad() {
        var tooFew = Arrangement.default
        tooFew.bankRows = 0
        XCTAssertEqual(SurfaceLayout(tooFew).bankRows, 1)

        var tooMany = Arrangement.default
        tooMany.bankRows = 99
        XCTAssertEqual(SurfaceLayout(tooMany).bankRows, SlotBank.maxRows)
    }

    /// Invariant 3, extended: the two new fields round-trip through the same JSON encoding every
    /// other `Arrangement` field already does.
    func testArrangementRoundTripsTheBankFields() throws {
        var arrangement = Arrangement.default
        arrangement.bankRows = 4
        arrangement.isBankCollapsed = true

        let data = try JSONEncoder().encode(arrangement)
        let decoded = try JSONDecoder().decode(Arrangement.self, from: data)

        XCTAssertEqual(decoded, arrangement)
    }

    /// THE persistence trap this task exists to close. `Arrangement` used to rely on Swift's
    /// synthesized `Codable`, and adding two stored properties to a synthesized decoder would have
    /// made every blob saved before this task fail to decode outright — `SurfaceLayoutStore.load()`
    /// returns `.default` on any decode failure, so the operator's saved panel width and every
    /// section-collapse flag would have silently reset on first launch. Hand-built JSON containing
    /// only the three original keys must still decode, keeping the old fields intact and picking up
    /// defaults for the two new ones.
    func testAnArrangementSavedBeforeThisTaskStillDecodes() throws {
        let oldSchemaJSON = """
        {
          "openPanel": "settings",
          "expanded": [],
          "panelWidth": 331
        }
        """
        let decoded = try JSONDecoder().decode(Arrangement.self, from: Data(oldSchemaJSON.utf8))

        XCTAssertEqual(decoded.openPanel, .settings, "The old openPanel value survives")
        XCTAssertEqual(decoded.panelWidth, 331, "The old panelWidth value survives")
        XCTAssertTrue(decoded.expanded.isEmpty, "The old (empty) expanded value survives")
        XCTAssertEqual(decoded.bankRows, 1, "A blob with no bankRows key takes the default")
        XCTAssertFalse(decoded.isBankCollapsed, "A blob with no isBankCollapsed key takes the default")
    }
}
