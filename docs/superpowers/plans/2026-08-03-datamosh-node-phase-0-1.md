# Datamosh Node — Phases 0a, 0b, 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the out-of-process node architecture end to end — a patched-libavcodec datamosh engine running standalone, and an XPC-hosted trivial node delivering frames into ARShader's FX chain through shared IOSurfaces — so that phase 2 can drop the real engine into a pipe that already works.

**Architecture:** A new XPC service (`MoshNode.xpc`) embedded in `ARShader.app` owns all codec state and can crash without taking the instrument down. Frames cross the process boundary as IOSurface-backed `MTLTexture`s shared once at connection setup; per-frame IPC carries only a slot index and a parameter snapshot. `FXStage` is generalized behind an `FXStageBacking` protocol so ISF stages and native stages are both first-class. The node is free-running: it holds its last output when no new frame is ready, never passing its input through, because a clean frame is visually identical to a reset.

**Tech Stack:** Swift 5.9 / SwiftUI / Metal, XcodeGen (`App/project.yml`), XCTest, C++17, CMake, ffglitch-core (patched FFmpeg), libx264.

**Spec:** `docs/superpowers/specs/2026-08-03-datamosh-node-design.md`
**Research:** `docs/research/2026-08-03-datamosh-node-research.md`

## Global Constraints

- **Platform:** macOS 13.0 deployment target, Apple Silicon (arm64) only. No Windows, no Intel.
- **ARShader is unsandboxed** (`com.apple.security.app-sandbox` = `false`). Hardened runtime is ON in Release, OFF in Debug.
- **Signing:** `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: Q9DY8S68BC`. Any new target must match, or TCC grants and XPC launch break.
- **Project generation:** targets are defined in `App/project.yml` and the `.xcodeproj` is generated. **Never hand-edit `App/TrueISFEditor.xcodeproj`.** After editing `project.yml`, run `cd App && xcodegen generate`.
- **ffglitch pin:** repo `https://github.com/ramiropolla/ffglitch-core.git`, branch `ffedit-0.10`, commit `4b71d60c6640ad3f9ce483eac14391dc73f8c950`. This is `ffglitch-0.10.3-dev`, ~14 commits AHEAD of the `0.10.2` tag. Do not "upgrade" it.
- **Starvation behavior:** a native stage that has no fresh decoded frame returns its **last decoded output**, never its input. Pass-through is reachable only via an explicit Bypass control. See spec §4.1.
- **Sequence contract:** the host publishes frames and never replays or reorders them, and never assumes output frame N corresponds to input frame N. See spec §6.
- **Existing suites must stay green.** `ARShaderTests` and `TrueISFEditorTests` pass before and after every task. The `FXStageBacking` refactor is behavior-preserving by definition, and those suites are the evidence.
- **Never commit `third_party/` build outputs to git** beyond the archives explicitly staged in Task 3. Build trees (`build-*/`, checked-out ffglitch source) are gitignored.

---

## File Structure

**New — engine, outside the Xcode project:**

| Path | Responsibility |
|---|---|
| `Engine/ffglitch.lock` | Pinned source identity: repo, branch, commit, patch checksum. Single source of truth for the build script. |
| `Engine/build_ffglitch.sh` | Checks out the pinned commit, verifies the patch checksum, configures with `--enable-libx264`, builds static archives into `Engine/third_party/`. |
| `Engine/patches/ffglitch-snow-always-reset.patch` | Vendored from mosh-top. Exposes Snow's `always_reset` bitstream flag as an encoder option. |
| `Engine/mosh/src/*` | Vendored mosh-top engine, TD shim removed. |
| `Engine/mosh/tests/*` | Vendored mosh-top ctest suite, unchanged. |
| `Engine/mosh/CMakeLists.txt` | Builds `libmoshengine.a`, the ctest suite, and the `moshcli` harness. |
| `Engine/mosh/src/MoshEngine.h` / `.cpp` | **New.** The host-independent engine facade replacing `MoshTOP.cpp`. Owns a `StreamWorker`, takes RGBA8 in, gives RGBA8 out. |
| `Engine/mosh/tools/moshcli.cpp` | **New.** Headless file-in/file-out harness proving the engine detached from any host. |

**New — Swift, inside the Xcode project:**

| Path | Responsibility |
|---|---|
| `App/FXNodeKit/FXStageBacking.swift` | The protocol that generalizes a stage's source of pixels. |
| `App/FXNodeKit/ISFStageBacking.swift` | ISF conformer. Wraps the existing `MetalRenderCore.renderOffscreen` call. |
| `App/FXNodeKit/SurfaceRing.swift` | Fixed-size ring of IOSurface-backed `MTLTexture`s with drop-on-contention publish. |
| `App/FXNodeKit/NodeProtocol.swift` | The `@objc` XPC protocol shared by host and service, plus the `NodeFrameSlot` payload. |
| `App/FXNodeKit/NodeConnection.swift` | Owns the `NSXPCConnection`: handshake, surface exchange, relaunch with backoff, crash-loop disable. |
| `App/FXNodeKit/NativeNodeBacking.swift` | `FXStageBacking` conformer. Publishes into the ring, polls for output, holds last output on starvation. |
| `App/MoshNode/main.swift` | XPC service entry point. |
| `App/MoshNode/NodeService.swift` | Service-side implementation of `NodeProtocol`. Phase 1: inverts. Phase 2: calls the engine. |
| `App/MoshNode/MoshNode.entitlements` | Service entitlements. |
| `App/MoshNode/Info.plist` | `XPCService` dictionary. |

**Modified:**

| Path | Change |
|---|---|
| `App/project.yml` | Add the `MoshNode` xpc-service target; add `FXNodeKit` sources and the service dependency to `ARShader` and `ARShaderTests`. |
| `App/ARShader/FXStage.swift:10-19` | `unit` becomes optional; stage gains a `backing`. |
| `App/ARShader/FXChain.swift:6-10, 116-138` | `FXStageSnapshot` carries a backing rather than a `MetalRenderCore`; `encode` calls `backing.produce`. |
| `.gitignore` | Ignore `Engine/third_party/`, `Engine/build-*`, `Engine/ffglitch-src/`. |

**New tests:**

| Path | Covers |
|---|---|
| `App/ARShaderTests/SurfaceRingTests.swift` | Ring allocation, drop-on-contention, slot reuse. |
| `App/ARShaderTests/NativeNodeBackingTests.swift` | Hold-last-output, the three nil cases, crash-loop disable. |
| `App/ARShaderTests/NodeConnectionTests.swift` | Handshake, surface round-trip, relaunch after kill. |
| `Engine/mosh/tests/MoshEngineTests.cpp` | The engine facade: RGBA8 in, RGBA8 out, reset, param changes. |

---

## Task 1: Architecture spike — XPC, GPU, and IOSurface (BLOCKING)

**This task gates the entire plan.** If both GPU access and IOSurface mapping fail in the service, stop, report, and re-plan against the in-process dynamic-bundle fallback in spec §4. Timebox: one hour.

The risk is lower than the research assumed, because ARShader is unsandboxed. This task confirms rather than discovers — but it confirms before nine thousand lines depend on it.

**Files:**
- Create: `App/MoshNode/main.swift`
- Create: `App/MoshNode/NodeService.swift`
- Create: `App/MoshNode/Info.plist`
- Create: `App/MoshNode/MoshNode.entitlements`
- Create: `App/FXNodeKit/NodeProtocol.swift`
- Modify: `App/project.yml`
- Test: `App/ARShaderTests/NodeConnectionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NodeProtocol` (`@objc` protocol, methods `probeCapabilities(reply:)` and `acceptSurface(_:reply:)`); `NodeCapabilities` (a `Codable` struct with `hasMetalDevice: Bool`, `deviceName: String?`, `canMapSurface: Bool`); the `MoshNode.xpc` target and its bundle id `com.arsonrivvers.ARShader.MoshNode`.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/NodeConnectionTests.swift`:

```swift
import XCTest
import IOSurface
@testable import ARShader

final class NodeConnectionTests: XCTestCase {

    /// Opens a connection to the embedded XPC service. Returns nil if the service is missing,
    /// which is a build-configuration failure rather than a test failure worth asserting on here.
    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(serviceName: "com.arsonrivvers.ARShader.MoshNode")
        c.remoteObjectInterface = NSXPCInterface(with: NodeProtocol.self)
        c.resume()
        return c
    }

    func testServiceReportsItsGPUAndSurfaceCapabilities() throws {
        let connection = makeConnection()
        defer { connection.invalidate() }

        let answered = expectation(description: "probe returned")
        var caps: NodeCapabilities?

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC error: \(error)")
            answered.fulfill()
        } as? NodeProtocol
        XCTAssertNotNil(proxy, "remote proxy must conform to NodeProtocol")

        proxy?.probeCapabilities { data in
            caps = try? JSONDecoder().decode(NodeCapabilities.self, from: data)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 10)

        let c = try XCTUnwrap(caps, "service must answer the probe")
        // The load-bearing assertion: the child can map a shared surface. GPU access is
        // reported but NOT required — the engine is pure CPU and may never need Metal.
        XCTAssertTrue(c.canMapSurface, "the service must be able to map an IOSurface")
        print("SPIKE: hasMetalDevice=\(c.hasMetalDevice) device=\(c.deviceName ?? "nil") canMapSurface=\(c.canMapSurface)")
    }

    func testServiceWritesThroughASharedSurface() throws {
        let connection = makeConnection()
        defer { connection.invalidate() }

        // A 4x4 BGRA surface, zeroed. The service must stamp 0xFF into byte 0 of pixel 0.
        let props: [IOSurfacePropertyKey: Any] = [
            .width: 4, .height: 4, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        let surface = try XCTUnwrap(IOSurface(properties: props), "surface allocation failed")

        surface.lock(options: [], seed: nil)
        memset(surface.baseAddress, 0, surface.allocationSize)
        surface.unlock(options: [], seed: nil)

        let stamped = expectation(description: "service stamped the surface")
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC error: \(error)")
            stamped.fulfill()
        } as? NodeProtocol

        proxy?.acceptSurface(surface) { ok in
            XCTAssertTrue(ok, "service reported it could not map the surface")
            stamped.fulfill()
        }
        wait(for: [stamped], timeout: 10)

        surface.lock(options: .readOnly, seed: nil)
        let firstByte = surface.baseAddress.assumingMemoryBound(to: UInt8.self).pointee
        surface.unlock(options: .readOnly, seed: nil)
        XCTAssertEqual(firstByte, 0xFF, "the write must be visible in the host's process")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NodeConnectionTests 2>&1 | tail -30
```

Expected: FAIL — `NodeProtocol` and `NodeCapabilities` are undefined; the target does not compile.

- [ ] **Step 3: Define the shared protocol**

Create `App/FXNodeKit/NodeProtocol.swift`:

```swift
import Foundation
import IOSurface

/// What the service can do in its own process. Answered over XPC as JSON so the struct can gain
/// fields without an NSSecureCoding dance.
struct NodeCapabilities: Codable, Sendable {
    let hasMetalDevice: Bool
    let deviceName: String?
    let canMapSurface: Bool
}

/// The host↔service contract. `@objc` because NSXPCConnection requires an ObjC protocol.
///
/// IOSurface (the ObjC class, not IOSurfaceRef) conforms to NSSecureCoding, so it crosses
/// NSXPCConnection directly. A raw IOSurfaceRef does NOT — that is the trap this avoids.
@objc protocol NodeProtocol {
    /// JSON-encoded `NodeCapabilities`.
    func probeCapabilities(reply: @escaping (Data) -> Void)

    /// Maps the surface in the service's address space and stamps 0xFF into its first byte.
    /// Spike-only; replaced by the real frame path in Task 8.
    func acceptSurface(_ surface: IOSurface, reply: @escaping (Bool) -> Void)
}
```

- [ ] **Step 4: Write the service**

Create `App/MoshNode/NodeService.swift`:

```swift
import Foundation
import IOSurface
import Metal

final class NodeService: NSObject, NodeProtocol {

    func probeCapabilities(reply: @escaping (Data) -> Void) {
        let device = MTLCreateSystemDefaultDevice()

        // Prove surface mapping independently of Metal: allocate one here and touch it.
        var canMap = false
        let props: [IOSurfacePropertyKey: Any] = [
            .width: 4, .height: 4, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        if let probe = IOSurface(properties: props) {
            probe.lock(options: [], seed: nil)
            probe.baseAddress.assumingMemoryBound(to: UInt8.self).pointee = 0x01
            canMap = probe.baseAddress.assumingMemoryBound(to: UInt8.self).pointee == 0x01
            probe.unlock(options: [], seed: nil)
        }

        let caps = NodeCapabilities(hasMetalDevice: device != nil,
                                    deviceName: device?.name,
                                    canMapSurface: canMap)
        reply((try? JSONEncoder().encode(caps)) ?? Data())
    }

    func acceptSurface(_ surface: IOSurface, reply: @escaping (Bool) -> Void) {
        surface.lock(options: [], seed: nil)
        surface.baseAddress.assumingMemoryBound(to: UInt8.self).pointee = 0xFF
        surface.unlock(options: [], seed: nil)
        reply(true)
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NodeProtocol.self)
        connection.exportedObject = NodeService()
        connection.resume()
        return true
    }
}
```

Create `App/MoshNode/main.swift`:

```swift
import Foundation

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()   // never returns
```

- [ ] **Step 5: Write the service bundle metadata**

Create `App/MoshNode/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.arsonrivvers.ARShader.MoshNode</string>
  <key>CFBundleName</key><string>MoshNode</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>XPCService</key>
  <dict>
    <key>ServiceType</key><string>Application</string>
  </dict>
</dict>
</plist>
```

Create `App/MoshNode/MoshNode.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Unsandboxed, matching the host app. The service reads no user files; this keeps its
       IOSurface and GPU access unqualified while the architecture is being proven. -->
  <key>com.apple.security.app-sandbox</key><false/>
</dict>
</plist>
```

- [ ] **Step 6: Add the target to project.yml**

In `App/project.yml`, add to `targets:` (sibling of `ARShader`):

```yaml
  MoshNode:
    type: xpc-service
    platform: macOS
    sources:
      - path: MoshNode
      - path: FXNodeKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arsonrivvers.ARShader.MoshNode
        INFOPLIST_FILE: MoshNode/Info.plist
        CODE_SIGN_ENTITLEMENTS: MoshNode/MoshNode.entitlements
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: Q9DY8S68BC
        ENABLE_HARDENED_RUNTIME: YES
        GENERATE_INFOPLIST_FILE: NO
        SKIP_INSTALL: YES
      configs:
        Debug:
          ENABLE_HARDENED_RUNTIME: NO
```

Then, in the `ARShader` target, add `FXNodeKit` to `sources` (after `- path: ARShader`) and the service to `dependencies`:

```yaml
      - target: MoshNode
        embed: true
        codeSign: true
```

And in `ARShaderTests`, add `- path: FXNodeKit` to `sources` so the test bundle can see `NodeProtocol`.

Finally add `MoshNode: all` under the `ARShader` scheme's `build.targets`.

- [ ] **Step 7: Regenerate and run**

```bash
cd App && xcodegen generate
xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NodeConnectionTests 2>&1 | tail -40
```

Expected: PASS, both tests. The `SPIKE:` line prints the GPU answer.

**Decision gate.** If `canMapSurface` is false, or the service cannot be reached at all, **STOP** — the out-of-process design does not hold. Record the failure and re-plan against spec §4's in-process fallback. If `canMapSurface` is true but `hasMetalDevice` is false, that is **fine and expected to be survivable**: the engine is pure CPU. Record it and continue.

- [ ] **Step 8: Verify the existing suites still pass**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' 2>&1 | tail -20
```

Expected: all `ARShaderTests` pass. A new embedded target must not disturb them.

- [ ] **Step 9: Record the result and commit**

Create `docs/reports/spike-xpc-surface-2026-08-03.md` with: the printed `SPIKE:` line verbatim, the macOS and hardware versions from `sw_vers` and `sysctl -n machdep.cpu.brand_string`, and a one-line verdict (`PROCEED` or `STOP`).

```bash
git add App/project.yml App/MoshNode App/FXNodeKit/NodeProtocol.swift \
        App/ARShaderTests/NodeConnectionTests.swift docs/reports/spike-xpc-surface-2026-08-03.md
git commit -m "spike(node): prove XPC service can map a host IOSurface"
```

---

## Task 2: Build patched libavcodec with libx264

Produces the static archives every later engine task links against. No Swift in this task.

**Files:**
- Create: `Engine/ffglitch.lock`
- Create: `Engine/patches/ffglitch-snow-always-reset.patch`
- Create: `Engine/build_ffglitch.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: `Engine/third_party/ffglitch-mac/lib/*.a` (`libavcodec.a`, `libavutil.a`, `libswscale.a`, `libswresample.a`) and `Engine/third_party/ffglitch-mac/include/`. Later tasks link against exactly these paths.

- [ ] **Step 1: Vendor the lockfile and the patch**

Copy the patch from the mosh-top checkout (it is MIT-licensed wrapper content):

```bash
mkdir -p Engine/patches Engine/third_party
MOSH=/private/tmp/claude-501/-Users-arsonrivvers-Desktop-AV-Projects-max-mcp-interstream-td/13ea334d-ba0d-42b4-b2b8-9a95ee0edf1b/scratchpad/mosh-top
cp "$MOSH/patches/ffglitch-snow-always-reset.patch" Engine/patches/
shasum -a 256 Engine/patches/ffglitch-snow-always-reset.patch
```

Expected checksum: `459ba9bf8690ee703717c90e8f158d29bd69cfe5c812c78421d42ec383a01591`

If the mosh-top checkout is gone, re-clone it: `git clone --depth 1 --branch v1.3 https://github.com/ericsouther-source/mosh-top.git`.

Create `Engine/ffglitch.lock`:

```sh
# Canonical ffglitch source identity. Shared by the build script and any packaging.
# This commit is ffglitch-0.10.3-dev, roughly 14 commits AHEAD of the 0.10.2 tag.
# Do NOT "upgrade" it to the 0.10.2 tarball.
FFGLITCH_REPO=https://github.com/ramiropolla/ffglitch-core.git
FFGLITCH_BRANCH=ffedit-0.10
FFGLITCH_COMMIT=4b71d60c6640ad3f9ce483eac14391dc73f8c950
FFGLITCH_VERSION=ffglitch-0.10.3-dev
FFGLITCH_PATCH=patches/ffglitch-snow-always-reset.patch
FFGLITCH_PATCH_SHA256=459ba9bf8690ee703717c90e8f158d29bd69cfe5c812c78421d42ec383a01591
```

- [ ] **Step 2: Write the build script**

Create `Engine/build_ffglitch.sh`:

```bash
#!/usr/bin/env bash
# Builds patched libavcodec (ffedit features) WITH libx264, for arm64 macOS.
#
# Why --enable-libx264 matters: the ffedit patches are additive (new ffedit_*.c files, a new
# `ffedit_features` struct field, new capability bits) and touch none of the encoder wrappers, so
# x264 coexists cleanly. Official ffglitch builds omit it; we need it because our H.264
# P-frame-duplication engine and the MPEG-family bitstream editing share one library.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/ffglitch.lock"

SRC="$HERE/ffglitch-src"
OUT="$HERE/third_party/ffglitch-mac"

command -v pkg-config >/dev/null || { echo "need pkg-config: brew install pkg-config"; exit 1; }
pkg-config --exists x264 || { echo "need x264: brew install x264"; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  git clone --branch "$FFGLITCH_BRANCH" "$FFGLITCH_REPO" "$SRC"
fi
git -C "$SRC" fetch --all --tags
git -C "$SRC" checkout --force "$FFGLITCH_COMMIT"
git -C "$SRC" clean -fdx

# Verify the patch before applying it. A silently-changed patch is a silently-changed binary.
ACTUAL="$(shasum -a 256 "$HERE/$FFGLITCH_PATCH" | awk '{print $1}')"
[ "$ACTUAL" = "$FFGLITCH_PATCH_SHA256" ] || {
  echo "patch checksum mismatch: $ACTUAL != $FFGLITCH_PATCH_SHA256"; exit 1; }
git -C "$SRC" apply "$HERE/$FFGLITCH_PATCH"

cd "$SRC"
# --enable-gpl is REQUIRED by libx264 and is acceptable here: nothing is distributed.
# See spec §11 before ever changing that assumption.
./configure \
  --prefix="$OUT" \
  --arch=arm64 --enable-static --disable-shared \
  --disable-programs --disable-doc --disable-autodetect \
  --enable-gpl --enable-libx264 \
  --enable-zlib \
  --disable-avdevice --disable-avfilter --disable-postproc
make -j"$(sysctl -n hw.ncpu)"
make install

echo "--- verifying ---"
# 1. ffedit capability bits present in libavcodec.
nm -g "$OUT/lib/libavcodec.a" 2>/dev/null | grep -q ffedit \
  && echo "OK: ffedit symbols present" || { echo "FAIL: no ffedit symbols"; exit 1; }
# 2. x264 encoder linked in.
nm -g "$OUT/lib/libavcodec.a" 2>/dev/null | grep -q X264_init \
  && echo "OK: libx264 encoder present" || { echo "FAIL: no libx264"; exit 1; }
# 3. The ffedit_features struct field exists in the installed headers.
grep -q "ffedit_features" "$OUT/include/libavcodec/codec.h" \
  && echo "OK: ffedit_features field in codec.h" || { echo "FAIL: header not patched"; exit 1; }
echo "Built $FFGLITCH_VERSION into $OUT"
```

Make it executable: `chmod +x Engine/build_ffglitch.sh`

- [ ] **Step 3: Ignore build outputs**

Append to `.gitignore`:

```
# Datamosh engine build trees (see Engine/build_ffglitch.sh)
Engine/ffglitch-src/
Engine/third_party/
Engine/build-*/
```

- [ ] **Step 4: Run the build**

```bash
brew install pkg-config x264
./Engine/build_ffglitch.sh 2>&1 | tail -30
```

Expected: three `OK:` lines and `Built ffglitch-0.10.3-dev`. This takes several minutes on first run.

If configure fails on `libx264 not found`, confirm `pkg-config --cflags x264` resolves; Homebrew on Apple Silicon installs to `/opt/homebrew`, so `PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig` may be needed.

- [ ] **Step 5: Commit**

```bash
git add Engine/ffglitch.lock Engine/patches Engine/build_ffglitch.sh .gitignore
git commit -m "build(engine): reproducible patched-libavcodec build with libx264"
```

---

## Task 3: Vendor the mosh-top engine and get its tests green

**Files:**
- Create: `Engine/mosh/src/` (from mosh-top, minus `MoshTOP.cpp`, `MoshTOP.h`, `MinGWStubs.cpp`)
- Create: `Engine/mosh/tests/` (from mosh-top, unchanged)
- Create: `Engine/mosh/CMakeLists.txt`
- Create: `Engine/mosh/THIRD_PARTY.md`

**Interfaces:**
- Consumes: `Engine/third_party/ffglitch-mac/` from Task 2.
- Produces: CMake target `moshengine` (a static library) exporting `MoshNS::StreamWorker`, `MoshNS::Parameters`, `MoshNS::MoshOps`, `MoshNS::MvFieldOps` as declared in the vendored headers. `Engine/mosh/build/` holds the ctest suite.

- [ ] **Step 1: Copy the engine sources, minus the TouchDesigner shim**

```bash
MOSH=/private/tmp/claude-501/-Users-arsonrivvers-Desktop-AV-Projects-max-mcp-interstream-td/13ea334d-ba0d-42b4-b2b8-9a95ee0edf1b/scratchpad/mosh-top
mkdir -p Engine/mosh/src Engine/mosh/tests Engine/mosh/tools
cp "$MOSH"/src/{StreamWorker,MoshOps,MvFieldOps,Parameters}.{h,cpp} Engine/mosh/src/
cp "$MOSH"/src/{PixelRouting.h,FFEditJsonBridge.h,FFEditJsonBridge.c} Engine/mosh/src/
cp "$MOSH"/tests/*.cpp Engine/mosh/tests/
cp "$MOSH"/LICENSE Engine/mosh/LICENSE-mosh-top
```

Deliberately NOT copied: `MoshTOP.cpp`, `MoshTOP.h` (the TD plugin shim, replaced in Task 4) and `MinGWStubs.cpp` (Windows only).

- [ ] **Step 2: Strip the TouchDesigner coupling from Parameters and StreamWorker**

`Parameters.h` currently does `#include "CPlusPlus_Common.h"` and declares
`static Parameters read(const OP_Inputs*)` plus `static void setupParameters(OP_ParameterManager*)`.
Delete the include and both declarations; keep the `Parameters` struct, every `enum class`, `resolveDims`, and all the `parse*` free functions. In `Parameters.cpp`, delete `setupParameters` and `Parameters::read` — everything from the `appendDivider` helper through the end of `setupParameters`, and the `read` definition. The `parse*` functions and `resolveDims` stay.

In `StreamWorker.h`, replace the `InputDownload` struct with a surface-free equivalent:

```cpp
    // One source frame, already resident in CPU-addressable memory. The host is responsible for
    // keeping `pixels` valid until submitInputFrames() returns.
    struct InputFrame {
        bool           connected { false };
        int            width     { 0 };
        int            height    { 0 };
        const uint8_t* pixels    { nullptr };  // RGBA8, top-down, width*4 stride
    };

    void submitInputFrames(InputFrame inputs[kNumSources], InputFrame control);
```

Delete the `#include` of the TD headers and the `TD::OP_SmartRef` members in `SourceInbox`, replacing `pending` with an owned `std::vector<uint8_t> pending;` plus a `bool hasPending {false};`.

In `StreamWorker.cpp`, the two sites at approximately lines 1945 and 2097 that hold `TD::OP_SmartRef<TD::OP_TOPDownloadResult>` and call `getData()` become direct reads of the inbox's `pending` vector. Copy the incoming pixels into `pending` under the inbox mutex in `submitInputFrames`, and read from it on the worker.

- [ ] **Step 3: Write the CMake build**

Create `Engine/mosh/CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.20)
project(MoshEngine CXX C)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(FF "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffglitch-mac")
if(NOT EXISTS "${FF}/lib/libavcodec.a")
  message(FATAL_ERROR "Run Engine/build_ffglitch.sh first — ${FF}/lib/libavcodec.a is missing")
endif()

add_library(moshengine STATIC
  src/StreamWorker.cpp src/MoshOps.cpp src/MvFieldOps.cpp
  src/Parameters.cpp   src/FFEditJsonBridge.c)
target_include_directories(moshengine PUBLIC src "${FF}/include")
target_link_libraries(moshengine PUBLIC
  "${FF}/lib/libavcodec.a" "${FF}/lib/libswscale.a"
  "${FF}/lib/libswresample.a" "${FF}/lib/libavutil.a"
  x264 z bz2 iconv
  "-framework CoreFoundation" "-framework CoreVideo" "-framework CoreMedia"
  "-framework VideoToolbox" "-framework AudioToolbox" "-framework Security")
target_link_directories(moshengine PUBLIC /opt/homebrew/lib)

enable_testing()
foreach(t MoshOpsTests PixelRoutingTests MvFieldOpsTests CodecCorruptionProbe)
  add_executable(${t} tests/${t}.cpp)
  target_link_libraries(${t} PRIVATE moshengine)
  add_test(NAME MoshEngine_${t} COMMAND ${t})
endforeach()
```

- [ ] **Step 4: Build and run the vendored suite**

```bash
cmake -S Engine/mosh -B Engine/mosh/build -DCMAKE_BUILD_TYPE=Release
cmake --build Engine/mosh/build -j8 2>&1 | tail -20
ctest --test-dir Engine/mosh/build --output-on-failure 2>&1 | tail -20
```

Expected: all four test executables build and pass. `CodecCorruptionProbe` exercises every inter-frame codec and is the one that proves the ffglitch link is real.

If a test fails, the port broke the engine — fix the port, do not edit the test. These tests are the inherited regression asset and their value depends entirely on not being adjusted to fit.

- [ ] **Step 5: Record provenance**

Create `Engine/mosh/THIRD_PARTY.md`:

```markdown
# Vendored components

| Component | Source | Version / commit | License |
|---|---|---|---|
| mosh-top engine (`src/`, `tests/`) | github.com/ericsouther-source/mosh-top | tag `v1.3` | MIT — see `LICENSE-mosh-top`. © 2026 Eric Souther / Philosophical Tools. |
| ffglitch-core (patched libavcodec) | github.com/ramiropolla/ffglitch-core | `4b71d60c6640ad3f9ce483eac14391dc73f8c950`, branch `ffedit-0.10` | ffedit sources LGPL-2.1-or-later; built here with `--enable-gpl`, so the archives are GPL-2.0-or-later. |
| libx264 | Homebrew `x264` | whatever `brew` provides | GPL-2.0-or-later |

Nothing here is distributed — ARShader is a personal instrument (spec §11). This ledger exists so
that a future decision to release is a document to read rather than an investigation to run. That
decision needs real legal review; this file is not it.

Modifications to the vendored mosh-top sources: the TouchDesigner plugin shim
(`MoshTOP.cpp/.h`) and the Windows-only `MinGWStubs.cpp` were removed; `Parameters`
lost its `OP_ParameterManager` / `OP_Inputs` entry points; `StreamWorker`'s input type
changed from `OP_TOPDownloadResult` to a plain RGBA8 pointer.
```

- [ ] **Step 6: Commit**

```bash
git add Engine/mosh
git commit -m "engine: vendor mosh-top, strip the TD shim, 4/4 ctest green"
```

---

## Task 4: The engine facade and headless harness

Replaces the deleted TD shim with a host-independent facade, then proves the engine works with no host at all.

**Files:**
- Create: `Engine/mosh/src/MoshEngine.h`
- Create: `Engine/mosh/src/MoshEngine.cpp`
- Create: `Engine/mosh/tools/moshcli.cpp`
- Create: `Engine/mosh/tests/MoshEngineTests.cpp`
- Modify: `Engine/mosh/CMakeLists.txt`

**Interfaces:**
- Consumes: `MoshNS::StreamWorker`, `MoshNS::Parameters` from Task 3.
- Produces: `MoshNS::MoshEngine` with `MoshEngine(int width, int height)`, `void setParameters(const Parameters&)`, `void submit(const uint8_t* rgba, int w, int h)`, `bool takeLatest(uint8_t* outRgba, int w, int h)`, `void reset()`. Task 11 (phase 2) calls exactly these.

- [ ] **Step 1: Write the failing test**

Create `Engine/mosh/tests/MoshEngineTests.cpp`:

```cpp
// Engine facade: RGBA8 in, RGBA8 out, no host of any kind.
#include "MoshEngine.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>

using namespace MoshNS;

static void fillGradient(std::vector<uint8_t>& buf, int w, int h, int shift)
{
    buf.assign((size_t)w * h * 4, 0);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            uint8_t* p = &buf[((size_t)y * w + x) * 4];
            p[0] = (uint8_t)((x + shift) & 0xFF);
            p[1] = (uint8_t)((y + shift) & 0xFF);
            p[2] = 0x40; p[3] = 0xFF;
        }
}

// Pushes frames until the engine yields one, or gives up. The engine is asynchronous by design:
// there is NO frame-accurate correspondence between submit and takeLatest (spec §6).
static bool pumpUntilFrame(MoshEngine& e, int w, int h, std::vector<uint8_t>& out, int maxTries)
{
    std::vector<uint8_t> in;
    for (int i = 0; i < maxTries; ++i) {
        fillGradient(in, w, h, i * 3);
        e.submit(in.data(), w, h);
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        if (e.takeLatest(out.data(), w, h)) return true;
    }
    return false;
}

int main()
{
    const int W = 320, H = 240;
    std::vector<uint8_t> out((size_t)W * H * 4, 0);

    // 1. Clean pass: the engine produces a frame.
    {
        MoshEngine e(W, H);
        Parameters p;
        p.active = true;
        p.mode = MoshMode::None;
        p.codec = MoshCodec::Mpeg4;
        e.setParameters(p);
        assert(pumpUntilFrame(e, W, H, out, 200) && "engine must produce a frame in clean mode");
        bool nonBlack = false;
        for (size_t i = 0; i < out.size(); i += 4)
            if (out[i] || out[i + 1] || out[i + 2]) { nonBlack = true; break; }
        assert(nonBlack && "clean output must not be black");
        printf("OK: clean pass produced a non-black frame\n");
    }

    // 2. Mosh pass: P-frame duplication also produces frames, and does not wedge.
    {
        MoshEngine e(W, H);
        Parameters p;
        p.active = true;
        p.mode = MoshMode::PFrameDuplicate;
        p.codec = MoshCodec::Mpeg4;
        p.intensity = 1.0;
        p.dupProb = 1.0;
        p.dupCount = 3;
        e.setParameters(p);
        assert(pumpUntilFrame(e, W, H, out, 200) && "engine must produce a frame while moshing");
        printf("OK: mosh pass produced a frame\n");
    }

    // 3. Reset is accepted and the engine keeps producing afterwards.
    {
        MoshEngine e(W, H);
        Parameters p;
        p.active = true;
        p.mode = MoshMode::PFrameDuplicate;
        p.codec = MoshCodec::Mpeg2;
        e.setParameters(p);
        assert(pumpUntilFrame(e, W, H, out, 200));
        e.reset();
        assert(pumpUntilFrame(e, W, H, out, 200) && "engine must recover after reset");
        printf("OK: reset recovers\n");
    }

    printf("MoshEngineTests: all passed\n");
    return 0;
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cmake --build Engine/mosh/build -j8 2>&1 | tail -10
```

Expected: FAIL — `MoshEngine.h` does not exist.

- [ ] **Step 3: Write the facade header**

Create `Engine/mosh/src/MoshEngine.h`:

```cpp
// Host-independent facade over StreamWorker. This is what replaces MoshTOP.cpp: it owns the
// worker, forwards parameters, accepts RGBA8 frames, and hands back the newest decoded frame.
//
// Asynchronous by contract. submit() and takeLatest() are NOT paired: the caller publishes when
// it has a frame and polls when it wants one, and output frame N does not correspond to input
// frame N. See the design spec, section 6.
#pragma once

#include "Parameters.h"
#include "StreamWorker.h"

#include <cstdint>
#include <memory>
#include <string>

namespace MoshNS {

class MoshEngine {
public:
    MoshEngine(int width, int height);
    ~MoshEngine();

    MoshEngine(const MoshEngine&)            = delete;
    MoshEngine& operator=(const MoshEngine&) = delete;

    // Forwarded to the worker on the next submit. Cheap; safe to call every frame.
    void setParameters(const Parameters& p);

    // Publish one source frame. `rgba` is width*height*4 bytes, top-down, and need only stay
    // valid for the duration of the call.
    void submit(const uint8_t* rgba, int width, int height);

    // Copy the newest decoded frame into `outRgba` (width*height*4, top-down).
    // Returns false when nothing new has been decoded since the last call — in which case the
    // CALLER decides what to show. It must not show its input; see spec section 4.1.
    bool takeLatest(uint8_t* outRgba, int width, int height);

    // Force a clean keyframe and resync the decoder ("snap back").
    void reset();

    std::string lastError() const;
    int64_t decodedFrames() const;

private:
    int  myWidth  { 0 };
    int  myHeight { 0 };
    bool myPendingReset { false };
    Parameters myParams;
    std::unique_ptr<StreamWorker> myWorker;
};

} // namespace MoshNS
```

- [ ] **Step 4: Write the facade implementation**

Create `Engine/mosh/src/MoshEngine.cpp`:

```cpp
#include "MoshEngine.h"

#include <algorithm>
#include <cstring>

namespace MoshNS {

MoshEngine::MoshEngine(int width, int height)
    : myWidth(width), myHeight(height), myWorker(std::make_unique<StreamWorker>())
{
}

MoshEngine::~MoshEngine() = default;

void MoshEngine::setParameters(const Parameters& p) { myParams = p; }

void MoshEngine::reset() { myPendingReset = true; }

void MoshEngine::submit(const uint8_t* rgba, int width, int height)
{
    if (!rgba || width <= 0 || height <= 0) return;

    // forceReopen carries the reset request; the worker rebuilds and primes a fresh keyframe.
    myWorker->updateControl(myParams, myPendingReset, 0, 0);
    myPendingReset = false;

    StreamWorker::InputFrame inputs[StreamWorker::kNumSources];
    inputs[0].connected = true;
    inputs[0].width  = width;
    inputs[0].height = height;
    inputs[0].pixels = rgba;
    // Slot 2 and the control slot are unwired until phase 4 routes them through SourceRouter.
    inputs[1] = StreamWorker::InputFrame{};
    StreamWorker::InputFrame control{};

    myWorker->submitInputFrames(inputs, control);
}

bool MoshEngine::takeLatest(uint8_t* outRgba, int width, int height)
{
    if (!outRgba || width <= 0 || height <= 0) return false;

    std::unique_ptr<RgbaFrame> frame = myWorker->takeLatestFrame();
    if (!frame) return false;

    const bool usable = frame->width == width && frame->height == height
                     && frame->data.size() >= (size_t)width * height * 4u;
    if (usable)
        std::memcpy(outRgba, frame->data.data(), (size_t)width * height * 4u);

    myWorker->recycleFrame(std::move(frame));
    return usable;
}

std::string MoshEngine::lastError() const  { return myWorker->lastError(); }
int64_t MoshEngine::decodedFrames() const  { return myWorker->decodedFrames(); }

} // namespace MoshNS
```

- [ ] **Step 5: Add the facade and its test to CMake**

In `Engine/mosh/CMakeLists.txt`, add `src/MoshEngine.cpp` to the `moshengine` source list, and add `MoshEngineTests` to the `foreach` list of test names.

- [ ] **Step 6: Build and run**

```bash
cmake --build Engine/mosh/build -j8 2>&1 | tail -10
ctest --test-dir Engine/mosh/build --output-on-failure 2>&1 | tail -20
```

Expected: 5 tests, all pass, including three `OK:` lines from `MoshEngineTests`.

- [ ] **Step 7: Write the headless harness**

Create `Engine/mosh/tools/moshcli.cpp`:

```cpp
// Headless proof that the engine runs with no host: reads raw RGBA8 frames from stdin, writes
// moshed RGBA8 frames to stdout. Deliberately dumb about containers — piping through ffmpeg is
// the point, because it keeps the engine's I/O surface to "a pointer to pixels".
//
//   ffmpeg -i in.mp4 -f rawvideo -pix_fmt rgba -s 640x480 - \
//     | ./moshcli 640 480 mpeg4 pdup \
//     | ffmpeg -f rawvideo -pix_fmt rgba -s 640x480 -i - out.mp4
#include "MoshEngine.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

using namespace MoshNS;

int main(int argc, char** argv)
{
    if (argc < 5) {
        fprintf(stderr, "usage: moshcli WIDTH HEIGHT CODEC MODE\n"
                        "  CODEC: mpeg1 mpeg2 mpeg4 wmv1 wmv2 flv1 msmpeg4v3 snow mjpeg\n"
                        "  MODE:  none idrop pdup bitflip mv\n");
        return 2;
    }
    const int W = atoi(argv[1]);
    const int H = atoi(argv[2]);
    if (W <= 0 || H <= 0) { fprintf(stderr, "bad dimensions\n"); return 2; }

    Parameters p;
    p.active    = true;
    p.codec     = parseCodec(argv[3]);
    p.mode      = parseMode(argv[4]);
    p.intensity = 1.0;
    p.dupProb   = 1.0;
    p.dupCount  = 2;

    MoshEngine engine(W, H);
    engine.setParameters(p);

    const size_t frameBytes = (size_t)W * H * 4u;
    std::vector<uint8_t> in(frameBytes), out(frameBytes, 0);
    int64_t read = 0, written = 0;

    while (fread(in.data(), 1, frameBytes, stdin) == frameBytes) {
        ++read;
        engine.submit(in.data(), W, H);
        // Give the worker a moment; it is a separate thread and this is a batch tool, so a
        // short wait is the honest way to let it keep up rather than dropping most frames.
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        if (engine.takeLatest(out.data(), W, H)) {
            fwrite(out.data(), 1, frameBytes, stdout);
            ++written;
        }
    }
    fflush(stdout);
    fprintf(stderr, "moshcli: read %lld frames, wrote %lld, decoded %lld%s\n",
            (long long)read, (long long)written, (long long)engine.decodedFrames(),
            engine.lastError().empty() ? "" : (" ERROR: " + engine.lastError()).c_str());
    return engine.lastError().empty() ? 0 : 1;
}
```

Add to `Engine/mosh/CMakeLists.txt`:

```cmake
add_executable(moshcli tools/moshcli.cpp)
target_link_libraries(moshcli PRIVATE moshengine)
```

- [ ] **Step 8: Prove it on real video**

```bash
cmake --build Engine/mosh/build -j8 2>&1 | tail -5
# Any handy clip; generate one if none is nearby:
ffmpeg -y -f lavfi -i testsrc2=size=640x480:rate=30 -t 5 /tmp/mosh_in.mp4
ffmpeg -v error -i /tmp/mosh_in.mp4 -f rawvideo -pix_fmt rgba -s 640x480 - \
  | ./Engine/mosh/build/moshcli 640 480 mpeg4 pdup \
  | ffmpeg -y -v error -f rawvideo -pix_fmt rgba -s 640x480 -r 30 -i - /tmp/mosh_out.mp4
open /tmp/mosh_out.mp4
```

Expected: `moshcli` reports frames read, written, and decoded with no error, and `/tmp/mosh_out.mp4` shows visible P-frame-duplication smear. **Watch it.** A file that exists is not the same as a file that moshed — this is the first point in the plan where the effect is visible, and it is the whole reason phase 0b exists.

- [ ] **Step 9: Commit**

```bash
git add Engine/mosh
git commit -m "engine: host-independent MoshEngine facade + headless moshcli harness"
```

---

## Task 5: Generalize FXStage behind a backing protocol

Behavior-preserving refactor. The existing suites are the proof.

**Files:**
- Create: `App/FXNodeKit/FXStageBacking.swift`
- Create: `App/FXNodeKit/ISFStageBacking.swift`
- Modify: `App/ARShader/FXStage.swift`
- Modify: `App/ARShader/FXChain.swift:6-10, 85-93, 116-138`
- Test: `App/ARShaderTests/FXChainTests.swift` (existing, must keep passing)

**Interfaces:**
- Consumes: `MetalRenderCore` (existing), `ShaderUnit` (existing).
- Produces: `protocol FXStageBacking: Sendable { func produce(input: MTLTexture, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? }`; `final class ISFStageBacking: FXStageBacking`; `FXStage.backing: any FXStageBacking`; `FXStageSnapshot.backing` replacing `FXStageSnapshot.core`.

- [ ] **Step 1: Write the failing test**

Append to `App/ARShaderTests/FXChainTests.swift`:

```swift
    func testAnISFStageExposesItsCoreThroughABacking() throws {
        let stage = try loadedStage("invert_filter")
        // The chain must reach pixels through the backing, not through a hardcoded ISF core.
        XCTAssertTrue(stage.backing is ISFStageBacking,
                      "an ISF stage must be backed by ISFStageBacking")
    }

    func testTheRenderMirrorCarriesBackingsNotCores() throws {
        let stage = try loadedStage("invert_filter")
        chain.append(stage)
        let published = chain.renderStages()
        XCTAssertEqual(published.count, 1)
        XCTAssertTrue(published[0].backing is ISFStageBacking)
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/FXChainTests 2>&1 | tail -20
```

Expected: FAIL — `stage.backing` and `ISFStageBacking` do not exist.

- [ ] **Step 3: Define the protocol**

Create `App/FXNodeKit/FXStageBacking.swift`:

```swift
import Metal

/// Where an FX stage's pixels come from.
///
/// The chain does not care whether a stage is an ISF shader compiled in-process or a node running
/// in another process — it asks for a texture and composites whatever it gets.
///
/// Returning `nil` means "this stage contributes nothing this frame", and `FXChain.encode` will
/// pass its input through untouched. That is correct for a stage that is bypassed or has never
/// produced anything. It is NOT correct as a response to being merely busy: for an accumulating
/// effect like datamosh, showing the clean input is visually identical to a reset. A backing that
/// can fall behind must hold its own last output and return that. See the design spec, §4.1.
protocol FXStageBacking: Sendable {
    func produce(input: MTLTexture, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture?
}
```

Create `App/FXNodeKit/ISFStageBacking.swift`:

```swift
import Metal

/// The ISF conformer: a thin pass-through to `MetalRenderCore.renderOffscreen`.
///
/// `MetalRenderCore` is `@unchecked Sendable` behind its own lock, which is what lets this be
/// handed to the render thread inside an `FXStageSnapshot`.
final class ISFStageBacking: FXStageBacking, @unchecked Sendable {
    let core: MetalRenderCore

    init(core: MetalRenderCore) { self.core = core }

    func produce(input: MTLTexture, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        core.renderOffscreen(size: size, in: cb, primaryInput: input)
    }
}
```

- [ ] **Step 4: Give FXStage a backing**

In `App/ARShader/FXStage.swift`, after the `unit` property (line 12), add:

```swift
    /// Where this stage's pixels come from. An ISF stage wraps its own unit's core; a native node
    /// stage supplies its own. Stored rather than computed so a stage's backing is fixed at
    /// construction and the render mirror can hold it without reaching back into `unit`.
    let backing: any FXStageBacking
```

and set it at the end of `init`:

```swift
        self.backing = ISFStageBacking(core: self.unit.core)
```

- [ ] **Step 5: Publish backings instead of cores**

In `App/ARShader/FXChain.swift`, change `FXStageSnapshot` (lines 6–10) to:

```swift
struct FXStageSnapshot: @unchecked Sendable {
    let backing: any FXStageBacking
    let mix: Double
    let blendMode: BlendMode
}
```

In `publishToRenderThread()` (line 88), change the map to:

```swift
            .map { FXStageSnapshot(backing: $0.backing, mix: $0.mix, blendMode: $0.blendMode) }
```

In `encode(input:scratch:renderSize:compositor:preserveAlpha:in:)` (line 128), change the guard to:

```swift
            guard let produced = stage.backing.produce(input: source, size: renderSize, in: cb) else {
                continue
            }
```

and update the surrounding doc comment: the `primaryInput: source` note now belongs to `ISFStageBacking`, and the `continue` branch means "the stage contributed nothing", not "the render failed".

- [ ] **Step 6: Run the FX tests**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/FXChainTests 2>&1 | tail -20
```

Expected: PASS, including the two new tests and every pre-existing one.

- [ ] **Step 7: Run BOTH full suites**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' 2>&1 | tail -15
xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' 2>&1 | tail -15
```

Expected: both green. This refactor is behavior-preserving by definition; these suites are the evidence, and a failure here means the refactor changed behavior.

- [ ] **Step 8: Commit**

```bash
git add App/FXNodeKit/FXStageBacking.swift App/FXNodeKit/ISFStageBacking.swift \
        App/ARShader/FXStage.swift App/ARShader/FXChain.swift \
        App/ARShaderTests/FXChainTests.swift
git commit -m "refactor(fx): generalize FXStage behind FXStageBacking"
```

---

## Task 6: The surface ring

**Files:**
- Create: `App/FXNodeKit/SurfaceRing.swift`
- Test: `App/ARShaderTests/SurfaceRingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `final class SurfaceRing` with `init?(device: MTLDevice, width: Int, height: Int, depth: Int)`, `var surfaces: [IOSurface]`, `func nextWritableSlot() -> Int?`, `func texture(at: Int) -> MTLTexture`, `func markReady(_ slot: Int)`, `func takeNewestReady() -> Int?`, `func release(_ slot: Int)`. Task 8 drives all of these.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/SurfaceRingTests.swift`:

```swift
import XCTest
import Metal
@testable import ARShader

final class SurfaceRingTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func makeRing(depth: Int = 3) throws -> SurfaceRing {
        try XCTUnwrap(SurfaceRing(device: device, width: 64, height: 64, depth: depth))
    }

    func testItAllocatesOneSurfaceAndTexturePerSlot() throws {
        let ring = try makeRing(depth: 3)
        XCTAssertEqual(ring.surfaces.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(ring.texture(at: i).width, 64)
            XCTAssertEqual(ring.texture(at: i).height, 64)
        }
    }

    func testEachWritableSlotIsHandedOutOnlyOnce() throws {
        let ring = try makeRing(depth: 3)
        let a = try XCTUnwrap(ring.nextWritableSlot())
        let b = try XCTUnwrap(ring.nextWritableSlot())
        let c = try XCTUnwrap(ring.nextWritableSlot())
        XCTAssertEqual(Set([a, b, c]).count, 3, "slots must not be handed out twice")
    }

    func testAFullRingDropsTheOldestRatherThanBlocking() throws {
        let ring = try makeRing(depth: 2)
        let a = try XCTUnwrap(ring.nextWritableSlot())
        ring.markReady(a)
        let b = try XCTUnwrap(ring.nextWritableSlot())
        ring.markReady(b)
        // Both slots hold unconsumed frames. Publishing again must recycle the OLDER one.
        let c = try XCTUnwrap(ring.nextWritableSlot(), "a full ring must drop, never block")
        XCTAssertEqual(c, a, "the oldest unconsumed slot is the one reused")
    }

    func testTakeNewestReadyReturnsTheMostRecentAndConsumesIt() throws {
        let ring = try makeRing(depth: 3)
        let a = try XCTUnwrap(ring.nextWritableSlot()); ring.markReady(a)
        let b = try XCTUnwrap(ring.nextWritableSlot()); ring.markReady(b)
        XCTAssertEqual(ring.takeNewestReady(), b, "newest wins — this is a latest-frame mailbox")
        XCTAssertNil(ring.takeNewestReady(), "nothing new since the last take")
    }

    func testAnEmptyRingHasNothingReady() throws {
        let ring = try makeRing()
        XCTAssertNil(ring.takeNewestReady())
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/SurfaceRingTests 2>&1 | tail -20
```

Expected: FAIL — `SurfaceRing` is undefined.

- [ ] **Step 3: Implement the ring**

Create `App/FXNodeKit/SurfaceRing.swift`:

```swift
import Foundation
import IOSurface
import Metal

/// A fixed-size ring of IOSurface-backed textures shared with a node process.
///
/// Drop-on-contention by design: when every slot holds an unconsumed frame, publishing recycles
/// the OLDEST rather than blocking or growing. That bounds memory by construction and matches the
/// engine's own inbox philosophy — a live instrument would rather lose a stale frame than stall
/// the render thread.
///
/// The surfaces are allocated once and handed to the service at connection setup, so per-frame IPC
/// carries a slot index rather than pixels.
final class SurfaceRing: @unchecked Sendable {

    let surfaces: [IOSurface]
    private let textures: [MTLTexture]
    private let lock = NSLock()

    /// Monotonic publish sequence per slot. 0 = never published.
    private var sequence: [UInt64]
    /// True while a slot holds a frame the consumer has not taken.
    private var ready: [Bool]
    private var nextSequence: UInt64 = 1

    init?(device: MTLDevice, width: Int, height: Int, depth: Int) {
        guard width > 0, height > 0, depth > 0 else { return nil }

        var builtSurfaces: [IOSurface] = []
        var builtTextures: [MTLTexture] = []
        builtSurfaces.reserveCapacity(depth)
        builtTextures.reserveCapacity(depth)

        let bytesPerRow = width * 4
        let props: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .allocSize: bytesPerRow * height,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .shared

        for _ in 0..<depth {
            guard let surface = IOSurface(properties: props),
                  let texture = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)
            else { return nil }
            builtSurfaces.append(surface)
            builtTextures.append(texture)
        }

        self.surfaces = builtSurfaces
        self.textures = builtTextures
        self.sequence = Array(repeating: 0, count: depth)
        self.ready    = Array(repeating: false, count: depth)
    }

    var depth: Int { surfaces.count }

    func texture(at slot: Int) -> MTLTexture { textures[slot] }

    /// Claims a slot to write into. Prefers a slot nobody is waiting on; falls back to the oldest
    /// unconsumed one. Never returns nil for a ring of depth >= 1.
    func nextWritableSlot() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard !surfaces.isEmpty else { return nil }

        if let free = ready.firstIndex(of: false) {
            sequence[free] = nextSequence; nextSequence += 1
            return free
        }
        // Full: recycle the oldest unconsumed frame.
        var oldest = 0
        for i in ready.indices where sequence[i] < sequence[oldest] { oldest = i }
        ready[oldest] = false
        sequence[oldest] = nextSequence; nextSequence += 1
        return oldest
    }

    func markReady(_ slot: Int) {
        lock.lock(); defer { lock.unlock() }
        guard surfaces.indices.contains(slot) else { return }
        ready[slot] = true
    }

    /// The newest unconsumed slot, consumed. Nil when nothing has been published since the last
    /// call. Older ready slots are dropped — this is a latest-frame mailbox, not a queue.
    func takeNewestReady() -> Int? {
        lock.lock(); defer { lock.unlock() }
        var best: Int? = nil
        for i in ready.indices where ready[i] {
            if best == nil || sequence[i] > sequence[best!] { best = i }
        }
        guard let winner = best else { return nil }
        for i in ready.indices where ready[i] { ready[i] = false }
        return winner
    }

    func release(_ slot: Int) {
        lock.lock(); defer { lock.unlock() }
        guard surfaces.indices.contains(slot) else { return }
        ready[slot] = false
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/SurfaceRingTests 2>&1 | tail -20
```

Expected: PASS, all six tests.

- [ ] **Step 5: Commit**

```bash
git add App/FXNodeKit/SurfaceRing.swift App/ARShaderTests/SurfaceRingTests.swift
git commit -m "feat(node): IOSurface ring with drop-on-contention publish"
```

---

## Task 7: The frame protocol and a real service loop

Replaces the spike's `acceptSurface` with the actual frame contract, and makes the service invert.

**Files:**
- Modify: `App/FXNodeKit/NodeProtocol.swift`
- Modify: `App/MoshNode/NodeService.swift`
- Test: `App/ARShaderTests/NodeConnectionTests.swift`

**Interfaces:**
- Consumes: `SurfaceRing` (Task 6), `NodeCapabilities` (Task 1).
- Produces: `NodeProtocol` gains `attachSurfaces(input:output:width:height:reply:)` and `processSlot(_:params:reply:)`. `NodeParams` — a `Codable` struct carrying `bypass: Bool` and `invert: Bool` in phase 1, extended in phase 2.

- [ ] **Step 1: Write the failing test**

Append to `App/ARShaderTests/NodeConnectionTests.swift`:

```swift
    func testTheServiceInvertsAPublishedFrameIntoTheOutputRing() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let inRing  = try XCTUnwrap(SurfaceRing(device: device, width: 8, height: 8, depth: 2))
        let outRing = try XCTUnwrap(SurfaceRing(device: device, width: 8, height: 8, depth: 2))

        let connection = makeConnection()
        defer { connection.invalidate() }
        let proxy = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC error: \(error)")
        } as? NodeProtocol)

        let attached = expectation(description: "surfaces attached")
        proxy.attachSurfaces(input: inRing.surfaces, output: outRing.surfaces,
                             width: 8, height: 8) { ok in
            XCTAssertTrue(ok); attached.fulfill()
        }
        wait(for: [attached], timeout: 10)

        // Write a known value into input slot 0: mid-grey, opaque.
        let slot = try XCTUnwrap(inRing.nextWritableSlot())
        let surface = inRing.surfaces[slot]
        surface.lock(options: [], seed: nil)
        let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(8 * 8 * 4) { base[i] = (i % 4 == 3) ? 0xFF : 0x40 }
        surface.unlock(options: [], seed: nil)

        let processed = expectation(description: "frame processed")
        var producedSlot = -1
        let params = try JSONEncoder().encode(NodeParams(bypass: false, invert: true))
        proxy.processSlot(slot, params: params) { out in
            producedSlot = out; processed.fulfill()
        }
        wait(for: [processed], timeout: 10)

        XCTAssertGreaterThanOrEqual(producedSlot, 0, "service must report an output slot")
        let outSurface = outRing.surfaces[producedSlot]
        outSurface.lock(options: .readOnly, seed: nil)
        let outBase = outSurface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let b = outBase[0], g = outBase[1], r = outBase[2], a = outBase[3]
        outSurface.unlock(options: .readOnly, seed: nil)

        XCTAssertEqual(b, 0xBF, "0x40 inverted is 0xBF")
        XCTAssertEqual(g, 0xBF)
        XCTAssertEqual(r, 0xBF)
        XCTAssertEqual(a, 0xFF, "alpha must be preserved, not inverted")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NodeConnectionTests 2>&1 | tail -20
```

Expected: FAIL — `attachSurfaces`, `processSlot`, and `NodeParams` are undefined.

- [ ] **Step 3: Extend the protocol**

In `App/FXNodeKit/NodeProtocol.swift`, add above the protocol:

```swift
/// Everything the service needs per frame. JSON-encoded so the shape can grow without touching
/// the ObjC protocol. Phase 2 replaces these two fields with the full parameter snapshot.
struct NodeParams: Codable, Sendable {
    var bypass: Bool = false
    var invert: Bool = true
}
```

and inside the protocol, replace `acceptSurface` with:

```swift
    /// Hands the service both rings, once, at connection setup. After this the per-frame messages
    /// carry only a slot index — never pixels.
    func attachSurfaces(input: [IOSurface],
                        output: [IOSurface],
                        width: Int,
                        height: Int,
                        reply: @escaping (Bool) -> Void)

    /// Processes input slot `slot` and replies with the output slot it wrote, or -1 on failure.
    /// `params` is a JSON-encoded `NodeParams`.
    func processSlot(_ slot: Int, params: Data, reply: @escaping (Int) -> Void)
```

Because the protocol now passes an array of a non-property-list class, the interface must whitelist it. In `NodeConnection` (Task 8) and in the test's `makeConnection()`, configure the interface after creating it:

```swift
let iface = NSXPCInterface(with: NodeProtocol.self)
let classes = NSSet(array: [NSArray.self, IOSurface.self]) as! Set<AnyHashable>
iface.setClasses(classes,
                 for: #selector(NodeProtocol.attachSurfaces(input:output:width:height:reply:)),
                 argumentIndex: 0, ofReply: false)
iface.setClasses(classes,
                 for: #selector(NodeProtocol.attachSurfaces(input:output:width:height:reply:)),
                 argumentIndex: 1, ofReply: false)
c.remoteObjectInterface = iface
```

Apply the same two `setClasses` calls on the service side in `ServiceDelegate.listener(_:shouldAcceptNewConnection:)` for `exportedInterface`.

- [ ] **Step 4: Implement the service loop**

Replace the body of `App/MoshNode/NodeService.swift`'s `NodeService` class (keeping `probeCapabilities` as-is, deleting `acceptSurface`):

```swift
    private var inputSurfaces: [IOSurface] = []
    private var outputSurfaces: [IOSurface] = []
    private var width = 0
    private var height = 0
    private var nextOutputSlot = 0

    func attachSurfaces(input: [IOSurface], output: [IOSurface],
                        width: Int, height: Int, reply: @escaping (Bool) -> Void) {
        guard !input.isEmpty, !output.isEmpty, width > 0, height > 0 else {
            reply(false); return
        }
        self.inputSurfaces  = input
        self.outputSurfaces = output
        self.width  = width
        self.height = height
        self.nextOutputSlot = 0
        reply(true)
    }

    func processSlot(_ slot: Int, params: Data, reply: @escaping (Int) -> Void) {
        guard inputSurfaces.indices.contains(slot), !outputSurfaces.isEmpty else {
            reply(-1); return
        }
        let p = (try? JSONDecoder().decode(NodeParams.self, from: params)) ?? NodeParams()

        let outSlot = nextOutputSlot
        nextOutputSlot = (nextOutputSlot + 1) % outputSurfaces.count

        let src = inputSurfaces[slot]
        let dst = outputSurfaces[outSlot]

        src.lock(options: .readOnly, seed: nil)
        dst.lock(options: [], seed: nil)
        defer {
            dst.unlock(options: [], seed: nil)
            src.unlock(options: .readOnly, seed: nil)
        }

        let count = min(src.allocationSize, dst.allocationSize)
        let s = src.baseAddress.assumingMemoryBound(to: UInt8.self)
        let d = dst.baseAddress.assumingMemoryBound(to: UInt8.self)

        if p.bypass || !p.invert {
            memcpy(d, s, count)
        } else {
            // BGRA: invert colour, preserve alpha. Phase 2 replaces this with MoshEngine.
            var i = 0
            while i + 3 < count {
                d[i]     = 255 &- s[i]
                d[i + 1] = 255 &- s[i + 1]
                d[i + 2] = 255 &- s[i + 2]
                d[i + 3] = s[i + 3]
                i += 4
            }
        }
        reply(outSlot)
    }
```

Update the spike test from Task 1 (`testServiceWritesThroughASharedSurface`) — `acceptSurface` no longer exists. Delete that test; `testTheServiceInvertsAPublishedFrameIntoTheOutputRing` supersedes it and proves the same property against the real contract. Keep `testServiceReportsItsGPUAndSurfaceCapabilities`.

- [ ] **Step 5: Run to verify it passes**

```bash
cd App && xcodegen generate
xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NodeConnectionTests 2>&1 | tail -20
```

Expected: PASS, both remaining tests.

- [ ] **Step 6: Commit**

```bash
git add App/FXNodeKit/NodeProtocol.swift App/MoshNode/NodeService.swift \
        App/ARShaderTests/NodeConnectionTests.swift
git commit -m "feat(node): real frame protocol — attach rings once, publish slots per frame"
```

---

## Task 8: NativeNodeBacking — publish, poll, hold last output

**Files:**
- Create: `App/FXNodeKit/NodeConnection.swift`
- Create: `App/FXNodeKit/NativeNodeBacking.swift`
- Test: `App/ARShaderTests/NativeNodeBackingTests.swift`

**Interfaces:**
- Consumes: `SurfaceRing`, `NodeProtocol`, `NodeParams`, `FXStageBacking`.
- Produces: `final class NodeConnection` with `init(serviceName: String, device: MTLDevice, width: Int, height: Int, ringDepth: Int)`, `func send(slot: Int, params: NodeParams)`, `var onOutputReady: ((Int) -> Void)?`, `var isFaulted: Bool`, `var isDisabled: Bool`, `var restartCount: Int`, `func invalidate()`. `final class NativeNodeBacking: FXStageBacking` with `var bypass: Bool` and `var lastOutput: MTLTexture?`.

- [ ] **Step 1: Write the failing test**

Create `App/ARShaderTests/NativeNodeBackingTests.swift`:

```swift
import XCTest
import Metal
@testable import ARShader

@MainActor
final class NativeNodeBackingTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func makeInput() throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    private func makeBacking() throws -> NativeNodeBacking {
        try XCTUnwrap(NativeNodeBacking(serviceName: "com.arsonrivvers.ARShader.MoshNode",
                                        device: device, width: 8, height: 8, ringDepth: 3))
    }

    func testItReturnsNilBeforeAnyFrameHasEverBeenDecoded() throws {
        let backing = try makeBacking()
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let out = backing.produce(input: try makeInput(),
                                  size: MTLSize(width: 8, height: 8, depth: 1), in: cb)
        XCTAssertNil(out, "nothing has been decoded yet — the chain must pass through")
    }

    func testItHoldsItsLastOutputRatherThanReturningTheInput() throws {
        let backing = try makeBacking()
        let input = try makeInput()
        let size = MTLSize(width: 8, height: 8, depth: 1)

        // Pump until the service has produced at least one frame.
        var produced: MTLTexture?
        for _ in 0..<60 {
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            produced = backing.produce(input: input, size: size, in: cb)
            cb.commit(); cb.waitUntilCompleted()
            if produced != nil { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let first = try XCTUnwrap(produced, "the node must eventually produce a frame")

        // Now starve it: ask again immediately, before anything new can arrive.
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let second = backing.produce(input: input, size: size, in: cb)
        let held = try XCTUnwrap(second, "starvation must NOT return nil once output exists")
        XCTAssertTrue(held === first || held.width == first.width,
                      "it must hold its own last output, never hand back the input")
        XCTAssertFalse(held === input, "returning the input is a visual reset — forbidden")
    }

    func testBypassReturnsNilSoTheChainPassesThrough() throws {
        let backing = try makeBacking()
        backing.bypass = true
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(backing.produce(input: try makeInput(),
                                     size: MTLSize(width: 8, height: 8, depth: 1), in: cb),
                     "bypass is the one deliberate pass-through")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NativeNodeBackingTests 2>&1 | tail -20
```

Expected: FAIL — `NativeNodeBacking` is undefined.

- [ ] **Step 3: Write the connection**

Create `App/FXNodeKit/NodeConnection.swift`:

```swift
import Foundation
import IOSurface
import Metal
import os

/// Owns the XPC connection to one node process, including its rings and its recovery policy.
///
/// Recovery is the reason this is a class rather than a few free functions: a codec fed corrupted
/// bitstreams WILL eventually crash, and the instrument has to survive that without the operator
/// noticing anything worse than a held frame.
final class NodeConnection: @unchecked Sendable {

    /// Beyond this many restarts inside `restartWindow`, the node disables itself. A crash loop
    /// must never degrade into an invisible strobe diagnosed under stage lighting.
    private static let maxRestarts = 5
    private static let restartWindow: TimeInterval = 30

    let inputRing: SurfaceRing
    let outputRing: SurfaceRing

    private let serviceName: String
    private let device: MTLDevice
    private let width: Int
    private let height: Int

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var attached = false
    private var restartTimes: [Date] = []
    private var backoff: TimeInterval = 0.25

    private(set) var isDisabled = false
    private(set) var restartCount = 0

    /// Fired on the XPC reply queue when the service reports a finished output slot.
    var onOutputReady: ((Int) -> Void)?

    init?(serviceName: String, device: MTLDevice, width: Int, height: Int, ringDepth: Int) {
        guard let inRing = SurfaceRing(device: device, width: width, height: height, depth: ringDepth),
              let outRing = SurfaceRing(device: device, width: width, height: height, depth: ringDepth)
        else { return nil }
        self.serviceName = serviceName
        self.device = device
        self.width = width
        self.height = height
        self.inputRing = inRing
        self.outputRing = outRing
        connect()
    }

    static func makeInterface() -> NSXPCInterface {
        let iface = NSXPCInterface(with: NodeProtocol.self)
        let classes = NSSet(array: [NSArray.self, IOSurface.self]) as! Set<AnyHashable>
        let sel = #selector(NodeProtocol.attachSurfaces(input:output:width:height:reply:))
        iface.setClasses(classes, for: sel, argumentIndex: 0, ofReply: false)
        iface.setClasses(classes, for: sel, argumentIndex: 1, ofReply: false)
        return iface
    }

    private func connect() {
        lock.lock()
        guard !isDisabled else { lock.unlock(); return }
        let c = NSXPCConnection(serviceName: serviceName)
        c.remoteObjectInterface = Self.makeInterface()
        c.invalidationHandler = { [weak self] in self?.handleDeath() }
        c.interruptionHandler = { [weak self] in self?.handleDeath() }
        c.resume()
        connection = c
        attached = false
        lock.unlock()

        guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in }) as? NodeProtocol else { return }
        proxy.attachSurfaces(input: inputRing.surfaces, output: outputRing.surfaces,
                             width: width, height: height) { [weak self] ok in
            guard let self else { return }
            self.lock.lock(); self.attached = ok; self.lock.unlock()
        }
    }

    /// The child died. Its decoder reference state died with it, so a restarted child necessarily
    /// begins from a fresh IDR — successful isolation still renders as a reset. The BACKING covers
    /// the relaunch window by holding its last texture; nothing can make the first recovered frame
    /// anything other than clean. See design spec §9.
    private func handleDeath() {
        lock.lock()
        connection = nil
        attached = false
        restartCount += 1

        let now = Date()
        restartTimes.append(now)
        restartTimes.removeAll { now.timeIntervalSince($0) > Self.restartWindow }
        if restartTimes.count > Self.maxRestarts {
            isDisabled = true
            lock.unlock()
            return
        }
        let delay = backoff
        backoff = min(backoff * 2, 5.0)
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    var isFaulted: Bool {
        lock.lock(); defer { lock.unlock() }
        return connection == nil || !attached
    }

    func send(slot: Int, params: NodeParams) {
        lock.lock()
        let c = connection
        let ready = attached && !isDisabled
        lock.unlock()
        guard ready, let c,
              let proxy = c.remoteObjectProxyWithErrorHandler({ _ in }) as? NodeProtocol,
              let data = try? JSONEncoder().encode(params)
        else { return }

        proxy.processSlot(slot, params: data) { [weak self] out in
            guard let self, out >= 0 else { return }
            self.outputRing.markReady(out)
            self.onOutputReady?(out)
        }
    }

    func invalidate() {
        lock.lock()
        let c = connection
        connection = nil
        isDisabled = true
        lock.unlock()
        c?.invalidationHandler = nil
        c?.interruptionHandler = nil
        c?.invalidate()
    }

    deinit { invalidate() }
}
```

- [ ] **Step 4: Write the backing**

Create `App/FXNodeKit/NativeNodeBacking.swift`:

```swift
import Foundation
import Metal

/// An FX stage backed by a node running in another process.
///
/// The starvation rule lives here, and it is the whole reason this class exists rather than the
/// chain simply calling the connection. Datamosh accumulates inside the decoder's reference
/// buffer, so showing the clean input while the encoder is busy is visually identical to a reset —
/// the loudest gesture the effect has — fired several times a second at an unpredictable cadence.
/// This backing therefore ABSORBS starvation and returns its own last output.
///
/// It returns nil in exactly three cases: before the first decoded frame has ever arrived, while
/// bypassed, and while disabled after a crash loop. In those cases `FXChain.encode` passes the
/// input through, which is correct.
final class NativeNodeBacking: FXStageBacking, @unchecked Sendable {

    private let connection: NodeConnection
    private let copyPass: TextureCopyPass?
    private let lock = NSLock()
    private var held: MTLTexture?

    /// The one deliberate pass-through. A gesture, never a consequence of the encoder being busy.
    var bypass: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _bypass }
        set { lock.lock(); _bypass = newValue; lock.unlock() }
    }
    private var _bypass = false

    /// Read on the render thread, written from the UI — lock-guarded for the same reason
    /// `FXChain` mirrors its stages rather than letting the render thread read `@Published`.
    var params: NodeParams {
        get { lock.lock(); defer { lock.unlock() }; return _params }
        set { lock.lock(); _params = newValue; lock.unlock() }
    }
    private var _params = NodeParams()

    var isDisabled: Bool { connection.isDisabled }
    var restartCount: Int { connection.restartCount }

    init?(serviceName: String, device: MTLDevice, width: Int, height: Int, ringDepth: Int = 3) {
        guard let c = NodeConnection(serviceName: serviceName, device: device,
                                     width: width, height: height, ringDepth: ringDepth)
        else { return nil }
        self.connection = c
        // .bgra8Unorm matches the ring's surfaces; TextureCopyPass requires the destination
        // format up front so it can build its pipeline once rather than per frame.
        self.copyPass = TextureCopyPass(device: device, destinationFormat: .bgra8Unorm)
    }

    func produce(input: MTLTexture, size: MTLSize, in cb: MTLCommandBuffer) -> MTLTexture? {
        if bypass || connection.isDisabled { return nil }

        // Publish: blit this frame into the input ring inside the caller's command buffer, then
        // tell the service about it once the GPU has actually written it.
        if let slot = connection.inputRing.nextWritableSlot(), let copyPass {
            copyPass.encode(from: input, to: connection.inputRing.texture(at: slot), in: cb)
            let p = params
            cb.addCompletedHandler { [weak self] _ in
                self?.connection.send(slot: slot, params: p)
            }
        }

        // Poll: take the newest decoded frame if one arrived.
        if let ready = connection.outputRing.takeNewestReady() {
            let texture = connection.outputRing.texture(at: ready)
            lock.lock(); held = texture; lock.unlock()
            return texture
        }

        // Starved. Hold, never pass through.
        lock.lock(); defer { lock.unlock() }
        return held
    }

    func invalidate() { connection.invalidate() }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NativeNodeBackingTests 2>&1 | tail -20
```

Expected: PASS, all three tests.

- [ ] **Step 6: Commit**

```bash
git add App/FXNodeKit/NodeConnection.swift App/FXNodeKit/NativeNodeBacking.swift \
        App/ARShaderTests/NativeNodeBackingTests.swift
git commit -m "feat(node): NativeNodeBacking holds its last output rather than passing through"
```

---

## Task 9: Prove crash recovery

The failure model is the reason for the whole architecture. It gets a test that actually kills the process.

**Files:**
- Test: `App/ARShaderTests/NodeConnectionTests.swift`
- Modify: `App/FXNodeKit/NodeProtocol.swift`
- Modify: `App/MoshNode/NodeService.swift`

**Interfaces:**
- Consumes: `NodeConnection`, `NativeNodeBacking`.
- Produces: `NodeProtocol.crashForTesting()` — a deliberate abort used only by the recovery test.

- [ ] **Step 1: Write the failing test**

Append to `App/ARShaderTests/NodeConnectionTests.swift`:

```swift
    func testTheHostSurvivesAServiceCrashAndRelaunchesIt() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let backing = try XCTUnwrap(
            NativeNodeBacking(serviceName: "com.arsonrivvers.ARShader.MoshNode",
                              device: device, width: 8, height: 8, ringDepth: 3))
        defer { backing.invalidate() }

        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        let input = try XCTUnwrap(device.makeTexture(descriptor: d))
        let size = MTLSize(width: 8, height: 8, depth: 1)

        func pump() throws -> MTLTexture? {
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            let out = backing.produce(input: input, size: size, in: cb)
            cb.commit(); cb.waitUntilCompleted()
            return out
        }

        // Establish output so there is something to hold.
        var first: MTLTexture?
        for _ in 0..<60 {
            first = try pump()
            if first != nil { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertNotNil(first, "need a decoded frame before killing the service")

        // Kill it.
        let connection = makeConnection()
        (connection.remoteObjectProxyWithErrorHandler { _ in } as? NodeProtocol)?.crashForTesting()
        connection.invalidate()
        Thread.sleep(forTimeInterval: 0.5)

        // The host must still be alive, and the stage must be HOLDING, not passing through.
        let duringOutage = try pump()
        XCTAssertNotNil(duringOutage, "a dead child must not make the stage pass its input through")

        // And it must come back on its own.
        var recovered = false
        for _ in 0..<150 {
            _ = try pump()
            if !backing.isDisabled && backing.restartCount > 0 && try pump() != nil {
                recovered = true; break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(recovered, "the service must relaunch on its own")
        XCTAssertFalse(backing.isDisabled, "one crash is not a crash loop")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NodeConnectionTests/testTheHostSurvivesAServiceCrashAndRelaunchesIt 2>&1 | tail -20
```

Expected: FAIL — `crashForTesting` is undefined.

- [ ] **Step 3: Add the deliberate crash**

In `App/FXNodeKit/NodeProtocol.swift`, add to the protocol:

```swift
    /// Kills the service process on purpose. The ONLY caller is the crash-recovery test — the
    /// failure model is load-bearing enough that it gets exercised rather than assumed.
    func crashForTesting()
```

In `App/MoshNode/NodeService.swift`, add to `NodeService`:

```swift
    func crashForTesting() {
        // Not fatalError(): this must look like the codec segfaulting, not like a Swift trap.
        abort()
    }
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd App && xcodegen generate
xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' \
  -only-testing:ARShaderTests/NodeConnectionTests 2>&1 | tail -25
```

Expected: PASS, all three tests in the file.

- [ ] **Step 5: Run everything**

```bash
cd App && xcodebuild test -scheme ARShader -destination 'platform=macOS,arch=arm64' 2>&1 | tail -15
xcodebuild test -scheme TrueISFEditor -destination 'platform=macOS,arch=arm64' 2>&1 | tail -15
ctest --test-dir ../Engine/mosh/build --output-on-failure 2>&1 | tail -10
```

Expected: all three green — ARShader, TrueISFEditor, and the 5 engine tests.

- [ ] **Step 6: Commit**

```bash
git add App/FXNodeKit/NodeProtocol.swift App/MoshNode/NodeService.swift \
        App/ARShaderTests/NodeConnectionTests.swift
git commit -m "test(node): prove the host survives a service crash and relaunches it"
```

---

## Task 10: Live smoke — the pipe, by hand

Unit tests cannot see the XPC, IOSurface, and codec boundaries together. This is the mandatory live leg.

**Files:**
- Create: `docs/reports/live-smoke-datamosh-node-phase1.md`
- Modify: `App/ARShader/FXChainView.swift` (temporary debug affordance)

**Interfaces:**
- Consumes: everything above.
- Produces: a signed-off smoke report.

- [ ] **Step 1: Pre-flight assertions**

Run each and record the actual output. Do NOT proceed past a failure.

```bash
# 1. The service is embedded in the built app, not merely built alongside it.
cd App && xcodebuild -scheme ARShader -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -3
APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'ARShader.app' -path '*Build/Products/Debug*' | head -1)
echo "APP=$APP"
ls "$APP/Contents/XPCServices/MoshNode.xpc/Contents/MacOS/MoshNode"

# 2. It is signed with the same identity as the host.
codesign -dv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier'
codesign -dv "$APP/Contents/XPCServices/MoshNode.xpc" 2>&1 | grep -E 'Authority|TeamIdentifier'

# 3. Nothing else is holding the repo.
ps aux | grep -E 'claude|codex' | grep -v grep | wc -l
```

Expected: the MoshNode binary exists inside `Contents/XPCServices/`, both `TeamIdentifier`s read `Q9DY8S68BC`, and no competing session is mid-write.

- [ ] **Step 2: Add a temporary way to insert a native stage**

In `App/ARShader/FXChainView.swift`, add a debug-only button beside the existing add-stage control:

```swift
#if DEBUG
Button("Add Native Node (debug)") { onAddNativeNode?() }
    .help("Phase 1: inserts the out-of-process invert node")
#endif
```

with a matching `var onAddNativeNode: (() -> Void)?` on the view, wired from wherever `FXChainView` is constructed to append an `FXStage` whose backing is a `NativeNodeBacking`. This is scaffolding for the smoke test and is removed in phase 2 when the node arrives through the real effect library.

- [ ] **Step 3: Run the app and drive it by hand**

```bash
./scripts/run-instrument.sh
```

Then, with the app running, verify each and record PASS/FAIL with a note:

1. Load any shader on deck 1. Confirm normal output.
2. Add the native node to deck 1's FX chain. **Confirm the image inverts.** This is the first time a frame has crossed the process boundary in the real app.
3. Confirm `Activity Monitor` shows a separate `MoshNode` process.
4. Set the stage's mix to 0.5. Confirm a half-strength invert — this proves the node inherits the existing mix and blend path.
5. Reorder the native node above and below an ISF stage. Confirm the order changes the result.
6. `kill -9` the MoshNode process from Terminal. **Confirm ARShader does not crash, the image holds rather than snapping to clean, and the node recovers within a few seconds.**
7. Kill it six times in under 30 seconds. Confirm the node disables itself rather than looping.
8. Press blackout while the node is running. **Confirm the master goes black** — no node can defeat panic.
9. Add native nodes to deck 1, deck 2 and master simultaneously. Record the frame rate and whether it holds.

- [ ] **Step 4: Write the report**

Create `docs/reports/live-smoke-datamosh-node-phase1.md` with the build SHA (`git rev-parse --short HEAD`), the macOS and hardware strings, the pre-flight output verbatim, the nine numbered results, and an explicit verdict line. Record failures as failures — a smoke report that only contains passes is not evidence.

- [ ] **Step 5: Commit**

```bash
git add docs/reports/live-smoke-datamosh-node-phase1.md App/ARShader/FXChainView.swift
git commit -m "test(node): phase 1 live smoke — frames cross the process boundary"
```

---

## Done criteria for phases 0a, 0b and 1

- The spike report records a `PROCEED` verdict with the measured capability line.
- `Engine/build_ffglitch.sh` builds patched libavcodec with libx264 from a clean checkout, verifying the patch checksum.
- `ctest --test-dir Engine/mosh/build` passes 5/5, including the four vendored suites unmodified.
- `moshcli` produces a visibly moshed video file from a real clip.
- `ARShaderTests` and `TrueISFEditorTests` are green, including the pre-existing tests that prove the `FXStageBacking` refactor preserved behavior.
- A native node inserted into a live FX chain inverts the image, survives `kill -9`, holds rather than passing through during the outage, disables itself on a crash loop, and cannot defeat blackout.

**Phase 2 gets its own plan**, written once this one lands — it depends on the measured XPC round-trip and on whether the service reported a usable `MTLDevice`.
