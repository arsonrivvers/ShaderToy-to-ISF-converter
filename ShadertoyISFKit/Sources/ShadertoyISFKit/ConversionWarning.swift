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

/// Builds the one-line summary for a conversion report from its warning counts. Pure logic, shared by
/// any "what happened" report (import today; ShaderAssist/remix can reuse it).
public enum ConversionReportSummary {
    public static func line(source: String, warnings: [ConversionWarning]) -> String {
        if warnings.isEmpty { return "\(source) converted cleanly." }
        let e = warnings.filter { $0.severity == .error }.count
        let w = warnings.filter { $0.severity == .warning }.count
        let rest = warnings.count - e - w
        var parts: [String] = []
        if e > 0 { parts.append("\(e) error\(e == 1 ? "" : "s")") }
        if w > 0 { parts.append("\(w) warning\(w == 1 ? "" : "s")") }
        if rest > 0 { parts.append("\(rest) note\(rest == 1 ? "" : "s")") }
        return "\(source) converted with " + parts.joined(separator: ", ") + ". Review below."
    }
}
