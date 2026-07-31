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
        // Under XCTest, `Instrument()` is built many times across the suite — every ARShader test
        // that touches a deck or the library builds one — and would otherwise read AND overwrite
        // the operator's REAL slot bank in `UserDefaults.standard` on every run. Task 3 already
        // established the doctrine for this (`SlotBankStoreTests` uses a private suite so tests
        // never clobber the real bank); this applies the same isolation one level up, to every
        // `Instrument()` built under the harness, not just this file's own tests. Chose a fresh
        // volatile suite per instance (isolates BOTH load and save) over merely skipping the
        // `onChange` hook below: skipping only the write would still `bankStore.load()` the real
        // bank into a test instrument's initial state, which is exactly the nondeterminism this is
        // meant to remove.
        let bankStore: SlotBankStore
        if TestHarness.isActive {
            let suiteName = "ARShader.Instrument.testHarness.\(UUID().uuidString)"
            bankStore = SlotBankStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        } else {
            bankStore = SlotBankStore()
        }
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

    /// Installs a compile handler that applies the one-shot snapshot (success only — see below),
    /// then runs the chain's ongoing concern, then CLEARS the one-shot. If it were never cleared,
    /// a later load that bypassed `Instrument.load` entirely (calling `ShaderUnit.load` directly —
    /// a future MIDI reload, an edit-and-recompile path) would re-fire this closure and replay a
    /// retired preset's values onto a shader they were never captured from; no current production
    /// path can actually reach that, since `load` always calls `attach` fresh before every compile
    /// and every FX load mints a brand-new unit, but the clear makes it true unconditionally rather
    /// than by accident of today's call graph.
    private func attach(_ snapshot: ParamSnapshot?, to unit: ShaderUnit,
                        alsoRunning ongoing: (() -> Void)?) {
        unit.onCompileFinished = { [weak self, weak unit] in
            // `onCompileFinished` fires on ALL THREE outcomes (unreadable file, compile failure,
            // success) but `compileError` is nil'd ONLY on success (ShaderUnit.swift). On a
            // failure the previous shader is deliberately left playing — compile-first-swap-on-
            // success — so applying a snapshot here would mutate the shader that is still up:
            // `applySnapshot` REPLACES `values` wholesale, destroying its live dialled values.
            if let snapshot, let unit, unit.compileError == nil { unit.params.applySnapshot(snapshot) }
            // Apply the snapshot before the ongoing concern (not after): otherwise a fresh FX stage
            // would enter the render mirror at header defaults for one turn, then jump to the
            // preset's values a moment later.
            ongoing?()
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
