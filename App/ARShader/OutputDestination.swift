import AppKit

/// A value model of an `NSScreen`, so placement logic is testable without hardware. Screens are
/// identified by their `NSScreenNumber`, which is stable across a plug/unplug of the same display.
struct ScreenInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let frame: CGRect
    let isMain: Bool

    init(id: String, name: String, frame: CGRect, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isMain = isMain
    }

    @MainActor
    init(screen: NSScreen) {
        let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.id = number.map { "\($0.uint32Value)" } ?? screen.localizedName
        self.name = screen.localizedName
        self.frame = screen.frame
        self.isMain = screen == NSScreen.main
    }

    @MainActor
    static func current() -> [ScreenInfo] { NSScreen.screens.map(ScreenInfo.init(screen:)) }
}

/// Where the operator has asked the program feed to go.
enum OutputDestination: Equatable, Hashable, Sendable {
    case off
    case floating
    case screen(id: String)

    /// Nothing is projected until the operator deliberately opens it — the same doctrine as the
    /// TouchDesigner build's ships-off servers.
    static let launchDefault: OutputDestination = .off
}

/// Resolves a request against the screens that actually exist right now.
enum OutputPlacement {
    enum Resolved: Equatable {
        case closed
        case floating(on: ScreenInfo)
        case fullscreen(on: ScreenInfo)
    }

    static func resolve(_ requested: OutputDestination, screens: [ScreenInfo]) -> Resolved {
        guard let main = screens.first(where: \.isMain) ?? screens.first else { return .closed }
        switch requested {
        case .off:
            return .closed
        case .floating:
            return .floating(on: main)
        case .screen(let id):
            guard let target = screens.first(where: { $0.id == id }) else {
                // Unplugged mid-set. Fall back to a floating window rather than vanishing
                // (output lost with no signal) or staying on a screen that no longer exists.
                return .floating(on: main)
            }
            return .fullscreen(on: target)
        }
    }
}

/// Whether what reaches the projector is being upscaled.
///
/// The render scale is MANUAL by the operator's choice (2026-07-30): it never changes behind your
/// back when output opens. The cost of that choice is that you can walk on stage still rasterising
/// at the value you set during rehearsal, so the surface has to say so out loud.
enum OutputSharpness {
    /// True when the program output is live AND the chain rasterises below the typed output
    /// resolution — the projected image is an upscale.
    ///
    /// While output is CLOSED this is always false, however low the scale: nothing needs full
    /// resolution when the only consumers are ~340px monitor tiles, so a low scale there is pure
    /// saving with no image cost at all.
    static func isProjectingUpscaled(destination: OutputDestination, scale: RenderScale) -> Bool {
        destination != .off && scale.percent < RenderScale.maxPercent
    }
}

enum OutputMenu {
    static func options(for screens: [ScreenInfo]) -> [OutputDestination] {
        [.off, .floating] + screens.map { .screen(id: $0.id) }
    }

    static func title(for destination: OutputDestination, screens: [ScreenInfo]) -> String {
        switch destination {
        case .off:      return "Off"
        case .floating: return "Floating Window"
        case .screen(let id):
            return screens.first(where: { $0.id == id })?.name ?? "Display \(id) (disconnected)"
        }
    }
}
