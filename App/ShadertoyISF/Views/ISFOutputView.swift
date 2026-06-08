import SwiftUI

struct ISFOutputView: View {
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ISF Output (.fs)").font(.headline)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
