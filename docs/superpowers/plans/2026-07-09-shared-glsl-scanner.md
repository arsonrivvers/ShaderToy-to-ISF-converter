# Shared GLSLScanner + Rewriter Protocol Implementation Plan (Plan-of-record Task 3.2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One shared GLSL char-scanner primitive replacing six divergent hand-rolled walkers, then the design fixes it unlocks: C5+M20 scope-aware uniform rewriting, M18 Common-aware macro scoping, N2 comment-safe reserved renames, M1 per-pass output init, M2 multi-declarator globals, N1 return-shape convergence.

**Architecture:** `GLSLScanner.scan` walks UTF-16 units emitting `(index, unit, State{comment/directive flags, brace/paren depth})`; helpers (`strip`, `braceDepth`, `statementEnd`, `braceMatchEnd`, `splitArgs`) are thin queries over that single machine. Consumers migrate one at a time behind their existing tests; the "masked text" idiom (match structure on `strip`-blanked code, slice/edit the original at the same UTF-16 offsets) replaces per-consumer comment state machines. Design changes land after all migrations, each corpus-gated.

**Tech Stack:** Swift 5 / SwiftPM (`ShadertoyISFKit`), XCTest, NSRegularExpression (UTF-16 offsets throughout), xcodebuild app harness, `scripts/corpus-run.sh`.

**Spec:** `docs/superpowers/specs/2026-07-09-shared-glsl-scanner-design.md`

## Global Constraints

- **Gate after every task marked [CORPUS]:** kit tests green AND `./scripts/corpus-run.sh --build` — compile pass-list **identical by ID** to `docs/corpus-analysis-2026-07-09-pixel-baseline.txt` (BLACK→OK flips are improvements and allowed; any OK→FAIL or pass-list change blocks: revert the step, diagnose, do not stack changes on a regression).
- Kit tests: `cd ShadertoyISFKit && swift test 2>&1 | tail -3` → expect `Executed N tests, with 0 failures` (N ≥ 236 and growing).
- App tests (only where noted): `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
- Corpus baseline compare (run after every corpus run):
  ```bash
  diff <(grep -E $'\t(OK|FAIL)\t?' "${TMPDIR:-/tmp/}conversion-corpus-report.txt" | awk -F'\t' '{print $1"\t"$2}' | sort) \
       <(grep -E $'\t(OK|FAIL)\t?' docs/corpus-analysis-2026-07-09-pixel-baseline.txt | awk -F'\t' '{print $1"\t"$2}' | sort)
  ```
  Acceptable diff lines: a triaged BLACK id moving `FAIL` → `OK`. Anything else blocks.
- **Never `git add -A`** (concurrent sessions may edit `App/`); add files explicitly.
- All offsets are UTF-16 (`NSString`/`NSRange`); never mix with `String.Index` math.
- Commit after every task; message prefix `feat(scanner):` / `fix(conv):` / `refactor(kit):` as fits, with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Triage — attribute the 10 BLACK, re-check the 14 STATIC

**Files:**
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift` (corpus block, ~line 160: gate-times env override)
- Modify: `App/TrueISFEditor/PixelGate.swift` (add `parseTimes`)
- Test: `App/TrueISFEditorTests/PixelGateTests.swift`
- Create: `corpus/black-ids.txt`, `corpus/static-ids.txt`
- Modify (results): this plan file, "Task 1 Results" section below

**Interfaces:**
- Produces: `PixelGate.parseTimes(_ raw: String?) -> [Double]?` (nil unless raw parses to ≥1 time); `SHADERTOY_DEBUG_GATE_TIMES="0,0.75,2,4,8"` env override honored by the corpus harness; attribution table binding exit criteria.

- [ ] **Step 1: Write the failing tests** (append to `PixelGateTests.swift`):

```swift
    // MARK: - SHADERTOY_DEBUG_GATE_TIMES parsing (triage affordance)

    func test_parseTimes_nilAndGarbage_returnNil() {
        XCTAssertNil(PixelGate.parseTimes(nil))
        XCTAssertNil(PixelGate.parseTimes(""))
        XCTAssertNil(PixelGate.parseTimes("abc,def"))
    }

    func test_parseTimes_commaSeparated_parsesAndTrims() {
        XCTAssertEqual(PixelGate.parseTimes("0, 0.75,2.0"), [0.0, 0.75, 2.0])
    }

    func test_parseTimes_partialGarbage_keepsValid() {
        XCTAssertEqual(PixelGate.parseTimes("0,x,4"), [0.0, 4.0])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd App && xcodegen generate && xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata -only-testing:TrueISFEditorTests/PixelGateTests 2>&1 | tail -5`
Expected: FAIL — `parseTimes` not defined.

- [ ] **Step 3: Implement.** In `PixelGate.swift` (same enum as `verdict`):

```swift
    /// Parses the `SHADERTOY_DEBUG_GATE_TIMES` override ("0,0.75,2,4,8") for triage runs that
    /// need more/later frames than the default 3 (feedback shaders can look STATIC at t≤1.5).
    /// Returns nil when the raw value yields no parseable times (callers fall back to defaults).
    static func parseTimes(_ raw: String?) -> [Double]? {
        guard let raw, !raw.isEmpty else { return nil }
        let times = raw.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return times.isEmpty ? nil : times
    }
```

In `TrueISFEditorApp.swift`, corpus block — replace `let pixel = preview.runPixelGate()` with:

```swift
                            let gateTimes = PixelGate.parseTimes(
                                ProcessInfo.processInfo.environment["SHADERTOY_DEBUG_GATE_TIMES"])
                            let pixel = gateTimes.map { preview.runPixelGate(times: $0) }
                                ?? preview.runPixelGate()
```

- [ ] **Step 4: Run tests** (same command). Expected: PASS.

- [ ] **Step 5: Create the id lists.**

```bash
printf '%s\n' wc33RN wX33zX M3BfzG XtdSDn XXVfRV wfX3WX lcXXzM 33jcRR tXfBz2 3XBBWD > corpus/black-ids.txt
grep -E $'\tSTATIC\t|pixel=STATIC' docs/corpus-analysis-2026-07-09-pixel-baseline.txt | awk -F'\t' '{print $1}' > corpus/static-ids.txt
wc -l corpus/black-ids.txt corpus/static-ids.txt   # expect 10 and 14
```

- [ ] **Step 6: Dump raw JSON + converted `.fs` for the 10 BLACK ids.**

```bash
mkdir -p /tmp/t32-triage/json /tmp/t32-triage/fs
./scripts/corpus-run.sh --build -o /tmp/t32-triage/json corpus/black-ids.txt
BIN=/tmp/trueisfeditor-ddata/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor
while read -r id; do
  SHADERTOY_DEBUG_FETCH="$id" "$BIN" 2>/dev/null | sed -n '/^=== DEBUG FETCH ===$/,/^=== END ===$/p' > "/tmp/t32-triage/fs/$id.fs"
done < corpus/black-ids.txt
```

- [ ] **Step 7: Attribute each BLACK id.** For each `/tmp/t32-triage/json/<id>.json` + `fs/<id>.fs`, answer: does the Common tab use a detectable uniform (`iTime`, `iResolution`, `iMouse`, …) inside a helper body with no same-named parameter (→ **C5**)? Is it multipass with an `out vec4` accumulated-before-assigned in a non-first pass (→ **M1**)? Does any pass declare comma-separated globals colliding cross-pass (→ **M2**)? Uniform-named helper params in a pass body (→ **M20**)? Otherwise: name the actual cause (→ **other**, out of 3.2 scope).

- [ ] **Step 8: Re-check the 14 STATIC with longer/later frames.**

```bash
SHADERTOY_DEBUG_GATE_TIMES="0,0.75,2,4,8" ./scripts/corpus-run.sh corpus/static-ids.txt
```
Record which flip STATIC→OK (feedback shaders needing warm-up; note them — no gate-default change in this plan).

- [ ] **Step 9: Record results + commit.** Fill in the table below in THIS file, listing per-id attribution and the STATIC flips. **The BLACK ids attributed C5/M1/M2/M20 become the binding acceptance targets for Task 13.**

#### Task 1 Results (filled 2026-07-09)

**Headline: the C5/M1/M2 hypothesis is FALSIFIED for these 10 — zero are that class.** The converted files carry no raw uniforms (C5-clean), and none of the multipass ones hit the M1/M2 shapes. Two NEW converter bug classes dominate, both fixable with exactly the declarator/scanner machinery this plan builds:

- **zero-init-locals (6/10):** uninitialized local declarators read before write — `float i, d, z, r;` + `for(O*=i; i++<9e1;)`, `for (float i; i < log2(R.x);)`. ANGLE (WebGL) zero-initializes locals, Metal does not → loop guards read garbage/NaN → loop never runs → black. The XorDev-golf idiom class, endemic on Shadertoy.
- **injected-name collision (1/10):** user local `vec2 mouse = iMouse.xy` — the iMouse rule rewrites the initializer to reference `mouse` (the ISF point2D input), which the fresh local shadows immediately → self-referential garbage camera → black.

| id | attribution | evidence (one line) |
|----|-------------|---------------------|
| wc33RN | zero-init-locals | `vec4 o, P, q; float i, j, z, d, s, D;` uninit; `o += P.w*P/d` accum; `O = tanh(o/3E3)` |
| wX33zX | zero-init-locals | `vec3 r=iResolution, o, p, P;` — uninit accumulator `o` + ray state |
| M3BfzG | other: input-dependent | Canny thresholds = `iMouse.xy*{15,90}`; gate mouse=(0,0) → both 0 → final `mix()` → black. Gate limitation (no mouse binding), not a converter bug |
| XtdSDn | other: unknown | SmoothLife feedback; seed path (`iFrame<10` → hash noise) looks sound; needs live debug — out of 3.2 scope |
| XXVfRV | zero-init-locals | `vec2 R=…, S, k, P = k+.5, …` reads uninit `k`; `for(; i < n;` uninit `i` |
| wfX3WX | zero-init-locals | `for (float i; i < log2(R.x);` — init-less loop var (cubemap-pass degradation secondary) |
| lcXXzM | zero-init-locals | `float l = 1e5, d,x, r;` + `for(; r < R.y/2.;` — uninit `r` guard |
| 33jcRR | zero-init-locals | `float i, d, z, r;` + `for(O*=i; i++<9e1;` (silent mic secondary) |
| tXfBz2 | injected-name collision | `vec2 mouse = iMouse.xy` → rewrite makes the initializer read the just-declared local |
| 3XBBWD | zero-init-locals | `float t = iTime,i,z,d;` + `for(o*=i;i++<80.;…)` — canonical golf |

STATIC flips at extended times (`0,0.75,2,4,8`): **none** — all 14 remain STATIC; the labels are genuine (truly static or input-content-static shaders), not warm-up artifacts.

**Consequence for exit criteria:** C5/M1/M2/M20 remain correct structural fixes but flip zero of these BLACKs. The BLACK-flipping payoff requires two NEW rewriters (decision checkpoint with Conner recorded below): **ZeroInitLocals** (Task 12b) and **InjectedNameGuard** (Task 12c) — both consumers of M2's declarator machinery.

```bash
git add App/TrueISFEditor/PixelGate.swift App/TrueISFEditor/TrueISFEditorApp.swift App/TrueISFEditorTests/PixelGateTests.swift corpus/black-ids.txt corpus/static-ids.txt docs/superpowers/plans/2026-07-09-shared-glsl-scanner.md
git commit -m "feat(triage): gate-times override + BLACK/STATIC attribution for Task 3.2"
```

---

### Task 2: `GLSLScanner` primitive + state-transition test matrix

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLScanner.swift`
- Test: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/GLSLScannerTests.swift`

**Interfaces:**
- Produces (all `internal`, consumed by every later task):
  - `GLSLScanner.State { inLineComment, inBlockComment, isCommentDelimiter, inDirective: Bool; braceDepth, parenDepth: Int; inComment: Bool }`
  - `GLSLScanner.scan(_ code: String, _ body: (Int, unichar, State) -> Bool)` — body returns false to stop
  - `GLSLScanner.strip(_ code: String) -> String` — blanks comment content, keeps `//` `/*` `*/` + newlines, **UTF-16-offset-exact**
  - `GLSLScanner.braceDepth(_ code: String, before: Int) -> Int` (precondition: `before` < utf16 length)
  - `GLSLScanner.statementEnd(_ code: String, from: Int) -> Int?`
  - `GLSLScanner.braceMatchEnd(_ code: String, openBrace: Int) -> Int?`
  - `GLSLScanner.splitArgs(_ code: String, openParen: Int) -> (argRanges: [NSRange], close: Int)?`

Semantics (locked here, asserted by the tests): depths are **before-effect** (an opening `{` is reported at its outer depth); comment flags cover delimiters, `isCommentDelimiter` true exactly on the 2 units of `//`/`/*`/`*/`; `inDirective` spans `#`(first non-blank on line)→just-before-`\n`; comments DO open inside directives; depth never counts inside comments OR directives; closers never push depth below 0; unterminated block comment runs to EOF; no line-continuation handling (GLSLLineContinuation.splice runs before every consumer).

- [ ] **Step 1: Write the failing tests:**

```swift
import XCTest
@testable import ShadertoyISFKit

final class GLSLScannerTests: XCTestCase {
    /// (char, state) per UTF-16 unit — ASCII-only fixtures so unichar↔Character is 1:1.
    private func states(_ code: String) -> [(c: Character, st: GLSLScanner.State)] {
        var out: [(Character, GLSLScanner.State)] = []
        GLSLScanner.scan(code) { _, u, st in
            out.append((Character(UnicodeScalar(u)!), st)); return true
        }
        return out
    }
    private func stateAt(_ code: String, _ i: Int) -> GLSLScanner.State { states(code)[i].st }

    // MARK: comments

    func test_lineComment_contentFlagged_newlineEndsIt() {
        let s = states("a// x\nb")
        XCTAssertFalse(s[0].st.inComment)                       // a
        XCTAssertTrue(s[1].st.inLineComment && s[1].st.isCommentDelimiter)  // '/'
        XCTAssertTrue(s[2].st.inLineComment && s[2].st.isCommentDelimiter)  // '/'
        XCTAssertTrue(s[4].st.inLineComment && !s[4].st.isCommentDelimiter) // 'x'
        XCTAssertFalse(s[5].st.inComment)                       // '\n' is not comment content
        XCTAssertFalse(s[6].st.inComment)                       // b
    }

    func test_blockComment_spansLines_delimitersFlagged() {
        let s = states("/* x\ny */z")
        XCTAssertTrue(s[0].st.inBlockComment && s[0].st.isCommentDelimiter)
        XCTAssertTrue(s[3].st.inBlockComment && !s[3].st.isCommentDelimiter) // x
        XCTAssertTrue(s[5].st.inBlockComment)                                // y (after \n)
        XCTAssertTrue(s[7].st.inBlockComment && s[7].st.isCommentDelimiter)  // '*' of */
        XCTAssertFalse(s[9].st.inComment)                                    // z
    }

    func test_lineCommentMarker_insideBlockComment_isJustContent() {
        let s = states("/* // */x")
        XCTAssertTrue(s[3].st.inBlockComment && !s[3].st.inLineComment)
        XCTAssertFalse(s[9].st.inComment)   // x — the */ closed it despite the //
    }

    func test_unterminatedBlockComment_runsToEnd() {
        let s = states("/* x")
        XCTAssertTrue(s[3].st.inBlockComment)
    }

    // MARK: depth

    func test_braceAndParenDepth_beforeEffect() {
        let code = "f(a){b}"
        let s = states(code)
        XCTAssertEqual(s[1].st.parenDepth, 0)   // '(' reported at outer depth
        XCTAssertEqual(s[2].st.parenDepth, 1)   // a
        XCTAssertEqual(s[3].st.parenDepth, 1)   // ')' reported inside
        XCTAssertEqual(s[4].st.braceDepth, 0)   // '{' outer
        XCTAssertEqual(s[5].st.braceDepth, 1)   // b
        XCTAssertEqual(s[6].st.braceDepth, 1)   // '}' inside
    }

    func test_delimitersInComments_dontCount() {
        // the N323DD smiley — a paren in a comment must not shift depth for the rest of the file
        let s = states("// :(\nx")
        XCTAssertEqual(s.last!.st.parenDepth, 0)
    }

    func test_closersNeverGoNegative() {
        let s = states(")}x")
        XCTAssertEqual(s[2].st.braceDepth, 0)
        XCTAssertEqual(s[2].st.parenDepth, 0)
    }

    // MARK: directives

    func test_directive_bracesDontCount_endsAtNewline() {
        // ssjyWc header-macro class: unbalanced { in a #define must not desync depth
        let code = "#define Main void mainImage(out vec4 Q){\nfloat g;"
        let s = states(code)
        XCTAssertTrue(s[1].st.inDirective)
        XCTAssertEqual(s.last!.st.braceDepth, 0)
        XCTAssertEqual(s.last!.st.parenDepth, 0)
        XCTAssertFalse(s.last!.st.inDirective)
    }

    func test_hashMidLine_isNotADirective() {
        let s = states("a # b")
        XCTAssertFalse(s[2].st.inDirective)
    }

    func test_indentedHash_isADirective() {
        let s = states("  #define X 1")
        XCTAssertTrue(s[2].st.inDirective)
    }

    func test_lineCommentOpensInsideDirective() {
        let s = states("#define X 1 // note")
        XCTAssertTrue(s[12].st.inLineComment)   // the first '/'
    }

    func test_earlyExit_stops() {
        var count = 0
        GLSLScanner.scan("abcdef") { _, _, _ in count += 1; return count < 3 }
        XCTAssertEqual(count, 3)
    }

    // MARK: strip (absorbs GLSLCommentsTests' contract)

    func test_strip_blanksContent_keepsDelimitersAndNewlines() {
        XCTAssertEqual(GLSLScanner.strip("a // bc\nd"), "a //   \nd")
        XCTAssertEqual(GLSLScanner.strip("a /* b\nc */ d"), "a /*  \n  */ d")
    }

    func test_strip_noComments_identity() {
        XCTAssertEqual(GLSLScanner.strip("float x = 1.0;"), "float x = 1.0;")
    }

    func test_strip_preservesUTF16Offsets_astralCharInComment() {
        let code = "// 🙂\nx"
        let out = GLSLScanner.strip(code)
        XCTAssertEqual((out as NSString).length, (code as NSString).length)
        XCTAssertTrue(out.hasSuffix("\nx"))
    }

    // MARK: helpers

    func test_braceDepth_before() {
        let code = "void f() { int x; } int y;"
        let xPos = (code as NSString).range(of: "int x").location
        let yPos = (code as NSString).range(of: "int y").location
        XCTAssertEqual(GLSLScanner.braceDepth(code, before: xPos), 1)
        XCTAssertEqual(GLSLScanner.braceDepth(code, before: yPos), 0)
    }

    func test_statementEnd_skipsCommentAndDirectiveSemicolons() {
        let code = "float x /* ; */ = 1.0; y"
        XCTAssertEqual(GLSLScanner.statementEnd(code, from: 0), (code as NSString).range(of: "1.0;").location + 4)
        XCTAssertNil(GLSLScanner.statementEnd("float x = 1.0", from: 0))
    }

    func test_braceMatchEnd_skipsCommentBraces() {
        let code = "{ /* } */ a }b"
        XCTAssertEqual(GLSLScanner.braceMatchEnd(code, openBrace: 0), 13)
        XCTAssertNil(GLSLScanner.braceMatchEnd("{ a", openBrace: 0))
    }

    func test_splitArgs_commentCommaAndParenNotStructure() {
        let code = "f(a /*, ) */, b)"
        let ns = code as NSString
        let open = ns.range(of: "(").location
        let r = GLSLScanner.splitArgs(code, openParen: open)!
        XCTAssertEqual(r.argRanges.map { ns.substring(with: $0) }, ["a /*, ) */", " b"])
        XCTAssertEqual(ns.substring(with: NSRange(location: r.close, length: 1)), ")")
    }

    func test_splitArgs_nestedParens() {
        let code = "f(g(a, b), c)"
        let ns = code as NSString
        let r = GLSLScanner.splitArgs(code, openParen: 1)!
        XCTAssertEqual(r.argRanges.map { ns.substring(with: $0) }, ["g(a, b)", " c"])
    }

    func test_splitArgs_unclosed_returnsNil() {
        XCTAssertNil(GLSLScanner.splitArgs("f(a, b", openParen: 1))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ShadertoyISFKit && swift test --filter GLSLScannerTests 2>&1 | tail -3`
Expected: compile FAIL — `GLSLScanner` not defined.

- [ ] **Step 3: Implement `GLSLScanner.swift`:**

```swift
import Foundation

/// THE shared GLSL character scanner (DESLOPPIFY M3). One state machine tracking comment /
/// preprocessor-directive state and brace/paren depth over a string's UTF-16 units; every
/// consumer needing "am I in a comment / what's the depth here" builds on `scan` or a helper
/// below. Do NOT hand-roll another `inLine`/`inBlock` walker — extend this one.
///
/// Semantics (locked by GLSLScannerTests):
/// - `braceDepth`/`parenDepth` are the depth BEFORE the current unit's own effect: an opening
///   `{` is reported at its OUTER depth, a closing `}` at its inner one.
/// - Comment flags cover the ENTIRE comment INCLUDING delimiters; `isCommentDelimiter` is true
///   exactly for the two units of `//`, `/*`, `*/`.
/// - `inDirective` spans a `#` line (first non-blank unit on the line) up to just before its
///   newline. Comments still open inside directives (`#define X 1 // note`). Depth is never
///   counted inside comments OR directives (a `#define Main …{` must not desync brace depth —
///   the ssjyWc header-macro class that CommonUniformRewriter.walkRuns pioneered handling).
/// - No `\` line-continuation handling: GLSLLineContinuation.splice runs before every scanner
///   consumer (ISFConverter stages 1/5), so directives are single-line here.
/// - Totality: no throws; an unterminated block comment stays open to end-of-string; unbalanced
///   closers never push depth below 0.
enum GLSLScanner {
    struct State {
        var inLineComment = false
        var inBlockComment = false
        /// True for the two units of a `//`, `/*` or `*/` token (strip keeps these, blanks content).
        var isCommentDelimiter = false
        var inDirective = false
        var braceDepth = 0
        var parenDepth = 0
        var inComment: Bool { inLineComment || inBlockComment }
    }

    /// Walks every UTF-16 unit of `code`, calling `body(index, unit, state)`. Return false from
    /// `body` to stop early. Every other helper in this enum is a query over this one machine.
    static func scan(_ code: String, _ body: (Int, unichar, State) -> Bool) {
        let s = code as NSString
        let slash: unichar = 47, star: unichar = 42, nl: unichar = 10, hash: unichar = 35
        let ob: unichar = 123, cb: unichar = 125, op: unichar = 40, cp: unichar = 41
        let sp: unichar = 32, tab: unichar = 9
        var st = State()
        var atLineStart = true
        var i = 0
        while i < s.length {
            let c = s.character(at: i)
            let n: unichar? = i + 1 < s.length ? s.character(at: i + 1) : nil
            st.isCommentDelimiter = false

            if st.inLineComment {
                if c == nl {
                    st.inLineComment = false
                    st.inDirective = false
                    if !body(i, c, st) { return }
                    atLineStart = true
                    i += 1; continue
                }
                if !body(i, c, st) { return }
                i += 1; continue
            }
            if st.inBlockComment {
                if c == star, n == slash {
                    st.isCommentDelimiter = true
                    if !body(i, c, st) { return }
                    if !body(i + 1, slash, st) { return }
                    st.inBlockComment = false
                    atLineStart = false
                    i += 2; continue
                }
                if !body(i, c, st) { return }
                if c == nl { atLineStart = true } else if c != sp, c != tab { atLineStart = false }
                i += 1; continue
            }
            if c == slash, n == slash {
                st.inLineComment = true
                st.isCommentDelimiter = true
                if !body(i, c, st) { return }
                if !body(i + 1, slash, st) { return }
                atLineStart = false
                i += 2; continue
            }
            if c == slash, n == star {
                st.inBlockComment = true
                st.isCommentDelimiter = true
                if !body(i, c, st) { return }
                if !body(i + 1, star, st) { return }
                atLineStart = false
                i += 2; continue
            }
            if c == nl { st.inDirective = false }
            else if atLineStart, c == hash { st.inDirective = true }
            if !body(i, c, st) { return }
            if !st.inDirective {
                switch c {
                case ob: st.braceDepth += 1
                case cb: if st.braceDepth > 0 { st.braceDepth -= 1 }
                case op: st.parenDepth += 1
                case cp: if st.parenDepth > 0 { st.parenDepth -= 1 }
                default: break
                }
            }
            if c == nl { atLineStart = true }
            else if c != sp, c != tab { atLineStart = false }
            i += 1
        }
    }

    /// Blanks comment CONTENT (a space per non-newline unit), keeping `//` `/*` `*/` delimiters
    /// and all newlines — UTF-16 offsets are EXACTLY preserved (an astral char in a comment
    /// becomes two spaces), so match ranges found on the masked text index straight into the
    /// original. Detection scans and structure parsing run on this; rewrites edit the original.
    static func strip(_ code: String) -> String {
        var units: [unichar] = []
        units.reserveCapacity((code as NSString).length)
        let nl: unichar = 10, sp: unichar = 32
        scan(code) { _, c, st in
            units.append(st.inComment && !st.isCommentDelimiter && c != nl ? sp : c)
            return true
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// Brace depth immediately before UTF-16 position `pos` (0 = file scope).
    /// Precondition: `pos` < the string's UTF-16 length.
    static func braceDepth(_ code: String, before pos: Int) -> Int {
        var depth = 0
        scan(code) { i, _, st in
            if i >= pos { depth = st.braceDepth; return false }
            return true
        }
        return depth
    }

    /// Index just past the first `;` at or after `from` outside comments and directives
    /// (a `;` in a `#define` body does not end a declaration statement).
    static func statementEnd(_ code: String, from: Int) -> Int? {
        let semi: unichar = 59
        var result: Int? = nil
        scan(code) { i, c, st in
            if i < from { return true }
            if c == semi, !st.inComment, !st.inDirective { result = i + 1; return false }
            return true
        }
        return result
    }

    /// Index just past the `}` matching the `{` at `openBrace` (which must sit outside comments).
    static func braceMatchEnd(_ code: String, openBrace: Int) -> Int? {
        let ob: unichar = 123, cb: unichar = 125
        var depth = 0
        var result: Int? = nil
        scan(code) { i, c, st in
            if i < openBrace { return true }
            if st.inComment || st.inDirective { return true }
            if c == ob { depth += 1 }
            else if c == cb { depth -= 1; if depth == 0 { result = i + 1; return false } }
            return true
        }
        return result
    }

    /// Splits the args of a call whose `(` sits at `openParen` (outside comments). Returns the
    /// UTF-16 range of each top-level arg (comment text inside args is covered by the ranges —
    /// callers slice the ORIGINAL so comments survive verbatim) and the index of the matching
    /// `)`. Commas/parens inside comments are not structure. nil when the list never closes.
    static func splitArgs(_ code: String, openParen: Int) -> (argRanges: [NSRange], close: Int)? {
        let op: unichar = 40, cp: unichar = 41, comma: unichar = 44
        var depth = 0
        var argStart = openParen + 1
        var ranges: [NSRange] = []
        var close: Int? = nil
        scan(code) { i, c, st in
            if i < openParen || st.inComment { return true }
            if c == op { depth += 1; if depth == 1 { argStart = i + 1 }; return true }
            if c == cp {
                depth -= 1
                if depth == 0 {
                    ranges.append(NSRange(location: argStart, length: i - argStart))
                    close = i
                    return false
                }
                return true
            }
            if c == comma, depth == 1 {
                ranges.append(NSRange(location: argStart, length: i - argStart))
                argStart = i + 1
            }
            return true
        }
        guard let c = close else { return nil }
        return (ranges, c)
    }
}
```

- [ ] **Step 4: Run tests.** `cd ShadertoyISFKit && swift test --filter GLSLScannerTests 2>&1 | tail -3` → PASS. Then full kit suite: `swift test 2>&1 | tail -3` → 0 failures.

- [ ] **Step 5: Commit**

```bash
git add ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLScanner.swift ShadertoyISFKit/Tests/ShadertoyISFKitTests/GLSLScannerTests.swift
git commit -m "feat(scanner): GLSLScanner shared primitive — one comment/directive/depth state machine (M3 core)"
```

---

### Task 3: Migrate `GLSLComments` → `GLSLScanner.strip` [CORPUS]

**Files:**
- Delete: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLComments.swift`
- Delete: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/GLSLCommentsTests.swift` (contract now lives in GLSLScannerTests' strip tests)
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/ISFConverter.swift:50,90`

**Interfaces:**
- Consumes: `GLSLScanner.strip` (Task 2). No public shape changes.

- [ ] **Step 1:** In `ISFConverter.swift` replace both call sites:
  - line 50: `let detectable = GLSLComments.strip(code)` → `let detectable = GLSLScanner.strip(code)`
  - line 90: `let detectableCommon = GLSLComments.strip(splicedCommon)` → `let detectableCommon = GLSLScanner.strip(splicedCommon)`
- [ ] **Step 2:** `git rm` the two deleted files. Grep to confirm zero survivors: `grep -rn "GLSLComments" ShadertoyISFKit App --include='*.swift'` → no hits.
- [ ] **Step 3:** Kit suite green (`swift test`), then **corpus gate** (Global Constraints — expect identical pass list).
- [ ] **Step 4: Commit** — `refactor(kit): GLSLComments.strip folds into GLSLScanner.strip (walker D deleted)`

---

### Task 4: Migrate `GLSLCallParser` — both duplicate walkers onto the scanner [CORPUS]

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLCallParser.swift` (full rewrite below; `channelIndex(forArg:)` kept verbatim)
- Test: existing `GLSLCallParserTests.swift` + `SamplerRewriterTests.swift` + `CommonChannelRewriterTests.swift` (no changes — they pin public behavior)

**Interfaces:**
- Consumes: `GLSLScanner.strip`, `GLSLScanner.splitArgs`.
- Produces (unchanged): `replaceCall(in:fn:arity:transform:) -> String`, `channelIndex(forArg:) -> Int?`. Deleted: `parseArgs`, `matchesIdentifier`, `isIdentChar` (internal only; no test references them — verified 2026-07-09).

- [ ] **Step 1: Rewrite the file.** New idiom: match structure on masked text, slice arg TEXT from the original (comments inside args survive verbatim — pinned by `test_comma_insideBlockComment_doesNotSplitArgs`).

```swift
import Foundation

/// Shared identifier/call-site parsing for GLSL rewriters. Replaces `fn(arg0, arg1, …)` with a
/// caller-supplied transform, respecting nested parentheses and word boundaries. Used by
/// SamplerRewriter (per-pass sampling) and CommonChannelRewriter (Common-tab PASSINDEX dispatch).
///
/// Structure (comment skipping, arg splitting) is computed on GLSLScanner-masked text; arg text
/// is sliced from the ORIGINAL at the same UTF-16 offsets, so comments inside args are preserved.
enum GLSLCallParser {
    /// Replaces every `fn(...)` whose top-level arg count equals `arity` with `transform(args)`.
    /// Returning nil from `transform` leaves that call untouched (its args are still scanned for
    /// nested matches on the next search iteration). Calls inside comments never match — their
    /// identifier is blanked in the masked text.
    static func replaceCall(in code: String, fn: String, arity: Int,
                            transform: ([String]) -> String?) -> String {
        let masked = GLSLScanner.strip(code)
        let ns = code as NSString
        let mns = masked as NSString
        // GLSL permits whitespace between the function name and its paren (M21).
        let re = try! NSRegularExpression(
            pattern: "\\b" + NSRegularExpression.escapedPattern(for: fn) + "\\b[ \\t]*\\(")
        var result = ""
        var cursor = 0     // UTF-16 read position in the original
        var searchAt = 0
        while searchAt < mns.length,
              let m = re.firstMatch(in: masked,
                                    range: NSRange(location: searchAt, length: mns.length - searchAt)) {
            let openParen = m.range.location + m.range.length - 1
            guard let (argRanges, close) = GLSLScanner.splitArgs(masked, openParen: openParen),
                  argRanges.count == arity else {
                searchAt = m.range.location + m.range.length
                continue
            }
            // Rewrite calls nested inside the args first (texture-inside-texture is the standard
            // distortion/feedback idiom) — skipping past the outer match would leave them raw.
            let args = argRanges.map { ns.substring(with: $0) }
            let nested = args.map { replaceCall(in: $0, fn: fn, arity: arity, transform: transform) }
            if let replacement = transform(nested) {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                result += replacement
                cursor = close + 1
                searchAt = close + 1
            } else {
                searchAt = m.range.location + m.range.length
            }
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// The channel index of an `iChannelN` argument, or nil. The arg may carry a trailing comment
    /// (`iChannel0 /* src */`), so match the LEADING identifier rather than requiring the whole
    /// trimmed token to parse — and the digits must end the identifier (`iChannel0img` is not
    /// channel 0). Single shared parser so per-pass and Common rewrites can't disagree.
    static func channelIndex(forArg arg: String) -> Int? {
        let t = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("iChannel") else { return nil }
        let rest = t.dropFirst("iChannel".count)
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        if let after = rest.dropFirst(digits.count).first, after.isLetter || after == "_" { return nil }
        return n
    }
}
```

- [ ] **Step 2:** Run: `cd ShadertoyISFKit && swift test --filter 'GLSLCallParserTests|SamplerRewriterTests|CommonChannelRewriterTests' 2>&1 | tail -3` → PASS (all 33 pinned behaviors).
- [ ] **Step 3:** Full kit suite, then **corpus gate**.
- [ ] **Step 4: Commit** — `refactor(kit): GLSLCallParser onto GLSLScanner — two duplicate comment walkers deleted (M3, C1 net kept)`

---

### Task 5: Migrate `GLSLGlobalScanner` + direct tests (fixes M14 for globals) [CORPUS]

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLGlobalScanner.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/GLSLGlobalScannerTests.swift` (this scanner has NO direct tests today — write the net before touching it)

**Interfaces:**
- Consumes: `GLSLScanner.strip/braceDepth/statementEnd`.
- Produces (unchanged this task): `GLSLGlobalScanner.Def { name, start, end }`, `defs(in:) -> [Def]`. (Multi-declarator lands in Task 11.)

- [ ] **Step 1: Write the direct tests FIRST** (they must pass against the CURRENT implementation before the migration — run them against old code, then keep them green through it):

```swift
import XCTest
@testable import ShadertoyISFKit

final class GLSLGlobalScannerTests: XCTestCase {
    func test_simpleGlobal_found() {
        let defs = GLSLGlobalScanner.defs(in: "float f = 0.025;\n")
        XCTAssertEqual(defs.map(\.name), ["f"])
    }

    func test_constAndArrayGlobals_found() {
        let code = "const float pi = 3.14159;\nvec3 pal[16];"
        XCTAssertEqual(GLSLGlobalScanner.defs(in: code).map(\.name), ["pi", "pal"])
    }

    func test_localDeclaration_excluded() {
        let code = "void f() {\n    float local = 1.0;\n}"
        XCTAssertTrue(GLSLGlobalScanner.defs(in: code).isEmpty)
    }

    func test_functionDefinitionAndPrototype_excluded() {
        let code = "float f(vec2 p) { return p.x; }\nfloat g(vec2 p);"
        XCTAssertTrue(GLSLGlobalScanner.defs(in: code).isEmpty)
    }

    func test_defRange_coversWholeStatement() {
        let code = "float f = 0.025;"
        let d = GLSLGlobalScanner.defs(in: code)[0]
        XCTAssertEqual((code as NSString).substring(with: NSRange(location: d.start, length: d.end - d.start)),
                       "float f = 0.025;")
    }

    /// M14 — a global inside a block comment must NOT become a Def (phantom defs made
    /// GLSLFunctionDedup delete the REAL definition and keep the commented text).
    func test_globalInsideBlockComment_isNotADef_M14() {
        let code = "/*\nfloat ghost = 1.0;\n*/\nfloat real = 2.0;"
        XCTAssertEqual(GLSLGlobalScanner.defs(in: code).map(\.name), ["real"])
    }

    /// M14 — line-commented global likewise.
    func test_globalInsideLineComment_isNotADef_M14() {
        XCTAssertEqual(GLSLGlobalScanner.defs(in: "// float ghost = 1.0;\nfloat real = 2.0;").map(\.name),
                       ["real"])
    }
}
```

- [ ] **Step 2: Run them against the CURRENT code.** `swift test --filter GLSLGlobalScannerTests 2>&1 | tail -5`
Expected: the two `_M14` tests FAIL (current regex matches inside comments — that's the bug), the rest PASS. This pins both the preserved contract and the fix.

- [ ] **Step 3: Migrate.** Replace `defs(in:)` and DELETE the private `depth`/`statementEnd` walkers:

```swift
    /// All file-scope (brace-depth-0) global declarations in `code`, in source order.
    /// Matching runs on comment-masked text (M14: a commented-out global can't become a Def);
    /// ranges index into the original, which is offset-identical.
    static func defs(in code: String) -> [Def] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let masked = GLSLScanner.strip(code)
        let ms = masked as NSString
        var out: [Def] = []
        for m in re.matches(in: masked, range: NSRange(location: 0, length: ms.length)) {
            guard GLSLScanner.braceDepth(code, before: m.range.location) == 0 else { continue }
            guard let end = GLSLScanner.statementEnd(code, from: m.range.location) else { continue }
            let name = ms.substring(with: m.range(at: 1))
            out.append(Def(name: name, start: m.range.location, end: end))
        }
        return out
    }
```

(Behavior notes for the commit message: depth/statement scans are now also directive-aware — a `{` or `;` inside a `#define` line no longer desyncs them; strictly a hardening, corpus-gated.)

- [ ] **Step 4:** `swift test --filter 'GLSLGlobalScannerTests|GLSLFunctionDedupTests|GLSLPassNamespaceTests' 2>&1 | tail -3` → ALL pass (M14 tests now green). Full kit suite, then **corpus gate**.
- [ ] **Step 5: Commit** — `fix(kit): GLSLGlobalScanner onto GLSLScanner — M14 phantom globals in comments fixed, direct test net added`

---

### Task 6: Migrate `GLSLFunctionScanner` + params capture (fixes M14 for functions; C5's prerequisite) [CORPUS]

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLFunctionScanner.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/GLSLFunctionScannerTests.swift`

**Interfaces:**
- Consumes: `GLSLScanner.strip/braceMatchEnd`.
- Produces: existing `Def { name, start, end }` + `defs(in:)` (unchanged shape, used by Dedup/Namespace), PLUS new:
  - `struct FunctionDef { let name: String; let paramNames: [String]; let start: Int; let end: Int }`
  - `static func functionDefs(in code: String) -> [FunctionDef]` — `defs(in:)` becomes a thin projection of this.
  - `normalize(_:)` reimplemented on `GLSLScanner.strip` (kills the third, regex-based comment strip).
  - `braceMatchEnd(_ s: NSString, openBrace: Int)` DELETED (callers use `GLSLScanner.braceMatchEnd`).

- [ ] **Step 1: Write the tests:**

```swift
import XCTest
@testable import ShadertoyISFKit

final class GLSLFunctionScannerTests: XCTestCase {
    func test_simpleDef_nameAndRange() {
        let code = "float noise(vec2 p) { return p.x; }"
        let d = GLSLFunctionScanner.defs(in: code)[0]
        XCTAssertEqual(d.name, "noise")
        XCTAssertEqual(d.start, 0)
        XCTAssertEqual(d.end, (code as NSString).length)
    }

    func test_allmanBrace_stillADef() {
        XCTAssertEqual(GLSLFunctionScanner.defs(in: "vec3 f(vec2 p)\n{\n  return vec3(p, 0.);\n}").map(\.name),
                       ["f"])
    }

    func test_controlFlow_notADef() {
        XCTAssertTrue(GLSLFunctionScanner.defs(in: "void g(){ if (x) { } else if (y) { } }").map(\.name)
            .allSatisfy { $0 == "g" })
    }

    /// M14 — commented-out function must not become a Def (worst case Dedup deletes the REAL one).
    func test_commentedOutFunction_isNotADef_M14() {
        let code = "/*\nfloat helper(vec2 p) { return p.x; }\n*/\nfloat helper(vec2 p) { return p.y; }"
        let defs = GLSLFunctionScanner.defs(in: code)
        XCTAssertEqual(defs.count, 1)
        let kept = (code as NSString).substring(with: NSRange(location: defs[0].start,
                                                              length: defs[0].end - defs[0].start))
        XCTAssertTrue(kept.contains("p.y"))
    }

    // MARK: functionDefs — the C5 capability

    func test_paramNames_basicAndQualified() {
        let defs = GLSLFunctionScanner.functionDefs(in:
            "void ups(in vec2 uv, inout vec4 col, vec2 iResolution, sampler2D iChannel0) { }")
        XCTAssertEqual(defs[0].paramNames, ["uv", "col", "iResolution", "iChannel0"])
    }

    func test_paramNames_voidAndEmpty() {
        XCTAssertEqual(GLSLFunctionScanner.functionDefs(in: "float a() { return 1.; }")[0].paramNames, [])
        XCTAssertEqual(GLSLFunctionScanner.functionDefs(in: "float b(void) { return 1.; }")[0].paramNames, [])
    }

    func test_paramNames_arraySuffix() {
        XCTAssertEqual(GLSLFunctionScanner.functionDefs(in: "float c(float arr[4]) { return arr[0]; }")[0].paramNames,
                       ["arr"])
    }

    func test_normalize_ignoresCommentsAndWhitespace() {
        let a = GLSLFunctionScanner.normalize("float f() { // note\n  return 1.0; }")
        let b = GLSLFunctionScanner.normalize("float f() {  return 1.0; }")
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run** — `functionDefs`/M14 tests fail (`functionDefs` undefined; M14 case matches today). The pre-existing behavior tests must pass against current code first.

- [ ] **Step 3: Implement.** Replace the body of `GLSLFunctionScanner` (keep `headerPattern`, `controlKeywords`, `lastIdentifierBeforeParen` verbatim):

```swift
    /// A top-level function definition with its parameter NAMES — the C5/M20 scope model.
    struct FunctionDef { let name: String; let paramNames: [String]; let start: Int; let end: Int }

    /// All top-level function definitions in `code`, in source order. Header matching runs on
    /// comment-masked text (M14); ranges index into the original (offset-identical).
    static func functionDefs(in code: String) -> [FunctionDef] {
        let re = try! NSRegularExpression(pattern: headerPattern)
        let masked = GLSLScanner.strip(code)
        let ms = masked as NSString
        var out: [FunctionDef] = []
        for m in re.matches(in: masked, range: NSRange(location: 0, length: ms.length)) {
            let bracePos = m.range.location + m.range.length - 1   // the `{`
            guard let end = GLSLScanner.braceMatchEnd(code, openBrace: bracePos) else { continue }
            let header = ms.substring(with: m.range)               // masked: params are comment-free
            guard let name = lastIdentifierBeforeParen(header) else { continue }
            if controlKeywords.contains(name) { continue }
            out.append(FunctionDef(name: name, paramNames: paramNames(inHeader: header),
                                   start: m.range.location, end: end))
        }
        return out
    }

    /// All top-level function definitions (legacy shape for Dedup/Namespace).
    static func defs(in code: String) -> [Def] {
        functionDefs(in: code).map { Def(name: $0.name, start: $0.start, end: $0.end) }
    }

    /// Key on CODE only: blank comment content and collapse whitespace + delimiter tokens, so two
    /// copies differing only in comments/formatting compare equal.
    static func normalize(_ block: String) -> String {
        GLSLScanner.strip(block)
            .replacingOccurrences(of: "//", with: " ")
            .replacingOccurrences(of: "/*", with: " ")
            .replacingOccurrences(of: "*/", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parameter NAMES from a (masked) definition header: text between the first `(` and last `)`,
    /// split on commas (GLSL params contain no parens), each param's name = its last identifier
    /// before any `[` array suffix. `()`/`(void)` → [].
    private static func paramNames(inHeader header: String) -> [String] {
        guard let open = header.firstIndex(of: "("), let close = header.lastIndex(of: ")"),
              open < close else { return [] }
        let inner = header[header.index(after: open)..<close]
        let idRe = try! NSRegularExpression(pattern: "[A-Za-z_]\\w*")
        var names: [String] = []
        for piece in inner.split(separator: ",") {
            let text = String(piece)
            let beforeArray = text.firstIndex(of: "[").map { String(text[..<$0]) } ?? text
            let ns = beforeArray as NSString
            let ids = idRe.matches(in: beforeArray, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }
            if let last = ids.last, last != "void" { names.append(last) }
        }
        return names
    }
```

Delete the old `braceMatchEnd(_ s: NSString, openBrace:)` (walker C). Grep: `grep -rn "braceMatchEnd" ShadertoyISFKit/Sources` → only `GLSLScanner.braceMatchEnd` remains.

- [ ] **Step 4:** `swift test --filter 'GLSLFunctionScannerTests|GLSLFunctionDedupTests|GLSLPassNamespaceTests' 2>&1 | tail -3` → PASS. Full kit suite, then **corpus gate**.
- [ ] **Step 5: Commit** — `feat(kit): GLSLFunctionScanner onto GLSLScanner + param capture (M14 functions fixed; C5 scope model ready)`

---

### Task 7: N1 — `RewriteResult` convergence (mechanical, before the design changes use it)

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/RewriteResult.swift`
- Modify: `SamplerRewriter.swift` (Result → RewriteResult), `GLSLCompat.swift` (same), `OutputInitializer.swift` (Result{code,notes} → RewriteResult{code,warnings}), `ISFConverter.swift:150` (`initialized.notes` → `.warnings`)
- Modify: `OutputInitializerTests.swift` / any test referencing `.notes` (grep)
- Modify: spec `docs/superpowers/specs/2026-07-09-shared-glsl-scanner-design.md` (N1 paragraph — see Step 1 note)

**Interfaces:**
- Produces: `public struct RewriteResult { public let code: String; public let warnings: [ConversionWarning] }` — the return type Tasks 8–12 use.

**Plan sharpens spec (record in the spec in this task):** pure `String → String` transforms with no possible warnings (`GLSLLineContinuation.splice`, `GLSLFunctionDedup.dedup`, `UniformRewriter.rewrite`/`rewriteScoped`, `GLSLReservedIdentifierRewriter.rewrite`) STAY bare-String — wrapping them adds `.code` noise at every call site and no information. N1's deliverable is the converged shape for every warning-carrying stage plus the documented convention. Amend the spec's N1 sentence accordingly.

- [ ] **Step 1: Create `RewriteResult.swift`:**

```swift
import Foundation

/// The uniform return shape for warning-carrying pipeline rewriter stages (DESLOPPIFY N1).
///
/// Convention for `ISFConverter` pipeline stages:
/// - Produces warnings → return `RewriteResult` (these exact field names).
/// - Multi-output stages (HeaderMacroExpander, CommonChannelRewriter, GLSLBodyBuilder) keep
///   their own typed result structs but use the same `warnings: [ConversionWarning]` field name.
/// - Pure String→String transforms with no possible warnings (GLSLLineContinuation.splice,
///   GLSLFunctionDedup.dedup, UniformRewriter.rewrite/rewriteScoped,
///   GLSLReservedIdentifierRewriter.rewrite) stay bare String.
/// - Detection-only checks (GLSLLint.check) return bare `[ConversionWarning]`.
public struct RewriteResult {
    public let code: String
    public let warnings: [ConversionWarning]
    public init(code: String, warnings: [ConversionWarning] = []) {
        self.code = code
        self.warnings = warnings
    }
}
```

- [ ] **Step 2: Converge the three structs.**
  - `SamplerRewriter`: delete `public struct Result { public let code: String; public let warnings: [ConversionWarning] }`; `rewrite` returns `RewriteResult` (construct with `RewriteResult(code: …, warnings: …)`). Field names identical → call sites/tests untouched.
  - `GLSLCompat`: same swap.
  - `OutputInitializer`: delete its `Result`; return `RewriteResult`; the `notes:` label becomes `warnings:`. Update `ISFConverter.swift:150` → `warnings.append(contentsOf: initialized.warnings)`. Grep `\.notes` across kit sources + tests and update (expect: ISFConverter + OutputInitializerTests only).
- [ ] **Step 3:** Amend the spec's N1 paragraph per the "Plan sharpens spec" note; one sentence, same commit.
- [ ] **Step 4:** Full kit suite green. (No corpus needed — types only; the compiler is the gate.)
- [ ] **Step 5: Commit** — `refactor(kit): RewriteResult — one return shape for warning-carrying rewriter stages (N1)`

---

### Task 8: C5 + M20 — scope-aware uniform rewriting everywhere [CORPUS]

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/UniformRewriter.swift` (add `rewriteScoped`, `unresolvedUniformUses`; make no changes to `rules`/`rewrite`)
- Delete: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/CommonUniformRewriter.swift` (walker E — the last hand-rolled walker — dies here)
- Modify: `ISFConverter.swift` (stages 2 and 7 + the interim-warning loop + stage-list comment lines 8–17)
- Rename/modify: `CommonUniformRewriterTests.swift` → `UniformRewriterScopedTests.swift`
- Modify: `ISFConverterTests.swift` (M20 pipeline test)

**Interfaces:**
- Consumes: `GLSLFunctionScanner.functionDefs` (Task 6), `GLSLScanner.strip`.
- Produces: `UniformRewriter.rewriteScoped(_ code: String) -> String`; `UniformRewriter.unresolvedUniformUses(_ rewrittenCode: String) -> [String]` (tripwire — replaces `CommonUniformRewriter.unrewrittenBodyUniforms`).

- [ ] **Step 1: Write the failing tests** (`UniformRewriterScopedTests.swift` — port the 13 CommonUniformRewriter tests, calling `UniformRewriter.rewriteScoped`; these five change meaning or are new):

```swift
    /// C5 — THE fix: an unshadowed uniform inside a helper body IS now rewritten.
    /// (Was the "interim warn" case: `float n(vec2 p){ … iTime … }` shipped raw → black import.)
    func test_unshadowedBodyUniform_isRewritten_C5() {
        XCTAssertEqual(UniformRewriter.rewriteScoped("float n(vec2 p){ return sin(p.x + iTime); }"),
                       "float n(vec2 p){ return sin(p.x + TIME); }")
    }

    /// Per-function scope: shadowed function protected, unshadowed sibling rewritten — in one file.
    func test_mixedFunctions_shadowedProtected_unshadowedRewritten() {
        let src = """
        vec2 f(vec2 iResolution){ return iResolution.xy; }
        float g(vec2 p){ return p.x / iResolution.x; }
        """
        let out = UniformRewriter.rewriteScoped(src)
        XCTAssertTrue(out.contains("vec2 f(vec2 iResolution){ return iResolution.xy; }"), out)
        XCTAssertTrue(out.contains("p.x / vec3(RENDERSIZE, 1.0).x"), out)
    }

    /// Comment content is never rewritten (the Common-path sibling of N2).
    func test_commentContent_neverRewritten() {
        XCTAssertEqual(UniformRewriter.rewriteScoped("// uses iTime\nfloat t = iTime;"),
                       "// uses iTime\nfloat t = TIME;")
    }

    /// Tripwire: on correctly-rewritten output, nothing is unresolved.
    func test_unresolvedUniformUses_emptyAfterScopedRewrite() {
        let out = UniformRewriter.rewriteScoped("float n(vec2 p){ return sin(p.x + iTime); }")
        XCTAssertTrue(UniformRewriter.unresolvedUniformUses(out).isEmpty)
    }

    /// Tripwire: a bare (un-indexed) iChannelResolution survives the rewrite and IS flagged.
    func test_unresolvedUniformUses_flagsBareChannelResolution() {
        let out = UniformRewriter.rewriteScoped("vec3 r = iChannelResolution;")
        XCTAssertEqual(UniformRewriter.unresolvedUniformUses(out), ["iChannelResolution"])
    }
```

Ported tests that keep their exact expectations: `test_fileScopeDefine_rewritten`, `test_parameterDeclaration_protected`, `test_functionBodyUniform_protected`, `test_fileScopeGlobal_rewritten`, `test_unbalancedParenInComment_doesNotProtectRest`, `test_unbalancedBraceInBlockComment_doesNotProtectRest`, `test_headerMacroWithUnbalancedBrace_rewritesBodyAndDoesNotLeakScope`, `test_iChannelResolutionDefine_rewritten`, `test_iMouseDefine_rewritten_parameterThreaded_protected`, `test_mixed_defineRewritten_helperUntouched` — s/CommonUniformRewriter.rewrite/UniformRewriter.rewriteScoped/. DROP `test_unrewrittenBodyUniforms_detected` / `test_paramShadowedUniform_notFlaggedAsUnrewritten` / `test_fileScopeUniform_notFlaggedAsUnrewritten` (superseded by the tripwire tests above).

M20 pipeline test (append to `ISFConverterTests.swift`):

```swift
    /// M20 — paste path: a helper with a uniform-named PARAM in a pass body must be protected
    /// (was: whole-string rewrite emitted `vec2 vec3(RENDERSIZE, 1.0)` → syntax error), while
    /// its call sites still get the real rewrite.
    func test_pastePath_helperWithUniformNamedParam_isProtected_M20() {
        let shader = ShaderFactory.singlePass(imageCode: """
            float vig(vec2 uv, vec2 iResolution){ return uv.x / iResolution.x; }
            void mainImage(out vec4 O, in vec2 U){ O = vec4(vig(U, iResolution.xy)); }
            """)
        let (doc, _) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("float vig(vec2 uv, vec2 iResolution)"), doc.glslBody)
        XCTAssertTrue(doc.glslBody.contains("vig(U, vec3(RENDERSIZE, 1.0).xy)"), doc.glslBody)
    }
```

- [ ] **Step 2: Run to verify failure** — `rewriteScoped` undefined.

- [ ] **Step 3: Implement in `UniformRewriter`** (below the existing `rewrite`):

```swift
    /// Scope-aware uniform rewrite (C5/M20): rewrites every detectable Shadertoy uniform EXCEPT
    /// occurrences inside a function whose OWN parameter list declares that name (the author
    /// threads the uniform through as a parameter — substituting the mapped expression into the
    /// declaration or its uses would corrupt the code). File scope, directive bodies, and
    /// unshadowed function bodies all rewrite. Comment content is never rewritten.
    ///
    /// Replaces both the whole-string per-pass call (M20: paste-path helpers now protected) and
    /// CommonUniformRewriter's indiscriminate depth>0 protection (C5: unshadowed Common helper
    /// bodies now rewritten instead of shipping raw `iTime`).
    public static func rewriteScoped(_ code: String) -> String {
        let masked = GLSLScanner.strip(code)
        let mns = masked as NSString
        let defs = GLSLFunctionScanner.functionDefs(in: code)

        func isProtected(_ pos: Int, _ name: String) -> Bool {
            for d in defs where pos >= d.start && pos < d.end {
                return d.paramNames.contains(name)
            }
            return false
        }

        var edits: [(NSRange, String)] = []
        // Indexed forms first (same rationale as `rewrite`: consume the whole `name[…]` access;
        // ranges can't overlap the word rules — no rule name is a substring of these at `\b`).
        let indexed: [(name: String, pattern: String, replacement: String)] = [
            ("iChannelResolution", "iChannelResolution\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]",
             "vec3(RENDERSIZE, 1.0)"),
            ("iChannelTime", "iChannelTime\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]", "TIME"),
        ]
        for f in indexed {
            let re = try! NSRegularExpression(pattern: f.pattern)
            for m in re.matches(in: masked, range: NSRange(location: 0, length: mns.length))
            where !isProtected(m.range.location, f.name) {
                edits.append((m.range, f.replacement))
            }
        }
        for (from, to) in rules {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b")
            for m in re.matches(in: masked, range: NSRange(location: 0, length: mns.length))
            where !isProtected(m.range.location, from) {
                edits.append((m.range, to))
            }
        }
        guard !edits.isEmpty else { return code }
        let out = NSMutableString(string: code)
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            out.replaceCharacters(in: range, with: replacement)
        }
        return out as String
    }

    /// Post-rewrite tripwire (replaces the C5-interim `unrewrittenBodyUniforms`): detectable
    /// uniform names still present (outside comments) in ALREADY-REWRITTEN code, excluding
    /// legitimate param-shadowed uses. Non-empty means something the scoped rewrite should have
    /// handled slipped through (e.g. a bare un-indexed iChannelResolution) — callers warn loudly.
    public static func unresolvedUniformUses(_ rewrittenCode: String) -> [String] {
        let masked = GLSLScanner.strip(rewrittenCode)
        let mns = masked as NSString
        let defs = GLSLFunctionScanner.functionDefs(in: rewrittenCode)
        var out: [String] = []
        for name in detectableNames {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            let hits = re.matches(in: masked, range: NSRange(location: 0, length: mns.length))
            let unresolved = hits.contains { m in
                let d = defs.first { m.range.location >= $0.start && m.range.location < $0.end }
                return !(d?.paramNames.contains(name) ?? false)
            }
            if unresolved { out.append(name) }
        }
        return out
    }
```

- [ ] **Step 4: Rewire `ISFConverter`.**
  - Stage 2 (line 56): `code = UniformRewriter.rewrite(code)` → `code = UniformRewriter.rewriteScoped(code)`.
  - Stage 7 (line 119): `var commonCode = CommonUniformRewriter.rewrite(channelRewrite.rewrittenCommon)` → `var commonCode = UniformRewriter.rewriteScoped(channelRewrite.rewrittenCommon)`.
  - Interim-warning loop (lines 123–127) → tripwire on the REWRITTEN code, message updated:

```swift
        // Tripwire (C5 is now fixed structurally): any detectable uniform that SURVIVED the
        // scope-aware rewrite outside a param-shadowed position means a case the rewriter
        // doesn't map (e.g. bare un-indexed iChannelResolution) — surface it loudly.
        for name in UniformRewriter.unresolvedUniformUses(commonCode) {
            warnings.append(ConversionWarning(severity: .warning,
                message: "\(name) survived uniform rewriting in the Common tab (no ISF mapping applies at this use) — the shader may fail to compile. Verify or rework the use.",
                context: "Common"))
        }
```

  - Stage-list comment: stage 2 → `UniformRewriter.rewriteScoped (scope-aware — param-shadowed names protected; incl. iMouse mirror)`; stage 7 → `UniformRewriter.rewriteScoped (same primitive as stage 2)`.
  - `git rm` `CommonUniformRewriter.swift`; grep `CommonUniformRewriter` → zero hits.
- [ ] **Step 5:** Full kit suite green. **Corpus gate** — this is the change expected to flip C5-attributed BLACK ids to OK; verify against the Task 1 table. Any OK→FAIL: revert this task's ISFConverter wiring (keep the new APIs + tests) and diagnose before re-landing.
- [ ] **Step 6: Commit** — `fix(conv): scope-aware uniform rewriting everywhere — C5 (Common bodies) + M20 (paste path); CommonUniformRewriter deleted (last hand-rolled walker gone, M3 complete)`

---

### Task 9: M18 — Common-aware, comment-aware macro scoping [CORPUS]

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLPassMacroScoper.swift`
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Builders/GLSLBodyBuilder.swift:23` (pass `commonCode` through)
- Test: `GLSLPassMacroScoperTests.swift`

**Interfaces:**
- Consumes: `GLSLScanner.strip`.
- Produces: `GLSLPassMacroScoper.scope(_ passBodies: [String], commonCode: String) -> [String]` (signature change; `GLSLBodyBuilder.build` is the only caller — it already holds `commonCode`).

- [ ] **Step 1: Write the failing tests:**

```swift
    /// M18 — a pass redefining a Common macro: `#undef` inserted immediately BEFORE the pass's
    /// own `#define` (code above it legitimately uses the Common meaning), and the Common
    /// definition restored after the pass so later passes/Common helpers keep their meaning.
    func test_passDefineShadowingCommonMacro_undeffedAndRestored_M18() {
        let common = "#define A 1.0"
        let passes = ["float x = A;\n#define A 2.0\nfloat y = A;", "float z = A;"]
        let out = GLSLPassMacroScoper.scope(passes, commonCode: common)
        XCTAssertTrue(out[0].contains("float x = A;\n#undef A\n#define A 2.0"), out[0])
        XCTAssertTrue(out[0].hasSuffix("#undef A\n#define A 1.0"), out[0])
        XCTAssertEqual(out[1], "float z = A;")
    }

    /// M18 comment-awareness — a macro name mentioned only inside another pass's COMMENT is not
    /// a collision; no spurious #undef.
    func test_macroMentionedOnlyInComment_noUndef_M18() {
        let passes = ["#define B 1.0\nfloat x = B;", "// B is prose here\nfloat y = 0.;"]
        let out = GLSLPassMacroScoper.scope(passes, commonCode: "")
        XCTAssertEqual(out, passes)
    }

    /// A #define inside a comment is not a definition.
    func test_commentedOutDefine_notCollected() {
        let passes = ["// #define C 1.0\nfloat x = 0.;", "#define C 2.0\nfloat y = C;"]
        let out = GLSLPassMacroScoper.scope(passes, commonCode: "")
        XCTAssertEqual(out, passes)   // C defined in one pass only, mentioned nowhere else → untouched
    }
```

Existing 4 tests must keep passing with `commonCode: ""` added at their call sites.

- [ ] **Step 2: Run to verify failure** (signature + behaviors).

- [ ] **Step 3: Implement.** Rework `scope`:

```swift
    static func scope(_ passBodies: [String], commonCode: String) -> [String] {
        let defineRe = try! NSRegularExpression(
            pattern: "(?m)^[ \\t]*#define[ \\t]+([A-Za-z_]\\w*)")
        // All detection runs on comment-masked text (offsets are identical to the originals):
        // a #define inside a comment is not a definition, a name mentioned only in a comment is
        // not a collision (M18's comment-awareness; was: spurious #undef).
        let strippedBodies = passBodies.map { GLSLScanner.strip($0) }
        let strippedCommon = GLSLScanner.strip(commonCode)

        // 0. Common macros: name → the full original #define line (for restore-after-shadowing).
        var commonDefineLine: [String: String] = [:]
        let lineRe = try! NSRegularExpression(pattern: "(?m)^[ \\t]*#define[ \\t]+([A-Za-z_]\\w*).*$")
        let scn = strippedCommon as NSString
        for m in lineRe.matches(in: strippedCommon, range: NSRange(location: 0, length: scn.length)) {
            let name = scn.substring(with: m.range(at: 1))
            if commonDefineLine[name] == nil {
                commonDefineLine[name] = (commonCode as NSString).substring(with: m.range)
            }
        }

        // 1. Each pass's own macro definitions (name + the match location of the #define line).
        var definedPerPass: [[(name: String, at: Int)]] = []
        for body in strippedBodies {
            let s = body as NSString
            var defs: [(String, Int)] = []
            var seen = Set<String>()
            for m in defineRe.matches(in: body as String, range: NSRange(location: 0, length: s.length)) {
                let name = s.substring(with: m.range(at: 1))
                if seen.insert(name).inserted { defs.append((name, m.range.location)) }
            }
            definedPerPass.append(defs)
        }

        // 2. For each defined name, which passes mention it as a whole word (masked text).
        var passesMentioning: [String: Set<Int>] = [:]
        for name in Set(definedPerPass.flatMap { $0.map(\.name) }) {
            let wordRe = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            for (idx, body) in strippedBodies.enumerated() {
                let s = body as NSString
                if wordRe.firstMatch(in: body as String,
                                     range: NSRange(location: 0, length: s.length)) != nil {
                    passesMentioning[name, default: []].insert(idx)
                }
            }
        }

        var out = passBodies
        for (idx, defs) in definedPerPass.enumerated() {
            var body = out[idx]
            // 3a. Common shadowing (M18): `#undef` right before the pass's own redefinition,
            // restore the Common definition after the pass body.
            let shadowingCommon = defs.filter { commonDefineLine[$0.name] != nil }
            for def in shadowingCommon.sorted(by: { $0.at > $1.at }) {   // back-to-front insert
                let ns = body as NSString
                body = ns.substring(to: def.at) + "#undef \(def.name)\n" + ns.substring(from: def.at)
            }
            if !shadowingCommon.isEmpty {
                let restores = shadowingCommon.map { "#undef \($0.name)\n\(commonDefineLine[$0.name]!)" }
                body = body + "\n" + restores.joined(separator: "\n")
            }
            // 3b. Pass-vs-pass collisions (pre-existing behavior): trailing #undef for macros this
            // pass defines that another pass mentions. Common-shadowing names already got theirs.
            let shadowNames = Set(shadowingCommon.map(\.name))
            let colliding = defs.map(\.name).filter { name in
                !shadowNames.contains(name)
                    && (passesMentioning[name]?.contains(where: { $0 != idx }) ?? false)
            }
            if !colliding.isEmpty {
                body = body + "\n" + colliding.map { "#undef \($0)" }.joined(separator: "\n")
            }
            out[idx] = body
        }
        return out
    }
```

Update `GLSLBodyBuilder.build` line 23: `let scoped = GLSLPassMacroScoper.scope(namespaced)` → `let scoped = GLSLPassMacroScoper.scope(namespaced, commonCode: commonCode)`.

Note: `def.at` positions were computed on the pre-insert body — inserting back-to-front (highest offset first) keeps earlier offsets valid.

- [ ] **Step 4:** Kit suite green (fix the 4 existing tests' call sites), then **corpus gate**.
- [ ] **Step 5: Commit** — `fix(conv): macro scoper sees Common macros + ignores comments (M18)`

---

### Task 10: N2 — reserved-identifier renames skip comments [CORPUS]

**Files:**
- Modify: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/GLSLReservedIdentifierRewriter.swift`
- Test: `GLSLReservedIdentifierRewriterTests.swift`

- [ ] **Step 1: Write the failing test:**

```swift
    /// N2 — reserved words inside comments are prose, not identifiers; renaming them pollutes
    /// output the user reads (`// new approach` became `// usr_new approach`).
    func test_reservedWordInComment_notRenamed_N2() {
        let src = "// try the new approach\nfloat new_x = 1.0; int new = 2;"
        let out = GLSLReservedIdentifierRewriter.rewrite(src)
        XCTAssertTrue(out.contains("// try the new approach"), out)
        XCTAssertTrue(out.contains("float new_x = 1.0"), out)     // word boundary holds
        XCTAssertTrue(out.contains("int usr_new = 2"), out)       // real identifier renamed
    }
```

- [ ] **Step 2: Run to verify failure** (comment gets renamed today).

- [ ] **Step 3: Implement** — replace `rewrite`:

```swift
    public static func rewrite(_ code: String) -> String {
        // Match on comment-masked text (N2: a reserved word in a comment is prose), edit the
        // original at the same UTF-16 offsets, back-to-front.
        let masked = GLSLScanner.strip(code)
        let mns = masked as NSString
        var edits: [(NSRange, String)] = []
        for name in reserved {
            let re = try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b")
            for m in re.matches(in: masked, range: NSRange(location: 0, length: mns.length)) {
                edits.append((m.range, prefix + name))
            }
        }
        guard !edits.isEmpty else { return code }
        let out = NSMutableString(string: code)
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            out.replaceCharacters(in: range, with: replacement)
        }
        return out as String
    }
```

- [ ] **Step 4:** Kit suite, **corpus gate**.
- [ ] **Step 5: Commit** — `fix(conv): reserved-identifier renames skip comment content (N2)`

---

### Task 11: M1 — OutputInitializer runs per-pass (the one pipeline reorder) [CORPUS]

**Files:**
- Modify: `ISFConverter.swift` (insert per-pass+Common stage after HeaderMacroExpander; delete merged-file stage 12; renumber the stage-list comment)
- Test: `ISFConverterTests.swift`

**Interfaces:**
- Consumes: `OutputInitializer.apply(_:) -> RewriteResult` (Task 7 shape). No signature changes.

- [ ] **Step 1: Write the failing pipeline test:**

```swift
    /// M1 — multipass: pass 0 plainly assigns `O`, pass 1 accumulates into `O` before assigning.
    /// The merged-file detector saw pass 0's plain `=` first and skipped pass 1 → NaN/black pass.
    /// Per-pass runs must inject the initializer into pass 1.
    func test_multipass_accumulatorSecondPass_isInitialized_M1() {
        let bufA = RenderPass(inputs: [], outputs: [PassOutput(id: "buf0", channel: 0)],
                              code: "void mainImage(out vec4 O, in vec2 U){ O = vec4(1.0); }",
                              name: "Buf A", type: .buffer)
        let img = RenderPass(inputs: [], outputs: [PassOutput(id: "img", channel: 0)],
                             code: "void mainImage(out vec4 O, in vec2 U){ for(int i=0;i<4;i++){ O += vec4(0.1); } }",
                             name: "Image", type: .image)
        let shader = Shader(info: Info(id: "m1", name: "m1", username: nil, description: nil),
                            renderpass: [bufA, img])
        let (doc, warnings) = ISFConverter.convert(shader)
        XCTAssertTrue(doc.glslBody.contains("O = vec4(0.0);"), doc.glslBody)
        XCTAssertTrue(warnings.contains { $0.message.contains("Auto-initialized output 'O'")
                                          && $0.context == "Image" })
    }
```

- [ ] **Step 2: Run to verify failure** (no injection today — the false negative).

- [ ] **Step 3: Implement.** In `ISFConverter.convert`, after `let expanded = HeaderMacroExpander.expand(…)` and before `GLSLBodyBuilder.build`:

```swift
        // M1: run the uninitialized-accumulator fix on each ISOLATED pass body (and on Common's
        // helpers) BEFORE concatenation — on the merged file, pass 0's plain `O =` masked pass 1's
        // compound-first `O` (both passes name their output `O`; the whole-file test dedups names).
        // After HeaderMacroExpander so header-macro shaders' expanded mainImage signatures are seen.
        var initializedBodies: [String] = []
        for (idx, body) in expanded.passBodies.enumerated() {
            let r = OutputInitializer.apply(body)
            warnings.append(contentsOf: r.warnings.map {
                ConversionWarning(severity: $0.severity, message: $0.message,
                                  context: plan.renderPasses[idx].name)
            })
            initializedBodies.append(r.code)
        }
        let commonInitialized = OutputInitializer.apply(expanded.commonCode)
        warnings.append(contentsOf: commonInitialized.warnings.map {
            ConversionWarning(severity: $0.severity, message: $0.message, context: "Common")
        })
        let glsl = GLSLBodyBuilder.build(passBodies: initializedBodies,
                                         commonCode: commonInitialized.code)
```

Delete the merged-file stage: `let initialized = OutputInitializer.apply(reserved)` + its warnings line; `GLSLCompat.apply(initialized.code)` → `GLSLCompat.apply(reserved)`; `GLSLLint.check(initialized.code)` → `GLSLLint.check(reserved)`. Update the stage-list comment (lines 8–17) to:

```
///   Per pass:  1. GLSLLineContinuation.splice   2. UniformRewriter.rewriteScoped (incl. iMouse mirror)
///              3. channel auto-stub             4. SamplerRewriter
///   Common:    5. GLSLLineContinuation.splice   6. CommonChannelRewriter (PASSINDEX dispatch)
///              7. UniformRewriter.rewriteScoped  8. HeaderMacroExpander
///              8b. OutputInitializer — PER PASS BODY + Common, before concatenation (M1)
///              9. GLSLBodyBuilder.build, which internally runs, IN ORDER:
///                   9a. GLSLPassNamespace (rename cross-pass colliding helpers/globals)
///                   9b. GLSLPassMacroScoper  (#undef per-pass #defines; Common-aware — M18)
///                   9c. per-pass mainImage rename + PASSINDEX dispatch assembly
///             10. GLSLFunctionDedup   11. GLSLReservedIdentifierRewriter
///             12. GLSLCompat (+ GLSLLint)   13. HeaderBuilder
```

- [ ] **Step 4:** Kit suite, **corpus gate** (expected to flip M1-attributed BLACK ids; single-pass shaders must be byte-stable — the detector sees the same isolated body it effectively saw merged).
- [ ] **Step 5: Commit** — `fix(conv): OutputInitializer per pass body — cross-pass false negative fixed (M1)`

---

### Task 12: M2 — multi-declarator globals [CORPUS]

**Files:**
- Modify: `GLSLGlobalScanner.swift` (declarator split), `GLSLFunctionDedup.swift` (per-declarator keys + range-dedup)
- Test: `GLSLGlobalScannerTests.swift`, `GLSLPassNamespaceTests.swift`, `GLSLFunctionDedupTests.swift`

**Interfaces:**
- Produces: `GLSLGlobalScanner.defs` now emits **one `Def` per declarator** (same `start`/`end` = the whole statement for all declarators of one statement).
- `GLSLFunctionDedup` keys globals as `name + "\u{1F}" + normalize(statement)` and dedups removals by range.

- [ ] **Step 1: Write the failing tests:**

```swift
    // GLSLGlobalScannerTests
    /// M2 — `float a, b, c;` previously matched only `a` (and `float a = 1., b = 2.;` matched as
    /// a single Def named `a`), leaving the rest invisible to dedup/namespacing → cross-pass
    /// redefinition errors.
    func test_commaSeparatedGlobals_allDeclaratorsVisible_M2() {
        let defs = GLSLGlobalScanner.defs(in: "float a, b, c;")
        XCTAssertEqual(defs.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(Set(defs.map(\.start)).count, 1)   // one statement, three declarators
    }

    func test_commaListWithInitializers_M2() {
        XCTAssertEqual(GLSLGlobalScanner.defs(in: "float a = 1., b = 2.;").map(\.name), ["a", "b"])
    }

    func test_initializerCommas_doNotSplitDeclarators_M2() {
        XCTAssertEqual(GLSLGlobalScanner.defs(in: "vec2 q = vec2(1., 2.), r = vec2(3., 4.);").map(\.name),
                       ["q", "r"])
    }

    // GLSLPassNamespaceTests
    /// M2 end-to-end: comma globals colliding across passes with differing values are ALL renamed.
    func test_commaGlobals_collidingAcrossPasses_allRenamed_M2() {
        let out = GLSLPassNamespace.namespace([
            "float a = 1., b = 2.;\nfloat u(){ return a + b; }",
            "float a = 3., b = 4.;\nfloat v(){ return a + b; }",
        ])
        XCTAssertTrue(out[0].contains("p0_a") && out[0].contains("p0_b"), out[0])
        XCTAssertTrue(out[1].contains("p1_a") && out[1].contains("p1_b"), out[1])
    }

    // GLSLFunctionDedupTests
    /// M2 — identical comma-global statements dedup as ONE removal (not one per declarator).
    func test_identicalCommaGlobalStatement_dedupedOnce_M2() {
        XCTAssertEqual(GLSLFunctionDedup.dedup("float a, b;\nfloat a, b;"), "float a, b;\n")
    }
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** In `GLSLGlobalScanner.defs`, replace the single append with declarator expansion:

```swift
        for m in re.matches(in: masked, range: NSRange(location: 0, length: ms.length)) {
            guard GLSLScanner.braceDepth(code, before: m.range.location) == 0 else { continue }
            guard let end = GLSLScanner.statementEnd(code, from: m.range.location) else { continue }
            let firstName = m.range(at: 1)
            for name in declaratorNames(ms, firstName: firstName, statementEnd: end) {
                out.append(Def(name: name, start: m.range.location, end: end))
            }
        }
```

New private helper:

```swift
    /// All declarator names in a (possibly multi-declarator) global statement — `float a, b = 2., c;`
    /// → ["a","b","c"]. Splits on commas at nesting depth 0 within the statement (commas inside
    /// initializers like `vec2(1., 2.)` or `float[](1., 2.)` sit inside parens/brackets/braces and
    /// are not declarator boundaries). `masked` is comment-blanked, so comment commas are spaces.
    private static func declaratorNames(_ masked: NSString, firstName: NSRange,
                                        statementEnd end: Int) -> [String] {
        var names = [masked.substring(with: firstName)]
        var depth = 0
        var commas: [Int] = []
        var i = firstName.location + firstName.length
        while i < end {
            switch masked.character(at: i) {
            case 40, 91, 123: depth += 1                    // ( [ {
            case 41, 93, 125: if depth > 0 { depth -= 1 }   // ) ] }
            case 44: if depth == 0 { commas.append(i) }     // ,
            default: break
            }
            i += 1
        }
        guard !commas.isEmpty else { return names }
        let idRe = try! NSRegularExpression(pattern: "[A-Za-z_]\\w*")
        for c in commas {
            if let m = idRe.firstMatch(in: masked as String,
                                       range: NSRange(location: c + 1, length: end - c - 1)) {
                names.append(masked.substring(with: m.range))
            }
        }
        return names
    }
```

In `GLSLFunctionDedup.dedup`, keep names with the globals and dedup removals by range:

```swift
        let defs: [(name: String?, start: Int, end: Int)] =
            (GLSLFunctionScanner.defs(in: code).map { (name: nil, start: $0.start, end: $0.end) }
             + GLSLGlobalScanner.defs(in: code).map { (name: $0.name, start: $0.start, end: $0.end) })
            .sorted { $0.start < $1.start }
        var removedStarts = Set<Int>()
        for d in defs {
            let block = s.substring(with: NSRange(location: d.start, length: d.end - d.start))
            // Globals key per-DECLARATOR (name + statement): `float a, b;` twice must remove the
            // second statement exactly once, while `float a;` vs `float a, b;` must NOT collapse.
            let key = (d.name.map { $0 + "\u{1F}" } ?? "") + GLSLFunctionScanner.normalize(block)
            if seen.contains(key) {
                if removedStarts.insert(d.start).inserted { removals.append((d.start, d.end)) }
            } else { seen.insert(key) }
        }
```

(`GLSLPassNamespace` needs no change: it already builds per-Def `(name, key)` entries; more Defs per statement = more entries, and its whole-word rename per name handles comma statements. Its normalize key covers the whole statement — two passes with any textual difference rename ALL that statement's declarators per-pass, which is semantically exactly Shadertoy's per-pass isolation.)

- [ ] **Step 4:** Kit suite, **corpus gate** (M2-attributed ids should flip; namespacing behavior on the rest of the corpus must hold the pass list).
- [ ] **Step 5: Commit** — `fix(kit): multi-declarator global scanning — comma lists visible to dedup/namespacing (M2)`

---

### Task 12b: ZeroInitLocals — zero-initialize uninitialized local declarators [CORPUS]

_(Added at the Task-1 checkpoint with Conner's approval, 2026-07-09: triage attributed 6/10 BLACKs to this class. ANGLE zero-initializes locals on WebGL; Metal does not — golf shaders (`float i, d, z, r;` + `for(O*=i; i++<9e1;)`, `for (float i; i<…;)`) read garbage guards and render black.)_

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/ZeroInitLocals.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/ZeroInitLocalsTests.swift`
- Modify: `ISFConverter.swift` (per-pass + Common, stage 8c alongside 8b; stage-list comment)
- Modify: `ISFConverterTests.swift` (pipeline test)

**Interfaces:**
- Consumes: `GLSLScanner.strip/braceDepth/statementEnd/braceMatchEnd`, `GLSLGlobalScanner`-style declarator logic, `RewriteResult`.
- Produces: `ZeroInitLocals.rewrite(_ code: String) -> RewriteResult` (info note listing initialized names when any).

**Design constraints (all asserted by tests):**
- Only LOCAL statement declarations (brace depth ≥ 1) and `for (TYPE i; …)` / `for (TYPE i, j; …)` init-less loop declarations.
- Only whitelisted zeroable types: `float→0.0`, `int→0`, `uint→0u`, `bool→false`, `vec2/3/4→vecN(0.0)` (same for `ivec/uvec/bvec` with their scalar), `mat2/3/4→matN(0.0)` (matches ANGLE's zero matrices, NOT identity). Any other type (user structs, samplers): declarator untouched.
- Only declarators WITHOUT an initializer; declarators with `[` array suffix untouched (array constructors are noisy and absent from the golf idiom).
- `const` declarations untouched (valid GLSL const declarators are always initialized anyway).
- **struct bodies excluded**: declarations inside `struct … { … }` spans (found via `\bstruct\b[^{;]*\{` + `GLSLScanner.braceMatchEnd`) must NOT gain initializers — member initializers are illegal.
- Comment-masked matching; edits applied to the original back-to-front.
- Runs per pass body AND on Common (helpers use the same idiom).

- [ ] **Step 1: Write failing tests** (representative set — the executor writes these exactly):

```swift
import XCTest
@testable import ShadertoyISFKit

final class ZeroInitLocalsTests: XCTestCase {
    func test_commaDeclaredScalars_initialized() {
        let out = ZeroInitLocals.rewrite("void f(){ float t = 1.0,i,z,d; }")
        XCTAssertEqual(out.code, "void f(){ float t = 1.0,i = 0.0,z = 0.0,d = 0.0; }")
        XCTAssertEqual(out.warnings.count, 1)
        XCTAssertTrue(out.warnings[0].message.contains("i, z, d"))
    }

    func test_vectorLocals_initialized() {
        XCTAssertEqual(ZeroInitLocals.rewrite("void f(){ vec4 o, P; }").code,
                       "void f(){ vec4 o = vec4(0.0), P = vec4(0.0); }")
    }

    func test_initlessForLoopVar_initialized() {
        XCTAssertEqual(ZeroInitLocals.rewrite("void f(){ for (float i; i < 8.; i++) {} }").code,
                       "void f(){ for (float i = 0.0; i < 8.; i++) {} }")
    }

    func test_fileScopeGlobals_untouched() {
        let src = "float g;\nvoid f(){ }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_structMembers_untouched() {
        let src = "void f(){ struct S { float a, b; }; S s = S(1., 2.); }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_constAndInitialized_untouched() {
        let src = "void f(){ const float c = 1.0; float x = 2.0; }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_arrayAndUserStructDeclarators_untouched() {
        let src = "void f(){ float arr[4]; MyType m; }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }

    func test_commentedDeclaration_untouched() {
        let src = "void f(){ // float i, j;\n float k = 1.; }"
        XCTAssertEqual(ZeroInitLocals.rewrite(src).code, src)
    }
}
```

- [ ] **Step 2:** Run → FAIL (type undefined).
- [ ] **Step 3: Implement** `ZeroInitLocals.rewrite`: masked = strip(code); struct spans precomputed; two match passes over masked — (a) statement declarations `(?m)(?<![\w.])(float|int|uint|bool|[iub]?vec[234]|mat[234])[ \t]+` at braceDepth≥1 whose statement (to `statementEnd`) splits into declarators (reuse the declarator-split approach from Task 12, generalized to also return each declarator's range and has-initializer flag); (b) for-init declarations `for[ \t]*\([ \t]*(TYPE)[ \t]+…;` handled by the same declarator splitter bounded by the first `;` at paren depth 1. For each uninitialized, non-array declarator of a whitelisted type not inside a struct span: insert ` = <zero>` right after the declarator name. Apply inserts back-to-front. Emit one info `ConversionWarning` naming the initialized identifiers (context filled by the converter call site).
- [ ] **Step 4: Wire into `ISFConverter`** as stage 8c beside 8b (per pass with pass-name context, plus Common), stage-list comment updated.
- [ ] **Step 5: Pipeline test** (`ISFConverterTests`): the 3XBBWD golf shape `void mainImage( out vec4 o, in vec2 I ){ float t = iTime,i,z,d; for(o*=i;i++<80.;){} }` converts with `i = 0.0` present and an info warning.
- [ ] **Step 6:** Kit suite, **corpus gate** — expect the six zero-init BLACKs (`wc33RN wX33zX XXVfRV wfX3WX lcXXzM 33jcRR 3XBBWD` minus any that also need more) to flip; pass-list otherwise identical.
- [ ] **Step 7: Commit** — `fix(conv): zero-initialize uninitialized locals — Metal lacks ANGLE's zero-init; flips the golf-shader black class`

---

### Task 12c: InjectedNameGuard — user identifiers colliding with ISF-injected names [CORPUS]

_(Added at the Task-1 checkpoint: tXfBz2's `vec2 mouse = iMouse.xy` — the iMouse rewrite makes the initializer reference the ISF `mouse` input, which the just-declared local shadows self-referentially.)_

**Files:**
- Create: `ShadertoyISFKit/Sources/ShadertoyISFKit/Rewriters/InjectedNameGuard.swift`
- Create: `ShadertoyISFKit/Tests/ShadertoyISFKitTests/InjectedNameGuardTests.swift`
- Modify: `ISFConverter.swift` (stage 1b, right after splice, before any uniform rewriting; stage-list comment)
- Modify: `ISFConverterTests.swift`

**Interfaces:**
- Consumes: `GLSLScanner.strip`.
- Produces: `InjectedNameGuard.Result { passBodies: [String]; commonCode: String; warnings: [ConversionWarning] }`, `rewrite(passBodies:commonCode:) -> Result`.

**Design:** guarded names = identifiers our output injects references to at user scope: `mouse`, `RENDERSIZE`, `TIME`, `TIMEDELTA`, `FRAMEINDEX`, `DATE`, `PASSINDEX`. None mean anything in Shadertoy GLSL, so ANY whole-word occurrence in the ORIGINAL source is the user's identifier. Decision is per-shader: if a name occurs (comment-masked) in any pass or Common, rename every occurrence in ALL passes + Common to `usr_<name>` (`GLSLReservedIdentifierRewriter.prefix` convention — cross-tab helpers keep working). Emit one info warning per renamed name. Runs BEFORE uniform rewriting so the rewrites' injected references can never be shadowed.

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import ShadertoyISFKit

final class InjectedNameGuardTests: XCTestCase {
    func test_userMouseLocal_renamedEverywhere() {
        let r = InjectedNameGuard.rewrite(
            passBodies: ["void mainImage(out vec4 O, in vec2 U){ vec2 mouse = iMouse.xy; O = vec4(mouse, 0, 1); }"],
            commonCode: "")
        XCTAssertTrue(r.passBodies[0].contains("vec2 usr_mouse = iMouse.xy"), r.passBodies[0])
        XCTAssertTrue(r.passBodies[0].contains("vec4(usr_mouse, 0, 1)"), r.passBodies[0])
        XCTAssertEqual(r.warnings.count, 1)
    }

    func test_commonHelperNamedTIME_renamedInPassToo() {
        let r = InjectedNameGuard.rewrite(
            passBodies: ["void mainImage(out vec4 O, in vec2 U){ O = vec4(TIME(1.)); }"],
            commonCode: "float TIME(float x){ return x; }")
        XCTAssertTrue(r.commonCode.contains("float usr_TIME(float x)"))
        XCTAssertTrue(r.passBodies[0].contains("usr_TIME(1.)"))
    }

    func test_nameOnlyInComment_notRenamed() {
        let r = InjectedNameGuard.rewrite(
            passBodies: ["// mouse driven\nvoid mainImage(out vec4 O, in vec2 U){ O = vec4(1); }"],
            commonCode: "")
        XCTAssertEqual(r.passBodies[0], "// mouse driven\nvoid mainImage(out vec4 O, in vec2 U){ O = vec4(1); }")
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func test_noCollisions_identity() {
        let r = InjectedNameGuard.rewrite(passBodies: ["void mainImage(out vec4 O, in vec2 U){ O = vec4(1); }"],
                                          commonCode: "")
        XCTAssertTrue(r.warnings.isEmpty)
    }
}
```

- [ ] **Step 2:** Run → FAIL. **Step 3: Implement** (masked whole-word detection per name across all codes; masked-match + original back-to-front rename in each). **Step 4: Wire** as stage 1b in `ISFConverter` (after all per-pass splices and the Common splice — restructure: splice everything first, then guard, then proceed; keep the detection scans reading the GUARDED code). **Step 5:** pipeline test: tXfBz2 shape converts with `usr_mouse` and compiles the `mouse * RENDERSIZE` rewrite un-shadowed. **Step 6:** kit suite + **corpus gate** (tXfBz2 → OK expected). **Step 7: Commit** — `fix(conv): guard ISF-injected names against user identifier collisions (tXfBz2 mouse-shadowing class)`

---

### Task 13: Full gates, DESLOPPIFY close-out, docs

**Files:**
- Modify: `DESLOPPIFY.md` (items + header), `docs/superpowers/plans/2026-07-08-launch-hardening-and-elevation.md` (Task 3.2 → DONE)
- Test: everything

- [ ] **Step 1: Full verification battery.**
  1. Kit: `cd ShadertoyISFKit && swift test 2>&1 | tail -3` → 0 failures.
  2. App: full app-test command (Global Constraints) → `TEST SUCCEEDED`, ≥ 227 tests (224 + Task 1's 3).
  3. Release build: `cd App && xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath ./ddata-release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"` → SUCCEEDED.
  4. Full corpus: `./scripts/corpus-run.sh --build` + baseline compare. **Acceptance: compile pass-list identical by ID; pixel OK ≥ 64/78; every Task-1 id attributed C5/M1/M2/M20 now `OK`.** Save the report: `cp "${TMPDIR:-/tmp/}conversion-corpus-report.txt" docs/corpus-analysis-$(date +%F)-task32.txt`.
- [ ] **Step 2: Close DESLOPPIFY items** — M3, N1, C5, M14, M18, M20, N2, M1, M2 → `- **Status:** done` + one-line `- **Resolved:** …` each (cite the shared scanner, the masked-match idiom, and the new corpus numbers); update the header line (open/done counts + new pixel numbers); note C1's parseArgs concern is structurally gone (one comment machine).
- [ ] **Step 3: Update the plan of record** — Task 3.2 marked DONE with the corpus numbers; note the C5 launch decision (plan "Decisions needed" #6) can now close as SHIPPED-FIXED if the corpus confirms.
- [ ] **Step 4: Exhaust-the-universe sweep** (no truncation, paste counts into the session summary):

```bash
grep -rn "inLine\b\|inBlock\b" ShadertoyISFKit/Sources --include='*.swift'   # expect: GLSLScanner.swift only
grep -rn "GLSLComments\|CommonUniformRewriter\|walkRuns\|parseArgs\|matchesIdentifier" ShadertoyISFKit App --include='*.swift'  # expect: zero hits
```

- [ ] **Step 5: Commit** — `docs(desloppify): Task 3.2 complete — one scanner primitive; C5/M1/M2/M3/M14/M18/M20/N1/N2 closed; corpus <numbers>`

---

## Self-review notes (writing-time)

- **Spec coverage:** Task 0→1, scanner→2, migrations→3–6, N1→7 (moved before design changes so they use RewriteResult; spec listed it after migrations — same position in the dependency order), C5/M20→8, M18→9, N2→10, M1→11, M2→12, exit criteria→13. M19 needs no task (absorbed as `strip`).
- **Spec deviation (recorded in Task 7):** pure String→String transforms stay bare-String rather than wrapping in `RewriteResult(warnings: [])`; the spec file gets a one-line amendment in that task's commit.
- **Type consistency check:** `RewriteResult{code,warnings}` used by Tasks 7/8/11; `FunctionDef{name,paramNames,start,end}` defined Task 6, consumed Task 8; `scope(_:commonCode:)` defined Task 9 with its only caller updated in the same task; `splitArgs` returns `(argRanges:[NSRange], close:Int)` — Task 4 consumes exactly that.
- **Behavior changes beyond the named fixes** (all corpus-gated where they land): scanner-based depth/statement/brace-match queries are directive-aware (Tasks 5/6 — hardens the ssjyWc class in dedup/namespace paths); `strip` is UTF-16-exact where the old Character walk drifted on astral chars in comments (Task 3); commented-out `#define`s no longer collected (Task 9).
