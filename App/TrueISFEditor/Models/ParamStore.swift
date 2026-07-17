import Foundation

/// A user-set shader input value. Name-keyed storage (not ordinal) so values survive input
/// reordering when the header is edited — the null_signal preset lesson.
enum ParamValue: Equatable {
    case float(Double)
    case bool(Bool)
    case long(Double)
    case point2D([Double])
    case color([Double])

    /// The JSON fragment `PreviewCoordinator.setInput` expects (see MetalPreviewController.setInput:
    /// bool / number / 2-array = point / 4-array = color; integer-vs-float NSNumber distinguishes
    /// long from float, so longs MUST serialize without a decimal point).
    var jsonFragment: String {
        switch self {
        case .float(let v):   return "\(v)"
        case .bool(let v):    return v ? "true" : "false"
        case .long(let v):    return "\(Int(v))"
        case .point2D(let p): return "[\(p[0]), \(p[1])]"
        case .color(let c):   return "[\(c[0]), \(c[1]), \(c[2]), \(c[3])]"
        }
    }

    /// True when both values are the same case (type drift guard for syncInputs).
    func sameKind(as other: ParamValue) -> Bool {
        switch (self, other) {
        case (.float, .float), (.bool, .bool), (.long, .long),
             (.point2D, .point2D), (.color, .color): return true
        default: return false
        }
    }
}

/// The observable model between the param UI and the render engines (Phase B keystone).
/// User-set values live here — NOT in view @State — so they can be replayed into a freshly
/// compiled scene, forwarded to multiple render sinks (inline + pop-out), diffed against
/// defaults, and (Plan 2) serialized as snapshots/presets.
@MainActor
final class ParamStore: ObservableObject {
    @Published private(set) var values: [String: ParamValue] = [:]
    private(set) var defaults: [String: ParamValue] = [:]

    /// Fired on every set/reset — the owner (EditorViewModel) forwards to the coordinators.
    var onSet: ((_ name: String, _ jsonFragment: String) -> Void)?

    func set(_ name: String, _ value: ParamValue) {
        values[name] = value
        onSet?(name, value.jsonFragment)
    }

    /// The effective value: user-set, else header default, else nil.
    func value(for name: String) -> ParamValue? {
        values[name] ?? defaults[name]
    }

    func isModified(_ name: String) -> Bool {
        guard let v = values[name] else { return false }
        return v != defaults[name]
    }

    /// Remove the user value and push the header default back to the engines.
    func resetToDefault(_ name: String) {
        values.removeValue(forKey: name)
        if let d = defaults[name] { onSet?(name, d.jsonFragment) }
    }

    /// Rebuild defaults from a freshly compiled scene's inputs. PRUNES user values whose input
    /// vanished or changed type; KEEPS survivors (values replay onto the edited shader by name).
    func syncInputs(_ inputs: [ISFPreviewInput]) {
        var newDefaults: [String: ParamValue] = [:]
        for input in inputs {
            if let d = Self.defaultValue(for: input) { newDefaults[input.name] = d }
        }
        defaults = newDefaults
        values = values.filter { name, value in
            guard let d = newDefaults[name] else { return false }
            return value.sameKind(as: d)
        }
    }

    /// Document switch: nothing carries over.
    func resetAll() {
        values = [:]
        defaults = [:]
    }

    /// Push every stored user value into the engines — called after a new scene is installed,
    /// because a fresh scene boots at header defaults regardless of what the UI shows.
    func replayAll() {
        for (name, value) in values {
            onSet?(name, value.jsonFragment)
        }
    }

    // MARK: default coercion

    /// Map an ISFPreviewInput's header default into a ParamValue (image/event inputs: none).
    static func defaultValue(for input: ISFPreviewInput) -> ParamValue? {
        switch input.type {
        case "float":
            return .float((input.defaultValue as? Double) ?? (input.min as? Double) ?? 0)
        case "bool":
            return .bool((input.defaultValue as? Bool) ?? false)
        case "long":
            return .long((input.defaultValue as? Double) ?? input.values?.first ?? 0)
        case "point2D":
            return .point2D(doubles(input.defaultValue, count: 2, fallback: [0, 0]))
        case "color":
            return .color(doubles(input.defaultValue, count: 4, fallback: [1, 1, 1, 1]))
        default:
            return nil   // image (routed via SourceRouter) / event (momentary) / unsupported
        }
    }

    /// Coerce an ISF JSON value (`[NSNumber]`/`[Any]`) into exactly `count` doubles.
    static func doubles(_ any: Any?, count: Int, fallback: [Double]) -> [Double] {
        guard let arr = any as? [Any] else { return fallback }
        let mapped = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
        return mapped.count >= count ? Array(mapped.prefix(count)) : fallback
    }
}
