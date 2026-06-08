public struct ISFDocument {
    public let headerJSON: String   // raw JSON object text (no comment wrapper)
    public let glslBody: String

    public init(headerJSON: String, glslBody: String) {
        self.headerJSON = headerJSON
        self.glslBody = glslBody
    }

    public var fileText: String {
        let inner = headerJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped: String
        if inner.hasPrefix("{") && inner.hasSuffix("}") {
            stripped = String(inner.dropFirst().dropLast())
        } else { stripped = inner }
        return "/*{\(stripped)}*/\n\n\(glslBody)\n"
    }
}
