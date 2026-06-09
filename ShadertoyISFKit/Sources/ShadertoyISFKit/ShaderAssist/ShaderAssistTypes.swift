import Foundation
public enum ShaderAssistTask: Sendable { case diagnoseAndFix, suggestions }
public struct AIEdit: Codable, Equatable, Sendable {
    public let fromLine: Int; public let toLine: Int; public let replacement: String; public let rationale: String
}
public struct AIFixResult: Codable, Equatable, Sendable {
    public let explanation: String; public let edits: [AIEdit]
}
public struct AIIdea: Codable, Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String; public let detail: String; public let kind: String; public let lines: [Int]?
}
public struct AISuggestionsResult: Codable, Equatable, Sendable { public let ideas: [AIIdea] }
public enum ShaderAssistParseError: Error, Equatable { case unparseable(raw: String) }
