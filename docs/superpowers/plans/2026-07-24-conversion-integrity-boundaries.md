# Conversion Integrity Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every emitted ISF header safe against metadata containing `*/`, and surface every Shadertoy uniform that survives per-pass rewriting as a pass-scoped conversion warning.

**Architecture:** Put block-comment safety at `ISFDocument.fileText`, the final boundary shared by every header producer, using JSON's lossless escaped-slash form. Extend the existing `UniformRewriter.unresolvedUniformUses` tripwire at the point immediately after each isolated pass body is rewritten, preserving the converter's ordered pipeline and Common behavior.

**Tech Stack:** Swift 6, Foundation `JSONSerialization`, XCTest, Swift Package Manager, TrueISFEditor's native corpus harness.

## Global Constraints

- Scope is limited to ROADMAP conversion items 1 and 2. Do not include pixel-BLACK residue work, keyboard-texture emulation, sampler monomorphization, UI changes, or broad cleanup.
- Preserve decoded metadata exactly. Escape literal `*/` as JSON-equivalent `*\/`; do not insert visible spaces or discard content.
- Header safety must be enforced at `ISFDocument.fileText`, not only at the current Shadertoy metadata producer.
- Per-pass unresolved-uniform detection runs immediately after `UniformRewriter.rewriteScoped` and before channel stubs or sampler rewriting.
- Detection is diagnostic, not fatal: emit `.warning` with the exact render-pass name as context and continue conversion.
- Reuse `UniformRewriter.unresolvedUniformUses`; do not add a second detector or change parameter-shadow behavior.
- Preserve the ordered conversion pipeline documented in `ISFConverter.convert`.
- Use TDD: capture RED before implementation, then GREEN.
- Full corpus compile verdicts must remain identical by ID to `docs/corpus-analysis-2026-07-09-pixel-baseline.txt`; pixel result must remain at least 64/78 OK-or-STATIC.
- Stop and diagnose any corpus regression. Do not stack another conversion change on a broken render state.
- Do not push. The standing `null_signal` courtesy-heads-up gate still applies to all local TrueISFEditor commits. **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**

---

### Task 1: Lossless ISF header comment safety

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFDocument.swift:10-16`
- Modify: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ISFDocumentTests.swift:4-15`
- Modify: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ISFConverterTests.swift:11-26`

**Interfaces:**
- Consumes: `ISFDocument.init(headerJSON:glslBody:)` and `ISFDocument.fileText`.
- Produces: `ISFDocument.fileText: String` with exactly one literal `*/`, the final ISF wrapper terminator, while JSON-decoded metadata remains exactly equal as a Swift `String`.

- [ ] **Step 1: Add direct boundary tests that fail on literal comment terminators**

Append these tests to `ISFDocumentTests`:

```swift
func test_serialize_escapesLiteralCommentTerminatorsWithoutChangingMetadata() throws {
    let original = "one */ two */ three"
    let doc = ISFDocument(
        headerJSON: #"{"DESCRIPTION":"one */ two */ three"}"#,
        glslBody: "void main() {}")

    let text = doc.fileText
    XCTAssertEqual(text.components(separatedBy: "*/").count - 1, 1,
                   "only the final ISF wrapper terminator may remain literal")

    let headerStart = try XCTUnwrap(text.range(of: "/*")).upperBound
    let headerEnd = try XCTUnwrap(text.range(of: "*/")).lowerBound
    let encoded = String(text[headerStart..<headerEnd])
    let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
    XCTAssertEqual(object["DESCRIPTION"] as? String, original)
}

func test_serialize_doesNotDoubleEscapeAlreadySafeJSON() {
    let doc = ISFDocument(
        headerJSON: #"{"DESCRIPTION":"already *\/ safe"}"#,
        glslBody: "void main() {}")

    XCTAssertTrue(doc.fileText.contains(#""DESCRIPTION":"already *\/ safe""#))
    XCTAssertFalse(doc.fileText.contains(#"*\\/"#),
                   "an already escaped slash must not gain a second backslash")
}
```

- [ ] **Step 2: Run the direct tests and capture RED**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ISFDocumentTests
```

Expected: `test_serialize_escapesLiteralCommentTerminatorsWithoutChangingMetadata` fails because the current output contains three literal `*/` sequences. The existing wrapper test and already-safe test pass.

- [ ] **Step 3: Escape literal terminators at the final wrapper boundary**

Replace `ISFDocument.fileText` with:

```swift
public var fileText: String {
    let inner = headerJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripped: String
    if inner.hasPrefix("{") && inner.hasSuffix("}") {
        stripped = String(inner.dropFirst().dropLast())
    } else {
        stripped = inner
    }
    // ISF embeds JSON inside a block comment. JSON's escaped slash decodes identically but
    // prevents metadata from closing the wrapper early. Already-safe `*\/` has no literal
    // `*/`, so this is idempotent.
    let commentSafe = stripped.replacingOccurrences(of: "*/", with: #"*\/"#)
    return "/*{\(commentSafe)}*/\n\n\(glslBody)\n"
}
```

- [ ] **Step 4: Run the direct tests and confirm GREEN**

Run:

```bash
cd ShadertoyISFKit
swift test --filter ISFDocumentTests
```

Expected: all `ISFDocumentTests` pass.

- [ ] **Step 5: Add a converter-level production-path regression**

Append this test to `ISFConverterTests`:

```swift
func test_metadataCommentTerminator_roundTripsThroughConverter() throws {
    let original = "Title close */ description close */ preserved"
    let image = RenderPass(
        inputs: [],
        outputs: [PassOutput(id: "out0", channel: 0)],
        code: "void mainImage(out vec4 O, vec2 I){ O = vec4(1.0); }",
        name: "Image",
        type: .image)
    let shader = Shader(
        info: Info(id: "safe01", name: "fallback */ title",
                   username: "tester", description: original),
        renderpass: [image])

    let (doc, _) = ISFConverter.convert(shader)
    let text = doc.fileText
    XCTAssertEqual(text.components(separatedBy: "*/").count - 1, 1)

    let headerStart = try XCTUnwrap(text.range(of: "/*")).upperBound
    let headerEnd = try XCTUnwrap(text.range(of: "*/")).lowerBound
    let encoded = String(text[headerStart..<headerEnd])
    let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
    XCTAssertEqual(object["DESCRIPTION"] as? String, original)

    let fallbackTitle = "fallback */ title"
    let fallbackShader = Shader(
        info: Info(id: "safe02", name: fallbackTitle,
                   username: "tester", description: nil),
        renderpass: [image])
    let (fallbackDoc, _) = ISFConverter.convert(fallbackShader)
    let fallbackText = fallbackDoc.fileText
    XCTAssertEqual(fallbackText.components(separatedBy: "*/").count - 1, 1)
    let fallbackStart = try XCTUnwrap(fallbackText.range(of: "/*")).upperBound
    let fallbackEnd = try XCTUnwrap(fallbackText.range(of: "*/")).lowerBound
    let fallbackEncoded = String(fallbackText[fallbackStart..<fallbackEnd])
    let fallbackObject = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(fallbackEncoded.utf8)) as? [String: Any])
    XCTAssertEqual(fallbackObject["DESCRIPTION"] as? String, fallbackTitle)
}
```

This test covers the real `Shader.info.description → HeaderBuilder → ISFDocument.fileText` path. Foundation currently escapes the slash during header construction, so its value is regression coverage after the direct boundary test has supplied the RED.

- [ ] **Step 6: Run focused metadata tests**

Run:

```bash
cd ShadertoyISFKit
swift test --filter 'ISFDocumentTests|HeaderBuilderTests|ISFConverterTests.test_metadataCommentTerminator'
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add \
  ShadertoyISFKit/Sources/ShadertoyISFKit/ISFDocument.swift \
  ShadertoyISFKit/Tests/ShadertoyISFKitTests/ISFDocumentTests.swift \
  ShadertoyISFKit/Tests/ShadertoyISFKitTests/ISFConverterTests.swift
git commit -m "fix(conversion): protect ISF headers from metadata terminators" \
  -m "Co-Authored-By: OpenAI Codex <noreply@openai.com>"
```

---

### Task 2: Per-pass unresolved-uniform tripwire and conversion close-out

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift:66-75`
- Modify: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ISFConverterTests.swift`
- Modify: `docs/ROADMAP.md:98-105`

**Interfaces:**
- Consumes: `UniformRewriter.rewriteScoped(_:) -> String`, `UniformRewriter.unresolvedUniformUses(_:) -> [String]`, `ConversionWarning.init(severity:message:context:)`, and `RenderPass.name`.
- Produces: one `.warning` per unique unresolved uniform name per offending pass, with `context == pass.name`; Common warnings remain unchanged.

- [ ] **Step 1: Add failing single-pass, multipass, and false-positive tests**

Append these tests to `ISFConverterTests`:

```swift
func test_perPassUnresolvedUniform_emitsPassScopedWarning() {
    let shader = ShaderFactory.singlePass(
        imageCode: """
            void mainImage(out vec4 O, vec2 I) {
                vec3 nativeSize = iChannelResolution;
                O = vec4(nativeSize.xy, 0.0, 1.0);
            }
            """)

    let (_, warnings) = ISFConverter.convert(shader)
    let tripwires = warnings.filter {
        $0.message.contains("iChannelResolution survived uniform rewriting")
    }
    XCTAssertEqual(tripwires.count, 1, "\(warnings)")
    XCTAssertEqual(tripwires[0].severity, .warning)
    XCTAssertEqual(tripwires[0].context, "Image")
}

func test_perPassUnresolvedUniform_namesOnlyOffendingPass() {
    let buffer = RenderPass(
        inputs: [],
        outputs: [PassOutput(id: "buf0", channel: 0)],
        code: "void mainImage(out vec4 O, vec2 I){ O = vec4(1.0); }",
        name: "Buffer A",
        type: .buffer)
    let image = RenderPass(
        inputs: [],
        outputs: [PassOutput(id: "out0", channel: 0)],
        code: """
            void mainImage(out vec4 O, vec2 I) {
                vec3 nativeSize = iChannelResolution;
                O = vec4(nativeSize.xy, 0.0, 1.0);
            }
            """,
        name: "Image",
        type: .image)
    let shader = Shader(
        info: Info(id: "tripwire", name: "Tripwire", username: nil, description: nil),
        renderpass: [buffer, image])

    let (_, warnings) = ISFConverter.convert(shader)
    let contexts = warnings
        .filter { $0.message.contains("survived uniform rewriting") }
        .compactMap(\.context)
    XCTAssertEqual(contexts, ["Image"], "\(warnings)")
}

func test_perPassUnresolvedUniform_parameterShadow_remainsUnwarned() {
    let shader = ShaderFactory.singlePass(imageCode: """
        vec3 nativeSize(vec3 iChannelResolution) { return iChannelResolution; }
        void mainImage(out vec4 O, vec2 I) {
            O = vec4(nativeSize(vec3(1.0)).xy, 0.0, 1.0);
        }
        """)

    let (_, warnings) = ISFConverter.convert(shader)
    XCTAssertFalse(warnings.contains {
        $0.message.contains("iChannelResolution survived uniform rewriting")
    }, "\(warnings)")
}
```

- [ ] **Step 2: Run the converter tests and capture RED**

Run:

```bash
cd ShadertoyISFKit
swift test --filter 'ISFConverterTests.test_perPassUnresolvedUniform'
```

Expected: the first two tests fail because no per-pass tripwire warnings exist. The parameter-shadow test passes.

- [ ] **Step 3: Add the tripwire immediately after scoped per-pass rewriting**

In `ISFConverter.convert`, directly after:

```swift
code = UniformRewriter.rewriteScoped(code)
```

insert:

```swift
// Tripwire parity with Common: if a detectable Shadertoy uniform survives the
// scope-aware rewrite outside a parameter-shadowed position, retain the best-effort
// conversion but identify the originating pass loudly.
for name in UniformRewriter.unresolvedUniformUses(code) {
    warnings.append(ConversionWarning(
        severity: .warning,
        message: "\(name) survived uniform rewriting in pass \(pass.name) (no ISF mapping applies at this use) — the shader may fail to compile. Verify or rework the use.",
        context: pass.name))
}
```

Do not move the existing Common tripwire and do not run the detector on the later merged GLSL.

- [ ] **Step 4: Run the focused tripwire tests and confirm GREEN**

Run:

```bash
cd ShadertoyISFKit
swift test --filter 'ISFConverterTests.test_perPassUnresolvedUniform|UniformRewriterScopedTests'
```

Expected: all selected tests pass. The result proves pass context, multipass isolation, Common detector behavior, unique-name behavior, and parameter-shadow suppression.

- [ ] **Step 5: Run the complete kit suite**

Run:

```bash
cd ShadertoyISFKit
swift test
```

Expected: all tests pass with zero failures. The prior handoff baseline was 306 passed; the total must increase by the tests added in Tasks 1 and 2.

- [ ] **Step 6: Run the live corpus pre-flight assertions**

Hypothesis: the environment can exercise the exact native build-and-render boundary before the human-readable corpus gate begins.

Run:

```bash
test -f corpus/discovery-ids.txt
test -f docs/corpus-analysis-2026-07-09-pixel-baseline.txt
test -x scripts/corpus-run.sh
command -v xcodebuild
command -v xcodegen
```

Expected: every command exits 0 and prints the installed paths for `xcodebuild` and `xcodegen`. If any assertion fails, stop and repair the environment before running the corpus.

- [ ] **Step 7: Run the full native corpus gate**

Run from the repository root:

```bash
./scripts/corpus-run.sh --build
```

Expected:

- the arm64 TrueISFEditor build succeeds;
- the final report is written to `${TMPDIR:-/tmp/}conversion-corpus-report.txt`;
- the summary remains at least `compile 74/78 · pixel 64/78 OK`;
- any increased warning counts are attributable to the new per-pass tripwire.

- [ ] **Step 8: Compare every compile verdict by ID against the pinned baseline**

Run:

```bash
diff \
  <(grep -E $'\t(OK|FAIL)\t?' "${TMPDIR:-/tmp/}conversion-corpus-report.txt" |
      awk -F'\t' '{print $1"\t"$2}' | sort) \
  <(grep -E $'\t(OK|FAIL)\t?' docs/corpus-analysis-2026-07-09-pixel-baseline.txt |
      awk -F'\t' '{print $1"\t"$2}' | sort)
```

Expected: no output and exit 0. This compares the complete verdict set without truncation. Any output is a blocking regression that must be diagnosed before proceeding.

Then run:

```bash
awk -F'\t' '
  BEGIN { ok = 0; static = 0 }
  $2 == "OK" && $3 == "pixel=OK" { ok++ }
  $2 == "OK" && $3 == "pixel=STATIC" { static++ }
  END {
    print "pixel acceptable:", ok + static, "(OK=" ok ", STATIC=" static ")"
    exit ((ok + static) >= 64 ? 0 : 1)
  }
' "${TMPDIR:-/tmp/}conversion-corpus-report.txt"
```

Expected: `pixel acceptable: 64` or higher and exit 0.

- [ ] **Step 9: Mark only ROADMAP conversion items 1 and 2 landed**

Replace the first two conversion items in `docs/ROADMAP.md` with:

```markdown
1. ✅ **Sanitize Shadertoy metadata into the ISF header** — landed in Plan 3
   (2026-07-24): `ISFDocument.fileText` losslessly escapes literal block-comment terminators
   at the final wrapper boundary; direct and converter-path regressions pin exact round-tripping.
2. ✅ **Wire the unresolved-uniform tripwire for per-pass bodies** — landed in Plan 3
   (2026-07-24): every isolated pass runs `UniformRewriter.unresolvedUniformUses` immediately
   after scoped rewriting and emits a pass-named warning for survivors.
```

Leave conversion items 3-7 unchanged.

- [ ] **Step 10: Run final validation**

Run:

```bash
cd ShadertoyISFKit
swift test
cd ..
git diff --check
git status --short
```

Expected:

- the complete kit suite passes with zero failures;
- `git diff --check` prints nothing and exits 0;
- only `ISFConverter.swift`, `ISFConverterTests.swift`, and `docs/ROADMAP.md` remain modified since the Task 1 commit;
- no source file outside Plan 3 scope is changed.

- [ ] **Step 11: Commit Task 2**

Run:

```bash
git add \
  ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift \
  ShadertoyISFKit/Tests/ShadertoyISFKitTests/ISFConverterTests.swift \
  docs/ROADMAP.md
git commit -m "fix(conversion): flag unresolved uniforms in every pass" \
  -m "Co-Authored-By: OpenAI Codex <noreply@openai.com>"
```

Do not commit the generated `/tmp` corpus report and do not push.

---

## Plan Completion Gate

After both tasks:

1. Confirm the two implementation commits exist after plan commit `6f1c957`.
2. Confirm `git status --short` is empty.
3. Confirm focused RED and GREEN evidence was captured for each task.
4. Confirm the complete kit suite passes.
5. Confirm the native corpus build passed and the complete compile verdict diff returned zero.
6. Confirm pixel acceptable count is at least 64.
7. Confirm ROADMAP items 1 and 2 alone are marked landed.
8. Run the `gate` skill before declaring completion.
9. No UI changed, so Mechanic and Client Success reviews are not triggered.
10. Do not push until Conner confirms the `null_signal` courtesy heads-up. **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**
