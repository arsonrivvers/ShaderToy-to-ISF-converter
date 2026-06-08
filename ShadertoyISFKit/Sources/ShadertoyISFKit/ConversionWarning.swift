public struct ConversionWarning: Equatable, Sendable {
    public enum Severity: String, Sendable { case info, warning, error }
    public let severity: Severity
    public let message: String
    public let context: String   // e.g. pass name, or "" for global

    public init(severity: Severity, message: String, context: String = "") {
        self.severity = severity
        self.message = message
        self.context = context
    }
}
