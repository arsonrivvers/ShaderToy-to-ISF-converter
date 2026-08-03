# Fast-fail hardening: `testSteadyStateAllocatesNoNewTextures`

2026-08-02, worktree `m2-slot-bank`, FIX_BASE `e318f0a`.

## What changed

`App/ARShaderTests/InstrumentRendererTests.swift:114-165` — rewrote the body of
`testSteadyStateAllocatesNoNewTextures` (previously lines 114-123).

- The 31-frame `renderer.renderFrame()` loop now runs on
  `DispatchQueue.global(qos: .userInitiated)`.
- The test thread waits on an `XCTestExpectation` with `wait(for: [done], timeout: 30)` — the
  same house idiom already used in `BlackoutTests`, `FXChainTests`, `DeckTests`, etc.
- On timeout, `first`/`last` stay `nil` and the test `XCTFail`s with a message naming the known
  intermittent hang, the observed failure shape (2/7 runs, SIGTERM after ~195-518s), and that the
  rest of the suite is healthy (326/326 in ~25s with this test skipped) — a pointer for whoever
  picks up root-causing later.
- The original assertion is preserved exactly: `XCTAssertTrue(first === last, ...)` — same pooled
  master-texture check, same message.
- Added a doc comment above the test explaining the shape, why `executionTimeAllowance` was
  rejected (no test-timeout key in `ARShader.xcscheme`), and why running the loop off-thread is
  consistent with production rather than a compromise: `InstrumentRenderer` is deliberately not
  `@MainActor` (doc comment at `InstrumentRenderer.swift:83`) because `renderFrame()` is driven
  from the CVDisplayLink thread, is `@unchecked Sendable` with one coarse `NSLock` guarding every
  render-thread-touched field, and `rawMasterTexture()` takes that same lock
  (`InstrumentRenderer.swift:385-388`). Its dependency `MixerState.renderLayers()` /
  `isBlackedOutForRender()` are themselves `nonisolated` for the identical reason
  (`MixerState.swift:113,119`, with `nonisolated(unsafe)` backing fields at lines 48-49) — so a
  test calling `renderFrame()` from a background queue is exercising the exact threading contract
  production already relies on, not inventing a new one.

## Mutation proof (RED)

Temporarily inserted `Thread.sleep(forTimeInterval: 60)` inside the loop body before each
`renderFrame()` call, then ran:

```
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader -destination 'platform=macOS' \
  -derivedDataPath /tmp/arshader-ddata-bank test-without-building \
  -only-testing:ARShaderTests/InstrumentRendererTests/testSteadyStateAllocatesNoNewTextures
```

Result — failed at **30.128 seconds**, not a multi-minute stall:

```
InstrumentRendererTests.swift:151: error: -[ARShaderTests.InstrumentRendererTests
testSteadyStateAllocatesNoNewTextures] : Asynchronous wait failed: Exceeded timeout of 30 seconds,
with unfulfilled expectations: "31-frame steady-state render loop completed".
InstrumentRendererTests.swift:154: error: -[ARShaderTests.InstrumentRendererTests
testSteadyStateAllocatesNoNewTextures] : failed - The steady-state render loop did not complete
within 30s. This is the known intermittent full-suite hang on
testSteadyStateAllocatesNoNewTextures (observed 2/7 runs, SIGTERM after ~195-518s) — the rest of
the suite is otherwise healthy (326/326 in ~25s with this test skipped). Root cause is not fixed
here; see the doc comment on this test for what has already been ruled out.
Test Case '-[ARShaderTests.InstrumentRendererTests testSteadyStateAllocatesNoNewTextures]' failed
(30.128 seconds).
```

Total wall-clock for the `xcodebuild` invocation: 39s (30.1s test + startup/teardown overhead).

Reverted the mutation, rebuilt, reran the same single-test invocation:

```
Test Case '-[ARShaderTests.InstrumentRendererTests testSteadyStateAllocatesNoNewTextures]' passed
(0.005 seconds).
```

0.005s, matching the pre-change baseline (0.003s).

## Full-suite result

```
xcodebuild -project App/TrueISFEditor.xcodeproj -scheme ARShader -destination 'platform=macOS' \
  -derivedDataPath /tmp/arshader-ddata-bank test-without-building
```

`Executed 327 tests, with 0 failures (0 unexpected) in 22.465 (22.534) seconds` — full suite,
**327/327, 0 failures, 0 skipped.** Total wall-clock for the invocation: 25s. No hang on this
run, consistent with the documented intermittency (observed 2 times in 7 runs, not every run).

## Notes on the underlying hang (not chased, but recorded)

Nothing new was learned about root cause — this task deliberately did not investigate it. Two
observations from working the file, for whoever does:

- `InstrumentRenderer`'s and `MixerState`'s threading design is already sound for this exact
  call shape (locks + `nonisolated`), which weakens "test calls `renderFrame()` off-thread
  incorrectly" as a hypothesis for the original hang — the test as originally written called
  `renderFrame()` from the main thread (inside `@MainActor final class
  InstrumentRendererTests`), same as every other passing test in this file, so the hang is not
  explained by a thread-safety bug in this call path.
- The intermittency plus variable duration (~195s vs ~518s) is more consistent with a resource
  contention / ordering issue triggered by full-suite state (e.g. GPU command queue backlog,
  Metal driver stall, or a leftover async completion from an earlier test class) than with a
  deterministic bug in this test's own code. Nothing in `InstrumentRenderer.swift` or
  `MixerState.swift` read during this task pointed at a specific culprit.

## Files touched

- `App/ARShaderTests/InstrumentRendererTests.swift` (only file changed; staged/committed by
  explicit path only, never `git add -A`)
