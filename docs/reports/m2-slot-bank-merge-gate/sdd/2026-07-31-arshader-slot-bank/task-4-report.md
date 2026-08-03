# Task 4 report: `ShaderUnit.sourceURL`

## Status: DONE_WITH_CONCERNS

## What changed

`App/ARShader/ShaderUnit.swift`:
- Added `@Published private(set) var sourceURL: URL?` next to `shaderName`, with the doc comment
  from the brief verbatim.
- `load(source:name:)` sets `sourceURL = nil` at its start, as specified.
- `load(url:)` calls `load(source:name:)` and THEN sets `sourceURL = url` — reordered from the
  brief's literal instruction (see Deviation below).

`App/ARShaderTests/InstrumentLoadTests.swift` (new file):
- `makeShaderFile(_:)` — non-private, per the brief, for Task 5 to reuse.
- `testAFreshUnitHasNoSourceURL` — brief's test 1, verbatim.
- `testLoadingFromAURLRetainsIt` — brief's test 2, verbatim.
- `testLoadingFromSourceAfterAURLClearsIt` — added per the judgment call (see below).

Also ran `xcodegen generate` in `App/` — the new test file wasn't in the (gitignored, generated)
`.xcodeproj` until regenerated. Nothing to commit there; `TrueISFEditor.xcodeproj/` is ignored per
`.gitignore` line 6.

## Deviation from the brief: assignment order in `load(url:)`

The brief's Step 3 says to set `sourceURL = url` **immediately before** the `load(source:name:)`
call inside `load(url:)`, and separately says `load(source:name:)` should clear
`sourceURL = nil` **at its start**. Implemented literally, these two instructions collide:
`load(url:)` calls `load(source:name:)` internally, so setting `sourceURL = url` before that call
gets immediately wiped out by the clear at the top of `load(source:name:)` — the URL would never
stick. I caught this by tracing the call graph before wiring the assignment in, and confirmed it
with the mutation-proof run (see below): the naive order fails `testLoadingFromAURLRetainsIt`
deterministically, not flakily.

Fix: keep the clear-at-start in `load(source:name:)` exactly as specified (defensive, and it's
what the judgment-call test exercises), but move `sourceURL = url` in `load(url:)` to AFTER the
`load(source:name:)` call instead of before. Everything up to that point in `load(url:)` and
`load(source:name:)` is synchronous on the main actor — only the compile itself is dispatched to
`compileQueue` — so `sourceURL` is `url` by the time `load(url:)` returns, satisfying the
synchronous test assertion, and stays `url` regardless of whether the async compile later
succeeds or fails.

## A doctrine tension worth flagging (not changed)

`sourceURL` is set synchronously in `load(url:)`, before the async compile in
`load(source:name:)` resolves — unlike `shaderName`, which is only updated inside `apply()` on a
**successful** compile ("compile first, swap only on success"). Concretely: if `load(url:)` is
called with a file that fails to compile, `sourceURL` will report the new (failed) file while
`shaderName` and the rendering scene stay on whatever was previously loaded. `sourceURL` and
"what's actually running" can diverge on a failed load.

I did not change this — the given test (`testLoadingFromAURLRetainsIt`) asserts `sourceURL`
synchronously, immediately after calling `load(url:)`, with no wait for `onCompileFinished`. That
forces `sourceURL` to be set at call time, not inside the success branch of `apply()`; moving it
into `apply()` would fail the brief's own verbatim test. Flagging for whoever builds Task 5's
capture: if capture can run while a load is mid-flight or just failed, capturing `sourceURL` alone
could produce a `Preset` that doesn't match what's on screen. A defensive option would be for
capture to also check `compileError == nil` (or generation-match) before trusting `sourceURL`, but
that's a Task 5 decision, not mine to make here.

## Judgment call: `load(source:name:)` clear coverage

The brief's two required tests never exercise the `sourceURL = nil` clear. I added a third test,
`testLoadingFromSourceAfterAURLClearsIt`: load from a URL, confirm `sourceURL` is set, then load
from bare source and confirm `sourceURL` goes back to `nil`. Reasoning: this clear is exactly the
line that stops a source-loaded unit (e.g. a Remix result with no file behind it) from having
capture wrongly claim a stale file. Without a test, a future refactor could delete the clear and
nothing would catch it. This makes the suite count **228**, not the 227 stated in my task
assignment — flagging the discrepancy explicitly per the "if you believe something is wrong, say
so" instruction, since the assignment's own judgment-call clause invited adding this test.

## Test command and verbatim tail output

Targeted run:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:ARShaderTests/InstrumentLoadTests
```
```
Test Suite 'InstrumentLoadTests' started at 2026-07-31 12:19:55.593.
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshUnitHasNoSourceURL]' started.
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshUnitHasNoSourceURL]' passed (0.002 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt]' started.
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt]' passed (0.006 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt]' started.
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt]' passed (0.002 seconds).
Test Suite 'InstrumentLoadTests' passed at 2026-07-31 12:19:55.603.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.010 (0.011) seconds
** TEST SUCCEEDED **
```

Full suite:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 12:21:07.219.
	 Executed 228 tests, with 0 failures (0 unexpected) in 15.467 (15.520) seconds
Test Suite 'All tests' passed at 2026-07-31 12:21:07.219.
	 Executed 228 tests, with 0 failures (0 unexpected) in 15.467 (15.521) seconds
** TEST SUCCEEDED **
```
(225 baseline + 3 new = 228, not the 227 in the assignment — the extra one is the judgment-call
test above.)

## Mutation proof (Step 5, mandatory)

Removed `sourceURL = url` from the end of `load(url:)`. Ran the targeted suite:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshUnitHasNoSourceURL]' passed (0.002 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt]' started.
.../InstrumentLoadTests.swift:32: error: -[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt] :
XCTAssertEqual failed: ("nil") is not equal to ("Optional(file:///.../probe-....fs)") -
Capture needs the URL, and lastPathComponent is not enough — filenames are not unique across the corpus
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt]' failed (0.109 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt]' started.
.../InstrumentLoadTests.swift:46: error: -[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt] :
XCTAssertEqual failed: ("nil") is not equal to ("Optional(file:///.../probe-....fs)") - sanity: the URL load landed
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt]' failed (0.003 seconds).
Test Suite 'InstrumentLoadTests' failed at 2026-07-31 12:20:32.099.
	 Executed 3 tests, with 2 failures (0 unexpected) in 0.113 (0.114) seconds
** TEST FAILED **
```
Both the brief's required test and the judgment-call test went red, as expected. Restored the
line; re-ran the full suite: 228/228 pass (output above, second block, is the post-restore run).

## Commit

`584d019` — `feat(3b): ShaderUnit retains the URL it loaded`
Files: `App/ARShader/ShaderUnit.swift`, `App/ARShaderTests/InstrumentLoadTests.swift` (2 files
changed, 68 insertions, 0 deletions).

## Concerns for the caller

1. **Ordering deviation** from the brief's literal Step 3 wording (documented above) — the *effect*
   (sourceURL ends up set to the loaded URL, cleared on source loads) matches the brief's intent
   and interface contract; only the line order inside `load(url:)` changed, and it's covered by
   the given test plus the mutation proof.
2. **Test count is 228, not 227** — one extra test added for the judgment call the assignment
   explicitly invited. Task 5 should account for 228 as its new baseline, not 227.
3. **Doctrine tension flagged, not fixed**: `sourceURL` can point at a URL whose compile failed,
   while `shaderName`/the rendering scene stay on the previous shader. This is inherent to the
   brief's synchronous-test contract, not something Task 4 could resolve without breaking the
   given test. Surfaced for Task 5's capture design to consider.

---

# Fix round 1 of 5: `sourceURL` rides the swap, not the load

## Status: DONE

Ruling from the coordinator: concern 3 above was a real correctness bug, not a nicety. Fixed as
directed.

## What changed

`App/ARShader/ShaderUnit.swift`:
- Added `private var pendingSourceURL: URL?` — the URL of the in-flight load, consumed only on a
  successful compile.
- `load(url:)` now calls a new private three-argument `load(source:name:url:)`, passing the URL
  through instead of stamping `sourceURL` itself.
- `load(source:name:)` (the public two-arg entry point) forwards to the same private method with
  `url: nil`.
- The private `load(source:name:url:)` sets `pendingSourceURL = url` (replacing the old
  `sourceURL = nil` at the top — a nil `pendingSourceURL` naturally clears `sourceURL` when it's
  later consumed).
- `apply(_:name:generation:)`'s **success** branch now sets `sourceURL = pendingSourceURL`
  immediately after `shaderName = name` — nowhere else touches `sourceURL`.

Net effect: `sourceURL` is now written in exactly one place, on the exact same success path as
`shaderName`. A failed compile changes neither. A superseded load (generation guard) changes
neither. The old ordering hack from round 0 (restamping `sourceURL = url` after the internal
`load(source:name:)` call) is gone — there's nothing left to reorder around, since the stamp lives
entirely inside `apply`.

`App/ARShaderTests/InstrumentLoadTests.swift`:
- Added a `loadAndWait(_:_:)` helper (same shape as the one specified for Task 5) that awaits
  `onCompileFinished` via `withCheckedContinuation`, since the stamp now lands after the
  background compile rather than synchronously.
- `testAFreshUnitHasNoSourceURL` — unchanged, still synchronous (nothing is loaded).
- `testLoadingFromAURLRetainsIt` and `testLoadingFromSourceAfterAURLClearsIt` — converted to
  `async throws`, using `loadAndWait` (and, for the inline-source half of the second test, an
  `XCTestExpectation` + `fulfillment(of:timeout:)`, since that half calls `load(source:name:)`
  directly rather than through the URL path `loadAndWait` wraps).
- Added `testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying` — the regression test.

### Malformed `.fs` used for the regression test

Used the same uncompilable body already proven to fail elsewhere in the suite
(`App/ARShaderTests/Fixtures/broken.fs`, referenced from `ShaderUnitTests.testAFailedCompileKeepsThePreviousShaderPlaying`):
```glsl
/*{ "ISFVSN": "2.0", "DESCRIPTION": "Deliberately uncompilable.", "INPUTS": [] }*/
void main() { gl_FragColor = this_symbol_does_not_exist(1.0); }
```
An undefined GLSL symbol reference. Confirmed it actually fails at the ISFMSLKit layer (see the
runtime log lines in the test output below: `ERR: unable to convert frag shader`, `ERR: shader
doesn't exist- ... cached as compiler-error proxy state`) — this is a real compile failure in this
runtime, not a hypothetical.

## Note: the coordinator's fix to `ShaderUnit.swift` had already landed

While I was implementing this round, a commit appeared on this branch —
`4228630 fix(3b): sourceURL belongs to the swap, not the load` — that made the identical
`ShaderUnit.swift` change specified in the coordinator's message (byte-identical after my own
edit: `git diff HEAD -- App/ARShader/ShaderUnit.swift` was empty once I applied the coordinator's
exact instructions). I did not need to commit that file again. My commit for this round contains
only the test file, which that commit did not touch. Flagging this per the multi-session awareness
doctrine — another process wrote to this worktree's branch mid-task — but the content converged
identically, so there was no conflict to resolve.

## Test command and verbatim tail output

Targeted run (4 tests):
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:ARShaderTests/InstrumentLoadTests
```
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying]' started.
2026-07-31 12:24:59.911689-0700 ARShader[66679:33721657] mdb_txn_commit error: MDB_MAP_FULL: Environment mapsize limit reached
2026-07-31 12:24:59.947200-0700 ARShader[66679:33721657] ERR: unable to convert frag shader for file isfruntime-515C3BEB-3420-4F41-BDBA-FE82C53E1D30, bailing
2026-07-31 12:24:59.951551-0700 ARShader[66679:33721657] ERR: shader doesn't exist- object (<ISFMSLCacheObject isfruntime-515C3BEB-3420-4F41-BDBA-FE82C53E1D30 0x934fa9540>) is cached as compiler-error proxy state
2026-07-31 12:24:59.973859-0700 ARShader[66679:33721657] ERR: unable to load file (isfruntime-515C3BEB-3420-4F41-BDBA-FE82C53E1D30.fs), -[ISFMSLScene loadURL:resetTimer:]
Test Case '-[ARShaderTests.InstrumentLoadTests testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying]' passed (1.001 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshUnitHasNoSourceURL]' started.
Test Case '-[ARShaderTests.InstrumentLoadTests testAFreshUnitHasNoSourceURL]' passed (0.001 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt]' started.
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromAURLRetainsIt]' passed (0.186 seconds).
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt]' started.
Test Case '-[ARShaderTests.InstrumentLoadTests testLoadingFromSourceAfterAURLClearsIt]' passed (0.160 seconds).
Test Suite 'InstrumentLoadTests' passed at 2026-07-31 12:25:00.408.
	 Executed 4 tests, with 0 failures (0 unexpected) in 1.349 (1.350) seconds
** TEST SUCCEEDED **
```

Full suite:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 12:25:28.580.
	 Executed 229 tests, with 0 failures (0 unexpected) in 15.965 (16.020) seconds
Test Suite 'All tests' passed at 2026-07-31 12:25:28.580.
	 Executed 229 tests, with 0 failures (0 unexpected) in 15.965 (16.020) seconds
** TEST SUCCEEDED **
```
229/229 — exactly as predicted (225 baseline + 3 round-0 tests + 1 new regression test).

## Mutation proof (mandatory)

Moved `sourceURL = pendingSourceURL` from `apply`'s success branch to immediately after the
`generation == loadGeneration` guard, i.e. before the failure guard, so it would fire even when
the compile fails:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying]' started.
2026-07-31 12:25:46.371358-0700 ARShader[66946:33724066] ERR: unable to convert frag shader for file isfruntime-AB08A0D2-D8E3-4A50-93D8-3309AE679E0D, bailing
.../InstrumentLoadTests.swift:101: error: -[ARShaderTests.InstrumentLoadTests testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying] :
XCTAssertEqual failed: ("Optional(file:///.../bad-B3683AF8-E663-4C0B-92DF-6D7EBEF74068.fs)") is not equal to
("Optional(file:///.../good-1899BF2B-ED2D-4E1A-B56B-2B0AC2567593.fs)") -
A failed compile leaves the previous shader playing, so sourceURL must still name it — capture reads this, and
would otherwise store a shader that does not compile
Test Case '-[ARShaderTests.InstrumentLoadTests testAFailedCompileLeavesSourceURLOnTheShaderThatIsStillPlaying]' failed (0.541 seconds).
Test Suite 'InstrumentLoadTests' failed at 2026-07-31 12:25:46.697.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.541 (0.542) seconds
** TEST FAILED **
```
Went RED as expected — `sourceURL` was stamped to the failed file's URL instead of staying on the
previously-playing one. Restored the line to the success branch; re-ran the full suite: 229/229
pass.

## Commit

`57b4538` — `test(3b): cover the sourceURL swap fix async, plus the failed-compile regression`
File: `App/ARShaderTests/InstrumentLoadTests.swift` (1 file changed, 54 insertions, 4 deletions).

The `ShaderUnit.swift` fix itself is `4228630` — already on the branch before this round's commit,
authored outside this session (see note above); not re-committed here since there was nothing to
add.

## Concerns for the caller

None outstanding. All three round-0 concerns are now closed: concern 1 (ordering) and concern 2
(extra test) were accepted as-is; concern 3 (the doctrine tension) is now fixed and covered by a
dedicated regression test, proven with a mutation test.

---

# Fix round 2 of 5: `unload()` was clearing `shaderName` but not `sourceURL`

## Status: DONE

Same class of bug as round 1's concern 3: `sourceURL` and `shaderName` disagreeing about what's
actually up. This time on the Clear path rather than the failed-compile path.

## What changed

`App/ARShader/ShaderUnit.swift`, `unload()` — confirmed this is the real target of the Clear
button (`InstrumentView.swift:72`: `Button("Clear") { unit.unload() }`), matching the coordinator's
citation exactly, so no name/signature substitution was needed.

```swift
    func unload() {
        loadGeneration += 1   // cancels any in-flight compile: its apply() will fail the guard
        pendingSourceURL = nil
        core.setScene(nil, imageInputNames: [])
        shaderName = nil
        sourceURL = nil
        inputs = []
        compileError = nil
        params.resetAll()
    }
```

Two additions: `sourceURL = nil` beside `shaderName = nil` (the actual fix), and
`pendingSourceURL = nil` (defensive). Checked what `unload()` actually does per the coordinator's
instruction rather than assuming: it already bumps `loadGeneration`, and `apply()`'s first line is
`guard generation == loadGeneration else { return }` — so any in-flight compile from before the
clear is already cancelled and will never reach the line that reads `pendingSourceURL`. Clearing
`pendingSourceURL` here isn't load-bearing for correctness (a subsequent `load(url:)`/`load(source:)`
always overwrites it before it's next consumed), but it keeps every in-flight/current-state field
nil'd together rather than leaving one stale field around for a reader to trip over.

`App/ARShaderTests/InstrumentLoadTests.swift` — added
`testUnloadingClearsTheSourceURLAsWellAsTheName`, verbatim from the coordinator's message.

## Test command and verbatim tail output

Targeted run (5 tests):
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:ARShaderTests/InstrumentLoadTests
```
```
Test Case '-[ARShaderTests.InstrumentLoadTests testUnloadingClearsTheSourceURLAsWellAsTheName]' started.
2026-07-31 12:36:22.359454-0700 ARShader[65220:33896099] mdb_txn_commit error: MDB_MAP_FULL: Environment mapsize limit reached
Test Case '-[ARShaderTests.InstrumentLoadTests testUnloadingClearsTheSourceURLAsWellAsTheName]' passed (0.214 seconds).
Test Suite 'InstrumentLoadTests' passed at 2026-07-31 12:36:22.462.
	 Executed 5 tests, with 0 failures (0 unexpected) in 2.362 (2.364) seconds
** TEST SUCCEEDED **
```

Full suite:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader \
  -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
```
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 12:36:53.188.
	 Executed 230 tests, with 0 failures (0 unexpected) in 21.748 (21.815) seconds
Test Suite 'All tests' passed at 2026-07-31 12:36:53.188.
	 Executed 230 tests, with 0 failures (0 unexpected) in 21.748 (21.815) seconds
** TEST SUCCEEDED **
```
230/230 — exactly as predicted (229 + this one).

## Mutation proof (mandatory)

Removed `sourceURL = nil` from `unload()`:
```
Test Case '-[ARShaderTests.InstrumentLoadTests testUnloadingClearsTheSourceURLAsWellAsTheName]' started.
2026-07-31 12:37:19.440019-0700 ARShader[74939:33910126] mdb_txn_commit error: MDB_MAP_FULL: Environment mapsize limit reached
.../InstrumentLoadTests.swift:118: error: -[ARShaderTests.InstrumentLoadTests testUnloadingClearsTheSourceURLAsWellAsTheName] :
XCTAssertNil failed: "file:///.../loaded-1D21730E-F77C-4A46-8B9A-D3FB69974815.fs" -
A cleared deck has nothing playing, so it must not still name a file — capture reads sourceURL to decide whether there is anything to capture
Test Case '-[ARShaderTests.InstrumentLoadTests testUnloadingClearsTheSourceURLAsWellAsTheName]' failed (1.811 seconds).
Test Suite 'InstrumentLoadTests' failed at 2026-07-31 12:37:19.901.
	 Executed 1 test, with 1 failure (0 unexpected) in 1.811 (1.811) seconds
** TEST FAILED **
```
Went RED as expected. Restored the line; re-ran the full suite: 230/230 pass.

## Commit

`89dc2a1` — `fix(3b): unload() clears sourceURL too, not just shaderName`
Files (explicit paths, no `-A`/`.`): `App/ARShader/ShaderUnit.swift`,
`App/ARShaderTests/InstrumentLoadTests.swift` — 2 files changed, 20 insertions, 1 deletion.

Confirmed `git status --short` immediately before `git add` showed only these two files modified,
before staging.

## Concerns for the caller

None outstanding.
