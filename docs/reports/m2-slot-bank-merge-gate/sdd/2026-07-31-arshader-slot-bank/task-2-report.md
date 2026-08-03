# Task 2: SlotBank — Report

## Implementation Summary

Implemented `SlotBank`, transcribed verbatim from the brief:

- **File created**: `App/ARShader/SlotBank.swift`
- **Tests created**: `App/ARShaderTests/SlotBankTests.swift`
- **No SwiftUI import, no `Instrument` reference** — verified by reading the final file back; the type only holds `[Preset?]` plus an `onChange` closure.

`SlotBank` is `@MainActor`, `ObservableObject`, `slotCount = 8`, backed by `@Published private(set) var slots: [Preset?]`. `capture`/`clear` mutate a single index and fire `onChange`; `recall` returns the preset only when the index is valid AND `isAvailable` (slot occupied AND its `shaderURL` still exists on disk) — an unavailable slot recalls `nil` without being cleared. Every index-taking method guards with `isValid` and no-ops (rather than trapping) on an out-of-range index.

Project registration: this repo uses XcodeGen (`App/project.yml`, `sources: - path: ARShader` / `- path: ARShaderTests`, folder-based glob). `App/TrueISFEditor.xcodeproj/` is gitignored. I initially hand-patched `project.pbxproj` to unblock a first test run, then ran `xcodegen generate` to regenerate it canonically from the folder sources — confirmed it produces the identical test result before committing. Only the two `.swift` files were staged/committed; the generated project file is not tracked.

## Test Results

**Test command:**
```bash
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests
```

**Verbatim tail:**
```
Test Suite 'SurfaceLayoutTests' passed at 2026-07-31 12:00:34.320.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.008 (0.012) seconds
Test Suite 'ARShaderTests.xctest' failed at 2026-07-31 12:00:34.320.
	 Executed 221 tests, with 1 failure (0 unexpected) in 15.961 (16.008) seconds
Test Suite 'All tests' failed at 2026-07-31 12:00:34.320.
	 Executed 221 tests, with 1 failure (0 unexpected) in 15.961 (16.009) seconds

Test session results, code coverage, and logs:
	/tmp/arshader-ddata-bank/Logs/Test/Test-ARShader-2026.07.31_12-00-14--0700.xcresult

** TEST FAILED **
```

10 of 11 `SlotBankTests` pass. The one failure is `testRecallReturnsTheCapturedValuesIntact`, and it is a defect in the brief's own test code, not in the implementation — see Concerns below.

## Mutation Proofs (all 3 mandatory, brief Step 5)

### 1. `isAvailable` returns `true` unconditionally

Applied:
```swift
func isAvailable(_ index: Int) -> Bool {
    return true
}
```
Observed (RED):
```
Test Case '-[ARShaderTests.SlotBankTests testAnEmptySlotIsNotReportedAvailable]' failed (0.111 seconds).
Test Case '-[ARShaderTests.SlotBankTests testASlotWhoseFileHasGoneIsUnavailableAndRecallsNilButStaysOccupied]' failed (0.002 seconds).
```
Both named tests failed as predicted. (A third, unnamed test — `testOutOfRangeIndicesAreIgnoredRatherThanTrapping` — also failed as a side effect, since `isAvailable(-1)` now returns `true` too; this is consistent with the mutation, not a problem with the proof.)

Restored `isAvailable` to the guarded file-existence check. Re-ran: both named tests pass (GREEN).

### 2. `recall` calls `onChange?()`

First attempt placed `onChange?()` after the `guard` (success path only) — this was masked by the same fixture bug described below, because `recall(0)` in `testRecallDoesNotNotifyBecauseItChangesNothing` never reaches the guarded body (its preset uses the non-existent default path, so `isAvailable` is already `false`). Moved the call to fire unconditionally, before the guard:
```swift
func recall(_ index: Int) -> Preset? {
    onChange?()
    guard isValid(index), isAvailable(index) else { return nil }
    return slots[index]
}
```
Observed (RED):
```
Test Case '-[ARShaderTests.SlotBankTests testRecallDoesNotNotifyBecauseItChangesNothing]' failed (0.083 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 0.083 (0.083) seconds
```
Restored `recall` to the original (no `onChange?()` call). Re-ran: test passes (GREEN):
```
Test Case '-[ARShaderTests.SlotBankTests testRecallDoesNotNotifyBecauseItChangesNothing]' passed (0.001 seconds).
```

### 3. `clear` sets `slots = Array(repeating: nil, count: Self.slotCount)`

Applied:
```swift
func clear(_ index: Int) {
    guard isValid(index) else { return }
    slots = Array(repeating: nil, count: Self.slotCount)
    onChange?()
}
```
Observed (RED):
```
Test Case '-[ARShaderTests.SlotBankTests testClearEmptiesOneSlotAndLeavesItsNeighboursAlone]' failed (0.092 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 0.092 (0.092) seconds
```
Restored `clear` to the single-index assignment. Re-ran full `SlotBankTests`: back to the baseline 10 pass / 1 fail (the known fixture bug, unaffected by this mutation) — confirming the restore was clean and complete.

## Commit

```
commit 9643f95 (m2-slot-bank)
feat(3b): SlotBank — eight slots, no view and no Instrument in sight

 2 files changed, 165 insertions(+)
 create mode 100644 App/ARShader/SlotBank.swift
 create mode 100644 App/ARShaderTests/SlotBankTests.swift
```

## Concerns

1. **`testRecallReturnsTheCapturedValuesIntact` cannot pass as the brief wrote it — this is a bug in the brief's test code, not the implementation.** The test:
   ```swift
   func testRecallReturnsTheCapturedValuesIntact() throws {
       let bank = SlotBank()
       bank.capture(preset(speed: 0.9), into: 2)
       let got = try XCTUnwrap(bank.recall(2))
       ...
   }
   ```
   uses the `preset()` helper's default path, `"/tmp/a.fs"`, which is never created anywhere — not by this test, not by any other test, not by any scheme pre-action (checked `ARShader.xcscheme`, no `PreActions`/`ShellScript` entries; grepped the whole repo for anything that writes `/tmp/a.fs`). Since `recall` correctly requires `isAvailable` (exactly the behavior `testASlotWhoseFileHasGoneIsUnavailableAndRecallsNilButStaysOccupied` demands), `recall(2)` legitimately returns `nil` and `XCTUnwrap` fails. This is deterministic, not environment-flaky — I confirmed with two independent full-suite runs, same result both times.

   The likely intended fix (I did **not** apply it, per the "use as written, report rather than silently change" instruction) is for this test to use `realFileURL()` for its fixture, exactly as the neighboring `testASlotWhoseFileExistsIsAvailable` already does:
   ```swift
   func testRecallReturnsTheCapturedValuesIntact() throws {
       let bank = SlotBank()
       bank.capture(Preset.capturing(url: try realFileURL(), snapshot: ParamSnapshot(params: ["speed": .float(0.9)])), into: 2)
       let got = try XCTUnwrap(bank.recall(2))
       XCTAssertEqual(got.snapshot.params["speed"], .float(0.9))
   }
   ```
   Left as-is in the committed file, exactly as the brief specified.

2. **The brief's own test/suite counts were off by one, independent of the bug above.** Step 4 says "Expected: PASS, 12 tests" and Step 6 says "Expected ARShader count: 222" — but `SlotBankTests.swift` as given in the brief contains exactly **11** `func test...` methods (confirmed by grep), not 12. Baseline was 210 (confirmed via Task 1's report); 210 + 11 = **221**, which is exactly what both full-suite runs produced. So the discrepancy the caller's dispatch brief warned about ("Anything else means a test was lost — investigate and report it") is fully explained: no test was lost, the brief's stated counts (12 / 222) were simply wrong by one against its own transcribed code.

3. Both concerns point at the same root file (`task-2-brief.md`) and are cheap to fix — a one-line change to the test method plus updating the two count mentions — but I left the brief and the transcribed test file untouched per instruction, for the orchestrator to decide.

---

## Fix Round 1 — coordinator ruling applied

Ruling received: Finding 1's fixture (not `recall`/`isAvailable`) was wrong. Fix applied exactly as specified — `testRecallReturnsTheCapturedValuesIntact` now builds its preset from `realFileURL()` (same pattern as `testASlotWhoseFileExistsIsAvailable`), keeping the value assertion unchanged. Nothing in `SlotBank.swift` was touched (confirmed via `git diff App/ARShader/SlotBank.swift` — empty). Finding 2 required no action; the plan's downstream counts are the coordinator's to correct.

**Covering test file** (`App/ARShaderTests/SlotBankTests.swift`, the only file changed this round):
```swift
func testRecallReturnsTheCapturedValuesIntact() throws {
    let bank = SlotBank()
    bank.capture(Preset.capturing(url: try realFileURL(),
                                  snapshot: ParamSnapshot(params: ["speed": .float(0.9)])),
                 into: 2)
    let got = try XCTUnwrap(bank.recall(2))
    XCTAssertEqual(got.snapshot.params["speed"], .float(0.9),
                   "The dialled values must survive capture and come back on recall")
}
```

### 1. Full suite, post-fix

**Command:**
```bash
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests
```

**Verbatim tail:**
```
Test Suite 'SurfaceLayoutTests' passed at 2026-07-31 12:04:19.240.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.008 (0.011) seconds
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 12:04:19.240.
	 Executed 221 tests, with 0 failures (0 unexpected) in 15.433 (15.480) seconds
Test Suite 'All tests' passed at 2026-07-31 12:04:19.241.
	 Executed 221 tests, with 0 failures (0 unexpected) in 15.433 (15.480) seconds

Test session results, code coverage, and logs:
	/tmp/arshader-ddata-bank/Logs/Test/Test-ARShader-2026.07.31_12-04-01--0700.xcresult

** TEST SUCCEEDED **
```
221 tests, 0 failures — matches the corrected expectation exactly.

### 2. Non-vacuity mutation proof for this test

Applied (`recall` returns `nil` unconditionally):
```swift
func recall(_ index: Int) -> Preset? {
    return nil
}
```
**Command:**
```bash
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests/SlotBankTests/testRecallReturnsTheCapturedValuesIntact
```
**Verbatim tail (RED):**
```
Test Case '-[ARShaderTests.SlotBankTests testRecallReturnsTheCapturedValuesIntact]' started.
/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShaderTests/SlotBankTests.swift:44: error: -[ARShaderTests.SlotBankTests testRecallReturnsTheCapturedValuesIntact] : XCTUnwrap failed: expected non-nil value of type "Preset"
Test Case '-[ARShaderTests.SlotBankTests testRecallReturnsTheCapturedValuesIntact]' failed (0.090 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 0.090 (0.090) seconds
```
Confirmed not vacuous. Restored `recall` to the original guarded implementation, re-ran the full suite: **221 tests, 0 failures** (verbatim tail identical to the block above).

### 3. Commit

```
commit <see below>
fix(3b): SlotBankTests — give the round-trip test a real fixture file

 1 file changed
```

### Remaining concerns

None. Both prior concerns are resolved: Finding 1 fixed per ruling, Finding 2 was arithmetic-only and needed no code change. Full suite is green at 221/221.
