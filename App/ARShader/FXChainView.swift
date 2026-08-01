import AppKit      // NSEvent.modifierFlags — SwiftUI alone does not guarantee it
import SwiftUI

/// One FX chain: an ordered, unbounded stack of stages.
///
/// Stage count is shown because it is a FACT the operator can act on. No per-chain milliseconds:
/// cost inside a single command buffer cannot be honestly attributed to one chain, and a number
/// the engine did not measure is not worth showing.
///
/// A drop target (task 5): a library drag onto this chain APPENDS a stage, through the same
/// `Instrument.load(_:onto:thenApply:)` seam a library click used to reach. `target` names WHICH
/// chain this is (`.deckFX(id)` or `.masterFX`) — `FXChainView` itself has no opinion, it is
/// always exactly what the call site says.
struct FXChainView: View {
    let title: String
    let instrument: Instrument
    /// Always `.deckFX` or `.masterFX` — never `.deck`. `LibraryTarget` is reused rather than a
    /// narrower type because it is exactly what `Instrument.load` already takes.
    let target: LibraryTarget
    @ObservedObject var chain: FXChain
    @ObservedObject var stats: RenderStatsModel
    @ObservedObject var library: LibraryModel
    @State private var isTargeted = false

    private var dragDestination: ShaderDrag.Destination {
        switch target {
        case .deck(let id):   return .deck(id)
        case .deckFX(let id): return .deckFX(id)
        case .masterFX:       return .masterFX
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(chain.stages.count) FX")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(budgetColor)
                    .help(budgetHelp)
            }
            if chain.stages.isEmpty {
                // Fix-round-1, F5: named the "Load onto" picker task 5 deleted. A chain fills
                // exactly one way now — drag a library shader onto it.
                Text("Drag a shader here to add it to the chain.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(chain.stages.enumerated()), id: \.element.id) { index, stage in
                FXStageRow(chain: chain, stage: stage, index: index, library: library)
            }
        }
        .padding(4)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .dropDestination(for: ShaderDrag.self) { items, _ in
            guard let drag = items.first,
                  ShaderDrag.accepts(drag, on: dragDestination, isSlotFilled: false,
                                     withOption: NSEvent.modifierFlags.contains(.option))
            else { return false }
            instrument.load(drag.url, onto: target, thenApply: drag.snapshot)
            return true
        // Accepted limitation, not an oversight (fix-round-1, F2 — operator ruling: keep the
        // modern API, do not fix). `isTargeted` receives only a `Bool`; SwiftUI resolves the
        // hovering item's VALUE only inside `action`, at drop time. A deck-sourced drag is
        // rejected by `ShaderDrag.accepts` for every destination here (only a library drag may
        // fill an FX chain), but this highlight cannot ask "which source is this?" before the
        // drop lands, so it lights up for a deck drag too — correctly rejected a moment later
        // when `action` runs, never appended. `DropDelegate`'s `DropInfo.itemProviders(for:)`
        // (macOS 11+) could answer this at `dropEntered`/`validateDrop`, but every such fix is an
        // API rollback off `Transferable`/`.dropDestination`, which the brief specified
        // deliberately (see `ShaderDrag.swift`'s own doc comment). Slots — the one destination
        // that can actually destroy a dialled-in look — ARE filtered correctly; see
        // `SlotBankStripView.wouldHighlight(at:)`.
        } isTargeted: { isTargeted = $0 }
    }

    /// Amber/red track the MEASURED global frame time, never a per-chain estimate. A chain with no
    /// stages is never blamed for the frame.
    private var budgetColor: Color {
        guard chain.stages.count > 0, let fps = stats.stats?.fps else { return .secondary }
        if fps < 30 { return .red }
        if fps < 54 { return .orange }
        return .secondary
    }

    private var budgetHelp: String {
        "Stages in this chain. The colour tracks the measured frame rate for the whole "
        + "instrument — cost inside one command buffer cannot be attributed to a single chain."
    }
}

/// One stage row: on/off, name, Mix, blend, reorder, remove — and its generated controls behind a
/// disclosure triangle so a deep chain stays readable.
struct FXStageRow: View {
    @ObservedObject var chain: FXChain
    @ObservedObject var stage: FXStage
    let index: Int
    @ObservedObject var library: LibraryModel
    @State private var expanded = false

    /// The row observes the stage AND its unit. The unit is what publishes the shader name and
    /// compile error, and a row observing only the stage would freeze at "—" exactly the way
    /// `DeckStripView` did before it was retargeted (Milestone 1 defect, 2026-07-30).
    @ObservedObject private var unit: ShaderUnit

    init(chain: FXChain, stage: FXStage, index: Int, library: LibraryModel) {
        self.chain = chain
        self.stage = stage
        self.index = index
        self.library = library
        self._unit = ObservedObject(wrappedValue: stage.unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Toggle("", isOn: Binding(get: { stage.isEnabled },
                                         set: { chain.setEnabled($0, for: stage) }))
                    .labelsHidden().toggleStyle(.checkbox)
                    .help("Off skips this stage entirely — no render, no cost")
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                // The whole name is the hit target, not just the chevron — a 12pt glyph is a poor
                // thing to aim at mid-set.
                Text(unit.shaderName ?? (unit.isLoading ? "loading…" : "—"))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .contentShape(Rectangle())
                    .onTapGesture { expanded.toggle() }
                    .help(unit.shaderName ?? "No shader")
                if stage.isGenerator {
                    Text("GEN").font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 3)
                        .background(.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                        .help("No image input — this shader REPLACES the feed rather than "
                              + "processing it. With Mix and a blend mode that is a usable move.")
                }
                Spacer()
                Button { chain.moveUp(index) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.plain).help("Move earlier in the chain")
                Button { chain.moveDown(index) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.plain).help("Move later in the chain")
                Button { chain.remove(stage.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Remove this stage")
            }
            HStack(spacing: 4) {
                Text("Mix").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { stage.mix },
                                      set: { chain.setMix($0, for: stage) }), in: 0...1)
                Text(String(format: "%.2f", stage.mix))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Picker("", selection: Binding(get: { stage.blendMode },
                                          set: { chain.setBlendMode($0, for: stage) })) {
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
            .labelsHidden().controlSize(.small)
            if let error = unit.compileError {
                Text(error).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            if expanded {
                // minHeight is load-bearing. ShaderControlsView is itself a ScrollView, and a
                // ScrollView nested in another scrolling container has NO intrinsic height — with
                // only a maxHeight it collapses to nothing and the stage's sliders are invisible
                // even though the disclosure "opened". Caught on the first live look, 2026-07-30.
                // Its own SOURCES block: the primary shows as the chain feed, and a second input
                // (a mask, a blend layer) is still the operator's to route.
                SourceRoutingView(unit: unit, library: library)
                ShaderControlsView(unit: unit)
                    .frame(minHeight: 150, maxHeight: 260)
            }
            Divider()
        }
    }
}
