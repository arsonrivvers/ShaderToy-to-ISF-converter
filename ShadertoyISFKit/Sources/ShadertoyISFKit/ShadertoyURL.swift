import Foundation

/// Extracts a 6-character Shadertoy shader ID from a URL or bare ID string.
public enum ShadertoyURL {
    public static func shaderID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare ID: exactly 6 alphanumerics.
        if isID(trimmed) { return trimmed }

        // URL form: take the path component after /view/ or /embed/.
        guard let url = URL(string: trimmed),
              let host = url.host, host.contains("shadertoy.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let idx = parts.firstIndex(where: { $0 == "view" || $0 == "embed" }),
              idx + 1 < parts.count else { return nil }
        let candidate = parts[idx + 1]
        return isID(candidate) ? candidate : nil
    }

    private static func isID(_ s: String) -> Bool {
        s.count == 6 && s.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
