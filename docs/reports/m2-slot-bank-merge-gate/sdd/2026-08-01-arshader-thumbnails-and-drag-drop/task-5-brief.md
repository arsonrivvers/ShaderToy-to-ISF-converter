### Task 5: Drag and drop — library → slot / deck / deck FX / master FX

**Files:**
- Create: `App/ARShader/ShaderDrag.swift` — the payload type and drop-acceptance rules
- Modify: `App/ARShader/LibraryPanelView.swift` — rows become draggable; the five-way picker and click-to-load are REMOVED
- Modify: `App/ARShader/SlotBankStripView.swift` — cells become drop targets
- Modify: `App/ARShader/MonitorView.swift` — deck tiles become drop targets
- Modify: `App/ARShader/FXChainView.swift` — FX sections become drop targets
- Modify: `App/ARShader/InstrumentView.swift` — the `libraryTarget` state is now dead; remove it
- Test: `App/ARShaderTests/ShaderDragTests.swift` (new)

**Interfaces:**
- Consumes: `Instrument.load(_:onto:thenApply:)`; `SlotBank.capture(_:into:)`; `SlotCellState` from Task 3.
- Produces: `ShaderDrag` (a `Transferable` payload) and `ShaderDrag.accepts(_:on:isSlotFilled:withOption:) -> Bool`, reused verbatim by Task 6.

**There is no drag-and-drop anywhere in this codebase today** — confirmed by exhaustive grep for
`.draggable`, `.dropDestination`, `onDrag`, `onDrop`, `NSItemProvider`, `UTType`, `Transferable`.
This task establishes the pattern; Task 6 extends it. Follow SwiftUI's `Transferable` +
`.dropDestination(for:action:isTargeted:)`, not the older `NSItemProvider` API.

**The acceptance rules are a pure function**, deliberately: the whole never-overwrite invariant is
expressible without a view, and therefore testable without one.

- [ ] **Step 1: Write the failing acceptance tests**

Create `App/ARShaderTests/ShaderDragTests.swift`:

```swift
import XCTest
@testable import ARShader

@MainActor
final class ShaderDragTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/a.fs")
    private var fromLibrary: ShaderDrag { .init(source: .library, url: url, snapshot: nil) }
    private var fromDeck: ShaderDrag {
        .init(source: .deck(.one), url: url, snapshot: ParamSnapshot(params: [:]))
    }

    // MARK: The never-overwrite rule, now under a drag

    func testADropOnAnEmptySlotIsAccepted() {
        XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: false,
                                         withOption: false))
    }

    /// The rule phase 3b was built around, restated for a gesture that is a BIGGER mis-click risk
    /// than a click: the operator is crossing the surface with a payload attached and a slot is a
    /// small target beside seven identical ones.
    func testADropOnAFilledSlotIsRejectedWithoutOption() {
        XCTAssertFalse(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: true,
                                          withOption: false))
        XCTAssertFalse(ShaderDrag.accepts(fromDeck, on: .slot, isSlotFilled: true,
                                         withOption: false))
    }

    /// ⌥ is the ONE "I mean it" gesture on this surface. It already means overwrite for a click;
    /// it means the same for a drop rather than inventing a second modifier.
    func testOptionDragReplacesAFilledSlot() {
        XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: .slot, isSlotFilled: true,
                                         withOption: true))
    }

    // MARK: Which sources may reach which destinations

    func testALibraryShaderMayReachEveryNonSlotDestination() {
        for destination: ShaderDrag.Destination in [.deck(.one), .deck(.two),
                                                    .deckFX(.one), .deckFX(.two), .masterFX] {
            XCTAssertTrue(ShaderDrag.accepts(fromLibrary, on: destination,
                                             isSlotFilled: false, withOption: false),
                          "the library must be able to fill \(destination)")
        }
    }

    /// A deck is a source for CAPTURE and nothing else. Dropping deck A onto deck B is not a
    /// copy-shader gesture — it reads like one and would silently discard the dialled values that
    /// are the entire reason a look is worth capturing.
    func testADeckMayOnlyBeDroppedOnASlot() {
        XCTAssertTrue(ShaderDrag.accepts(fromDeck, on: .slot, isSlotFilled: false,
                                         withOption: false))
        for destination: ShaderDrag.Destination in [.deck(.two), .deckFX(.one), .masterFX] {
            XCTAssertFalse(ShaderDrag.accepts(fromDeck, on: destination,
                                              isSlotFilled: false, withOption: false),
                           "a deck must not be droppable on \(destination)")
        }
    }

    /// Banned this phase. Clicking a slot already loads it onto a deck; a drag would be a second
    /// way to fire a slot mid-set with no new capability, and twice the ways to do it by accident.
    func testASlotIsNotADragSource() {
        let fromSlot = ShaderDrag(source: .slot, url: url, snapshot: nil)
        for destination: ShaderDrag.Destination in [.slot, .deck(.one), .deckFX(.one), .masterFX] {
            XCTAssertFalse(ShaderDrag.accepts(fromSlot, on: destination,
                                              isSlotFilled: false, withOption: false))
        }
    }

    /// A capture carries the dialled values; a library drag cannot, because there are none yet.
    func testOnlyADeckDragCarriesASnapshot() {
        XCTAssertNil(fromLibrary.snapshot)
        XCTAssertNotNil(fromDeck.snapshot)
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure** (`cannot find 'ShaderDrag' in scope`).

- [ ] **Step 3: Create the payload and the rules**

`App/ARShader/ShaderDrag.swift`:

```swift
import CoreTransferable
import UniformTypeIdentifiers

/// What a drag is carrying, and where it is allowed to land.
///
/// No SwiftUI import: the acceptance rules are the never-overwrite invariant restated for a
/// gesture, and that invariant must be testable with no view and no GPU in play — the same
/// doctrine `SurfaceLayout` and `SlotBank` follow.
struct ShaderDrag: Codable, Transferable, Sendable {
    enum Source: Codable, Equatable, Sendable {
        case library
        case deck(DeckID)
        /// Never a legal source this phase. Present so `accepts` can REJECT it explicitly rather
        /// than by omission — a rule you can read is a rule someone can find later.
        case slot
    }

    enum Destination: Equatable, Sendable {
        case slot
        case deck(DeckID)
        case deckFX(DeckID)
        case masterFX
    }

    let source: Source
    let url: URL
    /// The dialled values. Present only on a deck capture — a library shader has none yet.
    let snapshot: ParamSnapshot?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .arshaderDrag)
    }

    /// The single acceptance rule. Every drop target asks this and nothing else, so there is one
    /// place the never-overwrite invariant lives.
    static func accepts(_ drag: ShaderDrag, on destination: Destination,
                        isSlotFilled: Bool, withOption option: Bool) -> Bool {
        switch drag.source {
        case .slot:
            return false
        case .deck:
            guard case .slot = destination else { return false }
            return !isSlotFilled || option
        case .library:
            guard case .slot = destination else { return true }
            return !isSlotFilled || option
        }
    }
}

extension UTType {
    static let arshaderDrag = UTType(exportedAs: "com.arshader.shader-drag")
}
```

The custom `UTType` must also be declared in the app target's `Info.plist` under
`UTExportedTypeDeclarations`, or the drag will silently never register. `App/project.yml` generates
the target — add it there, not to a generated plist.

- [ ] **Step 4: Run the tests — expect PASS.**

- [ ] **Step 5: Make library rows draggable and remove the picker**

In `LibraryPanelView`, delete the `Picker("Load onto", …)` block (lines 66-74) and the
`@Binding var target: LibraryTarget` with it. The row `Button` (77-88) loses its action —
`instrument.load(entry.url, onto: target)` goes — and becomes a plain draggable label:

```swift
            List(entries) { entry in
                Text(entry.name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)   // long AR_Genuary names differ at the END
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .draggable(ShaderDrag(source: .library, url: entry.url, snapshot: nil))
                    .help("Drag onto a deck, an FX chain, or a slot")
            }
```

**This removes click-to-load entirely** — the spec's decision, and the reason the drag targets must
all land in this one task rather than being spread across several. A half-migrated library where
clicking does nothing and only some targets accept drops is unusable.

Then delete `@State private var libraryTarget` from `InstrumentView` and the argument from the
`LibraryPanelView(instrument:target:)` call site. Task 4 already removed the strip's use of it, so
this is the last reference.

- [ ] **Step 6: Add the drop targets**

Each target applies the same shape. Slot cells, in `SlotBankStripView`'s `ForEach`:

```swift
                                    .dropDestination(for: ShaderDrag.self) { items, _ in
                                        guard let drag = items.first,
                                              ShaderDrag.accepts(
                                                drag, on: .slot,
                                                isSlotFilled: bank.slots[index] != nil,
                                                withOption: NSEvent.modifierFlags.contains(.option))
                                        else {
                                            rejected = index      // drives the shake
                                            return false
                                        }
                                        bank.capture(Preset.capturing(url: drag.url,
                                                                      snapshot: drag.snapshot
                                                                        ?? ParamSnapshot(params: [:])),
                                                     into: index)
                                        return true
                                    } isTargeted: { targetedSlot = $0 ? index : nil }
```

Deck monitor tiles use `.deck(id)` and call `instrument.load(drag.url, onto: .deck(id), thenApply: drag.snapshot)`.
FX sections use `.deckFX(id)` / `.masterFX` and call `instrument.load` with the matching
`LibraryTarget` — the existing seam already appends a stage for those cases (`Instrument.swift:96-99`),
so no new append path is created.

- [ ] **Step 7: Both rejection signals**

Returning `false` from `dropDestination` already yields the no-entry cursor — that is the baseline,
not the answer. Add the second: a `@State private var rejected: Int?` that a refused drop sets, with
a brief `.offset` shake keyed on it, cleared after ~0.4s. **No dialog, no alert, nothing that steals
focus.** A rejected drop mid-set must cost zero attention beyond "that didn't take". The
highlight-on-valid-target comes from `isTargeted:` and must NOT fire for a target that would reject.

- [ ] **Step 8: Mutation-prove the invariant**

Change `accepts`'s `.library` branch to `return true` unconditionally. Expected:
`testADropOnAFilledSlotIsRejectedWithoutOption` FAILS. Revert. This is the single most important
mutation proof in the phase — it is the one that stops a mid-set drag destroying a dialled-in look.

- [ ] **Step 9: Full suite, re-record baselines, commit**

The library panel lost a control, so the panel baselines change. Same distinctness check as Task 3.

```bash
git add App/ARShader/ShaderDrag.swift App/ARShader/LibraryPanelView.swift \
        App/ARShader/SlotBankStripView.swift App/ARShader/MonitorView.swift \
        App/ARShader/FXChainView.swift App/ARShader/InstrumentView.swift \
        App/project.yml App/ARShaderTests/ShaderDragTests.swift App/ARShaderTests/Baselines
git commit -m "feat(3c): drag and drop from the library; a drop never overwrites a filled slot"
```

---

