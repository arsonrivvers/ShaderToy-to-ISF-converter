# Task 11 verification report

Date: 2026-07-26
Status: STAGED, pending Conner's ordinary-interaction acceptance

## Audit repairs

The first Task 11 audit found six fix-first defects. Each behavior was captured RED before the
production repair:

- Shadertoy readiness now trusts only `shadertoy.com` and subdomains ending in
  `.shadertoy.com`; both ready and challenge states on `evilshadertoy.com` are rejected.
- Lineage and Activity text use the scalable 14-point-minimum Remix text policy.
- Salvage controls use stable semantic identity instead of per-render UUIDs.
- The live-preview cap reserves renderer surfaces, so rendering one node in both canvas and
  inspector consumes two budget slots.
- Focused-child commands are disabled without a focused child and expose an accessible reason.
- Activity announcements safely skip a missing application instead of force-unwrapping `NSApp`.

Native review then exposed a clipped narrow-window empty-state instruction. Two additional
RED/GREEN iterations made its text vertically flexible and made the focusable canvas fill the
available workspace height. The final capture is `/tmp/remix-task11-remix-empty-final3.png`.

Focused evidence:

- `/tmp/remix-task11-fixes-red.log`: expected missing-policy/API RED.
- `/tmp/remix-task11-combined-green.log`: 38 tests, 0 failures.
- `/tmp/remix-task11-empty-red.log` then `/tmp/remix-task11-empty-green.log`.
- `/tmp/remix-task11-canvas-fill-red.log` then `/tmp/remix-task11-canvas-fill-green.log`.
- Renderer-budget repair commit `f47955e`: targeted 2/2 and model suite 56/56.

## Fresh final verification

App suite:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Result: `496` executed, `3` live-network tests skipped, `0` failures,
`** TEST SUCCEEDED **`. Log: `/tmp/remix-task11-app-tests-final3.log`.

Converter kit:

```bash
cd ShadertoyISFKit
swift test
```

Result: `312` executed, `0` failures. Log: `/tmp/remix-task11-kit-tests-final3.log`.

Release-shaped build:

```bash
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -derivedDataPath ./ddata -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Result: `** BUILD SUCCEEDED **`. Log: `/tmp/remix-task11-build-final3.log`.

Fresh-binary proof:

```bash
strings App/ddata/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib \
  | rg -F 'Choose a starting shader'
file App/ddata/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib
```

Result: string present; Mach-O arm64. Staged bundle:
`App/ddata/Build/Products/Debug/TrueISFEditor.app`, version `0.1.0` build `1`.

## Defensive and corpus checks

- The new readiness boundary is exact-host/suffix-delimited and covered against a lookalike host.
- The Remix implementation adds no Cloudflare click, AXPress, CGEvent, or verification-event
  synthesis. The older corpus harvester's browse-page `click()` is outside the verification path
  and unchanged by this plan.
- `git diff --name-only 1facc2d..HEAD -- ShadertoyISFKit corpus scripts
  docs/corpus-analysis-2026-07-09-pixel-baseline.txt` returned no paths. Therefore the Plan 3
  native corpus result at `1facc2d` remains the converter boundary: compile `74/78`, pixel
  `69/78`, with no converter/corpus changes stacked by the Remix work.
- Corpus preflight assets remain present: `corpus/discovery-ids.txt`,
  `docs/corpus-analysis-2026-07-09-pixel-baseline.txt`, executable `scripts/corpus-run.sh`,
  `xcodebuild`, and `xcodegen`.

## Native review and remaining acceptance

The fresh staged app launched successfully, opened Remix Studio through its ordinary
Command-Shift-R shortcut, and produced an exact 900-point-window capture. The final empty-state
capture shows the three-zone shell, narrow-layout lineage collapse, non-clipped guidance, disabled
unavailable parent actions, activity drawer, and clear next action.

Not performed automatically:

- no Cloudflare checkbox interaction or accessibility press;
- no paid provider generation;
- no fabricated populated/failure/session states;
- no claim that VoiceOver and ordinary mouse interaction passed on Conner's device.

Conner must still complete the Task 11 ordinary-interaction checklist: real Parent A/B, five-child
generation and stop, Grid/2-up/Hero, favorite/promote/retry/open, keyboard zone operations, relaunch
restore, a real Shadertoy human-verification handoff with exact-slot resume, and mouse/keyboard/
VoiceOver crash checks. Until then the release status is STAGED, not confirmed.

## Final review verdicts

- Mechanic: PASS. The six Task 11 findings are closed: strict trusted-host matching, scalable
  14-point Lineage/Activity text, stable salvage identities, renderer reservations counted by
  `(nodeID, surface)`, disabled focused-child actions with an explicit reason, and nil-safe
  accessibility announcements.
- Client Success: PASS/STAGED. The native 900-point empty-state capture is centered, legible, and
  unclipped. Populated layouts, ordinary mouse/keyboard traversal, VoiceOver, relaunch restore,
  renderer behavior, and the real human-verification return remain Conner acceptance items.
- CSO: SHIP. The trusted-host boundary rejects sibling and lookalike domains; the verification path
  contains no synthetic click, AXPress, CAPTCHA bypass, private-data leg, or exfiltration path.
- Coach: PROCEED TO STAGED. No known code-level fix-first defect remains; do not promote beyond
  STAGED until Conner completes the ordinary-interaction checklist.
