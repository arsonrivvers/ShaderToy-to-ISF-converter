import SwiftUI

/// The ⚙ Crossover settings popover: balance + variation sliders, a per-trait routing matrix, and a
/// directive-pool toggle list. Balance + routing show only in Crossover mode (they need two parents).
struct RemixCrossoverPopover: View {
    @ObservedObject var model: RemixStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crossover settings").font(.headline)
                Spacer()
                Button("Reset") { model.crossoverSettings = RemixCrossoverSettings() }
                    .font(.caption).buttonStyle(.link)
            }

            if model.mode == .crossover {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parent balance").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("A").font(.caption2)
                        Slider(value: $model.crossoverSettings.balance, in: 0...1)
                        Text("B").font(.caption2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Variation").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Faithful").font(.caption2)
                    Slider(value: $model.crossoverSettings.variation, in: 0...1)
                    Text("Wild").font(.caption2)
                }
            }

            if model.mode == .crossover {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trait routing").font(.caption).foregroundStyle(.secondary)
                    ForEach(RemixTrait.allCases, id: \.self) { trait in
                        HStack {
                            Text(trait.rawValue.capitalized).font(.caption).frame(width: 70, alignment: .leading)
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
                Text("Directive pool").font(.caption).foregroundStyle(.secondary)
                ForEach(RemixDirectives.catalog, id: \.self) { vector in
                    Toggle(vector, isOn: Binding(
                        get: { model.crossoverSettings.enabledDirectives.contains(vector) },
                        set: { on in
                            if on { model.crossoverSettings.enabledDirectives.insert(vector) }
                            else { model.crossoverSettings.enabledDirectives.remove(vector) }
                        }
                    )).font(.caption2).toggleStyle(.checkbox)
                }
                if model.crossoverSettings.enabledDirectives.isEmpty {
                    Text("All off — the batch falls back to every vector.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
