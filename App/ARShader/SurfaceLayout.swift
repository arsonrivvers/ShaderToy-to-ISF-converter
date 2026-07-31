import Foundation

/// A tool the rail can show. One case per rail icon; the rail's order is `allCases`.
///
/// Later phases add cases here and nothing else changes — that is the whole reason the panel is a
/// rail rather than a set of fixed regions.
enum PanelID: String, CaseIterable, Codable, Identifiable, Sendable {
    case library, settings
    var id: String { rawValue }

    /// SF Symbol for the rail. Drawn glyphs are an art-direction decision, deferred.
    var systemImage: String {
        switch self {
        case .library:  return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .library:  return "Library"
        case .settings: return "Settings"
        }
    }

    /// The digit in this panel's `⌘⌥N` shortcut, or nil past the ninth panel.
    ///
    /// One source for both the shortcut and the tooltip that advertises it. They were two
    /// independent `index + 1` expressions in two files with nothing tying them together, so a
    /// reordered `allCases` would have silently made every tooltip a lie.
    ///
    /// Optional rather than an `Int`, because the shortcut was built as
    /// `Character("\(index + 1)")` and `Character.init` requires exactly one grapheme cluster —
    /// at the tenth panel that is `Character("10")`, which traps at first render, i.e. at launch.
    /// The rail's whole stated premise is that a later phase adds a tool by adding one case here;
    /// case ten must not be a crash.
    var shortcutNumber: Int? {
        guard let index = Self.allCases.firstIndex(of: self), index < 9 else { return nil }
        return index + 1
    }
}

/// The collapsible sections of a deck strip. Configuration only — see the spec's §2.3 rule.
enum DeckSection: String, CaseIterable, Codable, Sendable {
    case sources, fx, parameters
}

/// Identity of one collapsible section. Carries the `DeckID`, so deck A's FX and deck B's FX are
/// different keys and cannot share a flag.
enum SectionKey: Hashable, Codable, Sendable {
    case deck(DeckID, DeckSection)
    case masterFX

    /// Every section the surface has. Show mode iterates this; the test pins it.
    static var all: [SectionKey] {
        DeckID.allCases.flatMap { deck in
            DeckSection.allCases.map { SectionKey.deck(deck, $0) }
        } + [.masterFX]
    }
}

/// The whole restorable arrangement: what show mode snapshots, and what persists across launches.
///
/// One value serves both jobs on purpose — a separate snapshot type and persistence type could
/// drift on what counts as "the arrangement," and the restore would quietly stop restoring part
/// of it.
struct Arrangement: Codable, Equatable, Sendable {
    var openPanel: PanelID?
    var expanded: [SectionKey: Bool]
    var panelWidth: Double

    static let `default` = Arrangement(
        openPanel: nil,
        expanded: Dictionary(uniqueKeysWithValues: SectionKey.all.map { ($0, true) }),
        panelWidth: 280)
}

/// Every layout flag on the instrument surface, and the show-mode snapshot.
///
/// A plain model with no SwiftUI import: show mode has to snapshot and restore ALL of the state
/// atomically, which per-view `@State` cannot do, and every invariant below is then testable with
/// no view in play — the only kind of test that has ever been cheap on this surface.
///
/// Blackout is deliberately absent. It has no `SectionKey` and no `PanelID`, so show mode cannot
/// reach it structurally rather than by promise.
@MainActor
final class SurfaceLayout: ObservableObject {
    /// The panel never narrows past this, however far the divider is dragged.
    static let minPanelWidth: Double = 260

    /// Absolute ceiling, applied when no window width is available to clamp against.
    ///
    /// Exists so that *forgetting* to pass a width cannot reintroduce an unbounded panel. A caller
    /// that knows the window gets the real clamp; one that does not still gets a bound.
    static let maxPanelWidth: Double = 900

    /// The fixed width the panel shares its window with: the rail, two dividers, the resize handle,
    /// the deck strips' own minimum, and the mixer strip.
    ///
    /// A fraction of the window would NOT be a correct ceiling — at the minimum window size, half
    /// the width still starves the strips' 620pt minimum and pushes the mixer out. The bound the
    /// operator actually needs is "everything else still fits", which is this subtraction.
    /// `SurfaceMetrics` owns the parts; `testTheReservedWidthMatchesTheRegionsItClaimsToCover`
    /// fails if the two ever drift apart.
    static let reservedSurfaceWidth: Double = 872

    /// The widest the panel may be drawn in a surface of `surfaceWidth`.
    ///
    /// The floor outranks the ceiling: on a window too narrow for both, the panel keeps its floor
    /// and the window's own declared minimum is what guarantees the rest still fits.
    static func panelWidthCeiling(inSurfaceOfWidth surfaceWidth: Double) -> Double {
        guard surfaceWidth.isFinite else { return maxPanelWidth }
        return max(minPanelWidth, min(surfaceWidth - reservedSurfaceWidth, maxPanelWidth))
    }

    @Published private(set) var openPanel: PanelID?
    @Published private(set) var panelWidth: Double
    @Published private(set) var showMode: Bool = false

    @Published private var expanded: [SectionKey: Bool]

    /// The arrangement as it stood when show mode was entered. Discarded the moment the operator
    /// edits a section during a show — see `setExpanded`.
    private var snapshot: Arrangement?

    init(_ arrangement: Arrangement = .default) {
        self.openPanel = arrangement.openPanel
        self.panelWidth = arrangement.panelWidth
        self.expanded = arrangement.expanded
    }

    // MARK: Sections

    /// Unknown keys read as expanded: a section added in a later build must appear, not hide.
    func isExpanded(_ key: SectionKey) -> Bool { expanded[key] ?? true }

    /// A deliberate layout action during a show ENDS the show rather than restoring over it later.
    /// An untouched round trip still restores exactly; a deliberate mid-set change is never
    /// silently thrown away.
    ///
    /// Both doors call this: section collapse AND panel selection. The rail stays live during a
    /// show by design (`PanelRailView`), so opening Library mid-set is an ANTICIPATED action — and
    /// if it did not end the show, a later ⌘⇧P would fire the restore branch and re-expand the
    /// whole patch arrangement mid-song. That is the exact class this rule exists to prevent.
    private func endShowModeOverride() {
        guard showMode else { return }
        showMode = false
        snapshot = nil
    }

    func setExpanded(_ value: Bool, for key: SectionKey) {
        expanded[key] = value
        endShowModeOverride()
    }

    func toggle(_ key: SectionKey) { setExpanded(!isExpanded(key), for: key) }

    // MARK: Panel

    /// Selecting the open panel closes it; selecting another swaps. The rail itself never hides.
    /// Ends a show-mode override for the reason in `endShowModeOverride`.
    func select(panel: PanelID) {
        openPanel = (openPanel == panel) ? nil : panel
        endShowModeOverride()
    }

    /// Clamped here rather than in the drag handler: the bounds are a property of the layout, and a
    /// view-local clamp would let a future second call site write a 40pt — or a 4000pt — panel.
    ///
    /// `availableWidth` is the width of the surface the panel sits in. Pass it whenever it is
    /// known; the default exists only so a caller without geometry still gets `maxPanelWidth`
    /// rather than no ceiling at all.
    ///
    /// This originally clamped the floor only. `DragGesture` keeps reporting locations after the
    /// pointer leaves the window, so dragging the handle right and releasing could make the panel
    /// wider than the window — pushing the deck strips and the entire mixer strip off-screen,
    /// taking BLACKOUT, SHOW MODE and the OUTPUT destination picker with them. The resize handle
    /// went off-window too, so the mouse could not undo it, and `.onChange` persisted the result
    /// 300ms later, so it survived a relaunch. Found at the phase 3a branch review, 2026-07-31.
    ///
    /// Resizing is NOT a show-mode-ending action — it is a continuous adjustment of a panel that
    /// show mode has already closed, so the case cannot arise.
    func setPanelWidth(_ width: Double, availableWidth: Double = .infinity) {
        // A non-finite width is not a narrow or wide panel, it is a broken one. Rejected outright
        // rather than clamped: `.infinity` survives `max()` unchanged, and an infinite panelWidth
        // makes the whole Arrangement unencodable — which `SurfaceLayoutStore.save()` swallows,
        // silently ending persistence for the session with no symptom until the next launch.
        guard width.isFinite else { return }
        let ceiling = Self.panelWidthCeiling(inSurfaceOfWidth: availableWidth)
        panelWidth = min(max(Self.minPanelWidth, width), ceiling)
    }

    /// The width the panel should be DRAWN at right now, which is not always the width the operator
    /// asked for.
    ///
    /// Clamping only at drag time leaves the other door open: drag the panel wide on a large
    /// window, then make the window small, and the stored width once again covers the mixer strip.
    /// The stored preference is deliberately NOT rewritten — shrinking the window and growing it
    /// back restores the panel the operator chose, rather than silently keeping the shrunken one.
    func drawnPanelWidth(inSurfaceOfWidth surfaceWidth: Double) -> Double {
        min(panelWidth, Self.panelWidthCeiling(inSurfaceOfWidth: surfaceWidth))
    }

    // MARK: Show mode

    func toggleShowMode() {
        if showMode {
            if let snapshot { apply(snapshot) }
            self.snapshot = nil
            showMode = false
        } else {
            snapshot = arrangement
            for key in SectionKey.all { expanded[key] = false }
            openPanel = nil
            showMode = true
        }
    }

    // MARK: Whole-arrangement access

    var arrangement: Arrangement {
        Arrangement(openPanel: openPanel, expanded: expanded, panelWidth: panelWidth)
    }

    func apply(_ a: Arrangement) {
        openPanel = a.openPanel
        expanded = a.expanded
        panelWidth = a.panelWidth
    }
}
