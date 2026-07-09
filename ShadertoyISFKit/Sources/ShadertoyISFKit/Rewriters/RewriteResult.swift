import Foundation

/// The uniform return shape for warning-carrying pipeline rewriter stages (DESLOPPIFY N1).
///
/// Convention for `ISFConverter` pipeline stages:
/// - Produces warnings → return `RewriteResult` (these exact field names).
/// - Multi-output stages (HeaderMacroExpander, CommonChannelRewriter, GLSLBodyBuilder) keep
///   their own typed result structs but use the same `warnings: [ConversionWarning]` field name.
/// - Pure String→String transforms with no possible warnings (GLSLLineContinuation.splice,
///   GLSLFunctionDedup.dedup, UniformRewriter.rewrite,
///   GLSLReservedIdentifierRewriter.rewrite) stay bare String.
/// - Detection-only checks (GLSLLint.check) return bare `[ConversionWarning]`.
public struct RewriteResult {
    public let code: String
    public let warnings: [ConversionWarning]
    public init(code: String, warnings: [ConversionWarning] = []) {
        self.code = code
        self.warnings = warnings
    }
}
