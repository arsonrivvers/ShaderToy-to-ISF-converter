---
schema_version: 1
topic: datamosh-node
date: 2026-08-03
tier: just-me
status: complete
correlation_id: arshader-datamosh-node-20260803
builds_on: docs/superpowers/specs/2026-07-30-native-performance-instrument-design.md
source_repos:
  - ~/Desktop/AV_Projects/max-mcp/interstream-td   (our TouchDesigner datamosh component)
  - github.com/ericsouther-source/mosh-top          (Eric Souther / Philosophical Tools, MIT wrapper)
  - github.com/ramiropolla/ffglitch-core            (FFmpeg fork, branch ffedit-0.10)
---

# Datamosh Node — a native out-of-process FX node for ARShader

## 1. What this is

A datamosh / codec-glitch effect that appears in ARShader's effect library and can be dropped
into the FX chain of deck 1, deck 2, or master. It performs **authentic codec-domain glitch** —
real encode, real bitstream manipulation, real decode — not a pixel-domain imitation.

It is also the **first non-ISF node in ARShader**, and therefore the first test of an effect-node
abstraction that is not "an ISF shader." That is the larger reason to build it carefully: the
node-graph workspace this project eventually wants (section 13) needs exactly this abstraction,
and the first native node is what defines it.

## 2. Where the capability comes from

Three sources, and it is worth being precise about which contributes what, because they are not
equivalent.

**mosh-top** (Eric Souther, MIT-licensed wrapper) is the primary source. It is a TouchDesigner
C++ TOP built on ffglitch-core, and it is a mechanically deeper instrument than ours. It was
cloned, built, and tested on this machine on 2026-08-02 at tag `v1.3`: a clean checkout built on macOS arm64
with `cmake -S . -B build-mac`, produced a 16 MB self-contained plugin linking only system
frameworks, and passed 14 of 14 ctest targets.

**ffglitch-core** (Ramiro Polla) is what makes mosh-top possible and is the single most valuable
discovery of this research. Its `ffedit` layer exports compressed-bitstream syntax — motion
vectors, quantized DCT coefficients, quantizers, per-macroblock bytestreams — as an editable JSON
tree, then re-encodes the edited syntax back into a valid packet ("transplication"). This permits
a class of effect our own tool cannot reach at all:

- **Motion Paint** — a control input sampled at macroblock centers, whose red/green channels are
  written directly into real vector syntax.
- **Edit Mask** — a spatial gate over which macroblocks receive syntax edits; outside it, the
  encoder's original bytes survive byte-for-byte.
- **Macroblock Shuffle** — whole coded macroblocks swapped within a packet, each carrying its
  coded bit size so the packet stays aligned.
- **Bitstream Texture Lab** — rewrites of DCT coefficients, DC values, and quantizer tables.

**interstream-td** (ours) contributes the codec-domain work mosh-top lacks: an H.264/libx264
keyframe-free engine, the empirically verified per-codec keyframe-free option table, Fluid Mosh's
burst envelope, and Pixel Persist. It does **not** contribute its modulation matrix, presets, or
audio reactivity — see section 8.

### 2.1 The mechanism distinction

Our component manipulates **packets**: duplicate a P-frame packet and let the decoder re-apply its
motion vectors against a compounding buffer. `core/datamosher.py` documents the finding that makes
this work — dropping keyframe *packets* does not produce smear, because FFmpeg's decoder conceals
orphaned P-frames and yields stutter. P-frame *duplication* on a keyframe-free stream is what
blooms.

mosh-top does that too, and additionally edits **syntax inside the packet**. Both are authentic;
they are different layers of the same stack, and the merged node offers both.

A discipline carried from mosh-top verbatim: *only macroblocks whose syntax already codes a
writable vector are ever painted; nothing synthetic is invented.* When a codec cannot support an
edit, the node passes through with a visible warning rather than substituting a simulated effect.
This is the same instinct as this project's never-unintentionally-black pixel gate.

## 3. Host coupling — why this is a port, not a rewrite

Coupling was measured per file across mosh-top's ~7,700-line wrapper:

| Component | Lines | TouchDesigner-coupled |
|---|---:|---|
| `StreamWorker.cpp/h` — threaded codec pipeline | 3,667 | 2 lines (`OP_TOPDownloadResult`) |
| `Parameters.cpp/h` — struct, parsers, UI declaration | 1,935 | `setupParameters()` + `read()` only; the struct is plain data |
| `MoshOps`, `MvFieldOps`, `PixelRouting`, `FFEditJsonBridge` | 1,499 | none |
| `MoshTOP.cpp/h` — the plugin shim | 594 | all |

Roughly **7,100 of 7,700 lines are host-independent**, and deliberately so — `MvFieldOps.h` states
that its math owns no FFmpeg or ffglitch state specifically so the syntax-editing math is unit
testable against hand-built arrays.

The TouchDesigner host pattern also maps almost directly onto Metal. `downloadTexture()` becomes a
blit into an IOSurface-backed texture; `createOutputBuffer`/`uploadBuffer` become a write into an
output surface. And when the worker has no new frame, `MoshTOP::execute` simply returns and TD
keeps showing the previous texture — which is precisely what `FXChain.encode()` already does on a
nil stage result.

## 4. Decisions taken

| Decision | Choice | Rationale |
|---|---|---|
| Distribution | Personal use only; no public release planned | Removes all LGPL/GPL distribution obligation. libx264 and the GPL-configured builds are available. A `THIRD_PARTY` ledger records what is vendored under what terms so a future release decision is a document to read, not an archaeology project. |
| Code provenance | **Vendor and adapt** mosh-top's `src/` under its MIT notice | Upstream tracking fights us: the port must edit `StreamWorker.cpp` and gut `Parameters.cpp`, so every pull would conflict in the files we changed most. A clean-room rewrite would discard a passing 14-test suite and the empirical per-codec capability knowledge, which is the expensive part to re-derive. |
| Process model | **Out-of-process, XPC + shared IOSurface** | A codec fed deliberately corrupted bitstreams will eventually segfault. Out-of-process means it takes down the node, not the show. Also the correct foundation for the future node workspace, where third-party nodes are untrusted by definition. |
| Clock | **Free-running; pass through on miss** | Matches what the engine already expects and what `FXChain.encode` already does. No new machinery. Datamosh is temporal smear, so a few frames of lag is stylistically camouflaged. |
| Scope | **Full capability set**, ordered by phase | Operator's decision. Section 12 orders the work so the transport is proven before the feature mass lands, and so the node is playable at phase 2. |
| Parameter count | **Keep all ~76** | Operator wants the depth. The problem is disclosure, not count — solved by pages/sections and capability gating, not by cutting. |

## 5. Architecture

Three pieces, two new.

**`FXNodeKit`** — new Swift package, sibling to `ISFRuntimeKit`. The node abstraction plus the host
side of the XPC connection. Knows nothing about datamosh.

**`MoshNode.xpc`** — new XPC service embedded in `ARShader.app`. Contains the vendored engine, the
libx264 engine, and the ffglitch static libraries. It is the only component linking LGPL/GPL code
and the only component that can crash.

**`FXStage` generalization** — an edit to existing code. `FXStage` currently owns a `ShaderUnit`,
and `FXChain.encode` calls `stage.core.renderOffscreen(...)`. That becomes:

```swift
protocol FXStageBacking: Sendable {
    func produce(input: MTLTexture, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?
}
```

`ISFStageBacking` implements it by calling the existing `renderOffscreen` — behavior-identical, and
the existing 227 app + 302 kit tests are the evidence. `NativeNodeBacking` implements it against
the surface ring in section 6. `FXChain.encode`'s body changes by one line, and its existing
`guard let produced = ... else { continue }` becomes pass-through-on-miss at no cost.

## 6. Data flow, one render tick

A native stage does not encode work into the command buffer the way an ISF stage does. It
publishes and polls:

1. **Publish** — blit the incoming `source` texture into the next free slot of an input ring of
   IOSurface-backed `MTLTexture`s, within the same command buffer.
2. **Signal** — on that command buffer's completion handler, notify the service of the slot index
   and the current parameter snapshot. This is the only per-frame crossing of the process
   boundary, and it carries an integer and a struct — never pixels.
3. **Poll** — request the newest ready output surface. If one exists, return it; otherwise return
   `nil` and the chain passes through.
4. **Composite** — the returned texture goes into
   `compositor.encodeLayer(source:backdrop:destination:opacity:mode:preserveAlpha:in:)`, unchanged.
   The node inherits per-stage mix and all 19 blend modes with no new code.

Surfaces are shared once at connection setup via `IOSurfaceCreateXPCObject` /
`IOSurfaceLookupFromXPCObject`, and wrapped host-side with
`MTLDevice.makeTexture(descriptor:iosurface:plane:)`. On Apple Silicon's unified memory both
processes then address the same physical pages; the per-frame IPC is a notification, not a
transfer.

**Ring discipline.** Input and output rings are fixed-size with drop-on-contention: if the host
publishes faster than the service consumes, the oldest unconsumed slot is overwritten. This
matches the engine's existing `SourceInbox` philosophy and bounds memory by construction.

## 7. Inside the node process

`StreamWorker` is vendored essentially intact. Its threading model, latest-frame mailbox,
drop-on-contention inbox, and recycled RGBA storage are already correct for this host. Two edits:

- Input type changes from `OP_SmartRef<OP_TOPDownloadResult>` to an `IOSurfaceRef` plus
  dimensions; locking the surface and reading RGBA8 replaces `getData()`.
- Output writes directly into an output IOSurface rather than returning an `RgbaFrame` for the
  host to upload — removing one full-frame memcpy per frame relative to the TouchDesigner path.

**Input slots.** The engine supports three: two encoder sources (for the dual-input splice) and one
control input (Edit Mask / Motion Paint, which never reaches an encoder). These map onto ARShader
as: slot 1 is the FX chain's own input; slots 2 and 3 are resolved through the existing
`SourceRouter`. Motion Paint therefore accepts a shader, the camera, or the opposite deck as a
real motion source.

## 8. Control model, and what does NOT move into the node

The node ships a **parameter manifest** — its ~76 controls declared as data: name, label, page,
section, type, range, default, and a gating predicate mirroring mosh-top's
`applyParameterGating` (which greys out what the selected codec cannot do). The manifest is
written in the same descriptor shape `ShaderControlsView` already consumes for auto-generated ISF
controls, so the node's UI is the existing UI, and pages plus sections solve parameter density
without cutting anything.

Because values land in `ParamStore` like any ISF input, the modulation-expression layer already in
flight drives all 76 automatically.

**This is why interstream's non-codec features stay behind.** Our LFO/mod-matrix patch bay, preset
snapshot-and-morph, and audio reactivity are all things ARShader either has or is actively
building. Porting them into the node would create a second, competing modulation system living
inside a single FX stage. What ports from interstream is strictly codec-domain: the libx264
keyframe-free engine, the verified per-codec option table, Fluid Mosh's burst envelope, and Pixel
Persist.

## 9. Failure model

The node is the first component in ARShader that can genuinely crash. Four classes:

**Service crash.** XPC's invalidation handler fires; the stage marks itself faulted and passes its
input through. Relaunch is automatic with backoff (250 ms → 5 s cap), restoring the last parameter
snapshot and forcing a keyframe so the new decoder starts clean. Restart count is visible in the
UI. **If restarts exceed a threshold within a window, the node disables itself and reports why** —
a crash loop must never degrade into an invisible strobe diagnosed under stage lighting.

**Capability gap.** Pass through with a visible warning and a greyed parameter. Never a simulated
substitute.

**Damaged packet rejected by the decoder.** Adaptive backoff, or forward the original compressed
packet. Already implemented in the vendored engine.

**Encoder behind.** Not an error — the free-running latency model. Resolves to pass-through, or to
re-emitting the stage's previous output when the per-node *Hold Last Output* toggle is on. That
toggle costs one retained texture and is the difference between a clean strobe and a continuous
smear at high encode resolutions. Default is pass-through.

**Blackout is unaffected.** It is a final gate that clears the master after the entire chain, so no
faulted, wedged, or berserk node can defeat panic. This node is the first real test of that
property, which is why blackout was specified as a gate rather than a stage.

## 10. Testing

1. **The vendored ctest suite, unchanged** — all 14 targets. A failure means the port broke the
   engine. This is the highest-value asset inherited and it costs nothing to keep running.
2. **XPC transport tests** — surface round-trip integrity, ring ordering, drop-on-contention under
   load, teardown without leaking surfaces.
3. **Golden-frame tests** through the existing `PixelGate` / `FramePNGEncoder` headless capture.
   Viable because `MoshOps` carries a seeded xorshift32 with `setSeed()`: fixed seed plus fixed
   input yields byte-stable output, making glitch genuinely regression-testable.
4. **Crash-recovery test** — kill the service mid-render; assert the host survives, the stage
   passes through rather than going black, and relaunch restores parameters.
5. **Live smoke, mandatory.** XPC, the codec, and IOSurface are three protocol boundaries no unit
   test can see. Named pre-flight assertions precede the human-in-the-loop leg.

The "never unintentionally black" pixel gate applies to the node's output.

## 11. Licensing posture

No public distribution is planned, so no LGPL or GPL obligation is triggered — those attach to
distribution, not use. libx264 may be vendored and the GPL-configured builds used freely.

A `THIRD_PARTY.md` ledger records each vendored component, its license, and its pinned commit:
mosh-top's wrapper (MIT), ffglitch-core at `4b71d60c6640ad3f9ce483eac14391dc73f8c950` on branch
`ffedit-0.10` (LGPL-2.1-or-later as configured for macOS), and libx264 (GPL-2.0-or-later) if
added. The ledger exists so that a future decision to release is a document to read rather than an
investigation to run.

Should release ever be reconsidered, the out-of-process design already helps: the LGPL/GPL code is
confined to a separate binary, which is the cleanest starting point for any relicensing or
separate-distribution argument.

## 12. Phasing

Full scope, ordered so the transport is proven before the feature mass lands on it.

| Phase | Delivers | Rationale |
|---|---|---|
| **0** | Vendor `src/`, strip the TD shim, headless CLI harness that moshes a file. 14 tests green outside TouchDesigner. | Proves the engine detached from its host at zero risk to ARShader. |
| **1** | `FXNodeKit`, the `FXStageBacking` protocol, and a `MoshNode.xpc` that only inverts. ISF suites still green. | Isolates the riskiest new thing — surface handoff, ordering, crash recovery — so a failure has one possible cause. |
| **2** | Engine into the service. MPEG family, four mosh modes, Bloom. | **First playable.** |
| **3** | All nine codecs, the libx264 H.264 engine, Fluid Mosh, Pixel Persist. | Where interstream's contribution merges. |
| **4** | Bitstream labs: Motion Lab, Texture Lab, Macroblock Shuffle, Motion Paint and Edit Mask wired through `SourceRouter`. | The ffglitch capability with no equivalent in our tool. |
| **5** | Dual-input splice, Pixel Sort, Snow lab, Live Bloom Scrub. | Depends on phase 3's codec set and phase 4's mask plumbing. |
| **6** | Parameter-manifest completeness, capability gating, presets via ARShader's existing layer. | Polish over a complete feature set. |

## 13. Non-goals

The ComfyUI-style node workspace — a visible patching graph of deck 1 → deck 2 → master with
user-inserted nodes — is explicitly out of scope. This design deliberately makes it cheaper by
establishing three of the four things it needs (an out-of-process node ABI, a backing-agnostic
stage protocol, and a data-driven parameter manifest), but building it is a separate project with
its own spec.

Also out of scope: Windows support, any TouchDesigner deliverable (Souther's `.pkg` covers that
need), and porting interstream's modulation, preset, or audio subsystems (section 8).

## 14. Open questions

1. Whether input slots 2 and 3 resolve through `SourceRouter` or the node gets its own input
   picker. Specified as `SourceRouter` above; reversible, and cheap to revisit once the node is
   playable.
2. Ring depth for the input and output surface rings. Start at 3 and measure; the correct value
   depends on the actual XPC round-trip latency, which is unmeasured on this hardware.
3. Whether the libx264 engine (phase 3) shares `StreamWorker` or runs as a parallel pipeline. Our
   H.264 path and the ffglitch codecs have different capability surfaces; resolve when phase 3
   begins and the coupling is visible.
4. Whether multiple simultaneous node instances (deck 1 + deck 2 + master) share one XPC service
   or get one process each. One process each is simpler and preserves isolation per instance, but
   triples resident memory for the static libraries. Measure at phase 2.
