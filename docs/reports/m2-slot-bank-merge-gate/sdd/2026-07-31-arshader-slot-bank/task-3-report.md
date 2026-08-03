# Task 3 report: SlotBankStore

## What was implemented

- `App/ARShader/SlotBankStore.swift` — `SlotBankStore`, a `UserDefaults`-backed store that reads
  and writes the eight-slot bank as one JSON blob under key `ARShader.slotBank`. Mirrors
  `SurfaceLayoutStore`'s shape exactly, per the brief and the Task-1/2 context notes:
  - `load()` returns `Self.empty` (all-nil, `SlotBank.slotCount` entries) on any decode failure
    (absent key, corrupt data, wrong-shaped future schema), then always runs the result through
    `normalised(_:)` so the returned array is always exactly `slotCount` long.
  - `save(_:)` normalises before encoding. On an encode failure it calls `assertionFailure` (loud
    in debug, non-fatal in release) rather than silently swallowing the error the way
    `SurfaceLayoutStore.save` does — this is the deliberate divergence from the mirrored pattern,
    called out explicitly in the brief as a defect Task 3 must not repeat.
- `App/ARShaderTests/SlotBankStoreTests.swift` — the four tests from the brief, verbatim: empty
  store round-trips to an empty bank, a populated bank round-trips values and positions, corrupt
  stored data loads an empty bank rather than throwing, and a wrong-length stored bank normalises
  to `slotCount` on load.

Both files were used exactly as written in the brief — no changes needed, nothing looked wrong.

### Xcode project wiring

The `.xcodeproj` is XcodeGen-generated and entirely gitignored (`App/TrueISFEditor.xcodeproj/` in
`.gitignore`). `App/project.yml` globs whole folders for both the `ARShader` and `ARShaderTests`
targets (`path: ARShader` appears in both targets' `sources:`), so no `project.yml` edit was
needed — new files under `App/ARShader/` and `App/ARShaderTests/` are picked up automatically by
a fresh `xcodegen generate`. I made local, uncommitted edits to the already-generated
`project.pbxproj` (adding file references and Sources build-phase entries for the two new files,
mirroring exactly how `SlotBank.swift`/`SlotBankTests.swift` were wired) so `xcodebuild` would
pick the new files up without needing to run `xcodegen` in this session. Nothing here is
committed or needs to be — the pbxproj is regenerated fresh by anyone who runs `xcodegen`.

## Test command and verbatim tail output

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Tail:
```
Test Suite 'SurfaceLayoutTests' passed at 2026-07-31 12:11:36.385.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.007 (0.009) seconds
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 12:11:36.388.
	 Executed 225 tests, with 0 failures (0 unexpected) in 15.371 (15.422) seconds
Test Suite 'All tests' passed at 2026-07-31 12:11:36.389.
	 Executed 225 tests, with 0 failures (0 unexpected) in 15.371 (15.423) seconds
** TEST SUCCEEDED **
```

221 → 225, exactly as the brief specified (4 new tests, 0 failures). Re-ran the full suite again
after both mutation proofs were reverted, also green at 225/225 (see below).

Scoped run (`-only-testing:ARShaderTests/SlotBankStoreTests`) also green, 4/4:
```
Test Suite 'SlotBankStoreTests' passed at 2026-07-31 12:11:14.193.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.007 (0.008) seconds
```

## Mutation proof 1: `try!` in place of the decode guard (expected to CRASH the run)

Changed `load()` from:
```swift
guard let data = defaults.data(forKey: Self.key),
      let decoded = try? JSONDecoder().decode([Preset?].self, from: data)
else { return Self.empty }
```
to:
```swift
guard let data = defaults.data(forKey: Self.key)
else { return Self.empty }
let decoded = try! JSONDecoder().decode([Preset?].self, from: data)
```

Ran the scoped test command. **Observed:** `xcodebuild test` exited with code 65 (`** TEST
FAILED **`), and the log shows the ARShader test-host process crashing mid-test with a trap, not
a normal assertion failure:

```
ARShaderTests/SlotBankStore.swift:19: Fatal error: 'try!' expression unexpectedly raised an
error: DecodingError.dataCorrupted: Data was corrupted. Debug description: The given data was
not valid JSON.. Underlying error: Error Domain=NSCocoaErrorDomain Code=3840 "Unexpected
character 'o' in expected null value around line 1, column 2." ...
```
followed by a full crash backtrace, an interactive "Press space to interact, D to debug, or any
other key to quit (30s)..." prompt from the crash-reporter, then:
```
Restarting after unexpected exit, crash, or test timeout; summary will include totals from
previous launches.
Test Suite 'SlotBankStoreTests' passed at 2026-07-31 12:12:25.302.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
```
The crash happened inside `testCorruptStoredDataLoadsAnEmptyBankRatherThanThrowing` — confirmed
by the backtrace frame `SlotBankStoreTests.testCorruptStoredDataLoadsAnEmptyBankRatherThanThrowing()`
at `SlotBankStoreTests.swift:41`. The test-runner then restarted the host and reported 0 tests
executed in that restarted sub-run; the overall `xcodebuild test` invocation still correctly
surfaced as **TEST FAILED**. This matches the brief's prediction exactly: a trap, not a clean
assertion failure — the crash-reporter's 30-second interactive prompt did make the raw log noisy
to read, but the crash and its origin were unambiguous in the log text. Reverted the change,
re-ran the scoped suite: green, 4/4.

## Mutation proof 2: remove `normalised()` from `load()` (expected clean FAIL)

Changed `load()`'s final line from `return Self.normalised(decoded)` to `return decoded`. Ran the
scoped test command. **Observed:** clean failure, no crash:

```
SlotBankStoreTests.swift:51: error: -[ARShaderTests.SlotBankStoreTests
testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount] : XCTAssertEqual failed: ("12") is not
equal to ("8") - Loading must always yield exactly slotCount entries, whatever is on disk
Test Case '...testAStoredBankOfTheWrongLengthIsNormalisedToSlotCount]' failed (0.094 seconds).
```
The other three tests in the suite still passed in the same run. Reverted the change.

## Final state

Reverted both mutations, restoring `SlotBankStore.swift` to exactly the brief's implementation.
Re-ran the full `ARShader` suite: **225/225, 0 failures** (`** TEST SUCCEEDED **`).

Commit: `64e3a24` — "feat(3b): SlotBankStore — one blob, and it never blocks launch"
(`App/ARShader/SlotBankStore.swift`, `App/ARShaderTests/SlotBankStoreTests.swift`).

## Concerns

None on the implementation or tests — both match the brief verbatim and all gates passed. One
process note for whoever runs Task 5 or later work in this worktree: the generated `.xcodeproj`
is gitignored, and I hand-edited the already-generated `project.pbxproj` (not `project.yml`) to
wire the two new files in rather than running `xcodegen generate`. Anyone who does run
`xcodegen generate` in this worktree will regenerate a clean pbxproj that picks up
`SlotBankStore.swift`/`SlotBankStoreTests.swift` automatically via the existing folder globs in
`project.yml` (no `project.yml` change was needed or made) — so there's no drift risk, just
worth knowing the pbxproj currently on disk is a hand patch, not a fresh xcodegen output.
