import SwiftUI
import AppKit

/// Manages a detachable output window with its own preview controller, kept in sync with the
/// editor's current source. P1 scope: detach + resize (resolution/freeze/alpha are P4).
@MainActor
final class OutputWindowManager: ObservableObject {
    private var window: NSWindow?
    let controller = ISFPreviewController()

    /// Open (or focus) the output window and render the given source.
    func show(source: String) {
        controller.load(isf: source)
        if window == nil {
            let host = NSHostingView(rootView: OutputWindowView(controller: controller))
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "TrueISFEditor — Output"
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Push a new source if the window is open; no-op otherwise.
    func update(source: String) {
        guard window?.isVisible == true else { return }
        controller.load(isf: source)
    }

    /// Apply output dimensions to the render buffer and size the window to match (1:1) when fixed.
    func setRenderSize(width: Int?, height: Int?) {
        controller.setRenderSize(width: width, height: height)
        if let w = width, let h = height, w > 0, h > 0 {
            window?.setContentSize(NSSize(width: w, height: h))
        }
    }

    var isOpen: Bool { window?.isVisible == true }
}

private struct OutputWindowView: View {
    let controller: ISFPreviewController
    var body: some View {
        ISFPreviewView(webView: controller.webView)
            .frame(minWidth: 320, minHeight: 240)
    }
}
