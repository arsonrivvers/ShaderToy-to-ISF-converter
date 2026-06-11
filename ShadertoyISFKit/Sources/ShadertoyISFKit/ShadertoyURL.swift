import Foundation

/// Extracts a 6-character Shadertoy shader ID from a URL or bare ID string.
public enum ShadertoyURL {
    public static func shaderID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare ID: alphanumeric, near the canonical 6-char length (tolerant of format drift).
        if isBareID(trimmed) { return trimmed }

        // URL form: take the path component after /view/ or /embed/. Its position after /view/ makes
        // it unambiguously the ID, so we accept any reasonable alphanumeric token (no fixed length).
        guard let url = URL(string: trimmed),
              let host = url.host, host.contains("shadertoy.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let idx = parts.firstIndex(where: { $0 == "view" || $0 == "embed" }),
              idx + 1 < parts.count else { return nil }
        let candidate = parts[idx + 1]
        return isPathID(candidate) ? candidate : nil
    }

    private static func isAlnum(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber }
    }
    /// Bare typed ID: keep a length window so ordinary words aren't misread as IDs.
    private static func isBareID(_ s: String) -> Bool { (5...10).contains(s.count) && isAlnum(s) }
    /// ID extracted from a URL path: unambiguous by position, so only require alphanumeric.
    private static func isPathID(_ s: String) -> Bool { (3...16).contains(s.count) && isAlnum(s) }
}
