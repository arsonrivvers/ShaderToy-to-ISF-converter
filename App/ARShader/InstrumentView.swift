import SwiftUI

/// One deck's strip: name, opacity (set AND effective), blend mode, and its generated controls.
///
/// A separate `View` with its own `@ObservedObject var deck` on purpose. Built inline as a
/// `func deckStrip(_:) -> some View` capturing a plain `Deck` local, the strip never observed the
/// deck at all: the loaded shader's name stayed frozen at its initial "—" while the controls right
/// below it — which DID declare @ObservedObject — updated correctly. Caught on the first live
/// capture, 2026-07-30.
struct DeckStripView: View {
    @ObservedObject var deck: Deck
    @ObservedObject var mixer: MixerState

    private var id: DeckID { deck.id }
    private var layer: LayerParams? { mixer.layers().first { $0.deck == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DECK \(id.displayName)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                if deck.isLoading { ProgressView().controlSize(.small) }
                Button("Clear") { deck.unload() }.controlSize(.small)
            }
            Text(deck.shaderName ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(deck.shaderName == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
                .help(deck.shaderName ?? "No shader loaded")

            // Both values, always — the fader the operator set AND what it is contributing.
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
                ForEach(BlendMode.allCases) { Text($0.displayName).tag($0) }
            }

            Divider()
            DeckControlsView(deck: deck)
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
    @State private var libraryTarget: DeckID = .one
    @State private var keys: BlackoutKeyMonitor?

    init(instrument: Instrument) {
        self.instrument = instrument
        self.mixer = instrument.mixer
        self.output = instrument.output
    }

    var body: some View {
        VStack(spacing: 0) {
            monitors
            Divider()
            HSplitView {
                LibraryPanelView(instrument: instrument, targetDeck: $libraryTarget)
                    .frame(minWidth: 260, idealWidth: 300)
                deckStrips
                mixerStrip.frame(width: 200)
            }
        }
        .background(Color.black)
        .onAppear {
            if keys == nil {
                let monitor = BlackoutKeyMonitor(mixer: mixer) {
                    instrument.output.toggleFullscreen()
                }
                monitor.start()
                keys = monitor
            }
        }
        .onDisappear { keys?.stop(); keys = nil }
    }

    private var monitors: some View {
        HStack(spacing: 10) {
            MonitorTile(instrument: instrument, source: .deck(.one), label: "DECK A")
            MonitorTile(instrument: instrument, source: .deck(.two), label: "DECK B")
            // PROGRAM drives the instrument clock: one tick of this view is one instrument frame.
            MonitorTile(instrument: instrument, source: .master, label: "PROGRAM",
                        drivesClock: true)
        }
        .padding(10)
        .frame(maxHeight: 260)
    }

    private var deckStrips: some View {
        HStack(spacing: 0) {
            ForEach(MixerState.layerOrder) { id in
                DeckStripView(deck: instrument.deck(id), mixer: mixer)
                if id != MixerState.layerOrder.last { Divider() }
            }
        }
        .frame(minWidth: 420)
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
            outputPicker

            Spacer()

            Button {
                mixer.toggleBlackoutLatch()
            } label: {
                Text(mixer.isBlackedOut ? "BLACKOUT ON" : "BLACKOUT")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(mixer.isBlackedOut ? .red : .gray)
            .help("⌘B latches blackout. Hold Escape for a momentary blackout.")

            Text("⌘B latch · hold ESC · ⌘⇧F output")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(10)
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
