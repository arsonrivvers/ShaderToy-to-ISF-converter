---
title: ARShader — responsive surface layout
date: 2026-08-01
status: draft — deferred until milestone 2 is merged
target_repo: ShaderToy-to-ISF-converter
depends_on: Milestone 2 phase 3c merged and signed on device
---

# Responsive surface layout

Filed 2026-08-01 mid-phase-3c, after the operator asked: *"Can all of this just be scalable by
viewport by percentage like we would with a website? Seems logical."*

It is logical, and it is most of the answer. This spec records what to adopt, what not to, and the
evidence for both — because this surface has now been burned once in each direction.

## The two failures that motivate this

**Pure percentage, phase 3c task 3.** The slot cell was `.frame(minWidth: 96, maxWidth: .infinity)`
— fill the available width, i.e. 1/8 of the viewport — with `.aspectRatio(16/9, .fit)`. On a real
window that made each cell ~207pt wide, and because the aspect ratio couples the axes, **width
percentage drove height**: ~116pt per row, two rows ≈ 244pt. The operator's reaction on device: *"I
can see us shrinking this bar a lot."* Vertical space is the scarce resource on this surface — the
monitor row is above and the deck strips below — and a percentage cannot express *"grow with the
window but do not eat my monitors."*

**Pure fixed, phase 3c task 4.** The fix went to `.frame(width: 96, height: 54)` — exact, forever.
That solved the complaint and introduced its opposite: a permanently tiny strip with dead space
beside it on a large display. The task reviewer flagged it in the same round: *"cell area drops
~4.6× in one step to a size never seen on device."*

Neither extreme is right. The web solved this and the answer is not percentage — it is
**`clamp(min, preferred, max)`**, plus **breakpoints** where proportional scaling stops working and
the layout must change shape instead.

## What SwiftUI already gives us

`.frame(minWidth:idealWidth:maxWidth:)` **is** `clamp()`. The tooling was never missing; both
failures came from using only two of the three values — a floor with infinite growth, then an exact
value with neither.

## What is genuinely absolute on a native surface, and can never be a percentage

1. **Legibility floors.** A 9pt monospaced shader name needs its points regardless of window size.
   On macOS, text scales with the user's system text setting, **not** with the window — so 5% of a
   1280pt window is an unreadable cell and 5% of 3840pt is fine. A percentage cannot say "never
   smaller than readable."
2. **Hit targets.** This surface has already shipped the bug: in phase 3b, cells computed to
   **31.1pt against their own 32pt floor**, so hit areas overlapped and an edge click fired the
   *neighbouring* slot. On a bank the operator fires by position mid-set, that is unacceptable, and
   a raw percentage reintroduces it at every small window size.
3. **Intrinsic control widths.** A segmented picker showing `MST FX` needs the width of that text; a
   slider needs usable travel; a numeric field needs its digits. These have natural sizes that a
   ratio cannot invent.

## What percentage-with-clamps SHOULD govern

- **Slot cells** — floor at the legibility/hit-target minimum, grow with the window, stop at a
  ceiling so the strip never dominates the surface. This is the one piece pulled forward into phase
  3c (task 4C); everything else below waits.
- **Region proportions** — panel / deck strips / mixer as clamped ratios rather than the current
  fixed `panelWidth` + `mixerWidth` + `stripsMinWidth` arithmetic.
- **Monitor tile sizing** within the content-sized monitor row.

## Breakpoints, where scaling stops being enough

Below some width the answer is not smaller controls, it is a **different layout**. Candidates:

- Slot strip below its comfortable width → show names instead of thumbnails, rather than
  scroll-forever.
- Panel below its floor → overlay the surface instead of displacing it.
- Deck strips below theirs → stack rather than sit side by side.

## Why this also fixes the `minWindowWidth` fragility

`SurfaceMetrics` currently composes a window minimum by summing fixed region widths
(`reservedSurfaceWidth = rail + dividers + stripsMinWidth + mixerWidth`). Phase 3c task 4 proved how
brittle that is: a single test-determinism change moved one summand and cascaded
`minWindowWidth` 1180 → 1390, which would have made the app **unfittable on a 13"/14" MacBook at
common scaled text settings** — while `OutputDestination.floating` puts the projector preview in a
second window on that same screen. The cascade was reverted.

A clamped-range model removes the whole failure class: regions declare a range, the surface
distributes what exists, and no single content measurement can dictate a global minimum. See the
memory note `ideal-width-is-not-minimum-width` for the specific trap (`.fixedSize(horizontal:)`
measures *ideal* width — a `Text`'s full unwrapped single-line width — which is not a minimum and
must never be used as one).

## Out of scope

- Anything shipping before milestone 2 is merged and signed. Reworking `SurfaceMetrics` while
  drag-and-drop is half-built would move the layout under an unfinished feature.
- The slot-cell clamp specifically — pulled forward into phase 3c task 4C, deliberately narrow.

## Open question for the operator

The breakpoint set is a product decision, not an engineering one: at what window size should the
bank stop showing pictures and go back to names? That wants his eyes on real sizes, not a number
chosen here.
