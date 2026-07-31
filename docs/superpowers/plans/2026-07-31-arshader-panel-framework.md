# ARShader Milestone 2 phase 3a — Panel Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ARShader instrument a 44pt icon rail with one swapping panel, collapsible
configuration sections inside the deck strips, a one-key show mode, and a settings panel — so
collapsing a section hands its height to the monitors.

**Architecture:** One `@MainActor` `SurfaceLayout` observable owns every layout flag and the
show-mode snapshot; it is a plain model with no SwiftUI dependency, so all of its behaviour is unit
tested with no view in play. A generic `InstrumentSurface` container owns the four-region geometry
and the flexible monitor-height allocation, which lets tests exercise the real layout code with
stub content instead of live Metal monitors. Views are thin over both.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (`NSHostingView` for the render harness), XCTest,
XcodeGen (`App/project.yml`), macOS 13+.

**Spec:** `docs/superpowers/specs/2026-07-31-arshader-panel-framework-design.md`

## Global Constraints

- **`SurfaceLayout` and all new instrument views live in `App/ARShader/`, never `ISFRuntime/`.**
  `ISFRuntime` is compiled into TrueISFEditor as well; instrument UI state must not leak there.
  (Same rule that put `ShaderUnit` in `App/ARShader` in phase 2.)
- **Nothing in this plan touches the render thread**, the compositor, the FX encode path, or any
  published render mirror. View layer and view state only.
- **Build and test with an explicit non-Desktop derived-data path:** `/tmp/arshader-ddata`. The
  repo lives under `~/Desktop`, where Defender DLP has stalled test hosts pre-`main`.
- **`xcodebuild test` launches a second ARShader window via `TEST_HOST`, and
  `scripts/run-instrument.sh` QUITS any running ARShader.** Tell the operator before running
  either. Use `build-for-testing` when you only need to confirm something fails to compile — it
  launches no window.
- **Regenerate the project after adding any file:** `cd App && xcodegen generate`. The
  `.xcodeproj` is generated and gitignored; a stale one silently omits new sources.
- **Baseline gate counts:** ARShaderTests **181**, TrueISFEditorTests **514 (3 skipped)**,
  ShadertoyISFKit **312**. Every task that ends in a commit must not reduce any of them.
- **Configuration collapses, performance never does.** `SOURCES`, `FX`, `PARAMETERS` and master
  `FX` are collapsible. Deck name, shader name, opacity, blend, crossfader, `PREVIEW SCALE`,
  `CUE SCALE`, stats and `BLACKOUT` are not, and must never move behind a panel.
- **Blackout has no representation in `SurfaceLayout`.** No `SectionKey` case, no `PanelID` case.
  This is the mechanism, not a convention.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| Create `App/ARShader/SurfaceLayout.swift` | `PanelID`, `DeckSection`, `SectionKey`, `Arrangement`, `SurfaceLayout` — all layout state and show-mode snapshot logic | 1 |
| Create `App/ARShader/SurfaceLayoutStore.swift` | Persist/restore an `Arrangement` through `UserDefaults` | 2 |
| Create `App/ARShader/PanelRailView.swift` | The 44pt icon rail | 3 |
| Create `App/ARShader/InstrumentSurface.swift` | Generic four-region geometry + flexible monitor height | 4 |
| Create `App/ARShader/CollapsibleSection.swift` | Reusable header-with-summary + collapsible content | 5 |
| Modify `App/ARShader/InstrumentView.swift` | Adopt the surface, rail, sections, show mode; shed the moved settings | 4, 6, 7, 8 |
| Create `App/ARShader/SettingsPanelView.swift` | `OUTPUT RES` + output destination, moved off the mixer strip | 7 |
| Modify `App/ARShader/Deck.swift:4` | `DeckID` gains `Codable` | 1 |
| Modify `App/ARShader/Instrument.swift` | Own a `SurfaceLayout` | 4 |
| Create `App/ARShaderTests/SurfaceLayoutTests.swift` | The six model invariants | 1 |
| Create `App/ARShaderTests/SurfaceLayoutStoreTests.swift` | Persistence round trip | 2 |
| Create `App/ARShaderTests/SurfaceRenderHarness.swift` | Render a SwiftUI view to an `NSView` tree + PNG; measure subview geometry | 9 |
| Create `App/ARShaderTests/SurfaceGeometryTests.swift` | Geometry gates + PNG baselines + the mutation proof | 9 |
| Create `App/ARShaderTests/Baselines/` | Committed PNG baselines | 9 |
| Create `docs/reports/live-smoke-instrument-m2-phase3a.md` | Operator-signed smoke | 10 |

---

## Task 1: `SurfaceLayout` — the model

**Files:**
- Create: `App/ARShader/SurfaceLayout.swift`
- Modify: `App/ARShader/Deck.swift:4`
- Test: `App/ARShaderTests/SurfaceLayoutTests.swift`

**Interfaces:**
- Consumes: `DeckID` from `App/ARShader/Deck.swift`.
- Produces: `PanelID`, `DeckSection`, `SectionKey`, `Arrangement`, and
  `SurfaceLayout` with `openPanel: PanelID?`, `panelWidth: Double`,
  `isExpanded(_: SectionKey) -> Bool`, `setExpanded(_: Bool, for: SectionKey)`,
  `toggle(_: SectionKey)`, `select(panel: PanelID)`, `showMode: Bool`,
  `toggleShowMode()`, `arrangement: Arrangement`, `apply(_: Arrangement)`.
  Tasks 3–8 use exactly these names.

- [ ] **Step 1: Make `DeckID` Codable**

`SectionKey` carries a `DeckID` and must encode. Modify `App/ARShader/Deck.swift` line 4:

```swift
enum DeckID: String, CaseIterable, Identifiable, Codable, Sendable {
```

(A raw-value enum gets `Codable` synthesis only when the conformance is declared. Everything else
on the line is unchanged.)

- [ ] **Step 2: Write the failing tests**

Create `App/ARShaderTests/SurfaceLayoutTests.swift`:

```swift
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

    /// Invariant 3 — an arrangement survives a relaunch.
    func testArrangementEncodesAndDecodesUnchanged() throws {
        let layout = SurfaceLayout()
        layout.select(panel: .settings)
        layout.panelWidth = 331
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

    /// Every collapsible section the surface has, and nothing else.
    func testTheCollapsibleSetIsExactlyTheConfigurationSections() {
        XCTAssertEqual(Set(SectionKey.all), Set([
            .deck(.one, .sources), .deck(.one, .fx), .deck(.one, .parameters),
            .deck(.two, .sources), .deck(.two, .fx), .deck(.two, .parameters),
            .masterFX,
        ]), "Performance controls are not collapsible and must never appear here")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'SurfaceLayout' in scope`. `build-for-testing` is used here
deliberately: it opens no window.

- [ ] **Step 4: Write the implementation**

Create `App/ARShader/SurfaceLayout.swift`:

```swift
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
        openPanel: .library,
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
    @Published private(set) var openPanel: PanelID?
    @Published var panelWidth: Double
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

    /// Setting a section during a show ENDS the show rather than restoring over the edit later.
    /// An untouched round trip still restores exactly; a deliberate mid-set change is never
    /// silently thrown away.
    func setExpanded(_ value: Bool, for key: SectionKey) {
        expanded[key] = value
        if showMode {
            showMode = false
            snapshot = nil
        }
    }

    func toggle(_ key: SectionKey) { setExpanded(!isExpanded(key), for: key) }

    // MARK: Panel

    /// Selecting the open panel closes it; selecting another swaps. The rail itself never hides.
    func select(panel: PanelID) {
        openPanel = (openPanel == panel) ? nil : panel
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
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test \
  -only-testing:ARShaderTests/SurfaceLayoutTests 2>&1 | tail -25
```

Expected: 7 tests, all PASS. **Warn the operator first — this launches a second ARShader window.**

- [ ] **Step 6: Mutation-test invariant 2**

Temporarily change `setExpanded` to drop the `showMode = false` line. Re-run.
Expected: `testEditingASectionInShowModeExitsShowModeAndKeepsTheEdit` FAILS. Restore the line and
confirm it passes again. This is the subtle behaviour in the whole design; a test that cannot fail
on it is not pinning it.

- [ ] **Step 7: Commit**

```bash
git add App/ARShader/SurfaceLayout.swift App/ARShader/Deck.swift \
        App/ARShaderTests/SurfaceLayoutTests.swift
git commit -m "feat(m2): SurfaceLayout, the panel framework's state model

One observable owns every layout flag and the show-mode snapshot, with no
SwiftUI import — show mode must snapshot and restore all of it atomically,
which per-view @State cannot do.

Editing a section during a show ENDS the show and keeps the edit rather than
restoring over it later. Mutation-proven: dropping that line fails the test.

Blackout has no SectionKey and no PanelID, so show mode cannot reach it
structurally.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Persist the arrangement

**Files:**
- Create: `App/ARShader/SurfaceLayoutStore.swift`
- Test: `App/ARShaderTests/SurfaceLayoutStoreTests.swift`

**Interfaces:**
- Consumes: `Arrangement` from Task 1.
- Produces: `SurfaceLayoutStore(defaults: UserDefaults)` with `load() -> Arrangement` and
  `save(_: Arrangement)`. Task 4 constructs `SurfaceLayout(store.load())`.

- [ ] **Step 1: Write the failing tests**

Create `App/ARShaderTests/SurfaceLayoutStoreTests.swift`:

```swift
import XCTest

@MainActor
final class SurfaceLayoutStoreTests: XCTestCase {

    private func makeDefaults() throws -> UserDefaults {
        let suite = "arshader-surface-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAnUnwrittenStoreReturnsTheDefaultArrangement() throws {
        let store = SurfaceLayoutStore(defaults: try makeDefaults())
        XCTAssertEqual(store.load(), .default,
                       "First launch gets the default arrangement, never an empty one")
    }

    func testASavedArrangementSurvivesAReload() throws {
        let defaults = try makeDefaults()
        var saved = Arrangement.default
        saved.openPanel = .settings
        saved.panelWidth = 412
        saved.expanded[.deck(.two, .fx)] = false

        SurfaceLayoutStore(defaults: defaults).save(saved)

        // A SEPARATE store instance — this is the relaunch, not a cache read.
        XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), saved)
    }

    func testCorruptStoredDataFallsBackToTheDefaultRatherThanCrashing() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: SurfaceLayoutStore.key)

        XCTAssertEqual(SurfaceLayoutStore(defaults: defaults).load(), .default,
                       "A corrupt arrangement must not take the instrument down at launch")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'SurfaceLayoutStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/ARShader/SurfaceLayoutStore.swift`:

```swift
import Foundation

/// Reads and writes the surface `Arrangement` as one JSON blob.
///
/// One key, not N `@AppStorage` keys: the flags are restored together or the restore is wrong, and
/// separate keys can drift out of sync with each other across app versions.
struct SurfaceLayoutStore {
    static let key = "ARShader.surfaceArrangement"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Any failure — absent, truncated, from a future schema — yields the default arrangement.
    /// A corrupt layout must never be able to stop the instrument launching.
    func load() -> Arrangement {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(Arrangement.self, from: data)
        else { return .default }
        return decoded
    }

    func save(_ arrangement: Arrangement) {
        guard let data = try? JSONEncoder().encode(arrangement) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test \
  -only-testing:ARShaderTests/SurfaceLayoutStoreTests 2>&1 | tail -20
```

Expected: 3 tests PASS. **Warn the operator — second window.**

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/SurfaceLayoutStore.swift App/ARShaderTests/SurfaceLayoutStoreTests.swift
git commit -m "feat(m2): persist the surface arrangement as one blob

One key rather than N @AppStorage keys — the flags restore together or the
restore is wrong, and separate keys drift across versions. Corrupt or
future-schema data falls back to the default instead of failing launch.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: The rail

**Files:**
- Create: `App/ARShader/PanelRailView.swift`
- Test: covered by `SurfaceLayoutTests` invariant 4 (the rail is a thin view over `select(panel:)`)
  plus the Task 9 geometry gate.

**Interfaces:**
- Consumes: `PanelID`, `SurfaceLayout.select(panel:)`, `SurfaceLayout.openPanel` from Task 1.
- Produces: `PanelRailView(layout:)`, a fixed 44pt-wide view.

- [ ] **Step 1: Write the implementation**

There is no new logic to test here — the selection semantics are already pinned by Task 1
invariant 4, and the rail's *appearance* is gated in Task 9. Writing a test that asserts a SwiftUI
body renders buttons would test SwiftUI, not this code.

Create `App/ARShader/PanelRailView.swift`:

```swift
import SwiftUI

/// The always-visible tool rail. Fixed 44pt, full height, far left.
///
/// It never hides — including in show mode. A rail that could disappear would leave the operator
/// with no way back to a tool except a keyboard shortcut they may not remember mid-set.
///
/// Adding a tool in a later phase is one `PanelID` case. That is the point of a rail over a set of
/// fixed regions: a new tool costs no layout renegotiation and no screen space when closed.
struct PanelRailView: View {
    @ObservedObject var layout: SurfaceLayout

    static let width: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(PanelID.allCases.enumerated()), id: \.element) { index, panel in
                Button { layout.select(panel: panel) } label: {
                    Image(systemName: panel.systemImage)
                        .font(.system(size: 15))
                        // 44x44 minimum hit target — this gets aimed at mid-set.
                        .frame(width: Self.width, height: Self.width)
                        .background(layout.openPanel == panel
                                    ? Color.accentColor.opacity(0.30) : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(panel.title) (⌘⌥\(index + 1))")
            }
            Spacer()
        }
        .frame(width: Self.width)
        .background(Color.black)
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED. No window.

- [ ] **Step 3: Commit**

```bash
git add App/ARShader/PanelRailView.swift
git commit -m "feat(m2): the tool rail

Fixed 44pt, always visible including in show mode — only the panel beside it
opens and closes. Adding a tool later is one PanelID case.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `InstrumentSurface` — geometry, and the flexible monitor row

**Files:**
- Create: `App/ARShader/InstrumentSurface.swift`
- Modify: `App/ARShader/Instrument.swift` (own a `SurfaceLayout`)
- Modify: `App/ARShader/InstrumentView.swift:104-126` (adopt the surface)

**Interfaces:**
- Consumes: `SurfaceLayout`, `PanelRailView`, `SurfaceLayoutStore`.
- Produces: `InstrumentSurface<Panel: View, Monitors: View, Strips: View, Mixer: View>`, and
  `Instrument.surfaceLayout: SurfaceLayout`. Task 9 renders `InstrumentSurface` with stub content.

**This is the task that makes collapsing worth anything.** Today the monitor row is pinned at
`.frame(maxHeight: 260)` and the deck strips take the rest, so collapsing a section would free
space nothing uses. The generic container exists so the *real* layout code can be rendered in a
test with a coloured rectangle in place of the live Metal monitors.

- [ ] **Step 1: Write the implementation**

Create `App/ARShader/InstrumentSurface.swift`:

```swift
import SwiftUI

/// The four-region geometry of the instrument window: rail | panel | content | mixer, with the
/// content column split into a flexible monitor row over a content-sized deck-strip row.
///
/// Generic over its content so tests can render this exact layout code with stub views — the live
/// monitors are Metal-backed and cannot be rendered in a unit test, and a layout gate that skips
/// the layout is worthless.
struct InstrumentSurface<Panel: View, Monitors: View, Strips: View, Mixer: View>: View {
    @ObservedObject var layout: SurfaceLayout
    @ViewBuilder var panel: () -> Panel
    @ViewBuilder var monitors: () -> Monitors
    @ViewBuilder var strips: () -> Strips
    @ViewBuilder var mixer: () -> Mixer

    /// The monitors never shrink below this, however much is expanded below them.
    static var minMonitorHeight: CGFloat { 160 }
    static var minPanelWidth: CGFloat { 260 }

    var body: some View {
        HStack(spacing: 0) {
            PanelRailView(layout: layout)
            Divider()

            if layout.openPanel != nil {
                panel()
                    .frame(width: CGFloat(layout.panelWidth))
                    .frame(minWidth: Self.minPanelWidth)
                Divider()
            }

            VStack(spacing: 0) {
                // Flexible, and FIRST in the greedy order: the monitor row takes whatever the deck
                // strips are not using. Collapsing a section hands its height straight to the
                // picture — without this the feature frees space nothing uses, and "the monitors
                // are too small" is untouched no matter how much collapses.
                monitors()
                    .frame(minHeight: Self.minMonitorHeight, maxHeight: .infinity)
                Divider()
                // Content-sized: shrinks as sections collapse rather than holding its height.
                strips()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Divider()
            mixer()
        }
        .background(Color.black)
    }
}
```

- [ ] **Step 2: Give `Instrument` a `SurfaceLayout`**

Modify `App/ARShader/Instrument.swift`. After the `let elementStats = ElementStatsModel()` line
(currently line 20), add:

```swift
    /// Panel, section and show-mode state. Restored from the last launch.
    let surfaceLayout: SurfaceLayout
    private let surfaceStore = SurfaceLayoutStore()
```

and in `init()`, as the FIRST statement of the body:

```swift
        self.surfaceLayout = SurfaceLayout(SurfaceLayoutStore().load())
```

- [ ] **Step 3: Adopt the surface in `InstrumentView`**

Modify `App/ARShader/InstrumentView.swift`. Add to the stored properties (after
`@ObservedObject private var stats: RenderStatsModel`, line 89):

```swift
    @ObservedObject private var layout: SurfaceLayout
```

and in `init(instrument:)`, after `self.stats = instrument.renderStats`:

```swift
        self.layout = instrument.surfaceLayout
```

Replace the whole `body` (lines 104-126) with:

```swift
    var body: some View {
        InstrumentSurface(layout: layout) {
            panelContent
        } monitors: {
            monitors
        } strips: {
            deckStrips
        } mixer: {
            mixerStrip.frame(width: 200)
        }
        .onAppear {
            if keys == nil {
                let monitor = BlackoutKeyMonitor(mixer: mixer) {
                    instrument.output.toggleFullscreen()
                }
                monitor.start()
                keys = monitor
            }
        }
        .onDisappear { keys?.stop(); keys = nil }
    }

    /// Whichever tool the rail has open. Task 7 adds `.settings`.
    @ViewBuilder private var panelContent: some View {
        switch layout.openPanel {
        case .library:
            LibraryPanelView(instrument: instrument, target: $libraryTarget)
        case .settings:
            SettingsPanelView(instrument: instrument)
        case nil:
            EmptyView()
        }
    }
```

Also remove the `.frame(maxHeight: 260)` from `monitors` (line 137) — the surface owns that
allocation now. The `.padding(10)` stays.

Note `SettingsPanelView` does not exist until Task 7; this task will not compile until then. To
keep Task 4 independently testable, stub it now at the bottom of `InstrumentSurface.swift`:

```swift
/// Replaced by the real panel in Task 7.
struct SettingsPanelView: View {
    let instrument: Instrument
    var body: some View { Color.clear }
}
```

- [ ] **Step 4: Build and run the full ARShader suite**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -25
```

Expected: **191 tests** (181 baseline + 7 from Task 1 + 3 from Task 2), all PASS.
**Warn the operator — second window.**

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/InstrumentSurface.swift App/ARShader/Instrument.swift \
        App/ARShader/InstrumentView.swift
git commit -m "feat(m2): the surface container, and a flexible monitor row

The monitor row stops being pinned at 260pt and takes whatever the deck strips
are not using; the strip row becomes content-sized. This is the mechanism that
makes collapsing worth anything — without it a collapsed section frees space
nothing uses.

Generic over its content so the real layout code can be rendered in a test with
stubs. The live monitors are Metal-backed and cannot render in a unit test, and
a layout gate that skips the layout is worthless.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `CollapsibleSection`

**Files:**
- Create: `App/ARShader/CollapsibleSection.swift`

**Interfaces:**
- Consumes: `SurfaceLayout.isExpanded(_:)`, `SurfaceLayout.toggle(_:)`, `SectionKey`.
- Produces: `CollapsibleSection(title:summary:key:layout:content:)`. Task 6 uses it four times.

- [ ] **Step 1: Write the implementation**

Create `App/ARShader/CollapsibleSection.swift`:

```swift
import SwiftUI

/// A titled section that collapses to a single header row.
///
/// The header ALWAYS carries a summary — `FX 3`, `PARAMETERS 12`, `SOURCES cam→in0`. Collapsing
/// hides detail; it must never hide the fact that detail exists. The failure mode of a collapsible
/// surface is a control the operator cannot find, and a bare header with no count is that failure
/// mode by design. (Phase 2 shipped a disclosure triangle that opened onto nothing; this is the
/// same class caught at the component.)
///
/// The whole header is the hit target, not just the chevron — a 12pt glyph is a poor thing to aim
/// at mid-set.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Shown on the header in BOTH states. Empty string is allowed but discouraged.
    let summary: String
    let key: SectionKey
    @ObservedObject var layout: SurfaceLayout
    @ViewBuilder var content: () -> Content

    private var isExpanded: Bool { layout.isExpanded(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { layout.toggle(key) } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title) — \(summary)")

            if isExpanded { content() }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/ARShader/CollapsibleSection.swift
git commit -m "feat(m2): CollapsibleSection, with a summary that survives collapse

The header carries its count in both states. Collapsing hides detail, never the
fact that detail exists — phase 2 shipped a triangle that opened onto nothing,
and a bare collapsed header is the same class.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Collapse the deck strips and the master strip

**Files:**
- Modify: `App/ARShader/InstrumentView.swift` (`DeckStripView.body` lines 23-80; `masterStrip`
  lines 154-167)

**Interfaces:**
- Consumes: `CollapsibleSection`, `SectionKey`, `SurfaceLayout`, and the existing
  `SourceRoutingView`, `FXChainView`, `ShaderControlsView`.
- Produces: no new API.

- [ ] **Step 1: Give `DeckStripView` the layout**

Add to `DeckStripView`'s stored properties (after `@ObservedObject var library: LibraryModel`,
line 19):

```swift
    @ObservedObject var layout: SurfaceLayout
```

Update its construction in `deckStrips` (line 143-145):

```swift
                DeckStripView(id: id, unit: instrument.deck(id).unit, mixer: mixer,
                              fx: instrument.deck(id).fx, stats: stats,
                              library: instrument.library, layout: layout)
```

- [ ] **Step 2: Add the summary helpers to `DeckStripView`**

Add these computed properties to `DeckStripView`, above `body`:

```swift
    /// Routable image inputs, summarised for the collapsed header. A generator has none and the
    /// section is not rendered at all.
    private var sourceRows: [DeckControlModel.ControlRow] {
        DeckControlModel.rows(for: unit.inputs, reservesPrimaryInput: unit.reservesPrimaryInput)
            .filter { $0.kind == .routed || $0.kind == .chainFed }
    }

    private var sourcesSummary: String {
        let first = sourceRows.first.map { unit.imageSources.source(for: $0.input.name).displayName }
        guard let first else { return "" }
        return sourceRows.count > 1 ? "\(first) +\(sourceRows.count - 1)" : first
    }

    /// Non-image controls — what ShaderControlsView actually renders.
    private var parameterCount: Int {
        DeckControlModel.rows(for: unit.inputs, reservesPrimaryInput: unit.reservesPrimaryInput)
            .filter { $0.kind != .routed && $0.kind != .chainFed }
            .count
    }
```

- [ ] **Step 3: Rewrite `DeckStripView.body`**

Replace lines 23-80 (the whole `body`) with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Performance controls. These never collapse. ──
            HStack {
                Text("DECK \(id.displayName)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                if unit.isLoading { ProgressView().controlSize(.small) }
                Button("Clear") { unit.unload() }.controlSize(.small)
            }
            Text(unit.shaderName ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(unit.shaderName == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
                .help(unit.shaderName ?? "No shader loaded")

            HStack {
                Text("Opacity").font(.system(size: 11))
                Spacer()
                Text(String(format: "%.2f", layer?.userOpacity ?? 1))
                    .font(.system(size: 11, design: .monospaced))
                Text(String(format: "→ %.2f", layer?.effectiveOpacity ?? 1))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("Effective opacity after the crossfader")
            }
            Slider(value: Binding(
                get: { mixer.opacity[id] ?? 1 },
                set: { mixer.setOpacity($0, for: id) }), in: 0...1)

            Picker("Blend", selection: Binding(
                get: { mixer.blendMode[id] ?? .normal },
                set: { mixer.setBlendMode($0, for: id) })) {
                Section("Standard") {
                    ForEach(BlendMode.allCases.filter(\.isW3CSeparable)) {
                        Text($0.displayName).tag($0)
                    }
                }
                Section("Extended") {
                    ForEach(BlendMode.allCases.filter { !$0.isW3CSeparable }) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            // ── Configuration. These collapse. ──
            // A generator has no image inputs, so the SOURCES section is absent entirely rather
            // than present-and-empty — same rule SourceRoutingView already follows.
            if !sourceRows.isEmpty {
                Divider()
                CollapsibleSection(title: "SOURCES", summary: sourcesSummary,
                                   key: .deck(id, .sources), layout: layout) {
                    SourceRoutingView(unit: unit, library: library)
                }
            }

            Divider()
            CollapsibleSection(title: "FX", summary: "\(fx.stages.count)",
                               key: .deck(id, .fx), layout: layout) {
                FXChainView(title: "FX", chain: fx, stats: stats, library: library)
            }

            Divider()
            CollapsibleSection(title: "PARAMETERS", summary: "\(parameterCount)",
                               key: .deck(id, .parameters), layout: layout) {
                ShaderControlsView(unit: unit)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

`SourceRoutingView` renders its own `SOURCES` header; remove it there so the section header is not
doubled. In `App/ARShader/SourceRoutingView.swift`, delete lines 35-36:

```swift
                Text("SOURCES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
```

- [ ] **Step 4: Collapse the master strip's FX**

Replace `masterStrip` (lines 154-167) with:

```swift
    private var masterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MASTER").font(.system(size: 12, weight: .bold, design: .monospaced))
            Text("Applied to the program feed, before blackout.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            CollapsibleSection(title: "MASTER FX",
                               summary: "\(instrument.renderer.masterFX.stages.count)",
                               key: .masterFX, layout: layout) {
                FXChainView(title: "MASTER FX", chain: instrument.renderer.masterFX,
                            stats: stats, library: instrument.library)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

The `ScrollView` that wrapped the master chain is deliberately dropped: the strip row is now
content-sized (Task 4) and a `ScrollView` inside a content-sized container has no intrinsic height
— exactly the phase-2 defect. `masterStrip` must observe the chain to keep the count live; add to
`InstrumentView`'s stored properties:

```swift
    @ObservedObject private var masterFX: FXChain
```

and in `init`, after `self.layout = instrument.surfaceLayout`:

```swift
        self.masterFX = instrument.renderer.masterFX
```

then use `masterFX.stages.count` and `chain: masterFX` in `masterStrip`.

- [ ] **Step 5: Run the full suite**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -25
```

Expected: 191 PASS. **Warn the operator — second window.**

- [ ] **Step 6: Commit**

```bash
git add App/ARShader/InstrumentView.swift App/ARShader/SourceRoutingView.swift
git commit -m "feat(m2): collapse the configuration sections in place

SOURCES, FX and PARAMETERS collapse; deck name, opacity and blend do not.
Configuration collapses, performance never does — one rule at both levels.

The master chain's ScrollView is dropped: the strip row is content-sized now,
and a ScrollView with no intrinsic height inside one is exactly the phase-2
defect that opened onto nothing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: The settings panel

**Files:**
- Create: `App/ARShader/SettingsPanelView.swift`
- Modify: `App/ARShader/InstrumentSurface.swift` (delete the Task 4 stub)
- Modify: `App/ARShader/InstrumentView.swift` (`resolutionPickers` lines 214-285, `outputPicker`
  lines 391-404, `mixerStrip` lines 169-209)

**Interfaces:**
- Consumes: `Instrument`, `RenderSize`, `RenderScale`, `OutputWindowController`, `ScreenInfo`,
  `OutputMenu`.
- Produces: `SettingsPanelView(instrument:)`.

`OUTPUT RES` and the `OUTPUT` destination picker move. `PREVIEW SCALE` and `CUE SCALE` **stay on
the mixer strip** — they are what gets reached for when the GPU is struggling during a set, and a
panel-open gesture at that moment is the wrong cost.

- [ ] **Step 1: Delete the stub**

Remove the `SettingsPanelView` stub from the bottom of `App/ARShader/InstrumentSurface.swift`.

- [ ] **Step 2: Create the panel**

Create `App/ARShader/SettingsPanelView.swift`. Move `applyOutput`, `commitTypedResolution`, the
`OUTPUT RES` block from `resolutionPickers`, and `outputPicker` here verbatim:

```swift
import SwiftUI

/// Load-in configuration: what the instrument renders at, and where it goes.
///
/// These are set once before a show, not reached for mid-song — which is why they left the mixer
/// strip. PREVIEW SCALE and CUE SCALE deliberately did NOT come with them: those are the controls
/// the operator reaches for when the GPU is struggling during a set, and a panel-open gesture at
/// that moment is the wrong cost.
struct SettingsPanelView: View {
    let instrument: Instrument
    @ObservedObject private var output: OutputWindowController
    @State private var widthField = ""
    @State private var heightField = ""

    init(instrument: Instrument) {
        self.instrument = instrument
        self.output = instrument.output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTINGS").font(.system(size: 12, weight: .bold, design: .monospaced))
            Divider()
            outputResolution
            Divider()
            outputPicker
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: syncFields)
    }

    private var outputResolution: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("OUTPUT RES").font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                // Presets are a convenience tucked into a menu, not the vocabulary — typing a size
                // is the primary control.
                Menu {
                    ForEach(RenderSize.presets, id: \.self) { preset in
                        Button(preset.label) { apply(preset) }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Common sizes")
            }
            HStack(spacing: 4) {
                TextField("W", text: $widthField)
                    .textFieldStyle(.roundedBorder).frame(width: 62)
                    .onSubmit { commitTyped() }
                Text("×").foregroundStyle(.secondary)
                TextField("H", text: $heightField)
                    .textFieldStyle(.roundedBorder).frame(width: 62)
                    .onSubmit { commitTyped() }
                Button("Set") { commitTyped() }.controlSize(.small)
            }
            .font(.system(size: 11, design: .monospaced))
            Text(String(format: "%.1f MP", instrument.renderer.outputResolution.megapixels))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    /// Output ships CLOSED; this is the deliberate operator enable.
    private var outputPicker: some View {
        let screens = ScreenInfo.current()
        return VStack(alignment: .leading, spacing: 4) {
            Text("OUTPUT").font(.system(size: 11, weight: .bold, design: .monospaced))
            Picker("", selection: Binding(
                get: { output.destination },
                set: { output.setDestination($0) })) {
                ForEach(OutputMenu.options(for: screens), id: \.self) { option in
                    Text(OutputMenu.title(for: option, screens: screens)).tag(option)
                }
            }
            .labelsHidden()
        }
    }

    private func apply(_ size: RenderSize) {
        instrument.renderer.outputResolution = size
        syncFields()
    }

    /// A field that is empty or nonsense keeps the current value rather than snapping to a default
    /// — losing a deliberately-set output size to a stray keystroke mid-set would be worse than
    /// ignoring the edit.
    private func commitTyped() {
        let current = instrument.renderer.outputResolution
        let w = Int(widthField.trimmingCharacters(in: .whitespaces)) ?? current.width
        let h = Int(heightField.trimmingCharacters(in: .whitespaces)) ?? current.height
        apply(RenderSize(width: w, height: h))   // RenderSize clamps to safe bounds
    }

    private func syncFields() {
        let r = instrument.renderer.outputResolution
        widthField = String(r.width)
        heightField = String(r.height)
    }
}
```

- [ ] **Step 3: Strip the moved controls out of `InstrumentView`**

In `App/ARShader/InstrumentView.swift`:

1. Delete `outputPicker` (lines 391-404), `applyOutput` (348-351), `commitTypedResolution`
   (356-361), and the `widthField` / `heightField` `@State` properties (92-93).
2. In `mixerStrip`, replace `resolutionPickers` and `outputPicker` with a single `scalePickers`.
3. Replace `resolutionPickers` (lines 214-285) with:

```swift
    /// The two scales stay on the strip: these are what gets reached for when the GPU is
    /// struggling mid-set. Output size and destination moved to the settings panel.
    private var scalePickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            scaleField(title: "PREVIEW SCALE",
                       text: $renderScaleField,
                       current: instrument.renderer.previewScale,
                       resolved: instrument.renderer.previewScale
                           .applied(to: instrument.renderer.outputResolution),
                       caption: "rasterising",
                       help: "What live decks AND the program composite actually rasterise at. "
                           + "With output closed these panes are the only thing looking, and they "
                           + "are tiny — so dropping this is free GPU at no visible cost. While "
                           + "projecting it also softens the projected image, which is what the "
                           + "warning is for.",
                       warning: projectingUpscaled ? "PROJECTING BELOW 100%" : nil,
                       apply: { instrument.renderer.previewScale = $0 })

            scaleField(title: "CUE SCALE",
                       text: $cueScaleField,
                       current: instrument.renderer.cueRenderScale,
                       resolved: instrument.renderer.cueRenderScale
                           .applied(to: instrument.renderer.previewScale
                               .applied(to: instrument.renderer.outputResolution)),
                       caption: "cued decks",
                       help: "What a deck rasterises at while it is NOT on program — a loaded deck "
                           + "you have faded out. This reallocates nothing and never touches the "
                           + "projected image, so it is safe to drop very low. It is also the only "
                           + "saving still available while you ARE projecting.",
                       warning: nil,
                       apply: { instrument.renderer.cueRenderScale = $0 })
        }
        .onAppear { syncResolutionFields() }
    }
```

4. Trim `syncResolutionFields` to the two scale fields:

```swift
    private func syncResolutionFields() {
        renderScaleField = String(instrument.renderer.previewScale.percent)
        cueScaleField = String(instrument.renderer.cueRenderScale.percent)
    }
```

- [ ] **Step 4: Run the full suite**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -25
```

Expected: 191 PASS. If `OutputDestinationTests` or `RenderScaleTests` fail, the move broke a
reference — fix rather than adjust the assertion.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/SettingsPanelView.swift App/ARShader/InstrumentView.swift \
        App/ARShader/InstrumentSurface.swift
git commit -m "feat(m2): a settings panel, and the mixer strip gets its space back

OUTPUT RES and the output destination move to the rail — set at load-in, not
mid-song. PREVIEW SCALE and CUE SCALE stay on the strip: those are what gets
reached for when the GPU is struggling during a set.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Show mode and keyboard shortcuts

**Files:**
- Modify: `App/ARShader/InstrumentView.swift` (`mixerStrip`, and a `.background` for shortcuts)

**Interfaces:**
- Consumes: `SurfaceLayout.toggleShowMode()`, `SurfaceLayout.select(panel:)`.
- Produces: no new API.

`⌘⇧P` toggles show mode; `⌘⌥1`…`⌘⌥9` select by rail position. Verified clear of `⌘B` (blackout
latch), Escape (momentary blackout) and `⌘⇧F` (output fullscreen), all owned by
`BlackoutKeyMonitor`.

- [ ] **Step 1: Add the show-mode button to the mixer strip**

In `mixerStrip`, directly above the `BLACKOUT` button, add:

```swift
            Button { layout.toggleShowMode() } label: {
                Text(layout.showMode ? "SHOW MODE ON" : "SHOW MODE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.bordered)
            .tint(layout.showMode ? .accentColor : .gray)
            .help("⌘⇧P collapses every section and closes the panel, so the monitors take the "
                  + "space. Press it again to restore. Touching a section while in show mode "
                  + "leaves show mode and keeps your change.")
```

Update the shortcut hint at the bottom of `mixerStrip`:

```swift
            Text("⌘B latch · hold ESC · ⌘⇧F output · ⌘⇧P show")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
```

- [ ] **Step 2: Add the keyboard shortcuts**

SwiftUI `.keyboardShortcut` needs a focusable control. Attach hidden zero-size buttons in a
`.background` on the `InstrumentSurface` in `body`:

```swift
        .background(shortcuts)
```

and add to `InstrumentView`:

```swift
    /// Hidden buttons that exist only to carry keyboard shortcuts. `.keyboardShortcut` needs a
    /// control; these are the smallest thing that is one. Blackout stays with BlackoutKeyMonitor —
    /// it must work even when SwiftUI focus is somewhere unhelpful.
    private var shortcuts: some View {
        ZStack {
            Button("") { layout.toggleShowMode() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            ForEach(Array(PanelID.allCases.enumerated()), id: \.element) { index, panel in
                Button("") { layout.select(panel: panel) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                      modifiers: [.command, .option])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
```

- [ ] **Step 3: Persist the arrangement on change**

The arrangement must survive a relaunch. In `InstrumentView.body`, on the `InstrumentSurface`:

```swift
        .onChange(of: layout.arrangement) { _, new in
            SurfaceLayoutStore().save(new)
        }
```

`Arrangement` is `Equatable` (Task 1), so this fires only on real changes.

- [ ] **Step 4: Run the full suite**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -25
```

Expected: 191 PASS.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/InstrumentView.swift
git commit -m "feat(m2): show mode, its shortcut, and arrangement persistence

⌘⇧P collapses everything and closes the panel; ⌘⌥1..9 select by rail position.
Clear of ⌘B, Escape and ⌘⇧F, which stay with BlackoutKeyMonitor so blackout
works regardless of where SwiftUI focus is.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Layout gates — geometry assertions and PNG baselines

**Files:**
- Create: `App/ARShaderTests/SurfaceRenderHarness.swift`
- Create: `App/ARShaderTests/SurfaceGeometryTests.swift`
- Create: `App/ARShaderTests/Baselines/` (PNG output, committed)
- Modify: `App/project.yml` (add `Baselines` as a test resource)

**Interfaces:**
- Consumes: `InstrumentSurface`, `CollapsibleSection`, `SurfaceLayout`.
- Produces: `SurfaceRenderHarness.render(_:size:) -> NSView`,
  `SurfaceRenderHarness.frames(in:) -> [String: CGRect]`,
  `SurfaceRenderHarness.png(_:size:) -> Data?`.

**A deliberate deviation from the spec's §5.2, stated rather than silent.** The spec says
"screenshot baselines." Pure pixel diffing is brittle — text rendering and control metrics shift
across macOS point releases, and a baseline that goes red on an OS update trains you to regenerate
it without looking, which is worse than no gate. The defects that actually shipped were *geometry*
failures: a pane collapsing to ~0 height, a button at the wrong size. So this harness renders the
view tree ONCE and gates on two things: **measured subview geometry (load-bearing)** and **PNG
baselines (supplementary, regenerable)**. If the operator wants pixel-only, drop `SurfaceSnapshot`
and keep the geometry tests — they are the ones that catch the real class.

- [ ] **Step 1: Write the harness**

Create `App/ARShaderTests/SurfaceRenderHarness.swift`:

```swift
import AppKit
import SwiftUI

/// Renders a SwiftUI view into a real laid-out AppKit view tree, so tests can measure what the
/// layout actually did.
///
/// Why this exists: 181 green tests said nothing about a ScrollView that collapsed to zero height,
/// dropdowns lost among sliders, or a 56pt button slab. Every defect that reached the operator for
/// three sessions was invisible to assertions on state. This measures geometry instead.
///
/// Every view baselined here must be pure SwiftUI — the live monitors are Metal-backed and cannot
/// render in a unit test, which is exactly why `InstrumentSurface` is generic over its content.
@MainActor
enum SurfaceRenderHarness {

    static func render<V: View>(_ view: V, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // A second pass: SwiftUI resolves some sizes only after the first layout settles.
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// Frames of every accessibility-identified subview, in the host's coordinate space.
    /// Views under test tag themselves with `.accessibilityIdentifier(_:)`.
    static func frames(in root: NSView) -> [String: CGRect] {
        var out: [String: CGRect] = [:]
        func walk(_ v: NSView) {
            if let id = v.accessibilityIdentifier(), !id.isEmpty {
                out[id] = v.convert(v.bounds, to: root)
            }
            v.subviews.forEach(walk)
        }
        walk(root)
        return out
    }

    static func png<V: View>(_ view: V, size: CGSize) -> Data? {
        let host = render(view, size: size)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Compare against a committed baseline. Set `ARSHADER_RECORD_BASELINES=1` to (re)record.
    /// Returns nil on success, or a human-readable reason on failure.
    static func compareBaseline(_ data: Data, named name: String) -> String? {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Baselines")
        let file = dir.appendingPathComponent("\(name).png")

        if ProcessInfo.processInfo.environment["ARSHADER_RECORD_BASELINES"] == "1" {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file)
            return nil
        }
        guard let baseline = try? Data(contentsOf: file) else {
            return "No baseline for \(name). Record with ARSHADER_RECORD_BASELINES=1."
        }
        return baseline == data ? nil : "\(name) differs from its baseline."
    }
}
```

- [ ] **Step 2: Tag the views under test**

The geometry gate needs identifiers. Add these `.accessibilityIdentifier` calls:

In `App/ARShader/InstrumentSurface.swift`, on the monitors and strips:

```swift
                monitors()
                    .frame(minHeight: Self.minMonitorHeight, maxHeight: .infinity)
                    .accessibilityIdentifier("surface.monitors")
                Divider()
                strips()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("surface.strips")
```

and on the panel:

```swift
                panel()
                    .frame(width: CGFloat(layout.panelWidth))
                    .frame(minWidth: Self.minPanelWidth)
                    .accessibilityIdentifier("surface.panel")
```

In `App/ARShader/CollapsibleSection.swift`, on the content:

```swift
            if isExpanded {
                content().accessibilityIdentifier("section.\(title).content")
            }
```

- [ ] **Step 3: Write the failing tests**

Create `App/ARShaderTests/SurfaceGeometryTests.swift`:

```swift
import XCTest
import SwiftUI

@MainActor
final class SurfaceGeometryTests: XCTestCase {

    private static let windowSize = CGSize(width: 1600, height: 1000)

    /// A stand-in for the Metal monitor row: same layout participation, no GPU.
    private func stubSurface(layout: SurfaceLayout, stripHeight: CGFloat) -> some View {
        InstrumentSurface(layout: layout) {
            Color.gray
        } monitors: {
            Color.blue
        } strips: {
            Color.green.frame(height: stripHeight)
        } mixer: {
            Color.red.frame(width: 200)
        }
    }

    /// THE gate. Collapsing must hand height to the picture, not leave grey space.
    func testTheMonitorRowGrowsWhenTheStripsShrink() {
        let layout = SurfaceLayout()

        let tall = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            stubSurface(layout: layout, stripHeight: 600), size: Self.windowSize))
        let short = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            stubSurface(layout: layout, stripHeight: 120), size: Self.windowSize))

        let tallMonitors = try! XCTUnwrap(tall["surface.monitors"]).height
        let shortMonitors = try! XCTUnwrap(short["surface.monitors"]).height

        XCTAssertGreaterThan(shortMonitors, tallMonitors + 400,
                             "Every point the strips give up must reach the monitor row. If this "
                             + "fails, collapsing frees space nothing uses and the whole feature "
                             + "is cosmetic.")
    }

    func testTheMonitorRowNeverGoesBelowItsFloor() {
        let layout = SurfaceLayout()
        let frames = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            stubSurface(layout: layout, stripHeight: 5000), size: Self.windowSize))

        XCTAssertGreaterThanOrEqual(try! XCTUnwrap(frames["surface.monitors"]).height,
                                    InstrumentSurface<Color, Color, Color, Color>.minMonitorHeight,
                                    "A very tall strip column must not squeeze the picture to nothing")
    }

    func testClosingThePanelGivesItsWidthToTheContent() {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        let open = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            stubSurface(layout: layout, stripHeight: 300), size: Self.windowSize))
        XCTAssertNotNil(open["surface.panel"])
        let openMonitorWidth = try! XCTUnwrap(open["surface.monitors"]).width

        layout.select(panel: .library)   // close
        let closed = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            stubSurface(layout: layout, stripHeight: 300), size: Self.windowSize))

        XCTAssertNil(closed["surface.panel"], "A closed panel is absent, not zero-width")
        XCTAssertGreaterThan(try! XCTUnwrap(closed["surface.monitors"]).width, openMonitorWidth,
                             "The closed panel's width reaches the content column")
    }

    /// The phase-2 defect, caught at the component: a section that "opens" onto nothing.
    func testAnExpandedSectionHasRealHeightAndACollapsedOneIsAbsent() {
        let layout = SurfaceLayout()
        let section = { (l: SurfaceLayout) in
            CollapsibleSection(title: "FX", summary: "3", key: .masterFX, layout: l) {
                VStack { ForEach(0..<5, id: \.self) { _ in Slider(value: .constant(0.5)) } }
            }
        }

        layout.setExpanded(true, for: .masterFX)
        let expanded = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            section(layout), size: CGSize(width: 300, height: 400)))
        XCTAssertGreaterThan(try! XCTUnwrap(expanded["section.FX.content"]).height, 60,
                             "An expanded section must contain something visible — a disclosure "
                             + "that opens onto nothing shipped in phase 2")

        layout.setExpanded(false, for: .masterFX)
        let collapsed = SurfaceRenderHarness.frames(in: SurfaceRenderHarness.render(
            section(layout), size: CGSize(width: 300, height: 400)))
        XCTAssertNil(collapsed["section.FX.content"])
    }

    // MARK: PNG baselines (supplementary — regenerable with ARSHADER_RECORD_BASELINES=1)

    func testSurfaceBaselines() throws {
        let cases: [(String, () -> SurfaceLayout)] = [
            ("panel-closed", { let l = SurfaceLayout(); l.select(panel: .library); return l }),
            ("panel-library", { SurfaceLayout() }),
            ("show-mode",     { let l = SurfaceLayout(); l.toggleShowMode(); return l }),
        ]
        for (name, make) in cases {
            let data = try XCTUnwrap(SurfaceRenderHarness.png(
                stubSurface(layout: make(), stripHeight: 300), size: Self.windowSize))
            if let reason = SurfaceRenderHarness.compareBaseline(data, named: name) {
                XCTFail(reason)
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify they fail, then record baselines**

```bash
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test \
  -only-testing:ARShaderTests/SurfaceGeometryTests 2>&1 | tail -30
```

Expected: geometry tests PASS (Task 4 already implemented the behaviour), `testSurfaceBaselines`
FAILS with "No baseline". Record them:

```bash
ARSHADER_RECORD_BASELINES=1 xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test \
  -only-testing:ARShaderTests/SurfaceGeometryTests 2>&1 | tail -10
```

Then re-run without the variable and confirm all PASS.

- [ ] **Step 5: MUTATION TEST — prove the gate is load-bearing**

This is the step that makes the suite worth having. In `App/ARShader/InstrumentSurface.swift`,
temporarily restore the old fixed height:

```swift
                monitors()
                    .frame(maxHeight: 260)          // MUTATION — revert after
                    .accessibilityIdentifier("surface.monitors")
```

Re-run `SurfaceGeometryTests`.

Expected: **`testTheMonitorRowGrowsWhenTheStripsShrink` FAILS**, and `show-mode` baseline fails
too. Record both results in the commit message. Restore the correct code and confirm green.

A baseline suite that has never failed on a deliberate break is decoration, not a gate.

- [ ] **Step 6: Register baselines as a test resource**

In `App/project.yml`, under `ARShaderTests: sources:`, after the `Fixtures` entry:

```yaml
      - path: ARShaderTests/Baselines
        buildPhase: resources
        type: folder
```

- [ ] **Step 7: Run the full suite**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -25
```

Expected: **196 tests** (191 + 5), all PASS.

- [ ] **Step 8: Commit**

```bash
git add App/ARShaderTests/SurfaceRenderHarness.swift \
        App/ARShaderTests/SurfaceGeometryTests.swift \
        App/ARShaderTests/Baselines App/project.yml \
        App/ARShader/InstrumentSurface.swift App/ARShader/CollapsibleSection.swift
git commit -m "test(m2): gate the layout on measured geometry, mutation-proven

Every defect that reached the operator for three sessions was invisible to
assertions on state — a ScrollView collapsed to zero height, dropdowns lost
among sliders, a button slab. These render the real layout code with stub
content and measure what it did.

Deliberate deviation from the spec's 'screenshot baselines': pixel diffing
alone is brittle across OS point releases, and a baseline that goes red on an
OS update trains you to regenerate without looking. Geometry assertions are the
load-bearing gate; PNGs are supplementary and regenerable.

Mutation-proven: restoring the old fixed 260pt monitor height fails
testTheMonitorRowGrowsWhenTheStripsShrink and the show-mode baseline.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Full regression, install, and live smoke

**Files:**
- Create: `docs/reports/live-smoke-instrument-m2-phase3a.md`

- [ ] **Step 1: Run all three suites**

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -12
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -12
```

Expected: ARShaderTests **196**, TrueISFEditorTests **514 (3 skipped)**. Run ShadertoyISFKit's
**312** per its usual command. Any reduction is a regression — fix it, do not adjust the count.

- [ ] **Step 2: Install, having warned the operator**

`scripts/run-instrument.sh` QUITS any running ARShader. Check first and say so:

```bash
ps aux | grep '[A]RShader.app/Contents/MacOS/ARShader'
```

Then, after the operator confirms:

```bash
./scripts/run-instrument.sh
```

- [ ] **Step 3: Verify the binary is genuinely fresh**

```bash
strings ~/Applications/ARShader.app/Contents/MacOS/ARShader | grep -c "Show mode collapses every section"
```

Expected: `1` or more. Swift strings ≤15 bytes are invisible to `strings`, which is why a long
marker is used. **Do not tell the operator to relaunch if this is 0.**

- [ ] **Step 4: Write the smoke report with the legs unchecked**

Create `docs/reports/live-smoke-instrument-m2-phase3a.md` with status `PENDING` and these legs:

1. Rail shows two icons; clicking Library opens the panel, clicking it again closes it entirely.
2. Clicking Settings while Library is open swaps without closing.
3. `⌘⌥1` and `⌘⌥2` do the same as clicking.
4. Dragging the panel edge resizes it; it does not go below 260pt.
5. Each of SOURCES, FX, PARAMETERS collapses and expands on both decks independently.
6. A collapsed header still shows its count/summary.
7. **The monitors visibly grow as sections collapse.** (The whole point.)
8. MASTER FX collapses; its stage count stays visible collapsed.
9. `⌘⇧P` collapses everything and closes the panel; `⌘⇧P` again restores it exactly.
10. In show mode, expanding DECK A's FX leaves show mode and keeps FX open; the rest stay collapsed.
11. `⌘B` latches blackout with a panel open, and in show mode. Hold Escape still works.
12. `⌘⇧F` still toggles the output window.
13. OUTPUT RES and the output picker are in Settings and still work; PREVIEW/CUE SCALE are still
    on the mixer strip and still work.
14. Quit and relaunch: the arrangement is exactly as left.
15. A generator on a deck shows no SOURCES section at all (not an empty one).

- [ ] **Step 5: Operator runs the legs and signs them**

Do not mark this phase complete on green tests. **STAGED until the operator has seen it run and
accepted it**, per the on-device gate. Record the result and any defects in the report, set its
status to `CONFIRMED` only on the operator's word, and file an action item for anything deferred.

- [ ] **Step 6: Commit the signed report**

```bash
git add docs/reports/live-smoke-instrument-m2-phase3a.md
git commit -m "docs(m2): phase 3a live smoke — operator ran and signed the legs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §2.1 flexible monitor row | 4 (built), 9 (gated + mutation-proven) |
| §2.2 rail, toggle semantics, shortcuts, width | 3, 8; semantics tested in 1 (#4), width in 9 |
| §2.3 what collapses + summary in header | 5, 6 |
| §2.4 settings panel day one | 7 |
| §2.5 show mode + edit-in-show-mode | 1 (logic + 2 tests), 8 (UI) |
| §3.1 `SurfaceLayout`, `Arrangement` | 1 |
| §3.2 lives in `App/ARShader` | Global Constraints; every Create path |
| §3.3 blackout structurally outside | 1 (test #6), 8 (shortcuts stay with `BlackoutKeyMonitor`) |
| §3.4 custom rail, not `NavigationSplitView` | 3 |
| §4 no visual treatment, library contents unchanged, render path untouched | Global Constraints; Task 6 leaves `FXChainView`/`ShaderControlsView` internals alone |
| §5.1 six invariants | 1 (7 tests — the six plus the collapsible-set pin) |
| §5.2 baselines, mutation-tested | 9, with a stated deviation |
| §5.3 live smoke | 10 |
| §6 failure modes | Each mitigated by the task above; "new deck inherits state" by `SectionKey` (test #5) |

No spec requirement is without a task.

**Placeholder scan:** No "TBD", "TODO", "add error handling", "similar to Task N", or code step
without a code block. The Task 4 `SettingsPanelView` stub is an explicit, named, deleted-in-Task-7
placeholder, not an unfinished instruction.

**Type consistency:** `SurfaceLayout` members used in Tasks 3–8 (`openPanel`, `panelWidth`,
`showMode`, `isExpanded(_:)`, `setExpanded(_:for:)`, `toggle(_:)`, `select(panel:)`,
`toggleShowMode()`, `arrangement`, `apply(_:)`) all exist as written in Task 1.
`SurfaceLayoutStore.load()/save(_:)/key` match Task 2. `InstrumentSurface.minMonitorHeight` and
`minPanelWidth` are used in Task 9 with the generic parameters spelled out. `SectionKey.all` is
defined in Task 1 and used in Tasks 1 and 9. `PanelRailView.width` defined in Task 3, unused
elsewhere by design.

**One known ordering wrinkle, deliberate:** Task 4 introduces a `SettingsPanelView` stub because
`InstrumentView` references it before Task 7 exists. Task 7 step 1 deletes the stub. This keeps
Task 4 independently buildable and testable rather than leaving a task that cannot compile.
