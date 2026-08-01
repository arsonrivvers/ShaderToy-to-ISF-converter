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
/// Until phase 3c the render scale was MANUAL by the operator's choice (2026-07-30) and never
/// changed behind your back when output opened — so you could walk on stage still rasterising at
/// a rehearsal value, and the surface had to say so out loud. Phase 3c replaced that with a hard
/// rule instead of a warning: `InstrumentRenderer.isProgramLive` pins the live chain to full size
/// the instant output opens, so the hazard this type existed to flag can no longer occur.
enum OutputSharpness {
    /// Once TRUE when the program output was live and the chain rasterised below the typed output
    /// resolution. Phase 3c made that unreachable: `InstrumentRenderer.isProgramLive` lifts
    /// PREVIEW SCALE off the whole live chain the moment output opens, so an open projector is
    /// always rasterising at full size.
    ///
    /// Kept, and kept false, deliberately. It is the assertion that the hazard is gone; a change
    /// that lets a preview control reach the projector again turns this true and fails
    /// `testProjectingAnUpscaleIsUnreachable`.
    static func isProjectingUpscaled(destination: OutputDestination, scale: RenderScale) -> Bool {
        false
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
