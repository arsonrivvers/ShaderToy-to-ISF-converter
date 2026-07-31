import SwiftUI

/// Load-in configuration: what the instrument renders at.
///
/// Output SIZE is set once before a show, which is why it left the mixer strip. Three things
/// deliberately did NOT come with it — PREVIEW SCALE and CUE SCALE (dropped when the GPU is
/// struggling mid-set) and the OUTPUT destination picker (used when a cable is kicked, per M1
/// smoke legs 17-18). Each is reached for at a bad moment, and a panel-open gesture then is the
/// wrong cost.
struct SettingsPanelView: View {
    let instrument: Instrument
    @State private var widthField = ""
    @State private var heightField = ""

    init(instrument: Instrument) {
        self.instrument = instrument
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTINGS").font(.system(size: 12, weight: .bold, design: .monospaced))
            Divider()
            outputResolution
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: syncFields)
    }

    private var outputResolution: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("OUTPUT RES").font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                // Presets are a convenience tucked into a menu, not the vocabulary — typing a size
                // is the primary control.
                Menu {
                    ForEach(RenderSize.presets, id: \.self) { preset in
                        Button(preset.label) { apply(preset) }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Common sizes")
            }
            HStack(spacing: 4) {
                TextField("W", text: $widthField)
                    .textFieldStyle(.roundedBorder).frame(width: 62)
                    .onSubmit { commitTyped() }
                Text("×").foregroundStyle(.secondary)
                TextField("H", text: $heightField)
                    .textFieldStyle(.roundedBorder).frame(width: 62)
                    .onSubmit { commitTyped() }
                Button("Set") { commitTyped() }.controlSize(.small)
            }
            .font(.system(size: 11, design: .monospaced))
            Text(String(format: "%.1f MP", instrument.renderer.outputResolution.megapixels))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private func apply(_ size: RenderSize) {
        instrument.renderer.outputResolution = size
        syncFields()
    }

    /// A field that is empty or nonsense keeps the current value rather than snapping to a default
    /// — losing a deliberately-set output size to a stray keystroke mid-set would be worse than
    /// ignoring the edit.
    private func commitTyped() {
        let current = instrument.renderer.outputResolution
        let w = Int(widthField.trimmingCharacters(in: .whitespaces)) ?? current.width
        let h = Int(heightField.trimmingCharacters(in: .whitespaces)) ?? current.height
        apply(RenderSize(width: w, height: h))   // RenderSize clamps to safe bounds
    }

    private func syncFields() {
        let r = instrument.renderer.outputResolution
        widthField = String(r.width)
        heightField = String(r.height)
    }
}
