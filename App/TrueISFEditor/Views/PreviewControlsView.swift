import SwiftUI
import AppKit

/// Live ISF input controls, styled after the OffspringEngine parent panels: every row is
/// label-left / monospaced-value-right with a compact full-width control below, in a LazyVStack —
/// lazy is load-bearing, not cosmetic: a plain VStack lays out ALL rows on every main-thread layout
/// pass, and with high-input shaders (80+) that starves the (also main-thread) MTKView render loop
/// and visibly stutters the preview during slider drags.
///
/// B1b: values live in ParamStore (NOT view @State) so they survive recompiles, reach every render
/// sink, and can be snapshotted. The view never talks to the coordinator directly for values —
/// the store's onSet does; events go through onPulse (forwarded to all open windows).
struct PreviewControlsView: View {
    @ObservedObject var coordinator: PreviewCoordinator
    @ObservedObject var store: ParamStore
    var onPulse: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if coordinator.inputs.isEmpty {
                    Text("No adjustable inputs").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(coordinator.inputs) { input in
                    switch input.type {
                    case "float":  floatControl(input)
                    case "bool":   boolControl(input)
                    case "point2D": point2DControl(input)
                    case "color":  colorControl(input)
                    case "long":   longControl(input)
                    case "event":  eventControl(input)
                    case "image":  EmptyView()  // image inputs are routed from the preview toolbar
                    default:
                        Text("\(input.name) (\(input.type))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Label-left / live-value-right header row shared by the slider controls. Double-click resets
    /// to the header default; the tint dot marks a value off its default (null_signal affordances).
    private func labelRow(_ name: String, value: String) -> some View {
        HStack(spacing: 5) {
            if store.isModified(name) {
                Circle().fill(.tint).frame(width: 5, height: 5)
            }
            Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.resetToDefault(name) }
        .help("Double-click to reset to default")
    }

    private func format(_ v: Double) -> String { String(format: "%.3g", v) }

    // MARK: float / bool

    @ViewBuilder private func floatControl(_ input: ISFPreviewInput) -> some View {
        let lo = (input.min as? Double) ?? 0, hi = (input.max as? Double) ?? 1
        let fallback = (input.defaultValue as? Double) ?? lo
        let current: Double = {
            if case .float(let v)? = store.value(for: input.name) { return v }
            return fallback
        }()
        let binding = Binding<Double>(
            get: { if case .float(let v)? = store.value(for: input.name) { return v }
                   return fallback },
            set: { store.set(input.name, .float($0)) })
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: format(current))
            Slider(value: binding, in: lo...max(hi, lo + 0.0001))
                .controlSize(.small)
        }
    }

    @ViewBuilder private func boolControl(_ input: ISFPreviewInput) -> some View {
        let binding = Binding<Bool>(
            get: { if case .bool(let v)? = store.value(for: input.name) { return v }
                   return (input.defaultValue as? Bool) ?? false },
            set: { store.set(input.name, .bool($0)) })
        Toggle(isOn: binding) {
            HStack(spacing: 5) {
                if store.isModified(input.name) {
                    Circle().fill(.tint).frame(width: 5, height: 5)
                }
                Text(input.name).font(.caption).lineLimit(1)
            }
        }
        .toggleStyle(.switch).controlSize(.mini)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.resetToDefault(input.name) }
    }

    // MARK: point2D

    @ViewBuilder private func point2DControl(_ input: ISFPreviewInput) -> some View {
        let lo = ParamStore.doubles(input.min, count: 2, fallback: [0, 0])
        let hi = ParamStore.doubles(input.max, count: 2, fallback: [1, 1])
        let def = ParamStore.doubles(input.defaultValue, count: 2, fallback: [lo[0], lo[1]])
        let current: [Double] = {
            if case .point2D(let p)? = store.value(for: input.name) { return p }
            return def
        }()
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: "(\(format(current[0])), \(format(current[1])))")
            ForEach(0..<2, id: \.self) { axis in
                let binding = Binding<Double>(
                    get: {
                        if case .point2D(let p)? = store.value(for: input.name) { return p[axis] }
                        return def[axis]
                    },
                    set: { v in
                        var p = current
                        p[axis] = v
                        store.set(input.name, .point2D(p))
                    })
                HStack(spacing: 4) {
                    Text(axis == 0 ? "x" : "y")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    Slider(value: binding, in: lo[axis]...max(hi[axis], lo[axis] + 0.0001))
                        .controlSize(.mini)
                }
            }
        }
    }

    // MARK: color

    @ViewBuilder private func colorControl(_ input: ISFPreviewInput) -> some View {
        let def = ParamStore.doubles(input.defaultValue, count: 4, fallback: [1, 1, 1, 1])
        let binding = Binding<Color>(
            get: {
                let c: [Double] = {
                    if case .color(let v)? = store.value(for: input.name) { return v }
                    return def
                }()
                return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3])
            },
            set: { newColor in
                store.set(input.name, .color(rgbaComponents(newColor)))
            })
        ColorPicker(selection: binding, supportsOpacity: true) {
            HStack(spacing: 5) {
                if store.isModified(input.name) {
                    Circle().fill(.tint).frame(width: 5, height: 5)
                }
                Text(input.name).font(.caption).lineLimit(1)
            }
        }
        .controlSize(.small)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.resetToDefault(input.name) }
    }

    // MARK: long (integer / enum)

    @ViewBuilder private func longControl(_ input: ISFPreviewInput) -> some View {
        let def = (input.defaultValue as? Double) ?? (input.values?.first ?? 0)
        let current: Double = {
            if case .long(let v)? = store.value(for: input.name) { return v }
            return def
        }()
        if let labels = input.labels, let values = input.values,
           labels.count == values.count, !values.isEmpty {
            // Enum: a Picker over the named options, sending the underlying value.
            let binding = Binding<Double>(
                get: { current },
                set: { store.set(input.name, .long($0)) })
            VStack(alignment: .leading, spacing: 2) {
                labelRow(input.name, value: "")
                Picker("", selection: binding) {
                    ForEach(Array(zip(labels, values)), id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }.labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
        } else {
            // Plain integer: a stepped slider over [min, max] with a live value readout.
            let lo = (input.min as? Double) ?? 0
            let hi = max((input.max as? Double) ?? 10, lo + 1)
            let binding = Binding<Double>(
                get: { current },
                set: { store.set(input.name, .long($0.rounded())) })
            VStack(alignment: .leading, spacing: 2) {
                labelRow(input.name, value: "\(Int(current))")
                Slider(value: binding, in: lo...hi, step: 1)
                    .controlSize(.small)
            }
        }
    }

    // MARK: event (momentary trigger)

    @ViewBuilder private func eventControl(_ input: ISFPreviewInput) -> some View {
        Button {
            // ISF `event` inputs are true for a single frame; the engine latches the pulse until
            // the next rendered frame consumes it (M34). Forwarded to every open render window.
            onPulse(input.name)
        } label: {
            Label(input.name, systemImage: "bolt.fill")
        }
        .controlSize(.small)
        .font(.caption)
        .help("Trigger this ISF event input")
    }

    // MARK: helpers

    /// SwiftUI `Color` → sRGB `[r,g,b,a]` doubles for the ISF color uniform.
    private func rgbaComponents(_ color: Color) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return [Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent)]
    }
}
