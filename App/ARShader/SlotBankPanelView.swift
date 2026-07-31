import SwiftUI

/// The slot bank as a rail panel. Task 7 builds the cells; this is the seam.
struct SlotBankPanelView: View {
    let instrument: Instrument

    var body: some View {
        Text("Bank").font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
