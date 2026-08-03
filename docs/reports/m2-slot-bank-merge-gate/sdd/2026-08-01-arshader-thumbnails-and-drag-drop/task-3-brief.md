### Task 3: Slot cells draw thumbnails, with the three states

**Files:**
- Modify: `App/ARShader/SlotBankStripView.swift` — `SlotCell` (lines 233-308) gains a thumbnail and the three states
- Modify: `App/ARShader/InstrumentSurface.swift:108` — cell metrics grow for an image
- Test: `App/ARShaderTests/SlotCellStateTests.swift` (new)

**Interfaces:**
- Consumes: `ThumbnailService.thumbnail(for:priority:)` and `ThumbnailService.Result` from Task 1.
- Produces: `SlotCellState` (`enum { live(DeckID), idle, unavailable }`) and `SlotCell.state(preset:isAvailable:liveOn:)`, both used by Task 5's drop-target work.

`SlotCell` today is a `Button(action: activate)` wrapping an `HStack` of an index label and a name.
The whole visual body is replaced; **`activate()` (lines 293-301) and the context menu (274-285) are
NOT touched** — that gating is the never-overwrite rule and it is already correct and reviewed.

The state carrier changes from saturation to border+badge, because a thumbnail already spends
colour. See the spec's "Slot cell states" for why desaturation cannot survive photographic cells.

- [ ] **Step 1: Write the failing state test**

Create `App/ARShaderTests/SlotCellStateTests.swift`. The state derivation is pulled OUT of the view
into a pure static function precisely so it is testable without a render harness — the same doctrine
`SurfaceLayout` follows.

```swift
import XCTest
@testable import ARShader

@MainActor
final class SlotCellStateTests: XCTestCase {
    private func preset(_ path: String = "/tmp/a.fs") -> Preset {
        Preset.capturing(url: URL(fileURLWithPath: path), snapshot: ParamSnapshot(params: [:]))
    }

    func testAnEmptySlotIsIdle() {
        XCTAssertEqual(SlotCellState.of(preset: nil, isAvailable: false, liveOn: nil), .idle)
    }

    func testAFilledSlotWhoseFileIsGoneIsUnavailable() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: false, liveOn: nil),
                       .unavailable)
    }

    /// Unavailable OUTRANKS live. A slot whose file vanished while its shader is still playing
    /// must not draw as a healthy live slot — the operator would fire it and get nothing.
    func testUnavailableOutranksLive() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: false, liveOn: .one),
                       .unavailable)
    }

    func testAFilledAvailableSlotPlayingOnADeckIsLiveOnThatDeck() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: true, liveOn: .two),
                       .live(.two))
    }

    func testAFilledAvailableSlotNotPlayingIsIdle() {
        XCTAssertEqual(SlotCellState.of(preset: preset(), isAvailable: true, liveOn: nil), .idle)
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure** (`cannot find 'SlotCellState' in scope`).

- [ ] **Step 3: Add the state type**

In `App/ARShader/SlotBankStripView.swift`, above `SlotCell`:

```swift
/// How one cell reads. Derived rather than stored, so it cannot drift from the bank.
///
/// Border and badge carry the state, NOT saturation. Phase 3b distinguished live from idle by
/// colour-vs-greyscale, which worked when a cell was a flat rectangle and a name. A thumbnail is a
/// photograph and already spends colour: this library runs from near-monochrome ASCII shaders to
/// fully saturated ones, so a greyscale shader's live and idle cells would look identical and a
/// lurid one would read as live while idle. Brightness is the channel a still image does not
/// already own.
enum SlotCellState: Equatable {
    case live(DeckID)
    case idle
    case unavailable

    /// Unavailable outranks live: a slot whose file vanished must never draw as healthy, because
    /// the operator would fire it and get nothing.
    static func of(preset: Preset?, isAvailable: Bool, liveOn: DeckID?) -> SlotCellState {
        guard preset != nil else { return .idle }
        guard isAvailable else { return .unavailable }
        if let deck = liveOn { return .live(deck) }
        return .idle
    }

    var borderColor: Color? {
        switch self {
        case .live(.one): return .cyan
        case .live(.two): return .orange
        case .idle, .unavailable: return nil
        }
    }

    /// Dimming, not desaturation — see the type's doc comment.
    var imageOpacity: Double {
        switch self {
        case .live:        return 1.0
        case .idle:        return 0.65
        case .unavailable: return 0.35
        }
    }

    var badge: String? {
        switch self {
        case .live(let deck): return deck.displayName
        case .idle:           return nil
        case .unavailable:    return "exclamationmark.triangle.fill"
        }
    }
}
```

- [ ] **Step 4: Run the state tests — expect PASS.**

- [ ] **Step 5: Give `SlotCell` the thumbnail**

Add `liveOn: DeckID?` and `thumbnail: Image?` to `SlotCell`'s stored properties, and replace the
`HStack` body (lines 248-267) with the image + overlaid chrome. Keep `.contentShape(Rectangle())`,
`.buttonStyle(.plain)`, the `.contextMenu`, `.help(helpText)` and `.accessibilityLabel` exactly as
they are. An **unavailable cell keeps showing its last-known thumbnail** rather than going blank:
the operator needs to recognise *which* look is broken in order to go remount the drive.

```swift
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .opacity(state.imageOpacity)
                } else {
                    Rectangle().fill(Color.white.opacity(preset == nil ? 0.03 : 0.08))
                }

                if let badge = state.badge {
                    // A live badge is the deck letter; an unavailable badge is a warning glyph.
                    // They occupy the same corner deliberately — one slot of chrome, one meaning.
                    Group {
                        if case .unavailable = state {
                            Image(systemName: badge).foregroundStyle(.orange)
                        } else {
                            Text(badge).foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .background(state.borderColor ?? .white, in: Capsule())
                        }
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(3)
                }

                VStack {
                    Spacer()
                    Text(preset?.name ?? "empty")
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)   // long AR_Genuary names differ at the END
                        .foregroundStyle(preset == nil ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                        .background(.black.opacity(0.55))
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(state.borderColor ?? .clear, lineWidth: 2))
            .contentShape(Rectangle())
```

with `private var state: SlotCellState { .of(preset: preset, isAvailable: isAvailable, liveOn: liveOn) }`.

The name stays, under the image. The spec replaces name-as-primary-identifier with the still, not
the name entirely — at 56pt a thumbnail alone cannot disambiguate two variants of the same shader.

- [ ] **Step 6: Feed thumbnails and live state from the strip**

In `SlotBankStripView.content`, the `ForEach` at lines 146-158 gains the two new arguments. The
thumbnail comes from a `@State private var thumbnails: [Int: Image]` populated in a `.task` that
asks the service at `.batch` priority for every filled slot — **batch, not interactive**, because
cancelling these leaves permanently blank cells (spec, "Two consumers, two concurrency policies").

`liveOn` compares each slot's `shaderURL` to what each deck is actually playing:

```swift
    /// Which deck, if any, is playing this slot's shader right now. Compares `sourceURL`, which is
    /// stamped only on a SUCCESSFUL compile — so a slot whose recall failed to compile does not
    /// light up as live while the previous shader is still on screen.
    private func liveDeck(for preset: Preset?) -> DeckID? {
        guard let preset else { return nil }
        return DeckID.allCases.first {
            instrument.deck($0).unit.sourceURL == preset.shaderURL
        }
    }
```

- [ ] **Step 7: Grow the cell metrics**

`SurfaceMetrics.minCellWidth` is `56` (`InstrumentSurface.swift:108`). A 16:9 thumbnail at 56pt is
31pt tall — unreadable. Raise it to `96`, and re-check the row height constant the resize drag uses
(`SurfaceMetrics.slotStripRowHeight`) so a row still snaps cleanly. **Then re-run the existing
geometry gates**: `testTheMonitorStripIsUnmovedByTheSlotStripBelowIt` and both phase 3a monitor
gates must still pass — the strip is content-sized, and a taller strip must still not move the
monitors.

- [ ] **Step 8: Mutation-prove the state gate**

Change `SlotCellState.of` so `isAvailable` is checked AFTER `liveOn` (i.e. live wins over
unavailable). Expected: `testUnavailableOutranksLive` FAILS. Revert.

- [ ] **Step 9: Full suite, re-record PNG baselines, commit**

The three surface baselines change — the strip now draws images. Re-record via the `RECORD`
sentinel, and **confirm the pairwise-distinctness assertion in `testSurfaceBaselines` still passes
before accepting them**: three baselines that became identical would mean the strip renders nothing.

```bash
git add App/ARShader/SlotBankStripView.swift App/ARShader/InstrumentSurface.swift \
        App/ARShaderTests/SlotCellStateTests.swift App/ARShaderTests/Baselines
git commit -m "feat(3c): slot cells draw thumbnails, with border and badge carrying state"
```

---

