import AppKit
import Carbon.HIToolbox

/// The parts of an NSEvent the mapping depends on. Split out so the mapping is a pure function and
/// testable without synthesising AppKit events.
struct KeyEventDescriptor: Equatable {
    let keyCode: UInt16
    let hasCommand: Bool
    let isDown: Bool
    let isRepeat: Bool
}

enum BlackoutAction: Equatable {
    case toggleLatch
    case beginHold
    case endHold
}

/// Global keyboard access to blackout, plus the output-window toggle.
///
/// Uses an app-wide `NSEvent` local monitor rather than a SwiftUI `.keyboardShortcut`, because the
/// panic path must not depend on what has focus or which panel is open (spec §8).
///
/// ⌘B and Escape are both un-typeable into a text field, so no focus special-casing is needed. A
/// bare letter key could not satisfy "reachable at all times": the library search field is a first
/// responder that swallows plain keystrokes, so a bare `B` would either do nothing while searching
/// or need an exception — exactly the "reachable except when…" the spec rules out.
///
/// Escape is deliberately the momentary blackout and NOT an output-window escape hatch: a panic key
/// that also closed the projector window would be a bad surprise mid-set.
@MainActor
final class BlackoutKeyMonitor {
    private let mixer: MixerState
    private let onToggleOutput: () -> Void
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    init(mixer: MixerState, onToggleOutput: @escaping () -> Void = {}) {
        self.mixer = mixer
        self.onToggleOutput = onToggleOutput
    }

    /// Pure mapping. Auto-repeat produces no action: a held ⌘B must not strobe the latch, and a
    /// held Escape must not re-trigger the hold.
    nonisolated static func action(for event: KeyEventDescriptor) -> BlackoutAction? {
        guard !event.isRepeat else { return nil }
        switch (event.keyCode, event.hasCommand, event.isDown) {
        case (UInt16(kVK_ANSI_B), true, true):   return .toggleLatch
        case (UInt16(kVK_Escape), false, true):  return .beginHold
        case (UInt16(kVK_Escape), false, false): return .endHold
        default: return nil
        }
    }

    /// ⌘⇧F toggles the program output window. Separate from the blackout mapping so the panic
    /// path stays a two-case switch.
    nonisolated static func isOutputToggle(_ event: KeyEventDescriptor, hasShift: Bool) -> Bool {
        !event.isRepeat && event.isDown && event.hasCommand && hasShift
            && event.keyCode == UInt16(kVK_ANSI_F)
    }

    func apply(_ action: BlackoutAction) {
        switch action {
        case .toggleLatch: mixer.toggleBlackoutLatch()
        case .beginHold:   mixer.beginBlackoutHold()
        case .endHold:     mixer.endBlackoutHold()
        }
    }

    func start() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event, isDown: true) ?? event
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handle(event, isDown: false) ?? event
        }
    }

    func stop() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m); keyUpMonitor = nil }
    }

    deinit {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
    }

    /// Returns nil to SWALLOW the event (we handled it), or the event to pass it on.
    private func handle(_ event: NSEvent, isDown: Bool) -> NSEvent? {
        let descriptor = KeyEventDescriptor(
            keyCode: event.keyCode,
            hasCommand: event.modifierFlags.contains(.command),
            isDown: isDown,
            isRepeat: isDown && event.isARepeat)
        if Self.isOutputToggle(descriptor, hasShift: event.modifierFlags.contains(.shift)) {
            onToggleOutput()
            return nil
        }
        guard let action = Self.action(for: descriptor) else { return event }
        apply(action)
        return nil
    }
}
