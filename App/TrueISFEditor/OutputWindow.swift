import SwiftUI
import AppKit

/// Manages a detachable output window with its own preview controller, kept in sync with the
/// editor's current source. P1 scope: detach + resize (resolution/freeze/alpha are P4).
@MainActor
final class OutputWindowManager: ObservableObject {
    private var window: NSWindow?
    let coordinator = PreviewCoordinator(metal: MetalPreviewController(), webkit: WebKitPreviewController())

    /// D0: observable pop-out lifecycle — EditorScreen drives pop-out editing mode off this.
    @Published private(set) var isOpen = false
    private var closeObserver: NSObjectProtocol?

    /// Open (or focus) the output window and render the given source.
    func show(source: String) {
        coordinator.load(isf: source)
        if window == nil {
            let host = NSHostingView(rootView: OutputWindowView(coordinator: coordinator))
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "TrueISFEditor — Output"
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOpen = false }
            }
        }
        if TestHarness.isActive {
            // Still visible (update() gates on isVisible) but never key — a suite run must not
            // steal keyboard focus from whatever the user is doing.
            window?.orderFront(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
        isOpen = true
    }

    /// Close the pop-out programmatically (the inline "Restore Preview" affordance).
    /// willCloseNotification flips isOpen.
    func close() {
        window?.close()
    }

    deinit {
        // Block-based observers are not auto-removed (same rule as MetalPreviewController).
        if let o = closeObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// Push a new source if the window is open; no-op otherwise. Debounced — this is fed from the
    /// editor's per-keystroke onChange, and each load is a full GLSL→SPIRV→MSL transpile (the inline
    /// preview already debounces 300ms; without this the pop-out recompiled on every keystroke).
    private let updateDebouncer = Debouncer(delayNanos: 300_000_000)
    func update(source: String) {
        guard window?.isVisible == true else { return }
        updateDebouncer.call { [weak self] in self?.coordinator.load(isf: source) }
    }

    /// Apply output dimensions to the render buffer and size the window to match (1:1) when fixed.
    func setRenderSize(width: Int, height: Int, fitToWindow: Bool) {
        coordinator.setRenderSize(width: width, height: height, fitToWindow: fitToWindow)
        if !fitToWindow, width > 0, height > 0 {
            window?.setContentSize(NSSize(width: width, height: height))
        }
    }

    /// Mirror the inline preview's per-input source selections so a filter renders its input here too
    /// (camera/test-pattern/shader) instead of black.
    func syncSelections(from inlineRouter: SourceRouter) {
        coordinator.imageSources.applySelections(from: inlineRouter)
    }
}

private struct OutputWindowView: View {
    @ObservedObject var coordinator: PreviewCoordinator
    var body: some View {
        ISFPreviewView(coordinator: coordinator)
            .frame(minWidth: 320, minHeight: 240)
            .overlay(alignment: .topTrailing) {
                // No toolbar here, so the FPS readout rides as a capsule over the pixels.
                RenderStatsSlot(coordinator: coordinator)
                    .environment(\.colorScheme, .dark)   // capsule is black → keep .secondary legible in light mode
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
    }
}
