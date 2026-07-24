# Conversion Integrity Boundaries Design

**Date:** 2026-07-24

**Status:** Approved design

## Goal

Close the two conversion-integrity gaps tracked as ROADMAP conversion items 1 and 2:

1. An ISF header must remain one valid block comment even when metadata contains `*/`.
2. A Shadertoy uniform that survives rewriting in any render-pass body must produce a loud,
   pass-scoped conversion warning instead of silently reaching a black or uncompilable import.

This is Plan 3. It is limited to these two correctness boundaries. It does not include the later
pixel-BLACK residue classes, keyboard-texture emulation, sampler monomorphization, or cleanup work.

## Existing Behavior

`HeaderBuilder` serializes metadata through `JSONSerialization`. The Foundation version currently
used by the app emits a slash in `*/` as the equivalent JSON escape `*\/`, but that safety property
is implicit, platform-dependent behavior with no test at the final comment-wrapper boundary.
`ISFDocument.fileText` accepts raw header JSON from any producer and wraps it directly in `/*{…}*/`.

`ISFConverter` calls `UniformRewriter.unresolvedUniformUses` after rewriting Common code. Per-pass
bodies call the same scope-aware uniform rewriter but do not run the tripwire. A surviving use such
as bare, unindexed `iChannelResolution` can therefore reach the emitted shader without a diagnostic.

## Design

### 1. Enforce comment safety at `ISFDocument.fileText`

`ISFDocument.fileText` is the final boundary that turns raw JSON into an ISF block comment. Before
adding the outer `/*{` and `}*/`, it will replace every literal `*/` sequence remaining in
`headerJSON` with `*\/`.

`\/` and `/` decode to the same JSON string value. This keeps the title, description, credit, and
any future metadata semantically unchanged while making an early block-comment terminator
impossible. Already escaped `*\/` text contains no literal `*/`, so this operation is idempotent and
does not double-escape safe JSON.

The invariant belongs at this boundary rather than only in `HeaderBuilder` because:

- every current and future header producer passes through `ISFDocument.fileText`;
- callers may construct `ISFDocument` with raw header JSON that did not come from Foundation;
- the emitted file, not an intermediate dictionary, is the artifact that must be safe.

`HeaderBuilder` remains responsible for producing valid JSON. It does not gain metadata-specific
replacement rules.

### 2. Run the unresolved-uniform tripwire per pass

Immediately after each pass body is transformed by `UniformRewriter.rewriteScoped`, the converter
will call `UniformRewriter.unresolvedUniformUses` on that rewritten, still-isolated body.

For each returned uniform name, append one `.warning` `ConversionWarning` with:

- the render pass's existing `pass.name` as `context`;
- wording parallel to the existing Common warning;
- an explicit statement that no ISF mapping applies at that use and compilation may fail.

The converter continues through sampler rewriting and later stages. This is a diagnostic tripwire,
not a conversion abort: the user still receives the best available shader and can inspect the
pass-scoped warning.

Detection stays immediately after `rewriteScoped` because this is the first point where “survived
rewriting” is meaningful and the last point before later transformations can obscure the originating
pass. The existing `unresolvedUniformUses` implementation remains the single detector for Common
and per-pass bodies, including its parameter-shadow false-positive protection.

## Data Flow

For each render pass:

1. Splice continuations and apply the whole-shader injected-name guard.
2. Resolve channel bindings and scan original detectable uses.
3. Run `UniformRewriter.rewriteScoped`.
4. Run `UniformRewriter.unresolvedUniformUses` on the rewritten pass body.
5. Append pass-scoped warnings for survivors.
6. Continue through channel stubs, sampler rewriting, and the existing ordered pipeline.

For the emitted header:

1. Build or receive valid raw header JSON.
2. Strip only the outer JSON braces as today.
3. Escape any remaining literal `*/` as `*\/`.
4. Wrap the safe JSON in the single ISF `/*{…}*/` comment.

## Error and Warning Semantics

- Header protection is deterministic and silent because decoded metadata is unchanged.
- A per-pass unresolved uniform is a warning, matching Common behavior. It is not promoted to an
  error because the tripwire identifies an unsupported use, while later compilation remains the
  authoritative validity check.
- Warning context must use the exact pass name supplied by `PassBuilder`.
- Multiple different unresolved names in one pass produce one warning each.
- Repeated uses of the same unresolved name in one pass produce one warning because
  `unresolvedUniformUses` returns unique names.
- Parameter-shadowed names remain unreported.

## Tests

### Header boundary

- Construct an `ISFDocument` directly with raw header JSON whose description contains one and
  multiple literal `*/` sequences.
- Assert the emitted header contains no literal early terminator before its final closing `*/`.
- Parse the emitted JSON object and assert the decoded description exactly matches the original
  text, including every `*/`.
- Assert calling the boundary with already escaped `*\/` JSON does not double-escape it.
- Add a converter-level metadata regression using Shadertoy description/title fallback so the
  production path is covered, not only the boundary helper.

### Per-pass tripwire

- Convert a single render pass containing a known unresolved bare uniform use and assert a warning
  names the uniform and carries the pass name as context.
- Convert multiple passes and assert only the offending pass is named.
- Assert a parameter-shadowed spelling produces no unresolved-uniform warning.
- Preserve the existing Common tests and add a parity assertion if needed to pin shared wording and
  severity.

### Verification

- Run focused `ISFDocument`, `HeaderBuilder`, `UniformRewriterScoped`, and `ISFConverter` tests.
- Run the complete `ShadertoyISFKit` test suite.
- Run `./scripts/corpus-run.sh --build` and compare against the checked-in/current baseline:
  compile pass-list must not regress, and every new warning must be attributable to the new tripwire.
- Run `git diff --check`.

## Acceptance Criteria

- No emitted ISF header can contain a literal `*/` before the one final wrapper terminator, even
  when `ISFDocument` receives manually constructed raw JSON.
- Decoding the protected JSON preserves metadata exactly.
- Every unresolved uniform detected after per-pass scoped rewriting produces a warning with the
  correct pass context.
- Common behavior and parameter-shadow suppression remain unchanged.
- Focused tests, full kit tests, corpus comparison, and whitespace validation pass.
- No UI, app workflow, dependency, environment-variable, or unrelated conversion-stage change is
  included.
