import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
import SwiftUI

/// The slot bank: a SOURCE deck picker, a RECALL TO destination picker, and one row of eight cells
/// — always visible directly under the monitors, never a panel to open mid-set.
///
/// Moved here from the rail (task 6R) because recall fires at `target`, and a rail panel put that
/// picker off-screen exactly when the Bank panel itself was open — an operator could fire a slot at
/// an invisible destination, where one wrong value silently appends unbounded FX stages. An
/// always-visible strip keeps the destination always visible too.
///
/// Two pickers, two directions, both on the strip's leading edge. Both bind the SAME `$target` the
/// Library panel binds, so there is no duplicated state: SOURCE (deck A/B) is where a capture READS
/// from; RECALL TO is where a recall WRITES to. Leaving RECALL TO on a stale value such as `MST FX`
/// would make recall additive — every slot click appends a new FX stage instead of swapping a deck.
///
/// Rows, collapse, and the resize drag (task 7R). The model (`SlotBank`) always holds forty slots
/// and has no concept of rows at all — `layout.bankRows` decides how many are DRAWN, never how
/// many exist, which is what makes "shrinking rows can never destroy a captured look" structural
/// rather than a promise. See `SlotBank.slotCount`'s doc comment.
struct SlotBankStripView: View {
    let instrument: Instrument
    @Binding var target: LibraryTarget
    @ObservedObject private var bank: SlotBank
    @ObservedObject var layout: SurfaceLayout
    @State private var source: DeckID = .one

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

    init(instrument: Instrument, target: Binding<LibraryTarget>, layout: SurfaceLayout) {
        self.instrument = instrument
        self._target = target
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
                Text("SOURCE")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Picker("Capture from", selection: $source) {
                    ForEach(DeckID.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Capture from — which deck a capture reads")
            }
            .frame(width: SurfaceMetrics.slotStripSourceWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text("RECALL TO")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Picker("Load onto", selection: $target) {
                    ForEach(LibraryTarget.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Load onto — where a recall writes")
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
            ScrollView(.horizontal, showsIndicators: true) {
                // One VStack of rows inside a SINGLE horizontal ScrollView, not one ScrollView per
                // row — separate scroll views could drift out of sync and a wide bank would show
                // row 1 and row 2 scrolled to different columns.
                VStack(alignment: .leading, spacing: SurfaceMetrics.slotStripCellSpacing) {
                    ForEach(0..<layout.bankRows, id: \.self) { row in
                        HStack(spacing: SurfaceMetrics.slotStripCellSpacing) {
                            ForEach(0..<SlotBank.perRow, id: \.self) { column in
                                let index = row * SlotBank.perRow + column
                                SlotCell(index: index,
                                         preset: bank.slots[index],
                                         isAvailable: bank.isAvailable(index),
                                         onRecall: { recall(index) },
                                         onCapture: { capture(into: index) },
                                         onClear: { bank.clear(index) })
                                    .frame(minWidth: SurfaceMetrics.minCellWidth,
                                           maxWidth: .infinity)
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
        instrument.load(preset.shaderURL, onto: target, thenApply: preset.snapshot)
    }

    /// The ONLY call site of `capture` in this view. Every gesture that reaches it — clicking an
    /// empty cell, Replace in the context menu, and ⌥-click — is an explicit user act. A plain
    /// click on a filled cell routes to `recall`, never here: losing a dialled-in look to a
    /// one-cell mis-click is unrecoverable and would happen exactly once before the bank stopped
    /// being trusted.
    private func capture(into index: Int) {
        guard let preset = instrument.currentPreset(of: source) else { return }
        bank.capture(preset, into: index)
    }
}

/// One cell. Empty cells invite capture; filled ones recall on a plain click and hide Replace and
/// Clear behind a context menu — unconditionally available, not just under a mouse that happens to
/// have entered from the right direction.
private struct SlotCell: View {
    let index: Int
    let preset: Preset?
    let isAvailable: Bool
    let onRecall: () -> Void
    let onCapture: () -> Void
    let onClear: () -> Void

    var body: some View {
        // The single tap-delivery path for this cell. A real `Button` (not a bare
        // `.onTapGesture`) so VoiceOver gets a native button trait and an activate action for
        // free, matching `LibraryPanelView`'s row pattern. The accessibility label sits on the
        // Button itself, which SwiftUI already treats as one combined element — no child text or
        // control announces separately.
        Button(action: activate) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                if let preset {
                    Text(preset.name)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)   // long AR_Genuary names differ at the END
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("empty")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 5).padding(.horizontal, 6)
            .frame(minHeight: 28)
            .background(preset == nil ? Color.clear : Color.white.opacity(0.06))
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
