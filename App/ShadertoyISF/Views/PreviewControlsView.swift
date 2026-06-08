import SwiftUI

struct PreviewControlsView: View {
    @ObservedObject var controller: ISFPreviewController
    @State private var floats: [String: Double] = [:]
    @State private var bools: [String: Bool] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if controller.inputs.isEmpty {
                    Text("No adjustable inputs").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(controller.inputs) { input in
                    switch input.type {
                    case "float":
                        let lo = (input.min as? Double) ?? 0, hi = (input.max as? Double) ?? 1
                        let binding = Binding<Double>(
                            get: { floats[input.name] ?? (input.defaultValue as? Double) ?? lo },
                            set: { floats[input.name] = $0; controller.setInput(input.name, "\($0)") })
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.name).font(.caption)
                            Slider(value: binding, in: lo...hi)
                        }
                    case "bool":
                        let binding = Binding<Bool>(
                            get: { bools[input.name] ?? (input.defaultValue as? Bool ?? false) },
                            set: { bools[input.name] = $0; controller.setInput(input.name, $0 ? "true" : "false") })
                        Toggle(input.name, isOn: binding).font(.caption)
                    default:
                        Text("\(input.name) (\(input.type))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
