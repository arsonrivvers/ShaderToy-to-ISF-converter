import Foundation

/// Bundled third-party attribution (Resources/ACKNOWLEDGEMENTS.md — summary + full license texts).
/// Required for binary distribution: BSD/Apache components mandate reproducing their license text.
enum Acknowledgements {
    static let text: String = {
        guard let url = Bundle.main.url(forResource: "ACKNOWLEDGEMENTS", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Acknowledgements file missing from this build — see THIRD_PARTY_LICENSES in the repository."
        }
        return content
    }()
}
