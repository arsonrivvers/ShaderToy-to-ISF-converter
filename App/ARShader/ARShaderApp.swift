import SwiftUI

@main
struct ARShaderApp: App {
    @StateObject private var instrument = Instrument()

    var body: some Scene {
        WindowGroup("ARShader") {
            InstrumentView(instrument: instrument)
                .frame(minWidth: SurfaceMetrics.minWindowWidth,
                       minHeight: SurfaceMetrics.minWindowHeight)
                .preferredColorScheme(.dark)
                .task { instrument.library.loadInstrumentLibraries() }
        }
    }
}
