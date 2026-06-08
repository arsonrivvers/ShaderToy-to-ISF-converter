import SwiftUI

struct ImportedCodeView: View {
    let code: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Imported Shadertoy").font(.headline)
            ScrollView { Text(code.isEmpty ? "—" : code)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(8) }
                .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
