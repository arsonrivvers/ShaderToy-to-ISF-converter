### Task 7: The bank panel

**Files:**
- Modify: `App/ARShader/SlotBankPanelView.swift` (the real view)
- Test: `App/ARShaderTests/SlotBankTests.swift` (extend — gesture-routing tests only)

**Interfaces:**
- Consumes: everything above.
- Produces: no new public API.

**The safety property this task exists to protect:** *no code path may call `capture` on an occupied slot without an explicit user act.* That is a code-review item, not a unit test — the reviewer must trace every call site of `capture` in the view and confirm each is behind a distinct gesture.

- [ ] **Step 1: Write the implementation**

```swift
import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
import SwiftUI

/// The slot bank: eight cells, a SOURCE deck picker, and nothing else.
///
/// Recall fires into the load-target picker the library already owns — one answer to "load onto
/// what", shared by library clicks and slot hits. SOURCE is separate and means the opposite
/// direction: which deck a capture READS from. Sending library clicks to master FX while capturing
/// deck A is a normal state, so one control could not carry both meanings.
struct SlotBankPanelView: View {
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
        VStack(spacing: 6) {
            Picker("Capture from", selection: $source) {
                ForEach(DeckID.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Capture from")

            ForEach(0..<SlotBank.slotCount, id: \.self) { index in
                SlotCell(index: index,
                         preset: bank.slots[index],
                         isAvailable: bank.isAvailable(index),
                         onRecall: { recall(index) },
                         onCapture: { capture(into: index) },
                         onClear: { bank.clear(index) })
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private func recall(_ index: Int) {
        guard let preset = bank.recall(index) else { return }
        instrument.load(preset.shaderURL, onto: target, thenApply: preset.snapshot)
    }

    /// The ONLY call site of `capture` in this view. Both gestures that reach it — clicking an
    /// empty cell, and Replace on a filled one — are explicit user acts. A plain click on a filled
    /// cell routes to `recall`, never here: losing a dialled-in look to a one-cell mis-click is
    /// unrecoverable and would happen exactly once before the bank stopped being trusted.
    private func capture(into index: Int) {
        guard let preset = instrument.currentPreset(of: source) else { return }
        bank.capture(preset, into: index)
    }
}

/// One cell. Empty cells invite capture; filled ones recall and hide their destructive actions
/// behind hover.
private struct SlotCell: View {
    let index: Int
    let preset: Preset?
    let isAvailable: Bool
    let onRecall: () -> Void
    let onCapture: () -> Void
    let onClear: () -> Void

    @State private var isHovering = false

    var body: some View {
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
                if isHovering {
                    Button("Replace", action: onCapture).buttonStyle(.plain)
                        .font(.system(size: 10))
                    Button("Clear", action: onClear).buttonStyle(.plain)
                        .font(.system(size: 10))
                }
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
        .onHover { isHovering = $0 }
        // EXACTLY ONE tap gesture. Two `.onTapGesture` modifiers on the same view both fire,
        // so a second one for ⌥-click would make an option-click recall AND capture — breaking
        // the one safety property this cell exists to protect. The modifier check lives inside
        // the single handler instead.
        .onTapGesture {
            if preset == nil {
                onCapture()                       // empty: nothing can be lost
            } else if NSEvent.modifierFlags.contains(.option) {
                onCapture()                       // ⌥-click: the deliberate overwrite
            } else {
                onRecall()                        // plain click on a filled cell: ALWAYS recall
            }
        }
        .help(helpText)
        .accessibilityLabel(preset.map { "Slot \(index + 1), \($0.name)" } ?? "Slot \(index + 1), empty")
    }

    private var helpText: String {
        guard let preset else { return "Click to capture the SOURCE deck into slot \(index + 1)" }
        if !isAvailable { return "\(preset.name) — file not found" }
        return "\(preset.name) — click to recall, ⌥-click to replace"
    }
}

```

Update `InstrumentView.panelContent`:
```swift
        case .bank:
            SlotBankPanelView(instrument: instrument, target: $libraryTarget)
```

- [ ] **Step 2: Build and run the full suite**

Expected: 240 tests, 0 failures. No new tests in this task — the view's logic is routing, and the model beneath it is fully covered.

- [ ] **Step 3: Verify the safety property by inspection**

Grep every call: `grep -n "\.capture(" App/ARShader/*.swift`. Confirm the only call in view code is inside `SlotBankPanelView.capture(into:)`, and that the only paths reaching it are the empty-cell tap, the Replace button, and ⌥-click. **Write the result of this grep into the task report.**

- [ ] **Step 4: Commit**

```bash
git add App/ARShader/SlotBankPanelView.swift App/ARShader/InstrumentView.swift
git commit -m "feat(3b): the bank panel — a filled slot can only ever recall"
```

---

