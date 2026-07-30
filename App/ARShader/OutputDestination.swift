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
enum OutputDestination: Equatable, Sendable {
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
