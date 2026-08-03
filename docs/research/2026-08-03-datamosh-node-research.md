# Datamosh / glitch node — sourced research brief

**Date:** 2026-08-03
**Role:** Librarian
**Status:** Research synthesis for an architecture decision. Not an implementation plan.
**Scope:** ARShader (`App/ARShader/`) datamosh node built on ffglitch-core, plus the node-graph
and plugin-ABI questions that surround it.

---

## Evidence tags used throughout

Every substantive claim below carries one of these. They are not decoration — the confidence
difference between them is large and load-bearing.

| Tag | Meaning |
|---|---|
| **[LOCAL]** | I inspected a file or binary on this machine this session (`otool`, `strings`, `file`, source tarball, git). Strongest evidence available. |
| **[PRIMARY]** | I fetched and read the primary source myself this session (project docs, Apple docs JSON, GitHub API, source `.c`/`.h`). |
| **[LEG]** | Came from a quarantined `web-researcher` subagent and I did **not** independently re-verify it. Treat as a good lead, not a settled fact. |
| **[INFERRED]** | My analysis joining two or more facts. Not stated by any source. |
| **[UNVERIFIED]** | Could not confirm from any primary source. Stated as a gap, not filled. |

Verification density is **high for sections 1–3** (I read the ffglitch source tarball, the shipped
macOS binaries, the installed Interstream app, and Apple's documentation JSON directly) and
**lower for sections 4–5**, which rest more heavily on subagent legs. That asymmetry is real and
I have not smoothed it over.

---

## Sources read

### Local files and binaries (this machine)

- `/Users/arsonrivvers/Desktop/AV_Projects/max-mcp/interstream-td/README.md`
- `/Users/arsonrivvers/Desktop/AV_Projects/max-mcp/interstream-td/DATAMOSH_PERF_RESEARCH.md`
- `/Users/arsonrivvers/Desktop/AV_Projects/max-mcp/interstream-td/core/datamosher.py`
- `/Users/arsonrivvers/Desktop/AV_Projects/max-mcp/interstream-td/tools/` (`nokeyframe_test.py`, `pdup_test.py`, `corrupt_test.py`, `strategies.py`, `probe.py`, `spike.py`)
- `/Applications/Interstream_MACv2.app` — full bundle inspection (`Info.plist`, `Frameworks/`, `Resources/C74/externals/`, `otool -L`, `strings`, `file`)
- `mosh-top` working copy — `src/StreamWorker.cpp`, `src/Parameters.cpp`, `src/MoshTOP.cpp`, `src/FFEditJsonBridge.{c,h}`, `README.md`, `LICENSE`, git history
- `ffglitch-0.10.2.tar.xz` (downloaded from ffglitch.org, extracted to scratchpad) — `configure`, `FFGLITCH_VERSION`, `RELEASE`, `LICENSE.md`, `INSTALL.md`, `libavcodec/ffedit*.{c,h}`, `libavcodec/{mjpegdec,mpeg12dec,mpeg4videodec,pngdec,h263dec}.c`, `libavcodec/mpegvideoenc.h`
- `ffglitch-0.10.2-macos-aarch64.zip` (downloaded) — `ffedit`, `fflive`, `ffgac`, `qjs`, `readme.txt`
- `/Users/arsonrivvers/Desktop/AV_Projects/ShaderToy-to-ISF-converter/docs/arshader/README.md`
- `~/.claude/c-suite/reports/librarian/2026-07-31-arshader-adjacent-embedded-tech-and-sdf.md`

### Primary external sources fetched directly

- ffglitch.org: [home](https://ffglitch.org/), [docs 0.10.2 index](https://ffglitch.org/docs/0.10.2/), [ffedit](https://ffglitch.org/docs/0.10.2/ffedit/), [fflive](https://ffglitch.org/docs/0.10.2/fflive/), [ffgac](https://ffglitch.org/docs/0.10.2/ffgac/), [codecs](https://ffglitch.org/docs/0.10.2/codecs/), [formats](https://ffglitch.org/docs/0.10.2/formats/), [features](https://ffglitch.org/docs/0.10.2/features/), [MPEG-2 features](https://ffglitch.org/docs/0.10.2/features/mpeg2/), [MPEG-4 features](https://ffglitch.org/docs/0.10.2/features/mpeg4/), [MJPEG features](https://ffglitch.org/docs/0.10.2/features/mjpeg/), [PNG features](https://ffglitch.org/docs/0.10.2/features/png/), [download](https://ffglitch.org/download/)
- ffglitch.org release posts: [0.10.0](https://ffglitch.org/2024/06/ffglitch_0_10_0.html), [0.10.1](https://ffglitch.org/2024/07/ffglitch_0_10_1.html), [0.10.2](https://ffglitch.org/2024/10/ffglitch_0_11_2.html) (note: slug says `0_11_2`, title says 0.10.2 — slug is a typo), [Live Mosher](https://ffglitch.org/2024/12/live_mosher_1_0.html)
- [github.com/ramiropolla/ffglitch-core](https://github.com/ramiropolla/ffglitch-core) via GitHub REST API (repo meta, branches, tags, commits, compare, raw file reads at pinned SHA)
- [github.com/ramiropolla/ffglitch-scripts](https://github.com/ramiropolla/ffglitch-scripts) — [tutorial readme](https://raw.githubusercontent.com/ramiropolla/ffglitch-scripts/main/tutorial/readme.md), repo meta via API
- [FFmpeg n7.1 `libavcodec/mpegvideoenc.h`](https://raw.githubusercontent.com/FFmpeg/FFmpeg/n7.1/libavcodec/mpegvideoenc.h), [FFmpeg master `libavcodec/videotoolboxenc.c`](https://raw.githubusercontent.com/FFmpeg/FFmpeg/master/libavcodec/videotoolboxenc.c), FFmpeg `version_major.h` at `n7.1` / `n8.0` / `master`
- [signalculture.org/sc-modular-apps.html](https://signalculture.org/sc-modular-apps.html)
- Apple developer docs, machine-readable JSON (`developer.apple.com/tutorials/data/documentation/…json`): VideoToolbox [compression-properties](https://developer.apple.com/documentation/videotoolbox/compression-properties) index (all 82 keys enumerated), `kVTCompressionPropertyKey_MaxKeyFrameInterval`, `_AllowTemporalCompression`, `_AllowFrameReordering`, `_RealTime`, `_AllowOpenGOP`, `_EnableLTR`, `_ReferenceBufferCount`, `_H264EntropyMode`, `_MaxAllowedFrameQP`, `_BaseLayerFrameRate`; Metal `MTLSharedEvent.makeSharedEventHandle()`, `MTLDevice.makeSharedEvent(handle:)`, `MTLTexture.makeSharedTextureHandle()`, `MTLDevice.makeSharedTexture(handle:)`, `MTLDevice.makeTexture(descriptor:iosurface:plane:)`
- [OBS Studio PR #8677](https://github.com/obsproject/obs-studio/pull/8677) via GitHub REST API (verbatim body)
- [WWDC 2015 Session 508 transcript](https://asciiwwdc.com/2015/sessions/508) (AUv3 out-of-process overhead, verbatim)
- [ComfyUI `comfy_execution/validation.py` and `execution.py`](https://github.com/comfyanonymous/ComfyUI) at master, raw

### Quarantine note

Full-page reads were isolated into five parallel `web-researcher` subagents per the standing
prompt-injection policy; I ran direct `curl` / GitHub-API / Apple-JSON probes in parallel rather
than depending on them. I scanned all returned findings for injection markers
(`<system-reminder>`, `</user>`, all-caps directive tags, "ignore previous instructions",
`# claudeMd`) and found none. Every load-bearing number in sections 1–3 and the two load-bearing
numbers in section 5 were re-verified by me against the primary source.

---

## What changes our design

Two decisions are locked: **(1) the node runs out-of-process via XPC with IOSurface-shared
textures**, and **(2) it is free-running — the host takes the newest ready frame each render tick
and passes its input through unchanged when none is ready.** Findings are weighted against those.

### Findings that CHALLENGE a locked decision

**C1. "Passthrough when nothing is ready" fights the effect's signature. This is the single most
consequential finding in the brief.**
Datamosh is a *path-dependent, accumulating* effect: the bloom compounds inside the decoder's
reference buffer. A clean input frame appearing in the output is not a neutral fallback — it is
visually identical to a **reset**, which is the loudest gesture the effect has. Your own
`core/datamosher.py` documents this precisely: `reset()` = "force a keyframe → decoder refreshes →
clean image ('snap back')" **[LOCAL]**. Signal Culture ships "perpetual moshing **without the need
to reset your blooms**" as Interstream's headline new feature **[PRIMARY**, verbatim from
signalculture.org**]** — i.e. the entire product increment is about *not* doing what the passthrough
fallback does automatically, at an unpredictable cadence, several times a second.
**Recommendation:** keep free-running, but change the fallback from *passthrough input* to *hold
last moshed output*. You already have this concept implemented and named — `pixel_persist`, "hold
the last good frame when input is lost" **[LOCAL]**. Passthrough should be an explicit user-facing
bypass, not the starvation behaviour. **[INFERRED** — joining your own reset semantics to Signal
Culture's stated feature; no source states this as a rule.**]**

**C2. Crash-restart has a *visual* cost that crash-isolation alone does not address.**
The XPC decision is right for process survival, but when the codec child dies mid-bloom its decoder
reference state dies with it. A restarted child necessarily begins from a fresh IDR — so
"successful" crash recovery renders as a hard snap to clean, the exact artifact C1 is about. The
crash story therefore needs a *display* policy, not just a *process* policy: on
`interruptionHandler`, hold the last good output texture and rebuild the child silently behind it;
optionally expose "crash = intentional reset" as a switch. **[INFERRED]**

**C3. Free-running only works if the CHILD owns the encoder's frame sequence.**
Motion vectors and residuals are meaningful only relative to the specific previous frame the encoder
saw. If the host publishes frames irregularly (which free-running guarantees) and the child encodes
whatever it last received, coherence is preserved — the child sees a self-consistent sequence.
It breaks if the host ever re-delivers, reorders, or expects frame-accurate input↔output
correspondence. **Constraint to write into the spec:** the host publishes; it never replays, never
reorders, and must not assume output frame N corresponds to input frame N. **[INFERRED]**

**C4. FFglitch ships no library. The XPC child cannot "embed ffglitch" as stated.**
`PROGRAM_LIST` in `configure` contains exactly `ffplay ffprobe ffmpeg ffedit` **[LOCAL**, ffglitch
0.10.2 `configure` line 2071**]**; the shipped macOS arm64 archive is four CLI binaries —
`ffedit`, `fflive`, `ffgac`, `qjs` **[LOCAL]**. There is no `libffedit`, no C API, no daemon mode.
**But this is resolvable, and the resolution is the important part:** the ffedit capability does not
live in the `ffedit` tool — it lives in **libavcodec**, as a new `int ffedit_features` field on the
codec struct (`libavcodec/codec.h:237`) plus `AV_CODEC_CAP_FFEDIT_BITSTREAM` /
`AV_CODEC_CAP_FFEDIT_SLICE_THREADS` capability bits on the decoders **[LOCAL]**. So you link
**patched libavcodec**, not ffedit. That is exactly what mosh-top does — it calls
`avcodec_find_decoder()` then tests `c->capabilities & AV_CODEC_CAP_FFEDIT_BITSTREAM` and
`c->ffedit_features & (1 << feature)` directly **[LOCAL**, `mosh-top/src/StreamWorker.cpp:525-560`**]**.
XPC remains viable; the spec must say "child links patched libavcodec", not "child runs ffglitch".

**C5. FFglitch cannot touch H.264. Your existing component is H.264. These are different instruments.**
FFglitch supports exactly four codecs — **MJPEG, MPEG-1/2 video, MPEG-4 part 2, PNG/APNG** — and
three containers — **rawvideo, AVI, MOV** **[PRIMARY**, ffglitch.org codecs + formats pages**]**.
The docs show `ffedit` explicitly rejecting an H.264-in-Matroska file. Confirmed at the source
level: only `mjpegdec.c`, `mpeg12dec.c` (×3 decoders), `mpeg4videodec.c` and `pngdec.c` declare
`.p.ffedit_features` **[LOCAL]**. Your `interstream_datamosh` is built on keyframe-free H.264
P-frame duplication via libx264 **[LOCAL]**. The ffglitch node is therefore **not** a port or an
upgrade of that component — it is a second, mechanically different instrument with a different
look. Plan two nodes, or plan to lose H.264.

### Findings that SUPPORT a locked decision (and sharpen it)

**S1. Out-of-process is Apple's own answer to precisely this problem.**
FxPlug 4 — Apple's plugin API for Motion/Final Cut — moved third-party image plugins **out of
process** and passes GPU work across the boundary **[LEG]**. AUv3 app extensions default to
out-of-process on macOS for the stated reasons "safety and performance … it's a security risk to be
loading third-party code into your app, and if it crashes inside your app, then users might blame
you instead of the misbehaving plug-in" **[PRIMARY**, WWDC15 S508 transcript, verbatim**]**. A codec
deliberately fed corrupted bitstreams is the strongest possible case for this.

**S2. The measured out-of-process overhead is negligible at video rates.**
Apple measured AUv3 cross-process overhead "on the order of 40 microseconds per render cycle", and
gave their own worked example: "if you are rendering at a very low latency of 32 frames, that's a
1 millisecond render interval, so overhead of 40 microseconds could be significant at 5.5 percent"
**[PRIMARY**, WWDC15 S508, verbatim; MEASURED by Apple, hardware/date unstated**]**. Against a
16.7 ms frame at 60 fps that same 40 µs is ~0.24% **[INFERRED**, my arithmetic, ILLUSTRATIVE —
it is an *audio* figure being reused as an order-of-magnitude for IPC, not a video measurement**]**.
For context, your own component measures ~16 ms for a single 720p encode→decode round trip
**[LOCAL**, `DATAMOSH_PERF_RESEARCH.md`, MEASURED on this machine**]** — the codec is three orders
of magnitude more expensive than the IPC. **The XPC boundary is not the cost. Free-running is
mandatory regardless of process topology.**

**S3. Cross-process GPU sharing on Apple Silicon is fully supported and the per-frame cost is a
handle exchange, not a copy.** Verified API surface, all four symbols read from Apple's docs
**[PRIMARY]**:
- `MTLDevice.makeTexture(descriptor:iosurface:plane:)` — "Creates a texture instance that uses I/O surface to store its underlying data."
- `MTLTexture.makeSharedTextureHandle()` → `MTLSharedTextureHandle?` ("If the texture is not shareable, this method returns nil.")
- `MTLDevice.makeSharedTexture(handle:)` — "Creates a texture that references a shared texture."
- `MTLSharedEvent.makeSharedEventHandle()` → `MTLSharedEventHandle`, and `MTLDevice.makeSharedEvent(handle:)` — "Recreates a shared event from a handle."

  So: exchange IOSurface + `MTLSharedEvent` handles **once at connection setup**, then signal per
  frame. No per-frame XPC message needs to carry pixels. **[INFERRED** from the API shapes; the
  pattern is standard but no single Apple doc states it end-to-end.**]**
  Caveat worth designing around: a raw `IOSurfaceRef` reportedly does not survive `NSXPCConnection`
  — use the ObjC `IOSurface *` class or `IOSurfaceCreateXPCObject` **[LEG**, not re-verified**]**.

**S4. Out-of-process is also the cleaner licensing posture.**
FFglitch's ffedit patches are **LGPL-2.1-or-later** (`libavcodec/ffedit.c` header, verbatim)
**[LOCAL]**, but every official binary is built `--enable-gpl` and ships GPLv2+ boilerplate
**[LOCAL**, shipped `readme.txt` and the embedded configure string**]**. For a product you intend to
distribute, a separate process talking over XPC is a materially stronger arms-length argument than
in-process linking, and building **without** `--enable-gpl` keeps you on LGPL. **This is a design
input, not legal advice — get it reviewed before shipping.** **[INFERRED]**

### Findings that change the design independent of the locked decisions

**D1. `+forcemv` and `+nopimb` do not exist in stock FFmpeg. They are FFglitch's, and they fix the
two worst artifacts in your current component.** Stock FFmpeg n7.1 defines exactly six `mpv_flags`
— `skip_rd`, `strict_gop`, `qp_rd`, `cbp_rd`, `naq`, `mv0` — and **zero** occurrences of `forcemv`
or `nopimb` **[PRIMARY**, exhaustive grep of `libavcodec/mpegvideoenc.h` at n7.1, no truncation,
0 hits**]**. FFglitch adds `FF_MPV_FLAG_FORCE_MV 0x0040` and `FF_MPV_FLAG_NOPIMB 0x0080`
**[LOCAL]**, described verbatim in its source as:
  - `forcemv` — *"always write mvs for p frames (even if <0,0>)"*
  - `nopimb` — *"do not use intra mbs for predictive frames"*

  These are the fixes for "only part of the image is moving" and "little chunks keep getting
  restored to their unglitched version" respectively **[PRIMARY**, ffgac docs**]**. Your
  `datamosher.py` sets only `sc_threshold` for the MPEG family **[LOCAL]** — it structurally
  cannot produce either flag, because it links stock FFmpeg via PyAV. **This is the single
  strongest technical argument for adopting ffglitch at all.**

**D2. Your pinned commit is *ahead* of the 0.10.2 release, not behind it.**
`4b71d60c6640ad3f9ce483eac14391dc73f8c950` is the current HEAD of `ffedit-0.10` (compare against
branch: `status: identical, 0 ahead, 0 behind`) **[PRIMARY]**. Its `FFGLITCH_VERSION` reads
**`ffglitch-0.10.3-dev`**, versus `ffglitch-0.10.2` at the release tag `225c210d02a3…`
**[PRIMARY]**. It sits ~14 commits past that tag and picks up `fflive: add -o option`,
`fflive: add support for pipe ('-') as output`, the `qjs`→`ffjs` rename, and a `setup()`
feature-removal fix **[PRIMARY]**. Its *author* date is 2024-09-18 (a cherry-picked upstream
patch) but its *committer* date — and the repo's `pushed_at` — is **2025-05-17** **[PRIMARY]**.
Good pin. Do not "upgrade" it to the 0.10.2 tarball.

**D3. Choose MPEG-2, and treat codec choice as a creative control, not an implementation detail.**
The codec×feature matrix is asymmetric in a way that decides the instrument's expressive range
(full matrix in §1). **MPEG-1/2 is the only codec with both full motion-vector access and full
DCT/DC/quantizer access.** MPEG-4 part 2 has motion vectors and macroblocks but **no** DCT or
qscale features at all. MJPEG has DCT/quant but **no** motion vectors (it is all-intra). **[LOCAL**,
read from the `.p.ffedit_features` bitmasks in the decoder structs**]**.

**D4. Interstream's mechanism is now confirmed, and it validates your credit line.**
It is **real-codec, libavcodec + libx264, in-process, container-less** — not a pixel-domain
imitation. Details and evidence in §2. Your README's "inspired by Interstream — its real-codec
approach" is mechanistically accurate **[LOCAL]**. Two structural ideas are directly copyable: the
compressed bitstream is a **first-class typed value in the node graph**, and encode/decode are
**two separate nodes** with the manipulable packet between them.

**D5. Your two reference implementations are one lineage.**
`mosh-top` is by **Eric Souther / Philosophical Tools**, MIT, © 2026 **[LOCAL**, `LICENSE` + git
history + remote `github.com/ericsouther-source/mosh-top`**]**. Eric Souther is also credited as
Interstream's original creator (with Jason Bernagozzi) **[LEG]**. mosh-top is effectively the
open, source-available, MIT-licensed evolution of the same approach. It is the highest-value
document in the whole survey and you already have it.

**D6. mosh-top already uses 9 of ffedit's 14 features. The genuinely untapped surface is the
*encoder* side, not the decoder side.** See §1 for the exact five unused features. The larger gap
is that neither reference uses ffgac's `-mb_type_script` (per-macroblock I/P decision from a live
script) or its picture-type script — an entire scripting lane on the *encode* side that no
implementation in this survey touches. **[LOCAL** + **[PRIMARY]]**

**D7. VideoToolbox is a real fallback path, with one documented trap and one very promising bug.**
`kVTCompressionPropertyKey_MaxKeyFrameInterval` default is **0**, and Apple's own text says 0 means
"the video encoder should choose where to place all key frames" — so 0 is the *worst* value, not
"none". Apple also explicitly reserves the right to insert more: *"Video encoders are allowed to
generate key frames more frequently if doing so results in more efficient compression."*
**[PRIMARY**, verbatim**]**. Counterpoint: OBS shipped a fix because on Apple Silicon in CRF mode the
encoder *"will not create any keyframes past the initial one"*, with the maintainer adding *"it
seems that `kVTCompressionPropertyKey_MaxKeyFrameInterval` just straight up does nothing with the
HEVC encoder on M1 even in other modes"* **[PRIMARY**, PR #8677 body, verbatim, merged
2023-04-06**]**. That is a datamosher's dream reported as a bug — but it is M1 / HEVC / CRF / 2023
and **must be measured on your hardware before anything depends on it**.

---

## 1. FFglitch capability surface

### 1.1 What FFglitch actually is

Three CLI programs plus a standalone JS engine, all shipped as separate binaries
**[PRIMARY**, docs index; **[LOCAL]**, verified in the macOS arm64 archive**]**:

| Binary | What it is | Verbatim description |
|---|---|---|
| `ffedit` | The bitstream editor | "the main tool for FFglitch. It is a multimedia bitstream editor." |
| `fflive` | Real-time player + editor | "a video player (it's just a hacked up ffplay) that integrates ffedit so you can create live glitch in real-time." |
| `ffgac` | Patched encoder | "just `ffmpeg`, with … extra features" — GAC = Glitch Artists Collective. |
| `qjs` | Standalone QuickJS | With built-in MIDI and networking (0.10.2). Renamed `ffjs` after 0.10.2 **[PRIMARY]**. |

The core mechanism, verbatim from the ffedit docs **[PRIMARY]**:

> ffedit is collecting the bits that were read from the bitstream for each value of each codec, and
> then rewriting a new valid bitstream with those values, which are possibly modified. … The whole
> process does not involve any re-encoding of the codecs, nor does it do any re-muxing of the file.
> Everything works in the bitstream level.

Polla calls this **transplication**. The "Replicate file" mode exists to prove it round-trips
byte-identically (docs show matching md5sums) **[PRIMARY]**.

### 1.2 The complete `-f` feature list — 14, from source

Read directly from `libavcodec/ffedit.c`'s `feat_keys[]` array and the `FFEditFeature` enum in
`ffedit.h` **[LOCAL]**:

```
info · q_dct · q_dct_delta · q_dc · q_dc_delta · mv · mv_delta
qscale · dqt · dht · mb · gmc · headers · idat
```

**Correction to the brief's premise:** there is **no `q_ac` feature**. AC coefficients are reached
through `q_dct` (which carries DC + AC 1..63 in zig-zag order); `q_dc` is the DC-only variant.

| Feature | Exposes | Notes |
|---|---|---|
| `info` | Picture type (`I`/`P`/`B`/`S`), interlaced flag, field, and a per-macroblock **type-code string** | **Read-only.** "This feature is purely informative, no changes here will be applied back when transplicating." Letter codes: MPEG-2 `I q c f b`; MPEG-4 adds `a 4 i d G 1-6`. |
| `q_dct` | Quantized DCT coefficients: DC + AC 1–63, zig-zag | Plus informative `bpmb_v`/`bpmb_h` (blocks per macroblock) and the DQT table index. |
| `q_dct_delta` | Same, DC expressed as delta from previous DC | Prediction order is raster **per-macroblock**, not simply "block to the left". |
| `q_dc` / `q_dc_delta` | DC only / DC delta only | Cheap brightness-domain manipulation. |
| `mv` | Absolute motion vectors, `forward` / `backward` arrays | `null` = no MV for that MB. MPEG-4 may give an array of **4** MVs (8×8 mode). Carries informative `fcode` and an `overflow` policy: `assert` / `truncate` / `ignore` / `warn` — docs recommend `truncate`. |
| `mv_delta` | MVs as deltas from the predictor | Same shape and `fcode`/`overflow` fields. |
| `qscale` | Per-slice / per-macroblock quantizer scale | Docs warn: *"this feature is not very thread-friendly in its current state in FFglitch."* |
| `dqt` | JPEG quantization tables | "used to multiply the quantized coefficients before they go through the IDCT." |
| `dht` | JPEG Huffman tables | Docs actively discourage: *"Honestly, you don't want to mess with this one… You will break the glitched file in incomprehensible ways."* |
| `mb` | **Per-macroblock bytestream as a hex string** + its size in bits | *"Macroblocks are mostly self-sufficient, so it might be possible to reorder them and still have a valid bitstream."* The bit-size field is used for realignment — do not change it. |
| `gmc` | MPEG-4 Global Motion Compensation params (up to 3 × 2 numbers) | Docs: *"I don't remember how the gmc calculation is done."* Undocumented. |
| `headers` | PNG/APNG non-IDAT chunks (IHDR, fcTL, PLTE, tRNS, …) | |
| `idat` | PNG/APNG image data, per row: `[filter_type, …bytes]` + `compression_level` | Filter types 0–4 (None/Sub/Up/Average/Paeth). Interlaced PNG yields `passes` (Adam7) instead of `rows`. |

Exported MV JSON, verbatim shape **[PRIMARY]**:

```json
{ "ffedit_version":"ffglitch-0.10.0", "filename":"input.avi",
  "sha1sum":"9c37878623c27a5cba7aac099767e5a4463b09fd",
  "features":["mv"],
  "streams":[{ "codec":"mpeg2video", "frames":[
    { "pkt_pos":24444, "pts":null, "dts":null,
      "mv":{ "forward":[[null,[0,-1],[0,-1],…],…], "fcode":[1,1], "overflow":"warn" } }]}]}
```

MV range is `fcode`-derived — MPEG-2: `±(1<<(3+fcode))`; MPEG-4: `±(1<<(4+fcode))` **[PRIMARY]**.
The scripts tutorial passes `-fcode 6` at encode time to widen it **[PRIMARY]**.

### 1.3 Codec × feature matrix (read from the decoder structs)

This is the authoritative version, taken from `.p.ffedit_features` bitmasks in the ffglitch 0.10.2
source rather than from prose **[LOCAL]**:

| Feature | MJPEG | MPEG-1 | MPEG-2 | MPEG-4 pt2 | PNG / APNG |
|---|:--:|:--:|:--:|:--:|:--:|
| `info` | ● (empty) | ● | ● | ● | — |
| `q_dct` | ● | ● | ● | — | — |
| `q_dct_delta` | ● | ● | ● | — | — |
| `q_dc` | ● | ● | ● | — | — |
| `q_dc_delta` | ● | ● | ● | — | — |
| `mv` | — | ● | ● | ● | — |
| `mv_delta` | — | ● | ● | ● | — |
| `qscale` | — | ● | ● | — | — |
| `dqt` | ● | — | — | — | — |
| `dht` | ● | — | — | — | — |
| `mb` | — | ● | ● | ● | — |
| `gmc` | — | — | — | ● | — |
| `headers` | — | — | — | — | ● |
| `idat` | — | — | — | — | ● |

Notes:
- **MPEG-1 has the identical 9-feature set to MPEG-2.** Three decoder structs carry it:
  `ff_mpeg1video_decoder`, `ff_mpeg2video_decoder`, and the legacy `ff_mpegvideo_decoder` **[LOCAL]**.
- **`info` on MJPEG is registered but returns nothing** — "currently empty. It doesn't export anything" **[PRIMARY]**.
- **H.263 / H.263+ are NOT supported.** `ffedit_h263.c` exists and `h263dec.c` carries the
  `AV_CODEC_CAP_FFEDIT_*` capability bits, but **neither `ff_h263_decoder` nor `ff_h263p_decoder`
  declares `.p.ffedit_features`** — so zero features are selectable **[LOCAL]**. The h263 code is
  shared infrastructure for the MPEG-4 path, not a user-facing target.
- **No H.264, HEVC, VP8/9, AV1, ProRes, DV.** The docs show `ffedit` printing
  `FFEdit does not support format 'Matroska / WebM'` and rejecting an H.264 stream **[PRIMARY]**.
- Containers: **rawvideo, AVI, MOV only** (MOV added in 0.10.0). Audio glitching is not supported
  at all; AVI/MOV exist so audio can ride along in sync **[PRIMARY]**.
- Export vs apply: every listed feature is read/write (transplicable) **except `info`**, which is
  explicitly read-only.

### 1.4 What mosh-top does NOT use — the actual answer to the question

mosh-top defines its own feature indices mirroring ffedit's enum **[LOCAL**,
`src/StreamWorker.cpp:273-282`**]**: `kFeatQDct=1, kFeatQDctDelta=2, kFeatQDc=3, kFeatQDcDelta=4,
kFeatMv=5, kFeatMvDelta=6, kFeatQScale=7, kFeatDqt=8, kFeatMb=10, kFeatLast=14`.

**It uses 9 of 14.** Unused, with an honest assessment of each:

| Unused feature | Index | Worth taking? |
|---|:--:|---|
| **`info`** | 0 | **Yes — highest value.** It is the per-macroblock *type map* (intra / quant-change / coefficient-change / forward / backward / 4-MV / interlaced / GMC). It is the only way to target manipulation *semantically* — "displace only macroblocks that already carry forward motion", "leave intra MBs alone", "push only the 8×8-split blocks". Every mosh in both references is spatially blind by comparison. Read-only, so it costs nothing but a second selected feature. |
| **`dht`** | 9 | **No.** Author explicitly discourages it; breaks files "in incomprehensible ways". |
| **`gmc`** | 11 | **Maybe, narrow.** MPEG-4 S(GMC)-VOP global motion — a whole-frame warp parameter set. Would give a genuinely different gesture (global camera drift) from per-MB displacement. But it only appears in S-VOPs, which a normal encode will not produce without effort, and ffglitch's own docs decline to document the math. Speculative. |
| **`headers` / `idat`** | 12/13 | **Not for video.** PNG/APNG only. Interesting for a still/texture-glitch node, irrelevant to a live video deck. |

**The bigger untapped surface is `ffgac`, the encoder side** — neither reference uses it
**[PRIMARY** for the features, **[LOCAL]** for mosh-top's non-use**]**:

- `-mb_type_script <file>` — a JS callback `mb_type_func(args)` receives a **2-D array of
  per-macroblock candidate-type bitmasks** and rewrites them before encoding. The docs give the
  full constant list (`CANDIDATE_MB_TYPE_INTRA` `1<<0`, `_INTER` `1<<1`, `_INTER4V` `1<<2`,
  `_SKIPPED` `1<<3`, `_DIRECT` `1<<4`, `_FORWARD` `1<<5`, `_BACKWARD` `1<<6`, `_BIDIR` `1<<7`, …)
  and a worked checkerboard example. This is *authoring* the macroblock structure, not editing it
  after the fact — a strictly larger lever than anything on the decode side.
- Picture-type script — force I/P at frame granularity programmatically.
- `-filter_row_script` — per-row PNG filter selection at encode time (0.10.1).
- `-mpv_flags +forcemv` / `+nopimb` — see **D1**. Not available anywhere else.
- `-g max -sc_threshold max` — ffgac's documented route to an infinite keyframe interval. The docs
  note ffmpeg has "an arbitrary limitation of 600 frames between keyframes in MPEG2 and MPEG4
  encoders" plus a scene-change algorithm, and that both must be defeated **[PRIMARY]**.

Also unused by mosh-top but reasonably judged **EQUAL, not a gap**: `fflive` as a runtime, ZeroMQ
messaging, and RtMidi input. mosh-top is a TouchDesigner TOP, so the host already supplies
parameter transport and a render loop. The same reasoning applies to ARShader.

### 1.5 Build system — can libx264 / libvpx coexist with the ffedit patches?

**Yes, cleanly. The ffedit patches are orthogonal to external encoder libraries.** **[LOCAL]**

- `configure` retains the entire upstream FFmpeg external-library machinery untouched:
  `--enable-libx264` and `--enable-libvpx` are present with their normal help text, dependency
  declarations (`libx264_encoder_deps="libx264"`, `libvpx_vp8_encoder_deps="libvpx"`, …) and
  `pkg-config` probes including the `X264_BUILD >= 122` / `>= 158` version gates.
- The ffedit changes are additive: new `libavcodec/ffedit_*.c` files, a new `int ffedit_features`
  field on the codec struct, new capability bits, and a new `ffedit` entry in `PROGRAM_LIST`.
  Nothing in that touches the encoder wrappers.
- `INSTALL.md` is stock FFmpeg's, including the note *"Non system dependencies (e.g. libx264,
  libvpx) are disabled by default."*

**But the official builds do not enable them.** The configure line baked into the shipped macOS
arm64 `ffgac` binary, extracted verbatim **[LOCAL]**:

```
--disable-doc --enable-gpl --enable-static --disable-shared --disable-autodetect
--disable-iconv --enable-zlib --enable-rtmidi --enable-libzmq --enable-sdl2 --enable-avfoundation
```

Confirmed identical to `.github/workflows/macos-aarch64.yaml` at the pinned commit **[PRIMARY]**.
Encoder-name string probes on that binary: `h264_videotoolbox` **absent**, `libx264`/`libvpx`
present only as configure-help text; `mpeg4`, `mpeg2video`, `mpeg1video`, `msmpeg4v3`, `mjpeg`,
`apng`, `h263p`, `rawvideo` present **[LOCAL]**.

**Consequences for the build:**
1. To get x264/VP8/VP9 alongside ffedit you must **build from source** with the extra flags. The
   shipped binaries cannot do it.
2. `--enable-avfoundation` is on, so **live camera capture works on macOS out of the box**.
3. `--enable-static --disable-shared` is their packaging choice, not a constraint — build shared if
   you want to link libavcodec from an XPC child.
4. Bundled third-party libs, from the shipped `readme.txt` **[LOCAL]**: quickjs 2024-01-13,
   zlib-ng 2.2.2, SDL2 2.30.8, RtMidi 6.0.0, ZeroMQ 4.3.1.
5. **Licensing:** `libavcodec/ffedit.c` carries an **LGPL-2.1-or-later** header **[LOCAL]**, and
   `LICENSE.md` is stock FFmpeg's — LGPL-2.1+ by default, GPLv2+ *only* when `--enable-gpl` is
   passed. Official builds pass it. A from-source build that omits `--enable-gpl` (and avoids
   `libpostproc` and the GPL filters) stays LGPL. **[LOCAL]**. GitHub reports the repo license as
   `NOASSERTION` **[PRIMARY]**, which is normal for an FFmpeg fork and is not a licence in itself.

### 1.6 Real-time and streaming — the answer is yes, and it is documented

The brief assumed file-in/file-out. That is wrong for 0.10.x **[PRIMARY]**:

- **0.10.0 (2024-06-09)** introduced `fflive` — "multimedia glitching in real-time", with MIDI /
  keyboard-mouse / network input, MOV support, and the claim of "up to **4K** glitching in
  **real-time**".
- **0.10.1 (2024-07-22)** added **pipe support for export/apply JSON**, and fixed the build to
  include **video capture** — Polla's own note: *"How come nobody complained so far that live
  capture support wasn't enabled? Has nobody been using webcams and HDMI capture for live
  glitching?"*
- **0.10.2 (2024-10-30)** added arm64 optimizations explicitly for **Apple silicon**, fixed the
  **arm64 macOS build**, improved **ZeroMQ** messaging, and gave the standalone QuickJS built-in
  MIDI + networking.
- Post-0.10.2 on your pinned branch: `fflive -o` and `fflive` pipe-as-output **[PRIMARY]**.

The documented macOS live-camera pipeline, verbatim from the ffglitch-scripts tutorial **[PRIMARY]**:

```
./bin/ffgac -f avfoundation -i 0 -vf hflip -vcodec mpeg4 \
  -mpv_flags +nopimb+forcemv -qscale:v 1 -fcode 6 -g max -sc_threshold max \
  -f rawvideo pipe: \
| ./bin/fflive -i pipe: -s scripts/mpeg4/mv_average.js -fs -asap
```

A second form uses `-f avpipe -` instead of `-f rawvideo pipe:`, and one example chains
`-mb_type_script` on the encoder with an MV script on the player simultaneously. There is also a
YouTube-live variant via `yt-dlp -o - | ffgac | fflive` **[PRIMARY]**.

**Scripting API** — Python 3 *or* JavaScript (QuickJS). Python support is "fairly basic and has no
optimizations". Scripts export `glitch_frame(frame, stream)` (required) and optionally
`setup(args)`, where `args` carries `features` (mutable — you can add features from inside the
script), `input`, `output`, and `params` from `-sp`. `ffedit` has five modes: print features /
replicate / export JSON / apply JSON / transplicate-with-script **[PRIMARY]**.

**No library API exists.** CLI only. See **C4** for why that does not block the XPC design.

**Maintenance status:** `ffglitch-core` default branch `ffedit-0.10`, last committer date
**2025-05-17**, 292 stars, **zero GitHub releases** (distribution is via ffglitch.org)
**[PRIMARY]**. `ffglitch-scripts` is **Unlicense** (public domain), last pushed **2025-11-02**
**[PRIMARY]** — the scripts repo is the more actively maintained of the two. Newest published
release remains **0.10.2 (2024-10-30)**; no 0.11 exists despite the mis-slugged blog URL.

---

## 2. Prior art in realtime datamosh

### 2.1 Signal Culture's Interstream — mechanism CONFIRMED by local binary inspection

This was the priority question and it is now settled, not inferred. The app is installed on this
machine at `/Applications/Interstream_MACv2.app`, and standard bundle inspection (no decompilation,
no patcher extraction) answers it **[LOCAL]**.

**Product description, verbatim from signalculture.org** **[PRIMARY]**:

> The Interstream Modular App allows users to datamosh movies or live cameras fluidly in realtime.
> Innovative new features include multi-directional, timed blooming and perpetual moshing without
> the need to reset your blooms.

$15 donation, Mac + PC, part of a Syphon/Spout-linked suite. The suite is credited on the page:
*"The Signal Culture Modular Apps are developed by Jason Bernagozzi."* **[PRIMARY]**

**What the bundle actually is** **[LOCAL]**:

- **A Max/MSP + Jitter standalone.** `Contents/Frameworks/` holds `JitterAPI.framework`,
  `JitterAPIImpl.framework`, `MaxAudioAPI.framework`, `MaxLua.framework`, `libmozjs185.dylib`
  (SpiderMonkey). `Contents/Resources/` holds `Interstream_MACv2.mxf` (3.4 MB Max collective) and
  the `C74/` runtime tree. `CFBundleVersion` 9.1.4 = the Max version; `CFBundleShortVersionString`
  2.0. Main executable is a universal x86_64 + arm64 binary.
- **The mosh engine is one custom Jitter external: `jit.interstream.mxo`.** Internal string:
  `Interstream External, \n Signal Culture, 2026`. Binary is arm64, 79,952 bytes, dated 2026-06-26.
- **It links FFmpeg.** `otool -L` on the external:

  ```
  @rpath/libavcodec.62.dylib      (current version 62.28.100)
  @rpath/libavutil.60.dylib       (current version 60.26.100)
  @rpath/libswscale.9.dylib       (current version 9.5.100)
  @rpath/libswresample.6.dylib    (current version 6.3.100)
  /usr/lib/libSystem.B.dylib
  ```

  `LIBAVCODEC_VERSION_MAJOR 62` corresponds to **FFmpeg 8.0** (verified against FFmpeg's
  `version_major.h` at tags `n7.1`=61, `n8.0`=62, `master`=63) **[PRIMARY]**.
- **Bundled codec libraries** in the external's own `Frameworks/`: `libx264.165`, `libx265.215`,
  `libvpx.12`, `libdav1d.7`, `libSvtAv1Enc.4`, plus `libmp3lame`, `libopus`, `libssl`, `libcrypto`.
- **`libavformat` is completely absent** — exhaustive search of the external returned **0 hits**
  **[LOCAL]**. No muxer, no demuxer, no container. It operates on encoded packets in memory.

**The verdict:** Interstream is **bitstream/packet-level, real-codec, in-process, container-less,
libavcodec + libx264**. It is **not** a pixel-domain imitation and **not** ffglitch-based. It is the
same architectural family as your own PyAV/libx264 TouchDesigner component. Your README's credit —
"its real-codec approach (keyframe-free moshing, timed blooming, perpetual mosh)" — is accurate.

**The node contract, from the external's own assist strings** **[LOCAL]**:

```
encode: jit_matrix ARGB 4-plane | decode: jit_matrix 1-plane compressed |
        bang / start / stop / getcodec / getpixfmt
encode: 1-plane compressed matrix | decode: ARGB 4-plane matrix
```

**This is the most transferable idea in the entire survey.** One object with a `decode_mode`
attribute serves as *both* encoder and decoder. In encode mode it takes an ARGB 4-plane matrix and
emits a **1-plane compressed matrix** — the H.264 packet, carried as an ordinary Jitter matrix.
In decode mode it does the reverse. So the compressed bitstream is a **first-class typed value in
the patch**, and every ordinary matrix operator in the environment can mangle it in between.

**Attributes and methods** (names from the binary; **semantics below are [INFERRED]** from the names
plus the marketing copy — I did not run the app or extract the patcher) **[LOCAL** for names**]**:

```
attributes: framecount · decode_mode · codec · pixfmt · planecount · type
            dimlink · planelink · typelink · bframes · predictor · resample
            interlace · bitrate · framerate · dropkeyframes · encwidth · encheight
methods:    listcodecs · listpixfmts · bang · encode_open · encode_close
            decode_open · decode_close · start · stop · assist
defaults:   libx264 · yuv420p · bicubic · preset=ultrafast · tune=zerolatency
also present: libx265 · me_method · full SWS_* scaler enum
error strings: "interstream: encoder '%s' not found"
               "interstream: no decoder found for codec_id %u"
```

Two observations worth acting on:
- **`dropkeyframes` is a real attribute name**, matching the comment already in your
  `datamosher.py` (`"mosh": False, # THE switch (Interstream's 'dropkeyframes')`) **[LOCAL]**. Note
  the tension with your own validated spike result: *"Dropping keyframe packets at the decoder does
  NOT work — FFmpeg's h264 decoder conceals/withholds orphaned P-frames, producing stutter, not
  smear"* **[LOCAL]**. Both can be true if `dropkeyframes` suppresses keyframes at *encode* time
  rather than dropping them at decode time. **[INFERRED** — unresolved, and worth resolving by
  experiment before copying the name.**]**
- **`preset=ultrafast` / `tune=zerolatency` are exactly your settings** **[LOCAL]**, independently
  arrived at. Convergent evidence that this is the right encoder configuration for the job.

**Provenance caveat.** A subagent leg reported that Interstream v1 (Dec 2016, a Cycling '74 projects
page) was created by **Eric Souther** with Jason Bernagozzi and used **vipr** (a libavcodec-for-Max
external by Benjamin Day Smith), with a 2018 *Journal of Artistic Research* paper by the developer
describing the mechanism as varying the bitrate of the stream before decoding **[LEG**, not
re-verified by me**]**. That does not conflict with my binary evidence: **v2 (2026) ships a
purpose-built `jit.interstream` external against modern FFmpeg**, whoever wrote v1 and however.
The v1↔v2 reconciliation is **[INFERRED]**. I did not verify the vipr claim, the 2016 date, or the
JAR paper from a primary source.

**What I deliberately did not do:** decompile the binary or extract `Interstream_MACv2.mxf`. Bundle
structure, `otool -L`, and `strings` on a shipped binary are standard, non-circumventing
inspection; patcher extraction of a paid product is not, and it was not necessary.

### 2.2 mosh-top (Eric Souther / Philosophical Tools) — the most valuable document you have

**[LOCAL]**, from the working copy: MIT, © 2026 Eric Souther / Philosophical Tools, remote
`github.com/ericsouther-source/mosh-top`, actively committed through 2026-07-31 (Windows NSIS
installer, site video, funding link — i.e. it is being *released*, not just written).

Its README states the thesis directly: *"Mosh TOP ingests any TOP, re-encodes it on the fly to a
P-frame-bearing codec, and lets you corrupt, drop, duplicate, and smooth the compressed bitstream in
real time — then decodes the result back to RGBA. The glitches are authentic codec artifacts, not
pixel-domain imitations."*

Mechanism: **in-process C++ TOP linking patched libavcodec** (not shelling out to ffedit). Mosh
modes: `none / idrop / pdup / bitflip / mv`. Plus a "Bitstream Texture Lab" exposing
`coeff / coeffdelta / dc / dcdelta / qscale / macrorepeat / macroshuffle` with a
frequency-band selector (`all / low / mid / high`), gain and bias. Encoder prep via
`av_opt_set(pd, "mpv_flags", "+strict_gop"/"+nopimb"/"+forcemv")` applied **one token at a time**
and `sc_threshold = 1000000000` **[LOCAL]**.

**Techniques worth stealing, in priority order:**
1. **Runtime capability probing rather than a hardcoded matrix** — it calls
   `avcodec_find_decoder()` then tests `capabilities & AV_CODEC_CAP_FFEDIT_BITSTREAM` and
   `ffedit_features & (1 << feature)` **[LOCAL]**. This survives ffglitch version changes. Copy it
   verbatim.
2. **Per-codec gating in the UI** (`applyParameterGating`) so the panel "tells the truth at a
   glance" — parameters that cannot work on the selected codec are visibly disabled **[LOCAL]**.
   Directly applicable given how asymmetric §1.3 is.
3. **"Live Bloom Scrub"** — a rolling buffer of compressed P-frame packets; scrub to any stored
   packet and re-inject that exact packet into the current decoder reference, repeatedly. That is a
   genuinely novel performance gesture and it only exists because the packet is a first-class
   retained object.
4. **Applying `mpv_flags` one token at a time** — a small, real robustness detail; batched flag
   strings fail silently on option-parse differences.
5. Its `spike/` directory contains standalone probes (e.g. `spike_mb_probe.c`) used to verify
   feature availability end-to-end before building on it. Good practice to mirror.

### 2.3 Everything else — and an honest absence

**Categories I can speak to with local or primary evidence:**

| Tool | Mechanism | Real-time? | Licence | Note |
|---|---|:--:|---|---|
| **Interstream v2** | Bitstream/packet, libavcodec + libx264, in-process, no container | **Yes** | Proprietary, $15 | §2.1. Max/Jitter. |
| **mosh-top** | Bitstream, patched libavcodec in-process, C++ TOP | **Yes** | **MIT** | §2.2. Same author lineage. |
| **`interstream_datamosh`** (yours) | Keyframe-free H.264 P-frame duplication via PyAV/libx264 + a GPU-MV path | **Yes** | CC BY-NC 4.0 | ~16 ms/frame at 720p single-encoder **[LOCAL, MEASURED]**. |
| **FFglitch / ffedit / fflive** | Bitstream transplication, MPEG-1/2/4 + MJPEG + PNG | **Yes** (`fflive`, documented 4K) | LGPL-2.1+ core; official builds GPLv2+ | §1. |
| **Live Mosher** (pawelzwronek) | GUI front-end over FFglitch | Yes (drives `fflive`) | **[UNVERIFIED]** | Announced on ffglitch.org 2024-12-24; Win/macOS/Linux; script editor + playback **[PRIMARY]**. Not independently examined. |
| **ffglitch-scripts** | Reference JS/Python scripts + tutorial | n/a | **Unlicense** (public domain) | The single best free source of working MV-manipulation code. Pushed 2025-11-02 **[PRIMARY]**. |
| **Signal Culture PXLMSH** | *"unusual pixel sorting-esque engine that samples pixels along a key edge"* | Yes | Proprietary | **Pixel-domain**, not codec. Listed to keep the distinction clean **[PRIMARY]**. |
| **GLSL optical-flow feedback** ("fake datamosh") | Pixel-domain | Yes, trivially | varies | Your own prior finding: *"can't reproduce macroblock quantization, I-frame color-bleed, or block-tearing — a cheaper/lesser look, not a substitute"* **[LOCAL]**. |
| **Notch "Motion Datamosh" node** | Motion-vector driven | Yes | Proprietary | Cited in your own research as shipping precedent **[LOCAL]**; internals not examined. |

**Tools named in the original brief that I did not independently research this session, and am
therefore not characterising:** Datamosher Pro (Akascape), tomato.py (Kaspar Ravel — note he is
thanked by name in the FFglitch 0.10.0 release credits **[PRIMARY]**), ASDFPixelSort (Kim Asendorf —
pixel-domain, not codec-domain), AviGlitch / ucnv, moshpit, pymosh, Bitrot, ofxDatamosh, FFGL mosh
plugins, and academic work on compressed-domain video manipulation. A subagent leg covered some of
these but I have not re-verified any of it, and I would rather leave the row blank than fill it.
**[UNVERIFIED]**

**The absence, stated properly.** On "has anyone shipped a datamosher that works on a *live*
camera/stream rather than a file, and how did they solve the encode→corrupt→decode latency?" — the
answer is **yes, at least four times**, and none of them solved the latency; they all **accepted**
it and decoupled:
- FFglitch does it with an OS pipe between two processes (`ffgac | fflive`) and an `-asap` flag
  **[PRIMARY]**.
- Interstream does it in-process, container-less, with the packet as a matrix **[LOCAL]**.
- mosh-top does it in-process on a `StreamWorker` **[LOCAL]**.
- Yours does it on the main thread and pays ~16 ms for it **[LOCAL, MEASURED]**.

That convergence is itself the finding: **every shipped real-time datamosher decouples the codec
from the display cadence.** Your free-running decision matches all four. Search surface covered:
ffglitch.org (all pages + all release posts + frontends), ffglitch-scripts, signalculture.org,
GitHub API for both ffglitch repos, the local mosh-top tree, the installed Interstream bundle, and
your own repo's prior research. Not covered: VJ-forum literature, Resolume/VDMX/CoGe plugin
directories, academic databases.

---

## 3. Apple-native codec access

### 3.1 Can VideoToolbox produce a keyframe-free stream?

**Partially, and Apple explicitly refuses to guarantee it.** All quotes verbatim from Apple's
documentation JSON **[PRIMARY]**.

`kVTCompressionPropertyKey_MaxKeyFrameInterval` — *"The maximum interval between key frames, also
known as the key frame rate."*

> Key frames, also known as sync frames, reset inter-frame dependencies… **Video encoders are
> allowed to generate key frames more frequently if doing so results in more efficient
> compression.** The default key frame interval is **0, which indicates that the video encoder
> should choose where to place all key frames.** A key frame interval of 1 indicates that every
> frame must be a keyframe, 2 indicates that at least every other frame must be a keyframe, and so
> on.

Two things follow directly:
- **Setting 0 is the worst possible choice** — it hands placement entirely to the encoder. Set a
  large finite value.
- **It is an upper bound, not a suppression.** There is no documented ceiling, and no documented
  guarantee at any value.

`kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration` pairs with it — *"requires a keyframe every
X frames or every Y seconds, whichever comes first"* — so **both must be set**, or the duration
bound will re-introduce keyframes you thought you had suppressed **[PRIMARY]**.

`kVTCompressionPropertyKey_AllowTemporalCompression` — *"The default value is `true`. Set this value
to false to require key-frame-only compression."* Leave at default; setting false is the exact
opposite of what a mosh needs.

`kVTCompressionPropertyKey_AllowFrameReordering` — *"In order to encode B frames, a video encoder
must reorder frames… The default value is `true`. Set this value to `false` to prevent frame
reordering."* **Set false.** B-frames make packet-level manipulation far harder and add latency.

`kVTCompressionPropertyKey_RealTime` — *"For real-time compression, clients may set this property to
kCFBooleanTrue to recommend that encoding stay timely. By default, this property is `NULL`,
indicating unknown."* Note it is a *recommendation*, and the default is neither true nor false.

**Scene-cut detection: no property exists to disable it.** I enumerated **all 82**
`kVTCompressionPropertyKey_*` symbols from Apple's `compression-properties` index **[PRIMARY]**.
There is **no scene-change / scene-cut key, and no intra-refresh key** — the gradual/rolling intra
refresh that x264 exposes as `intra-refresh=1` has **no VideoToolbox equivalent**. That is a
definite absence over a complete enumeration, not a failed search.

**The counter-evidence, and it is strong.** OBS Studio PR #8677, *"mac-videotoolbox: Enforce minimum
keyframe interval in CRF mode"*, merged 2023-04-06, body verbatim **[PRIMARY**, read from the
GitHub REST API, not a summary**]**:

> Set a default keyframe interval when using Apple VT encoder in CRF mode. If not set, the encoder
> will not create *any* keyframes past the initial one, making the file nearly unusable in editors
> (including FCP) and video players… Sidenote: It seems that
> `kVTCompressionPropertyKey_MaxKeyFrameInterval` just straight up does nothing with the HEVC
> encoder on M1 even in other modes (haven't tested H.264). No matter what it's set no keyframes
> will be created.

So on Apple Silicon, in CRF mode, the hardware encoder was observed producing **exactly one
keyframe, ever**. That is the ideal datamosh source. **Caveats that must ride with this finding:**
M1 only, HEVC only, CRF mode, 2023, single reporter, filed as a bug — meaning Apple may have
"fixed" it. **This must be measured on your hardware, on H.264 and HEVC, before any design depends
on it.** **[PRIMARY** for the report; **[UNVERIFIED]** for current M3/M4 behaviour.**]**

**Other properties that matter for this node** (from the same enumeration) **[PRIMARY]**:

| Property | Why it matters |
|---|---|
| `_AllowOpenGOP` | *"Enables Open GOP (Group Of Pictures) encoding."* FFmpeg reaches it via a dynamically-resolved compat symbol with the literal CFString name **`"AllowOpenGop"`** (lowercase p) **[PRIMARY**, `videotoolboxenc.c`**]** — it post-dates older SDKs. |
| `_EnableLTR` | *"Enables Long Term Reference (LTR) frames during encoding."* A long-term reference is a frame the decoder holds indefinitely — potentially a way to build a mosh that decays toward a held frame rather than toward noise. Speculative but cheap to test. |
| `_ReferenceBufferCount` | Reference frame count. Abstract is **empty** in Apple's docs. A leg reported that setting it to 1 causes all-IDR output **[LEG**, not re-verified — but the direction of the risk is worth respecting**]**. |
| `_H264EntropyMode` | *"controls whether the encoder should use CAVLC or CABAC… The default value is encoder-specific and may change depending on other encoder settings."* **Force CAVLC.** CABAC's arithmetic coding makes byte-level manipulation of the slice payload effectively impossible; CAVLC is tractable. |
| `_MaxAllowedFrameQP` / `_MinAllowedFrameQP` | Direct quantizer control — the blockiness dial. FFmpeg maps `qmin` to `MinAllowedFrameQP` **[PRIMARY]**. |
| `_MaxH264SliceBytes` | Slice size cap — more slices means more independently-decodable units, which changes how corruption spreads spatially. |
| `_BaseLayerFrameRate` / `_BaseLayerFrameRateFraction` / `_BaseLayerBitRateFraction` | Hierarchical-P temporal layers. Abstracts empty in the docs. |
| `_PrioritizeEncodingSpeedOverQuality`, `_MaximizePowerEfficiency`, `_UsingHardwareAcceleratedVideoEncoder` | Latency and hardware-path control. |

**FFmpeg's own wrapper behaviour, read from source** **[PRIMARY]**: it sets
`MaxKeyFrameInterval` **only when `avctx->gop_size > 0`** — so `-g 0` silently leaves Apple's
"encoder decides" default in place. `AllowOpenGOP` is set to false only when
`AV_CODEC_FLAG_CLOSED_GOP` is requested. Per-frame forcing is a one-key dictionary
`{ kVTEncodeFrameOptionKey_ForceKeyFrame: true }` built whenever `frame->pict_type == AV_PICTURE_TYPE_I`
— which is also exactly how you would implement your `reset()` gesture.

**First frame:** I found no documented way to avoid an IDR at session start, and none of the 82
properties addresses it. **[UNVERIFIED]** — assume the first frame is always a keyframe and design
the "arm the mosh" gesture around that.

**Silent IDR re-insertion** on resolution change, error recovery, or `VTCompressionSessionCompleteFrames`:
**[UNVERIFIED]**. Apple documents none of it; the general licence in the `MaxKeyFrameInterval`
discussion ("encoders are allowed to generate key frames more frequently") covers them all.

### 3.2 Is there any Apple API below the packet level?

**No. Verified as an absence over a complete property enumeration and the documented data flow —
but the packet level itself is fully open in both directions, which is the part that matters.**

What you **can** get **[PRIMARY** for the API shapes; **[LEG]** for the exact call sequences**]**:
- `VTCompressionSession` hands you a **`CMSampleBuffer` of compressed data**. `CMSampleBufferGetDataBuffer`
  → `CMBlockBufferGetDataPointer` gives you the **raw AVCC bytes**. Parameter sets (SPS/PPS) come
  from the format description's `avcC` extradata via `CMFormatDescriptionGetExtension` /
  `kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms`.
- `AVAssetReaderTrackOutput` with `nil` outputSettings gives passthrough compressed samples.
- You can construct `CMSampleBuffer`s from **arbitrary bytes** and feed them to
  `VTDecompressionSession` or `AVSampleBufferDisplayLayer`. So corrupt-in / pixels-out is a
  supported round trip.

What you **cannot** get: motion vectors, DCT/transform coefficients, macroblock or CTU data,
quantizer values — anything *inside* a NAL unit. The decompression session's contract is compressed
`CMSampleBuffer` in, `CVImageBuffer` of pixels out, with nothing exposed in between. There is no
supported modern video-decoder plugin API that would let you interpose. **[UNVERIFIED** as a
categorical negative — I searched the VideoToolbox property enumeration and the documented session
APIs; I did not exhaustively search every AVFoundation/CoreMedia symbol.**]**

Adjacent but **not** codec syntax: `VTFrameProcessor` / motion-estimation and optical-flow
processors, and Vision's `VNGenerateOpticalFlowRequest`, produce *analysis* flow fields. They are
computed from pixels, not read from the bitstream. Useful for a different node; not a substitute for
`-f mv`. **[LEG]**

**Two operational traps to write into the spec** **[LEG**, not re-verified, but both are the kind of
silent failure that costs a day**]**:
1. **`kCMSampleAttachmentKey_NotSync` — a sample buffer with no attachment is treated as a sync
   (key) frame.** When you hand-build `CMSampleBuffer`s for P-frames you must explicitly mark them
   `NotSync`, or the decoder will treat every frame as a keyframe and the mosh will simply not
   happen — with no error.
2. VideoToolbox's decoder **error-conceals** rather than failing hard on malformed input —
   community reports describe grey output with accumulating incremental changes. Which is,
   conveniently, datamosh. Worth a deliberate spike.

**Precedent worth noting:** your own prior research records that **Arkestra uses VideoToolbox for
this exact effect via native `VTCompressionSession`** (not the PyAV wrapper), alongside the warning
that VT *"may dedupe a re-fed identical-`frame_num` packet and silently kill the bloom (no error)"*
**[LOCAL]**. Both halves of that are directly relevant: it has been done, and the failure mode is
silent.

---

## 4. Node-graph architectures for realtime video

**Verification caveat, stated up front:** this section rests substantially more on a subagent leg
than sections 1–3 do. I independently read ComfyUI's source and I have TouchDesigner's cook
semantics from the project's own rule files, but I did **not** re-verify the Vuo, Nuke, Cables,
Isadora, Blender or GStreamer specifics against their primary documentation myself. Treat the
mechanism names below as leads to confirm before building on them.

### 4.1 The consensus across every system surveyed

Three patterns hold everywhere, and they are the ones to copy:

**Cycles are illegal; a designated delay node is the only legal way to close a loop.**
Nuke, Blender's compositor, and ComfyUI are strict DAGs. TouchDesigner permits a loop only through
a **Feedback TOP**, which is explicitly a one-frame-delay node — the project's own rules state
*"A Feedback TOP captures its target on frame boundaries, so force-cooking the chain repeatedly
inside one synchronous Python loop returns the same state each time"* **[LOCAL**, project rule
file, and consistent with Derivative's documentation**]**. Max/MSP requires an explicit one-vector
delay in signal loops. **Recommendation: forbid cycles in the ARShader graph and ship exactly one
`Feedback` node whose contract is "returns last frame's value".** Do not attempt general cyclic
scheduling.

**Evaluation is pull-based (demand-driven) in the video systems that matter.**
TouchDesigner is documented pull-based: *"Operators only cook when downstream demands output…
Time-dependent ops cook only when demanded… With nothing demanding it, a correctly-built animated
network sits frozen on its last cooked frame"* **[LOCAL]**. Nuke is pull-based per-frame-range.
Vuo is event-driven; Max is push/message-driven. **For a VJ instrument with a fixed display-link
tick, pull from the master output is the right model** — it gives you dead-branch elimination for
free, which matters when a deck is faded out.

**Type checking is nominal and string-based, and everyone allows an escape hatch.**
ComfyUI, which I read directly **[PRIMARY]**, is the clearest case. `validate_node_input(received_type,
input_type, strict)` treats both as *comma-separated strings* of type names, and returns true if:
the strings are equal (via a `__ne__` override that lets *"legacy `'*'` Any types"* work); either
side is `IO.AnyType.io_type`; either side is `IO.MatchType.io_type` (*"validation for this is
handled by the frontend"*); or, non-strict, the comma-separated sets overlap. The source comment
calls this *"pre-union type extension behaviour"*. That is duck typing with a documented wildcard —
not a type system, and it works.

**Recommendation for ARShader:** nominal string types (`Texture`, `Packet`, `Float`, `Mask`), an
explicit `Any` wildcard, and **connection rejection at edit time** with the error on the wire, not
in a console. And take Interstream's lesson from §2.1: **make the compressed packet its own port
type.** That single decision is what turns a monolithic "datamosh effect" into a patchable
`Encode → [anything] → Decode` chain.

### 4.2 Asynchronous / latent nodes — the crux

This is where the systems genuinely diverge, and where your free-running decision needs a formal
frame.

**GStreamer is the only rigorous treatment.** Its latency design document specifies that elements
declare latency as a **`[min, max]` interval** in response to a `GST_QUERY_LATENCY`, that the
pipeline takes the **maximum of the minimums** and configures a global latency, and that live
sources are the elements that introduce it. If an element's `max` is less than the pipeline's
required `min`, the pipeline cannot run without dropping. **[LEG]** — I did not re-read the
document, but the model is the one worth importing.

**Vuo's port-level policy is the most directly applicable idea in this section.** Vuo trigger ports
are documented as choosing between **dropping events** and **enqueueing events** when downstream
cannot keep up. **[LEG]**. That is *exactly* your free-running decision, expressed as a per-port
property rather than a global mode — and expressing it per-port is strictly better for an
instrument that has to both render live *and* record deterministically. **Recommendation: make
drop-vs-enqueue a node property, defaulting to drop.** A live deck drops; a recorder enqueues.
Baking "always drop" into the host makes offline render impossible later.

**ComfyUI's block/unblock mechanism is the most portable concrete pattern.** A leg reports a
`blockCount` / `add_external_block` / `unblock()` mechanism by which a node can hold up its own
completion and be released asynchronously **[LEG**, not re-verified — I read `execution.py` and
confirmed the `IS_CHANGED` / `fingerprint_inputs` caching path but did not locate this API myself**]**.
The shape — "node declares itself pending, host continues, node signals ready" — maps cleanly onto
a Swift `AsyncStream` or a `MTLSharedEvent` signal from the XPC child.

**TouchDesigner's answer is Time Slicing plus explicit Cache/Delay nodes** rather than a general
latency contract **[LOCAL** for the cook model; **[LEG]** for Time Slicing specifics**]**.

**Recommendation for ARShader:** adopt GStreamer's *shape* (every node publishes a `[min, max]`
latency estimate) and Vuo's *policy* (per-port drop-or-queue), even if the host initially ignores
the latency numbers. Publishing them costs nothing now and is impossible to retrofit once presets
exist.

### 4.3 Feedback loops

Covered in 4.1. One addition specific to a codec node: **the datamosh node is itself a feedback
loop** — the decoder's reference buffer is persistent state that the graph cannot see. That has two
consequences:
- It cannot be treated as a pure function of its inputs, so any caching keyed on input hash
  (ComfyUI's `IS_CHANGED` model) is **wrong** for it. It must declare itself always-dirty.
- Its state must be resettable from the graph (a `reset` input), because that is the effect's
  loudest gesture and users will want it on a MIDI button. **[INFERRED]**

### 4.4 GPU vs CPU scheduling in one graph

**Blender's compositor is the model to copy** **[LEG]**: a device-polymorphic `Result` type that
can live on either CPU or GPU, with reference counting, and explicit `Domain` / realization
handling for size and transform mismatches. The host inserts conversion; the user does not place
readback nodes by hand.

**TouchDesigner's approach is the opposite and is worth avoiding**: the TOP/CHOP/SOP/DAT families
are separate type universes requiring explicit converter operators. It is legible but it clutters
every patch. **[LOCAL]**, from the project's own rules.

**A specific warning for a Swift/GCD host:** a leg reports that Vuo implements its own
`VuoThreadManager` specifically to avoid hitting GCD's **Dispatch Thread Soft Limit** (a hard cap of
64 threads, after which a `dispatch_sync` from an exhausted pool deadlocks) **[LEG**, not
re-verified**]**. If ARShader schedules per-node work onto GCD queues and any node blocks, this is a
real deadlock class. Worth confirming before the scheduler is written — it is much cheaper to design
around than to debug.

**Recommendation:** one `MTLCommandBuffer` per frame for the whole GPU portion of the graph, not one
per node; CPU nodes (the codec) never run on the display-link thread; the host inserts
upload/readback automatically based on a `Result`-style device-polymorphic texture type.

### 4.5 What I could not verify

Per-system specifics for **Vuo** (event semantics, GCD usage, feedback rules), **Nuke** (Op
framework, line-based threading), **Cables.gl**, **Isadora**, **Max/Jitter's** matrix/GL scheduling,
**vvvv**, **Notch**, and **Houdini COPs** rest on a single subagent leg and were **not** re-verified
against primary documentation by me. The GStreamer latency model and ComfyUI's async-block mechanism
likewise. If any of these becomes load-bearing for the design, re-verify it first. **[UNVERIFIED]**

---

## 5. Plugin ABI for a Swift/Metal host

**Verification caveat:** as with §4, this section leans on a subagent leg. The **two load-bearing
numbers** — Apple's 40 µs AUv3 figure and the Metal cross-process API surface — I re-verified
myself against primary sources **[PRIMARY]**. The FxPlug, OFX, Syphon and XPC-semantics details are
**[LEG]**.

### 5.1 The survey, and what it tells you

| System | ABI | Process model | GPU | Crash behaviour |
|---|---|---|---|---|
| **AUv3 app extensions** | ObjC/Swift class (`AUAudioUnit`) in an app extension | **Out-of-process by default on macOS**, opt-in in-process | n/a (audio) | Host survives; extension is restarted **[LEG]** |
| **FxPlug 4** (Motion/FCP) | Apple SDK, ObjC | **Out-of-process, mandatory** | Metal across the boundary | Host survives **[LEG]** |
| **OpenFX** | C ABI, `dlopen`'d bundle, suite/property based | **In-process** | CUDA/OpenCL/Metal render suites | **Host dies with the plugin** **[LEG]** |
| **Syphon** | Framework, server/client | **Cross-process by design**, IOSurface-backed | Yes; Metal server/client classes exist **[LEG]** | Independent processes |
| **Core Image custom filters** | `CIFilter` subclass / `CIKernel` | In-process | Metal-backed CIKernel (`-fcikernel`) | Host dies. Third-party *discoverable* CIFilter plugins are **not** a viable modern distribution path **[LEG]** |
| **FFGL** (Resolume) | C++ in-process | In-process | **OpenGL only** | Host dies |
| **VST3 / CLAP / AE SDK** | C++ in-process | In-process | varies | Host dies (AE's crash reputation is the cautionary tale) |
| **ISF** | **No ABI — it is data** (JSON header + GLSL) | n/a | n/a | Cannot crash the host |

**The pattern is unambiguous and it validates decision (1): every Apple-designed creative plugin
API built in the last decade is out-of-process, and every in-process one takes the host down with
it.** Apple's own stated reasoning, verbatim from WWDC15 S508 **[PRIMARY]**:

> Of course, it's a security risk to be loading third-party code into your app, and if it crashes
> inside your app, then users might blame you instead of the misbehaving plug-in.

FxPlug 4 is the closest analogue to what you are building — a third-party *image* effect with GPU
work, moved out of process by Apple deliberately **[LEG]**. **FFGL is not a usable model** (OpenGL
only). **ISF is worth noting as the counter-design:** a plugin format with no ABI at all, which is
why ARShader already runs third-party shaders safely. A codec node is the case ISF cannot cover, and
that is precisely why it needs a different mechanism.

### 5.2 In-process vs out-of-process for a crash-prone node

For a codec deliberately fed corrupted bitstreams, this is not a close call. The available
mechanisms **[LEG** except where noted**]**:

| Mechanism | Isolation | Restart | Notes |
|---|---|---|---|
| **XPC Service** (`NSXPCConnection`) | Full process boundary | launchd relaunches on demand | The right tool. Bundled inside your app; no separate installation. |
| **App extension / ExtensionKit** | Full | System-managed | Heavier; designed for *third-party* extensions. Overkill if you own the code. |
| `posix_spawn` + socket | Full | You own it | Maximum control, maximum work. |
| In-process `dlopen` | **None** | n/a | A malformed-bitstream crash kills the performance. Non-starter. |

**Crash semantics** — `NSXPCConnection` distinguishes:
- **`interruptionHandler`** — the remote process crashed or was killed. The connection is still
  valid; the next message relaunches the service. **This is your codec-crash path.**
- **`invalidationHandler`** — the connection is permanently dead (service missing, entitlement
  failure). Terminal; do not retry blindly.

**[LEG]** — not re-verified verbatim, but the two-handler distinction is the load-bearing detail
and worth confirming against Apple's docs before implementing, because conflating them produces
either a hang or an infinite relaunch loop.

**Open question you must settle by experiment, not by reading:** whether a *sandboxed* XPC service
can create an `MTLDevice`, and what entitlements it needs. FxPlug 4 plugins demonstrably do GPU work
out of process **[LEG]**, which is strong circumstantial evidence that it works — but I found no
Apple documentation stating it directly. **[UNVERIFIED]**. This is a one-hour spike and it gates the
entire design; do it first.

### 5.3 Texture-sharing cost on Apple Silicon

**The API surface is confirmed** — all five symbols read from Apple's documentation JSON this
session **[PRIMARY]**:

```swift
MTLDevice.makeTexture(descriptor:iosurface:plane:) -> (any MTLTexture)?
    // "Creates a texture instance that uses I/O surface to store its underlying data."
MTLTexture.makeSharedTextureHandle()   -> MTLSharedTextureHandle?
    // "If the texture is not shareable, this method returns nil."
MTLDevice.makeSharedTexture(handle:)   -> (any MTLTexture)?
    // "Call this method from the same [device] instance that created the shared texture instance."
MTLSharedEvent.makeSharedEventHandle() -> MTLSharedEventHandle
MTLDevice.makeSharedEvent(handle:)     -> (any MTLSharedEvent)?
    // "Recreates a shared event from a handle."
```

**The cost model, and this is the number that matters:**

- **Handle exchange is one-time, at connection setup.** IOSurface and `MTLSharedEvent` handles are
  passed once; per-frame synchronisation is an event signal, not an XPC message carrying pixels.
  **[INFERRED]** from the API shapes — standard practice, but no single Apple doc states it
  end-to-end.
- **IOSurface on Apple Silicon UMA is genuinely shared memory, not a copy** — CPU and GPU address
  the same pages. **[LEG]**, and consistent with the `makeTexture(descriptor:iosurface:plane:)`
  wording ("uses I/O surface to store its underlying data").
- **XPC round-trip:** Apple's own measured figure for out-of-process AUv3 is **"on the order of 40
  microseconds per render cycle"**, with their worked example *"if you are rendering at a very low
  latency of 32 frames, that's a 1 millisecond render interval, so overhead of 40 microseconds
  could be significant at 5.5 percent"* **[PRIMARY**, WWDC15 S508, verbatim; MEASURED by Apple,
  hardware and date unstated**]**. Against a 16.7 ms video frame that is ~0.24% **[INFERRED**, my
  arithmetic, **ILLUSTRATIVE** — this is an audio measurement being reused as an order of
  magnitude, not a video benchmark**]**.
- **I found no published Apple-Silicon-specific XPC microbenchmark, and no published Syphon
  frame-delivery latency figure.** **[UNVERIFIED]**. If you need a real number, measure it — a
  ping-pong `NSXPCConnection` benchmark is twenty minutes of work and will be more trustworthy than
  anything I could cite.

**Put against your own measurements, the conclusion is clear:** the codec costs ~16 ms per 720p
frame on this machine **[LOCAL, MEASURED]**; the IPC costs tens of microseconds. **The process
boundary is free. The codec is the entire budget.**

**What is *not* free, and is under-weighted in the current design:** the child does **CPU** codec
work, so every frame crosses BGRA→YUV420p→encode→mosh→decode→YUV420p→BGRA. Two `swscale`
conversions per frame, on CPU, at full resolution. In your existing component this is bundled into
the measured cost and it is a meaningful fraction of it. Three mitigations worth speccing:
1. **Encode resolution as a first-class parameter, decoupled from output resolution** — you already
   proved this is the dominant lever (720p→480p took 3 encoders from ~48 ms to ~23.6 ms
   **[LOCAL, MEASURED]**), and low-resolution encode is aesthetically *correct* for datamosh.
2. Allocate the shared IOSurface in a **format the codec wants** where possible, so one conversion
   disappears.
3. Keep the conversion in the child, never on the host's render thread.

### 5.4 Additional gotchas worth capturing

- **Raw `IOSurfaceRef` reportedly does not survive `NSXPCConnection`** — use the ObjC `IOSurface *`
  class (NSSecureCoding-conformant) or `IOSurfaceCreateXPCObject` / `IOSurfaceLookupFromXPCObject`.
  **[LEG]**, not re-verified, but it is the kind of thing that fails at runtime with an unhelpful
  message.
- **`makeSharedTexture(handle:)` must be called from the same `MTLDevice`** that created the shared
  texture — Apple states this explicitly **[PRIMARY]**. On a multi-GPU Mac that is a real
  constraint; on Apple Silicon it is trivially satisfied.
- **Code signing and notarization**: an XPC service bundled in the app inherits the app's signature,
  which is simpler than a separately-distributed plugin. Note that the repo's own README already
  says the app *"isn't notarized (it's shared friend-to-friend)"* **[LOCAL]** — worth confirming
  that an unnotarized app can still launch its own bundled XPC service under current Gatekeeper
  rules before assuming it. **[UNVERIFIED]**

---

## Open questions and explicit gaps

Listed as a discrete, searchable set rather than buried in prose.

1. **Does a sandboxed XPC service get GPU / `MTLDevice` access, and with what entitlements?**
   **[UNVERIFIED]** — gates the whole architecture. Spike this first.
2. **Interstream's `dropkeyframes` semantics** — encode-time suppression or decode-time packet drop?
   The name conflicts with your own validated finding that decode-time keyframe dropping does not
   work. **[INFERRED**, unresolved.**]**
3. **Current VideoToolbox keyframe behaviour on M3/M4, H.264 and HEVC.** The OBS report is M1/HEVC/
   CRF/2023 and was filed as a bug. **[UNVERIFIED]** — measure before depending on it.
4. **Does VideoToolbox silently re-insert IDR** on resolution change, error recovery, or
   `CompleteFrames`? No Apple documentation found. **[UNVERIFIED]**
5. **Can the first frame of a VT session be anything but an IDR?** No mechanism found among 82
   properties. **[UNVERIFIED]**
6. **`ReferenceBufferCount = 1` → all-IDR?** **[LEG]**, unconfirmed.
7. **`kCMSampleAttachmentKey_NotSync` default behaviour.** **[LEG]** — verify before hand-building
   sample buffers, it is a silent-failure trap.
8. **Interstream v1's mechanism, the vipr claim, and the 2018 JAR paper.** **[LEG]**, not
   independently verified. Does not affect the v2 finding.
9. **Live Mosher's internals** and whether its script surface is worth borrowing. **[UNVERIFIED]**
10. **Vuo, Nuke, Cables, Isadora, Max/Jitter, vvvv, Notch internals** in §4, and **FxPlug 4, OFX,
    Syphon, NSXPCConnection handler semantics, GCD thread-limit** in §5 — single-leg sourced, not
    re-verified. **[UNVERIFIED]**
11. **Datamosher Pro, tomato.py, AviGlitch/ucnv, moshpit, pymosh, ofxDatamosh, FFGL mosh plugins,
    and the academic compressed-domain literature** — not researched by me this session.
    **[UNVERIFIED]**
12. **Published Apple-Silicon XPC round-trip benchmark** and **Syphon frame-delivery latency**: none
    found. **[UNVERIFIED]** — measure locally.
13. **Whether an unnotarized app can launch its own bundled XPC service** under current Gatekeeper.
    **[UNVERIFIED]**
14. **GPL/LGPL posture** of a shipping ARShader that talks to an ffglitch-derived child process.
    Facts gathered (§1.5); **legal review not performed and not a substitute for one.**

---

## Verification notes

- I did not modify any file in the ShaderToy-to-ISF-converter repo other than creating this one.
  No commits, no branch operations, no `git checkout/switch/reset/stash`.
- `docs/research/` did not exist and was created to hold this file.
- Downloads (ffglitch 0.10.2 source tarball, macOS aarch64 binary archive, FFmpeg source files,
  ComfyUI source) went to the session scratchpad, not into any project repo. No downloaded binary
  was executed; the shipped ffglitch binaries were inspected with `strings`, `file` and `unzip -l`
  only.
- `/Applications/Interstream_MACv2.app` was inspected read-only (`ls`, `PlistBuddy -c Print`,
  `otool -L`, `file`, `strings`, `find`). Nothing was launched, extracted, decompiled, or modified.
- Exhaustive-search claims and their actual results, no truncation:
  `forcemv|nopimb` in stock FFmpeg n7.1 `mpegvideoenc.h` → **0 hits**;
  `*avformat*` anywhere in `jit.interstream.mxo` → **0 hits**;
  `kVTCompressionPropertyKey_*` in Apple's compression-properties index → **82 symbols, no
  intra-refresh key, no scene-cut key**;
  `.p.ffedit_features` across ffglitch 0.10.2 `libavcodec/` → **7 declarations across 4 files**
  (mjpeg, mpeg1video, mpeg2video, mpegvideo, mpeg4, png, apng).
- Five quarantined `web-researcher` legs were dispatched and all five returned. All findings were
  scanned for prompt-injection markers; none found. Direct primary probes were run in parallel and
  take precedence wherever they overlap. Where a leg's claim conflicted with my own read, my read
  is reported and the conflict noted (the ffedit-0.10 date discrepancy resolved as author-date vs
  committer-date; the Interstream v1/v2 mechanism resolved as two different implementations).
- Section 1–3 claims are predominantly [LOCAL] or [PRIMARY]. Sections 4–5 are predominantly [LEG]
  and are labelled as such throughout. This asymmetry is real and deliberate; do not read the
  brief as uniformly verified.
