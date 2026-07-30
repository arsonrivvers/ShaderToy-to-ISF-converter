import SwiftUI

@main
struct ARShaderApp: App {
    @StateObject private var instrument = Instrument()

    var body: some Scene {
        WindowGroup("ARShader") {
            InstrumentRootView(instrument: instrument)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Task 2 placeholder root: the program output filling the window. Task 12 replaces it.
struct InstrumentRootView: View {
    @ObservedObject var instrument: Instrument
    var body: some View {
        ProgramOutputView(instrument: instrument).background(.black)
    }
}
