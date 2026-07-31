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

    /// Clamped here rather than in the drag handler: the floor is a property of the layout, and a
    /// view-local clamp would let a future second call site write a 40pt panel.
    ///
    /// Resizing is NOT a show-mode-ending action — it is a continuous adjustment of a panel that
    /// show mode has already closed, so the case cannot arise.
    func setPanelWidth(_ width: Double) {
        panelWidth = max(Self.minPanelWidth, width)
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
