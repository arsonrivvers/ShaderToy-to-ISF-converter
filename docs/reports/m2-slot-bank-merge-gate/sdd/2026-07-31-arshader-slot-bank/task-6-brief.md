### Task 6: `PanelID.bank`

**Files:**
- Modify: `App/ARShader/SurfaceLayout.swift` (add the case, its `systemImage`, its `title`)
- Modify: `App/ARShader/InstrumentView.swift` — add a case to `panelContent` for the bank panel
- Create: `App/ARShader/SlotBankPanelView.swift` (placeholder body — Task 7 fills it)
- Test: `App/ARShaderTests/SurfaceLayoutTests.swift` (extend)

**Interfaces:**
- Produces: `PanelID.bank`, `SlotBankPanelView(instrument:)`.

**This is the deliberate test of phase 3a's central claim** that adding a tool costs one enum case. If it costs more, say so in the task report — that is a finding about the framework, not a nuisance.

- [ ] **Step 1: Write the failing test**

Add to `SurfaceLayoutTests`:

```swift
    func testTheBankIsTheThirdRailPanelAndBindsCommandOptionThree() {
        XCTAssertEqual(PanelID.allCases.count, 3, "library, settings, bank")
        XCTAssertEqual(PanelID.bank.shortcutNumber, 3,
                       "The rail's premise is that a new tool costs one case and inherits ⌘⌥N")
        XCTAssertFalse(PanelID.bank.title.isEmpty)
    }

    func testOpeningTheBankSwapsRatherThanStacking() {
        let layout = SurfaceLayout()
        layout.select(panel: .library)
        layout.select(panel: .bank)
        XCTAssertEqual(layout.openPanel, .bank, "The rail swaps one panel; it never shows two")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `type 'PanelID' has no member 'bank'`.

- [ ] **Step 3: Write minimal implementation**

In `SurfaceLayout.swift`, extend `PanelID`:
```swift
enum PanelID: String, CaseIterable, Codable, Identifiable, Sendable {
    case library, settings, bank
```
and add to both switches:
```swift
        case .bank:     return "square.grid.3x3"     // systemImage
        case .bank:     return "Bank"                // title
```

Create `App/ARShader/SlotBankPanelView.swift`:
```swift
import SwiftUI

/// The slot bank as a rail panel. Task 7 builds the cells; this is the seam.
struct SlotBankPanelView: View {
    let instrument: Instrument

    var body: some View {
        Text("Bank").font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

In `InstrumentView.swift`'s `panelContent`, add:
```swift
        case .bank:
            SlotBankPanelView(instrument: instrument)
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS. Run the FULL suite — `PanelID.allCases` grew, so anything iterating it is affected.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/SurfaceLayout.swift App/ARShader/SlotBankPanelView.swift App/ARShader/InstrumentView.swift App/ARShaderTests/SurfaceLayoutTests.swift
git commit -m "feat(3b): the bank is the third rail panel — one enum case, as advertised"
```

Expected ARShader count: **240**.

---

