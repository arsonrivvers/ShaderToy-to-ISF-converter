# Task 1: Preset — Report

## Implementation Summary

Implemented `Preset`, a value type that holds a shader URL together with the parameter values captured when it was saved:

- **File created**: `App/ARShader/Preset.swift`
- **Tests created**: `App/ARShaderTests/PresetTests.swift`
- **Conformances**: `Codable`, `Equatable`, `Identifiable`

The `Preset` struct stores:
- `id: UUID` — Unique identity for each captured preset (minted fresh on capture)
- `name: String` — Derived from shader filename at capture time
- `shaderURL: URL` — The shader asset being captured
- `snapshot: ParamSnapshot` — The dialled parameter values at capture time

The `capturing(url:snapshot:)` factory method ensures each capture mints a fresh UUID, so two captures of the same shader file produce two distinct slots that can evolve independently — the core requirement tested by `testTwoPresetsOfTheSameShaderAreDistinctThings`.

## Test Results

**Test command:**
```bash
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ARShaderTests/PresetTests
```

**Output (final 3 tests):**
```
Test Suite 'PresetTests' started at 2026-07-31 11:48:26.430.
Test Case '-[ARShaderTests.PresetTests testAPresetSurvivesAJSONRoundTripWithItsValuesIntact]' started.
Test Case '-[ARShaderTests.PresetTests testAPresetSurvivesAJSONRoundTripWithItsValuesIntact]' passed (0.001 seconds).
Test Case '-[ARShaderTests.PresetTests testCapturingNamesThePresetAfterItsShaderFile]' started.
Test Case '-[ARShaderTests.PresetTests testCapturingNamesThePresetAfterItsShaderFile]' passed (0.001 seconds).
Test Case '-[ARShaderTests.PresetTests testTwoPresetsOfTheSameShaderAreDistinctThings]' started.
Test Case '-[ARShaderTests.PresetTests testTwoPresetsOfTheSameShaderAreDistinctThings]' passed (0.000 seconds).
Test Suite 'PresetTests' passed at 2026-07-31 11:48:26.433.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 11:48:26.433.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'Selected tests' passed at 2026-07-31 11:48:26.433.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
```

## Mutation Proof

**Mutation applied**: Changed `capturing(url:snapshot:)` to return a stable UUID:
```swift
static func capturing(url: URL, snapshot: ParamSnapshot) -> Preset {
    Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
           name: url.lastPathComponent, shaderURL: url, snapshot: snapshot)
}
```

**Test failure observed** (with mutation):
```
Test Case '-[ARShaderTests.PresetTests testTwoPresetsOfTheSameShaderAreDistinctThings]' started.
/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/.worktrees/m2-slot-bank/App/ARShaderTests/PresetTests.swift:21: error: -[ARShaderTests.PresetTests testTwoPresetsOfTheSameShaderAreDistinctThings] : XCTAssertNotEqual failed: ("00000000-0000-0000-0000-000000000001") is equal to ("00000000-0000-0000-0000-000000000001") - Capturing the same shader twice with different values must produce two slots that can differ, not one identity shared between them
Test Case '-[ARShaderTests.PresetTests testTwoPresetsOfTheSameShaderAreDistinctThings]' failed (0.295 seconds).
Test Suite 'PresetTests' failed at 2026-07-31 11:47:51.422.
	 Executed 3 tests, with 1 failure (0 unexpected) in 0.296 (0.297) seconds
```

**Mutation restored**: Reverted `capturing` to mint fresh UUID per call (the correct implementation).

**Tests pass after restore**: All 3 PresetTests pass, confirming the mutation proof.

## Test Count Verification

**Expected**: 207 baseline + 3 new = 210 total  
**Observed**: 210 tests, 0 failures  
✓ Test count matches specification.

## Commit

```
commit 9f99e0c (m2-slot-bank)
Author: Conner Jones
Date:   Thu Jul 31 11:52:00 2026 -0700

    feat(3b): Preset — a shader plus the values dialled when it was captured

    - Create App/ARShader/Preset.swift with Preset struct
    - Create App/ARShaderTests/PresetTests.swift with 3 tests
    - Preset conforms to Codable, Equatable, Identifiable
    - capturing(url:snapshot:) mints fresh UUID on each call
    - All 3 tests passing; total ARShader suite: 210 tests
```

## Observations

- No issues encountered. The implementation is minimal, focused, and all tests pass.
- `ParamSnapshot` was correctly reused from `App/ISFRuntime/ParamStore.swift` (no modification needed).
- xcodegen was run once to generate the Xcode project from `App/project.yml`; the new files were picked up via directory globs.
- The mutation proof confirms the identity-minting behavior is essential and properly tested.
