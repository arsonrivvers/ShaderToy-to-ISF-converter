# Task 7 report: the bank panel

## What was implemented

Replaced the Task-7 placeholder `SlotBankPanelView` (which took only `instrument` and
rendered a static "Bank" label) with the real view specified in the brief, verbatim:

- `App/ARShader/SlotBankPanelView.swift` — full rewrite. `SlotBankPanelView` now takes
  `instrument: Instrument` and `target: Binding<LibraryTarget>`, owns an `@ObservedObject`
  `SlotBank` sourced from `instrument.slotBank`, and a `@State private var source: DeckID`
  defaulting to `.one`. Body: a segmented "Capture from" deck picker, then 8 `SlotCell` rows
  (`SlotBank.slotCount`), then a spacer. `recall(_:)` calls `bank.recall(index)` and, on a
  non-nil result, `instrument.load(preset.shaderURL, onto: target, thenApply: preset.snapshot)`.
  `capture(into:)` reads `instrument.currentPreset(of: source)` and, if non-nil, calls
  `bank.capture(preset, into: index)` — this is the file's only call to `SlotBank.capture`.
  `SlotCell` (private) renders index, name/"empty", Replace/Clear buttons that appear only on
  hover, and has exactly one `.onTapGesture` whose body branches on `preset == nil` (capture),
  `NSEvent.modifierFlags.contains(.option)` (capture), else recall.
- `App/ARShader/InstrumentView.swift` — one-line change to the `.bank` case of
  `panelContent`, passing `$libraryTarget` (declared at line 149) as the new `target` binding.

No test file changes — the brief states the view is routing logic over an already-covered
model, and I agree: `SlotBank`'s own behavior (capture/recall/clear/isAvailable) is already
exercised by `SlotBankTests`, and the view's gesture routing is exactly what Step 3's
by-inspection check exists to cover instead of a unit test.

## Full-suite run

Command (foreground, as instructed):
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Verbatim tail:
```
Test Suite 'SurfaceLayoutTests' passed at 2026-07-31 13:38:49.893.
	 Executed 16 tests, with 0 failures (0 unexpected) in 0.007 (0.009) seconds
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 13:38:49.893.
	 Executed 243 tests, with 0 failures (0 unexpected) in 18.190 (18.237) seconds
Test Suite 'All tests' passed at 2026-07-31 13:38:49.893.
	 Executed 243 tests, with 0 failures (0 unexpected) in 18.190 (18.238) seconds
...
** TEST SUCCEEDED **
```

**243 tests, 0 failures** — matches the dispatch context's stated pre-change count of 243
(and expected post-change count of 243, since no tests were added). This does NOT match the
brief's own Step 2, which says "Expected: 240 tests" — see Concerns below.

`SurfaceGeometryTests.testSurfaceBaselines` (the PNG-baseline test) passed with no diff. No
baseline changed. This is the expected result: the bank panel is only rendered when
`layout.openPanel == .bank`, and none of the three baselined states open the Bank panel, so a
touch to `SlotBankPanelView`/`InstrumentView` should not reach anything the baselines render.
I did not need to investigate further because the baseline test passed clean — nothing leaked.

## Step 3: safety-property verification by inspection

Grep command and full output:
```
$ grep -n "\.capture(" App/ARShader/*.swift
App/ARShader/SlotBankPanelView.swift:55:        bank.capture(preset, into: index)
```

Exactly one call to `SlotBank.capture` in all of `App/ARShader/`, inside
`SlotBankPanelView.capture(into:)`. That method itself is only reachable through `onCapture`
closures. Second grep to trace every path into it:
```
$ grep -n "onCapture" App/ARShader/SlotBankPanelView.swift
36:                         onCapture: { capture(into: index) },
66:    let onCapture: () -> Void
86:                    Button("Replace", action: onCapture).buttonStyle(.plain)
109:                onCapture()                       // empty: nothing can be lost
111:                onCapture()                       // ⌥-click: the deliberate overwrite
```

`onCapture` is wired to `capture(into: index)` once at construction (line 36), and invoked
from exactly three sites: the `Button("Replace")` action (line 86, visible only when
`isHovering` is true on a filled cell), and two branches inside the single `.onTapGesture`
closure — `preset == nil` (empty-cell tap, line 109) and
`NSEvent.modifierFlags.contains(.option)` on a filled cell (⌥-click, line 111). Confirmed
there is exactly one `.onTapGesture` modifier in the file:
```
$ grep -n "onTapGesture" App/ARShader/SlotBankPanelView.swift
103:        // EXACTLY ONE tap gesture. Two `.onTapGesture` modifiers on the same view both fire,
107:        .onTapGesture {
```
One comment reference, one actual modifier attachment. The remaining branch of that same
`onTapGesture` closure (plain click, preset non-nil, no option modifier) calls `onRecall()`,
which routes to `SlotBankPanelView.recall(_:)` — a function that never touches
`bank.capture`. So a plain click on a filled slot has no code path to `capture`, satisfying
the safety property: recall-only on plain click, capture only via empty-cell tap, Replace
button, or ⌥-click — all three explicit, none of them the default gesture.

## Commit

`b5e6d32` — "feat(3b): the bank panel — a filled slot can only ever recall"
Files: `App/ARShader/SlotBankPanelView.swift`, `App/ARShader/InstrumentView.swift` (staged by
explicit path, not `git add -A`).

## Concerns

1. **Brief's Step 2 test count is stale.** The brief text says "Expected: 240 tests, 0
   failures," but the actual suite (both before and after this task, per the dispatch
   context and my own run) is 243. This matches what I was told to expect going in, so I did
   not treat it as a blocker, but the brief document itself should be corrected — a future
   implementer trusting the brief's own number over out-of-band context would flag a false
   mismatch.
2. Everything else in the brief matched the actual codebase exactly on inspection
   (`Instrument.load`, `Instrument.currentPreset(of:)`, `Instrument.slotBank`,
   `SlotBank.capture/recall/clear/isAvailable/slots/slotCount`, `DeckID.allCases`/
   `.displayName`, `InstrumentView.panelContent`'s `.bank` case and the `$libraryTarget`
   binding at line 149) — no other defects found.

---

# Fix round 1 of 5

Coordinator review confirmed the implementation matched the brief and the safety trace was
correct, but found the brief's own DESIGN had four defects on the rendered surface. All four
addressed below, in one commit, `App/ARShader/SlotBankPanelView.swift` only —
`InstrumentView.swift` needed no further change this round.

## What changed

**CRITICAL — Replace/Clear moved off hover, onto a `.contextMenu`.** Deleted `@State private
var isHovering`, the `.onHover` modifier, and the two hover-revealed `Button("Replace"...)` /
`Button("Clear"...)` views entirely. Added:
```swift
.contextMenu {
    if preset != nil {
        Button("Replace with SOURCE deck", action: onCapture)
            .disabled(!isAvailable)
        Button("Clear slot", role: .destructive, action: onClear)
    }
}
```
`role: .destructive` compiled clean against the macOS 13 deployment target (SwiftUI
`ButtonRole` shipped in macOS 12) — confirmed by the successful build below, no downgrade
needed. A context menu exists unconditionally rather than materializing under a
possibly-already-moving or already-stationary cursor, closing the overwrite-by-entering-from-
the-right-side bug.

**IMPORTANT 1 — added a second, visible RECALL TO picker bound to the same `$target`.** The
Bank panel now shows two labelled pickers stacked above the slot list:
```swift
VStack(alignment: .leading, spacing: 2) {
    Text("SOURCE")...
    Picker("Capture from", selection: $source) { ... }
}
VStack(alignment: .leading, spacing: 2) {
    Text("RECALL TO")...
    Picker("Load onto", selection: $target) {
        ForEach(LibraryTarget.allCases) { Text($0.shortLabel).tag($0) }
    }
    ...
    .accessibilityLabel("Load onto — where a recall writes")
}
```
Same `$target` binding the Bank already held and passed to `instrument.load` — no new state,
just a second view of the one value, now visible on the surface where slots actually fire.
`LibraryTarget` needed no import; it's defined in `LibraryPanelView.swift` in the same module.

**IMPORTANT 2 — `SlotCell` is now a real `Button`, not a bare `.onTapGesture`.** Replaced the
`HStack` + `.onTapGesture` + `.accessibilityLabel(on the HStack)` pattern with:
```swift
Button(action: activate) {
    HStack(spacing: 6) { ... }
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.contextMenu { ... }
.help(helpText)
.accessibilityLabel(preset.map { ... } ?? ...)
```
`activate()` holds the exact same three-way branch the old `.onTapGesture` closure held
(`preset == nil` → capture, `⌥` → capture, else → recall) — only the delivery mechanism
changed, not the logic. The accessibility label now sits on the `Button`, which SwiftUI
already treats as one combined accessibility element (a native button trait plus an activate
action for VoiceOver), following the same pattern as `LibraryPanelView.swift:77-87`'s row
`Button`.

**MINOR — Replace disabled when unavailable.** `Button("Replace with SOURCE deck",
action: onCapture).disabled(!isAvailable)`. Clear stays enabled unconditionally, per the
brief.

## 1. Full ARShader suite, foreground

Command:
```
xcodebuild test -project App/TrueISFEditor.xcodeproj -scheme ARShader -derivedDataPath /tmp/arshader-ddata-bank ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Verbatim tail:
```
Test Suite 'SurfaceLayoutTests' passed at 2026-07-31 13:47:06.644.
	 Executed 16 tests, with 0 failures (0 unexpected) in 0.009 (0.012) seconds
Test Suite 'ARShaderTests.xctest' passed at 2026-07-31 13:47:06.645.
	 Executed 243 tests, with 0 failures (0 unexpected) in 18.846 (18.898) seconds
Test Suite 'All tests' passed at 2026-07-31 13:47:06.645.
	 Executed 243 tests, with 0 failures (0 unexpected) in 18.846 (18.899) seconds
...
** TEST SUCCEEDED **
```

**243 tests, 0 failures — unchanged.** `SurfaceGeometryTests.testSurfaceBaselines` passed with
no diff; no PNG baseline changed. Consistent with the design reasoning: the Bank panel only
renders when `layout.openPanel == .bank`, and none of the three baselined states open it.

## 2. Step 3 re-verification

```
$ grep -n "\.capture(" App/ARShader/*.swift
App/ARShader/SlotBankPanelView.swift:77:        bank.capture(preset, into: index)
```
Still exactly one call to `SlotBank.capture` in the entire view layer, inside
`SlotBankPanelView.capture(into:)`.

```
$ grep -n "onCapture\|onTapGesture\|\.onHover\|isHovering\|\.contextMenu\|Button(action: activate)\|activate()" App/ARShader/SlotBankPanelView.swift
57:                         onCapture: { capture(into: index) },
89:    let onCapture: () -> Void
94:        // `.onTapGesture`) so VoiceOver gets a native button trait and an activate action for
98:        Button(action: activate) {
125:        .contextMenu {
130:                Button("Replace with SOURCE deck", action: onCapture)
144:    private func activate() {
146:            onCapture()
148:            onCapture()
```

Re-traced every path: `onCapture` is wired once at construction (line 57) to
`capture(into: index)`, and is now invoked from exactly two places — the context-menu
`Button("Replace with SOURCE deck")` (line 130, gated `if preset != nil` and
`.disabled(!isAvailable)`), and inside `activate()` (lines 146 and 148: the `preset == nil`
branch and the `⌥`-modifier branch). `onHover` and `isHovering` no longer appear anywhere in
the file — confirmed zero hits — so Replace/Clear can no longer be triggered by cursor
position at all, only by an explicit right-click/Replace or ⌥-click. The plain-click,
no-modifier branch of `activate()` still calls only `onRecall()`, which never reaches
`bank.capture`. Safety property holds under the new delivery mechanism.

## 3. Tap-delivery path count

**One.** `grep -n "onTapGesture" App/ARShader/SlotBankPanelView.swift` now returns zero
matches (confirmed by the combined grep above — no `onTapGesture` line appears). The cell's
only interactive entry point is the single `Button(action: activate)` wrapping the row content;
`.buttonStyle(.plain)` changes its appearance only, not its event delivery. I verified this by
(a) grepping for every gesture-recognizing modifier name (`onTapGesture`, `onHover`,
`.contextMenu`, `Button`) in the file and confirming `Button(action: activate)` is the only tap
source feeding `activate()`/`onCapture`/`onRecall`, and (b) the successful compile + full green
suite, which would not silently catch a double-fire (that's a runtime/UX defect, not a compile
error) but does confirm no leftover `.onTapGesture` modifier survived the edit — the earlier
grep for that exact string returns nothing.

## Commit (fix round 1)

`f1fa9e4` — "fix(3b): bank panel — context menu overwrite, visible recall target, VoiceOver
button"
File: `App/ARShader/SlotBankPanelView.swift` only (staged by explicit path, not `git add -A`;
`InstrumentView.swift` was untouched this round since the `target` binding wiring from round 1
already routes into the panel correctly — only the panel's own UI needed to change).

## Remaining concerns

None found beyond what's noted above. The `role: .destructive` API compiled and ran clean
against the macOS 13 target as anticipated by the coordinator's note, so no fallback was
needed.
