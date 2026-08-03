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
research_basis: docs/research/2026-08-03-datamosh-node-research.md
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

### 2.0 Two codec surfaces, and the distinction that matters

FFglitch is a fork of FFmpeg, so **the full libavcodec encoder palette remains available** — that
is how mosh-top offers nine intermediate codecs (MPEG-1, MPEG-2, MPEG-4 pt2, WMV1, WMV2, FLV1,
MS-MPEG-4 v3, Snow, MJPEG). Packet-level moshing works on all of them.

The **ffedit syntax-editing** layer is far narrower. Only four decoders declare
`.p.ffedit_features`: MJPEG, MPEG-1/2, MPEG-4 part 2, and PNG/APNG. Everything in section 2's
bitstream list — Motion Paint, Edit Mask, Macroblock Shuffle, the Texture Lab — is therefore
confined to the MPEG family plus MJPEG, which is exactly what mosh-top's own capability matrix
reports. **MPEG-1/2 is the only codec with both full motion-vector access and full DCT/DC/quantizer
access**, and is therefore the node's default codec.

**FFglitch has no H.264 syntax access at all**, and the shipped ffglitch binaries are built without
`--enable-libx264`. This does *not* force two separate instruments: `configure` retains stock
FFmpeg's entire external-library machinery, and the ffedit changes are purely additive (new
`ffedit_*.c` files, a new struct field, new capability bits — nothing touching the encoder
wrappers). **Building ffglitch from source with `--enable-libx264` yields one patched libavcodec
carrying both our H.264 engine and the ffedit bitstream features**, so one child process serves
both. This resolves what would otherwise be a fork in the design.

### 2.1 The strongest technical argument for adopting ffglitch

Two encoder flags exist only in ffglitch, verified absent from stock FFmpeg n7.1 by exhaustive
grep of `libavcodec/mpegvideoenc.h` (six `mpv_flags` defined, zero occurrences of either):

- **`+forcemv`** — *"always write mvs for p frames (even if <0,0>)"*
- **`+nopimb`** — *"do not use intra mbs for predictive frames"*

These are the direct fixes for the two most common complaints about our current component: *only
part of the image moves*, and *little chunks keep snapping back to unglitched*. Our
`datamosher.py` sets only `sc_threshold` for the MPEG family and **structurally cannot produce
either flag**, because PyAV links stock FFmpeg. This alone justifies the dependency.

### 2.2 The mechanism distinction

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
| Clock | **Free-running; hold last moshed output on miss** | Free-running is mandatory regardless of process topology — one 720p encode→decode round trip measures ~16 ms on this machine, three orders of magnitude above the IPC cost. The *fallback* was originally specified as pass-through and was **changed on research evidence** — see 4.1. |
| Scope | **Full capability set**, ordered by phase | Operator's decision. Section 12 orders the work so the transport is proven before the feature mass lands, and so the node is playable at phase 2. |
| Parameter count | **Keep all ~76** | Operator wants the depth. The problem is disclosure, not count — solved by pages/sections and capability gating, not by cutting. |

### 4.1 Why the starvation fallback changed

The clock decision was originally taken as *free-running, pass the stage's input through when no
decoded frame is ready* — attractive because `FXChain.encode` already behaves that way on a nil
result, so it costs nothing. Research overturned the fallback, though not the free-running model.

Datamosh is a **path-dependent, accumulating** effect: the bloom compounds inside the decoder's
reference buffer over many frames. A clean input frame appearing in the output is therefore not a
neutral gap-filler — it is visually indistinguishable from a **reset**, which is the loudest single
gesture the effect has. Our own `datamosher.py` defines `reset()` as exactly that: force a
keyframe, decoder refreshes, "snap back" to clean.

At ~16 ms per 720p round trip against a 60 fps render tick, starvation is not an edge case — it
fires several times a second. Pass-through would therefore fire the effect's loudest gesture,
continuously, at an unpredictable cadence, with no operator input.

Signal Culture's stated product increment for Interstream is *"perpetual moshing without the need
to reset your blooms."* The pass-through fallback would automate precisely the thing that feature
exists to avoid.

**Resolution:** the starvation fallback is *hold last moshed output*. We already have this concept
implemented and named — `pixel_persist`, "hold the last good frame when input is lost." Pass-through
remains available, but as an explicit user-facing **Bypass**, which is a deliberate gesture rather
than a consequence of the encoder being busy. Cost is one retained texture per stage.

## 5. Architecture

Three pieces, two new.

**`FXNodeKit`** — new Swift package, sibling to `ISFRuntimeKit`. The node abstraction plus the host
side of the XPC connection. Knows nothing about datamosh.

**`MoshNode.xpc`** — new XPC service embedded in `ARShader.app`. Contains the vendored engine and
links **patched libavcodec** built from ffglitch source with `--enable-libx264`. It is the only
component linking LGPL/GPL code and the only component that can crash.

> Wording matters here: FFglitch ships **no library**. Its `PROGRAM_LIST` is four CLI binaries
> (`ffplay ffprobe ffmpeg ffedit`) and there is no `libffedit`, no C API, no daemon mode. The
> capability lives in libavcodec as an `int ffedit_features` field on the codec struct plus
> `AV_CODEC_CAP_FFEDIT_BITSTREAM` capability bits, which is what mosh-top actually queries. The
> child links the patched library; it does not run ffglitch.

**`FXStage` generalization** — an edit to existing code. `FXStage` currently owns a `ShaderUnit`,
and `FXChain.encode` calls `stage.core.renderOffscreen(...)`. That becomes:

```swift
protocol FXStageBacking: Sendable {
    func produce(input: MTLTexture, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?
}
```

`ISFStageBacking` implements it by calling the existing `renderOffscreen` — behavior-identical, and
the existing 227 app + 302 kit tests are the evidence. `NativeNodeBacking` implements it against
the surface ring in section 6. `FXChain.encode`'s body changes by one line.

Note that `FXChain.encode`'s existing `guard let produced = ... else { continue }` is the
*pass-through* behavior, which section 4.1 rules out as the starvation response.
**`NativeNodeBacking` therefore absorbs starvation itself** and returns its retained previous
output rather than `nil`. It returns `nil` in exactly three cases: before the first decoded frame
has ever arrived, while the node is explicitly bypassed, and while it is disabled after a crash
loop. In those cases `continue` is correct and the chain passes through as it always has.

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

**Sequence contract — the host publishes, and never replays.** Motion vectors and residuals are
meaningful only relative to the specific previous frame the encoder saw, so the child must own the
frame sequence. The host may publish irregularly — free-running guarantees it will — and coherence
survives that, because the child simply sees a self-consistent stream of whatever arrived. It does
**not** survive the host replaying a frame, reordering frames, or assuming output frame N
corresponds to input frame N. No part of the host may make that assumption; there is no
frame-accurate correspondence across this boundary, by design.

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

**Service crash.** XPC's invalidation handler fires; the stage marks itself faulted and **holds its
last good output texture** while the child is rebuilt silently behind it. Relaunch is automatic
with backoff (250 ms → 5 s cap), restoring the last parameter snapshot. Restart count is visible
in the UI. **If restarts exceed a threshold within a window, the node disables itself and reports
why** — a crash loop must never degrade into an invisible strobe diagnosed under stage lighting.

Crash recovery carries a **visual** cost that process isolation alone does not address: the child's
decoder reference state dies with it, so a restarted child necessarily begins from a fresh IDR.
Successful crash isolation therefore renders as a hard snap to clean — the same unwanted reset
section 4.1 is about. Holding the last good texture covers the relaunch window, but the first frame
after recovery is genuinely clean and nothing can prevent that. This is exposed as a switch —
*crash = intentional reset* — so the operator decides whether recovery reads as a glitch-out or as
a held freeze that gradually re-blooms. It is a display policy, not only a process policy.

**Capability gap.** When the selected codec cannot support a requested edit, **that edit is skipped**
— the node keeps moshing, the parameter greys out, and a visible warning says why. The node itself
does not bypass, and a simulated pixel-domain substitute is never offered in place of the real
edit.

**Damaged packet rejected by the decoder.** Adaptive backoff, or forward the original compressed
packet. Already implemented in the vendored engine.

**Encoder behind.** Not an error — the free-running latency model. Resolves to holding the last
moshed output (section 4.1). Pass-through is reachable only through the explicit *Bypass* control.

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
`ffedit-0.10`, and libx264 (GPL-2.0-or-later). The ledger exists so that a future decision to
release is a document to read rather than an investigation to run.

**Pin discipline.** That commit is the current HEAD of `ffedit-0.10` and reads
`ffglitch-0.10.3-dev` — it is roughly 14 commits *ahead* of the `0.10.2` release tag, not behind
it. Do not "upgrade" it to the 0.10.2 tarball.

Two facts worth recording even though nothing turns on them today. FFglitch's own ffedit sources
carry an LGPL-2.1-or-later header, and stock FFmpeg is LGPL-2.1+ by default — GPLv2+ applies only
when `--enable-gpl` is passed, which the official ffglitch builds do and our from-source build need
not. And vendoring libx264 makes the child GPL regardless. Since the child is a separate binary,
the LGPL/GPL code is already confined to one process, which is the cleanest possible starting point
should release ever be reconsidered. **None of this is legal advice, and a release decision needs a
real review rather than this paragraph.**

Should release ever be reconsidered, the out-of-process design already helps: the LGPL/GPL code is
confined to a separate binary, which is the cleanest starting point for any relicensing or
separate-distribution argument.

## 12. Phasing

Full scope, ordered so the transport is proven before the feature mass lands on it.

| Phase | Delivers | Rationale |
|---|---|---|
| **0a** | **Architecture spike, ~1 hour, blocks everything.** Prove a sandboxed XPC service can (i) obtain the GPU access it needs and (ii) receive and map a shared IOSurface from the host. | Undocumented, and it gates the entire out-of-process decision. Mitigating factor to test first: the engine is pure CPU (swscale + codec), so the child may need only IOSurface mapping and **no `MTLDevice` at all** — if true, the risk evaporates. If both fail, fall back to the in-process dynamic bundle and re-plan. |
| **0b** | Build patched libavcodec from ffglitch source at the pinned commit with `--enable-libx264`. Vendor mosh-top's `src/`, strip the TD shim, headless CLI harness that moshes a file. 14 tests green outside TouchDesigner. | Proves the engine detached from its host at zero risk to ARShader, and proves both codec surfaces coexist in one library before anything depends on that. |
| **1** | `FXNodeKit`, the `FXStageBacking` protocol, and a `MoshNode.xpc` that only inverts. ISF suites still green. | Isolates the riskiest new thing — surface handoff, ordering, crash recovery — so a failure has one possible cause. |
| **2** | Engine into the service. MPEG family, four mosh modes, Bloom. | **First playable.** |
| **3** | All nine encode codecs, the libx264 H.264 engine, `+forcemv` / `+nopimb`, Fluid Mosh, Pixel Persist. | Where interstream's contribution merges. `+forcemv` / `+nopimb` land here because they are encoder flags, and they are the fix for our component's two worst artifacts. |
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
3. Whether the libx264 engine (phase 3) shares `StreamWorker` or runs as a parallel pipeline. Both
   now live in one patched libavcodec (section 2.0), so this is an internal structuring question
   rather than a build question. Resolve when phase 3 begins and the coupling is visible.
4. Whether multiple simultaneous node instances (deck 1 + deck 2 + master) share one XPC service
   or get one process each. One process each is simpler and preserves isolation per instance, but
   triples resident memory for the static libraries. Measure at phase 2. Note that three
   simultaneous instances at ~16 ms per 720p round trip may not be viable at full resolution
   regardless of topology — encode resolution is the lever, as it is in our TouchDesigner
   component.
5. **Can a sandboxed XPC service obtain GPU access and map a host-shared IOSurface?** Undocumented;
   gates the architecture. Phase 0a spike. See the note there on why the child may not need Metal
   at all.
6. Whether an unnotarized app can launch its own bundled XPC service under current Gatekeeper.
   Unverified, and it affects local development directly.
7. Whether VideoToolbox is worth a fallback path at all. Apple reserves the right to insert
   keyframes and exposes no intra-refresh or scene-cut property across all 82 compression keys, but
   OBS reported that on Apple Silicon the HEVC encoder produced no keyframes past the first — filed
   as a bug, which for us would be the desired behavior. It is M1/HEVC/CRF/2023 and must be measured
   on this hardware before anything depends on it. Not required for any phase; opportunistic only.
8. What Interstream's `dropkeyframes` control actually does — encode-time suppression, or
   decode-time packet dropping? The name conflicts with our own validated finding that decode-time
   keyframe dropping produces stutter rather than smear. Worth resolving because it may indicate a
   third mechanism neither reference implements.
