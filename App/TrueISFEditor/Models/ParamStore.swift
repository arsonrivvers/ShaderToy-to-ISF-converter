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

// MARK: - snapshot codec (D1)

extension ParamValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case float, bool, long, point2D, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .float: self = .float(try c.decode(Double.self, forKey: .value))
        case .bool:  self = .bool(try c.decode(Bool.self, forKey: .value))
        case .long:  self = .long(try c.decode(Double.self, forKey: .value))
        case .point2D:
            let arr = try c.decode([Double].self, forKey: .value)
            guard arr.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c,
                                                       debugDescription: "point2D needs 2 components")
            }
            self = .point2D(arr)
        case .color:
            let arr = try c.decode([Double].self, forKey: .value)
            guard arr.count == 4 else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c,
                                                       debugDescription: "color needs 4 components")
            }
            self = .color(arr)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .float(let v):   try c.encode(Kind.float, forKey: .type); try c.encode(v, forKey: .value)
        case .bool(let v):    try c.encode(Kind.bool, forKey: .type); try c.encode(v, forKey: .value)
        case .long(let v):    try c.encode(Kind.long, forKey: .type); try c.encode(v, forKey: .value)
        case .point2D(let v): try c.encode(Kind.point2D, forKey: .type); try c.encode(v, forKey: .value)
        case .color(let v):   try c.encode(Kind.color, forKey: .type); try c.encode(v, forKey: .value)
        }
    }
}

/// Versioned param snapshot (null_signal preset-codec doctrine: versioned flat JSON keyed by
/// input NAME; corrupt entries are skipped on decode, never fatal; runtime state — window
/// geometry, transport — stays OUT of param snapshots).
struct ParamSnapshot: Equatable {
    var version: Int = 1
    var params: [String: ParamValue]
}

extension ParamSnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case version, params }

    /// Swallows one corrupt entry instead of failing the whole snapshot decode.
    private struct FailableParamValue: Codable {
        let value: ParamValue?
        init(value: ParamValue?) { self.value = value }
        init(from decoder: Decoder) throws { value = try? ParamValue(from: decoder) }
        func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let raw = try c.decodeIfPresent([String: FailableParamValue].self, forKey: .params) ?? [:]
        params = raw.compactMapValues(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(params.mapValues { FailableParamValue(value: $0) }, forKey: .params)
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
    /// Per-input numeric ranges from the live header (float/long: 1 element; point2D: 2).
    /// Captured by syncInputs so applySnapshot can clamp stale snapshot values (D1 doctrine).
    private(set) var bounds: [String: (lo: [Double], hi: [Double])] = [:]

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
        var newBounds: [String: (lo: [Double], hi: [Double])] = [:]
        for input in inputs {
            if let d = Self.defaultValue(for: input) { newDefaults[input.name] = d }
            switch input.type {
            case "float", "long":
                if let lo = input.min as? Double, let hi = input.max as? Double, hi > lo {
                    newBounds[input.name] = ([lo], [hi])
                }
            case "point2D":
                let lo = Self.doubles(input.min, count: 2, fallback: [])
                let hi = Self.doubles(input.max, count: 2, fallback: [])
                if lo.count == 2, hi.count == 2 { newBounds[input.name] = (lo, hi) }
            default:
                break
            }
        }
        defaults = newDefaults
        bounds = newBounds
        values = values.filter { name, value in
            guard let d = newDefaults[name] else { return false }
            return value.sameKind(as: d)
        }
    }

    /// Document switch: nothing carries over.
    func resetAll() {
        values = [:]
        defaults = [:]
        bounds = [:]
    }

    /// Push every stored user value into the engines — called after a new scene is installed,
    /// because a fresh scene boots at header defaults regardless of what the UI shows.
    func replayAll() {
        for (name, value) in values {
            onSet?(name, value.jsonFragment)
        }
    }

    // MARK: snapshots (D1)

    /// User-set values only — defaults are derived from the header, not stored.
    func exportSnapshot() -> ParamSnapshot {
        ParamSnapshot(params: values)
    }

    /// Replace user values from a snapshot — the null_signal apply doctrine: per-entry
    /// validate-and-clamp, never fatal. Type-drifted entries (known input, wrong kind) are
    /// skipped; surviving numeric values clamp to the LIVE header range (a snapshot captured
    /// under an older, wider range must not replay out-of-range into the engine); unknown
    /// names are kept as-is (the next syncInputs prunes them). Everything surviving replays
    /// into the render sinks.
    func applySnapshot(_ snapshot: ParamSnapshot) {
        var applied: [String: ParamValue] = [:]
        for (name, value) in snapshot.params {
            if let d = defaults[name] {
                guard value.sameKind(as: d) else { continue }
                applied[name] = clamped(value, name: name)
            } else {
                applied[name] = value
            }
        }
        values = applied
        replayAll()
    }

    /// Clamp a value to the live header range. Colors clamp per-component to [0, 1]; inputs
    /// without declared bounds pass through; bools have nothing to clamp.
    private func clamped(_ value: ParamValue, name: String) -> ParamValue {
        switch value {
        case .color(let c):
            return .color(c.map { min(max($0, 0), 1) })
        case .float(let v):
            guard let b = bounds[name] else { return value }
            return .float(min(max(v, b.lo[0]), b.hi[0]))
        case .long(let v):
            guard let b = bounds[name] else { return value }
            return .long(min(max(v, b.lo[0]), b.hi[0]))
        case .point2D(let p):
            guard let b = bounds[name], p.count == 2 else { return value }
            return .point2D([min(max(p[0], b.lo[0]), b.hi[0]),
                             min(max(p[1], b.lo[1]), b.hi[1])])
        case .bool:
            return value
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
