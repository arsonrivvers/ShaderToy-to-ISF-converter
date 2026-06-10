import SwiftUI
import AppKit

struct PreviewControlsView: View {
    @ObservedObject var coordinator: PreviewCoordinator
    @State private var floats: [String: Double] = [:]
    @State private var bools: [String: Bool] = [:]
    @State private var points: [String: [Double]] = [:]
    @State private var colors: [String: [Double]] = [:]
    @State private var longs: [String: Double] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
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
                    case "image":  EmptyView()  // image inputs are routed from the preview toolbar
                    default:
                        Text("\(input.name) (\(input.type))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: float / bool

    @ViewBuilder private func floatControl(_ input: ISFPreviewInput) -> some View {
        let lo = (input.min as? Double) ?? 0, hi = (input.max as? Double) ?? 1
        let binding = Binding<Double>(
            get: { floats[input.name] ?? (input.defaultValue as? Double) ?? lo },
            set: { floats[input.name] = $0; coordinator.setInput(input.name, "\($0)") })
        VStack(alignment: .leading, spacing: 2) {
            Text(input.name).font(.caption)
            Slider(value: binding, in: lo...hi)
        }
    }

    @ViewBuilder private func boolControl(_ input: ISFPreviewInput) -> some View {
        let binding = Binding<Bool>(
            get: { bools[input.name] ?? (input.defaultValue as? Bool ?? false) },
            set: { bools[input.name] = $0; coordinator.setInput(input.name, $0 ? "true" : "false") })
        Toggle(input.name, isOn: binding).font(.caption)
    }

    // MARK: point2D

    @ViewBuilder private func point2DControl(_ input: ISFPreviewInput) -> some View {
        let lo = doubles(input.min, fallback: [0, 0])
        let hi = doubles(input.max, fallback: [1, 1])
        let def = doubles(input.defaultValue, fallback: [lo[0], lo[1]])
        VStack(alignment: .leading, spacing: 2) {
            Text("\(input.name) (point2D)").font(.caption)
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
                    Text(axis == 0 ? "x" : "y").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: binding, in: lo[axis]...max(hi[axis], lo[axis] + 0.0001))
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
        ColorPicker(input.name, selection: binding, supportsOpacity: true).font(.caption)
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
                Text(input.name).font(.caption)
                Picker("", selection: binding) {
                    ForEach(Array(zip(labels, values)), id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }.labelsHidden().pickerStyle(.menu)
            }
        } else {
            // Plain integer: a stepper over [min, max].
            let lo = Int((input.min as? Double) ?? 0)
            let hi = Int((input.max as? Double) ?? 10)
            let binding = Binding<Int>(
                get: { Int(longs[input.name] ?? def) },
                set: { longs[input.name] = Double($0); coordinator.setInput(input.name, "\($0)") })
            Stepper(value: binding, in: lo...max(hi, lo)) {
                Text("\(input.name): \(Int(current))").font(.caption)
            }
        }
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
