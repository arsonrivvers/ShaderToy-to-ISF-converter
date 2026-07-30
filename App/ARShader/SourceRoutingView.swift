import SwiftUI
import ShadertoyISFKit   // TestPatternCatalog

/// Where each of a shader's image inputs gets its pixels.
///
/// A dedicated block rather than rows buried in the generated parameter list: routing is a
/// different KIND of decision from turning a knob, it is the first thing you set on a filter, and
/// mixed in among the float sliders it read as clutter (operator, 2026-07-30). Sits directly under
/// the shader name, above Opacity.
///
/// Renders nothing at all for a generator — no image inputs, no block, no empty header.
struct SourceRoutingView: View {
    @ObservedObject var unit: ShaderUnit
    /// The ROUTER publishes the selections; `unit` does not republish when a route changes, so the
    /// menu labels would go stale if this observed only the unit.
    @ObservedObject private var router: SourceRouter
    @ObservedObject private var library: LibraryModel

    init(unit: ShaderUnit, library: LibraryModel) {
        self.unit = unit
        self.router = unit.imageSources
        self.library = library
    }

    /// Image inputs only, in ISF declaration order, each already classified as routable or
    /// chain-fed by the same tested model that drives the parameter list.
    private var rows: [DeckControlModel.ControlRow] {
        DeckControlModel.rows(for: unit.inputs, reservesPrimaryInput: unit.reservesPrimaryInput)
            .filter { $0.kind == .routed || $0.kind == .chainFed }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("SOURCES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                ForEach(rows) { row in
                    switch row.kind {
                    case .chainFed: chainFedRow(row.input)
                    default:        sourceRow(row.input)
                    }
                }
            }
        }
    }

    /// A filter loaded on a DECK has no chain feeding it, so without this its `inputImage` is
    /// whatever the router defaulted to — the camera — and the operator has no way to say
    /// otherwise. Same vocabulary as the editor's source toolbar, deliberately.
    @ViewBuilder private func sourceRow(_ input: ISFPreviewInput) -> some View {
        HStack(spacing: 5) {
            Text(input.name)
                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Menu {
                Button("None") { router.setSelection(.none, for: input.name) }
                Menu("Test Pattern") {
                    ForEach(TestPatternCatalog.all) { p in
                        Button(p.name) { router.setSelection(.testPattern(id: p.id),
                                                             for: input.name) }
                    }
                }
                Menu("Shader") {
                    ForEach(library.filtered(query: "")) { entry in
                        Button(entry.name) { router.setSelection(.library(url: entry.url),
                                                                 for: input.name) }
                    }
                }
                Button("Camera") { router.setSelection(.camera, for: input.name) }
            } label: {
                Text(router.source(for: input.name).displayName)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: 150)
        }
        .help("Input source for “\(input.name)”")
    }

    /// An FX stage's primary input. Labelled, never a picker: the chain drives it, and a source
    /// menu here would silently unplug the stage from what came before it. Shown rather than
    /// hidden so the operator is not left wondering where the input went.
    @ViewBuilder private func chainFedRow(_ input: ISFPreviewInput) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.right.to.line")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Text(input.name)
                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("chain").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .help("Fed by the previous stage in this chain — or by the deck itself for the first "
              + "stage. Not routable, by design.")
    }
}
