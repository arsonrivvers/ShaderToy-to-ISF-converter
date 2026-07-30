import SwiftUI
import AppKit
import ShadertoyISFKit   // TestPatternCatalog, for the image-input source menu

/// Pure mapping from ISF input descriptors to control rows. Split out from the view so control
/// generation is testable without SwiftUI, and so an unknown type is a visible row rather than a
/// silent omission.
enum DeckControlModel {
    enum Kind: Equatable {
        case slider, toggle, point, color, menu, pulse
        /// Image inputs are routed through `SourceRouter`, not set as values. Gets a source picker.
        case routed
        /// An FX stage's FIRST image input: driven by the chain, not the router. Shown as a label
        /// rather than a picker — offering a source here would silently unplug the stage from the
        /// chain, and hiding it entirely would leave the operator wondering where the input went.
        case chainFed
        /// The engine reported a type this build cannot render a control for. Shown, never dropped.
        case unsupported
    }

    struct ControlRow: Identifiable, Equatable {
        let input: ISFPreviewInput
        let kind: Kind
        var id: String { input.name }
    }

    /// Rows in ISF header declaration order — the author's intent, never alphabetised.
    ///
    /// `reservesPrimaryInput` mirrors `ShaderUnit`: on an FX stage the FIRST image input is the
    /// chain feed and is not the operator's to route. Every LATER image input still is — that is
    /// how a blend or mask stage gets its second layer.
    static func rows(for inputs: [ISFPreviewInput],
                     reservesPrimaryInput: Bool = false) -> [ControlRow] {
        let firstImageName = inputs.first { $0.type == "image" }?.name
        return inputs.map { input in
            let kind: Kind
            switch input.type {
            case "float":   kind = .slider
            case "bool":    kind = .toggle
            case "point2D": kind = .point
            case "color":   kind = .color
            case "long":    kind = .menu
            case "event":   kind = .pulse
            case "image":
                kind = (reservesPrimaryInput && input.name == firstImageName) ? .chainFed : .routed
            default:        kind = .unsupported
            }
            return ControlRow(input: input, kind: kind)
        }
    }
}

/// Auto-generated controls for one hosted shader — a deck's, or an FX stage's.
struct ShaderControlsView: View {
    @ObservedObject var unit: ShaderUnit
    /// The router publishes the selections, so the source pickers need it observed directly —
    /// `unit` does not republish when a route changes.
    @ObservedObject private var router: SourceRouter
    @ObservedObject private var library: LibraryModel

    init(unit: ShaderUnit, library: LibraryModel) {
        self.unit = unit
        self.router = unit.imageSources
        self.library = library
    }

    private var rows: [DeckControlModel.ControlRow] {
        DeckControlModel.rows(for: unit.inputs,
                              reservesPrimaryInput: unit.reservesPrimaryInput)
    }

    var body: some View {
        ScrollView {
            // LazyVStack is load-bearing: a plain VStack lays out ALL rows on every main-thread
            // layout pass, and an 80-input shader then starves the render loop during a drag.
            LazyVStack(alignment: .leading, spacing: 9) {
                if let error = unit.compileError {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if unit.shaderName == nil {
                    Text("No shader loaded").font(.caption).foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    Text("No adjustable inputs").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    switch row.kind {
                    case .slider:      sliderRow(row.input)
                    case .toggle:      toggleRow(row.input)
                    case .point:       pointRow(row.input)
                    case .color:       colorRow(row.input)
                    case .menu:        menuRow(row.input)
                    case .pulse:       pulseRow(row.input)
                    case .routed:      sourceRow(row.input)
                    case .chainFed:    chainFedRow(row.input)
                    case .unsupported: unsupportedRow(row.input)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Label left, live value right. Double-click resets; a dot marks a value off its default.
    private func labelRow(_ name: String, value: String) -> some View {
        HStack(spacing: 5) {
            if unit.params.isModified(name) { Circle().fill(.tint).frame(width: 5, height: 5) }
            Text(name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { unit.params.resetToDefault(name) }
        .help("Double-click to reset to default")
    }

    private func format(_ v: Double) -> String { String(format: "%.3g", v) }

    @ViewBuilder private func sliderRow(_ input: ISFPreviewInput) -> some View {
        let lo = (input.min as? Double) ?? 0
        let hi = (input.max as? Double) ?? 1
        let fallback = (input.defaultValue as? Double) ?? lo
        let binding = Binding<Double>(
            get: { if case .float(let v)? = unit.params.value(for: input.name) { return v }
                   return fallback },
            set: { unit.params.set(input.name, .float($0)) })
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: format(binding.wrappedValue))
            Slider(value: binding, in: lo...max(hi, lo + 0.0001))
        }
    }

    @ViewBuilder private func toggleRow(_ input: ISFPreviewInput) -> some View {
        let binding = Binding<Bool>(
            get: { if case .bool(let v)? = unit.params.value(for: input.name) { return v }
                   return (input.defaultValue as? Bool) ?? false },
            set: { unit.params.set(input.name, .bool($0)) })
        Toggle(input.name, isOn: binding).font(.system(size: 12))
    }

    @ViewBuilder private func pointRow(_ input: ISFPreviewInput) -> some View {
        let lo = ParamStore.doubles(input.min, count: 2, fallback: [0, 0])
        let hi = ParamStore.doubles(input.max, count: 2, fallback: [1, 1])
        let fallback = ParamStore.doubles(input.defaultValue, count: 2, fallback: [0.5, 0.5])
        let current: [Double] = {
            if case .point2D(let p)? = unit.params.value(for: input.name) { return p }
            return fallback
        }()
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: "\(format(current[0])), \(format(current[1]))")
            ForEach(0..<2, id: \.self) { axis in
                Slider(value: Binding<Double>(
                    get: { current[axis] },
                    set: { newValue in
                        var next = current
                        next[axis] = newValue
                        unit.params.set(input.name, .point2D(next))
                    }), in: lo[axis]...max(hi[axis], lo[axis] + 0.0001))
            }
        }
    }

    @ViewBuilder private func colorRow(_ input: ISFPreviewInput) -> some View {
        let fallback = ParamStore.doubles(input.defaultValue, count: 4, fallback: [1, 1, 1, 1])
        let current: [Double] = {
            if case .color(let c)? = unit.params.value(for: input.name) { return c }
            return fallback
        }()
        let binding = Binding<Color>(
            get: { Color(red: current[0], green: current[1], blue: current[2])
                     .opacity(current[3]) },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .white
                unit.params.set(input.name, .color([Double(ns.redComponent),
                                                    Double(ns.greenComponent),
                                                    Double(ns.blueComponent),
                                                    Double(ns.alphaComponent)]))
            })
        HStack {
            labelRow(input.name, value: "")
            ColorPicker("", selection: binding, supportsOpacity: true).labelsHidden()
        }
    }

    @ViewBuilder private func menuRow(_ input: ISFPreviewInput) -> some View {
        let values = input.values ?? []
        let labels = input.labels ?? values.map { format($0) }
        let fallback = (input.defaultValue as? Double) ?? values.first ?? 0
        let binding = Binding<Double>(
            get: { if case .long(let v)? = unit.params.value(for: input.name) { return v }
                   return fallback },
            set: { unit.params.set(input.name, .long($0)) })
        HStack {
            Text(input.name).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Picker("", selection: binding) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    Text(i < labels.count ? labels[i] : format(v)).tag(v)
                }
            }
            .labelsHidden().frame(maxWidth: 160)
        }
    }

    @ViewBuilder private func pulseRow(_ input: ISFPreviewInput) -> some View {
        Button(input.name) { unit.pulseEvent(input.name) }
            .font(.system(size: 12))
    }

    /// Where this image input's pixels come from. A filter loaded on a DECK has no chain feeding
    /// it, so without this its `inputImage` is whatever the router defaulted to — the camera — and
    /// the operator has no way to say otherwise.
    @ViewBuilder private func sourceRow(_ input: ISFPreviewInput) -> some View {
        HStack(spacing: 5) {
            Text(input.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
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
    /// menu here would silently unplug the stage from what came before it.
    @ViewBuilder private func chainFedRow(_ input: ISFPreviewInput) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.right.to.line")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Text(input.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("chain").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .help("Fed by the previous stage in this chain — or by the deck itself for the first "
              + "stage. Not routable, by design.")
    }

    @ViewBuilder private func unsupportedRow(_ input: ISFPreviewInput) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text("\(input.name) — \(input.type) not supported")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .help("The engine reports this input, but this build has no control for its type.")
    }
}
