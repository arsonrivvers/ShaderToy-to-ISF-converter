import SwiftUI
import AppKit

/// Live ISF input controls, styled after the OffspringEngine parent panels: every row is
/// label-left / monospaced-value-right with a compact full-width control below, in a LazyVStack —
/// lazy is load-bearing, not cosmetic: a plain VStack lays out ALL rows on every main-thread layout
/// pass, and with high-input shaders (80+) that starves the (also main-thread) MTKView render loop
/// and visibly stutters the preview during slider drags.
struct PreviewControlsView: View {
    @ObservedObject var coordinator: PreviewCoordinator
    @State private var floats: [String: Double] = [:]
    @State private var bools: [String: Bool] = [:]
    @State private var points: [String: [Double]] = [:]
    @State private var colors: [String: [Double]] = [:]
    @State private var longs: [String: Double] = [:]

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

    /// Label-left / live-value-right header row shared by the slider controls.
    private func labelRow(_ name: String, value: String) -> some View {
        HStack {
            Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ v: Double) -> String { String(format: "%.3g", v) }

    // MARK: float / bool

    @ViewBuilder private func floatControl(_ input: ISFPreviewInput) -> some View {
        let lo = (input.min as? Double) ?? 0, hi = (input.max as? Double) ?? 1
        let current = floats[input.name] ?? (input.defaultValue as? Double) ?? lo
        let binding = Binding<Double>(
            get: { floats[input.name] ?? (input.defaultValue as? Double) ?? lo },
            set: { floats[input.name] = $0; coordinator.setInput(input.name, "\($0)") })
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: format(current))
            Slider(value: binding, in: lo...max(hi, lo + 0.0001))
                .controlSize(.small)
        }
    }

    @ViewBuilder private func boolControl(_ input: ISFPreviewInput) -> some View {
        let binding = Binding<Bool>(
            get: { bools[input.name] ?? (input.defaultValue as? Bool ?? false) },
            set: { bools[input.name] = $0; coordinator.setInput(input.name, $0 ? "true" : "false") })
        Toggle(isOn: binding) {
            Text(input.name).font(.caption).lineLimit(1)
        }
        .toggleStyle(.switch).controlSize(.mini)
    }

    // MARK: point2D

    @ViewBuilder private func point2DControl(_ input: ISFPreviewInput) -> some View {
        let lo = doubles(input.min, fallback: [0, 0])
        let hi = doubles(input.max, fallback: [1, 1])
        let def = doubles(input.defaultValue, fallback: [lo[0], lo[1]])
        let current = points[input.name] ?? def
        VStack(alignment: .leading, spacing: 2) {
            labelRow(input.name, value: "(\(format(current[0])), \(format(current[1])))")
            ForEach(0..<2, id: \.self) { axis in
                let binding = Binding<Double>(
                    get: { (points[input.name] ?? def)[axis] },
                    set: { v in
                        var p = points[input.name] ?? def
                        p[axis] = v
                        points[input.name] = p
                        coordinator.setInput(input.name, "[\(p[0]), \(p[1])]")
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
        let def = doubles(input.defaultValue, fallback: [1, 1, 1, 1])
        let binding = Binding<Color>(
            get: {
                let c = colors[input.name] ?? def
                return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3])
            },
            set: { newColor in
                let rgba = rgbaComponents(newColor)
                colors[input.name] = rgba
                coordinator.setInput(input.name, "[\(rgba[0]), \(rgba[1]), \(rgba[2]), \(rgba[3])]")
            })
        ColorPicker(selection: binding, supportsOpacity: true) {
            Text(input.name).font(.caption).lineLimit(1)
        }
        .controlSize(.small)
    }

    // MARK: long (integer / enum)

    @ViewBuilder private func longControl(_ input: ISFPreviewInput) -> some View {
        let def = (input.defaultValue as? Double) ?? (input.values?.first ?? 0)
        let current = longs[input.name] ?? def
        if let labels = input.labels, let values = input.values,
           labels.count == values.count, !values.isEmpty {
            // Enum: a Picker over the named options, sending the underlying value.
            let binding = Binding<Double>(
                get: { longs[input.name] ?? def },
                set: { longs[input.name] = $0; coordinator.setInput(input.name, "\(Int($0))") })
            VStack(alignment: .leading, spacing: 2) {
                Text(input.name).font(.caption).lineLimit(1)
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
                get: { longs[input.name] ?? def },
                set: { v in
                    let snapped = v.rounded()
                    longs[input.name] = snapped
                    coordinator.setInput(input.name, "\(Int(snapped))")
                })
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
            // the next rendered frame consumes it (M34).
            coordinator.pulseEvent(input.name)
        } label: {
            Label(input.name, systemImage: "bolt.fill")
        }
        .controlSize(.small)
        .font(.caption)
        .help("Trigger this ISF event input")
    }

    // MARK: helpers

    /// Coerce an ISF JSON value (which arrives as `[NSNumber]`/`[Any]`) into `[Double]`.
    private func doubles(_ any: Any?, fallback: [Double]) -> [Double] {
        guard let arr = any as? [Any] else { return fallback }
        let mapped = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
        return mapped.count >= fallback.count ? mapped : fallback
    }

    /// SwiftUI `Color` → sRGB `[r,g,b,a]` doubles for the ISF color uniform.
    private func rgbaComponents(_ color: Color) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return [Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent)]
    }
}
