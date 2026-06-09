import Foundation
import Combine
import ShadertoyISFKit

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var diagnostics: [Diagnostic] = []

    func update(converterWarnings: [ConversionWarning], compileError: String?, compileErrorLine: Int?) {
        var list = converterWarnings.map { Diagnostic($0) }
        if let err = compileError, !err.isEmpty {
            let first = err.components(separatedBy: "\n").first ?? err
            list.append(.compiler(message: first, line: compileErrorLine))
        }
        diagnostics = list.sorted { a, b in
            if a.severity != b.severity { return rank(a.severity) < rank(b.severity) }
            if a.source != b.source { return a.source == .compiler }
            return (a.line ?? Int.max) < (b.line ?? Int.max)
        }
    }

    var editorDiagnostics: [EditorDiagnostic] {
        diagnostics.compactMap { d in
            guard let line = d.line else { return nil }
            let sev = d.severity == .error ? "error" : (d.severity == .warning ? "warning" : "info")
            return EditorDiagnostic(line: line, message: d.message, severity: sev)
        }
    }

    private func rank(_ s: DiagnosticSeverity) -> Int { s == .error ? 0 : (s == .warning ? 1 : 2) }
}
