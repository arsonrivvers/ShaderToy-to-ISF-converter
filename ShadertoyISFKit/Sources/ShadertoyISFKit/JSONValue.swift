import Foundation

/// A lossless, Equatable representation of any JSON value. Used so the ISF header model can preserve
/// keys it doesn't structurally manage (and per-input attributes) verbatim across a parse → mutate →
/// re-serialize round-trip, without collapsing bools into numbers the way raw `Any` does.
public enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    /// Build from a Foundation object produced by `JSONSerialization`. Returns nil only for values
    /// JSON can't represent (which JSONSerialization never emits). Distinguishes `Bool` from numeric
    /// `NSNumber` via the CoreFoundation boolean type id — the standard JSON round-trip fix.
    public init?(any: Any) {
        switch any {
        case let v as String:
            self = .string(v)
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool(v.boolValue) }
            else { self = .number(v.doubleValue) }
        case is NSNull:
            self = .null
        case let v as [Any]:
            self = .array(v.compactMap(JSONValue.init(any:)))
        case let v as [String: Any]:
            self = .object(v.compactMapValues(JSONValue.init(any:)))
        case let v as Bool:
            self = .bool(v)
        default:
            return nil
        }
    }

    /// Convert back to a Foundation object suitable for `JSONSerialization`.
    public var jsonObject: Any {
        switch self {
        case .string(let s): return s
        case .number(let d): return d
        case .bool(let b):   return b
        case .null:          return NSNull()
        case .array(let a):  return a.map(\.jsonObject)
        case .object(let o): return o.mapValues(\.jsonObject)
        }
    }
}
