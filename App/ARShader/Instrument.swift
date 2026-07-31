import SwiftUI
import Metal
import VVMetalKit

/// Process-wide owner of the Metal context and the renderer. One instance, created at launch.
///
/// Deliberately NOT in `ARShaderApp.swift`: that file carries `@main`, which the test bundle must
/// exclude (two entry points in one binary is a duplicate-symbol error), and the tests still need
/// this type.
@MainActor
final class Instrument: ObservableObject {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let mixer = MixerState()
    let library = LibraryModel()
    let renderer: InstrumentRenderer
    /// Live FPS / GPU-ms readout. Fed from the render thread, published on main.
    let renderStats = RenderStatsModel()
    /// Per-monitor GPU cost, when metering is on. Fed from the render thread, published on main.
    let elementStats = ElementStatsModel()
    /// Panel, section and show-mode state. Restored from the last launch.
    let surfaceLayout: SurfaceLayout
    /// The slot bank, restored from the last launch, persisting itself on every write.
    let slotBank: SlotBank

    /// Fired after a load has compiled and any snapshot has been applied. Test seam only — the app
    /// has no use for it, but the compile is asynchronous and a test otherwise has nothing to await.
    var onLoadSettledForTesting: (() -> Void)?

    init() {
        self.surfaceLayout = SurfaceLayout(SurfaceLayoutStore().load())
        let bankStore = SlotBankStore()
        self.slotBank = SlotBank(slots: bankStore.load())
        // The same shared device/queue the editor uses, so both apps cooperate with one GPU
        // context rather than each minting their own.
        let props = RenderProperties.global()
        self.device = props.device
        self.queue = props.renderQueue
        self.renderer = InstrumentRenderer(device: props.device, queue: props.renderQueue,
                                           mixer: mixer)
        // Stats arrive on the render thread ~2x/sec; hop to main to publish.
        let model = renderStats
        renderer.onStats = { snapshot in
            Task { @MainActor in model.stats = snapshot }
        }
        let elements = elementStats
        renderer.onElementStats = { map in
            Task { @MainActor in elements.gpuMs = map }
        }
        self.slotBank.onChange = { [weak self] in
            guard let self else { return }
            bankStore.save(self.slotBank.slots)
        }
    }

    /// The program-output window (projector mock). Lazy so nothing AppKit-shaped is built until
    /// the operator first opens the Output menu; it ships closed either way.
    private(set) lazy var output = OutputWindowController(instrument: self)

    func deck(_ id: DeckID) -> Deck { renderer.deck(id) }

    // MARK: loading

    /// The ONE place a shader becomes loaded. Library clicks, slot recalls and (later) MIDI pads
    /// all arrive here, so the mapping from "a URL plus a target" to "replace a deck / append a
    /// stage" exists once rather than inside a view's private method.
    ///
    /// `thenApply` exists because `ShaderUnit.onCompileFinished` is a SINGLE-OWNER closure that the
    /// FX path already claims for `stageDidChangeScene()`. If the caller set it to apply a
    /// snapshot, whichever assignment ran second would silently drop the other. So this method owns
    /// the composition — and for FX targets it is also the only code that ever sees the freshly
    /// created stage, so the caller could not hook it even if the hook were free.
    func load(_ url: URL, onto target: LibraryTarget, thenApply snapshot: ParamSnapshot? = nil) {
        switch target {
        case .deck(let id):
            let unit = deck(id).unit
            attach(snapshot, to: unit, alsoRunning: nil)
            unit.load(url: url)
        case .deckFX(let id):
            append(url, to: deck(id).fx, snapshot: snapshot)
        case .masterFX:
            append(url, to: renderer.masterFX, snapshot: snapshot)
        }
    }

    private func append(_ url: URL, to chain: FXChain, snapshot: ParamSnapshot?) {
        let stage = FXStage(device: device, queue: queue, clock: renderer.clock)
        attach(snapshot, to: stage.unit, alsoRunning: { [weak chain] in chain?.stageDidChangeScene() })
        chain.append(stage)
        stage.unit.load(url: url)
    }

    /// Installs a compile handler that runs the chain's ongoing concern AND the one-shot snapshot,
    /// then CLEARS the one-shot. Without the clear, a later unrelated load onto the same unit would
    /// re-fire it and replay an old preset's values onto a shader they were never captured from.
    private func attach(_ snapshot: ParamSnapshot?, to unit: ShaderUnit,
                        alsoRunning ongoing: (() -> Void)?) {
        unit.onCompileFinished = { [weak self, weak unit] in
            ongoing?()
            if let snapshot, let unit { unit.params.applySnapshot(snapshot) }
            // One-shot: reinstall the ongoing concern alone, or nothing.
            unit?.onCompileFinished = ongoing.map { fn in { fn() } }
            self?.onLoadSettledForTesting?()
        }
    }

    /// What is on a deck right now, as a capturable preset. Nil when the deck has no file behind it.
    func currentPreset(of id: DeckID) -> Preset? {
        let unit = deck(id).unit
        guard let url = unit.sourceURL else { return nil }
        return Preset.capturing(url: url, snapshot: unit.params.exportSnapshot())
    }
}
