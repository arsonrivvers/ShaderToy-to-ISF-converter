import Foundation
import ShadertoyISFKit

@MainActor
final class ShaderAssistViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running(ShaderAssistTask)
        case fix(AIFixResult)
        case suggestions(AISuggestionsResult)
        case rawAnswer(String)
        case error(String)
    }
    @Published private(set) var state: State = .idle
    @Published var handledEdits: Set<Int> = []

    private let binaryOverride: () -> String?
    private var task: Task<Void, Never>?

    init(binaryOverride: @escaping () -> String?) { self.binaryOverride = binaryOverride }

    /// Map an AIEdit to a guarded P2 TextEdit, deriving expectedContains from the current source line.
    static func textEdit(from edit: AIEdit, source: String) -> TextEdit {
        let lines = source.components(separatedBy: "\n")
        let idx = edit.fromLine - 1
        let current = (idx >= 0 && idx < lines.count) ? lines[idx] : ""
        let expect = current.trimmingCharacters(in: .whitespaces)
        return TextEdit(fromLine: edit.fromLine, toLine: edit.toLine,
                        replacement: edit.replacement,
                        expectedContains: expect.isEmpty ? nil : String(expect.prefix(40)))
    }

    func run(_ t: ShaderAssistTask, source: String, diagnostics: [Diagnostic]) {
        task?.cancel(); handledEdits = []
        state = .running(t)
        let binary = ClaudeCodeRunner.locateBinary(override: binaryOverride())
        let runner = ClaudeCodeRunner(binary: binary)
        let system = ShaderAssistPrompt.system(for: t)
        let prompt = ShaderAssistPrompt.user(task: t, source: source, diagnostics: diagnostics)
        task = Task { [weak self] in
            do {
                let stdout = try await runner.run(prompt: prompt, system: system, model: "claude-sonnet-4-6")
                if Task.isCancelled { return }
                switch t {
                case .diagnoseAndFix:
                    if let r = try? ShaderAssistResponseParser.fixResult(fromClaudeStdout: stdout) { self?.state = .fix(r) }
                    else { self?.state = .rawAnswer(stdout) }
                case .suggestions:
                    if let r = try? ShaderAssistResponseParser.suggestions(fromClaudeStdout: stdout) { self?.state = .suggestions(r) }
                    else { self?.state = .rawAnswer(stdout) }
                }
            } catch let e as ClaudeRunError {
                self?.state = .error(Self.message(for: e))
            } catch { self?.state = .error("\(error)") }
        }
    }

    func cancel() { task?.cancel(); state = .idle }

    private static func message(for e: ClaudeRunError) -> String {
        switch e {
        case .binaryNotFound: return "Couldn't find the `claude` CLI. Set its path in Settings, or install Claude Code."
        case .notAuthenticated: return "Claude Code isn't signed in. Run `claude` once in Terminal to log in."
        case .timedOut: return "Claude timed out. Try again."
        case .processFailed(let m): return "Claude failed: \(m)"
        }
    }
}
