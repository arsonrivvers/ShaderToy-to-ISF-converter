import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
import SwiftUI

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
/// restores capture via a deck-monitor drag rather than reinstating a picker. See `capture(into:)`.
///
/// Rows, collapse, and the resize drag (task 7R). The model (`SlotBank`) always holds forty slots
/// and has no concept of rows at all — `layout.bankRows` decides how many are DRAWN, never how
/// many exist, which is what makes "shrinking rows can never destroy a captured look" structural
/// rather than a promise. See `SlotBank.slotCount`'s doc comment.
struct SlotBankStripView: View {
    let instrument: Instrument
    @ObservedObject private var bank: SlotBank
    @ObservedObject var layout: SurfaceLayout

    /// Where a recall WRITES. Two answers, because a slot holds a shader and shaders go on decks —
    /// "they will always be shaders not fx". Typed as `DeckID` rather than `LibraryTarget` so the
    /// phase 3b hazard is unreachable: there is no value of this picker that appends an FX stage.
    @State private var recallTarget: DeckID = .one

    static var recallTargets: [DeckID] { DeckID.allCases }

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
    private func loadThumbnails() async {
        for preset in bank.slots {
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
            // Cells are pinned with an EXACT `.frame(width:height:)` below (fix-round-2, task 4
            // addition 1), not `.frame(minWidth:, maxWidth: .infinity)`. The min/max form let each
            // cell's width follow whatever the ambient HStack/ScrollView proposal happened to be —
            // in the test harness that resolved to the floor, as documented, but a real window
            // proposed each cell roughly an eighth of the available width, and two rows of
            // stretched cells rivaled the monitor strip above them in height (operator, with
            // screenshot, 2026-08-01). An exact `.frame(width:height:)` reports that size to its
            // parent regardless of what is proposed, so the cell can no longer inherit stray width
            // from whatever container it sits inside — see `SurfaceMetrics.slotCellHeight`.
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
                                         onRecall: { recall(index) },
                                         onCapture: { capture(into: index) },
                                         onClear: { bank.clear(index) })
                                    .frame(width: SurfaceMetrics.minCellWidth,
                                           height: SurfaceMetrics.slotCellHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(SurfaceMetrics.slotStripPadding)
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
                            (-value.translation.height / SurfaceMetrics.slotStripRowHeight)
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

    /// The ONLY call site of `capture` in this view. Every gesture that reaches it — clicking an
    /// empty cell, Replace in the context menu, and ⌥-click — is an explicit user act. A plain
    /// click on a filled cell routes to `recall`, never here: losing a dialled-in look to a
    /// one-cell mis-click is unrecoverable and would happen exactly once before the bank stopped
    /// being trusted.
    ///
    /// **No-op between task 4 and task 6 (task 4 brief, ambiguity note 2).** Removing SOURCE (this
    /// task) leaves no deck to capture FROM, and task 6 restores capture via a deck-monitor drag
    /// rather than reinstating a picker — so there is deliberately no way to capture a look for one
    /// review cycle; the two tasks land together. `SlotCell` itself is untouched (its empty-cell
    /// click and Replace menu item still call this), so the gap is silent rather than surfaced by a
    /// disabled control — accepted, not a stopgap fix.
    private func capture(into index: Int) {}
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
    let onRecall: () -> Void
    let onCapture: () -> Void
    let onClear: () -> Void

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if preset != nil {
                // Disabled while the file is missing: a plain click is already a dead recall in
                // that state (`SlotBank.recall` returns nil), and leaving Replace live invites
                // destroying the entry the model deliberately preserves through a bad mount.
                Button("Replace with SOURCE deck", action: onCapture)
                    .disabled(!isAvailable)
                // Left enabled even when unavailable: deliberately clearing a slot whose file is
                // gone for good is legitimate.
                Button("Clear slot", role: .destructive, action: onClear)
            }
        }
        .help(helpText)
        .accessibilityLabel(preset.map { "Slot \(index + 1), \($0.name)" } ?? "Slot \(index + 1), empty")
    }

    /// Empty → capture (nothing can be lost). Filled + ⌥ → capture (the deliberate overwrite).
    /// Filled, no modifier → ALWAYS recall. This is the one place the modifier check happens; the
    /// Button above is the one place a tap can originate.
    private func activate() {
        if preset == nil {
            onCapture()
        } else if NSEvent.modifierFlags.contains(.option) {
            onCapture()
        } else {
            onRecall()
        }
    }

    private var helpText: String {
        guard let preset else { return "Click to capture the SOURCE deck into slot \(index + 1)" }
        if !isAvailable { return "\(preset.name) — file not found" }
        return "\(preset.name) — click to recall, ⌥-click to replace, right-click for more"
    }
}
