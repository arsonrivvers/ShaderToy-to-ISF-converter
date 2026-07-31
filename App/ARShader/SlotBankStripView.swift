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
/// One row of eight cells only. Rows, collapse, and the resize drag are task 7R.
struct SlotBankStripView: View {
    let instrument: Instrument
    @Binding var target: LibraryTarget
    @ObservedObject private var bank: SlotBank
    @State private var source: DeckID = .one

    init(instrument: Instrument, target: Binding<LibraryTarget>) {
        self.instrument = instrument
        self._target = target
        self.bank = instrument.slotBank
    }

    var body: some View {
        HStack(spacing: 10) {
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
            .frame(width: 90)

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
            .frame(width: 220)

            Divider()

            HStack(spacing: 6) {
                ForEach(0..<SlotBank.slotCount, id: \.self) { index in
                    SlotCell(index: index,
                             preset: bank.slots[index],
                             isAvailable: bank.isAvailable(index),
                             onRecall: { recall(index) },
                             onCapture: { capture(into: index) },
                             onClear: { bank.clear(index) })
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(8)
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
