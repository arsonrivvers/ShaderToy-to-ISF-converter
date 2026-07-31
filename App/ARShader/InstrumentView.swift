import AppKit
import SwiftUI

/// One deck's strip: name, opacity (set AND effective), blend mode, and its generated controls.
///
/// A separate `View` with its own `@ObservedObject` on purpose. Built inline as a
/// `func deckStrip(_:) -> some View` capturing a plain `Deck` local, the strip never observed the
/// deck at all: the loaded shader's name stayed frozen at its initial "—" while the controls right
/// below it — which DID declare @ObservedObject — updated correctly. Caught on the first live
/// capture, 2026-07-30.
///
/// It observes the `ShaderUnit`, not the `Deck`: the deck is a plain container now and publishes
/// nothing. Observing the deck would reproduce that same frozen-"—" defect with a green suite.
struct DeckStripView: View {
    let id: DeckID
    @ObservedObject var unit: ShaderUnit
    @ObservedObject var mixer: MixerState
    @ObservedObject var fx: FXChain
    @ObservedObject var stats: RenderStatsModel
    @ObservedObject var library: LibraryModel
    @ObservedObject var layout: SurfaceLayout
    /// The collapsed SOURCES header prints the current route, and the ROUTER publishes route
    /// changes — `unit` does not republish when a route changes (see `SourceRoutingView`). Without
    /// this the summary freezes at whatever it read first, which is precisely the frozen-"—"
    /// defect documented at the top of this file, reintroduced one level up.
    @ObservedObject var router: SourceRouter

    init(id: DeckID, unit: ShaderUnit, mixer: MixerState, fx: FXChain, stats: RenderStatsModel,
         library: LibraryModel, layout: SurfaceLayout) {
        self.id = id
        self.unit = unit
        self.mixer = mixer
        self.fx = fx
        self.stats = stats
        self.library = library
        self.layout = layout
        self._router = ObservedObject(wrappedValue: unit.imageSources)
    }

    private var layer: LayerParams? { mixer.layers().first { $0.deck == id } }

    /// Routable image inputs, summarised for the collapsed header. A generator has none and the
    /// section is not rendered at all.
    private var sourceRows: [DeckControlModel.ControlRow] {
        DeckControlModel.rows(for: unit.inputs, reservesPrimaryInput: unit.reservesPrimaryInput)
            .filter { $0.kind == .routed || $0.kind == .chainFed }
    }

    private var sourcesSummary: String {
        // Read through the observed `router`, not `unit.imageSources`: the value is the same
        // object, but only the observed reference makes this recompute when a route changes.
        let first = sourceRows.first.map { router.source(for: $0.input.name).displayName }
        guard let first else { return "" }
        return sourceRows.count > 1 ? "\(first) +\(sourceRows.count - 1)" : first
    }

    /// Non-image controls — what ShaderControlsView actually renders.
    private var parameterCount: Int {
        DeckControlModel.rows(for: unit.inputs, reservesPrimaryInput: unit.reservesPrimaryInput)
            .filter { $0.kind != .routed && $0.kind != .chainFed }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Performance controls. These never collapse. ──
            HStack {
                Text("DECK \(id.displayName)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                if unit.isLoading { ProgressView().controlSize(.small) }
                Button("Clear") { unit.unload() }.controlSize(.small)
            }
            Text(unit.shaderName ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(unit.shaderName == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
                .help(unit.shaderName ?? "No shader loaded")

            HStack {
                Text("Opacity").font(.system(size: 11))
                Spacer()
                Text(String(format: "%.2f", layer?.userOpacity ?? 1))
                    .font(.system(size: 11, design: .monospaced))
                Text(String(format: "→ %.2f", layer?.effectiveOpacity ?? 1))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("Effective opacity after the crossfader")
            }
            Slider(value: Binding(
                get: { mixer.opacity[id] ?? 1 },
                set: { mixer.setOpacity($0, for: id) }), in: 0...1)

            Picker("Blend", selection: Binding(
                get: { mixer.blendMode[id] ?? .normal },
                set: { mixer.setBlendMode($0, for: id) })) {
                // Grouped: the W3C separable twelve, then the arithmetic / light extras.
                Section("Standard") {
                    ForEach(BlendMode.allCases.filter(\.isW3CSeparable)) {
                        Text($0.displayName).tag($0)
                    }
                }
                Section("Extended") {
                    ForEach(BlendMode.allCases.filter { !$0.isW3CSeparable }) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            // ── Configuration. These collapse. ──
            // A generator has no image inputs, so the SOURCES section is absent entirely rather
            // than present-and-empty — same rule SourceRoutingView already follows.
            if !sourceRows.isEmpty {
                Divider()
                CollapsibleSection(title: "SOURCES", summary: sourcesSummary,
                                   key: .deck(id, .sources), layout: layout) {
                    // showsHeader: false — the section supplies the title here. The FX-stage call
                    // site keeps the default and draws its own.
                    SourceRoutingView(unit: unit, library: library, showsHeader: false)
                }
            }

            Divider()
            CollapsibleSection(title: "FX", summary: "\(fx.stages.count)",
                               key: .deck(id, .fx), layout: layout) {
                FXChainView(title: "FX", chain: fx, stats: stats, library: library)
            }

            Divider()
            CollapsibleSection(title: "PARAMETERS", summary: "\(parameterCount)",
                               key: .deck(id, .parameters), layout: layout) {
                ShaderControlsView(unit: unit)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The instrument surface. Deliberately plain (spec §11): three monitors across the top, a deck
/// strip per deck, the mixer, and the library. Design comes after the operator has played with it.
struct InstrumentView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject private var mixer: MixerState
    @ObservedObject private var output: OutputWindowController
    @ObservedObject private var stats: RenderStatsModel
    @ObservedObject private var layout: SurfaceLayout
    @ObservedObject private var masterFX: FXChain
    @State private var libraryTarget: LibraryTarget = .deck(.one)
    @State private var keys: BlackoutKeyMonitor?
    @State private var renderScaleField = ""
    @State private var cueScaleField = ""
    /// Debounces `Arrangement` persistence. `panelWidth` is part of `Arrangement` and the panel
    /// resize handle writes it on every drag delta, so saving on every `onChange` would encode
    /// and hit `UserDefaults` on nearly every frame of a drag. Cancelled and replaced on each
    /// change; `flushArrangement()` cancels it and saves immediately, so a pending debounce can
    /// never be the reason the final position is lost.
    @State private var arrangementPersistTask: Task<Void, Never>?
    @State private var terminationObserver: NSObjectProtocol?

    init(instrument: Instrument) {
        self.instrument = instrument
        self.mixer = instrument.mixer
        self.output = instrument.output
        self.stats = instrument.renderStats
        self.layout = instrument.surfaceLayout
        self.masterFX = instrument.renderer.masterFX
    }

    var body: some View {
        InstrumentSurface(layout: layout) {
            panelContent
        } monitors: {
            monitors
        } strips: {
            deckStrips
        } mixer: {
            mixerStrip.frame(width: SurfaceMetrics.mixerWidth)
        }
        .background(shortcuts)
        // Single-parameter form: the project's deployment target is macOS 13, and the
        // two-parameter `onChange(of:initial:_:)` the brief specified needs macOS 14.
        //
        // Debounced, not saved on every call: see `arrangementPersistTask`'s doc comment. A
        // continuous panel-width drag fires this on nearly every frame; waiting for a short quiet
        // period coalesces that into roughly one write per drag instead of one per delta.
        .onChange(of: layout.arrangement) { new in
            arrangementPersistTask?.cancel()
            arrangementPersistTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                SurfaceLayoutStore().save(new)
            }
        }
        .onAppear {
            if keys == nil {
                let monitor = BlackoutKeyMonitor(mixer: mixer) {
                    instrument.output.toggleFullscreen()
                }
                monitor.start()
                keys = monitor
            }
            // Quitting the app (⌘Q, Dock ▸ Quit) does not reliably send this view an
            // `onDisappear` before the process exits, so the debounce above needs a second flush
            // path that isn't tied to view teardown. `willTerminateNotification` fires on the main
            // thread while the app is still alive, ahead of the actual exit.
            if terminationObserver == nil {
                terminationObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
                ) { _ in
                    // `queue: .main` guarantees this runs on the main thread; `assumeIsolated`
                    // bridges that into the `@MainActor` isolation `flushArrangement()` and
                    // `SurfaceLayout` need, with no `async` hop — a hop here could still be
                    // sitting unrun in the queue when the process actually exits, which is exactly
                    // the silent-loss case this observer exists to close.
                    MainActor.assumeIsolated { flushArrangement() }
                }
            }
        }
        .onDisappear {
            keys?.stop(); keys = nil
            if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
            terminationObserver = nil
            flushArrangement()
        }
    }

    /// Cancels any pending debounced write and saves the current arrangement synchronously.
    /// Called on view teardown and on app termination — the two points where a still-pending
    /// debounce could otherwise silently drop the last change instead of persisting it.
    private func flushArrangement() {
        arrangementPersistTask?.cancel()
        arrangementPersistTask = nil
        SurfaceLayoutStore().save(layout.arrangement)
    }

    /// Hidden buttons that exist only to carry keyboard shortcuts. `.keyboardShortcut` needs a
    /// control; these are the smallest thing that is one. Blackout stays with BlackoutKeyMonitor —
    /// it must work even when SwiftUI focus is somewhere unhelpful.
    private var shortcuts: some View {
        ZStack {
            Button("") { layout.toggleShowMode() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            // Only panels that HAVE a shortcut digit get a button. Past the ninth there is no
            // single-character key equivalent to bind, and the old `Character("\(index + 1)")`
            // trapped at launch rather than degrading — see PanelID.shortcutNumber.
            ForEach(PanelID.allCases.filter { $0.shortcutNumber != nil }) { panel in
                Button("") { layout.select(panel: panel) }
                    .keyboardShortcut(KeyEquivalent(Character("\(panel.shortcutNumber!)")),
                                      modifiers: [.command, .option])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Whichever tool the rail has open. Task 7 adds `.settings`.
    @ViewBuilder private var panelContent: some View {
        switch layout.openPanel {
        case .library:
            LibraryPanelView(instrument: instrument, target: $libraryTarget)
        case .settings:
            SettingsPanelView(instrument: instrument)
        case nil:
            EmptyView()
        }
    }

    /// A / B / PROGRAM left to right — deck, deck, then what they composite into.
    ///
    /// This strip is deliberately CONTENT-SIZED, not flexible. Each tile takes its height from the
    /// available width through its 16:9 ratio, so the strip only changes size when the WINDOW does
    /// — never when a section is collapsed below it. An earlier version of this phase made the row
    /// flexible so freed height would go to the picture; on device that meant the previews resized
    /// every time the operator opened or closed PARAMETERS, and "the windows jump around" was the
    /// first thing said about it (2026-07-31). A preview that moves when you touch an unrelated
    /// control is worse than a smaller one that stays put. Collapsing now buys less scrolling in
    /// the strips, not a bigger picture.
    private var monitors: some View {
        HStack(spacing: 10) {
            MonitorTile(instrument: instrument, source: .deck(.one), label: "DECK A")
            MonitorTile(instrument: instrument, source: .deck(.two), label: "DECK B")
            // PROGRAM drives the instrument clock: one tick of this view is one instrument frame.
            MonitorTile(instrument: instrument, source: .master, label: "PROGRAM",
                        drivesClock: true)
        }
        .padding(10)
    }

    /// `alignment: .top` — the columns hang from the top of the region, they do not float in the
    /// middle of it. With sections collapsed a centred column left a large empty band between the
    /// monitor strip and DECK A, and the three columns drifted relative to each other as their
    /// content changed height (operator, 2026-07-31). Top-aligned, a collapsed column simply gets
    /// shorter and everything above it stays put.
    private var deckStrips: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(MixerState.layerOrder) { id in
                DeckStripView(id: id, unit: instrument.deck(id).unit, mixer: mixer,
                              fx: instrument.deck(id).fx, stats: stats,
                              library: instrument.library, layout: layout)
                Divider()
            }
            masterStrip
        }
        .frame(minWidth: SurfaceMetrics.stripsMinWidth)
    }

    /// The master FX chain reads exactly like a deck chain — one mental model for both.
    private var masterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MASTER").font(.system(size: 12, weight: .bold, design: .monospaced))
            Text("Applied to the program feed, before blackout.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            CollapsibleSection(title: "MASTER FX",
                               summary: "\(masterFX.stages.count)",
                               key: .masterFX, layout: layout) {
                FXChainView(title: "MASTER FX", chain: masterFX,
                            stats: stats, library: instrument.library)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mixerStrip: some View {
        VStack(spacing: 10) {
            Text("CROSSFADER").font(.system(size: 11, weight: .bold, design: .monospaced))
            Slider(value: $mixer.crossfadePosition, in: 0...1)
            HStack {
                Text("A").font(.system(size: 11, design: .monospaced))
                Spacer()
                Text(String(format: "%.2f", mixer.crossfadePosition))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("B").font(.system(size: 11, design: .monospaced))
            }

            Divider()
            scalePickers
            Divider()
            outputPicker

            Spacer()
            statsReadout

            Button { layout.toggleShowMode() } label: {
                Text(layout.showMode ? "SHOW MODE ON" : "SHOW MODE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.bordered)
            .tint(layout.showMode ? .accentColor : .gray)
            .help("⌘⇧P collapses every section and closes the panel, so the monitors take the "
                  + "space. Press it again to restore. Touching a section while in show mode "
                  + "leaves show mode and keeps your change.")

            Button {
                mixer.toggleBlackoutLatch()
            } label: {
                // Full width and bold, but a normal control height. The 56pt slab was sized as a
                // stage-lighting hit target; in practice ⌘B and Escape are how it gets hit, and it
                // was eating room the FX chains now need (operator, 2026-07-30).
                Text(mixer.isBlackedOut ? "BLACKOUT ON" : "BLACKOUT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .tint(mixer.isBlackedOut ? .red : .gray)
            .help("⌘B latches blackout. Hold Escape for a momentary blackout.")

            Text("⌘B latch · hold ESC · ⌘⇧F output · ⌘⇧P show")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(10)
    }

    /// The two scales stay on the strip: these are what gets reached for when the GPU is
    /// struggling mid-set. Output size and destination moved to the settings panel.
    private var scalePickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            scaleField(title: "PREVIEW SCALE",
                       text: $renderScaleField,
                       current: instrument.renderer.previewScale,
                       resolved: instrument.renderer.previewScale
                           .applied(to: instrument.renderer.outputResolution),
                       caption: "rasterising",
                       help: "What live decks AND the program composite actually rasterise at. "
                           + "With output closed these panes are the only thing looking, and they "
                           + "are tiny — so dropping this is free GPU at no visible cost. While "
                           + "projecting it also softens the projected image, which is what the "
                           + "warning is for.",
                       warning: projectingUpscaled ? "PROJECTING BELOW 100%" : nil,
                       apply: { instrument.renderer.previewScale = $0 })

            scaleField(title: "CUE SCALE",
                       text: $cueScaleField,
                       current: instrument.renderer.cueRenderScale,
                       // Composed, not applied to the output: cue is a fraction of the LIVE
                       // render, so the readout has to show the product of the two scales.
                       resolved: instrument.renderer.cueRenderScale
                           .applied(to: instrument.renderer.previewScale
                               .applied(to: instrument.renderer.outputResolution)),
                       caption: "cued decks",
                       help: "What a deck rasterises at while it is NOT on program — a loaded deck "
                           + "you have faded out. This reallocates nothing and never touches the "
                           + "projected image, so it is safe to drop very low. It is also the only "
                           + "saving still available while you ARE projecting.",
                       warning: nil,
                       apply: { instrument.renderer.cueRenderScale = $0 })
        }
        .onAppear { syncResolutionFields() }
    }

    /// A typed percentage with a presets menu and the pixel size it resolves to.
    ///
    /// The resolved size is shown because softness at a low scale should be a number the operator
    /// set, not a surprise on a wall.
    private func scaleField(title: String,
                            text: Binding<String>,
                            current: RenderScale,
                            resolved: RenderSize,
                            caption: String,
                            help: String,
                            warning: String?,
                            apply: @escaping (RenderScale) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Menu {
                    ForEach(RenderScale.presets, id: \.self) { preset in
                        Button(preset.label) { apply(preset); syncResolutionFields() }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Common scales")
            }
            HStack(spacing: 4) {
                TextField("%", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        // An empty or nonsense field keeps the current value rather than snapping
                        // to a default: losing a deliberately-set scale to a stray keystroke
                        // mid-set would be worse than ignoring the edit.
                        let parsed = Int(text.wrappedValue.trimmingCharacters(in: .whitespaces))
                        apply(RenderScale(percent: parsed ?? current.percent))
                        syncResolutionFields()
                    }
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("→ \(caption) \(resolved.label)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            if let warning {
                Text(warning)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
        .help(help)
    }

    /// The scale is manual and never snaps back on its own, so the surface says when that is
    /// costing sharpness on a wall rather than only on a 340px tile.
    private var projectingUpscaled: Bool {
        OutputSharpness.isProjectingUpscaled(destination: output.destination,
                                             scale: instrument.renderer.previewScale)
    }

    private func syncResolutionFields() {
        renderScaleField = String(instrument.renderer.previewScale.percent)
        cueScaleField = String(instrument.renderer.cueRenderScale.percent)
    }

    /// Real measured numbers or nothing. An FPS figure the engine did not produce would be the
    /// same class of lie as the fabricated recorder counter.
    private var statsReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(stats.stats == nil ? Color.secondary : .green)
                    .frame(width: 5, height: 5)
                Text(stats.stats?.readoutLabel ?? "no frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(stats.stats == nil ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Measured draw cadence and the frame's GPU span — earliest start to latest end "
                  + "across the frame's buffers, so overlapping work is counted once.\n\n"
                  + "Per-element figures live on the monitor tiles themselves.")
        }
    }

    /// Output ships CLOSED; this is the deliberate operator enable.
    private var outputPicker: some View {
        let screens = ScreenInfo.current()
        return VStack(alignment: .leading, spacing: 4) {
            Text("OUTPUT").font(.system(size: 11, weight: .bold, design: .monospaced))
            Picker("", selection: Binding(
                get: { output.destination },
                set: { output.setDestination($0) })) {
                ForEach(OutputMenu.options(for: screens), id: \.self) { option in
                    Text(OutputMenu.title(for: option, screens: screens)).tag(option)
                }
            }
            .labelsHidden()
        }
    }
}
