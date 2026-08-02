import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
import SwiftUI

/// Carries `SlotBankStripView.cellWidth` — the COMPUTED clamp result — up through the view tree.
/// Task 4C makes cell width a range (`SurfaceMetrics.minCellWidth`...`maxCellWidth`) rather than
/// one fixed value, so a test — or any future reader — needs a way to observe what the clamp
/// arithmetic produced.
///
/// **This is the injection point, not the render.** It reports `cellWidth` itself, not what
/// `SlotCell`'s `.frame(width:height:)` call site actually applies that value to (see
/// `RenderedCellWidthKey`, immediately below, for that). A mutation that severs the frame from
/// `cellWidth` — e.g. hardcoding `.frame(width: 96, height: 54)` while leaving `cellWidth` intact —
/// changes nothing this key reports; `RenderedCellWidthKey` is what catches exactly that mutation
/// (task 4's shipped defect: an exact frame pinned regardless of the computed clamp).
///
/// Not `private`: `SurfaceGeometryTests` taps this preference externally, wrapping the real
/// `SlotBankStripView` inside a real `InstrumentSurface` at real window widths, WITHOUT reaching
/// into `SlotCell` (which stays `private`) or `SlotBankStripView`'s own `@State` — a `.preference`
/// reported from inside a view keeps bubbling up through every ancestor's `.onPreferenceChange`,
/// including the test's own, which is what makes external observation possible at all.
struct DrawnCellWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Carries the ACTUAL rendered width of one `SlotCell` (row 0, column 0 — every cell in a row shares
/// the same `cellWidth`, so one is enough) — the real geometry SwiftUI laid it out at, not a
/// computed property that feeds it. Reported at `SlotBankStripView.body`'s OUTER level, republishing
/// `renderedCellWidth`, a `@State` var written from `.onAppear`/`.onChange` on the cell's own
/// `.background(GeometryReader)`. NOT a `.preference` bubbling directly from the cell — see
/// `renderedCellWidth`'s doc comment for why that reported 0 at every window width when tried.
///
/// This is what `DrawnCellWidthKey` is NOT: a mutation that disconnects the `.frame` call from
/// `cellWidth` (restoring an unconditional `.frame(width: 96, height: 54)`, for instance) leaves
/// `DrawnCellWidthKey` correctly reporting whatever `cellWidth` still computes, while THIS key
/// reports the frozen 96 that actually got drawn — the two keys disagreeing is itself the signal
/// that the render has come loose from the computation.
struct RenderedCellWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Carries the row pitch `SlotBankStripView` itself hands to the resize drag. Reported separately
/// from `DrawnCellWidthKey` rather than re-derived by a reader from the cell width alone, so a test
/// observing both catches the row height being frozen back to a constant even though the cell width
/// preference keeps moving — see `DrawnCellWidthKey`'s doc comment for why external observation
/// works without touching `SlotCell`.
struct DrawnRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The content column's width, handed DOWN from `InstrumentSurface` via `@Environment` rather than
/// measured by `SlotBankStripView` itself. `SlotBankStripView` tried self-measuring first — a
/// `PreferenceKey`-based `.background(GeometryReader)` reporting upward, tried at `body`'s own outer
/// `VStack` and at `content`'s inner `HStack` — and both reported 0 at every window width tested.
/// **Corrected, fix round 1 (F2) — stated here as what was OBSERVED in this reproduction, not as a
/// general claim about `PreferenceKey` and `ScrollView`:** an earlier draft of this comment claimed
/// any `ScrollView` in the tree breaks any `PreferenceKey`, which is false —
/// `DrawnCellWidthKey`/`DrawnRowHeightKey`, reported from this SAME `body` level, resolve correctly.
/// A proposed alternative (needs a longer settle loop) was also tested directly against this exact
/// measurement, at the loop's normal cap and again with it raised to 60 passes: both still measured
/// 0. See `InstrumentSurface.body`'s own doc comment (at the identical `.onAppear`/`.onChange`
/// measurement, one level up) for the full account of what was actually observed, and for the
/// caveat that this is evidence from a specific reproduction, not a settled rule about SwiftUI.
/// `@Environment` is the opposite direction (parent hands a value DOWN) and needs no
/// `GeometryReader`/`PreferenceKey` round trip at all — `InstrumentSurface` already knows this width
/// because it is the one proposing it, which is reason enough to prefer it here regardless.
private struct SlotBankContentColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// See `SlotBankContentColumnWidthKey`'s doc comment. Zero means "not yet measured," the same
    /// "unknown" convention `InstrumentSurface.surfaceWidth` and `.panelLeadingEdge` already use.
    var slotBankContentColumnWidth: CGFloat {
        get { self[SlotBankContentColumnWidthKey.self] }
        set { self[SlotBankContentColumnWidthKey.self] = newValue }
    }
}

/// The slot bank: a RECALL TO destination picker, and one row of eight cells — always visible
/// directly under the monitors, never a panel to open mid-set.
///
/// Moved here from the rail (task 6R) because recall fires at `recallTarget`, and a rail panel put
/// that picker off-screen exactly when the Bank panel itself was open — an operator could fire a
/// slot at an invisible destination, where one wrong value silently appends unbounded FX stages. An
/// always-visible strip keeps the destination always visible too.
///
/// **SOURCE removed (task 4).** A slot holds a shader, and shaders go on decks — "they will always
/// be shaders not fx" — so RECALL TO is typed as `DeckID` rather than `LibraryTarget`: there is no
/// value of this picker that can append an FX stage, which is what made phase 3b's stale-RECALL-TO
/// hazard reachable in the first place. That constraint also removes the deck a capture would read
/// FROM, so there is deliberately no way to capture a look between this task and task 6, which
/// restores capture via a deck-monitor drag rather than reinstating a picker (see the `ForEach`'s
/// own `.dropDestination`, the only place `SlotBank.capture` is called from this view).
///
/// Rows, collapse, and the resize drag (task 7R). The model (`SlotBank`) always holds forty slots
/// and has no concept of rows at all — `layout.bankRows` decides how many are DRAWN, never how
/// many exist, which is what makes "shrinking rows can never destroy a captured look" structural
/// rather than a promise. See `SlotBank.slotCount`'s doc comment.
struct SlotBankStripView: View {
    let instrument: Instrument
    @ObservedObject private var bank: SlotBank
    @ObservedObject var layout: SurfaceLayout

    /// See `SlotBankContentColumnWidthKey`'s doc comment for why this is handed down rather than
    /// self-measured.
    @Environment(\.slotBankContentColumnWidth) private var contentColumnWidth: CGFloat

    /// The ACTUAL rendered width of a `SlotCell`, written from `.onAppear`/`.onChange` on a cell's
    /// own `.background(GeometryReader)`, then republished at `body`'s OUTER level via
    /// `RenderedCellWidthKey` (see that key's doc comment). Same reason as `contentColumnWidth`:
    /// `.preference` reported from WITHIN the cells `ScrollView`'s own content did not propagate to
    /// an external listener in this harness (fix round 1, F1 investigation) — confirmed directly,
    /// not assumed, by trying it first and observing 0 at every window width, including with the
    /// reduce-order confound (below) already fixed. `.onAppear`/`.onChange` write directly, without
    /// bubbling through `reduce`, and reported correctly in the same position.
    @State private var renderedCellWidth: CGFloat = 0

    /// Where a recall WRITES. Two answers, because a slot holds a shader and shaders go on decks —
    /// "they will always be shaders not fx". Typed as `DeckID` rather than `LibraryTarget` so the
    /// phase 3b hazard is unreachable: there is no value of this picker that appends an FX stage.
    @State private var recallTarget: DeckID = .one

    static var recallTargets: [DeckID] { DeckID.allCases }

    /// A placeholder URL for `wouldHighlight`'s probe drag — see that method's doc comment. Never
    /// read; `ShaderDrag.accepts` never inspects `url` when deciding acceptance.
    private static let highlightProbeURL = URL(fileURLWithPath: "/")

    /// Whether `drag` would be accepted onto slot `index` right now. The ONE call both the drop's
    /// `.dropDestination` `action` (with the REAL drag) and its `isTargeted` highlight (via
    /// `wouldHighlight(at:)`, with a placeholder — see that method) route through, so `on: .slot`
    /// and `isSlotFilled:` are decided in exactly one place rather than the drop and the highlight
    /// silently agreeing by construction.
    ///
    /// **Fix-round-1, F1.** Before this, the `isTargeted` closure re-derived `!isSlotFilled ||
    /// option` inline instead of asking `ShaderDrag.accepts`, so mutating `on: .slot` →
    /// `on: .deck(.one)`, or `isSlotFilled: bank.slots[index] != nil` → `isSlotFilled: false`, at
    /// the action closure's OWN call to `accepts` left all 292 tests green: nothing exercised that
    /// exact call site, and the inline duplicate could not disagree with a mutation it never saw.
    /// Not `private`: `SlotBankStripViewDropSeamTests` calls this directly, the same "testable
    /// seam on the view struct itself" pattern `recallTargets` and `InstrumentView.liveResolution`
    /// already use — no rendering, no view-drop simulation, just a pure call.
    func wouldAccept(_ drag: ShaderDrag, at index: Int) -> Bool {
        ShaderDrag.accepts(drag, on: .slot, isSlotFilled: bank.slots[index] != nil,
                           withOption: NSEvent.modifierFlags.contains(.option))
    }

    /// The `isTargeted` highlight's version of the same question, asked before SwiftUI has
    /// resolved which item is actually hovering — `isTargeted` receives only a `Bool`, never the
    /// dragged value (see `FXChainView`'s and `MonitorTile`'s doc comments on this same platform
    /// limitation, fix-round-1 F2). Routes through `wouldAccept` with a placeholder `.library`
    /// source rather than re-deriving the predicate: for a `.slot` destination,
    /// `ShaderDrag.accepts` returns the IDENTICAL `!isSlotFilled || option` result for every legal
    /// source (`.library`, `.deck` — see `accepts(source:on:isSlotFilled:withOption:)`'s own
    /// switch), so which placeholder source is used here never changes the answer, and this stays
    /// a genuine call into the shared rule rather than a second implementation of it.
    func wouldHighlight(at index: Int) -> Bool {
        wouldAccept(ShaderDrag(source: .library, url: Self.highlightProbeURL, snapshot: nil),
                   at: index)
    }

    /// The slot a compatible AND acceptable drag is currently hovering — set only when
    /// `wouldHighlight(at:)` says yes for THIS slot's fill state and the live ⌥ state, not merely
    /// when a drag of the right TYPE is hovering (task 5 brief, "must NOT fire for a target that
    /// would reject").
    @State private var targetedSlot: Int?

    /// A slot a drop just refused, driving a brief shake (see `SlotCell`'s `isRejected`). Cleared
    /// after ~0.4s so the cue reads as "that didn't take" rather than a lingering error state.
    @State private var rejectedSlot: Int?

    /// Tracks the row count as it stood when the current drag began, so the drag reads as an
    /// absolute offset from a fixed start rather than accumulating per-frame deltas — the same
    /// reasoning `InstrumentSurface.panelResizeHandle` uses for `setPanelWidth`, adapted from an
    /// X position to a row count.
    @State private var dragStartRows: Int?

    /// Balanced push/pop tracking for the row-resize cursor, mirroring
    /// `InstrumentSurface.isResizeCursorPushed`: a bare hover-in/hover-out pair assumes hover-out
    /// always fires, but SwiftUI can tear the handle down mid-hover (e.g. the strip collapses)
    /// without ever calling `onHover(false)`, which would leave the resize cursor stuck.
    @State private var isRowResizeCursorPushed = false

    /// Decoded once, here, when a request resolves — never in a cell's `body`, which re-evaluates
    /// on every layout pass while the instrument is playing.
    ///
    /// **Keyed by the shader's URL, not the slot index (fix-round-1, C1).** An index is not a
    /// stable identity: `SlotBank.clear` nils a slot and `SlotBank.capture` overwrites it, so an
    /// index-keyed cache let a cleared or re-captured slot go on drawing the PREVIOUS shader's
    /// still under the new preset's name — the operator fires the picture they see and gets
    /// something else. Keying by URL means a cleared slot (preset nil) simply has no entry to look
    /// up, and a freshly captured slot's new URL starts with none either, until its own request
    /// resolves. It ALSO preserves the property the old doc comment was defending: an unavailable
    /// preset keeps its URL, and this dictionary is never cleared once an entry is set, so the
    /// "last-known thumbnail" of a slot whose file just went missing still resolves correctly — the
    /// disk cache itself cannot serve one for an unreadable file (its key needs the file's own
    /// mtime), so this in-memory copy is the only surviving one.
    @State private var thumbnails: [URL: Image] = [:]

    /// The resize drag's snap-to-whole-rows arithmetic divides by this. Derived from `cellWidth` —
    /// the SAME clamped value every cell is actually drawn at (see `cellWidth`'s doc comment) — not
    /// a constant. A constant desyncs the drag from what it is dragging once cell width is a range
    /// instead of one fixed value (task 4C); task 4 already found the drag reading 60 against a
    /// real ~122pt pitch from exactly this kind of drift.
    private var slotStripRowHeight: CGFloat {
        cellWidth * 9.0 / 16.0 + SurfaceMetrics.slotStripCellSpacing
    }

    init(instrument: Instrument, layout: SurfaceLayout) {
        self.instrument = instrument
        self.bank = instrument.slotBank
        self.layout = layout
    }

    /// Filled slots the strip is not drawing. Never lost: growing the rows back reveals them
    /// unchanged, because a resize never touches `SlotBank`.
    ///
    /// Derived from `drawnBankRows`, not `bankRows`: collapsed draws no rows at all, so a count
    /// taken from the row SETTING reported a collapsed strip as hiding nothing — every captured
    /// look off screen with no marker saying it still exists.
    private var hiddenFilledCount: Int {
        bank.hiddenFilledCount(drawnRows: layout.drawnBankRows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed shows the header row only — the resize handle has nothing to resize while
            // there is nothing drawn beneath it.
            if !layout.isBankCollapsed {
                rowResizeHandle
            }
            header
            if !layout.isBankCollapsed {
                content
            }
        }
        // Reports the SAME `cellWidth` every cell is actually drawn at, and the row pitch computed
        // from it (`slotStripRowHeight`), as two independent preferences — not one derived from the
        // other by whatever reads them — so a mutation that freezes `slotStripRowHeight` back to a
        // constant shows up as a mismatch against `DrawnCellWidthKey`, which keeps moving with the
        // window. See `DrawnCellWidthKey`'s and `DrawnRowHeightKey`'s doc comments.
        .preference(key: DrawnCellWidthKey.self, value: cellWidth)
        .preference(key: DrawnRowHeightKey.self, value: slotStripRowHeight)
        // Republishes `renderedCellWidth` (written by `.onAppear`/`.onChange` from WITHIN the cells
        // `ScrollView`) from OUT HERE, at the same outer level `DrawnCellWidthKey`/`DrawnRowHeightKey`
        // already report from successfully — see `renderedCellWidth`'s doc comment for why the
        // report has to happen here rather than as a `.preference` bubbling directly from the cell.
        .preference(key: RenderedCellWidthKey.self, value: renderedCellWidth)
        // Keyed on `bank.slots`, not fired once: fix-round-1 (F2). `bank.slots` is `@Published`
        // and `Preset` is `Equatable`, so SwiftUI restarts this task — cancelling whatever sweep
        // was still in flight — every time a capture or clear changes the array, not just at
        // launch. That is safe, not wasteful: `loadThumbnails` only ever requests entries it does
        // not already hold (keyed by URL now, see `thumbnails`' doc comment), so a restart re-asks
        // for exactly the slots the OLD sweep had not yet resolved (including one a cancellation
        // itself just un-resolved — `ThumbnailService` never persists a cancelled request, so it is
        // simply retried) plus whatever the bank change just added. On the outer VStack, not
        // `content`: `content` is torn down and rebuilt every time the strip collapses, and this
        // must not restart on a mere collapse/expand.
        .task(id: bank.slots) { await loadThumbnails() }
    }

    /// Fills `thumbnails` from the disk-cached thumbnail service, one request per filled slot whose
    /// URL is not already resolved — every slot in the model, not just the currently drawn rows, so
    /// expanding a collapsed row reveals thumbnails already in hand rather than triggering a fresh
    /// sweep. Re-entrant by construction (see the `.task(id:)` call site's doc comment): a capture
    /// or clear mid-sweep restarts this from a fresh loop over the CURRENT `bank.slots`, so a look
    /// captured mid-set gets picked up rather than waiting for relaunch (fix-round-1, F2).
    ///
    /// `.batch`, never `.interactive`: cancelling these leaves permanently blank cells that only a
    /// resize or relaunch would fill (spec, "Two consumers, two concurrency policies") — the
    /// opposite of library hover, where a superseded request is wasted work worth dropping.
    ///
    /// **The `Task.isCancelled` guard is what makes the `.task(id:)` doc comment above TRUE**
    /// (final-review F2). Without it, "SwiftUI restarts this task — cancelling whatever sweep was
    /// still in flight" was false: `await`ing an actor method is not a cancellation point, and
    /// `ThumbnailService.thumbnail` neither throws nor checks the CALLER's cancellation, so a
    /// cancelled sweep ran to completion and issued every remaining request anyway. Three captures
    /// in quick succession therefore left four concurrent sweeps issuing up to 4N `.batch`
    /// renders, all serialized on one actor, with any library-hover request queued behind the lot.
    /// Not `private`: `SlotBankStripViewDropSeamTests` drives this directly, the same "testable
    /// seam on the view struct itself, no rendering" pattern `wouldAccept` and `recallTargets`
    /// already use.
    func loadThumbnails() async {
        for preset in bank.slots {
            guard !Task.isCancelled else { return }
            guard let preset, thumbnails[preset.shaderURL] == nil else { continue }
            let result = await instrument.thumbnailService.thumbnail(
                for: preset.shaderURL, priority: .batch)
            guard case .image(let data) = result, let decoded = NSImage(data: data) else { continue }
            thumbnails[preset.shaderURL] = Image(nsImage: decoded)
        }
    }

    /// Which deck, if any, is playing this slot's shader right now. Compares `sourceURL`, which is
    /// stamped only on a SUCCESSFUL compile — so a slot whose recall failed to compile does not
    /// light up as live while the previous shader is still on screen.
    private func liveDeck(for preset: Preset?) -> DeckID? {
        guard let preset else { return nil }
        return DeckID.allCases.first {
            instrument.deck($0).unit.sourceURL == preset.shaderURL
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { layout.toggleBankCollapsed() }) {
                Image(systemName: layout.isBankCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("slotBank.disclosure")
            .accessibilityLabel(layout.isBankCollapsed ? "Expand slot bank" : "Collapse slot bank")
            .help(layout.isBankCollapsed ? "Expand the slot bank" : "Collapse the slot bank")

            Text("SLOT BANK")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            if hiddenFilledCount > 0 {
                Text("\(hiddenFilledCount) hidden")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("slotBank.hiddenCount")
                    .help("\(hiddenFilledCount) captured slot(s) sit in rows the strip is not "
                          + "currently showing. Nothing is lost — expand the strip to see them.")
            }

            Spacer()
        }
        .padding(.horizontal, SurfaceMetrics.slotStripPadding)
        .padding(.vertical, 4)
    }

    private var content: some View {
        HStack(spacing: SurfaceMetrics.slotStripGapWidth) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECALL TO")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Picker("Load onto", selection: $recallTarget) {
                    ForEach(Self.recallTargets) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Load onto — which deck a recall writes to")
            }
            .frame(width: SurfaceMetrics.slotStripRecallWidth)

            Divider()

            // Horizontal scroll, not a fixed shrink: below `SurfaceMetrics.minCellWidth` per
            // cell, cells no longer compress further — they scroll instead. A narrower window
            // (or a panel open at the floor) degrades into visible scrolling rather than
            // invisible hit-area overlap between neighbouring cells, which is what let an edge
            // click fire the WRONG slot before this fix (fix-round-1, task 6R). Sized by the
            // outer `.fixedSize(vertical: true)` `InstrumentSurface` already applies to the
            // whole `slots()` slot — confirmed empirically to bound this ScrollView to its
            // content's ideal height rather than the greedy full-window height it reports when
            // unconstrained.
            //
            // **Task 4C reopens width into a clamped RANGE** (`SurfaceMetrics.minCellWidth`...
            // `maxCellWidth`) instead of task 4's single exact size — a floor with no ceiling (task
            // 3) and an exact size with neither (task 4) were both wrong; this is the third value
            // `.frame(minWidth:maxWidth:)` needs to actually be `clamp()`.
            //
            // The clamp is computed in Swift (`cellWidth`, below) rather than left to a bare
            // `.frame(minWidth: .minCellWidth, maxWidth: .maxCellWidth)` on each cell: a horizontal
            // `ScrollView` proposes its CONTENT an effectively unconstrained width along the scroll
            // axis — that is the mechanism that lets content overflow into scrolling at all — so a
            // native min/max frame applied INSIDE the ScrollView's content never sees the window; it
            // always resolves toward its own maximum, regardless of actual window width.
            //
            // **The width this clamp needs comes from `@Environment(\.slotBankContentColumnWidth)`,
            // not from self-measurement.** Self-measuring this strip — a `.background(GeometryReader)`
            // reporting a `PreferenceKey` upward, in several placements (a `Color.clear` sibling of
            // the `ScrollView` inside this `HStack`; this `HStack`'s own resolved width; even
            // `body`'s outer `VStack`, nowhere near the `ScrollView`) — measured 0 at every window
            // width tested, including 2560pt, in every placement tried, even though a diagnostic
            // print confirmed the `GeometryReader` closures and the `onPreferenceChange` callback DID
            // fire. Whatever the exact cause, self-measurement proved unreliable in this specific
            // tree shape (a `ScrollView` present anywhere in the strip). `InstrumentSurface` already
            // knows the content column's width — it is the one proposing it — so it hands that value
            // DOWN via `@Environment` instead, which needs no `GeometryReader`/`PreferenceKey` round
            // trip. `cellWidth` then subtracts the KNOWN fixed chrome
            // (`SurfaceMetrics.slotStripLeadingChromeWidth`) from that to recover the region the
            // cells actually have to share.
            ScrollView(.horizontal, showsIndicators: true) {
                // One VStack of rows inside a SINGLE horizontal ScrollView, not one ScrollView per
                // row — separate scroll views could drift out of sync and a wide bank would show
                // row 1 and row 2 scrolled to different columns.
                VStack(alignment: .leading, spacing: SurfaceMetrics.slotStripCellSpacing) {
                    ForEach(0..<layout.bankRows, id: \.self) { row in
                        HStack(spacing: SurfaceMetrics.slotStripCellSpacing) {
                            ForEach(0..<SlotBank.perRow, id: \.self) { column in
                                let index = row * SlotBank.perRow + column
                                let preset = bank.slots[index]
                                // Looked up by the PRESET's own URL, not the index (C1) — see
                                // `thumbnails`' doc comment for why an index-keyed lookup drew a
                                // cleared or re-captured slot's PREVIOUS shader.
                                SlotCell(index: index,
                                         preset: preset,
                                         isAvailable: bank.isAvailable(index),
                                         liveOn: liveDeck(for: preset),
                                         thumbnail: preset.flatMap { thumbnails[$0.shaderURL] },
                                         isTargeted: targetedSlot == index,
                                         isRejected: rejectedSlot == index,
                                         onRecall: { recall(index) },
                                         onClear: { bank.clear(index) },
                                         // Handed to EVERY cell, not only the one that lost a
                                         // look: after a clear that cell is empty and reads as
                                         // "nothing here", so restricting the way back to it alone
                                         // would hide the undo on the least likely cell to be
                                         // right-clicked next. The title names the slot, so no
                                         // cell can imply it is the one being restored.
                                         undoTitle: bank.undoable?.menuTitle,
                                         onUndo: { bank.undo() })
                                    .frame(width: cellWidth, height: cellWidth * 9.0 / 16.0)
                                    // The never-overwrite invariant restated for a gesture — the
                                    // single most important mutation proof in the phase: a mid-set
                                    // drag must never silently replace a dialled-in look. Both this
                                    // action and the `isTargeted` highlight below route through
                                    // `wouldAccept`/`wouldHighlight` — ONE decision, not two
                                    // independent ones that could silently drift apart
                                    // (fix-round-1, F1).
                                    .dropDestination(for: ShaderDrag.self) { items, _ in
                                        guard let drag = items.first, wouldAccept(drag, at: index)
                                        else {
                                            rejectedSlot = index      // drives the shake
                                            Task {
                                                try? await Task.sleep(for: .milliseconds(400))
                                                if rejectedSlot == index { rejectedSlot = nil }
                                            }
                                            return false
                                        }
                                        bank.capture(Preset.capturing(url: drag.url,
                                                                      snapshot: drag.snapshot
                                                                        ?? ParamSnapshot(params: [:])),
                                                     into: index)
                                        return true
                                    } isTargeted: { hovering in
                                        guard hovering else {
                                            if targetedSlot == index { targetedSlot = nil }
                                            return
                                        }
                                        targetedSlot = wouldHighlight(at: index) ? index : nil
                                    }
                                    // The ONE gate that observes the RENDERED frame rather than the
                                    // computed property feeding it — writes `renderedCellWidth`,
                                    // republished at `body`'s outer level as `RenderedCellWidthKey`
                                    // (see both doc comments).
                                    //
                                    // `.onAppear`/`.onChange`, not `.preference`, from THIS cell:
                                    // tried `.preference` first (reported from row 0/column 0 only,
                                    // then — after finding `reduce`'s "last-write-wins" let the
                                    // other seven cells' un-set `defaultValue` silently overwrite the
                                    // one real report — from every cell). Neither reported anything
                                    // but 0, at every window width: a `.preference` bubbling from
                                    // WITHIN this `ScrollView`'s own content does not reach an
                                    // external listener in this harness, the same limit
                                    // `contentColumnWidth` hit measuring from OUTSIDE it. `.onAppear`/
                                    // `.onChange` write directly, without bubbling, and reported
                                    // correctly. Row 0, column 0 only: every cell in a row shares
                                    // `cellWidth`, so a second write would just be redundant.
                                    .background {
                                        if row == 0 && column == 0 {
                                            GeometryReader { proxy in
                                                Color.clear
                                                    .onAppear { renderedCellWidth = proxy.size.width }
                                                    .onChange(of: proxy.size.width) { newValue in
                                                        renderedCellWidth = newValue
                                                    }
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SurfaceMetrics.slotStripPadding)
    }

    /// The single clamped cell width every cell in the strip draws at, and the one `DrawnCellWidthKey`
    /// reports. `SlotBank.perRow` cells share whatever's left of `contentColumnWidth` (handed down
    /// via `@Environment` — see `SlotBankContentColumnWidthKey`'s doc comment) after the known fixed
    /// chrome (`SurfaceMetrics.slotStripLeadingChromeWidth` — padding, RECALL TO, gaps, the divider)
    /// and the gaps between cells; that even split is then bounded to
    /// `SurfaceMetrics.minCellWidth`...`maxCellWidth` — `clamp()`, spelled out by hand for the
    /// reason in `content`'s doc comment. `contentColumnWidth` is 0 until `InstrumentSurface`'s own
    /// first layout pass lands; treated as "unknown" here, same as everywhere else in this file, so
    /// the first frame draws at the floor rather than at a zero-derived one.
    private var cellWidth: CGFloat {
        let cellsRegionWidth = contentColumnWidth - SurfaceMetrics.slotStripLeadingChromeWidth
        guard cellsRegionWidth > 0 else { return SurfaceMetrics.minCellWidth }
        let count = CGFloat(SlotBank.perRow)
        let idealCellWidth = (cellsRegionWidth - SurfaceMetrics.slotStripCellSpacing * (count - 1))
            / count
        return min(max(idealCellWidth, SurfaceMetrics.minCellWidth), SurfaceMetrics.maxCellWidth)
    }

    /// A drag on the strip's top edge that snaps to whole rows — reads like the panel divider the
    /// operator already has (`InstrumentSurface.panelResizeHandle`), no stepper and no dialog to
    /// hit mid-set. Purely a view-local concern: `bankRows` is drawn-row count only, so growing or
    /// shrinking it here never reaches `SlotBank`.
    private var rowResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: SurfaceMetrics.resizeHandleWidth)
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .accessibilityIdentifier("slotBank.rowResizeHandle")
            .onHover { inside in
                // Balanced and idempotent — see `isRowResizeCursorPushed`'s doc comment.
                if inside {
                    guard !isRowResizeCursorPushed else { return }
                    NSCursor.resizeUpDown.push()
                    isRowResizeCursorPushed = true
                } else {
                    guard isRowResizeCursorPushed else { return }
                    NSCursor.pop()
                    isRowResizeCursorPushed = false
                }
            }
            .onDisappear {
                // Backstop for the case `onHover(false)` never fires: the strip collapses while
                // the pointer is still over the handle, and SwiftUI tears the view down without a
                // final hover-out.
                guard isRowResizeCursorPushed else { return }
                NSCursor.pop()
                isRowResizeCursorPushed = false
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStartRows == nil { dragStartRows = layout.bankRows }
                        // Dragging the top edge UP (negative translation.height) grows the strip
                        // downward by one row per `slotStripRowHeight` of travel — the same
                        // "handle stands in for the boundary it moves" feel as the panel divider.
                        let deltaRows = Int(
                            (-value.translation.height / slotStripRowHeight)
                                .rounded())
                        layout.setBankRows((dragStartRows ?? layout.bankRows) + deltaRows)
                    }
                    .onEnded { _ in dragStartRows = nil }
            )
    }

    private func recall(_ index: Int) {
        guard let preset = bank.recall(index) else { return }
        instrument.load(preset.shaderURL, onto: .deck(recallTarget), thenApply: preset.snapshot)
    }
}

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

    /// Fix-round-1 (F4): `.unavailable` now carries its own border, same as a live slot — the
    /// state whose whole job is "the operator must never fire this and get nothing" cannot be the
    /// one state with no border. Red rather than reusing deck B's orange: the original brief's
    /// snippet assigned orange to BOTH `.live(.two)` and the unavailable glyph, so a warm-toned
    /// still at 0.35 opacity with an orange glyph could misread as "playing on deck B" instead of
    /// "broken." Red does not collide with either deck's live colour (cyan, orange).
    var borderColor: Color? {
        switch self {
        case .live(.one):  return .cyan
        case .live(.two):  return .orange
        case .unavailable: return .red
        case .idle:        return nil
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

/// One cell. Empty cells invite capture; filled ones recall on a plain click and hide Replace and
/// Clear behind a context menu — unconditionally available, not just under a mouse that happens to
/// have entered from the right direction.
private struct SlotCell: View {
    let index: Int
    let preset: Preset?
    let isAvailable: Bool
    let liveOn: DeckID?
    let thumbnail: Image?
    /// A compatible AND acceptable drag is hovering this cell right now — see `targetedSlot`'s
    /// doc comment for why this is already acceptance-filtered before it reaches here.
    let isTargeted: Bool
    /// A drop just landed here and was refused — drives the shake below.
    let isRejected: Bool
    let onRecall: () -> Void
    let onClear: () -> Void
    /// The title of the one restorable change, or nil when there is nothing to put back — see
    /// `SlotBank.undoable`. Nil means the menu item is ABSENT, not disabled: a permanently greyed
    /// "Undo clear" would be one more thing to read mid-set.
    let undoTitle: String?
    let onUndo: () -> Void

    private var state: SlotCellState { .of(preset: preset, isAvailable: isAvailable, liveOn: liveOn) }

    var body: some View {
        // The single tap-delivery path for this cell. A real `Button` (not a bare
        // `.onTapGesture`) so VoiceOver gets a native button trait and an activate action for
        // free, matching `LibraryPanelView`'s row pattern. The accessibility label sits on the
        // Button itself, which SwiftUI already treats as one combined element — no child text or
        // control announces separately.
        Button(action: activate) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .opacity(state.imageOpacity)
                } else {
                    // Fix-round-1 (F2): 0.03 vs the old 0.08 read as near-identical on a dark
                    // surface, so a filled-but-not-yet-loaded cell (the ordinary state for the
                    // first several seconds of a set, or right after a fresh capture) looked
                    // exactly like an empty one. 0.22 makes "something is here, still loading" a
                    // visibly distinct plate from "nothing captured."
                    Rectangle().fill(Color.white.opacity(preset == nil ? 0.03 : 0.22))
                }

                if let badge = state.badge {
                    // A live badge is the deck letter; an unavailable badge is a warning glyph.
                    // They occupy the same corner deliberately — one slot of chrome, one meaning.
                    //
                    // Fix-round-1 (F4): the unavailable glyph used to draw with no background plate
                    // at all, while the live badge got a solid capsule — "unavailable outranks
                    // live" exists precisely so the operator never fires a dead slot, so it cannot
                    // be the WORSE-lit of the two badges. Both now sit on an opaque plate in
                    // `state.borderColor` (red for unavailable, never orange — see `borderColor`'s
                    // doc comment), same contrast treatment, same corner.
                    Group {
                        if case .unavailable = state {
                            Image(systemName: badge)
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(state.borderColor ?? .red, in: Circle())
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
            // Highlight ring for a drag hovering this cell that WOULD be accepted (see
            // `targetedSlot`'s doc comment) — drawn as a second overlay so it never competes with
            // `state.borderColor` for the same stroke.
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Left enabled even when unavailable: deliberately clearing a slot whose file is gone for
        // good is legitimate. Replace no longer lives here (task 5) — dragging a deck or a
        // library shader onto the cell, with ⌥ held, is the one way to replace a filled slot now.
        .contextMenu {
            if preset != nil {
                Button("Clear slot", role: .destructive, action: onClear)
            }
            // The way back from the only permanently-destructive gesture on this strip
            // (final-review F3). Present only while there is something to restore.
            if let undoTitle {
                Button(undoTitle, action: onUndo)
            }
        }
        .help(helpText)
        .accessibilityLabel(preset.map { "Slot \(index + 1), \($0.name)" } ?? "Slot \(index + 1), empty")
        // A brief horizontal shake for a refused drop — "that didn't take", nothing that steals
        // focus (task 5 brief, Step 7). No dialog, no alert: the operator is mid-set.
        .offset(x: isRejected ? 5 : 0)
        .animation(isRejected ? .easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)
                              : .default,
                   value: isRejected)
    }

    /// Click always recalls (fix-round-1, F6). ⌥ no longer changes anything about a click: it
    /// used to route a filled slot's ⌥-click to `onCapture()`, but capture is a drag-only gesture
    /// now (task 5) and that call reached nothing — an operator holding ⌥ mid-set got silence
    /// where they expected a recall. ⌥ keeps its "I mean it" meaning where overwriting is a real
    /// risk: a DROP landing on a filled slot. A click can no longer overwrite anything, so ⌥ has
    /// nothing left to guard there.
    ///
    /// Safe on an empty slot without a guard: `SlotBankStripView.recall(_:)` already no-ops
    /// (`SlotBank.recall` returns nil) when there is nothing to recall.
    private func activate() { onRecall() }

    private var helpText: String {
        guard let preset else {
            return "Drag a shader from the library, or a deck monitor, onto slot \(index + 1) "
                + "to capture it"
        }
        if !isAvailable { return "\(preset.name) — file not found" }
        return "\(preset.name) — click to recall, ⌥-drag a shader or deck here to replace, "
            + "right-click to clear"
    }
}
