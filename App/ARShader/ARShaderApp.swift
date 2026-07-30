import SwiftUI

@main
struct ARShaderApp: App {
    @StateObject private var instrument = Instrument()

    var body: some Scene {
        WindowGroup("ARShader") {
            InstrumentView(instrument: instrument)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
                .task { instrument.library.loadInstrumentLibraries() }
        }
    }
}
