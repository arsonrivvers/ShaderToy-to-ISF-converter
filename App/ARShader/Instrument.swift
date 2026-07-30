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

    init() {
        // The same shared device/queue the editor uses, so both apps cooperate with one GPU
        // context rather than each minting their own.
        let props = RenderProperties.global()
        self.device = props.device
        self.queue = props.renderQueue
        self.renderer = InstrumentRenderer(device: props.device, queue: props.renderQueue,
                                           mixer: mixer)
    }

    func deck(_ id: DeckID) -> Deck { renderer.deck(id) }
}
