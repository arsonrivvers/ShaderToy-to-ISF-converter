import SwiftUI

/// One FX chain: an ordered, unbounded stack of stages.
///
/// Stage count is shown because it is a FACT the operator can act on. No per-chain milliseconds:
/// cost inside a single command buffer cannot be honestly attributed to one chain, and a number
/// the engine did not measure is not worth showing.
struct FXChainView: View {
    let title: String
    @ObservedObject var chain: FXChain
    @ObservedObject var stats: RenderStatsModel
    @ObservedObject var library: LibraryModel

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
                Text("Load a shader with this chain selected in the library.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(chain.stages.enumerated()), id: \.element.id) { index, stage in
                FXStageRow(chain: chain, stage: stage, index: index, library: library)
            }
        }
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
                Text(unit.shaderName ?? (unit.isLoading ? "loading…" : "—"))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
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
                ShaderControlsView(unit: unit, library: library).frame(maxHeight: 220)
            }
            Divider()
        }
    }
}
