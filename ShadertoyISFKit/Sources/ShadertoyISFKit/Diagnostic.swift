import Foundation

public enum DiagnosticSeverity: String, Sendable, Equatable { case error, warning, info }
public enum DiagnosticSource: String, Sendable, Equatable { case converter, compiler }

public struct Diagnostic: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let line: Int?
    public let severity: DiagnosticSeverity
    public let message: String
    public let source: DiagnosticSource
    public let code: String?

    public init(id: UUID = UUID(), line: Int? = nil, severity: DiagnosticSeverity,
                message: String, source: DiagnosticSource, code: String? = nil) {
        self.id = id; self.line = line; self.severity = severity
        self.message = message; self.source = source; self.code = code
    }

    public init(_ w: ConversionWarning) {
        let sev: DiagnosticSeverity = w.severity == .error ? .error : (w.severity == .warning ? .warning : .info)
        self.init(line: nil, severity: sev,
                  message: w.context.isEmpty ? w.message : "\(w.message) (\(w.context))",
                  source: .converter, code: nil)
    }

    public static func compiler(message: String, line: Int?) -> Diagnostic {
        Diagnostic(line: line, severity: .error, message: message, source: .compiler, code: nil)
    }

    public static func == (l: Diagnostic, r: Diagnostic) -> Bool {
        l.line == r.line && l.severity == r.severity && l.message == r.message && l.source == r.source
    }
}
