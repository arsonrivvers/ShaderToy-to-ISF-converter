import SwiftUI

/// Opens the Remix Studio window from a menu command. Mirrors CrashLogMenuButton — a view is used
/// (rather than a bare command closure) so it can read `\.openWindow` from the environment.
struct RemixMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Remix ISF…") { openWindow(id: "remix-studio") }
            .keyboardShortcut("r", modifiers: [.command, .shift])
    }
}
