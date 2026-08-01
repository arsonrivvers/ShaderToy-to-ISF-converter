import AppKit

/// Owns the program-output window: a borderless window covering a chosen screen (the projector
/// mock), or a resizable floating window when no second display is available.
///
/// Deliberately NOT macOS native fullscreen: that animates into its own Space, is slow to enter and
/// leave, and fights ⌘-tab. A borderless window at `screen.frame` is what a projector feed wants
/// and what every VJ host does.
///
/// The window presents `renderer.programTexture()`, so blackout covers it with no second gate —
/// the texture is withdrawn and `TexturePresentingView` renders opaque black on nil.
@MainActor
final class OutputWindowController: NSObject, ObservableObject {
    private unowned let instrument: Instrument
    private var window: NSWindow?
    private var view: TexturePresentingView?
    private var screenObserver: NSObjectProtocol?

    @Published private(set) var destination: OutputDestination = .launchDefault

    var isOpen: Bool { window?.isVisible == true }

    init(instrument: Instrument) {
        self.instrument = instrument
        super.init()
        // Watch for plug/unplug so an output on a vanished screen falls back rather than stranding.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDestination() }
        }
    }

    deinit {
        // Block-based observers are not auto-removed.
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func setDestination(_ destination: OutputDestination) {
        self.destination = destination
        // The renderer has no knowledge of OutputDestination and must not gain any — it needs one
        // bit, not a concept. Setting it here rather than in applyDestination's branches keeps it
        // beside the published value it mirrors, so the two can never disagree.
        instrument.renderer.isProgramLive = destination != .off
        applyDestination()
    }

    /// ⌘⇧F: closed → the first non-main screen if there is one, else floating; open → closed.
    func toggleFullscreen() {
        if destination == .off {
            let screens = ScreenInfo.current()
            let external = screens.first(where: { !$0.isMain })
            setDestination(external.map { .screen(id: $0.id) } ?? .floating)
        } else {
            setDestination(.off)
        }
    }

    private func applyDestination() {
        switch OutputPlacement.resolve(destination, screens: ScreenInfo.current()) {
        case .closed:
            closeWindow()
        case .floating(let screen):
            showWindow(on: screen, fullscreen: false)
        case .fullscreen(let screen):
            showWindow(on: screen, fullscreen: true)
        }
    }

    private func showWindow(on screen: ScreenInfo, fullscreen: Bool) {
        let content = view ?? makeView()
        let frame: NSRect = fullscreen
            ? screen.frame
            : NSRect(x: screen.frame.midX - 480, y: screen.frame.midY - 270,
                     width: 960, height: 540)

        // Switching between borderless and titled needs a new style mask; rebuild rather than
        // mutate, which AppKit handles poorly on a visible window.
        if let w = window, w.styleMask.contains(.borderless) != fullscreen {
            w.orderOut(nil)
            window = nil
        }

        if window == nil {
            let w = NSWindow(contentRect: frame,
                             styleMask: fullscreen ? [.borderless]
                                                   : [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.title = "ARShader — Output"
            window = w
        }

        guard let w = window else { return }
        w.contentView = content
        w.setFrame(frame, display: true)
        if fullscreen {
            // Above normal windows so the control surface cannot land on top of the projector
            // feed, but below the screen-saver and alert levels.
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
            w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
            w.hidesOnDeactivate = false
        } else {
            w.level = .normal
            w.collectionBehavior = [.fullScreenAuxiliary]
        }
        // orderFront, never makeKey: the operator keeps keyboard focus on the control surface, so
        // blackout and the deck controls keep working while the projector is live.
        w.orderFront(nil)
        if fullscreen { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    private func closeWindow() {
        if let view { instrument.renderer.unregisterMonitor(view) }
        view = nil
        window?.orderOut(nil)
        window = nil
    }

    private func makeView() -> TexturePresentingView {
        let v = TexturePresentingView(device: instrument.device, queue: instrument.queue)
        v.isPaused = true               // the instrument's clock drives it
        v.enableSetNeedsDisplay = false
        let renderer = instrument.renderer
        v.sourceTexture = { renderer.programTexture() }   // nil while blacked out ⇒ black
        renderer.registerMonitor(v)
        view = v
        return v
    }
}
