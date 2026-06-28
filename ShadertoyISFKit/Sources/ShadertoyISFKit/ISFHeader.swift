import Foundation

public enum ISFHeaderError: Error, Equatable {
    case noHeader      // no `/*{ … }*/` comment block at all
    case malformed     // a header block exists but its JSON doesn't parse
}

/// One declared ISF INPUT. `name`/`type` are promoted; every other ISF key (DEFAULT, MIN, MAX,
/// LABELS, VALUES, and any host-specific extras like IDENTITY) is preserved verbatim in `attributes`.
public struct ISFInput: Equatable {
    public var name: String
    public var type: String
    public var attributes: [String: JSONValue]

    public init(name: String, type: String, attributes: [String: JSONValue] = [:]) {
        self.name = name; self.type = type; self.attributes = attributes
    }

    init(fromObject obj: [String: Any]) {
        var rest = obj
        self.name = (rest.removeValue(forKey: "NAME") as? String) ?? ""
        self.type = (rest.removeValue(forKey: "TYPE") as? String) ?? ""
        self.attributes = rest.compactMapValues(JSONValue.init(any:))
    }

    var jsonObject: [String: Any] {
        var d = attributes.mapValues(\.jsonObject)
        d["NAME"] = name
        d["TYPE"] = type
        return d
    }

    /// A new input pre-seeded with the fields appropriate to its type, for the "+ Add input" flow.
    public static func makeDefault(type: String, name: String) -> ISFInput {
        var attrs: [String: JSONValue] = [:]
        switch type {
        case "float", "long":
            attrs["DEFAULT"] = .number(type == "long" ? 0 : 0.5)
            attrs["MIN"] = .number(0)
            attrs["MAX"] = .number(type == "long" ? 10 : 1)
        case "bool":
            attrs["DEFAULT"] = .bool(false)
        case "point2D":
            attrs["DEFAULT"] = .array([.number(0.5), .number(0.5)])
            attrs["MIN"] = .array([.number(0), .number(0)])
            attrs["MAX"] = .array([.number(1), .number(1)])
        case "color":
            attrs["DEFAULT"] = .array([.number(1), .number(1), .number(1), .number(1)])
        case "image", "event":
            break   // no default/range
        default:
            break
        }
        return ISFInput(name: name, type: type, attributes: attrs)
    }
}

/// One ISF PASS. All keys live in `attributes`; the common ones get typed accessors.
public struct ISFPass: Equatable {
    public var attributes: [String: JSONValue]

    public init(attributes: [String: JSONValue] = [:]) { self.attributes = attributes }

    init(fromObject obj: [String: Any]) {
        self.attributes = obj.compactMapValues(JSONValue.init(any:))
    }

    var jsonObject: [String: Any] { attributes.mapValues(\.jsonObject) }

    public var target: String? {
        get { if case .string(let s)? = attributes["TARGET"] { return s }; return nil }
        set { attributes["TARGET"] = newValue.map(JSONValue.string) }
    }
    public var persistent: Bool {
        get { if case .bool(let b)? = attributes["PERSISTENT"] { return b }; return false }
        set { attributes["PERSISTENT"] = .bool(newValue) }
    }
    public var float: Bool {
        get { if case .bool(let b)? = attributes["FLOAT"] { return b }; return false }
        set { attributes["FLOAT"] = .bool(newValue) }
    }
    public var width: String? {
        get { if case .string(let s)? = attributes["WIDTH"] { return s }; return nil }
        set { attributes["WIDTH"] = newValue.map(JSONValue.string) }
    }
    public var height: String? {
        get { if case .string(let s)? = attributes["HEIGHT"] { return s }; return nil }
        set { attributes["HEIGHT"] = newValue.map(JSONValue.string) }
    }
}

/// Editable, typed projection of an ISF `/*{ … }*/` header. The code text is the single source of
/// truth; this is parsed from it, mutated, and written back — never touching the GLSL body. Keys the
/// model doesn't manage (DESCRIPTION, CREDIT, CATEGORIES, ISFVSN, …) are preserved verbatim in `extra`.
public struct ISFHeader: Equatable {
    public var inputs: [ISFInput]
    public var passes: [ISFPass]
    public var extra: [String: JSONValue]

    public init(inputs: [ISFInput] = [], passes: [ISFPass] = [], extra: [String: JSONValue] = [:]) {
        self.inputs = inputs; self.passes = passes; self.extra = extra
    }

    /// A minimal header for a brand-new shader (used when inserting into headerless source).
    public static var empty: ISFHeader {
        ISFHeader(extra: ["ISFVSN": .string("2.0"), "DESCRIPTION": .string("New ISF shader")])
    }

    // MARK: locate / parse

    /// The character range of the whole `/*{ … }*/` block (delimiters included), or nil if absent.
    /// Robust to whitespace variants (`/*{`, `/* {`, `/*\n{ …`): a block comment counts as the ISF
    /// header only when its body is a JSON object. Scans forward past any leading non-header comments
    /// (e.g. a license/credit block common in shared `.fs` files) to find the real header — otherwise
    /// detection would fail and `write` would prepend a duplicate header.
    public static func blockRange(in source: String) -> Range<String.Index>? {
        var searchStart = source.startIndex
        while let open = source.range(of: "/*", range: searchStart..<source.endIndex),
              let close = source.range(of: "*/", range: open.upperBound..<source.endIndex) {
            let inner = source[open.upperBound..<close.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.hasPrefix("{"), inner.hasSuffix("}") {
                return open.lowerBound..<close.upperBound
            }
            searchStart = close.upperBound
        }
        return nil
    }

    public static func parse(_ source: String) throws -> ISFHeader {
        guard let range = blockRange(in: source) else { throw ISFHeaderError.noHeader }
        // The JSON object sits between the `/*` and `*/` delimiters of the located block.
        let block = source[range]
        let jsonStart = block.index(block.startIndex, offsetBy: 2)
        let jsonEnd = block.index(block.endIndex, offsetBy: -2)
        let inner = String(block[jsonStart..<jsonEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = inner.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ISFHeaderError.malformed
        }
        var rest = obj
        let inputsRaw = (rest.removeValue(forKey: "INPUTS") as? [[String: Any]]) ?? []
        let passesRaw = (rest.removeValue(forKey: "PASSES") as? [[String: Any]]) ?? []
        return ISFHeader(
            inputs: inputsRaw.map(ISFInput.init(fromObject:)),
            passes: passesRaw.map(ISFPass.init(fromObject:)),
            extra: rest.compactMapValues(JSONValue.init(any:)))
    }

    // MARK: serialize / write

    /// Re-emit the header as a `{ … }` JSON object (pretty-printed, sorted keys — matching
    /// `HeaderBuilder` conventions). INPUTS always present; PASSES only when non-empty.
    public func serializeHeaderJSON() -> String {
        var top: [String: Any] = extra.mapValues(\.jsonObject)
        top["INPUTS"] = inputs.map(\.jsonObject)
        if !passes.isEmpty { top["PASSES"] = passes.map(\.jsonObject) }
        guard let data = try? JSONSerialization.data(
            withJSONObject: top, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Splice this header back into `source`, replacing an existing `/*{ … }*/` block or prepending a
    /// new one. Everything outside the header block (the GLSL body) is left byte-for-byte unchanged.
    public func write(into source: String) -> String {
        let block = "/*" + serializeHeaderJSON() + "*/"
        if let range = ISFHeader.blockRange(in: source) {
            return source.replacingCharacters(in: range, with: block)
        }
        return block + "\n\n" + source
    }
}
