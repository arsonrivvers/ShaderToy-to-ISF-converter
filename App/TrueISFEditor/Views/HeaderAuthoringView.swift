import SwiftUI
import ShadertoyISFKit

/// The right-column bottom panel: tabbed `Adjust | Inputs | Passes`. Adjust is the existing live
/// controls; Inputs/Passes author the header through `HeaderAuthoringModel`.
struct HeaderPanelView: View {
    @ObservedObject var coordinator: PreviewCoordinator
    @ObservedObject var model: HeaderAuthoringModel
    enum Tab: String, CaseIterable { case adjust = "Adjust", inputs = "Inputs", passes = "Passes" }
    @State private var tab: Tab = .adjust

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).padding(.horizontal, 6).padding(.top, 4)
            Divider().padding(.top, 4)
            switch tab {
            case .adjust: PreviewControlsView(coordinator: coordinator)
            case .inputs: InputsAuthoringView(model: model)
            case .passes: PassesAuthoringView(model: model)
            }
        }
    }
}

// MARK: - Inputs

struct InputsAuthoringView: View {
    @ObservedObject var model: HeaderAuthoringModel
    private let addableTypes = ["float", "bool", "long", "point2D", "color", "image", "event"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.state == .malformed {
                    malformedBanner
                }
                ForEach(model.header.inputs.indices, id: \.self) { i in
                    InputRow(model: model, index: i)
                }
                Menu {
                    ForEach(addableTypes, id: \.self) { t in
                        Button(t) { model.update { $0.inputs.append(.makeDefault(type: t, name: uniqueName(base: t))) } }
                    }
                } label: { Label("Add input", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(model.state == .malformed)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var malformedBanner: some View {
        Text("Header JSON is invalid — fix it in the code editor to edit inputs here.")
            .font(.caption).foregroundStyle(.orange)
            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private func uniqueName(base: String) -> String {
        let existing = Set(model.header.inputs.map(\.name))
        if !existing.contains(base) { return base }
        var n = 1
        while existing.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }
}

/// One inline-expandable input row.
private struct InputRow: View {
    @ObservedObject var model: HeaderAuthoringModel
    let index: Int
    @State private var expanded = false
    @State private var nameDraft = ""

    private var input: ISFInput? { index < model.header.inputs.count ? model.header.inputs[index] : nil }

    var body: some View {
        guard let input else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                    }.buttonStyle(.plain)
                    Text(input.type).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).background(.secondary.opacity(0.15), in: Capsule())
                    Text(input.name).font(.caption).bold()
                    Spacer()
                    Button { model.update { if index < $0.inputs.count { $0.inputs.remove(at: index) } } } label: {
                        Image(systemName: "trash").font(.caption2)
                    }.buttonStyle(.plain).help("Delete input")
                    Button { model.update { $0.inputs.swapAt(index, max(0, index - 1)) } } label: {
                        Image(systemName: "arrow.up").font(.caption2)
                    }.buttonStyle(.plain).disabled(index == 0).help("Move up")
                    Button { model.update { if index + 1 < $0.inputs.count { $0.inputs.swapAt(index, index + 1) } } } label: {
                        Image(systemName: "arrow.down").font(.caption2)
                    }.buttonStyle(.plain).disabled(index >= model.header.inputs.count - 1).help("Move down")
                }
                if expanded { fields(for: input) }
            }
            .padding(6)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        )
    }

    @ViewBuilder private func fields(for input: ISFInput) -> some View {
        // Name (commit on submit so we don't rename on every keystroke / write invalid intermediates).
        HStack {
            Text("name").font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            TextField("name", text: $nameDraft)
                .textFieldStyle(.roundedBorder).font(.caption)
                .onAppear { nameDraft = input.name }
                .onSubmit { commitName() }
        }
        switch input.type {
        case "float", "long": numberRow("DEFAULT", input); numberRow("MIN", input); numberRow("MAX", input)
            if input.type == "long" { LongEnumEditor(model: model, index: index) }
        case "bool": Toggle("default on", isOn: boolBinding("DEFAULT")).font(.caption)
        case "color": ColorPicker("default", selection: colorBinding(), supportsOpacity: true).font(.caption)
        case "point2D": pointRow("DEFAULT", input); pointRow("MIN", input); pointRow("MAX", input)
        case "image", "event": EmptyView()
        default: EmptyView()
        }
    }

    private func commitName() {
        guard model.nameIsValid(nameDraft, atInputIndex: index) else { nameDraft = input?.name ?? ""; return }
        let n = nameDraft.trimmingCharacters(in: .whitespaces)
        model.update { if index < $0.inputs.count { $0.inputs[index].name = n } }
    }

    // MARK: field editors

    @ViewBuilder private func numberRow(_ key: String, _ input: ISFInput) -> some View {
        HStack {
            Text(key.lowercased()).font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            TextField(key, value: numberBinding(key), format: .number).textFieldStyle(.roundedBorder).font(.caption)
        }
    }

    @ViewBuilder private func pointRow(_ key: String, _ input: ISFInput) -> some View {
        HStack {
            Text(key.lowercased()).font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            TextField("x", value: pointBinding(key, axis: 0), format: .number).textFieldStyle(.roundedBorder).font(.caption)
            TextField("y", value: pointBinding(key, axis: 1), format: .number).textFieldStyle(.roundedBorder).font(.caption)
        }
    }

    private func numberBinding(_ key: String) -> Binding<Double> {
        Binding(
            get: { if case .number(let d)? = input?.attributes[key] { return d }; return 0 },
            set: { v in model.update { if index < $0.inputs.count { $0.inputs[index].attributes[key] = .number(v) } } })
    }
    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { if case .bool(let b)? = input?.attributes[key] { return b }; return false },
            set: { v in model.update { if index < $0.inputs.count { $0.inputs[index].attributes[key] = .bool(v) } } })
    }
    private func pointBinding(_ key: String, axis: Int) -> Binding<Double> {
        Binding(
            get: {
                if case .array(let a)? = input?.attributes[key], axis < a.count, case .number(let d) = a[axis] { return d }
                return 0
            },
            set: { v in
                model.update {
                    guard index < $0.inputs.count else { return }
                    var arr: [JSONValue] = [.number(0), .number(0)]
                    if case .array(let a)? = $0.inputs[index].attributes[key] { arr = a }
                    while arr.count < 2 { arr.append(.number(0)) }
                    arr[axis] = .number(v)
                    $0.inputs[index].attributes[key] = .array(arr)
                }
            })
    }
    private func colorBinding() -> Binding<Color> {
        Binding(
            get: {
                if case .array(let a)? = input?.attributes["DEFAULT"], a.count >= 4 {
                    let c = a.map { if case .number(let d) = $0 { return d } else { return 0 } }
                    return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3])
                }
                return .white
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .white
                let rgba: [JSONValue] = [.number(Double(ns.redComponent)), .number(Double(ns.greenComponent)),
                                         .number(Double(ns.blueComponent)), .number(Double(ns.alphaComponent))]
                model.update { if index < $0.inputs.count { $0.inputs[index].attributes["DEFAULT"] = .array(rgba) } }
            })
    }
}

/// Editor for a `long` input's LABELS→VALUES enum pairs.
private struct LongEnumEditor: View {
    @ObservedObject var model: HeaderAuthoringModel
    let index: Int

    private var labels: [String] {
        if case .array(let a)? = model.header.inputs[safe: index]?.attributes["LABELS"] {
            return a.map { if case .string(let s) = $0 { return s } else { return "" } }
        }
        return []
    }
    private var values: [Double] {
        if case .array(let a)? = model.header.inputs[safe: index]?.attributes["VALUES"] {
            return a.map { if case .number(let d) = $0 { return d } else { return 0 } }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("enum options").font(.caption2).foregroundStyle(.secondary)
            ForEach(labels.indices, id: \.self) { i in
                HStack {
                    TextField("label", text: labelBinding(i)).textFieldStyle(.roundedBorder).font(.caption2)
                    Text("→").foregroundStyle(.secondary)
                    TextField("value", value: valueBinding(i), format: .number)
                        .textFieldStyle(.roundedBorder).font(.caption2).frame(width: 50)
                    Button { removePair(i) } label: { Image(systemName: "minus.circle").font(.caption2) }.buttonStyle(.plain)
                }
            }
            Button { addPair() } label: { Label("Add option", systemImage: "plus").font(.caption2) }.buttonStyle(.plain)
        }
    }

    private func writePairs(_ ls: [String], _ vs: [Double]) {
        model.update {
            guard index < $0.inputs.count else { return }
            $0.inputs[index].attributes["LABELS"] = .array(ls.map(JSONValue.string))
            $0.inputs[index].attributes["VALUES"] = .array(vs.map(JSONValue.number))
        }
    }
    private func labelBinding(_ i: Int) -> Binding<String> {
        Binding(get: { i < labels.count ? labels[i] : "" },
                set: { var ls = labels; if i < ls.count { ls[i] = $0; writePairs(ls, values) } })
    }
    private func valueBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { i < values.count ? values[i] : 0 },
                set: { var vs = values; if i < vs.count { vs[i] = $0; writePairs(labels, vs) } })
    }
    private func addPair() { writePairs(labels + ["Option \(labels.count + 1)"], values + [Double(values.count)]) }
    private func removePair(_ i: Int) {
        var ls = labels, vs = values
        if i < ls.count { ls.remove(at: i) }; if i < vs.count { vs.remove(at: i) }
        writePairs(ls, vs)
    }
}

// MARK: - Passes

struct PassesAuthoringView: View {
    @ObservedObject var model: HeaderAuthoringModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.state == .malformed {
                    Text("Header JSON is invalid — fix it in the code editor to edit passes here.")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                if model.header.passes.isEmpty {
                    Text("No passes — this shader renders in a single pass.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.header.passes.indices, id: \.self) { i in PassRow(model: model, index: i) }
                Button { model.update { $0.passes.append(ISFPass()) } } label: { Label("Add pass", systemImage: "plus") }
                    .buttonStyle(.plain).disabled(model.state == .malformed)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PassRow: View {
    @ObservedObject var model: HeaderAuthoringModel
    let index: Int
    private var pass: ISFPass? { index < model.header.passes.count ? model.header.passes[index] : nil }

    var body: some View {
        guard pass != nil else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pass \(index)").font(.caption).bold()
                    Spacer()
                    Button { model.update { if index < $0.passes.count { $0.passes.remove(at: index) } } } label: {
                        Image(systemName: "trash").font(.caption2)
                    }.buttonStyle(.plain)
                }
                HStack {
                    Text("target").font(.caption2).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                    TextField("buffer name (blank = screen)", text: targetBinding()).textFieldStyle(.roundedBorder).font(.caption)
                }
                Toggle("Persistent (feedback buffer)", isOn: boolBinding(\.persistent)).font(.caption)
                Toggle("Float (HDR precision)", isOn: boolBinding(\.float)).font(.caption)
            }
            .padding(6).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        )
    }

    private func targetBinding() -> Binding<String> {
        Binding(
            get: { pass?.target ?? "" },
            set: { v in model.update { guard index < $0.passes.count else { return }
                $0.passes[index].target = v.isEmpty ? nil : v } })
    }
    private func boolBinding(_ kp: WritableKeyPath<ISFPass, Bool>) -> Binding<Bool> {
        Binding(
            get: { pass?[keyPath: kp] ?? false },
            set: { v in model.update { if index < $0.passes.count { $0.passes[index][keyPath: kp] = v } } })
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
