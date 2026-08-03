### Task 7R: Rows, collapse, and the resize drag

**Files:**
- Modify: `App/ARShader/SlotBank.swift` — `slotCount` 8 → 40, add `static let maxRows = 5`, `perRow = 8`
- Modify: `App/ARShader/SurfaceLayout.swift` — `Arrangement.bankRows`, `Arrangement.isBankCollapsed`, `setBankRows(_:)`, `toggleBankCollapsed()`
- Modify: `App/ARShader/SlotBankStripView.swift` — draw `bankRows × 8`, the disclosure, the drag handle, the hidden-count marker
- Modify: `App/ARShaderTests/SurfaceLayoutTests.swift`, `App/ARShaderTests/SlotBankTests.swift`

**The two invariants this task exists to protect, both tested falsifiably:**

1. **Shrinking rows must not destroy a preset.** Capture into slot 15 (row 2), `setBankRows(1)`, assert `slots[15]` is still non-nil and that `setBankRows(2)` shows it unchanged. This is structural — resize touches `Arrangement`, never `SlotBank` — so the test should be impossible to fail without someone deliberately wiring resize into the model.
2. **Show mode must not collapse the bank.** `isBankCollapsed` has no `SectionKey`, so `toggleShowMode()` cannot reach it. Assert: collapse false, enter show mode, assert still false; and assert `SectionKey.all` contains nothing bank-related. Falsifiable — adding a bank `SectionKey` turns it red.

Also: `bankRows` clamps to `1...5`; `Arrangement` round-trips both new fields through `SlotBankStore`'s sibling `SurfaceLayoutStore`; a stored `bankRows` of 0 or 99 normalises on load.

