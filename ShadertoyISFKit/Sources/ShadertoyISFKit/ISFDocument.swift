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
        } else {
            stripped = inner
        }
        // ISF embeds JSON inside a block comment. JSON's escaped slash decodes identically but
        // prevents metadata from closing the wrapper early. Already-safe `*\/` has no literal
        // `*/`, so this is idempotent.
        let commentSafe = stripped.replacingOccurrences(of: "*/", with: #"*\/"#)
        return "/*{\(commentSafe)}*/\n\n\(glslBody)\n"
    }
}
