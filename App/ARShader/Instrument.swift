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

    init() {
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
    }

    /// The program-output window (projector mock). Lazy so nothing AppKit-shaped is built until
    /// the operator first opens the Output menu; it ships closed either way.
    private(set) lazy var output = OutputWindowController(instrument: self)

    func deck(_ id: DeckID) -> Deck { renderer.deck(id) }
}
