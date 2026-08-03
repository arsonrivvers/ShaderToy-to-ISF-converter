# Task 1 Report: `ThumbnailService`

## Status: DONE

## What was implemented

- `App/ARShader/ThumbnailCache.swift` — disk half of the pipeline (no GPU). SHA256(path|mtime)
  keyed, one `.png`/`.failed` file per entry under an Application-Support-style directory,
  count-bounded LRU eviction.
- `App/ARShader/ThumbnailService.swift` — the render half. First `actor` in the codebase, per the
  brief's explicit deviation rationale. Owns `RenderProperties.global().device` (shared) and
  `RenderProperties.global().bgCmdQueue` (isolated — never `.renderQueue`). Renders offscreen at
  `sampleTime = 2.0s`, 320×180, via `ISFSceneLoader.load` → `ISFMSLSafeRenderAtTime` →
  `TextureReadback.managedCopy` → `FramePNGEncoder.encodePNG`. Failures cache as `.unavailable`,
  invalidated by mtime like successes.
- `App/ARShaderTests/ThumbnailCacheTests.swift`, `App/ARShaderTests/ThumbnailServiceTests.swift` —
  copied verbatim from the brief, no changes.

Both new source files are picked up automatically by `App/project.yml`'s directory globs
(`path: ARShader`, `path: ARShaderTests`) — no `project.yml` edit needed; confirmed by reading the
ARShader/ARShaderTests target blocks before starting. Ran `xcodegen generate` after each new file.

## Deviations from the brief's literal code (both required — the pasted code does not compile /
does not pass without them)

1. **`render(_:)` — the brief's `try? ISFSceneLoader.load(...)` guard is dead code and mismatches
   the `renderPNG(scene:)` type.** `ISFSceneLoader.load` is non-throwing and returns a
   `ISFSceneLoader.Result` struct (not an optional `ISFMSLScene`) even on a failed compile — it
   always returns a `Result` with `.scene = nil` and `.errorMessage` set, never actually failing to
   return a value. So `let scene = try? ISFSceneLoader.load(...)` binds successfully (wrapped as
   `Result?`) on every call, including compile failures, and the binding's type is
   `ISFSceneLoader.Result`, which doesn't type-check against `renderPNG(scene: ISFMSLScene)` at all
   — the brief's snippet as pasted fails to compile. Fixed by calling `load` directly (no `try?`),
   checking `loaded.isValid`, and unwrapping `loaded.scene` before calling `renderPNG`.
2. **`ThumbnailCache.evict` sorted by `.contentAccessDateKey`, but `touch()` only ever writes
   `.modificationDate`.** `FileManager.setAttributes` has no settable access-date key (only creation
   and modification date are settable), and access-time updates are unreliable to begin with — many
   volumes mount `noatime`/`relatime` and never bump atime on a plain read. The mismatch made
   `testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling` fail (confirmed by running it before the
   fix — see RED evidence below). Fixed by switching the sort key to
   `.contentModificationDateKey`, matching what `touch()` actually writes.

Both are documented inline in the committed files and in the commit message. Neither changes the
tests (which were copied verbatim from the brief).

## Concern for the reviewer (not fixed — flagging per "report brief issues, don't paper over them")

`render(_:)`'s cancellation guard (`guard !Task.isCancelled, ... else { cache.store(.unavailable,
...) }`) is inherited unchanged from the brief. If an `.interactive` request is cancelled by a
newer hover before its `render()` task has started running, the cancelled path caches `.unavailable`
for that shader — a mid-flight *cancellation* gets recorded on disk identically to a genuine
*compile failure*, which would then poison every future hover of that shader (until its mtime
changes) even though it never actually failed to compile. In practice the window is narrow — once
`render()` starts executing it has no internal suspension points, so cooperative actor scheduling
means a later `cancel()` call can't interrupt it mid-flight; it can only matter in the gap between
`Task { ... }` creation and the task actually starting. No required test exercises this path (the
brief's test list has no interactive-cancellation case), so I left the code exactly as specified
rather than expanding scope. A future task should consider not persisting `.unavailable` when
`Task.isCancelled` is true, only when the compile/render genuinely failed.

## TDD evidence

**RED — cache (Step 2):**
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailCacheTests
```
```
error: cannot find type 'ThumbnailCache' in scope
```
Expected: `ThumbnailCache.swift` did not exist yet.

**GREEN — cache, first pass (Step 4), then a real RED from the access-date/mtime mismatch:**
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailCacheTests
```
```
Test Case '-[ARShaderTests.ThumbnailCacheTests testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling]' failed
  XCTAssertNotNil failed - the most recently used survives
  XCTAssertNil failed: "image(1 bytes)" - the least recently used is gone
Executed 5 tests, with 2 failures
```
Root cause diagnosed and fixed (see Deviation 2 above). Re-run, GREEN:
```
Executed 5 tests, with 0 failures (0 unexpected) in 0.032s
```

**RED — service (Step 6):**
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests
```
```
error: cannot find 'ThumbnailService' in scope
```
Expected: `ThumbnailService.swift` did not exist yet.

**GREEN — service (Step 8), after fixing Deviation 1 above:**
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests
```
```
Test Suite 'ThumbnailServiceTests' passed at 2026-08-01 07:01:59.380.
	 Executed 5 tests, with 0 failures (0 unexpected) in 1.407s
```

## Mutation-proof results (Step 9 — each applied, run, observed, then reverted)

1. **`sampleTime` 2.0 → 0.0.**
   Command: `xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests/testTheSampleTimeIsTwoSeconds`
   Observed: `XCTAssertEqual failed: ("0.0") is not equal to ("2.0")` — FAILED as expected.
   Reverted.

2. **Deleted `cache.store(.unavailable, …)` on the compile-failure path in `render`.**
   Command: `xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests/testABrokenShaderIsNotRecompiledOnEveryRequest`
   Observed: `XCTAssertEqual failed: ("1") is not equal to ("2") - the second request must be served
   from the cached failure` — FAILED as expected (the broken shader recompiled on the second call).
   Reverted.

3. **`self.queue = properties.bgCmdQueue` → `self.queue = properties.renderQueue`.**
   Command: `xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests/testTheServiceNeverUsesTheLiveRenderQueue`
   Observed: `XCTAssertFalse failed - sharing the live queue is how a thumbnail becomes a dropped
   frame mid-set` — FAILED as expected. This is the safety-critical one: the only assertion in the
   whole suite that can see a thumbnail compile sharing the live render queue.
   Reverted.

After each revert, re-ran the pair (`ThumbnailCacheTests` + `ThumbnailServiceTests`, 10 tests) to
confirm a clean GREEN state before moving on, and again as part of the full-suite run below.

## Full suite (Step 10)

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-08-01 07:03:49.987.
	 Executed 266 tests, with 0 failures (0 unexpected) in 17.928s
```
Baseline was 256 tests, 0 failures. 266 = 256 + 10 new (5 cache + 5 service). No test count
regression.

Also confirmed a clean `xcodebuild build` produces zero warnings in either new file
(`grep -i "ThumbnailService.swift\|ThumbnailCache.swift"` against the full build log — empty).

## Files changed

- `App/ARShader/ThumbnailService.swift` (new)
- `App/ARShader/ThumbnailCache.swift` (new)
- `App/ARShaderTests/ThumbnailServiceTests.swift` (new, verbatim from brief)
- `App/ARShaderTests/ThumbnailCacheTests.swift` (new, verbatim from brief)
- `App/project.yml` — not modified; both target source lists are directory globs and pick up new
  files automatically (confirmed by reading the ARShader/ARShaderTests blocks before starting).
- `App/TrueISFEditor.xcodeproj/project.pbxproj` — regenerated by `xcodegen generate` but not
  git-tracked in this repo, so nothing to stage/commit for it.

## Commit

`30bf31a` — `feat(3c): ThumbnailService — offscreen stills at t=2.0s, cached by path+mtime`
(includes the deviation rationale and mutation-proof results in the commit body, per the brief's
"record all three results in the commit message" instruction).

## Self-review (fresh eyes)

- **Completeness**: every brief interface is present — `thumbnail(for:priority:)`,
  `cancelInteractive()`, `Priority`, `Result`, `ThumbnailCache`, `sweepCache()`/`cacheCeiling` for a
  future launch-time sweep. Nothing extra added (no UI, no LibraryEntry wiring — out of scope for
  this task, left for Tasks 3/7 as specified).
- **Quality**: both new files match house doc-comment density and naming conventions. No force
  unwraps except `(try? ThumbnailCache(directory:))!` in `init`, which is the brief's own code —
  directory creation only fails on genuine filesystem errors (permissions, out of space), which
  would also break every other disk-backed feature in the app; consistent with how `SnapshotStore`
  and similar stores in this codebase behave.
- **Discipline**: no `git add -A` used (explicit paths only, per the global constraint). Derived
  data path was always `/tmp/arshader-ddata-bank`, never `/tmp/arshader-ddata`. No unrelated files
  touched.
- **Test honesty**: all TDD RED/GREEN transitions and all three mutation proofs were actually run,
  not asserted from memory — command output pasted above and in the commit message.

---

# Round 1 Fix Report

Reviewer returned SPEC ✅, QUALITY FINDINGS — 11 (1 Critical, 6 Important, 4 Minor). This section
covers the Critical (C1) and six Important (I2–I7) findings. The four Minor findings (M8–M11) were
NOT touched, per the coordinator's explicit instruction — deferred to the final branch review.

**Controller ruling acknowledged**: C1 originates in the task brief's own pasted code (the
`guard !Task.isCancelled` / `store(.unavailable)` shape), and the brief is wrong there — it
contradicts the spec's own stated intent that "failures cached as failures" means *compile*
failures, not cancellations. The fix below overrides the brief's literal code where the two
conflict.

## What changed, per finding

**C1 (Critical) + I2 (Important) — cancellation and `.batch` transient failures no longer poison
the cache.** `ThumbnailService.swift`. Replaced the old `render(_:) -> Result` (which persisted
`.unavailable` for every non-image outcome) with `render(_:) -> RenderOutcome`, a private enum with
four cases: `.success`, `.shaderFailed(reason:)`, `.transientFailure(reason:)`, `.cancelled`. A new
`resolve(_:for:) -> Result` is the ONLY place that writes to disk, and it persists `.unavailable`
for exactly ONE case: `.shaderFailed`. `.cancelled` and `.transientFailure` both return
`.unavailable` to the immediate caller (so a blank cell still shows "not available now") but write
nothing, so the very next request — whether interactive or batch — tries again instead of being
stuck behind a false verdict. This closes both C1 (interactive cancellation) and I2 (`.batch`
cancellation via the caller's own task) with the same fix, since both routes flow through the same
`render`/`resolve` pair.

Also corrected `cancelInteractive()`'s doc comment, which claimed it "drops in-flight hover work."
It doesn't: `render` has no `await` inside its body once started (`ISFSceneLoader.load` and
`renderPNG` are both synchronous), so a render already past its last `Task.isCancelled` checkpoint
runs to completion regardless of `cancelInteractive()`. The new comment states plainly what the call
actually guarantees: cancellation can only take effect at one of `render`'s two checkpoints (before
reading source, before rendering), and what's now reliable is that a cancelled render can't corrupt
the disk cache — not that it can abort in-flight GPU work.

**I3 (Important) — transient infrastructure failures no longer persist as permanent compile
failures; the discarded error is now surfaced.** `ThumbnailService.swift`. `render`'s middle guard
now distinguishes `.shaderFailed` (unreadable source, or `ISFSceneLoader.load` reporting
`!isValid`) from `.transientFailure` (everything inside `renderPNG`: `makeCommandBuffer()` nil,
`ISFMSLSafeRenderAtTime` failure, the render timeout, texture readback failure, PNG encode
failure). Per `resolve`, only `.shaderFailed` persists. `renderPNG` itself was changed from
returning `Data?` to a local `RenderPNGOutcome` enum (`.pngSuccess(Data)` / `.pngFailure(String)`)
carrying a message for every failure branch, including the previously-discarded `err` from
`ISFMSLSafeRenderAtTime` — `(err as String?) ?? "ISF render failed."`. That reason flows into
`RenderOutcome.shaderFailed`/`.transientFailure` and is stored in a new
`private(set) var lastFailureReasonForTesting: String?` on the actor (mirrors the existing
`compileCountForTesting` test-seam pattern). This is a diagnostic seam, not a UI feature — no test
asserts specific message text, only that the plumbing exists for a future task to surface it.

Note: `Swift.Result<Data, String>` does not compile (`String` doesn't conform to `Error`), so
`renderPNG` uses the local `RenderPNGOutcome` enum instead of the stdlib `Result` type. Caught by
the build, fixed immediately — noted here for the reviewer's awareness since it's a deviation from
what a natural first draft would reach for.

**I4 (Important) — the sample-time mutation proof was circular; replaced with a pixel-level
proof.** Added `App/ARShaderTests/Fixtures/time_gate.fs`: black at `TIME <= 1.0`, red past
`TIME > 1.0` (a wide margin around `sampleTime = 2.0` and the `0.0` mutation, both used verbatim as
the reviewer specified — no boundary-exactness assumption). Added
`testTheRenderedThumbnailReflectsTheSampleTimeNotZero` to `ThumbnailServiceTests.swift`: renders
`time_gate.fs` through the real service, decodes the PNG (a `decodeRGBA` helper mirroring
`FramePNGEncoderTests.decodeRGBA`), and asserts at least one strongly-red, near-zero-G/B pixel
exists. Kept `testTheSampleTimeIsTwoSeconds` as a cheap sanity check on the constant, but its doc
comment now says plainly that it's not the real proof and points at the new test.

**I5 (Important) — the eviction test now proves the read-touch, not write order.**
`ThumbnailCacheTests.swift`. Changed which entry is touched before eviction from `shaders[4]`
(already the newest by write order — touching it changed nothing observable) to `shaders[0]` (the
OLDEST write). Assertions now check: `shaders[0]` survives (touched last despite being written
first), `shaders[4]` survives (newest write, untouched), `shaders[3]` is EVICTED (would have
survived under write-order/FIFO alone — the second-newest write — but was never touched), and
`shaders[1]` is evicted (neither touched nor recently written). No production code change was
needed — `ThumbnailCache.swift`'s `evict`/`touch` were already correct from the original
implementation; the bug was entirely in what the test asserted.

**I6 (Important) — the cache can no longer crash the instrument.** `ThumbnailService.swift`.
`private let cache: ThumbnailCache` (force-unwrapped in `init`) became `private let cache:
ThumbnailCache?` (`self.cache = try? ThumbnailCache(directory: cacheDirectory)`, no `!`). Every call
site updated: `thumbnail(for:priority:)`'s cache-read guard is now `if let cache, let cached = try?
cache.entry(for: shaderURL)`; `resolve` writes via `try? cache?.store(...)`; `sweepCache()` is `try?
cache?.evict(...)`. When `cache` is `nil` the service still renders and returns fresh results every
time — degraded (no caching), never crashed. Corrected my own round-1 report, which had defended
the force-unwrap as "consistent with house behavior" — the reviewer is right that this was
backwards: `SnapshotStore`, `ISFSceneLoader`, and `ISFSceneSource` all degrade via `try?` rather than
crash, so the force-unwrap was the one outlier, not the norm.

**I7 (Important) — the actor-blocking GPU wait is now bounded, and the trade-off is documented.**
`ThumbnailService.swift`. Added `private static let renderTimeout: TimeInterval = 5.0`. `renderPNG`
no longer calls `cb.commit(); cb.waitUntilCompleted()`; it now attaches a completion handler to a
`DispatchSemaphore` BEFORE commit (`cb.addCompletedHandler { _ in done.signal() }`, `cb.commit()`,
`done.wait(timeout: .now() + Self.renderTimeout)`), and treats a timeout as `.pngFailure(...)` —
which resolves to `RenderOutcome.transientFailure`, i.e. never persisted (I3). This bounds OUR
commit-then-wait; `TextureReadback.managedCopy`'s own internal commit+wait is shared infrastructure
used elsewhere in the app (e.g. `InstrumentRendererTests`) and is a small GPU-local blit — left
untouched, as instructed ("do NOT redesign it"). A block comment above `renderPNG` states the
trade-off explicitly: every actor caller (including a queued `.batch` item) still waits behind an
in-flight render; this task bounds that wait rather than removing it.

## Covering tests re-run

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:ARShaderTests/ThumbnailServiceTests -only-testing:ARShaderTests/ThumbnailCacheTests
```
```
Test Suite 'ThumbnailCacheTests' passed ... Executed 5 tests, with 0 failures
Test Suite 'ThumbnailServiceTests' passed ... Executed 7 tests, with 0 failures
Test Suite 'ARShaderTests.xctest' passed ... Executed 12 tests, with 0 failures
** TEST SUCCEEDED **
```
(5 cache tests unchanged in count, I5 only changed assertions within the existing eviction test;
7 service tests = the original 5 + `testTheRenderedThumbnailReflectsTheSampleTimeNotZero` (I4) +
`testACancelledRequestIsNeverPersistedAsUnavailable` (new, added to give C1/I2 direct test
coverage — see below).)

## Mutation-proof re-runs (I4, I5) — exact commands and output

**I4 re-run, as specified: mutate the RENDER CALL SITE (`Self.sampleTime` → `0.0` at
`ISFMSLSafeRenderAtTime(scene, size, Self.sampleTime, cb, &err)`), NOT the constant.**
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailServiceTests/testTheRenderedThumbnailReflectsTheSampleTimeNotZero \
                     -only-testing:ARShaderTests/ThumbnailServiceTests/testTheSampleTimeIsTwoSeconds
```
```
Test Case '...testTheRenderedThumbnailReflectsTheSampleTimeNotZero' :
  XCTAssertTrue failed - expected a red frame (rendered past t=1), got an all-black one — the
  render did not actually sample at sampleTime
Test Case '...testTheRenderedThumbnailReflectsTheSampleTimeNotZero' failed (0.612 seconds).
Test Case '...testTheSampleTimeIsTwoSeconds' passed (0.000 seconds).
** TEST FAILED **
```
Confirms the finding exactly: the literal-constant test stays green under this mutation while the
new pixel test catches it. Reverted (`Self.sampleTime` restored at the call site).

**I5 re-run, as specified: delete `try? touch(png)` from `ThumbnailCache.entry(for:)`.**
```
xcodebuild test ... -only-testing:ARShaderTests/ThumbnailCacheTests/testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling
```
```
Test Case '...testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling' :
  XCTAssertNotNil failed - touched after being written oldest — survives because it was USED,
  not written, last
  XCTAssertNil failed: "image(1 bytes)" - would have survived under write-order alone
  (2nd-newest write), but was never touched
Test Case '...testEvictionDropsTheLeastRecentlyUsedAboveTheCeiling' failed (0.338 seconds).
** TEST FAILED **
```
Confirms the finding: without the read-touch, eviction is FIFO-by-write-order and the amended test
(which specifically probes for USE order, not write order) fails. Reverted (`try? touch(png)`
restored in `entry(for:)`).

## Bonus: direct test coverage for C1/I2 (not explicitly requested, added for test honesty)

Neither C1 nor I2 had a dedicated unit test — the fix was verifiable by code inspection and by the
full suite continuing green, but "green because nothing exercises the changed path" is a weak
claim for a Critical finding. Added `testACancelledRequestIsNeverPersistedAsUnavailable`:

```swift
func testACancelledRequestIsNeverPersistedAsUnavailable() async throws {
    let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
    let shader = try fixtureURL("solid_red")
    let cancelled = Task { await service.thumbnail(for: shader, priority: .batch) }
    cancelled.cancel()
    _ = await cancelled.value
    let result = await service.thumbnail(for: shader, priority: .batch)
    guard case .image = result else {
        return XCTFail("a cancelled request must not poison the cache; got \(result)")
    }
}
```

This uses `.batch`, not `.interactive`, deliberately: `.batch` awaits `render` directly on the
CALLING task with no intervening `await`, so cancelling that task immediately after creation (with
no `await` in between — Swift task scheduling won't run the new task's body until the creating
context yields) guarantees `Task.isCancelled` reads true for the task's entire body, with no
scheduling race to win. Reproducing the `.interactive`-specific race (which spawns an inner
unstructured `Task` not reachable from the caller's own task) deterministically would need a new
test seam (e.g. an injectable delay) that wasn't requested and risked scope creep; this test proves
the SHARED underlying fix (`RenderOutcome.cancelled` is never persisted) that both routes depend on.

**Mutation-proved** (not required, done for confidence given C1 is the Critical finding): reverted
`resolve`'s `.cancelled` case to persist (`case .cancelled: try? cache?.store(.unavailable, for:
shaderURL); return .unavailable`), ran the new test:
```
Test Case '...testACancelledRequestIsNeverPersistedAsUnavailable' :
  failed - a cancelled request must not poison the cache; got unavailable
** TEST FAILED **
```
Reproduces C1 exactly. Reverted.

## Full ARShader suite

First full-suite invocation after the round-1 changes returned `Executed 123 tests` and
`** TEST FAILED **` with `tail -20` showing no actual failing test case in the visible window — a
transient flake (most likely codesign/derived-data contention from the many back-to-back
`xcodebuild test` invocations in this session), not a real regression. Re-ran twice with the full
log captured:

```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/arshader-ddata-bank \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
Run 1 (tee'd to a log file, `grep -c " failed"` on the full log = 0):
```
Test Suite 'ARShaderTests.xctest' passed ... Executed 268 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed ... Executed 268 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```
Run 2 (repeated to confirm stability):
```
Executed 268 tests, with 0 failures (0 unexpected) in 18.099s
** TEST SUCCEEDED **
```
268 = the round-1 baseline of 266 (256 original + 10 new) + 2 new tests this round
(`testTheRenderedThumbnailReflectsTheSampleTimeNotZero` for I4,
`testACancelledRequestIsNeverPersistedAsUnavailable` for C1/I2). No test count regression across
two clean full-suite runs.

## M10 side-effect check

The coordinator asked to note whether C1's fix incidentally resolved M10 (`interactiveTask` never
cleared on completion). It did not: the `.interactive` branch of `thumbnail(for:priority:)` still
assigns `interactiveTask = task` and never sets it back to `nil` after a successful (uncancelled)
completion — only `cancelInteractive()` clears it. M10 is unchanged, left for the final review as
instructed.

## Files changed this round

- `App/ARShader/ThumbnailService.swift` (modified — C1, I2, I3, I6, I7)
- `App/ARShaderTests/ThumbnailServiceTests.swift` (modified — I4 new test + doc comment, C1/I2 new
  test, `decodeRGBA` helper, new imports `ImageIO`/`CoreGraphics`)
- `App/ARShaderTests/ThumbnailCacheTests.swift` (modified — I5 test fix)
- `App/ARShaderTests/Fixtures/time_gate.fs` (new — I4 fixture)
- `App/ARShader/ThumbnailCache.swift` — untouched (I5's bug was in the test, not this file;
  confirmed via `git status`/`git diff --stat` showing no changes to this file after the mutation
  proof was reverted)

## Concerns for the final review

- I3's diagnostic seam (`lastFailureReasonForTesting`) is test-only; no UI task yet consumes it.
  Flagging so Tasks 3/7 know it exists rather than adding their own parallel mechanism.
- I7 bounds only OUR OWN wait inside `renderPNG`; `TextureReadback.managedCopy`'s internal wait
  remains unbounded, as instructed. If a hung GPU ever manifests specifically inside that shared
  helper rather than the ISF render call, this task's bound won't catch it — flagging for the final
  review's awareness, not proposing a fix (redesigning shared infrastructure was explicitly out of
  scope here).
- M8–M11 (four Minor findings) were deliberately NOT touched, per the coordinator's instruction.
