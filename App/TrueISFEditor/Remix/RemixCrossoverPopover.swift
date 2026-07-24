import SwiftUI

/// The ⚙ Crossover settings popover: balance + variation sliders, a per-trait routing matrix, and a
/// directive-pool toggle list. Balance + routing show only in Crossover mode (they need two parents).
struct RemixCrossoverPopover: View {
    @ObservedObject var model: RemixStudioModel
    let onDismiss: () -> Void

    init(model: RemixStudioModel, onDismiss: @escaping () -> Void = {}) {
        self.model = model
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crossover settings").font(.headline)
                Spacer()
                Button("Reset") { model.crossoverSettings = RemixCrossoverSettings() }
                    .font(remixBodyFont).buttonStyle(.link)
            }

            if model.mode == .crossover {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parent balance").font(remixBodyFont).foregroundStyle(.secondary)
                    HStack {
                        Text("A").font(remixBodyFont)
                        Slider(value: $model.crossoverSettings.balance, in: 0...1)
                            .accessibilityLabel("Parent balance")
                            .accessibilityValue(balanceValue)
                        Text("B").font(remixBodyFont)
                    }
                    Text(balanceValue).font(remixBodyFont).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Variation").font(remixBodyFont).foregroundStyle(.secondary)
                HStack {
                    Text("Faithful").font(remixBodyFont)
                    Slider(value: $model.crossoverSettings.variation, in: 0...1)
                        .accessibilityLabel("Variation")
                        .accessibilityValue(variationValue)
                    Text("Wild").font(remixBodyFont)
                }
                Text(variationValue).font(remixBodyFont).foregroundStyle(.secondary)
            }

            if model.mode == .crossover {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trait routing").font(remixBodyFont).foregroundStyle(.secondary)
                    ForEach(RemixTrait.allCases, id: \.self) { trait in
                        HStack {
                            Text(trait.rawValue.capitalized).font(remixBodyFont).frame(minWidth: 70, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { model.crossoverSettings.source(for: trait) },
                                set: { model.crossoverSettings.setSource($0, for: trait) }
                            )) {
                                Text("A").tag(RemixTraitSource.a)
                                Text("auto").tag(RemixTraitSource.auto)
                                Text("B").tag(RemixTraitSource.b)
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Directive pool").font(remixBodyFont).foregroundStyle(.secondary)
                ForEach(RemixDirectives.catalog, id: \.self) { vector in
                    Toggle(vector, isOn: Binding(
                        get: { model.crossoverSettings.enabledDirectives.contains(vector) },
                        set: { on in
                            if on { model.crossoverSettings.enabledDirectives.insert(vector) }
                            else { model.crossoverSettings.enabledDirectives.remove(vector) }
                        }
                    )).font(remixBodyFont).toggleStyle(.checkbox)
                }
                if model.crossoverSettings.enabledDirectives.isEmpty {
                    Text("All off — the batch falls back to every vector.")
                        .font(remixBodyFont).foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 380)
        .font(RemixTextPolicy.bodyFont)
        .onDisappear(perform: onDismiss)
    }

    private var balanceValue: String {
        let b = Int((model.crossoverSettings.balance * 100).rounded())
        return "\(100 - b) percent Parent A, \(b) percent Parent B"
    }

    private var remixBodyFont: Font {
        RemixAccessibleTextLayout.bodyFont
    }

    private var variationValue: String {
        let percent = Int((model.crossoverSettings.variation * 100).rounded())
        return "\(percent) percent variation"
    }
}
