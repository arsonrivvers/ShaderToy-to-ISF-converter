import SwiftUI

/// Load-in configuration: what the instrument renders at.
///
/// Output SIZE is set once before a show, which is why it left the mixer strip. Three things
/// deliberately did NOT come with it — PREVIEW SCALE and CUE SCALE (dropped when the GPU is
/// struggling mid-set) and the OUTPUT destination picker (used when a cable is kicked, per M1
/// smoke legs 17-18). Each is reached for at a bad moment, and a panel-open gesture then is the
/// wrong cost.
///
/// **BLACKOUT and SHOW MODE are the deliberate exception to that rule** (operator, 2026-08-03).
/// Blackout is the most bad-moment control in the instrument, so on the rule as stated it belongs
/// in the rail — but the rule's premise is a *gesture* cost, and there is no gesture: ⌘B and
/// Escape are how it is reached, always, and they run off `BlackoutKeyMonitor`'s app-wide event
/// monitor rather than off anything rendered here. A button nobody presses was paying rail space.
/// What did NOT move is blackout STATE, which is on the PROGRAM tile — see
/// `MonitorTile.showsBlackoutBadge`. Moving the button without that would have made a cut output
/// indistinguishable from a dark shader.
struct SettingsPanelView: View {
    let instrument: Instrument
    @ObservedObject private var mixer: MixerState
    @ObservedObject private var layout: SurfaceLayout
    @State private var widthField = ""
    @State private var heightField = ""

    init(instrument: Instrument) {
        self.instrument = instrument
        self.mixer = instrument.mixer
        self.layout = instrument.surfaceLayout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTINGS").font(.system(size: 12, weight: .bold, design: .monospaced))
            Divider()
            outputResolution
            Divider()
            stageControls
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

    /// Both at `stageTarget` even though they now live behind a panel: the height floor is about
    /// hitting a control without looking, and opening a panel does not make the hand steadier.
    private var stageControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STAGE").font(.system(size: 11, weight: .bold, design: .monospaced))

            Button { layout.toggleShowMode() } label: {
                Text(layout.showMode ? "SHOW MODE ON" : "SHOW MODE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: SurfaceMetrics.stageTarget)
            }
            .buttonStyle(.bordered)
            .tint(layout.showMode ? .accentColor : .gray)
            .help("⌘⇧P collapses every section and closes the panel, so the monitors take the "
                  + "space. Press it again to restore. Touching a section while in show mode "
                  + "leaves show mode and keeps your change.")

            Button { mixer.toggleBlackoutLatch() } label: {
                Text(mixer.isBlackedOut ? "BLACKOUT ON" : "BLACKOUT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: SurfaceMetrics.stageTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(mixer.isBlackedOut ? .red : .gray)
            .help("⌘B latches blackout. Hold Escape for a momentary blackout. Both work with this "
                  + "panel closed — they do not depend on this button being on screen.")

            Text("Both are keyboard-first: ⌘B latch · hold ESC momentary · ⌘⇧P show mode. "
                 + "The keys work from anywhere, including with this panel closed.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
