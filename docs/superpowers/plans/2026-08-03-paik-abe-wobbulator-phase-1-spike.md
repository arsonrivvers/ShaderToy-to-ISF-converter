# ARShader Paik/Abe Wobbulator Phase 1 Renderer Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select and prove the Full Beam forward-deposition representation for ARShader on this
40-GPU-core Apple M5 Max before any host-stage refactor begins.

**Architecture:** Build `WobbulatorKit` as a sibling Swift package beside `ShadertoyISFKit`, with
a pure CPU target, a Metal target, and a command-line benchmark target. A double-precision oracle
and common Metal endpoint generator feed three interchangeable forward depositors. All three
representations consume the same beam samples, render into linear `RGBA16Float`, and are judged by
the same numerical, visual, energy, memory, and sustained GPU-time gates. The winning
representation and frozen tolerances become inputs to the later native-stage plan; no Phase 1
source is wired into `FXStage` or `FXChain`.

**Tech Stack:** Swift 6.2, Swift Package Manager, XCTest, Metal and Metal Shading Language, macOS
13+, Foundation, simd, and this Apple M5 Max.

**Approved spec:** `docs/superpowers/specs/2026-08-03-paik-abe-wobbulator-arshader.md`

**Research dossier:**
`/Users/arsonrivvers/.claude/c-suite/reports/chief-of-staff/2026-08-03-paik-abe-wobbulator-arshader-research.md`

## Global Constraints

- The sole deployment and benchmark target is this 40-GPU-core Apple M5 Max with 128 GB memory.
  Do not add an M1 tier, an iOS target, or a cross-device compatibility matrix.
- Full Beam forward deposition is the only v1 renderer. Do not implement inverse Fast Preview in
  this plan.
- Phase 1 changes only `WobbulatorKit/`, its tests, and the Phase 1 evidence directory under
  `docs/arshader/benchmarks/wobbulator-phase1/`. Do not modify `App/ARShader/`,
  `App/ISFRuntime/`, or `App/project.yml`.
- Execute in a fresh worktree created with `superpowers:using-git-worktrees`. Other sessions are
  active in this repository. Never use `git add -A`; stage only the paths named by each task.
- The package compiles Metal once before warm-up. No shader or pipeline compilation is included in
  measured frames.
- Every measured command buffer is committed and completed before its timestamp is read. GPU time
  is `gpuEndTime - gpuStartTime`; CPU wall time is recorded separately and never substituted.
- The benchmark reuses textures, buffers, pipelines, and command queues in steady state. Any
  per-frame Metal texture, buffer, pipeline, or command-queue allocation is a test failure.
  Command buffers, render-pass descriptors, and encoders remain frame-scoped Metal objects.
- The render target is linear `RGBA16Float`. Deposition is additive and energy-normalized. A final
  pass makes every output alpha value exactly 1, including uncovered black pixels.
- Every representation receives the same source grid, endpoint buffer, beam width, exposure,
  integration steps, and fixture. A representation-specific hidden gain is forbidden.
- CRT beam time is measured only in seconds and identifies when a raster sample launches. The
  Phase 1 trajectory is dimensionless because there is no calibrated seconds-per-simulation-unit
  conversion. Evaluate and freeze field phase at `rasterLaunchTimeSeconds` for the full flight;
  never add a dimensionless Boris step to CRT seconds. Phase may vary between raster samples.
- The adaptive candidate evaluates inserted quarter, midpoint, and three-quarter trajectories
  through the same Boris pusher. It may emit one, two, or four curved-path chords only after a
  real midpoint-error test against those evaluated endpoints. Linear subdivision of the original
  A-B chord is forbidden.
- The canonical high-quality GPU reference may be used for the 144-case matrix only after a
  bounded CPU depositor proves its absolute exposure, centroid, branch-additivity, and discrete
  kernel-normalization invariants. Reference validation is a recorded fail-closed prerequisite.
- Image metrics are outside the timed GPU loop but must still scale linearly with output pixels:
  deterministic Float16-energy histograms select the 95-percent-energy set without sorting every
  pixel, and exact separable Euclidean distance transforms replace pairwise contour matching.
- The provisional gates copied from the approved spec are binding until the evidence report
  confirms or revises them through an explicitly approved spec revision:
  - identity error <= 0.25 output-pixel RMS and <= 0.75 pixel maximum;
  - GPU endpoint error versus the CPU oracle <= 0.25 pixel RMS and <= 1.0 pixel maximum;
  - relative momentum drift <= 0.00001;
  - integrated exposure delta <= 2 percent across resolution and quality;
  - caustic centroid delta <= 1 pixel at 1080p and <= 2 pixels at 4K;
  - 95-percent-energy contour symmetric mean distance <= 2 pixels at 1080p and <= 4 pixels at 4K;
  - effect-only p95 GPU duration <= 4 ms at 1080p60 and <= 8 ms at 4K30/60;
  - zero numerically invalid samples for factory-safe fixtures.
- The screening matrix uses source grids `480x270`, `960x540`, `1280x720`, and `1920x1080`, with
  8, 16, and 32 integration steps. The full thermal run uses the highest validated grid and step
  count for the selected representation. Phase 1 rejects outputs above `3840x2160`, source grids
  above `1920x1080`, or more than 256 integration steps before any ABI conversion or allocation.
- Quick tests use deterministic generated identity, dipole, S-bend, and multi-valued fold fixtures.
  Gitignored Instagram media and archived PDFs remain local research evidence and are never copied
  into the package, test bundle, or Git history.
- A Phase 1 pass does not prove the future full 4K60 chain. It proves the effect has the required
  <= 8 ms p95 budget, reserving at least 8.67 ms for the later host chain.
- There is no runtime network access, external account, paid API, hosted service, scheduled job, or
  recurring cost.
- Before each commit, run from `WobbulatorKit`:

  ```bash
  swift format format --in-place --recursive Sources Tests
  swift format lint --strict --recursive Sources Tests
  swift test
  swift build -c release
  ```

## Mandatory mutation-proof protocol

Every step below that temporarily changes a threshold, shader expression, allocation route, or
decision helper follows this protocol. It is part of the step, not optional prose:

1. Run the named focused test unchanged and require a green negative control with at least one
   executed test in the output. Confirm `swift`, the Metal compiler when applicable, and every
   script named by the guard resolve at their runtime paths.
2. Set `proof_target` to the one exact file named by that mutation, create `proof_scratch` with
   `mktemp -d`, copy the target to `$proof_scratch/original`, and install an EXIT/INT/TERM trap that
   copies the original back. Never use Git checkout, reset, switch, or stash to restore a proof.
3. Apply only the named mutation. Require `cmp -s "$proof_scratch/original" "$proof_target"` to
   return nonzero, show the complete `git diff --no-index` for those two files, and abort if the
   mutation anchor was absent or the changed file no longer parses.
4. Run the named focused test directly, without piping or truncation. Capture its exit code before
   printing output; require a nonzero code and the assertion/test name unique to the intended
   guard. A different compile failure or a zero-test run is inconclusive, not a caught mutation.
5. Restore from `$proof_scratch/original`, remove the trap, require `cmp -s` to succeed, and rerun
   the same focused test to green. Remove only that validated scratch directory.
6. Mutate one guard at a time and record `baseline green / mutation applied / caught red / restored
   green` for the task's commit evidence. Any not-caught mutation blocks the task until a binding
   test exists.

## Why the line-level plan stops after Phase 1

The approved product spec covers the full instrument, but a line-level production plan written
before the representation spike would invent buffer layouts, quality tiers, memory bounds, and
host interfaces that the evidence is supposed to decide. Phase 1 therefore produces working,
testable software and a hard go/stop artifact. On a go result, write separate execution plans for
the remaining approved phases:

| Next phase | Dependency | Deliverable |
|---|---|---|
| 2. Shared native backing | Phase 1 go | One `FXStageDescriptor` / `FXStageRenderCore` / `FXRenderContext` / `FXEncodeResult` seam shared with Datamosh, plus an identity native stage |
| 3. Virtual CRT and H/V | Phase 2 | Resolution-independent raster, base yoke, H/V dipoles, historical fixtures, minimal operator shell |
| 4. S coil and Quadrupole | Phase 3 | Finite S field, production Boris pusher, Quadrupole, field and trajectory diagnostics |
| 5. Production Full Beam | Phases 1 and 4 | Port the selected depositor, energy normalization, fixed and adaptive quality, HDR finish interface |
| 6. Physically inspired modes | Phase 5 | Vortex, Radial Breathing, Ripple, Orbit Coil |
| 7. Hybrid and artistic modes | Phase 5 | Concentric Wave, Kaleidoscope, Wavefolder |
| 8. Complete instrument | Phases 6 and 7 | Advanced controls, modulation, presets, accessibility, status, panic, temporal lifecycle |
| 9. Release proof | Phase 8 | Phosphor and bloom finish, failure injection, evidence matrix, full-chain 4K thermal run, operator sign-off |
| 10. Conditional Fast Preview | Separate post-v1 approval | Guarded one-to-one inverse preview, omitted unless evidence justifies it |

## File Structure

| File | Responsibility | Task |
|---|---|---|
| Create `WobbulatorKit/Package.swift` | Isolated CPU library, Metal library, executable, resource, and test targets | 1, 3, 5 |
| Create `WobbulatorKit/Sources/WobbulatorCore/SpikeTypes.swift` | Stable workload, threshold, fixture, representation, report, and typed-error contracts | 1 |
| Create `WobbulatorKit/Tests/WobbulatorCoreTests/SpikeTypesTests.swift` | Contract validation and JSON round trips | 1 |
| Create `WobbulatorKit/Sources/WobbulatorCore/CRTTiming.swift` | Resolution-independent beam time, dwell, area, blanking, and parity | 2 |
| Create `WobbulatorKit/Sources/WobbulatorCore/RelativisticBorisOracle.swift` | Double-precision magnetic field and trajectory oracle | 2 |
| Create `WobbulatorKit/Tests/WobbulatorCoreTests/CRTTimingTests.swift` | Timing and phase invariance gates | 2 |
| Create `WobbulatorKit/Tests/WobbulatorCoreTests/RelativisticBorisOracleTests.swift` | Identity, reversal, conservation, and termination gates | 2 |
| Create `WobbulatorKit/Sources/WobbulatorMetal/Shaders/WobbulatorSpike.metal` | Common endpoint compute plus point, ribbon, adaptive, and finalize kernels | 3, 4 |
| Create `WobbulatorKit/Sources/WobbulatorMetal/MetalABI.swift` | Swift mirrors for 16-byte-aligned Metal parameters and records | 3 |
| Create `WobbulatorKit/Sources/WobbulatorMetal/MetalResourceFactory.swift` | Count every explicit Metal buffer, texture, pipeline, and queue creation | 3 |
| Create `WobbulatorKit/Sources/WobbulatorMetal/WobbulatorMetalRenderer.swift` | Pipeline creation, persistent resources, encoding, GPU timing, and readback | 3, 4 |
| Create `WobbulatorKit/Tests/WobbulatorMetalTests/MetalOracleTests.swift` | CPU/GPU endpoint and no-invalid-sample gates | 3 |
| Create `WobbulatorKit/Tests/WobbulatorMetalTests/ForwardDepositionTests.swift` | Fold branch retention, alpha, energy, centroid, and contour gates | 3, 4 |
| Create `WobbulatorKit/Sources/WobbulatorMetal/HDRMetrics.swift` | Float16 readback, exposure, centroid, 95-percent mask, contour distance, PPM previews | 4 |
| Create `WobbulatorKit/Sources/WobbulatorMetal/CPUForwardDepositionReference.swift` | Independent bounded double-precision endpoint and discrete-kernel deposition oracle | 4 |
| Create `WobbulatorKit/Tests/WobbulatorMetalTests/HDRMetricsTests.swift` | Histogram selection, exact EDT, pixel scaling, and CPU-reference authority gates | 4 |
| Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkOptions.swift` | CLI options, exact matrix expansion, and thermal selection loading | 5 |
| Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkRunner.swift` | Warm-up, quick matrix, sustained pacing, percentiles, allocation and metric records | 5 |
| Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkDecision.swift` | Acceptance filtering, deterministic ranking, stop states, and decision Markdown | 5 |
| Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkArtifactVerifier.swift` | Decode evidence, prove exact workload membership, recompute decisions, and lock thermal selection | 5 |
| Create `WobbulatorKit/Sources/WobbulatorBench/main.swift` | Dependency-free CLI and exit codes | 5 |
| Create `WobbulatorKit/Tests/WobbulatorBenchTests/BenchmarkRunnerTests.swift` | Percentile, matrix, exposure, artifact-coherence, hardware-redaction, and stop-rule gates | 5 |
| Create `docs/arshader/benchmarks/wobbulator-phase1/README.md` | Reproducible M5 command protocol and artifact schema | 5 |
| Generate `docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json` | Quick and extended M5 measurements | 6 |
| Generate `docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json` | Ten-minute sustained winner measurements | 6 |
| Generate `docs/arshader/benchmarks/wobbulator-phase1/previews/` | Downsampled deterministic PPM comparisons | 6 |
| Generate `docs/arshader/benchmarks/wobbulator-phase1/decision.md` | Winner, frozen quality floor, thresholds, stop/go result, and re-estimate | 6 |

---

### Task 1: Establish the isolated spike contracts

**Files:**
- Create: `WobbulatorKit/Package.swift`
- Create: `WobbulatorKit/Sources/WobbulatorCore/SpikeTypes.swift`
- Test: `WobbulatorKit/Tests/WobbulatorCoreTests/SpikeTypesTests.swift`

**Interfaces:**
- Consumes: Foundation only.
- Produces:
  - `DepositionRepresentation`, `SpikeFixture`, `SpikeSourcePattern`, `RasterSize`, `SampleGrid`,
    `SpikeWorkload`
  - `SpikeThresholds.approved`
  - `MetalResourceCreationCounts`, `BenchmarkStatus`, `BenchmarkMeasurement`, `BenchmarkReport`
  - `WobbulatorSpikeError`
  Tasks 2 through 6 use these names unchanged.

- [ ] **Step 1: Create the package shell**

Create `WobbulatorKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WobbulatorKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WobbulatorCore", targets: ["WobbulatorCore"])
    ],
    targets: [
        .target(name: "WobbulatorCore"),
        .testTarget(
            name: "WobbulatorCoreTests",
            dependencies: ["WobbulatorCore"]
        ),
    ]
)
```

Create `WobbulatorKit/Sources/WobbulatorCore/SpikeTypes.swift` with only:

```swift
import Foundation
```

- [ ] **Step 2: Write the failing contract tests**

Create `WobbulatorKit/Tests/WobbulatorCoreTests/SpikeTypesTests.swift`:

```swift
import Foundation
import XCTest
@testable import WobbulatorCore

final class SpikeTypesTests: XCTestCase {
    func testApprovedThresholdsMatchTheSignedSpec() {
        let t = SpikeThresholds.approved
        XCTAssertEqual(t.identityRMSPixels, 0.25)
        XCTAssertEqual(t.identityMaxPixels, 0.75)
        XCTAssertEqual(t.oracleRMSPixels, 0.25)
        XCTAssertEqual(t.oracleMaxPixels, 1.0)
        XCTAssertEqual(t.relativeMomentumDrift, 0.00001)
        XCTAssertEqual(t.exposureDeltaFraction, 0.02)
        XCTAssertEqual(t.p95Milliseconds1080, 4.0)
        XCTAssertEqual(t.p95Milliseconds4K, 8.0)
    }

    func testAWorkloadRejectsNonPositiveDimensionsAndSteps() {
        XCTAssertThrowsError(
            try SpikeWorkload(
                output: RasterSize(width: 0, height: 1080),
                samples: SampleGrid(width: 960, height: 540),
                integrationSteps: 16,
                beamWidthPixelsAt1080: 1.25,
                fixture: .fold,
                representation: .scanlineRibbon
            )
        ) { error in
            XCTAssertEqual(error as? WobbulatorSpikeError, .invalidWorkload("output must be positive"))
        }
    }

    func testAWorkloadRejectsNonFinitePhysicalInputs() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(
                try SpikeWorkload(
                    output: .hd1080,
                    samples: SampleGrid(width: 960, height: 540),
                    integrationSteps: 16,
                    beamWidthPixelsAt1080: value,
                    fixture: .fold,
                    representation: .scanlineRibbon
                )
            )
            XCTAssertThrowsError(
                try SpikeWorkload(
                    output: .hd1080,
                    samples: SampleGrid(width: 960, height: 540),
                    integrationSteps: 16,
                    beamWidthPixelsAt1080: 1.25,
                    fixtureAmount: value,
                    fixture: .fold,
                    representation: .scanlineRibbon
                )
            )
        }
    }

    func testAWorkloadRejectsValuesOutsideThePhaseOneMatrixBounds() {
        XCTAssertThrowsError(
            try SpikeWorkload(
                output: RasterSize(width: 3841, height: 2160),
                samples: SampleGrid(width: 960, height: 540),
                integrationSteps: 16,
                beamWidthPixelsAt1080: 1.25,
                fixture: .fold,
                representation: .scanlineRibbon
            )
        )
        XCTAssertThrowsError(
            try SpikeWorkload(
                output: .hd1080,
                samples: SampleGrid(width: 1921, height: 1080),
                integrationSteps: 257,
                beamWidthPixelsAt1080: 1.25,
                fixture: .fold,
                representation: .scanlineRibbon
            )
        )
    }

    func testDecodedWorkloadMustPassTheSameValidatedInitializer() {
        let malicious = """
        {
          "output":{"width":9223372036854775807,"height":2160},
          "samples":{"width":1920,"height":1080},
          "integrationSteps":32,
          "beamWidthPixelsAt1080":1.25,
          "fixtureAmount":0.35,
          "fixture":"fold",
          "sourcePattern":"colorGrid",
          "representation":"scanlineRibbon"
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(SpikeWorkload.self, from: Data(malicious.utf8))
        )
    }

    func testReportRoundTripsWithoutMachineIdentifiers() throws {
        let report = BenchmarkReport(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            hardware: HardwareRecord(
                deviceName: "Apple M5 Max",
                gpuCoreCount: 40,
                memoryGB: 128,
                operatingSystem: "macOS",
                swiftVersion: "6.2.1"
            ),
            thresholds: .approved,
            measurements: [],
            status: .go,
            recommendation: "scanlineRibbon",
            recommendedWorkload: nil,
            referenceValidationPassed: true,
            referenceIdentityNormalizedExposureDelta: 0.0,
            referenceFoldNormalizedExposureDelta: 0.0
        )
        let data = try JSONEncoder().encode(report)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("serial"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("uuid"))
        XCTAssertEqual(try JSONDecoder().decode(BenchmarkReport.self, from: data), report)
    }

    func testResourceCreationCountsSubtractFieldByField() {
        let before = MetalResourceCreationCounts(commandQueues: 1, buffers: 3, textures: 2)
        let after = MetalResourceCreationCounts(commandQueues: 1, buffers: 4, textures: 2)
        XCTAssertEqual(
            after - before,
            MetalResourceCreationCounts(buffers: 1)
        )
    }
}
```

- [ ] **Step 3: Run the tests to verify RED**

Run:

```bash
cd WobbulatorKit
swift test --filter SpikeTypesTests
```

Expected: compilation fails because `SpikeThresholds`, `SpikeWorkload`, and the other contract
types do not exist.

- [ ] **Step 4: Implement the complete contract layer**

Replace `WobbulatorKit/Sources/WobbulatorCore/SpikeTypes.swift` with:

```swift
import Foundation

public enum DepositionRepresentation: String, CaseIterable, Codable, Hashable, Sendable {
    case gaussianPointSprite
    case scanlineRibbon
    case adaptiveScanlineSegment
}

public enum SpikeFixture: String, CaseIterable, Codable, Hashable, Sendable {
    case identity
    case dipole
    case sBend
    case fold
    case branchOverlap
}

public enum SpikeSourcePattern: String, Codable, Hashable, Sendable {
    case colorGrid
    case solidWhite
    case leftRedOnly
    case rightGreenOnly
    case twoBranchRedGreen
}

public struct RasterSize: Codable, Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let hd1080 = RasterSize(width: 1920, height: 1080)
    public static let uhd4K = RasterSize(width: 3840, height: 2160)
}

public struct SampleGrid: Codable, Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var count: Int { width * height }
}

public struct SpikeWorkload: Codable, Equatable, Hashable, Sendable {
    public var output: RasterSize
    public var samples: SampleGrid
    public var integrationSteps: Int
    public var beamWidthPixelsAt1080: Double
    public var fixtureAmount: Double
    public var fixture: SpikeFixture
    public var sourcePattern: SpikeSourcePattern
    public var representation: DepositionRepresentation

    public init(
        output: RasterSize,
        samples: SampleGrid,
        integrationSteps: Int,
        beamWidthPixelsAt1080: Double,
        fixtureAmount: Double = 0.35,
        fixture: SpikeFixture,
        sourcePattern: SpikeSourcePattern = .colorGrid,
        representation: DepositionRepresentation
    ) throws {
        guard output.width > 0, output.height > 0 else {
            throw WobbulatorSpikeError.invalidWorkload("output must be positive")
        }
        guard samples.width > 1, samples.height > 0 else {
            throw WobbulatorSpikeError.invalidWorkload("sample grid must be at least 2 by 1")
        }
        guard integrationSteps > 0 else {
            throw WobbulatorSpikeError.invalidWorkload("integration steps must be positive")
        }
        guard output.width <= 3840, output.height <= 2160 else {
            throw WobbulatorSpikeError.invalidWorkload(
                "Phase 1 output must not exceed 3840 by 2160"
            )
        }
        guard samples.width <= 1920, samples.height <= 1080 else {
            throw WobbulatorSpikeError.invalidWorkload(
                "Phase 1 sample grid must not exceed 1920 by 1080"
            )
        }
        guard integrationSteps <= 256 else {
            throw WobbulatorSpikeError.invalidWorkload(
                "Phase 1 integration steps must not exceed 256"
            )
        }
        guard beamWidthPixelsAt1080.isFinite, beamWidthPixelsAt1080 > 0 else {
            throw WobbulatorSpikeError.invalidWorkload(
                "beam width must be finite and positive"
            )
        }
        guard fixtureAmount.isFinite else {
            throw WobbulatorSpikeError.invalidWorkload("fixture amount must be finite")
        }
        self.output = output
        self.samples = samples
        self.integrationSteps = integrationSteps
        self.beamWidthPixelsAt1080 = beamWidthPixelsAt1080
        self.fixtureAmount = fixtureAmount
        self.fixture = fixture
        self.sourcePattern = sourcePattern
        self.representation = representation
    }

    private enum CodingKeys: String, CodingKey {
        case output
        case samples
        case integrationSteps
        case beamWidthPixelsAt1080
        case fixtureAmount
        case fixture
        case sourcePattern
        case representation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                output: container.decode(RasterSize.self, forKey: .output),
                samples: container.decode(SampleGrid.self, forKey: .samples),
                integrationSteps: container.decode(Int.self, forKey: .integrationSteps),
                beamWidthPixelsAt1080: container.decode(
                    Double.self, forKey: .beamWidthPixelsAt1080
                ),
                fixtureAmount: container.decode(Double.self, forKey: .fixtureAmount),
                fixture: container.decode(SpikeFixture.self, forKey: .fixture),
                sourcePattern: container.decode(
                    SpikeSourcePattern.self, forKey: .sourcePattern
                ),
                representation: container.decode(
                    DepositionRepresentation.self, forKey: .representation
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "decoded workload failed Phase 1 validation",
                    underlyingError: error
                )
            )
        }
    }

    public var beamWidthPixels: Double {
        beamWidthPixelsAt1080 * Double(output.height) / 1080.0
    }
}

public struct SpikeThresholds: Codable, Equatable, Sendable {
    public var identityRMSPixels: Double
    public var identityMaxPixels: Double
    public var oracleRMSPixels: Double
    public var oracleMaxPixels: Double
    public var relativeMomentumDrift: Double
    public var exposureDeltaFraction: Double
    public var centroidPixels1080: Double
    public var centroidPixels4K: Double
    public var contourPixels1080: Double
    public var contourPixels4K: Double
    public var p95Milliseconds1080: Double
    public var p95Milliseconds4K: Double

    public static let approved = SpikeThresholds(
        identityRMSPixels: 0.25,
        identityMaxPixels: 0.75,
        oracleRMSPixels: 0.25,
        oracleMaxPixels: 1.0,
        relativeMomentumDrift: 0.00001,
        exposureDeltaFraction: 0.02,
        centroidPixels1080: 1.0,
        centroidPixels4K: 2.0,
        contourPixels1080: 2.0,
        contourPixels4K: 4.0,
        p95Milliseconds1080: 4.0,
        p95Milliseconds4K: 8.0
    )
}

public enum BenchmarkStatus: String, Codable, Equatable, Sendable {
    case go
    case stop1080
    case blocked4K
}

public struct HardwareRecord: Codable, Equatable, Sendable {
    public var deviceName: String
    public var gpuCoreCount: Int
    public var memoryGB: Int
    public var operatingSystem: String
    public var swiftVersion: String

    public init(
        deviceName: String,
        gpuCoreCount: Int,
        memoryGB: Int,
        operatingSystem: String,
        swiftVersion: String
    ) {
        self.deviceName = deviceName
        self.gpuCoreCount = gpuCoreCount
        self.memoryGB = memoryGB
        self.operatingSystem = operatingSystem
        self.swiftVersion = swiftVersion
    }
}

public struct MetalResourceCreationCounts: Codable, Equatable, Sendable {
    public var commandQueues: Int
    public var buffers: Int
    public var textures: Int
    public var libraries: Int
    public var computePipelines: Int
    public var renderPipelines: Int

    public init(
        commandQueues: Int = 0,
        buffers: Int = 0,
        textures: Int = 0,
        libraries: Int = 0,
        computePipelines: Int = 0,
        renderPipelines: Int = 0
    ) {
        self.commandQueues = commandQueues
        self.buffers = buffers
        self.textures = textures
        self.libraries = libraries
        self.computePipelines = computePipelines
        self.renderPipelines = renderPipelines
    }

    public static let zero = MetalResourceCreationCounts()

    public var total: Int {
        commandQueues + buffers + textures + libraries + computePipelines + renderPipelines
    }

    public static func - (
        lhs: MetalResourceCreationCounts,
        rhs: MetalResourceCreationCounts
    ) -> MetalResourceCreationCounts {
        MetalResourceCreationCounts(
            commandQueues: lhs.commandQueues - rhs.commandQueues,
            buffers: lhs.buffers - rhs.buffers,
            textures: lhs.textures - rhs.textures,
            libraries: lhs.libraries - rhs.libraries,
            computePipelines: lhs.computePipelines - rhs.computePipelines,
            renderPipelines: lhs.renderPipelines - rhs.renderPipelines
        )
    }
}

public struct BenchmarkMeasurement: Codable, Equatable, Sendable {
    public var workload: SpikeWorkload
    public var frameCount: Int
    public var p50GPUMilliseconds: Double
    public var p95GPUMilliseconds: Double
    public var meanCPUMilliseconds: Double
    public var measuredWallSeconds: Double
    public var thermalTargetSeconds: Double?
    public var thermalTargetFramesPerSecond: Double?
    public var allocatedBytes: Int
    public var fieldEvaluationsPerFrame: Int
    public var primitiveInstancesPerFrame: Int
    public var integratedExposure: Double
    public var relativeExposureDelta: Double
    public var centroidDistancePixels: Double
    public var contourDistancePixels: Double
    public var identityRMSPixels: Double
    public var identityMaxPixels: Double
    public var oracleRMSPixels: Double
    public var oracleMaxPixels: Double
    public var maximumRelativeMomentumDrift: Double
    public var branchRetentionPassed: Bool
    public var invalidSampleCount: Int
    public var adaptiveInvalidIntervalCount: Int
    public var adaptiveToleranceFailureCount: Int
    public var measuredResourceCreations: MetalResourceCreationCounts

    public init(
        workload: SpikeWorkload,
        frameCount: Int,
        p50GPUMilliseconds: Double,
        p95GPUMilliseconds: Double,
        meanCPUMilliseconds: Double,
        measuredWallSeconds: Double,
        thermalTargetSeconds: Double? = nil,
        thermalTargetFramesPerSecond: Double? = nil,
        allocatedBytes: Int,
        fieldEvaluationsPerFrame: Int,
        primitiveInstancesPerFrame: Int,
        integratedExposure: Double,
        relativeExposureDelta: Double,
        centroidDistancePixels: Double,
        contourDistancePixels: Double,
        identityRMSPixels: Double,
        identityMaxPixels: Double,
        oracleRMSPixels: Double,
        oracleMaxPixels: Double,
        maximumRelativeMomentumDrift: Double,
        branchRetentionPassed: Bool,
        invalidSampleCount: Int,
        adaptiveInvalidIntervalCount: Int,
        adaptiveToleranceFailureCount: Int,
        measuredResourceCreations: MetalResourceCreationCounts
    ) {
        self.workload = workload
        self.frameCount = frameCount
        self.p50GPUMilliseconds = p50GPUMilliseconds
        self.p95GPUMilliseconds = p95GPUMilliseconds
        self.meanCPUMilliseconds = meanCPUMilliseconds
        self.measuredWallSeconds = measuredWallSeconds
        self.thermalTargetSeconds = thermalTargetSeconds
        self.thermalTargetFramesPerSecond = thermalTargetFramesPerSecond
        self.allocatedBytes = allocatedBytes
        self.fieldEvaluationsPerFrame = fieldEvaluationsPerFrame
        self.primitiveInstancesPerFrame = primitiveInstancesPerFrame
        self.integratedExposure = integratedExposure
        self.relativeExposureDelta = relativeExposureDelta
        self.centroidDistancePixels = centroidDistancePixels
        self.contourDistancePixels = contourDistancePixels
        self.identityRMSPixels = identityRMSPixels
        self.identityMaxPixels = identityMaxPixels
        self.oracleRMSPixels = oracleRMSPixels
        self.oracleMaxPixels = oracleMaxPixels
        self.maximumRelativeMomentumDrift = maximumRelativeMomentumDrift
        self.branchRetentionPassed = branchRetentionPassed
        self.invalidSampleCount = invalidSampleCount
        self.adaptiveInvalidIntervalCount = adaptiveInvalidIntervalCount
        self.adaptiveToleranceFailureCount = adaptiveToleranceFailureCount
        self.measuredResourceCreations = measuredResourceCreations
    }
}

public struct BenchmarkReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var hardware: HardwareRecord
    public var thresholds: SpikeThresholds
    public var measurements: [BenchmarkMeasurement]
    public var status: BenchmarkStatus
    public var recommendation: String
    public var recommendedWorkload: SpikeWorkload?
    public var referenceValidationPassed: Bool
    public var referenceIdentityNormalizedExposureDelta: Double
    public var referenceFoldNormalizedExposureDelta: Double

    public init(
        schemaVersion: Int,
        createdAt: Date,
        hardware: HardwareRecord,
        thresholds: SpikeThresholds,
        measurements: [BenchmarkMeasurement],
        status: BenchmarkStatus,
        recommendation: String,
        recommendedWorkload: SpikeWorkload?,
        referenceValidationPassed: Bool,
        referenceIdentityNormalizedExposureDelta: Double,
        referenceFoldNormalizedExposureDelta: Double
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.hardware = hardware
        self.thresholds = thresholds
        self.measurements = measurements
        self.status = status
        self.recommendation = recommendation
        self.recommendedWorkload = recommendedWorkload
        self.referenceValidationPassed = referenceValidationPassed
        self.referenceIdentityNormalizedExposureDelta =
            referenceIdentityNormalizedExposureDelta
        self.referenceFoldNormalizedExposureDelta = referenceFoldNormalizedExposureDelta
    }
}

public enum WobbulatorSpikeError: Error, LocalizedError, Equatable, Sendable {
    case invalidWorkload(String)
    case noMetalDevice
    case wrongMetalDevice(expected: String, actual: String)
    case shaderResourceMissing
    case shaderCompilation(String)
    case pipelineCreation(String)
    case resourceAllocation(String)
    case commandEncoding(String)
    case commandFailure(String)
    case invalidArguments(String)
    case evidenceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWorkload(let reason): "Invalid workload: \(reason)"
        case .noMetalDevice: "No Metal device is available."
        case .wrongMetalDevice(let expected, let actual):
            "Expected \(expected), found \(actual)."
        case .shaderResourceMissing: "The packaged Metal source is unavailable."
        case .shaderCompilation(let reason): "Metal source compilation failed: \(reason)"
        case .pipelineCreation(let reason): "Metal pipeline creation failed: \(reason)"
        case .resourceAllocation(let reason): "Metal resource allocation failed: \(reason)"
        case .commandEncoding(let reason): "Metal command encoding failed: \(reason)"
        case .commandFailure(let reason): "Metal command buffer failed: \(reason)"
        case .invalidArguments(let reason): "Invalid benchmark arguments: \(reason)"
        case .evidenceFailure(let reason): "Benchmark evidence failed: \(reason)"
        }
    }
}
```

- [ ] **Step 5: Run tests and the release build to verify GREEN**

Run:

```bash
cd WobbulatorKit
swift test --filter SpikeTypesTests
swift build -c release
```

Expected: `SpikeTypesTests` passes and the release library builds successfully.

- [ ] **Step 6: Format, lint, and commit**

Run:

```bash
cd WobbulatorKit
swift format format --in-place --recursive Sources Tests
swift format lint --strict --recursive Sources Tests
swift test
git add Package.swift Sources/WobbulatorCore/SpikeTypes.swift \
  Tests/WobbulatorCoreTests/SpikeTypesTests.swift
git commit -m "spike: define wobbulator benchmark contracts"
```

Expected: formatter and linter exit 0, all package tests pass, and the commit contains only the
three named files.

---

### Task 2: Build the double-precision raster and trajectory oracle

**Files:**
- Create: `WobbulatorKit/Sources/WobbulatorCore/CRTTiming.swift`
- Create: `WobbulatorKit/Sources/WobbulatorCore/RelativisticBorisOracle.swift`
- Test: `WobbulatorKit/Tests/WobbulatorCoreTests/CRTTimingTests.swift`
- Test: `WobbulatorKit/Tests/WobbulatorCoreTests/RelativisticBorisOracleTests.swift`

**Interfaces:**
- Consumes: `SpikeWorkload`, `RasterSize`, `SampleGrid`, and `WobbulatorSpikeError` from Task 1.
- Produces:
  - `CRTTiming.ntsc525`, `.pal625`, and `.progressive(fieldRate:activeLines:)`
  - `CRTTiming.sample(line:x:activeSamples:fieldIndex:) throws -> RasterSample`
  - `CRTTiming.rasterLaunchTimeSeconds(normalizedLine:horizontal:fieldIndex:) throws -> Double`
  - `OracleField.magneticField(at:rasterLaunchTimeSeconds:) -> SIMD3<Double>`
  - `BorisState`, `BorisTermination`, `BorisResult`
  - `RelativisticBorisOracle.trace(initial:field:steps:screenZ:bounds:) -> BorisResult`
  Tasks 3 and 4 compare the GPU endpoint buffer against these exact contracts.

- [ ] **Step 1: Write the failing CRT timing tests**

Create `WobbulatorKit/Tests/WobbulatorCoreTests/CRTTimingTests.swift`:

```swift
import XCTest
@testable import WobbulatorCore

final class CRTTimingTests: XCTestCase {
    func testNTSCFieldAndLinePeriodsUseFieldTiming() {
        let timing = CRTTiming.ntsc525
        XCTAssertEqual(timing.fieldRate, 60_000.0 / 1_001.0, accuracy: 1e-12)
        XCTAssertEqual(timing.linesPerField, 262.5)
        XCTAssertEqual(timing.linePeriod, 1.0 / timing.fieldRate / 262.5, accuracy: 1e-15)
    }

    func testRasterLaunchTimeIsIndependentOfOutputResolution() throws {
        let timing = CRTTiming.ntsc525
        let coarse = try timing.sample(line: 127, x: 1, activeSamples: 6, fieldIndex: 23)
        let fine = try timing.sample(line: 127, x: 4, activeSamples: 18, fieldIndex: 23)
        XCTAssertEqual(coarse.sourceUV.x, fine.sourceUV.x, accuracy: 1e-15)
        XCTAssertEqual(
            coarse.rasterLaunchTimeSeconds,
            fine.rasterLaunchTimeSeconds,
            accuracy: 1e-15
        )
        let cycles = abs(
            coarse.rasterLaunchTimeSeconds - fine.rasterLaunchTimeSeconds
        ) * timing.fieldRate
        XCTAssertLessThanOrEqual(cycles, 0.0001)
    }

    func testNormalizedLaunchTimeIsIndependentOfSampleGridDensity() throws {
        let timing = CRTTiming.ntsc525
        let coarse = try timing.rasterLaunchTimeSeconds(
            normalizedLine: 0.25,
            horizontal: 0.625,
            fieldIndex: 23
        )
        let fine = try timing.rasterLaunchTimeSeconds(
            normalizedLine: 2.0 / 8.0,
            horizontal: 5.0 / 8.0,
            fieldIndex: 23
        )
        XCTAssertEqual(coarse, fine, accuracy: 1e-15)
    }

    func testInterlacedParityAddressesAlternatingSourceLines() throws {
        let timing = CRTTiming.ntsc525
        let even = try timing.sample(line: 0, x: 0, activeSamples: 2, fieldIndex: 0)
        let odd = try timing.sample(line: 0, x: 0, activeSamples: 2, fieldIndex: 1)
        XCTAssertEqual(even.parity, .even)
        XCTAssertEqual(odd.parity, .odd)
        XCTAssertEqual(odd.sourceUV.y - even.sourceUV.y, 1.0 / 480.0, accuracy: 1e-15)
    }

    func testOneInterlacedFieldRepresentsHalfTheFrameArea() throws {
        let timing = CRTTiming.ntsc525
        var area = 0.0
        for line in 0..<timing.activeLines {
            for x in 0..<8 {
                area += try timing.sample(line: line, x: x, activeSamples: 8, fieldIndex: 0)
                    .sourceCellArea
            }
        }
        XCTAssertEqual(area, 0.5, accuracy: 1e-12)
    }

    func testOutOfRangeSampleIsRejected() {
        XCTAssertThrowsError(
            try CRTTiming.ntsc525.sample(line: 240, x: 0, activeSamples: 8, fieldIndex: 0)
        )
    }

    func testNonFiniteRasterCoordinatesAreRejected() {
        XCTAssertThrowsError(
            try CRTTiming.ntsc525.rasterLaunchTimeSeconds(
                normalizedLine: .nan,
                horizontal: 0.5,
                fieldIndex: 0
            )
        )
        XCTAssertThrowsError(
            try CRTTiming.ntsc525.rasterLaunchTimeSeconds(
                normalizedLine: 0.5,
                horizontal: .infinity,
                fieldIndex: 0
            )
        )
    }

    func testSBendPhaseVariesAcrossRasterLaunches() throws {
        let timing = CRTTiming.progressive(fieldRate: 60.0, activeLines: 2)
        let left = try timing.sample(line: 0, x: 0, activeSamples: 2, fieldIndex: 0)
        let right = try timing.sample(line: 0, x: 1, activeSamples: 2, fieldIndex: 0)
        let field = OracleField.sBend(
            amplitude: 1.0,
            angularFrequency: 2.0 * .pi * 60.0,
            phase: .pi / 2.0
        )
        let leftField = field.magneticField(
            at: SIMD3(0.0, 0.0, -1.0),
            rasterLaunchTimeSeconds: left.rasterLaunchTimeSeconds
        )
        let rightField = field.magneticField(
            at: SIMD3(0.0, 0.0, -1.0),
            rasterLaunchTimeSeconds: right.rasterLaunchTimeSeconds
        )
        XCTAssertGreaterThan(abs(leftField.x - rightField.x), 0.5)
    }
}
```

- [ ] **Step 2: Write the failing Boris oracle tests**

Create `WobbulatorKit/Tests/WobbulatorCoreTests/RelativisticBorisOracleTests.swift`:

```swift
import XCTest
@testable import WobbulatorCore

final class RelativisticBorisOracleTests: XCTestCase {
    func testZeroFieldHitsTheIdentityEndpoint() {
        let state = BorisState(
            position: SIMD3(0.0, 0.0, -1.0),
            momentum: SIMD3(0.25, -0.125, 1.0),
            rasterLaunchTimeSeconds: 0.0
        )
        let result = RelativisticBorisOracle.trace(
            initial: state,
            field: .zero,
            steps: 32,
            screenZ: 0.0,
            bounds: 8.0
        )
        XCTAssertEqual(result.termination, .hitScreen)
        XCTAssertEqual(result.state.position.x, 0.25, accuracy: 1e-12)
        XCTAssertEqual(result.state.position.y, -0.125, accuracy: 1e-12)
        XCTAssertEqual(result.state.position.z, 0.0, accuracy: 1e-12)
    }

    func testMagneticOnlyPushConservesMomentum() {
        let result = RelativisticBorisOracle.trace(
            initial: BorisState(
                position: SIMD3(0.0, 0.0, -1.0),
                momentum: SIMD3(0.1, 0.0, 1.0),
                rasterLaunchTimeSeconds: 0.0
            ),
            field: .uniform(SIMD3(0.0, 0.35, 0.0)),
            steps: 512,
            screenZ: 0.0,
            bounds: 8.0
        )
        XCTAssertEqual(result.termination, .hitScreen)
        XCTAssertLessThanOrEqual(result.maximumRelativeMomentumDrift, 1e-12)
    }

    func testDimensionlessFlightKeepsCRTFieldPhaseFrozen() {
        let launch = 7.0 / (60_000.0 / 1_001.0) + 0.000_003
        let result = RelativisticBorisOracle.trace(
            initial: BorisState(
                position: SIMD3(0.0, 0.0, -1.0),
                momentum: SIMD3(0.1, 0.0, 1.0),
                rasterLaunchTimeSeconds: launch
            ),
            field: .sBend(
                amplitude: 0.2,
                angularFrequency: .pi * 120.0,
                phase: 0.0
            ),
            steps: 512,
            screenZ: 0.0,
            bounds: 8.0
        )
        XCTAssertEqual(result.termination, .hitScreen)
        XCTAssertEqual(result.minimumSampledFieldTimeSeconds, launch, accuracy: 0)
        XCTAssertEqual(result.maximumSampledFieldTimeSeconds, launch, accuracy: 0)
        XCTAssertEqual(result.sampledFieldTimeSpanSeconds, 0.0, accuracy: 0)
    }

    func testReversingDipoleReversesHorizontalDeflection() {
        let initial = BorisState(
            position: SIMD3(0.0, 0.0, -1.0),
            momentum: SIMD3(0.0, 0.0, 1.0),
            rasterLaunchTimeSeconds: 0.0
        )
        let positive = RelativisticBorisOracle.trace(
            initial: initial,
            field: .uniform(SIMD3(0.0, 0.1, 0.0)),
            steps: 256,
            screenZ: 0.0,
            bounds: 8.0
        )
        let negative = RelativisticBorisOracle.trace(
            initial: initial,
            field: .uniform(SIMD3(0.0, -0.1, 0.0)),
            steps: 256,
            screenZ: 0.0,
            bounds: 8.0
        )
        XCTAssertEqual(positive.state.position.x, -negative.state.position.x, accuracy: 1e-10)
        XCTAssertEqual(positive.state.position.y, negative.state.position.y, accuracy: 1e-12)
    }

    func testLowForwardMomentumTerminatesBeforeAccumulation() {
        let result = RelativisticBorisOracle.trace(
            initial: BorisState(
                position: SIMD3(0.0, 0.0, -1.0),
                momentum: SIMD3(1.0, 0.0, 0.001),
                rasterLaunchTimeSeconds: 0.0
            ),
            field: .zero,
            steps: 8,
            screenZ: 0.0,
            bounds: 8.0
        )
        XCTAssertEqual(result.termination, .lowForwardMomentum)
    }

    func testNonFiniteFieldNeverProducesAValidEndpoint() {
        let result = RelativisticBorisOracle.trace(
            initial: BorisState(
                position: SIMD3(0.0, 0.0, -1.0),
                momentum: SIMD3(0.0, 0.0, 1.0),
                rasterLaunchTimeSeconds: 0.0
            ),
            field: .uniform(SIMD3(.nan, 0.0, 0.0)),
            steps: 8,
            screenZ: 0.0,
            bounds: 8.0
        )
        XCTAssertEqual(result.termination, .nonFinite)
    }
}
```

- [ ] **Step 3: Run the tests to verify RED**

Run:

```bash
cd WobbulatorKit
swift test --filter CRTTimingTests
swift test --filter RelativisticBorisOracleTests
```

Expected: compilation fails because the timing and oracle types do not exist.

- [ ] **Step 4: Implement resolution-independent raster timing**

Create `WobbulatorKit/Sources/WobbulatorCore/CRTTiming.swift`:

```swift
import Foundation

public enum ScanParity: UInt32, Codable, Equatable, Sendable {
    case even = 0
    case odd = 1
}

public struct RasterSample: Equatable, Sendable {
    public var sourceUV: SIMD2<Double>
    public var rasterLaunchTimeSeconds: Double
    public var dwellTime: Double
    public var sourceCellArea: Double
    public var parity: ScanParity
}

public struct CRTTiming: Equatable, Sendable {
    public var fieldRate: Double
    public var linesPerField: Double
    public var activeLines: Int
    public var activeStartFraction: Double
    public var activeDurationFraction: Double
    public var isInterlaced: Bool

    public init(
        fieldRate: Double,
        linesPerField: Double,
        activeLines: Int,
        activeStartFraction: Double,
        activeDurationFraction: Double,
        isInterlaced: Bool
    ) {
        self.fieldRate = fieldRate
        self.linesPerField = linesPerField
        self.activeLines = activeLines
        self.activeStartFraction = activeStartFraction
        self.activeDurationFraction = activeDurationFraction
        self.isInterlaced = isInterlaced
    }

    public static let ntsc525 = CRTTiming(
        fieldRate: 60_000.0 / 1_001.0,
        linesPerField: 262.5,
        activeLines: 240,
        activeStartFraction: 0.165,
        activeDurationFraction: 0.827,
        isInterlaced: true
    )

    public static let pal625 = CRTTiming(
        fieldRate: 50.0,
        linesPerField: 312.5,
        activeLines: 288,
        activeStartFraction: 0.165,
        activeDurationFraction: 0.8125,
        isInterlaced: true
    )

    public static func progressive(fieldRate: Double, activeLines: Int) -> CRTTiming {
        CRTTiming(
            fieldRate: fieldRate,
            linesPerField: Double(activeLines),
            activeLines: activeLines,
            activeStartFraction: 0.0,
            activeDurationFraction: 1.0,
            isInterlaced: false
        )
    }

    public var fieldDuration: Double { 1.0 / fieldRate }
    public var linePeriod: Double { fieldDuration / linesPerField }

    public func rasterLaunchTimeSeconds(
        normalizedLine: Double,
        horizontal: Double,
        fieldIndex: Int
    ) throws -> Double {
        guard normalizedLine.isFinite, normalizedLine >= 0, normalizedLine < 1 else {
            throw WobbulatorSpikeError.invalidWorkload(
                "normalized line must be in the half-open unit interval"
            )
        }
        guard horizontal.isFinite, horizontal >= 0, horizontal <= 1 else {
            throw WobbulatorSpikeError.invalidWorkload(
                "horizontal position must be in the closed unit interval"
            )
        }
        guard fieldIndex >= 0 else {
            throw WobbulatorSpikeError.invalidWorkload("field index must be nonnegative")
        }
        let fieldStart = Double(fieldIndex) * fieldDuration
        return fieldStart
            + normalizedLine * Double(activeLines) * linePeriod
            + activeStartFraction * linePeriod
            + horizontal * activeDurationFraction * linePeriod
    }

    public func sample(
        line: Int,
        x: Int,
        activeSamples: Int,
        fieldIndex: Int
    ) throws -> RasterSample {
        guard activeSamples > 0 else {
            throw WobbulatorSpikeError.invalidWorkload("active samples must be positive")
        }
        guard line >= 0, line < activeLines else {
            throw WobbulatorSpikeError.invalidWorkload("line is outside the active interval")
        }
        guard x >= 0, x < activeSamples else {
            throw WobbulatorSpikeError.invalidWorkload("sample is outside the active interval")
        }
        guard fieldIndex >= 0 else {
            throw WobbulatorSpikeError.invalidWorkload("field index must be nonnegative")
        }

        let parity: ScanParity = fieldIndex.isMultiple(of: 2) ? .even : .odd
        let horizontal = (Double(x) + 0.5) / Double(activeSamples)
        let activeDuration = activeDurationFraction * linePeriod
        let rasterLaunchTimeSeconds = try rasterLaunchTimeSeconds(
            normalizedLine: Double(line) / Double(activeLines),
            horizontal: horizontal,
            fieldIndex: fieldIndex
        )

        let sourceY: Double
        let frameLines: Int
        if isInterlaced {
            frameLines = activeLines * 2
            sourceY = (Double(line * 2) + Double(parity.rawValue) + 0.5) / Double(frameLines)
        } else {
            frameLines = activeLines
            sourceY = (Double(line) + 0.5) / Double(frameLines)
        }

        return RasterSample(
            sourceUV: SIMD2(horizontal, sourceY),
            rasterLaunchTimeSeconds: rasterLaunchTimeSeconds,
            dwellTime: activeDuration / Double(activeSamples),
            sourceCellArea: 1.0 / Double(activeSamples * frameLines),
            parity: parity
        )
    }
}
```

The active fractions above are Phase 1 fixture values, not calibrated hardware claims. The
decision report must label them as such; Phase 3 replaces or confirms them from cited timing
references without changing the absolute beam-time formula.

The CPU oracle keeps absolute raster launch seconds in `Double`. Task 3 must not cast a late
absolute launch time to `Float`: Swift reduces the field-start oscillator phase modulo 2 pi in
`Double`, and Metal receives that small phase origin plus the within-field launch offset. This
preserves horizontal phase at ten-minute field indices instead of quantizing it to roughly a line.

- [ ] **Step 5: Implement the relativistic magnetic Boris oracle**

Create `WobbulatorKit/Sources/WobbulatorCore/RelativisticBorisOracle.swift`:

```swift
import Foundation
import simd

public enum OracleField: Equatable, Sendable {
    case zero
    case uniform(SIMD3<Double>)
    case sBend(amplitude: Double, angularFrequency: Double, phase: Double)

    public func magneticField(
        at position: SIMD3<Double>,
        rasterLaunchTimeSeconds: Double
    ) -> SIMD3<Double> {
        switch self {
        case .zero:
            return .zero
        case .uniform(let field):
            return field
        case .sBend(let amplitude, let angularFrequency, let phase):
            let envelope = max(0.0, 1.0 - 0.25 * position.z * position.z)
            return SIMD3(
                amplitude * envelope
                    * sin(angularFrequency * rasterLaunchTimeSeconds + phase),
                0.0,
                0.0
            )
        }
    }
}

public struct BorisState: Equatable, Sendable {
    public var position: SIMD3<Double>
    public var momentum: SIMD3<Double>
    public let rasterLaunchTimeSeconds: Double

    public init(
        position: SIMD3<Double>,
        momentum: SIMD3<Double>,
        rasterLaunchTimeSeconds: Double
    ) {
        self.position = position
        self.momentum = momentum
        self.rasterLaunchTimeSeconds = rasterLaunchTimeSeconds
    }
}

public enum BorisTermination: String, Codable, Equatable, Sendable {
    case hitScreen
    case lowForwardMomentum
    case outOfBounds
    case nonFinite
    case stepLimit
}

public struct BorisResult: Equatable, Sendable {
    public var state: BorisState
    public var termination: BorisTermination
    public var maximumRelativeMomentumDrift: Double
    public var minimumSampledFieldTimeSeconds: Double
    public var maximumSampledFieldTimeSeconds: Double

    public var sampledFieldTimeSpanSeconds: Double {
        maximumSampledFieldTimeSeconds - minimumSampledFieldTimeSeconds
    }
}

public enum RelativisticBorisOracle {
    private static let charge = -1.0
    private static let mass = 1.0
    private static let speedOfLight = 1.0

    public static func trace(
        initial: BorisState,
        field: OracleField,
        steps: Int,
        screenZ: Double,
        bounds: Double
    ) -> BorisResult {
        guard steps > 0, isFinite(initial.position), isFinite(initial.momentum),
            initial.rasterLaunchTimeSeconds.isFinite
        else {
            return result(
                state: initial,
                termination: .nonFinite,
                drift: .infinity,
                minimumFieldTime: initial.rasterLaunchTimeSeconds,
                maximumFieldTime: initial.rasterLaunchTimeSeconds
            )
        }

        var state = initial
        var minimumFieldTime = Double.infinity
        var maximumFieldTime = -Double.infinity
        let initialMagnitude = simd_length(initial.momentum)
        guard initialMagnitude > 0,
            initial.momentum.z / initialMagnitude > 0.01
        else {
            return result(
                state: state,
                termination: .lowForwardMomentum,
                drift: 0.0,
                minimumFieldTime: initial.rasterLaunchTimeSeconds,
                maximumFieldTime: initial.rasterLaunchTimeSeconds
            )
        }

        let initialGamma = gamma(for: initial.momentum)
        let initialVelocityZ = initial.momentum.z / (initialGamma * mass)
        guard initialVelocityZ > 0 else {
            return result(
                state: state,
                termination: .lowForwardMomentum,
                drift: 0.0,
                minimumFieldTime: initial.rasterLaunchTimeSeconds,
                maximumFieldTime: initial.rasterLaunchTimeSeconds
            )
        }
        let flightDuration = (screenZ - initial.position.z) / initialVelocityZ * 1.25
        let dt = flightDuration / Double(steps)
        var maximumDrift = 0.0

        for _ in 0..<steps {
            if state.momentum.z / initialMagnitude <= 0.01 {
                return result(
                    state: state,
                    termination: .lowForwardMomentum,
                    drift: maximumDrift,
                    minimumFieldTime: minimumFieldTime,
                    maximumFieldTime: maximumFieldTime
                )
            }

            let previous = state
            let fieldTime = initial.rasterLaunchTimeSeconds
            minimumFieldTime = min(minimumFieldTime, fieldTime)
            maximumFieldTime = max(maximumFieldTime, fieldTime)
            let magnetic = field.magneticField(
                at: state.position,
                rasterLaunchTimeSeconds: fieldTime
            )
            guard isFinite(magnetic) else {
                return result(
                    state: state,
                    termination: .nonFinite,
                    drift: .infinity,
                    minimumFieldTime: minimumFieldTime,
                    maximumFieldTime: maximumFieldTime
                )
            }

            let g = gamma(for: state.momentum)
            let t = magnetic * (charge * dt / (2.0 * mass * g))
            let s = 2.0 * t / (1.0 + simd_dot(t, t))
            let prime = state.momentum + simd_cross(state.momentum, t)
            state.momentum += simd_cross(prime, s)
            let newGamma = gamma(for: state.momentum)
            state.position += state.momentum / (newGamma * mass) * dt

            guard isFinite(state.position), isFinite(state.momentum) else {
                return result(
                    state: previous,
                    termination: .nonFinite,
                    drift: .infinity,
                    minimumFieldTime: minimumFieldTime,
                    maximumFieldTime: maximumFieldTime
                )
            }

            maximumDrift = max(
                maximumDrift,
                abs(simd_length(state.momentum) - initialMagnitude) / initialMagnitude
            )

            if max(max(abs(state.position.x), abs(state.position.y)), abs(state.position.z)) > bounds {
                return result(
                    state: state,
                    termination: .outOfBounds,
                    drift: maximumDrift,
                    minimumFieldTime: minimumFieldTime,
                    maximumFieldTime: maximumFieldTime
                )
            }

            if state.position.z >= screenZ {
                let denominator = state.position.z - previous.position.z
                let fraction = denominator == 0 ? 0 : (screenZ - previous.position.z) / denominator
                state.position = previous.position + (state.position - previous.position) * fraction
                state.position.z = screenZ
                return result(
                    state: state,
                    termination: .hitScreen,
                    drift: maximumDrift,
                    minimumFieldTime: minimumFieldTime,
                    maximumFieldTime: maximumFieldTime
                )
            }
        }

        return result(
            state: state,
            termination: .stepLimit,
            drift: maximumDrift,
            minimumFieldTime: minimumFieldTime,
            maximumFieldTime: maximumFieldTime
        )
    }

    private static func result(
        state: BorisState,
        termination: BorisTermination,
        drift: Double,
        minimumFieldTime: Double,
        maximumFieldTime: Double
    ) -> BorisResult {
        let minimum = minimumFieldTime.isFinite
            ? minimumFieldTime : state.rasterLaunchTimeSeconds
        let maximum = maximumFieldTime.isFinite
            ? maximumFieldTime : state.rasterLaunchTimeSeconds
        return BorisResult(
            state: state,
            termination: termination,
            maximumRelativeMomentumDrift: drift,
            minimumSampledFieldTimeSeconds: minimum,
            maximumSampledFieldTimeSeconds: maximum
        )
    }

    private static func gamma(for momentum: SIMD3<Double>) -> Double {
        sqrt(
            1.0
                + simd_dot(momentum, momentum)
                    / (mass * mass * speedOfLight * speedOfLight)
        )
    }

    private static func isFinite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
```

- [ ] **Step 6: Run the focused tests to verify GREEN**

Run:

```bash
cd WobbulatorKit
swift test --filter CRTTimingTests
swift test --filter RelativisticBorisOracleTests
```

Expected: all timing and oracle tests pass. If the conservation assertion fails above `1e-12`,
diagnose the integrator; do not loosen the approved production bound of `0.00001`.

- [ ] **Step 7: Prove the conservation test can fail**

Temporarily change the momentum update in `RelativisticBorisOracle.swift` from the Boris rotation to
forward Euler:

```swift
state.momentum += charge * simd_cross(state.momentum, magnetic) * dt
```

Run:

```bash
cd WobbulatorKit
swift test --filter RelativisticBorisOracleTests/testMagneticOnlyPushConservesMomentum
```

Expected: FAIL on `maximumRelativeMomentumDrift`. Restore the Boris rotation and rerun the same
test; expected: PASS.

- [ ] **Step 8: Format, lint, run the package suite, and commit**

Run:

```bash
cd WobbulatorKit
swift format format --in-place --recursive Sources Tests
swift format lint --strict --recursive Sources Tests
swift test
swift build -c release
git add Sources/WobbulatorCore/CRTTiming.swift \
  Sources/WobbulatorCore/RelativisticBorisOracle.swift \
  Tests/WobbulatorCoreTests/CRTTimingTests.swift \
  Tests/WobbulatorCoreTests/RelativisticBorisOracleTests.swift
git commit -m "spike: add CRT timing and Boris oracle"
```

Expected: all package tests pass and the release library builds.

---

### Task 3: Prove the common GPU pusher and Gaussian point depositor

**Files:**
- Modify: `WobbulatorKit/Package.swift`
- Create: `WobbulatorKit/Sources/WobbulatorMetal/MetalABI.swift`
- Create: `WobbulatorKit/Sources/WobbulatorMetal/MetalResourceFactory.swift`
- Create: `WobbulatorKit/Sources/WobbulatorMetal/Shaders/WobbulatorSpike.metal`
- Create: `WobbulatorKit/Sources/WobbulatorMetal/WobbulatorMetalRenderer.swift`
- Create: `WobbulatorKit/Tests/WobbulatorMetalTests/MetalOracleTests.swift`
- Create: `WobbulatorKit/Tests/WobbulatorMetalTests/ForwardDepositionTests.swift`

**Interfaces:**
- Consumes: all Task 1 workload contracts and Task 2's CPU oracle.
- Produces:
  - `MetalSpikeUniforms` and `MetalBeamSample`, each pinned by stride tests
  - `WobbulatorMetalRenderer.init(device:) throws`
  - `WobbulatorMetalRenderer.prepare(_:) throws -> PreparedSpikeCase`
  - `PreparedSpikeCase.render(frameIndex:) throws -> FrameTiming`
  - `PreparedSpikeCase.endpointSnapshot() throws -> [MetalBeamSample]`
  - `PreparedSpikeCase.outputRGBA16Bits() throws -> [UInt16]`
  - `PreparedSpikeCase.resourceCreationSnapshot -> MetalResourceCreationCounts`
  Task 4 adds two pipelines behind the same `prepare` and `render` interface. Task 5 benchmarks only
  this interface.

- [ ] **Step 1: Add the Metal target and its failing tests**

Replace `WobbulatorKit/Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WobbulatorKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WobbulatorCore", targets: ["WobbulatorCore"]),
        .library(name: "WobbulatorMetal", targets: ["WobbulatorMetal"]),
    ],
    targets: [
        .target(name: "WobbulatorCore"),
        .target(
            name: "WobbulatorMetal",
            dependencies: ["WobbulatorCore"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(
            name: "WobbulatorCoreTests",
            dependencies: ["WobbulatorCore"]
        ),
        .testTarget(
            name: "WobbulatorMetalTests",
            dependencies: ["WobbulatorCore", "WobbulatorMetal"]
        ),
    ]
)
```

Create `WobbulatorKit/Tests/WobbulatorMetalTests/MetalOracleTests.swift`:

```swift
import Foundation
import Metal
import simd
import XCTest
@testable import WobbulatorCore
@testable import WobbulatorMetal

final class MetalOracleTests: XCTestCase {
    func testMetalABIStridesArePinned() {
        XCTAssertEqual(MemoryLayout<MetalSpikeUniforms>.stride, 80)
        XCTAssertEqual(MemoryLayout<MetalBeamSample>.stride, 32)
    }

    func testMetalABIRejectsOutOfRangeFrameIndicesWithoutTrapping() throws {
        let workload = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 8, height: 4),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixture: .identity,
            representation: .gaussianPointSprite
        )
        XCTAssertThrowsError(try MetalSpikeUniforms(workload: workload, frameIndex: -1))
        if Int.max > Int(UInt32.max) {
            XCTAssertThrowsError(
                try MetalSpikeUniforms(
                    workload: workload,
                    frameIndex: Int(UInt32.max) + 1
                )
            )
        }
    }

    func testMetalABIRejectsFiniteValuesThatOverflowOrUnderflowFloat() throws {
        let workload = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 8, height: 4),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1e300,
            fixtureAmount: 1e300,
            fixture: .identity,
            representation: .gaussianPointSprite
        )
        XCTAssertThrowsError(try MetalSpikeUniforms(workload: workload, frameIndex: 0))
        let underflow = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 8, height: 4),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1e-300,
            fixture: .identity,
            representation: .gaussianPointSprite
        )
        XCTAssertThrowsError(try MetalSpikeUniforms(workload: underflow, frameIndex: 0))
    }

    func testGPUIdentityEndpointsMatchTheDoubleOracle() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 8, height: 4),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixture: .identity,
            representation: .gaussianPointSprite
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let gpu = try prepared.endpointSnapshot()
        XCTAssertEqual(gpu.count, workload.samples.count)

        var oracleSquaredError = 0.0
        var oracleMaximumError = 0.0
        var identitySquaredError = 0.0
        var identityMaximumError = 0.0
        for y in 0..<workload.samples.height {
            for x in 0..<workload.samples.width {
                let index = y * workload.samples.width + x
                let u = (Double(x) + 0.5) / Double(workload.samples.width)
                let v = (Double(y) + 0.5) / Double(workload.samples.height)
                let source = SIMD2(u * 2.0 - 1.0, v * 2.0 - 1.0)
                let cpu = RelativisticBorisOracle.trace(
                    initial: BorisState(
                        position: SIMD3(0.0, 0.0, -1.0),
                        momentum: SIMD3(source.x, source.y, 1.0),
                        rasterLaunchTimeSeconds: 0.0
                    ),
                    field: .zero,
                    steps: workload.integrationSteps,
                    screenZ: 0.0,
                    bounds: 8.0
                )
                XCTAssertEqual(cpu.termination, .hitScreen)
                let oracleExpected = SIMD2(
                    (cpu.state.position.x * 0.5 + 0.5) * Double(workload.output.width),
                    (cpu.state.position.y * 0.5 + 0.5) * Double(workload.output.height)
                )
                let analyticIdentity = SIMD2(
                    u * Double(workload.output.width),
                    v * Double(workload.output.height)
                )
                let actual = SIMD2(
                    Double(gpu[index].destinationAndUV.x),
                    Double(gpu[index].destinationAndUV.y)
                )
                let oracleError = simd_length(actual - oracleExpected)
                oracleSquaredError += oracleError * oracleError
                oracleMaximumError = max(oracleMaximumError, oracleError)
                let identityError = simd_length(actual - analyticIdentity)
                identitySquaredError += identityError * identityError
                identityMaximumError = max(identityMaximumError, identityError)
                XCTAssertEqual(gpu[index].energyValidityDrift.y, 1.0)
                XCTAssertLessThanOrEqual(
                    Double(gpu[index].energyValidityDrift.z),
                    SpikeThresholds.approved.relativeMomentumDrift
                )
            }
        }
        let oracleRMS = sqrt(oracleSquaredError / Double(gpu.count))
        let identityRMS = sqrt(identitySquaredError / Double(gpu.count))
        XCTAssertLessThanOrEqual(oracleRMS, SpikeThresholds.approved.oracleRMSPixels)
        XCTAssertLessThanOrEqual(
            oracleMaximumError,
            SpikeThresholds.approved.oracleMaxPixels
        )
        XCTAssertLessThanOrEqual(identityRMS, SpikeThresholds.approved.identityRMSPixels)
        XCTAssertLessThanOrEqual(
            identityMaximumError,
            SpikeThresholds.approved.identityMaxPixels
        )
    }
}
```

Create `WobbulatorKit/Tests/WobbulatorMetalTests/ForwardDepositionTests.swift`:

```swift
import Metal
import XCTest
@testable import WobbulatorCore
@testable import WobbulatorMetal

final class ForwardDepositionTests: XCTestCase {
    func testPointOutputIsFiniteAndOpaqueIncludingBlackPixels() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: RasterSize(width: 320, height: 180),
            samples: SampleGrid(width: 80, height: 45),
            integrationSteps: 16,
            beamWidthPixelsAt1080: 1.25,
            fixture: .identity,
            representation: .gaussianPointSprite
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let bits = try prepared.outputRGBA16Bits()
        XCTAssertEqual(bits.count, workload.output.width * workload.output.height * 4)
        var blackPixelCount = 0
        var litPixelCount = 0
        var integratedRGB = 0.0
        for index in stride(from: 0, to: bits.count, by: 4) {
            let red = Float(Float16(bitPattern: bits[index]))
            let green = Float(Float16(bitPattern: bits[index + 1]))
            let blue = Float(Float16(bitPattern: bits[index + 2]))
            let alpha = Float(Float16(bitPattern: bits[index + 3]))
            XCTAssertTrue(red.isFinite && green.isFinite && blue.isFinite)
            XCTAssertEqual(alpha, 1.0)
            if red == 0, green == 0, blue == 0 { blackPixelCount += 1 }
            let energy = Double(red + green + blue)
            integratedRGB += energy
            if energy > 0 { litPixelCount += 1 }
        }
        XCTAssertGreaterThan(blackPixelCount, 0)
        XCTAssertGreaterThan(litPixelCount, 0)
        XCTAssertGreaterThan(integratedRGB, 0)
    }

    func testInvalidRaysUseFiniteOffscreenSentinels() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: RasterSize(width: 320, height: 180),
            samples: SampleGrid(width: 16, height: 8),
            integrationSteps: 16,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: 10_000.0,
            fixture: .dipole,
            representation: .gaussianPointSprite
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let endpoints = try prepared.endpointSnapshot()
        let invalid = endpoints.filter { $0.energyValidityDrift.y == 0 }
        XCTAssertFalse(invalid.isEmpty)
        XCTAssertTrue(invalid.allSatisfy {
            $0.destinationAndUV.x.isFinite && $0.destinationAndUV.y.isFinite
                && $0.destinationAndUV.x == -10_000.0
                && $0.destinationAndUV.y == -10_000.0
        })
    }

    func testRenderCreatesNoPersistentMetalResources() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: RasterSize(width: 320, height: 180),
            samples: SampleGrid(width: 80, height: 45),
            integrationSteps: 16,
            beamWidthPixelsAt1080: 1.25,
            fixture: .identity,
            representation: .gaussianPointSprite
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let before = prepared.resourceCreationSnapshot
        _ = try prepared.render(frameIndex: 1)
        _ = try prepared.render(frameIndex: 2)
        XCTAssertEqual(prepared.resourceCreationSnapshot - before, .zero)
    }

    func testMetalCreationCannotBypassTheCountedFactory() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = packageRoot.appendingPathComponent("Sources/WobbulatorMetal")
        let methods = [
            "makeCommandQueue",
            "makeBuffer",
            "makeTexture",
            "makeLibrary",
            "makeComputePipelineState",
            "makeRenderPipelineState",
        ]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
        )
        var hits: [String] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift"
            && url.lastPathComponent != "MetalResourceFactory.swift"
        {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (lineNumber, line) in source.split(separator: "\n").enumerated() {
                for method in methods {
                    let call = ".\(method)("
                    guard line.contains(call), !line.contains("resources\(call)") else {
                        continue
                    }
                    hits.append("\(url.lastPathComponent):\(lineNumber + 1): \(call)")
                }
            }
        }
        XCTAssertEqual(hits, [])
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
cd WobbulatorKit
swift test --filter MetalOracleTests
swift test --filter ForwardDepositionTests
```

Expected: compilation fails because the Metal ABI and renderer do not exist.

- [ ] **Step 3: Implement and pin the Swift/Metal ABI**

Create `WobbulatorKit/Sources/WobbulatorMetal/MetalABI.swift`:

```swift
import Foundation
import WobbulatorCore

public struct MetalSpikeUniforms: Sendable {
    public var counts: SIMD4<UInt32>
    public var integration: SIMD4<UInt32>
    public var beam: SIMD4<Float>
    public var timing: SIMD4<Float>
    public var field: SIMD4<Float>

    public init(workload: SpikeWorkload, frameIndex: Int) throws {
        guard let encodedFrameIndex = UInt32(exactly: frameIndex),
            let sampleWidth = UInt32(exactly: workload.samples.width),
            let sampleHeight = UInt32(exactly: workload.samples.height),
            let outputWidth = UInt32(exactly: workload.output.width),
            let outputHeight = UInt32(exactly: workload.output.height),
            let integrationSteps = UInt32(exactly: workload.integrationSteps)
        else {
            throw WobbulatorSpikeError.invalidArguments(
                "workload counts and frame index must fit the nonnegative UInt32 Metal ABI"
            )
        }
        let outputArea = workload.output.width.multipliedReportingOverflow(
            by: workload.output.height
        )
        let sampleArea = workload.samples.width.multipliedReportingOverflow(
            by: workload.samples.height
        )
        guard !outputArea.overflow, !sampleArea.overflow, sampleArea.partialValue > 0 else {
            throw WobbulatorSpikeError.invalidWorkload("workload area overflow")
        }
        let timingFixture = CRTTiming.ntsc525
        let angularFrequency = Double.pi * 120.0
        let fieldStartSeconds = Double(frameIndex) * timingFixture.fieldDuration
        let phaseAtFieldStart = (angularFrequency * fieldStartSeconds)
            .truncatingRemainder(dividingBy: 2.0 * .pi)
        let beamWidth = Float(workload.beamWidthPixels)
        let fixtureAmount = Float(workload.fixtureAmount)
        let energy = Float(outputArea.partialValue) / Float(sampleArea.partialValue)
        guard beamWidth.isFinite, beamWidth > 0,
            fixtureAmount.isFinite, energy.isFinite, energy > 0,
            phaseAtFieldStart.isFinite
        else {
            throw WobbulatorSpikeError.invalidWorkload(
                "workload values must remain finite in the Float Metal ABI"
            )
        }
        counts = SIMD4(
            sampleWidth,
            sampleHeight,
            outputWidth,
            outputHeight
        )
        integration = SIMD4(
            integrationSteps,
            workload.fixture.metalIndex,
            workload.representation.metalIndex,
            encodedFrameIndex
        )
        beam = SIMD4(
            beamWidth,
            fixtureAmount,
            energy,
            Float(CRTTiming.ntsc525.activeLines)
        )
        timing = SIMD4(
            Float(timingFixture.fieldRate),
            Float(timingFixture.linesPerField),
            Float(timingFixture.activeStartFraction),
            Float(timingFixture.activeDurationFraction)
        )
        field = SIMD4(
            fixtureAmount,
            Float(angularFrequency),
            Float(phaseAtFieldStart),
            8.0
        )
    }
}

public struct MetalBeamSample: Sendable {
    public var destinationAndUV: SIMD4<Float>
    public var energyValidityDrift: SIMD4<Float>
}

extension SpikeFixture {
    fileprivate var metalIndex: UInt32 {
        switch self {
        case .identity: 0
        case .dipole: 1
        case .sBend: 2
        case .fold: 3
        case .branchOverlap: 4
        }
    }
}

extension DepositionRepresentation {
    fileprivate var metalIndex: UInt32 {
        switch self {
        case .gaussianPointSprite: 0
        case .scanlineRibbon: 1
        case .adaptiveScanlineSegment: 2
        }
    }
}
```

- [ ] **Step 4: Implement counted Metal resource creation**

Create `WobbulatorKit/Sources/WobbulatorMetal/MetalResourceFactory.swift`:

```swift
import Foundation
import Metal
import simd
import WobbulatorCore

public final class MetalResourceFactory {
    private let device: MTLDevice
    private let lock = NSLock()
    private var counts = MetalResourceCreationCounts.zero

    public init(device: MTLDevice) {
        self.device = device
    }

    public var snapshot: MetalResourceCreationCounts {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    func makeCommandQueue() -> MTLCommandQueue? {
        record { $0.commandQueues += 1 }
        return device.makeCommandQueue()
    }

    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        record { $0.buffers += 1 }
        return device.makeBuffer(length: length, options: options)
    }

    func makeBuffer(
        bytes: UnsafeRawPointer,
        length: Int,
        options: MTLResourceOptions
    ) -> MTLBuffer? {
        record { $0.buffers += 1 }
        return device.makeBuffer(bytes: bytes, length: length, options: options)
    }

    func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        record { $0.textures += 1 }
        return device.makeTexture(descriptor: descriptor)
    }

    func makeLibrary(source: String) throws -> MTLLibrary {
        record { $0.libraries += 1 }
        return try device.makeLibrary(source: source, options: nil)
    }

    func makeComputePipelineState(function: MTLFunction) throws -> MTLComputePipelineState {
        record { $0.computePipelines += 1 }
        return try device.makeComputePipelineState(function: function)
    }

    func makeRenderPipelineState(
        descriptor: MTLRenderPipelineDescriptor
    ) throws -> MTLRenderPipelineState {
        record { $0.renderPipelines += 1 }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func record(_ update: (inout MetalResourceCreationCounts) -> Void) {
        lock.lock()
        update(&counts)
        lock.unlock()
    }
}
```

All explicit Metal queue, buffer, texture, library, and pipeline creation in this package must go
through this factory. Command buffers, encoders, and render-pass descriptors are deliberately not
counted because the Phase 1 contract permits those frame-scoped objects.

- [ ] **Step 5: Implement the endpoint, point-deposition, and finalize shaders**

Create `WobbulatorKit/Sources/WobbulatorMetal/Shaders/WobbulatorSpike.metal`:

```metal
#include <metal_stdlib>
using namespace metal;

struct SpikeUniforms {
    uint4 counts;
    uint4 integration;
    float4 beam;
    float4 timing;
    float4 field;
};

struct BeamSample {
    float4 destinationAndUV;
    float4 energyValidityDrift;
};

inline float relativisticGamma(float3 momentum) {
    return sqrt(1.0f + dot(momentum, momentum));
}

inline float3 fixtureField(
    uint fixture,
    float amount,
    float angularFrequency,
    float phaseAtFieldStart,
    float3 position,
    float withinFieldLaunchTimeSeconds
) {
    if (fixture == 1u) return float3(0.0f, amount, 0.0f);
    if (fixture == 2u) {
        float envelope = max(0.0f, 1.0f - 0.25f * position.z * position.z);
        return float3(
            amount * envelope
                * sin(phaseAtFieldStart + angularFrequency * withinFieldLaunchTimeSeconds),
            0.0f,
            0.0f
        );
    }
    return float3(0.0f);
}

kernel void spike_integrate(
    device BeamSample *samples [[buffer(0)]],
    constant SpikeUniforms &u [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    uint sampleCount = u.counts.x * u.counts.y;
    if (gid >= sampleCount) return;

    uint x = gid % u.counts.x;
    uint y = gid / u.counts.x;
    float2 uv = (float2(x, y) + 0.5f) / float2(u.counts.xy);
    float2 source = uv * 2.0f - 1.0f;
    float3 position = float3(0.0f, 0.0f, -1.0f);
    float3 momentum = float3(source, 1.0f);
    float initialMagnitude = length(momentum);
    float initialGamma = relativisticGamma(momentum);
    float flightDuration = 1.25f / (momentum.z / initialGamma);
    float dt = flightDuration / float(u.integration.x);
    float linePeriod = 1.0f / (u.timing.x * u.timing.y);
    float normalizedLine = float(y) / float(u.counts.y);
    float withinFieldLaunchTimeSeconds = normalizedLine * u.beam.w * linePeriod
        + u.timing.z * linePeriod
        + uv.x * u.timing.w * linePeriod;
    float frozenFieldPhaseRadians = u.field.z
        + u.field.y * withinFieldLaunchTimeSeconds;
    float maximumDrift = 0.0f;
    bool valid = true;
    bool hit = false;

    for (uint step = 0u; step < u.integration.x; ++step) {
        if (momentum.z / initialMagnitude <= 0.01f) {
            valid = false;
            break;
        }
        float3 previous = position;
        float3 magnetic = fixtureField(
            u.integration.y,
            u.field.x,
            u.field.y,
            u.field.z,
            position,
            withinFieldLaunchTimeSeconds
        );
        float gamma = relativisticGamma(momentum);
        float3 t = -magnetic * (dt / (2.0f * gamma));
        float3 s = 2.0f * t / (1.0f + dot(t, t));
        float3 prime = momentum + cross(momentum, t);
        momentum += cross(prime, s);
        position += momentum / relativisticGamma(momentum) * dt;
        maximumDrift = max(maximumDrift, abs(length(momentum) - initialMagnitude) / initialMagnitude);

        if (!all(isfinite(position)) || !all(isfinite(momentum))
            || max(max(abs(position.x), abs(position.y)), abs(position.z)) > u.field.w) {
            valid = false;
            break;
        }
        if (position.z >= 0.0f) {
            float denominator = position.z - previous.z;
            float fraction = denominator == 0.0f ? 0.0f : -previous.z / denominator;
            position = mix(previous, position, fraction);
            position.z = 0.0f;
            hit = true;
            break;
        }
    }

    valid = valid && hit;
    float2 destination = (position.xy * 0.5f + 0.5f) * float2(u.counts.zw);
    if (u.integration.y == 3u && valid) {
        destination.x += u.beam.y * float(u.counts.z) * sin(uv.x * 2.0f * M_PI_F);
    }
    if (u.integration.y == 4u && valid) {
        destination.x = fract(uv.x * 2.0f) * float(u.counts.z);
    }
    if (!valid || !all(isfinite(destination))) {
        valid = false;
        destination = float2(-10000.0f);
    }
    samples[gid].destinationAndUV = float4(destination, uv);
    samples[gid].energyValidityDrift = float4(
        u.beam.z,
        valid ? 1.0f : 0.0f,
        maximumDrift,
        frozenFieldPhaseRadians
    );
}

struct PointVertexOut {
    float4 position [[position]];
    float2 deltaPixels;
    float2 sourceUV;
    float energy;
};

vertex PointVertexOut spike_point_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const BeamSample *samples [[buffer(0)]],
    constant SpikeUniforms &u [[buffer(1)]]
) {
    constexpr float2 corners[6] = {
        float2(-1.0f, -1.0f), float2(1.0f, -1.0f), float2(-1.0f, 1.0f),
        float2(-1.0f, 1.0f), float2(1.0f, -1.0f), float2(1.0f, 1.0f)
    };
    BeamSample sample = samples[instanceID];
    float2 corner = corners[vertexID];
    float2 delta = corner * u.beam.x * 3.0f;
    float2 pixel = sample.destinationAndUV.xy + delta;
    bool active = sample.energyValidityDrift.y == 1.0f
        && all(isfinite(sample.destinationAndUV.xy));
    if (!active) pixel = float2(-10000.0f);
    float2 clip = float2(
        pixel.x / float(u.counts.z) * 2.0f - 1.0f,
        1.0f - pixel.y / float(u.counts.w) * 2.0f
    );
    PointVertexOut out;
    out.position = float4(clip, 0.0f, 1.0f);
    out.deltaPixels = delta;
    out.sourceUV = sample.destinationAndUV.zw;
    out.energy = active ? sample.energyValidityDrift.x : 0.0f;
    return out;
}

fragment float4 spike_point_fragment(
    PointVertexOut in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant SpikeUniforms &u [[buffer(1)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float sigma = u.beam.x;
    float radiusSquared = dot(in.deltaPixels, in.deltaPixels);
    float weight = exp(-0.5f * radiusSquared / (sigma * sigma))
        / (2.0f * M_PI_F * sigma * sigma);
    float3 color = source.sample(linearSampler, in.sourceUV).rgb;
    return float4(color * in.energy * weight, in.energy * weight);
}

kernel void spike_finalize(
    texture2d<float, access::read> accumulation [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    float3 color = max(accumulation.read(gid).rgb, 0.0f);
    output.write(half4(half3(color), half(1.0f)), gid);
}
```

- [ ] **Step 6: Implement one-time pipelines, persistent resources, and whole-buffer timing**

Create `WobbulatorKit/Sources/WobbulatorMetal/WobbulatorMetalRenderer.swift`:

```swift
import Foundation
import Metal
import WobbulatorCore

public struct FrameTiming: Equatable, Sendable {
    public var gpuMilliseconds: Double
    public var cpuMilliseconds: Double
}

public final class WobbulatorMetalRenderer {
    private let resources: MetalResourceFactory
    private let queue: MTLCommandQueue
    private let integrate: MTLComputePipelineState
    private let point: MTLRenderPipelineState
    private let finalize: MTLComputePipelineState

    public init(
        device: MTLDevice,
        resources: MetalResourceFactory? = nil
    ) throws {
        let resources = resources ?? MetalResourceFactory(device: device)
        self.resources = resources
        guard let queue = resources.makeCommandQueue() else {
            throw WobbulatorSpikeError.resourceAllocation("command queue")
        }
        self.queue = queue
        guard let url = Bundle.module.url(
            forResource: "WobbulatorSpike",
            withExtension: "metal",
            subdirectory: "Shaders"
        ) else {
            throw WobbulatorSpikeError.shaderResourceMissing
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let library: MTLLibrary
        do {
            library = try resources.makeLibrary(source: source)
        } catch {
            throw WobbulatorSpikeError.shaderCompilation(error.localizedDescription)
        }

        func required(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else {
                throw WobbulatorSpikeError.pipelineCreation("missing function \(name)")
            }
            return function
        }

        do {
            integrate = try resources.makeComputePipelineState(
                function: required("spike_integrate")
            )
            finalize = try resources.makeComputePipelineState(
                function: required("spike_finalize")
            )
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = try required("spike_point_vertex")
            descriptor.fragmentFunction = try required("spike_point_fragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .rgba16Float
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
            point = try resources.makeRenderPipelineState(descriptor: descriptor)
        } catch let error as WobbulatorSpikeError {
            throw error
        } catch {
            throw WobbulatorSpikeError.pipelineCreation(error.localizedDescription)
        }
    }

    public func prepare(_ workload: SpikeWorkload) throws -> PreparedSpikeCase {
        guard workload.representation == .gaussianPointSprite else {
            throw WobbulatorSpikeError.invalidWorkload(
                "Task 3 supports gaussianPointSprite; Task 4 adds the other representations"
            )
        }
        return try PreparedSpikeCase(
            resources: resources,
            queue: queue,
            integrate: integrate,
            render: point,
            finalize: finalize,
            workload: workload
        )
    }
}

public final class PreparedSpikeCase {
    public let workload: SpikeWorkload
    public let allocatedBytes: Int
    public var resourceCreationSnapshot: MetalResourceCreationCounts { resources.snapshot }
    public var primitiveInstancesPerFrame: Int { workload.samples.count }
    public var fieldEvaluationsPerFrame: Int {
        workload.samples.count * workload.integrationSteps
    }

    private let queue: MTLCommandQueue
    private let resources: MetalResourceFactory
    private let integrate: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let finalize: MTLComputePipelineState
    private let sampleBuffer: MTLBuffer
    private let uniformBuffer: MTLBuffer
    private let sourceTexture: MTLTexture
    private let accumulationTexture: MTLTexture
    private let outputTexture: MTLTexture

    fileprivate init(
        resources: MetalResourceFactory,
        queue: MTLCommandQueue,
        integrate: MTLComputePipelineState,
        render: MTLRenderPipelineState,
        finalize: MTLComputePipelineState,
        workload: SpikeWorkload
    ) throws {
        self.workload = workload
        self.queue = queue
        self.resources = resources
        self.integrate = integrate
        renderPipeline = render
        self.finalize = finalize

        let sampleBytes = workload.samples.count * MemoryLayout<MetalBeamSample>.stride
        guard let samples = resources.makeBuffer(
            length: sampleBytes,
            options: .storageModePrivate
        ),
            let uniforms = resources.makeBuffer(
                length: MemoryLayout<MetalSpikeUniforms>.stride,
                options: .storageModeShared
            )
        else {
            throw WobbulatorSpikeError.resourceAllocation("sample or uniform buffer")
        }
        sampleBuffer = samples
        uniformBuffer = uniforms

        func texture(
            size: RasterSize,
            usage: MTLTextureUsage,
            storage: MTLStorageMode = .private
        ) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: size.width,
                height: size.height,
                mipmapped: false
            )
            descriptor.usage = usage
            descriptor.storageMode = storage
            guard let result = resources.makeTexture(descriptor: descriptor) else {
                throw WobbulatorSpikeError.resourceAllocation("\(size.width)x\(size.height) texture")
            }
            return result
        }

        sourceTexture = try texture(
            size: RasterSize(width: workload.samples.width, height: workload.samples.height),
            usage: .shaderRead
        )
        accumulationTexture = try texture(
            size: workload.output,
            usage: [.renderTarget, .shaderRead]
        )
        outputTexture = try texture(
            size: workload.output,
            usage: [.shaderRead, .shaderWrite]
        )

        let sourceBits = Self.makeSourceBits(
            grid: workload.samples,
            pattern: workload.sourcePattern
        )
        let staging = sourceBits.withUnsafeBytes { raw in
            resources.makeBuffer(
                bytes: raw.baseAddress!,
                length: raw.count,
                options: .storageModeShared
            )
        }
        guard let staging, let upload = queue.makeCommandBuffer(),
            let blit = upload.makeBlitCommandEncoder()
        else {
            throw WobbulatorSpikeError.resourceAllocation("source upload")
        }
        blit.copy(
            from: staging,
            sourceOffset: 0,
            sourceBytesPerRow: workload.samples.width * 8,
            sourceBytesPerImage: workload.samples.width * workload.samples.height * 8,
            sourceSize: MTLSize(
                width: workload.samples.width,
                height: workload.samples.height,
                depth: 1
            ),
            to: sourceTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        upload.commit()
        upload.waitUntilCompleted()
        guard upload.status == .completed else {
            throw WobbulatorSpikeError.commandFailure(
                upload.error?.localizedDescription ?? "source upload did not complete"
            )
        }

        allocatedBytes = sampleBytes + MemoryLayout<MetalSpikeUniforms>.stride
            + workload.samples.width * workload.samples.height * 8
            + workload.output.width * workload.output.height * 16
    }

    public func render(frameIndex: Int) throws -> FrameTiming {
        var uniforms = try MetalSpikeUniforms(workload: workload, frameIndex: frameIndex)
        withUnsafeBytes(of: &uniforms) { bytes in
            uniformBuffer.contents().copyMemory(
                from: bytes.baseAddress!,
                byteCount: bytes.count
            )
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw WobbulatorSpikeError.commandEncoding("command buffer")
        }
        let clock = ContinuousClock()
        let cpuStart = clock.now

        guard let compute = commandBuffer.makeComputeCommandEncoder() else {
            throw WobbulatorSpikeError.commandEncoding("integrator")
        }
        compute.setComputePipelineState(integrate)
        compute.setBuffer(sampleBuffer, offset: 0, index: 0)
        compute.setBuffer(uniformBuffer, offset: 0, index: 1)
        let threads = MTLSize(width: workload.samples.count, height: 1, depth: 1)
        let group = MTLSize(width: integrate.threadExecutionWidth, height: 1, depth: 1)
        compute.dispatchThreads(threads, threadsPerThreadgroup: group)
        compute.endEncoding()

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = accumulationTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw WobbulatorSpikeError.commandEncoding("point deposition")
        }
        render.setRenderPipelineState(renderPipeline)
        render.setVertexBuffer(sampleBuffer, offset: 0, index: 0)
        render.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        render.setFragmentTexture(sourceTexture, index: 0)
        render.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        render.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: workload.samples.count
        )
        render.endEncoding()

        guard let finish = commandBuffer.makeComputeCommandEncoder() else {
            throw WobbulatorSpikeError.commandEncoding("finalize")
        }
        finish.setComputePipelineState(finalize)
        finish.setTexture(accumulationTexture, index: 0)
        finish.setTexture(outputTexture, index: 1)
        finish.dispatchThreads(
            MTLSize(width: workload.output.width, height: workload.output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        finish.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let cpuDuration = cpuStart.duration(to: clock.now)
        guard commandBuffer.status == .completed else {
            throw WobbulatorSpikeError.commandFailure(
                commandBuffer.error?.localizedDescription ?? "frame did not complete"
            )
        }
        return FrameTiming(
            gpuMilliseconds: (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000.0,
            cpuMilliseconds: Double(cpuDuration.components.seconds) * 1_000.0
                + Double(cpuDuration.components.attoseconds) / 1e15
        )
    }

    public func endpointSnapshot() throws -> [MetalBeamSample] {
        let count = workload.samples.count
        let size = count * MemoryLayout<MetalBeamSample>.stride
        guard let destination = resources.makeBuffer(
            length: size,
            options: .storageModeShared
        ),
            let commandBuffer = queue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw WobbulatorSpikeError.resourceAllocation("endpoint readback")
        }
        blit.copy(
            from: sampleBuffer,
            sourceOffset: 0,
            to: destination,
            destinationOffset: 0,
            size: size
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw WobbulatorSpikeError.commandFailure("endpoint readback")
        }
        let pointer = destination.contents().bindMemory(
            to: MetalBeamSample.self,
            capacity: count
        )
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    public func outputRGBA16Bits() throws -> [UInt16] {
        let size = workload.output.width * workload.output.height * 8
        guard let device = resources.makeBuffer(length: size, options: .storageModeShared),
            let commandBuffer = queue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw WobbulatorSpikeError.resourceAllocation("output readback")
        }
        blit.copy(
            from: outputTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(
                width: workload.output.width,
                height: workload.output.height,
                depth: 1
            ),
            to: device,
            destinationOffset: 0,
            destinationBytesPerRow: workload.output.width * 8,
            destinationBytesPerImage: size
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw WobbulatorSpikeError.commandFailure("output readback")
        }
        let pointer = device.contents().bindMemory(to: UInt16.self, capacity: size / 2)
        return Array(UnsafeBufferPointer(start: pointer, count: size / 2))
    }

    private static func makeSourceBits(
        grid: SampleGrid,
        pattern: SpikeSourcePattern
    ) -> [UInt16] {
        var bits = [UInt16](repeating: 0, count: grid.count * 4)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let u = Float(x) / Float(max(grid.width - 1, 1))
                let v = Float(y) / Float(max(grid.height - 1, 1))
                let color: SIMD3<Float>
                switch pattern {
                case .colorGrid:
                    let band = min(Int(u * 3.0), 2)
                    let gridLine = x.isMultiple(of: max(grid.width / 16, 1))
                        || y.isMultiple(of: max(grid.height / 16, 1))
                    var gridColor = SIMD3<Float>(repeating: 0.05)
                    gridColor[band] = gridLine ? 1.0 : 0.7
                    gridColor += SIMD3(repeating: v * 0.1)
                    color = gridColor
                case .solidWhite:
                    color = SIMD3(repeating: 1.0)
                case .leftRedOnly:
                    color = x < grid.width / 2 ? SIMD3(1.0, 0.0, 0.0) : .zero
                case .rightGreenOnly:
                    color = x >= grid.width / 2 ? SIMD3(0.0, 1.0, 0.0) : .zero
                case .twoBranchRedGreen:
                    color = x < grid.width / 2
                        ? SIMD3(1.0, 0.0, 0.0) : SIMD3(0.0, 1.0, 0.0)
                }
                let index = (y * grid.width + x) * 4
                bits[index] = Float16(color.x).bitPattern
                bits[index + 1] = Float16(color.y).bitPattern
                bits[index + 2] = Float16(color.z).bitPattern
                bits[index + 3] = Float16(1.0).bitPattern
            }
        }
        return bits
    }
}
```

- [ ] **Step 7: Run the focused tests to verify GREEN**

Run:

```bash
cd WobbulatorKit
swift test --filter MetalOracleTests
swift test --filter ForwardDepositionTests/testPointOutputIsFiniteAndOpaqueIncludingBlackPixels
```

Expected: ABI, CPU/GPU endpoint, momentum, finite-output, alpha, and black-coverage assertions pass
on the M5 Max.

- [ ] **Step 8: Add permanent dipole and S-bend parity cases**

Add these permanent cases to `MetalOracleTests.swift` before performing any mutation:

```swift
func testGPUDipoleEndpointsMatchTheDoubleOracle() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let renderer = try WobbulatorMetalRenderer(device: device)
    let workload = try SpikeWorkload(
        output: .hd1080,
        samples: SampleGrid(width: 4, height: 2),
        integrationSteps: 256,
        beamWidthPixelsAt1080: 1.25,
        fixtureAmount: 0.35,
        fixture: .dipole,
        representation: .gaussianPointSprite
    )
    let prepared = try renderer.prepare(workload)
    _ = try prepared.render(frameIndex: 0)
    let gpu = try prepared.endpointSnapshot()

    for y in 0..<workload.samples.height {
        for x in 0..<workload.samples.width {
            let index = y * workload.samples.width + x
            let u = (Double(x) + 0.5) / Double(workload.samples.width)
            let v = (Double(y) + 0.5) / Double(workload.samples.height)
            let source = SIMD2(u * 2.0 - 1.0, v * 2.0 - 1.0)
            let cpu = RelativisticBorisOracle.trace(
                initial: BorisState(
                    position: SIMD3(0.0, 0.0, -1.0),
                    momentum: SIMD3(source.x, source.y, 1.0),
                    rasterLaunchTimeSeconds: 0.0
                ),
                field: .uniform(SIMD3(0.0, workload.fixtureAmount, 0.0)),
                steps: workload.integrationSteps,
                screenZ: 0.0,
                bounds: 8.0
            )
            XCTAssertEqual(cpu.termination, .hitScreen)
            let expected = SIMD2(
                (cpu.state.position.x * 0.5 + 0.5) * Double(workload.output.width),
                (cpu.state.position.y * 0.5 + 0.5) * Double(workload.output.height)
            )
            let actual = SIMD2(
                Double(gpu[index].destinationAndUV.x),
                Double(gpu[index].destinationAndUV.y)
            )
            XCTAssertLessThanOrEqual(
                simd_length(actual - expected),
                SpikeThresholds.approved.oracleMaxPixels
            )
        }
    }
}

func testGPUSBendEndpointsUseTheExactCRTTimingAndOracleField() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let renderer = try WobbulatorMetalRenderer(device: device)
    let workload = try SpikeWorkload(
        output: .hd1080,
        samples: SampleGrid(width: 4, height: 4),
        integrationSteps: 256,
        beamWidthPixelsAt1080: 1.25,
        fixtureAmount: 0.2,
        fixture: .sBend,
        representation: .gaussianPointSprite
    )
    let fieldIndex = 36_000
    let prepared = try renderer.prepare(workload)
    _ = try prepared.render(frameIndex: fieldIndex)
    let gpu = try prepared.endpointSnapshot()
    for y in 0..<workload.samples.height {
        for x in 0..<workload.samples.width {
            let index = y * workload.samples.width + x
            let u = (Double(x) + 0.5) / Double(workload.samples.width)
            let v = (Double(y) + 0.5) / Double(workload.samples.height)
            let rasterLaunchTimeSeconds = try CRTTiming.ntsc525.rasterLaunchTimeSeconds(
                normalizedLine: Double(y) / Double(workload.samples.height),
                horizontal: u,
                fieldIndex: fieldIndex
            )
            let cpu = RelativisticBorisOracle.trace(
                initial: BorisState(
                    position: SIMD3(0.0, 0.0, -1.0),
                    momentum: SIMD3(u * 2.0 - 1.0, v * 2.0 - 1.0, 1.0),
                    rasterLaunchTimeSeconds: rasterLaunchTimeSeconds
                ),
                field: .sBend(
                    amplitude: workload.fixtureAmount,
                    angularFrequency: .pi * 120.0,
                    phase: 0.0
                ),
                steps: workload.integrationSteps,
                screenZ: 0.0,
                bounds: 8.0
            )
            XCTAssertEqual(cpu.termination, .hitScreen)
            XCTAssertEqual(cpu.sampledFieldTimeSpanSeconds, 0.0, accuracy: 0)
            let angularFrequency = Double.pi * 120.0
            let fieldStartSeconds = Double(fieldIndex) * CRTTiming.ntsc525.fieldDuration
            let phaseAtFieldStart = (angularFrequency * fieldStartSeconds)
                .truncatingRemainder(dividingBy: 2.0 * .pi)
            let expectedFrozenPhase = phaseAtFieldStart
                + angularFrequency * (rasterLaunchTimeSeconds - fieldStartSeconds)
            XCTAssertEqual(
                Double(gpu[index].energyValidityDrift.w),
                expectedFrozenPhase,
                accuracy: 1e-5
            )
            let expected = SIMD2(
                (cpu.state.position.x * 0.5 + 0.5) * Double(workload.output.width),
                (cpu.state.position.y * 0.5 + 0.5) * Double(workload.output.height)
            )
            let actual = SIMD2(
                Double(gpu[index].destinationAndUV.x),
                Double(gpu[index].destinationAndUV.y)
            )
            XCTAssertLessThanOrEqual(
                simd_length(actual - expected),
                SpikeThresholds.approved.oracleMaxPixels
            )
        }
    }
}
```

Run:

```bash
cd WobbulatorKit
swift test --filter MetalOracleTests/testGPUDipoleEndpointsMatchTheDoubleOracle
swift test --filter MetalOracleTests/testGPUSBendEndpointsUseTheExactCRTTimingAndOracleField
```

Expected: both permanent CPU/GPU parity cases pass before mutation.

- [ ] **Step 9: Prove the charge-sign and allocation guards can fail**

Temporarily change the Metal charge sign in `spike_integrate` from:

```metal
float3 t = -magnetic * (dt / (2.0f * gamma));
```

to:

```metal
float3 t = magnetic * (dt / (2.0f * gamma));
```

Run:

```bash
cd WobbulatorKit
swift test --filter MetalOracleTests/testGPUDipoleEndpointsMatchTheDoubleOracle
```

Expected: FAIL on endpoint parity. Restore the negative charge sign and rerun; expected: PASS.

Then temporarily insert this line as the first statement in `PreparedSpikeCase.render`:

```swift
_ = resources.makeBuffer(length: 16, options: .storageModePrivate)
```

Run:

```bash
swift test --filter ForwardDepositionTests/testRenderCreatesNoPersistentMetalResources
```

Expected: FAIL because the counted buffer delta is one. Remove the mutation and rerun; expected:
PASS. This proves the steady-state allocation guard observes the render call site rather than an
immutable byte estimate.

Finally, temporarily insert this aliased raw bypass in `render`:

```swift
let uncountedDevice = outputTexture.device
_ = uncountedDevice.makeBuffer(length: 16, options: .storageModePrivate)
```

Run:

```bash
swift test --filter ForwardDepositionTests/testMetalCreationCannotBypassTheCountedFactory
```

Expected: FAIL with `.makeBuffer(` named in the hit. Remove the mutation and rerun; expected:
PASS. The counter plus this full-source policy test cover both compliant creation and bypasses.

- [ ] **Step 10: Format, lint, test, build, and commit**

Run:

```bash
cd WobbulatorKit
swift format format --in-place --recursive Sources Tests
swift format lint --strict --recursive Sources Tests
swift test
swift build -c release
git add Package.swift Sources/WobbulatorMetal \
  Tests/WobbulatorMetalTests/MetalOracleTests.swift \
  Tests/WobbulatorMetalTests/ForwardDepositionTests.swift
git commit -m "spike: add point-sprite Metal renderer"
```

Expected: the complete package suite passes and the release Metal library builds.

---

### Task 4: Add ribbons, adaptive segments, and representation-invariant image metrics

**Files:**
- Modify: `WobbulatorKit/Sources/WobbulatorMetal/MetalABI.swift`
- Modify: `WobbulatorKit/Sources/WobbulatorMetal/Shaders/WobbulatorSpike.metal`
- Modify: `WobbulatorKit/Sources/WobbulatorMetal/WobbulatorMetalRenderer.swift`
- Create: `WobbulatorKit/Sources/WobbulatorMetal/HDRMetrics.swift`
- Create: `WobbulatorKit/Sources/WobbulatorMetal/CPUForwardDepositionReference.swift`
- Modify: `WobbulatorKit/Tests/WobbulatorMetalTests/MetalOracleTests.swift`
- Modify: `WobbulatorKit/Tests/WobbulatorMetalTests/ForwardDepositionTests.swift`
- Create: `WobbulatorKit/Tests/WobbulatorMetalTests/HDRMetricsTests.swift`

**Interfaces:**
- Consumes: Task 3's `prepare`, `render`, and `outputRGBA16Bits` API.
- Produces:
  - `MetalBeamSegment` with a pinned 48-byte stride
  - all three `DepositionRepresentation` cases accepted by `prepare`
  - `HDRImage`, `HDRMetrics`, and `HDRComparison`
  - `CPUForwardDepositionReference.render(_:) throws -> HDRImage`
  - a canonical GPU-reference authority test that must pass before matrix comparisons
  - `HDRImage.writePreviewPPM(to:maxWidth:)`
  Task 5 records these metrics without adding a representation-specific path.

- [ ] **Step 1: Write the failing cross-representation tests**

Replace `WobbulatorKit/Tests/WobbulatorMetalTests/ForwardDepositionTests.swift` with:

```swift
import Foundation
import Metal
import simd
import XCTest
@testable import WobbulatorCore
@testable import WobbulatorMetal

final class ForwardDepositionTests: XCTestCase {
    private func image(
        representation: DepositionRepresentation,
        fixture: SpikeFixture = .identity,
        samples: SampleGrid = SampleGrid(width: 160, height: 90),
        output: RasterSize = RasterSize(width: 640, height: 360),
        sourcePattern: SpikeSourcePattern = .colorGrid
    ) throws -> HDRImage {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: output,
            samples: samples,
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: fixture == .fold ? 0.42 : 0.35,
            fixture: fixture,
            sourcePattern: sourcePattern,
            representation: representation
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        return try HDRImage(
            width: workload.output.width,
            height: workload.output.height,
            rgba16Bits: prepared.outputRGBA16Bits()
        )
    }

    func testEveryRepresentationIsFiniteAndOpaqueIncludingBlackPixels() throws {
        for representation in DepositionRepresentation.allCases {
            let rendered = try image(representation: representation)
            XCTAssertTrue(rendered.pixels.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w == 1.0
            }, representation.rawValue)
            XCTAssertTrue(rendered.pixels.contains {
                $0.x == 0 && $0.y == 0 && $0.z == 0 && $0.w == 1.0
            }, representation.rawValue)
            let metrics = try HDRMetrics.analyze(rendered)
            XCTAssertGreaterThan(metrics.integratedExposure, 0, representation.rawValue)
            XCTAssertGreaterThan(metrics.litPixelCount, 0, representation.rawValue)
        }
    }

    func testCanonicalAdaptiveReferenceMatchesIndependentCPUDepositor() throws {
        let output = RasterSize.hd1080
        let workload = try SpikeWorkload(
            output: output,
            samples: SampleGrid(width: 160, height: 90),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: 0.42,
            fixture: .fold,
            sourcePattern: .solidWhite,
            representation: .adaptiveScanlineSegment
        )
        let gpu = try image(
            representation: workload.representation,
            fixture: workload.fixture,
            samples: workload.samples,
            output: output,
            sourcePattern: .solidWhite
        )
        let cpu = try CPUForwardDepositionReference.render(workload, frameIndex: 0)
        let gpuMetrics = try HDRMetrics.analyze(gpu)
        let cpuMetrics = try HDRMetrics.analyze(cpu)
        let comparison = try gpuMetrics.compare(to: cpuMetrics)
        let diagnosticScale = Double(output.height) / 1080.0
        XCTAssertLessThanOrEqual(
            comparison.relativeExposureDelta,
            SpikeThresholds.approved.exposureDeltaFraction
        )
        XCTAssertLessThanOrEqual(
            comparison.centroidDistancePixels,
            SpikeThresholds.approved.centroidPixels1080 * diagnosticScale
        )
        XCTAssertLessThanOrEqual(
            comparison.contourSymmetricMeanDistancePixels,
            SpikeThresholds.approved.contourPixels1080 * diagnosticScale
        )
    }

    func testFoldRetainsMultipleSourceColorBranches() throws {
        for representation in DepositionRepresentation.allCases {
            let left = try image(
                representation: representation,
                fixture: .branchOverlap,
                sourcePattern: .leftRedOnly
            )
            let right = try image(
                representation: representation,
                fixture: .branchOverlap,
                sourcePattern: .rightGreenOnly
            )
            let both = try image(
                representation: representation,
                fixture: .branchOverlap,
                sourcePattern: .twoBranchRedGreen
            )
            var coLocatedContributionPixels = 0
            for y in (left.height / 4)..<(left.height * 3 / 4) {
                for x in (left.width / 4)..<(left.width * 3 / 4) {
                    let index = y * left.width + x
                    let leftRed = left.pixels[index].x
                    let rightGreen = right.pixels[index].y
                    guard leftRed > 1e-6, rightGreen > 1e-6 else { continue }
                    coLocatedContributionPixels += 1
                    XCTAssertEqual(
                        both.pixels[index].x,
                        leftRed,
                        accuracy: max(1e-4, leftRed * 0.01)
                    )
                    XCTAssertEqual(
                        both.pixels[index].y,
                        rightGreen,
                        accuracy: max(1e-4, rightGreen * 0.01)
                    )
                }
            }
            XCTAssertGreaterThan(
                coLocatedContributionPixels,
                100,
                "\(representation.rawValue) did not retain both branches in the known ROI"
            )
        }
    }

    func testMetalBeamSegmentStrideIsPinned() {
        XCTAssertEqual(MemoryLayout<MetalBeamSegment>.stride, 48)
        XCTAssertEqual(MemoryLayout<MetalSpikeUniforms>.stride, 96)
    }

    func testAdaptiveGeometryMeetsItsTrueProbeErrorLimit() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 160, height: 90),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: 0.42,
            fixture: .fold,
            representation: .adaptiveScanlineSegment
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let diagnostics = try prepared.adaptiveDiagnostics()
        XCTAssertTrue(
            diagnostics.completelyClassifies(
                (workload.samples.width - 1) * workload.samples.height
            )
        )
    }

    func testAdaptiveTopologyChoosesOneChordForIdentityAndMoreForCurvature() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)

        func diagnostics(
            fixture: SpikeFixture,
            fixtureAmount: Double,
            samples: SampleGrid
        ) throws -> AdaptiveDiagnostics {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 640, height: 360),
                samples: samples,
                integrationSteps: 32,
                beamWidthPixelsAt1080: 1.25,
                fixtureAmount: fixtureAmount,
                fixture: fixture,
                representation: .adaptiveScanlineSegment
            )
            let prepared = try renderer.prepare(workload)
            _ = try prepared.render(frameIndex: 0)
            return try prepared.adaptiveDiagnostics()
        }

        let identityGrid = SampleGrid(width: 160, height: 90)
        let identity = try diagnostics(
            fixture: .identity,
            fixtureAmount: 0.0,
            samples: identityGrid
        )
        XCTAssertTrue(identity.isFailureFree)
        XCTAssertEqual(
            identity.oneSubdivisionIntervalCount,
            (identityGrid.width - 1) * identityGrid.height
        )
        XCTAssertEqual(identity.twoSubdivisionIntervalCount, 0)
        XCTAssertEqual(identity.fourSubdivisionIntervalCount, 0)

        let curved = try diagnostics(
            fixture: .fold,
            fixtureAmount: 0.42,
            samples: SampleGrid(width: 40, height: 22)
        )
        XCTAssertTrue(curved.completelyClassifies((40 - 1) * 22))
        XCTAssertGreaterThan(
            curved.twoSubdivisionIntervalCount + curved.fourSubdivisionIntervalCount,
            0
        )
    }

    func testAdaptiveInteriorEndpointsAreEvaluatedTrajectoriesNotLinearSubdivisions() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        let workload = try SpikeWorkload(
            output: RasterSize(width: 640, height: 360),
            samples: SampleGrid(width: 40, height: 22),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: 0.42,
            fixture: .fold,
            representation: .adaptiveScanlineSegment
        )
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let segments = try prepared.adaptiveSegmentSnapshot()
        let intervalCount = (workload.samples.width - 1) * workload.samples.height
        XCTAssertEqual(segments.count, intervalCount * 4)
        XCTAssertTrue(segments.allSatisfy { segment in
            let d = segment.destinationAB
            let uv = segment.sourceUVAB
            let e = segment.energyActiveLength
            return d.x.isFinite && d.y.isFinite && d.z.isFinite && d.w.isFinite
                && uv.x.isFinite && uv.y.isFinite && uv.z.isFinite && uv.w.isFinite
                && e.x.isFinite && e.y.isFinite && e.z.isFinite && e.w.isFinite
        })
        var foundNonlinearInteriorKnot = false

        func expectedDestination(_ uv: SIMD2<Double>) throws -> SIMD2<Double> {
            let line = min(
                workload.samples.height - 1,
                max(0, Int(floor(uv.y * Double(workload.samples.height))))
            )
            let launch = try CRTTiming.ntsc525.rasterLaunchTimeSeconds(
                normalizedLine: Double(line) / Double(workload.samples.height),
                horizontal: uv.x,
                fieldIndex: 0
            )
            let oracle = RelativisticBorisOracle.trace(
                initial: BorisState(
                    position: SIMD3(0.0, 0.0, -1.0),
                    momentum: SIMD3(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, 1.0),
                    rasterLaunchTimeSeconds: launch
                ),
                field: .zero,
                steps: workload.integrationSteps,
                screenZ: 0.0,
                bounds: 8.0
            )
            guard oracle.termination == .hitScreen else {
                throw WobbulatorSpikeError.evidenceFailure(
                    "adaptive endpoint oracle did not hit the screen"
                )
            }
            var destination = SIMD2(
                (oracle.state.position.x * 0.5 + 0.5) * Double(workload.output.width),
                (oracle.state.position.y * 0.5 + 0.5) * Double(workload.output.height)
            )
            destination.x += workload.fixtureAmount * Double(workload.output.width)
                * sin(uv.x * 2.0 * .pi)
            return destination
        }

        for intervalStart in stride(from: 0, to: segments.count, by: 4) {
            let active = segments[intervalStart..<(intervalStart + 4)].filter {
                $0.energyActiveLength.y == 1.0
            }
            guard !active.isEmpty else { continue }
            for segment in active {
                let endpoints = [
                    (
                        SIMD2(
                            Double(segment.destinationAB.x),
                            Double(segment.destinationAB.y)
                        ),
                        SIMD2(
                            Double(segment.sourceUVAB.x),
                            Double(segment.sourceUVAB.y)
                        )
                    ),
                    (
                        SIMD2(
                            Double(segment.destinationAB.z),
                            Double(segment.destinationAB.w)
                        ),
                        SIMD2(
                            Double(segment.sourceUVAB.z),
                            Double(segment.sourceUVAB.w)
                        )
                    ),
                ]
                for (actual, uv) in endpoints {
                    XCTAssertLessThanOrEqual(
                        simd_length(actual - (try expectedDestination(uv))),
                        SpikeThresholds.approved.oracleMaxPixels
                    )
                }
            }
            guard active.count > 1, let first = active.first, let last = active.last else {
                continue
            }
            let outerA = SIMD2(
                Double(first.destinationAB.x), Double(first.destinationAB.y)
            )
            let outerB = SIMD2(
                Double(last.destinationAB.z), Double(last.destinationAB.w)
            )
            let sourceA = Double(first.sourceUVAB.x)
            let sourceB = Double(last.sourceUVAB.z)
            for segment in active.dropLast() {
                let u = Double(segment.sourceUVAB.z)
                let t = (u - sourceA) / (sourceB - sourceA)
                let evaluated = SIMD2(
                    Double(segment.destinationAB.z), Double(segment.destinationAB.w)
                )
                let linear = outerA + (outerB - outerA) * t
                if simd_length(evaluated - linear) > 0.25 {
                    foundNonlinearInteriorKnot = true
                }
            }
        }
        XCTAssertTrue(foundNonlinearInteriorKnot)
    }

    func testInvalidRaysKeepFiniteOffscreenSentinelsAfterGeneralization() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        for representation in DepositionRepresentation.allCases {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 320, height: 180),
                samples: SampleGrid(width: 16, height: 8),
                integrationSteps: 16,
                beamWidthPixelsAt1080: 1.25,
                fixtureAmount: 10_000.0,
                fixture: .dipole,
                representation: representation
            )
            let prepared = try renderer.prepare(workload)
            _ = try prepared.render(frameIndex: 0)
            let invalid = try prepared.endpointSnapshot().filter {
                $0.energyValidityDrift.y == 0.0
            }
            XCTAssertFalse(invalid.isEmpty, representation.rawValue)
            XCTAssertTrue(invalid.allSatisfy {
                $0.destinationAndUV.x == -10_000.0
                    && $0.destinationAndUV.y == -10_000.0
                    && $0.destinationAndUV.x.isFinite
                    && $0.destinationAndUV.y.isFinite
            }, representation.rawValue)
        }
    }

    func testEveryRepresentationCreatesNoPersistentMetalResourcesPerFrame() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        for representation in DepositionRepresentation.allCases {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 320, height: 180),
                samples: SampleGrid(width: 80, height: 45),
                integrationSteps: 16,
                beamWidthPixelsAt1080: 1.25,
                fixture: .identity,
                representation: representation
            )
            let prepared = try renderer.prepare(workload)
            _ = try prepared.render(frameIndex: 0)
            let before = prepared.resourceCreationSnapshot
            _ = try prepared.render(frameIndex: 1)
            _ = try prepared.render(frameIndex: 2)
            XCTAssertEqual(
                prepared.resourceCreationSnapshot - before,
                .zero,
                representation.rawValue
            )
        }
    }

    func testEveryRepresentationConsumesTheExactSameEndpointGenerator() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try WobbulatorMetalRenderer(device: device)
        var baseline: [MetalBeamSample]?
        for representation in DepositionRepresentation.allCases {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 640, height: 360),
                samples: SampleGrid(width: 16, height: 8),
                integrationSteps: 32,
                beamWidthPixelsAt1080: 1.25,
                fixtureAmount: 0.2,
                fixture: .sBend,
                representation: representation
            )
            let prepared = try renderer.prepare(workload)
            _ = try prepared.render(frameIndex: 36_000)
            let endpoints = try prepared.endpointSnapshot()
            if let baseline {
                XCTAssertEqual(endpoints.count, baseline.count)
                for (actual, expected) in zip(endpoints, baseline) {
                    XCTAssertEqual(actual.destinationAndUV, expected.destinationAndUV)
                    XCTAssertEqual(actual.energyValidityDrift, expected.energyValidityDrift)
                }
            } else {
                baseline = endpoints
            }
        }
    }

    func testMetalCreationStillCannotBypassTheCountedFactory() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = packageRoot.appendingPathComponent("Sources/WobbulatorMetal")
        let methods = [
            "makeCommandQueue",
            "makeBuffer",
            "makeTexture",
            "makeLibrary",
            "makeComputePipelineState",
            "makeRenderPipelineState",
        ]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
        )
        var hits: [String] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift"
            && url.lastPathComponent != "MetalResourceFactory.swift"
        {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (lineNumber, line) in source.split(separator: "\n").enumerated() {
                for method in methods {
                    let call = ".\(method)("
                    guard line.contains(call), !line.contains("resources\(call)") else {
                        continue
                    }
                    hits.append("\(url.lastPathComponent):\(lineNumber + 1): \(call)")
                }
            }
        }
        XCTAssertEqual(hits, [])
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
cd WobbulatorKit
swift test --filter ForwardDepositionTests
swift test --filter HDRMetricsTests
```

Expected: compilation fails because `HDRImage`, `HDRMetrics`, `MetalBeamSegment`, and the ribbon
pipelines do not exist; `prepare` also rejects the two new representations.

- [ ] **Step 3: Add adaptive-probe parameters and the segment ABI**

Add this stored property after `field` in `MetalSpikeUniforms`:

```swift
public var adaptive: SIMD4<Float>
```

At the end of `MetalSpikeUniforms.init`, add:

```swift
adaptive = SIMD4(0.25, 0.0, 0.0, 0.0)
```

In `MetalOracleTests.testMetalABIStridesArePinned`, change the uniform assertion from 80 to 96;
retain the 32-byte `MetalBeamSample` assertion. This is a deliberate Task 4 ABI evolution.

`adaptive.x` is a 0.25-output-pixel midpoint-error limit. Then append:

```swift
public struct MetalBeamSegment: Sendable {
    public var destinationAB: SIMD4<Float>
    public var sourceUVAB: SIMD4<Float>
    public var energyActiveLength: SIMD4<Float>
}
```

- [ ] **Step 4: Add the direct-ribbon and adaptive-segment shaders**

Insert after `BeamSample` in `WobbulatorSpike.metal`:

```metal
struct BeamSegment {
    float4 destinationAB;
    float4 sourceUVAB;
    float4 energyActiveLength;
};
```

Also add `float4 adaptive;` after `float4 field;` in the existing MSL `SpikeUniforms`; this keeps
the Metal struct at the same 96-byte stride pinned by the Swift test.

Replace the Task 3 `spike_integrate` kernel with this shared sample evaluator plus base-grid and
adaptive-builder use. Each inserted source position computes its own raster launch offset; field
phase is never interpolated from the A-B endpoints:

```metal
inline BeamSample integrateBeamSample(
    float2 uv,
    float normalizedLine,
    constant SpikeUniforms &u
) {
    float2 source = uv * 2.0f - 1.0f;
    float3 position = float3(0.0f, 0.0f, -1.0f);
    float3 momentum = float3(source, 1.0f);
    float initialMagnitude = length(momentum);
    float initialGamma = relativisticGamma(momentum);
    float flightDuration = 1.25f / (momentum.z / initialGamma);
    float dt = flightDuration / float(u.integration.x);
    float linePeriod = 1.0f / (u.timing.x * u.timing.y);
    float withinFieldLaunchTimeSeconds = normalizedLine * u.beam.w * linePeriod
        + u.timing.z * linePeriod
        + uv.x * u.timing.w * linePeriod;
    float frozenFieldPhaseRadians = u.field.z
        + u.field.y * withinFieldLaunchTimeSeconds;
    float maximumDrift = 0.0f;
    bool valid = true;
    bool hit = false;

    for (uint step = 0u; step < u.integration.x; ++step) {
        if (momentum.z / initialMagnitude <= 0.01f) {
            valid = false;
            break;
        }
        float3 previous = position;
        float3 magnetic = fixtureField(
            u.integration.y,
            u.field.x,
            u.field.y,
            u.field.z,
            position,
            withinFieldLaunchTimeSeconds
        );
        float gamma = relativisticGamma(momentum);
        float3 t = -magnetic * (dt / (2.0f * gamma));
        float3 s = 2.0f * t / (1.0f + dot(t, t));
        float3 prime = momentum + cross(momentum, t);
        momentum += cross(prime, s);
        position += momentum / relativisticGamma(momentum) * dt;
        maximumDrift = max(
            maximumDrift,
            abs(length(momentum) - initialMagnitude) / initialMagnitude
        );

        if (!all(isfinite(position)) || !all(isfinite(momentum))
            || !isfinite(maximumDrift)
            || max(max(abs(position.x), abs(position.y)), abs(position.z)) > u.field.w) {
            valid = false;
            break;
        }
        if (position.z >= 0.0f) {
            float denominator = position.z - previous.z;
            float fraction = denominator == 0.0f ? 0.0f : -previous.z / denominator;
            position = mix(previous, position, fraction);
            position.z = 0.0f;
            hit = true;
            break;
        }
    }

    valid = valid && hit;
    float2 destination = (position.xy * 0.5f + 0.5f) * float2(u.counts.zw);
    if (u.integration.y == 3u && valid) {
        destination.x += u.beam.y * float(u.counts.z) * sin(uv.x * 2.0f * M_PI_F);
    }
    if (u.integration.y == 4u && valid) {
        destination.x = fract(uv.x * 2.0f) * float(u.counts.z);
    }
    if (!valid || !all(isfinite(destination))) {
        valid = false;
        destination = float2(-10000.0f);
    }

    BeamSample result;
    result.destinationAndUV = float4(destination, uv);
    result.energyValidityDrift = float4(
        u.beam.z,
        valid ? 1.0f : 0.0f,
        maximumDrift,
        frozenFieldPhaseRadians
    );
    return result;
}

kernel void spike_integrate(
    device BeamSample *samples [[buffer(0)]],
    constant SpikeUniforms &u [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    uint sampleCount = u.counts.x * u.counts.y;
    if (gid >= sampleCount) return;
    uint x = gid % u.counts.x;
    uint y = gid / u.counts.x;
    float2 uv = (float2(x, y) + 0.5f) / float2(u.counts.xy);
    samples[gid] = integrateBeamSample(uv, float(y) / float(u.counts.y), u);
}

```

Insert before `spike_finalize`:

```metal
struct RibbonVertexOut {
    float4 position [[position]];
    float distancePixels;
    float2 sourceUV;
    float energy;
    float segmentLength;
};

inline RibbonVertexOut makeRibbonVertex(
    float2 destinationA,
    float2 destinationB,
    float2 sourceA,
    float2 sourceB,
    float energy,
    float active,
    uint vertexID,
    constant SpikeUniforms &u
) {
    constexpr float2 corners[6] = {
        float2(0.0f, -1.0f), float2(1.0f, -1.0f), float2(0.0f, 1.0f),
        float2(0.0f, 1.0f), float2(1.0f, -1.0f), float2(1.0f, 1.0f)
    };
    float2 axis = destinationB - destinationA;
    float rawLength = length(axis);
    float2 tangent = rawLength > 1e-5f ? axis / rawLength : float2(1.0f, 0.0f);
    float segmentLength = max(rawLength, 1.0f);
    float2 center = (destinationA + destinationB) * 0.5f;
    float2 a = center - tangent * segmentLength * 0.5f;
    float2 b = center + tangent * segmentLength * 0.5f;
    float2 normal = float2(-tangent.y, tangent.x);
    float2 corner = corners[vertexID];
    float2 pixel = mix(a, b, corner.x) + normal * corner.y * u.beam.x * 3.0f;
    if (active == 0.0f) pixel = float2(-10000.0f);
    float2 clip = float2(
        pixel.x / float(u.counts.z) * 2.0f - 1.0f,
        1.0f - pixel.y / float(u.counts.w) * 2.0f
    );
    RibbonVertexOut out;
    out.position = float4(clip, 0.0f, 1.0f);
    out.distancePixels = corner.y * u.beam.x * 3.0f;
    out.sourceUV = mix(sourceA, sourceB, corner.x);
    out.energy = energy * active;
    out.segmentLength = segmentLength;
    return out;
}

vertex RibbonVertexOut spike_ribbon_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const BeamSample *samples [[buffer(0)]],
    constant SpikeUniforms &u [[buffer(1)]]
) {
    uint segmentsPerLine = u.counts.x - 1u;
    uint line = instanceID / segmentsPerLine;
    uint x = instanceID % segmentsPerLine;
    uint indexA = line * u.counts.x + x;
    uint indexB = indexA + 1u;
    BeamSample a = samples[indexA];
    BeamSample b = samples[indexB];
    float active = a.energyValidityDrift.y * b.energyValidityDrift.y;
    float baseEnergy = a.energyValidityDrift.x * float(u.counts.x) / float(segmentsPerLine);
    return makeRibbonVertex(
        a.destinationAndUV.xy,
        b.destinationAndUV.xy,
        a.destinationAndUV.zw,
        b.destinationAndUV.zw,
        baseEnergy,
        active,
        vertexID,
        u
    );
}

inline bool validBeamSample(BeamSample sample) {
    return sample.energyValidityDrift.y == 1.0f
        && all(isfinite(sample.destinationAndUV.xy));
}

inline float pointChordError(
    BeamSample point,
    BeamSample a,
    BeamSample b,
    float t
) {
    return distance(
        point.destinationAndUV.xy,
        mix(a.destinationAndUV.xy, b.destinationAndUV.xy, t)
    );
}

kernel void spike_build_adaptive_segments(
    device const BeamSample *samples [[buffer(0)]],
    constant SpikeUniforms &u [[buffer(1)]],
    device BeamSegment *segments [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    uint segmentsPerLine = u.counts.x - 1u;
    uint baseCount = segmentsPerLine * u.counts.y;
    if (gid >= baseCount) return;
    uint line = gid / segmentsPerLine;
    uint x = gid % segmentsPerLine;
    uint indexA = line * u.counts.x + x;
    float xA = (float(x) + 0.5f) / float(u.counts.x);
    float xB = (float(x + 1u) + 0.5f) / float(u.counts.x);
    float sourceY = (float(line) + 0.5f) / float(u.counts.y);
    float normalizedLine = float(line) / float(u.counts.y);

    BeamSample knot[9];
    knot[0] = samples[indexA];
    for (uint index = 0u; index < 7u; ++index) {
        float t = float(index + 1u) * 0.125f;
        knot[index + 1u] = integrateBeamSample(
            float2(mix(xA, xB, t), sourceY),
            normalizedLine,
            u
        );
    }
    knot[8] = samples[indexA + 1u];

    bool allValid = true;
    for (uint index = 0u; index < 9u; ++index) {
        allValid = allValid && validBeamSample(knot[index]);
    }
    uint subdivisions = 4u;
    float candidateOneError = 1e20f;
    float candidateTwoError = 1e20f;
    float candidateFourError = 1e20f;
    if (allValid) {
        candidateOneError = 0.0f;
        for (uint index = 1u; index < 8u; ++index) {
            candidateOneError = max(
                candidateOneError,
                pointChordError(knot[index], knot[0], knot[8], float(index) * 0.125f)
            );
        }
        candidateTwoError = max(
            max(
                pointChordError(knot[1], knot[0], knot[4], 0.25f),
                pointChordError(knot[2], knot[0], knot[4], 0.50f)
            ),
            max(
                pointChordError(knot[3], knot[0], knot[4], 0.75f),
                max(
                    pointChordError(knot[5], knot[4], knot[8], 0.25f),
                    max(
                        pointChordError(knot[6], knot[4], knot[8], 0.50f),
                        pointChordError(knot[7], knot[4], knot[8], 0.75f)
                    )
                )
            )
        );
        candidateFourError = max(
            max(
                pointChordError(knot[1], knot[0], knot[2], 0.5f),
                pointChordError(knot[3], knot[2], knot[4], 0.5f)
            ),
            max(
                pointChordError(knot[5], knot[4], knot[6], 0.5f),
                pointChordError(knot[7], knot[6], knot[8], 0.5f)
            )
        );
        subdivisions = candidateOneError <= u.adaptive.x ? 1u
            : candidateTwoError <= u.adaptive.x ? 2u : 4u;
    }
    bool toleranceFailure = allValid && subdivisions == 4u
        && candidateFourError > u.adaptive.x;
    float baseEnergy = knot[0].energyValidityDrift.x
        * float(u.counts.x) / float(segmentsPerLine);

    for (uint slot = 0u; slot < 4u; ++slot) {
        uint startIndex = 0u;
        uint endIndex = 0u;
        bool enabled = slot < subdivisions;
        if (!enabled) {
            startIndex = 0u;
            endIndex = 0u;
        } else if (subdivisions == 1u) {
            startIndex = 0u;
            endIndex = 8u;
        } else if (subdivisions == 2u) {
            startIndex = slot * 4u;
            endIndex = startIndex + 4u;
        } else {
            startIndex = slot * 2u;
            endIndex = startIndex + 2u;
        }
        enabled = enabled && allValid
            && validBeamSample(knot[startIndex])
            && validBeamSample(knot[endIndex]);
        float projectedLength = enabled
            ? distance(
                knot[startIndex].destinationAndUV.xy,
                knot[endIndex].destinationAndUV.xy
            ) : 0.0f;
        BeamSegment segment;
        segment.destinationAB = float4(
            knot[startIndex].destinationAndUV.xy,
            knot[endIndex].destinationAndUV.xy
        );
        segment.sourceUVAB = float4(
            knot[startIndex].destinationAndUV.zw,
            knot[endIndex].destinationAndUV.zw
        );
        segment.energyActiveLength = float4(
            enabled ? baseEnergy / float(subdivisions) : 0.0f,
            enabled ? 1.0f : 0.0f,
            projectedLength,
            slot == 0u ? (toleranceFailure ? 1.0f : (allValid ? 0.0f : 2.0f)) : 0.0f
        );
        segments[gid * 4u + slot] = segment;
    }
}

vertex RibbonVertexOut spike_segment_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const BeamSegment *segments [[buffer(0)]],
    constant SpikeUniforms &u [[buffer(1)]]
) {
    BeamSegment segment = segments[instanceID];
    return makeRibbonVertex(
        segment.destinationAB.xy,
        segment.destinationAB.zw,
        segment.sourceUVAB.xy,
        segment.sourceUVAB.zw,
        segment.energyActiveLength.x,
        segment.energyActiveLength.y,
        vertexID,
        u
    );
}

fragment float4 spike_ribbon_fragment(
    RibbonVertexOut in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant SpikeUniforms &u [[buffer(1)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float sigma = u.beam.x;
    float normalWeight = exp(-0.5f * in.distancePixels * in.distancePixels / (sigma * sigma))
        / (sqrt(2.0f * M_PI_F) * sigma);
    float weight = normalWeight / max(in.segmentLength, 1.0f);
    float3 color = source.sample(linearSampler, in.sourceUV).rgb;
    return float4(color * in.energy * weight, in.energy * weight);
}
```

- [ ] **Step 5: Generalize pipeline creation and prepared-case encoding**

In `WobbulatorMetalRenderer`, add these stored properties:

```swift
private let ribbon: MTLRenderPipelineState
private let adaptive: MTLRenderPipelineState
private let buildAdaptive: MTLComputePipelineState
```

Replace the point-pipeline construction inside `init` with this exact block:

```swift
func additivePipeline(vertex: String, fragment: String) throws -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = try required(vertex)
    descriptor.fragmentFunction = try required(fragment)
    let attachment = descriptor.colorAttachments[0]!
    attachment.pixelFormat = .rgba16Float
    attachment.isBlendingEnabled = true
    attachment.rgbBlendOperation = .add
    attachment.alphaBlendOperation = .add
    attachment.sourceRGBBlendFactor = .one
    attachment.destinationRGBBlendFactor = .one
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationAlphaBlendFactor = .one
    return try resources.makeRenderPipelineState(descriptor: descriptor)
}

do {
    integrate = try resources.makeComputePipelineState(function: required("spike_integrate"))
    finalize = try resources.makeComputePipelineState(function: required("spike_finalize"))
    buildAdaptive = try resources.makeComputePipelineState(
        function: required("spike_build_adaptive_segments")
    )
    point = try additivePipeline(
        vertex: "spike_point_vertex",
        fragment: "spike_point_fragment"
    )
    ribbon = try additivePipeline(
        vertex: "spike_ribbon_vertex",
        fragment: "spike_ribbon_fragment"
    )
    adaptive = try additivePipeline(
        vertex: "spike_segment_vertex",
        fragment: "spike_ribbon_fragment"
    )
} catch let error as WobbulatorSpikeError {
    throw error
} catch {
    throw WobbulatorSpikeError.pipelineCreation(error.localizedDescription)
}
```

Replace `prepare` with:

```swift
public func prepare(_ workload: SpikeWorkload) throws -> PreparedSpikeCase {
    let renderPipeline: MTLRenderPipelineState
    let adaptivePipeline: MTLComputePipelineState?
    switch workload.representation {
    case .gaussianPointSprite:
        renderPipeline = point
        adaptivePipeline = nil
    case .scanlineRibbon:
        renderPipeline = ribbon
        adaptivePipeline = nil
    case .adaptiveScanlineSegment:
        renderPipeline = adaptive
        adaptivePipeline = buildAdaptive
    }
    return try PreparedSpikeCase(
        resources: resources,
        queue: queue,
        integrate: integrate,
        render: renderPipeline,
        buildAdaptive: adaptivePipeline,
        finalize: finalize,
        workload: workload
    )
}
```

Add the two optional adaptive properties to `PreparedSpikeCase` and replace its existing
`fieldEvaluationsPerFrame` and `primitiveInstancesPerFrame` properties with:

```swift
private let buildAdaptive: MTLComputePipelineState?
private let segmentBuffer: MTLBuffer?

public var fieldEvaluationsPerFrame: Int {
    let base = workload.samples.count
    guard workload.representation == .adaptiveScanlineSegment else {
        return base * workload.integrationSteps
    }
    let intervals = (workload.samples.width - 1) * workload.samples.height
    return (base + intervals * 7) * workload.integrationSteps
}

public var primitiveInstancesPerFrame: Int {
    switch workload.representation {
    case .gaussianPointSprite:
        workload.samples.count
    case .scanlineRibbon:
        (workload.samples.width - 1) * workload.samples.height
    case .adaptiveScanlineSegment:
        (workload.samples.width - 1) * workload.samples.height * 4
    }
}
```

Replace the prepared-case initializer signature with:

```swift
fileprivate init(
    resources: MetalResourceFactory,
    queue: MTLCommandQueue,
    integrate: MTLComputePipelineState,
    render: MTLRenderPipelineState,
    buildAdaptive: MTLComputePipelineState?,
    finalize: MTLComputePipelineState,
    workload: SpikeWorkload
) throws {
```

Keep the Task 3 initializer body after this opening line, then replace its buffer-allocation section
with:

```swift
self.buildAdaptive = buildAdaptive
let sampleBytes = workload.samples.count * MemoryLayout<MetalBeamSample>.stride
let segmentBytes = workload.representation == .adaptiveScanlineSegment
    ? (workload.samples.width - 1) * workload.samples.height * 4
        * MemoryLayout<MetalBeamSegment>.stride
    : 0
guard let samples = resources.makeBuffer(length: sampleBytes, options: .storageModePrivate),
    let uniforms = resources.makeBuffer(
        length: MemoryLayout<MetalSpikeUniforms>.stride,
        options: .storageModeShared
    )
else {
    throw WobbulatorSpikeError.resourceAllocation("sample or uniform buffer")
}
sampleBuffer = samples
uniformBuffer = uniforms
if segmentBytes > 0 {
    guard let segments = resources.makeBuffer(
        length: segmentBytes,
        options: .storageModePrivate
    )
    else {
        throw WobbulatorSpikeError.resourceAllocation("adaptive segment buffer")
    }
    segmentBuffer = segments
} else {
    segmentBuffer = nil
}
```

Replace the `allocatedBytes` assignment with:

```swift
allocatedBytes = sampleBytes + segmentBytes
    + MemoryLayout<MetalSpikeUniforms>.stride
    + workload.samples.width * workload.samples.height * 8
    + workload.output.width * workload.output.height * 16
```

In `render(frameIndex:)`, insert this block after the integrator encoder ends and before the render
pass begins:

```swift
if let buildAdaptive, let segmentBuffer {
    let intervalCount = (workload.samples.width - 1) * workload.samples.height
    guard let buildEncoder = commandBuffer.makeComputeCommandEncoder() else {
        throw WobbulatorSpikeError.commandEncoding("adaptive segment builder")
    }
    buildEncoder.setComputePipelineState(buildAdaptive)
    buildEncoder.setBuffer(sampleBuffer, offset: 0, index: 0)
    buildEncoder.setBuffer(uniformBuffer, offset: 0, index: 1)
    buildEncoder.setBuffer(segmentBuffer, offset: 0, index: 2)
    buildEncoder.dispatchThreads(
        MTLSize(width: intervalCount, height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(
            width: buildAdaptive.threadExecutionWidth,
            height: 1,
            depth: 1
        )
    )
    buildEncoder.endEncoding()
}
```

Add this diagnostics type at file scope and this post-timing readback method to
`PreparedSpikeCase`:

```swift
public struct AdaptiveDiagnostics: Equatable, Sendable {
    public var invalidIntervalCount: Int
    public var toleranceFailureCount: Int
    public var oneSubdivisionIntervalCount: Int
    public var twoSubdivisionIntervalCount: Int
    public var fourSubdivisionIntervalCount: Int

    public static let zero = AdaptiveDiagnostics(
        invalidIntervalCount: 0,
        toleranceFailureCount: 0,
        oneSubdivisionIntervalCount: 0,
        twoSubdivisionIntervalCount: 0,
        fourSubdivisionIntervalCount: 0
    )

    public var isFailureFree: Bool {
        invalidIntervalCount == 0 && toleranceFailureCount == 0
    }

    public var classifiedIntervalCount: Int {
        oneSubdivisionIntervalCount
            + twoSubdivisionIntervalCount
            + fourSubdivisionIntervalCount
    }

    public func completelyClassifies(_ expectedIntervalCount: Int) -> Bool {
        isFailureFree && classifiedIntervalCount == expectedIntervalCount
    }
}

public func adaptiveSegmentSnapshot() throws -> [MetalBeamSegment] {
    guard let segmentBuffer else { return [] }
    let count = (workload.samples.width - 1) * workload.samples.height * 4
    let size = count * MemoryLayout<MetalBeamSegment>.stride
    guard let destination = resources.makeBuffer(
        length: size,
        options: .storageModeShared
    ),
        let commandBuffer = queue.makeCommandBuffer(),
        let blit = commandBuffer.makeBlitCommandEncoder()
    else {
        throw WobbulatorSpikeError.resourceAllocation("adaptive diagnostics readback")
    }
    blit.copy(
        from: segmentBuffer,
        sourceOffset: 0,
        to: destination,
        destinationOffset: 0,
        size: size
    )
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    guard commandBuffer.status == .completed else {
        throw WobbulatorSpikeError.commandFailure("adaptive diagnostics readback")
    }
    let pointer = destination.contents().bindMemory(
        to: MetalBeamSegment.self,
        capacity: count
    )
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

public func adaptiveDiagnostics() throws -> AdaptiveDiagnostics {
    let values = try adaptiveSegmentSnapshot()
    guard !values.isEmpty else { return .zero }
    var result = AdaptiveDiagnostics.zero
    for intervalStart in stride(from: 0, to: values.count, by: 4) {
        let interval = values[intervalStart..<(intervalStart + 4)]
        switch interval.first!.energyActiveLength.w {
        case 1.0: result.toleranceFailureCount += 1
        case 2.0: result.invalidIntervalCount += 1
        default: break
        }
        let activeCount = interval.filter { $0.energyActiveLength.y == 1.0 }.count
        switch activeCount {
        case 1: result.oneSubdivisionIntervalCount += 1
        case 2: result.twoSubdivisionIntervalCount += 1
        case 4: result.fourSubdivisionIntervalCount += 1
        default: break
        }
    }
    return result
}
```

The readback occurs after the timed frame loop. It records failure counts and the number of base
intervals selecting one, two, or four true-trajectory chords. A factory-safe adaptive candidate is
rejected if either failure count is nonzero; base endpoint validity alone is not sufficient
authority for inserted trajectory probes.

Replace the vertex-buffer and draw call in the render encoder with:

```swift
let geometryBuffer = segmentBuffer ?? sampleBuffer
render.setVertexBuffer(geometryBuffer, offset: 0, index: 0)
render.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
render.setFragmentTexture(sourceTexture, index: 0)
render.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
render.drawPrimitives(
    type: .triangle,
    vertexStart: 0,
    vertexCount: 6,
    instanceCount: primitiveInstancesPerFrame
)
```

This preserves one command buffer per representation, which is the only defensible timer boundary
on this M5 Max because draw, dispatch, and blit boundary counter sampling are unavailable.

- [ ] **Step 6: Implement deterministic HDR metrics and previews**

Create `WobbulatorKit/Sources/WobbulatorMetal/HDRMetrics.swift`:

```swift
import Foundation
import simd
import WobbulatorCore

public struct HDRImage: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [SIMD4<Double>]

    public init(width: Int, height: Int, rgba16Bits: [UInt16]) throws {
        guard width > 0, height > 0, rgba16Bits.count == width * height * 4 else {
            throw WobbulatorSpikeError.evidenceFailure("RGBA16 readback size mismatch")
        }
        self.width = width
        self.height = height
        pixels = stride(from: 0, to: rgba16Bits.count, by: 4).map { index in
            SIMD4(
                Double(Float16(bitPattern: rgba16Bits[index])),
                Double(Float16(bitPattern: rgba16Bits[index + 1])),
                Double(Float16(bitPattern: rgba16Bits[index + 2])),
                Double(Float16(bitPattern: rgba16Bits[index + 3]))
            )
        }
        guard pixels.allSatisfy({ pixel in
            pixel.x.isFinite && pixel.y.isFinite && pixel.z.isFinite && pixel.w == 1.0
        }) else {
            throw WobbulatorSpikeError.evidenceFailure(
                "RGBA16 output contains non-finite RGB or non-opaque alpha"
            )
        }
    }

    public init(width: Int, height: Int, pixels: [SIMD4<Double>]) throws {
        guard width > 0, height > 0, pixels.count == width * height else {
            throw WobbulatorSpikeError.evidenceFailure("HDR pixel count mismatch")
        }
        guard pixels.allSatisfy({ pixel in
            pixel.x.isFinite && pixel.y.isFinite && pixel.z.isFinite && pixel.w == 1.0
        }) else {
            throw WobbulatorSpikeError.evidenceFailure("HDR image contains non-finite pixels")
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func writePreviewPPM(to url: URL, maxWidth: Int = 960) throws {
        let scale = min(1.0, Double(maxWidth) / Double(width))
        let targetWidth = max(1, Int(Double(width) * scale))
        let targetHeight = max(1, Int(Double(height) * scale))
        var data = Data("P6\n\(targetWidth) \(targetHeight)\n255\n".utf8)
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let sourceX = min(width - 1, Int(Double(x) / scale))
                let sourceY = min(height - 1, Int(Double(y) / scale))
                let color = pixels[sourceY * width + sourceX]
                for component in [color.x, color.y, color.z] {
                    let mapped = max(0.0, component) / (1.0 + max(0.0, component))
                    data.append(UInt8((pow(mapped, 1.0 / 2.2) * 255.0).rounded()))
                }
            }
        }
        try data.write(to: url, options: .atomic)
    }
}

public struct HDRComparison: Equatable, Sendable {
    public var relativeExposureDelta: Double
    public var centroidDistancePixels: Double
    public var contourSymmetricMeanDistancePixels: Double
}

public struct HDRMetrics: Sendable {
    public var width: Int
    public var height: Int
    public var integratedExposure: Double
    public var centroid: SIMD2<Double>
    public var energyMask: [Bool]
    public var contourMask: [Bool]
    public var contourSquaredDistance: [Double]
    public var litPixelCount: Int

    public static func analyze(_ image: HDRImage) throws -> HDRMetrics {
        let luma = image.pixels.map { pixel in
            max(0.0, 0.2126 * pixel.x + 0.7152 * pixel.y + 0.0722 * pixel.z)
        }
        guard luma.allSatisfy(\.isFinite) else {
            throw WobbulatorSpikeError.evidenceFailure("luma contains non-finite values")
        }
        let total = compensatedSum(luma)
        guard total > 0 else {
            throw WobbulatorSpikeError.evidenceFailure("HDR metric input has zero exposure")
        }

        var weightedX = 0.0
        var weightedY = 0.0
        for index in luma.indices {
            weightedX += (Double(index % image.width) + 0.5) * luma[index]
            weightedY += (Double(index / image.width) + 0.5) * luma[index]
        }

        let finiteHalfMaximum = 65_504.0
        let codes = luma.map {
            Float16(min($0, finiteHalfMaximum)).bitPattern
        }
        var bucketEnergy = [Double](repeating: 0.0, count: 0x7c00)
        for code in codes {
            bucketEnergy[Int(code)] += Double(Float16(bitPattern: code))
        }
        let quantizedTotal = compensatedSum(bucketEnergy)
        guard quantizedTotal > 0 else {
            throw WobbulatorSpikeError.evidenceFailure(
                "95-percent energy selection underflowed"
            )
        }
        let target = quantizedTotal * 0.95
        var aboveThresholdEnergy = 0.0
        var thresholdCode: UInt16 = 0
        for code in stride(from: 0x7bff, through: 1, by: -1) {
            let energy = bucketEnergy[code]
            if aboveThresholdEnergy + energy >= target {
                thresholdCode = UInt16(code)
                break
            }
            aboveThresholdEnergy += energy
        }
        guard thresholdCode > 0 else {
            throw WobbulatorSpikeError.evidenceFailure(
                "95-percent energy threshold is empty"
            )
        }

        let energyMask = codes.map { $0 >= thresholdCode }

        var contourMask = [Bool](repeating: false, count: energyMask.count)
        for index in energyMask.indices where energyMask[index] {
            let x = index % image.width
            let y = index / image.width
            let boundary = x == 0 || y == 0
                || x == image.width - 1 || y == image.height - 1
                || !energyMask[index - 1] || !energyMask[index + 1]
                || !energyMask[index - image.width] || !energyMask[index + image.width]
            contourMask[index] = boundary
        }
        guard contourMask.contains(true) else {
            throw WobbulatorSpikeError.evidenceFailure("95-percent contour is empty")
        }

        let contourSquaredDistance = exactSquaredDistanceTransform(
            featureMask: contourMask,
            width: image.width,
            height: image.height
        )
        return HDRMetrics(
            width: image.width,
            height: image.height,
            integratedExposure: total,
            centroid: SIMD2(weightedX / total, weightedY / total),
            energyMask: energyMask,
            contourMask: contourMask,
            contourSquaredDistance: contourSquaredDistance,
            litPixelCount: luma.reduce(into: 0) { count, value in
                if value > 0 { count += 1 }
            }
        )
    }

    public func compare(to reference: HDRMetrics) throws -> HDRComparison {
        guard width == reference.width, height == reference.height,
            contourMask.contains(true), reference.contourMask.contains(true),
            contourSquaredDistance.count == width * height,
            reference.contourSquaredDistance.count == width * height,
            integratedExposure.isFinite, reference.integratedExposure.isFinite,
            reference.integratedExposure > 0
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "HDR comparison dimensions or contours are invalid"
            )
        }
        func directed(_ source: [Bool], _ distance: [Double]) -> Double {
            var sum = 0.0
            var count = 0
            for index in source.indices where source[index] {
                sum += sqrt(distance[index])
                count += 1
            }
            return sum / Double(count)
        }
        let contourDistance = 0.5 * (
            directed(contourMask, reference.contourSquaredDistance)
                + directed(reference.contourMask, contourSquaredDistance)
        )
        guard contourDistance.isFinite else {
            throw WobbulatorSpikeError.evidenceFailure(
                "contour distance is non-finite"
            )
        }
        return HDRComparison(
            relativeExposureDelta: abs(integratedExposure - reference.integratedExposure)
                / reference.integratedExposure,
            centroidDistancePixels: simd_length(centroid - reference.centroid),
            contourSymmetricMeanDistancePixels: contourDistance
        )
    }

    static func exactSquaredDistanceTransform(
        featureMask: [Bool],
        width: Int,
        height: Int
    ) -> [Double] {
        precondition(width > 0 && height > 0 && featureMask.count == width * height)
        let far = 1e20
        var horizontal = [Double](repeating: far, count: featureMask.count)
        for y in 0..<height {
            let row = (0..<width).map { x in
                featureMask[y * width + x] ? 0.0 : far
            }
            let transformed = distanceTransform1D(row)
            for x in 0..<width { horizontal[y * width + x] = transformed[x] }
        }
        var result = [Double](repeating: far, count: featureMask.count)
        for x in 0..<width {
            let column = (0..<height).map { horizontal[$0 * width + x] }
            let transformed = distanceTransform1D(column)
            for y in 0..<height { result[y * width + x] = transformed[y] }
        }
        return result
    }

    private static func distanceTransform1D(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return values }
        let count = values.count
        var sites = [Int](repeating: 0, count: count)
        var boundaries = [Double](repeating: 0, count: count + 1)
        var output = [Double](repeating: 0, count: count)
        var envelope = 0
        sites[0] = 0
        boundaries[0] = -.infinity
        boundaries[1] = .infinity

        for q in 1..<count {
            var previous = sites[envelope]
            var intersection = (
                (values[q] + Double(q * q))
                    - (values[previous] + Double(previous * previous))
            ) / Double(2 * (q - previous))
            while intersection <= boundaries[envelope] {
                envelope -= 1
                previous = sites[envelope]
                intersection = (
                    (values[q] + Double(q * q))
                        - (values[previous] + Double(previous * previous))
                ) / Double(2 * (q - previous))
            }
            envelope += 1
            sites[envelope] = q
            boundaries[envelope] = intersection
            boundaries[envelope + 1] = .infinity
        }

        envelope = 0
        for q in 0..<count {
            while boundaries[envelope + 1] < Double(q) { envelope += 1 }
            let delta = q - sites[envelope]
            output[q] = Double(delta * delta) + values[sites[envelope]]
        }
        return output
    }

    private static func compensatedSum(_ values: [Double]) -> Double {
        var sum = 0.0
        var correction = 0.0
        for value in values {
            let adjusted = value - correction
            let next = sum + adjusted
            correction = (next - sum) - adjusted
            sum = next
        }
        return sum
    }
}
```

Metric extraction happens outside the timed loop. Nonnegative finite Float16 luma has 31,744
ordered codes and a maximum value of 65,504, so the fixed histogram selects the deterministic
95-percent luminance superlevel set in O(output pixels + 31,744) time without sorting pixels. The
separable exact squared Euclidean
distance transform is O(output pixels), and each cached reference transform is reused. No matrix
case performs pairwise contour matching.

- [ ] **Step 7: Implement the bounded CPU deposition reference**

Create `WobbulatorKit/Sources/WobbulatorMetal/CPUForwardDepositionReference.swift`:

```swift
import Foundation
import simd
import WobbulatorCore

public enum CPUForwardDepositionReference {
    public static func render(
        _ workload: SpikeWorkload,
        frameIndex: Int,
        quadratureCount: Int = 64
    ) throws -> HDRImage {
        guard workload.output.width <= 1920, workload.output.height <= 1080,
            workload.samples.width <= 160, workload.samples.height <= 90,
            workload.integrationSteps <= 256,
            (16...128).contains(quadratureCount)
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "CPU deposition reference exceeds its bounded 1920x1080, 160x90, "
                    + "256-step, 16-through-128-quadrature contract"
            )
        }
        var pixels = [SIMD4<Double>](
            repeating: SIMD4(0.0, 0.0, 0.0, 1.0),
            count: workload.output.width * workload.output.height
        )
        let timing = CRTTiming.ntsc525
        let field = oracleField(for: workload)
        let sigma = workload.beamWidthPixels
        let variance = sigma * sigma
        let radiusValue = ceil(sigma * 3.0)
        guard sigma.isFinite, sigma > 0, variance.isFinite, variance > 0,
            radiusValue.isFinite,
            radiusValue >= 1, radiusValue <= 512
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "CPU deposition kernel radius is outside the bounded finite contract"
            )
        }
        let radius = Int(radiusValue)
        let intervalCount = (workload.samples.width - 1) * workload.samples.height
        let energy = Double(workload.output.width * workload.output.height)
            / Double(intervalCount * quadratureCount)

        for y in 0..<workload.samples.height {
            for x in 0..<(workload.samples.width - 1) {
                let uA = (Double(x) + 0.5) / Double(workload.samples.width)
                let uB = (Double(x + 1) + 0.5) / Double(workload.samples.width)
                let colorA = sourceColor(
                    x: x, y: y, grid: workload.samples,
                    pattern: workload.sourcePattern
                )
                let colorB = sourceColor(
                    x: x + 1, y: y, grid: workload.samples,
                    pattern: workload.sourcePattern
                )
                for quadratureIndex in 0..<quadratureCount {
                    let t = (Double(quadratureIndex) + 0.5) / Double(quadratureCount)
                    let u = uA + (uB - uA) * t
                    let v = (Double(y) + 0.5) / Double(workload.samples.height)
                    let launch = try timing.rasterLaunchTimeSeconds(
                        normalizedLine: Double(y) / Double(workload.samples.height),
                        horizontal: u,
                        fieldIndex: frameIndex
                    )
                    let result = RelativisticBorisOracle.trace(
                        initial: BorisState(
                            position: SIMD3(0.0, 0.0, -1.0),
                            momentum: SIMD3(u * 2.0 - 1.0, v * 2.0 - 1.0, 1.0),
                            rasterLaunchTimeSeconds: launch
                        ),
                        field: field,
                        steps: workload.integrationSteps,
                        screenZ: 0.0,
                        bounds: 8.0
                    )
                    guard result.termination == .hitScreen else { continue }
                    var destination = SIMD2(
                        (result.state.position.x * 0.5 + 0.5)
                            * Double(workload.output.width),
                        (result.state.position.y * 0.5 + 0.5)
                            * Double(workload.output.height)
                    )
                    switch workload.fixture {
                    case .fold:
                        destination.x += workload.fixtureAmount
                            * Double(workload.output.width) * sin(u * 2.0 * .pi)
                    case .branchOverlap:
                        destination.x = (u * 2.0).truncatingRemainder(dividingBy: 1.0)
                            * Double(workload.output.width)
                    case .identity, .dipole, .sBend:
                        break
                    }
                    guard destination.x.isFinite, destination.y.isFinite else { continue }
                    deposit(
                        color: colorA + (colorB - colorA) * t,
                        energy: energy,
                        destination: destination,
                        variance: variance,
                        radius: radius,
                        width: workload.output.width,
                        height: workload.output.height,
                        pixels: &pixels
                    )
                }
            }
        }
        return try HDRImage(
            width: workload.output.width,
            height: workload.output.height,
            pixels: pixels
        )
    }

    private static func oracleField(for workload: SpikeWorkload) -> OracleField {
        switch workload.fixture {
        case .identity, .fold, .branchOverlap:
            return .zero
        case .dipole:
            return .uniform(SIMD3(0.0, workload.fixtureAmount, 0.0))
        case .sBend:
            return .sBend(
                amplitude: workload.fixtureAmount,
                angularFrequency: .pi * 120.0,
                phase: 0.0
            )
        }
    }

    private static func sourceColor(
        x: Int,
        y: Int,
        grid: SampleGrid,
        pattern: SpikeSourcePattern
    ) -> SIMD3<Double> {
        switch pattern {
        case .solidWhite:
            return SIMD3(repeating: 1.0)
        case .leftRedOnly:
            return x < grid.width / 2 ? SIMD3(1.0, 0.0, 0.0) : .zero
        case .rightGreenOnly:
            return x >= grid.width / 2 ? SIMD3(0.0, 1.0, 0.0) : .zero
        case .twoBranchRedGreen:
            return x < grid.width / 2
                ? SIMD3(1.0, 0.0, 0.0) : SIMD3(0.0, 1.0, 0.0)
        case .colorGrid:
            let u = Double(x) / Double(max(grid.width - 1, 1))
            let v = Double(y) / Double(max(grid.height - 1, 1))
            let band = min(Int(u * 3.0), 2)
            let gridLine = x.isMultiple(of: max(grid.width / 16, 1))
                || y.isMultiple(of: max(grid.height / 16, 1))
            var color = SIMD3<Double>(repeating: 0.05)
            color[band] = gridLine ? 1.0 : 0.7
            color += SIMD3(repeating: v * 0.1)
            return color
        }
    }

    private static func deposit(
        color: SIMD3<Double>,
        energy: Double,
        destination: SIMD2<Double>,
        variance: Double,
        radius: Int,
        width: Int,
        height: Int,
        pixels: inout [SIMD4<Double>]
    ) {
        let centerX = Int(floor(destination.x))
        let centerY = Int(floor(destination.y))
        let diameter = radius * 2 + 1
        withUnsafeTemporaryAllocation(
            of: Double.self,
            capacity: diameter * 2
        ) { weights in
            var xNormalization = 0.0
            var yNormalization = 0.0
            for offset in 0..<diameter {
                let x = centerX - radius + offset
                let y = centerY - radius + offset
                let dx = Double(x) + 0.5 - destination.x
                let dy = Double(y) + 0.5 - destination.y
                let xWeight = exp(-0.5 * dx * dx / variance)
                let yWeight = exp(-0.5 * dy * dy / variance)
                weights[offset] = xWeight
                weights[diameter + offset] = yWeight
                xNormalization += xWeight
                yNormalization += yWeight
            }
            let normalization = xNormalization * yNormalization
            guard normalization > 0 else { return }
            for yOffset in 0..<diameter {
                let y = centerY - radius + yOffset
                guard y >= 0, y < height else { continue }
                for xOffset in 0..<diameter {
                    let x = centerX - radius + xOffset
                    guard x >= 0, x < width else { continue }
                    let weight = weights[xOffset] * weights[diameter + yOffset]
                    let scaled = energy * weight / normalization
                    let index = y * width + x
                    pixels[index].x += color.x * scaled
                    pixels[index].y += color.y * scaled
                    pixels[index].z += color.z * scaled
                }
            }
        }
    }
}
```

The CPU reference is hard-bounded to tests and authority checks, never the timed matrix. Its
default 64-point midpoint quadrature is independent of the adaptive GPU chords, and the authority
gate first proves that 64 points have converged against 128 points within one quarter of the
scaled visual tolerances. Its finite discrete Gaussian is normalized over the full kernel support
before viewport clipping; off-screen energy stays lost instead of being renormalized back into
edge pixels.

- [ ] **Step 8: Pin histogram, exact-distance, scaling, and CPU energy invariants**

Create `WobbulatorKit/Tests/WobbulatorMetalTests/HDRMetricsTests.swift`:

```swift
import XCTest
@testable import WobbulatorCore
@testable import WobbulatorMetal

final class HDRMetricsTests: XCTestCase {
    func testEqualEnergyThresholdBucketPreservesSymmetry() throws {
        let image = try HDRImage(
            width: 20,
            height: 1,
            pixels: [SIMD4<Double>](
                repeating: SIMD4(1.0, 1.0, 1.0, 1.0),
                count: 20
            )
        )
        let first = try HDRMetrics.analyze(image)
        let second = try HDRMetrics.analyze(image)
        XCTAssertEqual(first.energyMask, second.energyMask)
        XCTAssertEqual(first.energyMask, [Bool](repeating: true, count: 20))
    }

    func testExactDistanceTransformMatchesBruteForce() {
        let width = 7
        let height = 5
        var mask = [Bool](repeating: false, count: width * height)
        mask[1 * width + 2] = true
        mask[4 * width + 5] = true
        let actual = HDRMetrics.exactSquaredDistanceTransform(
            featureMask: mask,
            width: width,
            height: height
        )
        for y in 0..<height {
            for x in 0..<width {
                let expected = min(
                    Double((x - 2) * (x - 2) + (y - 1) * (y - 1)),
                    Double((x - 5) * (x - 5) + (y - 4) * (y - 4))
                )
                XCTAssertEqual(actual[y * width + x], expected, accuracy: 1e-12)
            }
        }
    }

    func testContourDistanceUsesOutputPixelsAndScalesByTwo() throws {
        func metric(width: Int, height: Int, point: (Int, Int)) -> HDRMetrics {
            var mask = [Bool](repeating: false, count: width * height)
            mask[point.1 * width + point.0] = true
            return HDRMetrics(
                width: width,
                height: height,
                integratedExposure: 1.0,
                centroid: SIMD2(Double(point.0) + 0.5, Double(point.1) + 0.5),
                energyMask: mask,
                contourMask: mask,
                contourSquaredDistance: HDRMetrics.exactSquaredDistanceTransform(
                    featureMask: mask,
                    width: width,
                    height: height
                ),
                litPixelCount: 1
            )
        }
        let small = try metric(width: 8, height: 8, point: (3, 2)).compare(
            to: metric(width: 8, height: 8, point: (2, 2))
        )
        let large = try metric(width: 16, height: 16, point: (6, 4)).compare(
            to: metric(width: 16, height: 16, point: (4, 4))
        )
        XCTAssertEqual(small.contourSymmetricMeanDistancePixels, 1.0, accuracy: 1e-12)
        XCTAssertEqual(large.contourSymmetricMeanDistancePixels, 2.0, accuracy: 1e-12)
    }

    func testCPUDiscreteKernelPreservesAnalyticWhiteEnergy() throws {
        let workload = try SpikeWorkload(
            output: RasterSize(width: 64, height: 36),
            samples: SampleGrid(width: 16, height: 8),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixture: .identity,
            sourcePattern: .solidWhite,
            representation: .gaussianPointSprite
        )
        let image = try CPUForwardDepositionReference.render(workload, frameIndex: 0)
        let metrics = try HDRMetrics.analyze(image)
        XCTAssertEqual(metrics.integratedExposure, 64.0 * 36.0, accuracy: 1e-8)
        XCTAssertEqual(metrics.centroid.x, 32.0, accuracy: 1e-8)
        XCTAssertEqual(metrics.centroid.y, 18.0, accuracy: 1e-8)
    }

    func testCPUReferenceRejectsFiniteKernelOverflowAndUnderflowWithoutTrapping() throws {
        for beamWidth in [1e300, 1e-300] {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 64, height: 36),
                samples: SampleGrid(width: 16, height: 8),
                integrationSteps: 32,
                beamWidthPixelsAt1080: beamWidth,
                fixture: .identity,
                sourcePattern: .solidWhite,
                representation: .adaptiveScanlineSegment
            )
            XCTAssertThrowsError(
                try CPUForwardDepositionReference.render(workload, frameIndex: 0)
            )
        }
    }

    func testCPUReferenceProvesPixelwiseBranchAdditivity() throws {
        func render(_ pattern: SpikeSourcePattern) throws -> HDRImage {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 64, height: 36),
                samples: SampleGrid(width: 16, height: 8),
                integrationSteps: 32,
                beamWidthPixelsAt1080: 1.25,
                fixture: .branchOverlap,
                sourcePattern: pattern,
                representation: .adaptiveScanlineSegment
            )
            return try CPUForwardDepositionReference.render(workload, frameIndex: 0)
        }
        let left = try render(.leftRedOnly)
        let right = try render(.rightGreenOnly)
        let both = try render(.twoBranchRedGreen)
        for index in both.pixels.indices {
            XCTAssertEqual(
                both.pixels[index].x,
                left.pixels[index].x + right.pixels[index].x,
                accuracy: 1e-10
            )
            XCTAssertEqual(
                both.pixels[index].y,
                left.pixels[index].y + right.pixels[index].y,
                accuracy: 1e-10
            )
        }
    }

    func testCPUReference64PointQuadratureConvergesAgainst128Points() throws {
        let workload = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 160, height: 90),
            integrationSteps: 64,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: 0.42,
            fixture: .fold,
            sourcePattern: .solidWhite,
            representation: .adaptiveScanlineSegment
        )
        let q64 = try CPUForwardDepositionReference.render(
            workload, frameIndex: 0, quadratureCount: 64
        )
        let q128 = try CPUForwardDepositionReference.render(
            workload, frameIndex: 0, quadratureCount: 128
        )
        let comparison = try HDRMetrics.analyze(q64).compare(
            to: HDRMetrics.analyze(q128)
        )
        let scale = Double(workload.output.height) / 1080.0
        XCTAssertLessThanOrEqual(
            comparison.relativeExposureDelta,
            SpikeThresholds.approved.exposureDeltaFraction / 4.0
        )
        XCTAssertLessThanOrEqual(
            comparison.centroidDistancePixels,
            SpikeThresholds.approved.centroidPixels1080 * scale / 4.0
        )
        XCTAssertLessThanOrEqual(
            comparison.contourSymmetricMeanDistancePixels,
            SpikeThresholds.approved.contourPixels1080 * scale / 4.0
        )
    }
}
```

- [ ] **Step 9: Run the representation and metric tests to verify GREEN**

Run:

```bash
cd WobbulatorKit
swift test --filter ForwardDepositionTests
```

Expected: all three representations pass finite/opaque output, forward fold-branch retention,
exposure, centroid, contour, and ABI gates. If a representation needs a hidden scalar to pass
energy, reject it; only the shared analytic kernel normalization may be corrected.

- [ ] **Step 10: Prove the branch-retention and adaptive-error gates can fail**

Temporarily replace the additive blend factors for one pipeline with `.one` source and `.zero`
destination, then run:

```bash
cd WobbulatorKit
swift test --filter ForwardDepositionTests/testFoldRetainsMultipleSourceColorBranches
```

Expected: FAIL because overlap no longer retains multiple source branches. Restore additive
blending and rerun; expected: PASS.

Then temporarily change `adaptive = SIMD4(0.25, 0.0, 0.0, 0.0)` to an error limit of `0.0` and
run:

```bash
swift test --filter ForwardDepositionTests/testAdaptiveGeometryMeetsItsTrueProbeErrorLimit
```

Expected: FAIL with a nonzero `toleranceFailureCount`. Restore 0.25 and rerun; expected: PASS.

Finally, temporarily replace the adaptive selection expression with `subdivisions = 4u`, then
run:

```bash
swift test --filter ForwardDepositionTests/testAdaptiveTopologyChoosesOneChordForIdentityAndMoreForCurvature
```

Expected: FAIL because identity no longer selects exactly one chord per interval. Restore the
1/2/4 error-based selection and rerun both adaptive topology tests; expected: PASS.

- [ ] **Step 11: Format, lint, test, build, and commit**

Run:

```bash
cd WobbulatorKit
swift format format --in-place --recursive Sources Tests
swift format lint --strict --recursive Sources Tests
swift test
swift build -c release
git add Sources/WobbulatorMetal/MetalABI.swift \
  Sources/WobbulatorMetal/Shaders/WobbulatorSpike.metal \
  Sources/WobbulatorMetal/WobbulatorMetalRenderer.swift \
  Sources/WobbulatorMetal/HDRMetrics.swift \
  Sources/WobbulatorMetal/CPUForwardDepositionReference.swift \
  Tests/WobbulatorMetalTests/MetalOracleTests.swift \
  Tests/WobbulatorMetalTests/ForwardDepositionTests.swift \
  Tests/WobbulatorMetalTests/HDRMetricsTests.swift
git commit -m "spike: compare forward beam depositors"
```

Expected: the complete package suite and release build pass.

---

### Task 5: Build the reproducible M5 matrix, thermal runner, and stop rules

**Files:**
- Modify: `WobbulatorKit/Package.swift`
- Create: `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkOptions.swift`
- Create: `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkDecision.swift`
- Create: `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkArtifactVerifier.swift`
- Create: `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkRunner.swift`
- Create: `WobbulatorKit/Sources/WobbulatorBench/main.swift`
- Test: `WobbulatorKit/Tests/WobbulatorBenchTests/BenchmarkRunnerTests.swift`
- Create: `docs/arshader/benchmarks/wobbulator-phase1/README.md`

**Interfaces:**
- Consumes: `WobbulatorMetalRenderer.prepare`, `PreparedSpikeCase.render`, Task 4 HDR metrics,
  and Task 1 report contracts.
- Produces:
  - `BenchmarkOptions.parse(_:)` and deterministic quick, matrix, and thermal workload expansion
  - `BenchmarkRunner.run(_:) throws -> BenchmarkReport`
  - `BenchmarkDecision.evaluate(measurements:thresholds:requiredFixtures:)`
  - `BenchmarkDecision.markdown(matrix:thermal:)` with combined evidence and visual manifest
  - `BenchmarkArtifactVerifier.verify(report:suite:selectionReport:)`
  - pretty, sorted, ISO-8601 JSON plus a deterministic Markdown decision
  - exit 0 for `go`, exit 2 for `stop1080`, exit 3 for `blocked4K`, and exit 64 for usage or
    execution errors

- [ ] **Step 1: Add the benchmark targets and failing decision tests**

Replace `WobbulatorKit/Package.swift` with:

~~~swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WobbulatorKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WobbulatorCore", targets: ["WobbulatorCore"]),
        .library(name: "WobbulatorMetal", targets: ["WobbulatorMetal"]),
        .executable(name: "WobbulatorBench", targets: ["WobbulatorBench"]),
    ],
    targets: [
        .target(name: "WobbulatorCore"),
        .target(
            name: "WobbulatorMetal",
            dependencies: ["WobbulatorCore"],
            resources: [.copy("Shaders")]
        ),
        .target(
            name: "WobbulatorBenchSupport",
            dependencies: ["WobbulatorCore", "WobbulatorMetal"]
        ),
        .executableTarget(
            name: "WobbulatorBench",
            dependencies: ["WobbulatorBenchSupport"]
        ),
        .testTarget(
            name: "WobbulatorCoreTests",
            dependencies: ["WobbulatorCore"]
        ),
        .testTarget(
            name: "WobbulatorMetalTests",
            dependencies: ["WobbulatorCore", "WobbulatorMetal"]
        ),
        .testTarget(
            name: "WobbulatorBenchTests",
            dependencies: ["WobbulatorCore", "WobbulatorBenchSupport"]
        ),
    ]
)
~~~

Create `WobbulatorKit/Tests/WobbulatorBenchTests/BenchmarkRunnerTests.swift`:

~~~swift
import Foundation
import XCTest
import WobbulatorCore
@testable import WobbulatorBenchSupport

final class BenchmarkRunnerTests: XCTestCase {
    func testNearestRankPercentilesAreExact() {
        let values = (1...20).map(Double.init)
        XCTAssertEqual(BenchmarkRunner.percentile(values, fraction: 0.50), 10)
        XCTAssertEqual(BenchmarkRunner.percentile(values, fraction: 0.95), 19)
        XCTAssertEqual(BenchmarkRunner.percentile([7], fraction: 0.95), 7)
    }

    func testQuickAndFullMatricesHaveExactMembership() throws {
        let quick = try BenchmarkOptions.workloads(for: .quick)
        let matrix = try BenchmarkOptions.workloads(for: .matrix)
        XCTAssertEqual(quick.count, 12)
        XCTAssertEqual(matrix.count, 144)
        XCTAssertEqual(Set(matrix.map(\.samples)), Set([
            SampleGrid(width: 480, height: 270),
            SampleGrid(width: 960, height: 540),
            SampleGrid(width: 1280, height: 720),
            SampleGrid(width: 1920, height: 1080),
        ]))
        XCTAssertEqual(Set(matrix.map(\.integrationSteps)), Set([8, 16, 32]))
        XCTAssertEqual(Set(matrix.map(\.fixture)), Set([.identity, .fold]))
        XCTAssertEqual(Set(matrix.map(\.output)), Set([.hd1080, .uhd4K]))
        XCTAssertEqual(Set(matrix.map(\.representation)), Set(DepositionRepresentation.allCases))
        var leadingCounts: [DepositionRepresentation: Int] = [:]
        for start in stride(from: 0, to: matrix.count, by: 3) {
            let group = Array(matrix[start..<(start + 3)])
            XCTAssertEqual(
                Set(group.map(\.representation)),
                Set(DepositionRepresentation.allCases)
            )
            XCTAssertEqual(Set(group.map(\.output)).count, 1)
            XCTAssertEqual(Set(group.map(\.samples)).count, 1)
            XCTAssertEqual(Set(group.map(\.integrationSteps)).count, 1)
            XCTAssertEqual(Set(group.map(\.fixture)).count, 1)
            leadingCounts[group[0].representation, default: 0] += 1
        }
        XCTAssertEqual(Set(leadingCounts.values), Set([16]))
    }

    func testBranchProofAndSelectedPreviewUseTheExactCandidateQuality() throws {
        let selected = try SpikeWorkload(
            output: .uhd4K,
            samples: SampleGrid(width: 480, height: 270),
            integrationSteps: 8,
            beamWidthPixelsAt1080: 1.25,
            fixture: .fold,
            representation: .adaptiveScanlineSegment
        )
        let key = BenchmarkRunner.BranchValidationKey(workload: selected)
        let branch = try key.workload(sourcePattern: .twoBranchRedGreen)
        XCTAssertEqual(branch.output, selected.output)
        XCTAssertEqual(branch.samples, selected.samples)
        XCTAssertEqual(branch.integrationSteps, selected.integrationSteps)
        XCTAssertEqual(branch.beamWidthPixelsAt1080, selected.beamWidthPixelsAt1080)
        XCTAssertEqual(branch.fixtureAmount, selected.fixtureAmount)
        XCTAssertEqual(branch.fixture, .branchOverlap)
        XCTAssertEqual(branch.sourcePattern, .twoBranchRedGreen)
        XCTAssertEqual(branch.representation, selected.representation)
        XCTAssertEqual(
            BenchmarkDecision.selectedPreviewFilename(
                selected: selected,
                output: selected.output,
                fixture: selected.fixture
            ),
            "selected-adaptiveScanlineSegment-3840x2160-grid480x270-steps8-fold.ppm"
        )

        var differentOutput = selected
        differentOutput.output = .hd1080
        XCTAssertNotEqual(
            key,
            BenchmarkRunner.BranchValidationKey(workload: differentOutput)
        )
        var differentGrid = selected
        differentGrid.samples = SampleGrid(width: 960, height: 540)
        XCTAssertNotEqual(
            key,
            BenchmarkRunner.BranchValidationKey(workload: differentGrid)
        )
        var differentSteps = selected
        differentSteps.integrationSteps = 32
        XCTAssertNotEqual(
            key,
            BenchmarkRunner.BranchValidationKey(workload: differentSteps)
        )
    }

    func testCLIRejectsNonFiniteThermalDuration() {
        for value in ["nan", "inf", "-inf"] {
            XCTAssertThrowsError(
                try BenchmarkOptions.parse([
                    "--suite", "quick",
                    "--output", "/tmp/wobbulator-test.json",
                    "--thermal-seconds", value,
                ])
            )
        }
        XCTAssertThrowsError(
            try BenchmarkOptions.parse([
                "--suite", "thermal",
                "--output", "/tmp/wobbulator-test.json",
                "--selection-report", "/tmp/wobbulator-selection.json",
                "--thermal-seconds", "599",
            ])
        )
    }

    func testValidMatrixReportLoadsExactlyTheSelectedThermalPair() throws {
        let report = try validMatrixReport()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "wobbulator-valid-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: .atomic)
        let options = try BenchmarkOptions.parse([
            "--suite", "thermal",
            "--output", "/tmp/wobbulator-thermal-test.json",
            "--selection-report", url.path,
        ])
        let workloads = try options.selectedThermalWorkloads()
        let selected = try XCTUnwrap(report.recommendedWorkload)
        XCTAssertEqual(workloads.count, 2)
        XCTAssertEqual(Set(workloads.map(\.output)), Set([.hd1080, .uhd4K]))
        XCTAssertTrue(workloads.allSatisfy {
            $0.fixture == .fold
                && $0.representation == selected.representation
                && $0.samples == selected.samples
                && $0.integrationSteps == selected.integrationSteps
        })
    }

    func testThermalSelectionRejectsMetricUniverseAndDimensionTampering() throws {
        let valid = try validMatrixReport()

        var metricTamper = valid
        let selected = try XCTUnwrap(valid.recommendedWorkload)
        let selectedIndex = try XCTUnwrap(metricTamper.measurements.firstIndex {
            $0.workload.representation == selected.representation
                && $0.workload.samples == selected.samples
                && $0.workload.integrationSteps == selected.integrationSteps
        })
        metricTamper.measurements[selectedIndex].oracleMaxPixels = 2.0
        try assertSelectionRejected(metricTamper, label: "metric")

        var universeTamper = valid
        universeTamper.measurements[0].workload = universeTamper.measurements[1].workload
        try assertSelectionRejected(universeTamper, label: "universe")

        var dimensionTamper = valid
        dimensionTamper.measurements[0].workload.output.width = Int.max
        try assertSelectionRejected(dimensionTamper, label: "dimension")
    }

    func testArtifactVerifierRecomputesTheExactMatrixTerminalState() throws {
        let valid = try validMatrixReport()
        XCTAssertNoThrow(
            try BenchmarkArtifactVerifier.verify(report: valid, suite: .matrix)
        )

        var statusTamper = valid
        statusTamper.status = .blocked4K
        XCTAssertThrowsError(
            try BenchmarkArtifactVerifier.verify(report: statusTamper, suite: .matrix)
        )

        var recommendationTamper = valid
        recommendationTamper.recommendation = "a different candidate"
        XCTAssertThrowsError(
            try BenchmarkArtifactVerifier.verify(report: recommendationTamper, suite: .matrix)
        )

        var workloadTamper = valid
        workloadTamper.recommendedWorkload = nil
        XCTAssertThrowsError(
            try BenchmarkArtifactVerifier.verify(report: workloadTamper, suite: .matrix)
        )

        var referenceTamper = valid
        referenceTamper.referenceFoldNormalizedExposureDelta = 0.021
        XCTAssertThrowsError(
            try BenchmarkArtifactVerifier.verify(report: referenceTamper, suite: .matrix)
        )

        let blocked = try validMatrixReport(p95At1080: 3.0, p95At4K: 8.1)
        XCTAssertEqual(blocked.status, .blocked4K)
        XCTAssertNoThrow(
            try BenchmarkArtifactVerifier.verify(report: blocked, suite: .matrix)
        )
        let stopped = try validMatrixReport(p95At1080: 4.1, p95At4K: 8.1)
        XCTAssertEqual(stopped.status, .stop1080)
        XCTAssertNoThrow(
            try BenchmarkArtifactVerifier.verify(report: stopped, suite: .matrix)
        )
    }

    func testArtifactVerifierCLIRoundTripsAnISO8601MatrixReport() throws {
        let report = try validMatrixReport()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "wobbulator-verify-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: .atomic)
        XCTAssertNoThrow(
            try BenchmarkArtifactVerifier.verifyCLI(arguments: [
                "--suite", "matrix", "--report", url.path,
            ])
        )
    }

    func testArtifactVerifierKeepsThermalEvidenceOnTheMatrixSelection() throws {
        let matrix = try validMatrixReport()
        let selected = try XCTUnwrap(matrix.recommendedWorkload)
        var values = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            grid: selected.samples,
            steps: selected.integrationSteps,
            fixtures: [.fold],
            representation: selected.representation
        )
        for index in values.indices {
            values[index].frameCount = 36_000
            values[index].measuredWallSeconds = 600.0
            values[index].thermalTargetSeconds = 600.0
            values[index].thermalTargetFramesPerSecond = 60.0
        }
        let decision = BenchmarkDecision.evaluate(
            measurements: values,
            thresholds: .approved,
            requiredFixtures: [.fold]
        )
        var thermal = BenchmarkReport(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            hardware: matrix.hardware,
            thresholds: matrix.thresholds,
            measurements: values,
            status: decision.status,
            recommendation: decision.recommendation,
            recommendedWorkload: decision.recommendedWorkload,
            referenceValidationPassed: true,
            referenceIdentityNormalizedExposureDelta: 0.0,
            referenceFoldNormalizedExposureDelta: 0.0
        )
        XCTAssertNoThrow(
            try BenchmarkArtifactVerifier.verify(
                report: thermal,
                suite: .thermal,
                selectionReport: matrix
            )
        )

        for index in thermal.measurements.indices {
            thermal.measurements[index].workload.samples = SampleGrid(width: 480, height: 270)
        }
        let drifted = BenchmarkDecision.evaluate(
            measurements: thermal.measurements,
            thresholds: thermal.thresholds,
            requiredFixtures: [.fold]
        )
        thermal.status = drifted.status
        thermal.recommendation = drifted.recommendation
        thermal.recommendedWorkload = drifted.recommendedWorkload
        XCTAssertThrowsError(
            try BenchmarkArtifactVerifier.verify(
                report: thermal,
                suite: .thermal,
                selectionReport: matrix
            )
        )
    }

    func testDecisionMarkdownCombinesMatrixThermalAndSelectedVisualManifest() throws {
        let matrix = try validMatrixReport()
        let thermal = try validThermalReport(matrix: matrix)
        let selected = try XCTUnwrap(matrix.recommendedWorkload)
        let markdown = BenchmarkDecision.markdown(matrix: matrix, thermal: thermal)

        XCTAssertTrue(markdown.contains("GO: the selected Full Beam renderer passed"))
        XCTAssertTrue(markdown.contains("144 cases | exactly 144 | PASS"))
        XCTAssertTrue(markdown.contains("Paired sustained thermal proof"))
        XCTAssertTrue(markdown.contains("Phase 1 contains no ARShader stage"))
        XCTAssertTrue(markdown.contains("This authorizes a Phase 2 plan only"))
        XCTAssertTrue(
            markdown.contains(
                "Measured minimum effect-budget headroom: 12.500000 percent"
            )
        )
        XCTAssertTrue(markdown.contains("focused engineering effort"))
        XCTAssertTrue(markdown.contains("not calendar duration or a ship date"))
        XCTAssertTrue(markdown.contains("Conditional Fast Preview"))
        for output in [RasterSize.hd1080, .uhd4K] {
            for fixture in [SpikeFixture.identity, .fold] {
                let path = "previews/" + BenchmarkDecision.selectedPreviewFilename(
                    selected: selected,
                    output: output,
                    fixture: fixture
                )
                XCTAssertTrue(markdown.contains(path), path)
            }
        }
    }

    func testDecisionMarkdownDistinguishesBothMatrixStopStates() throws {
        let stopped = try validMatrixReport(p95At1080: 4.1, p95At4K: 8.1)
        let stoppedMarkdown = BenchmarkDecision.markdown(matrix: stopped)
        XCTAssertTrue(stoppedMarkdown.contains("STOP AT 1080P"))
        XCTAssertTrue(stoppedMarkdown.contains("Highest-ranked diagnostic candidate"))
        XCTAssertTrue(stoppedMarkdown.contains("new representation research proposal"))
        XCTAssertTrue(stoppedMarkdown.contains("No selected-quality preview manifest"))
        XCTAssertTrue(stoppedMarkdown.contains("Withheld"))

        let blocked = try validMatrixReport(p95At1080: 3.0, p95At4K: 8.1)
        let blockedMarkdown = BenchmarkDecision.markdown(matrix: blocked)
        XCTAssertTrue(blockedMarkdown.contains("BLOCKED AT 4K"))
        XCTAssertTrue(blockedMarkdown.contains("viable 1080p result"))
        XCTAssertTrue(blockedMarkdown.contains("versioned 4K scope revision"))
        XCTAssertTrue(blockedMarkdown.contains("| 4K effect-only p95 |"))
        XCTAssertTrue(blockedMarkdown.contains("| FAIL |"))
    }

    func testDecisionMarkdownNamesAReferenceAuthorityStop() throws {
        var matrix = try validMatrixReport()
        matrix.referenceValidationPassed = false
        let decision = BenchmarkDecision.evaluate(
            measurements: matrix.measurements,
            thresholds: matrix.thresholds,
            referenceValidationPassed: false
        )
        matrix.status = decision.status
        matrix.recommendation = decision.recommendation
        matrix.recommendedWorkload = decision.recommendedWorkload

        let markdown = BenchmarkDecision.markdown(matrix: matrix)
        XCTAssertTrue(markdown.contains("STOP AT REFERENCE AUTHORITY"))
        XCTAssertTrue(markdown.contains("No candidate is approved"))
        XCTAssertTrue(markdown.contains("Correct the reference-authority defect"))
        XCTAssertTrue(markdown.contains("No evidence candidate is available"))
        XCTAssertTrue(markdown.contains("CPU/GPU reference authority | failed"))
    }

    func testThermalStopKeepsTheMatrixCandidateAndExactFailureEvidence() throws {
        let matrix = try validMatrixReport()
        let selected = try XCTUnwrap(matrix.recommendedWorkload)
        var thermal = try validThermalReport(matrix: matrix)
        let index = try XCTUnwrap(thermal.measurements.firstIndex {
            $0.workload.output == .uhd4K
        })
        thermal.measurements[index].p95GPUMilliseconds = 8.1
        let decision = BenchmarkDecision.evaluate(
            measurements: thermal.measurements,
            thresholds: thermal.thresholds,
            requiredFixtures: [.fold]
        )
        thermal.status = decision.status
        thermal.recommendation = decision.recommendation
        thermal.recommendedWorkload = decision.recommendedWorkload
        XCTAssertEqual(thermal.status, .blocked4K)
        XCTAssertNil(thermal.recommendedWorkload)

        let markdown = BenchmarkDecision.markdown(matrix: matrix, thermal: thermal)
        XCTAssertTrue(markdown.contains("BLOCKED AT 4K"))
        XCTAssertTrue(markdown.contains(selected.representation.rawValue))
        XCTAssertTrue(
            markdown.contains(
                "grid\(selected.samples.width)x\(selected.samples.height)"
            )
        )
        XCTAssertTrue(markdown.contains("8.100000 ms | 8.000000 ms | FAIL"))
        XCTAssertTrue(markdown.contains("Operator approval covers these exact"))
        XCTAssertTrue(markdown.contains("Withheld"))
    }

    func testHardwareJSONContainsOnlyApprovedKeys() throws {
        let hardware = HardwareRecord(
            deviceName: "Apple M5 Max",
            gpuCoreCount: 40,
            memoryGB: 128,
            operatingSystem: "macOS 27.0",
            swiftVersion: "Apple Swift version 6.2"
        )
        let data = try JSONEncoder().encode(hardware)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set(["deviceName", "gpuCoreCount", "memoryGB", "operatingSystem", "swiftVersion"])
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("serial"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("uuid"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("registry"))
    }

    func testDecisionTransitionsFromStopToBlockedToGo() throws {
        let only1080Failure = try measurements(
            include4K: false,
            p95At1080: 4.1,
            p95At4K: 8.1
        )
        let stoppedResult = BenchmarkDecision.evaluate(
            measurements: only1080Failure,
            thresholds: .approved
        )
        XCTAssertEqual(stoppedResult.status, .stop1080)
        XCTAssertNotNil(stoppedResult.diagnosticWorkload)
        XCTAssertNil(stoppedResult.recommendedWorkload)

        let blocked = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 8.1
        )
        let blockedResult = BenchmarkDecision.evaluate(
            measurements: blocked,
            thresholds: .approved
        )
        XCTAssertEqual(blockedResult.status, .blocked4K)
        XCTAssertEqual(blockedResult.diagnosticWorkload?.output, .hd1080)
        XCTAssertNil(blockedResult.recommendedWorkload)

        var passing = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0
        )
        passing += try measurements(
            include4K: true,
            p95At1080: 3.5,
            p95At4K: 7.5,
            grid: SampleGrid(width: 1920, height: 1080),
            steps: 32
        )
        let result = BenchmarkDecision.evaluate(
            measurements: passing,
            thresholds: .approved
        )
        XCTAssertEqual(result.status, .go)
        XCTAssertEqual(
            result.recommendedWorkload?.samples,
            SampleGrid(width: 1920, height: 1080)
        )
        XCTAssertEqual(result.recommendedWorkload?.integrationSteps, 32)
    }

    func testThermalDecisionRequiresOnlyTheFoldFixture() throws {
        var thermal = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            fixtures: [.fold]
        )
        for index in thermal.indices {
            thermal[index].frameCount = 36_000
            thermal[index].measuredWallSeconds = 600.0
            thermal[index].thermalTargetSeconds = 600.0
            thermal[index].thermalTargetFramesPerSecond = 60.0
        }
        XCTAssertEqual(
            BenchmarkDecision.evaluate(
                measurements: thermal,
                thresholds: .approved,
                requiredFixtures: [.fold]
            ).status,
            .go
        )

        thermal[0].measuredWallSeconds = 599.9
        XCTAssertNotEqual(
            BenchmarkDecision.evaluate(
                measurements: thermal,
                thresholds: .approved,
                requiredFixtures: [.fold]
            ).status,
            .go
        )
        for index in thermal.indices {
            thermal[index].frameCount = 60
            thermal[index].measuredWallSeconds = 1.0
            thermal[index].thermalTargetSeconds = 1.0
        }
        XCTAssertNotEqual(
            BenchmarkDecision.evaluate(
                measurements: thermal,
                thresholds: .approved,
                requiredFixtures: [.fold]
            ).status,
            .go
        )
    }

    func testNormalizedExposureMustHoldAcrossResolutionEvenWhenReferenceDeltasPass() throws {
        var values = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0
        )
        let index = try XCTUnwrap(values.firstIndex {
            $0.workload.output == .uhd4K && $0.workload.fixture == .fold
        })
        values[index].integratedExposure *= 1.03
        values[index].relativeExposureDelta = 0.0
        XCTAssertEqual(
            BenchmarkDecision.evaluate(
                measurements: values,
                thresholds: .approved
            ).status,
            .blocked4K
        )
    }

    func testReferenceExposureDeltaNormalizesByOutputPixelArea() {
        let hdPixels = Double(RasterSize.hd1080.width * RasterSize.hd1080.height)
        let uhdPixels = Double(RasterSize.uhd4K.width * RasterSize.uhd4K.height)
        XCTAssertEqual(
            BenchmarkDecision.normalizedExposureDelta(
                baselineExposure: hdPixels,
                baselineOutput: .hd1080,
                comparisonExposure: uhdPixels,
                comparisonOutput: .uhd4K
            ),
            0.0,
            accuracy: 1e-12
        )
        XCTAssertGreaterThan(
            BenchmarkDecision.normalizedExposureDelta(
                baselineExposure: hdPixels,
                baselineOutput: .hd1080,
                comparisonExposure: uhdPixels * 1.03,
                comparisonOutput: .uhd4K
            ),
            SpikeThresholds.approved.exposureDeltaFraction
        )
    }

    func testNormalizedExposureMustHoldAcrossEveryTestedQualityTier() throws {
        var low = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            grid: SampleGrid(width: 480, height: 270),
            steps: 8
        )
        var high = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            grid: SampleGrid(width: 960, height: 540),
            steps: 16
        )
        XCTAssertEqual(
            BenchmarkDecision.evaluate(
                measurements: low + high,
                thresholds: .approved
            ).status,
            .go
        )
        for index in low.indices {
            low[index].integratedExposure *= 0.98
            low[index].relativeExposureDelta = 0.02
        }
        for index in high.indices {
            high[index].integratedExposure *= 1.02
            high[index].relativeExposureDelta = 0.02
        }
        XCTAssertEqual(
            BenchmarkDecision.evaluate(
                measurements: low + high,
                thresholds: .approved
            ).status,
            .stop1080
        )
    }

    func testEqualQualityTieBreakIsIndependentOfInputOrder() throws {
        let tied = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            grid: SampleGrid(width: 480, height: 270),
            steps: 32
        ) + measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            grid: SampleGrid(width: 960, height: 540),
            steps: 8
        )
        for _ in 0..<20 {
            let result = BenchmarkDecision.evaluate(
                measurements: tied.shuffled(),
                thresholds: .approved
            )
            XCTAssertEqual(result.status, .go)
            XCTAssertEqual(
                result.recommendedWorkload?.samples,
                SampleGrid(width: 960, height: 540)
            )
            XCTAssertEqual(result.recommendedWorkload?.integrationSteps, 8)
        }
    }

    func testEverySignedNumericalResourceAndAdaptiveGateRejects() throws {
        typealias Mutation = (String, (inout BenchmarkMeasurement) -> Void)
        let signedAndGateMutations: [Mutation] = [
            ("frame count", { $0.frameCount = 0 }),
            ("p50 negative", { $0.p50GPUMilliseconds = -1 }),
            ("p95 negative", { $0.p95GPUMilliseconds = -1 }),
            ("p50 exceeds p95", { $0.p50GPUMilliseconds = 3.1 }),
            ("CPU time negative", { $0.meanCPUMilliseconds = -1 }),
            ("wall time nonpositive", { $0.measuredWallSeconds = 0 }),
            ("allocation nonpositive", { $0.allocatedBytes = 0 }),
            ("field evaluations nonpositive", { $0.fieldEvaluationsPerFrame = 0 }),
            ("primitive instances nonpositive", { $0.primitiveInstancesPerFrame = 0 }),
            ("exposure nonpositive", { $0.integratedExposure = 0 }),
            ("exposure delta negative", { $0.relativeExposureDelta = -1 }),
            ("centroid negative", { $0.centroidDistancePixels = -1 }),
            ("contour negative", { $0.contourDistancePixels = -1 }),
            ("identity RMS negative", { $0.identityRMSPixels = -1 }),
            ("identity RMS high", { $0.identityRMSPixels = 0.251 }),
            ("identity max negative", { $0.identityMaxPixels = -1 }),
            ("identity max high", { $0.identityMaxPixels = 0.751 }),
            ("oracle RMS negative", { $0.oracleRMSPixels = -1 }),
            ("oracle RMS high", { $0.oracleRMSPixels = 0.251 }),
            ("oracle max negative", { $0.oracleMaxPixels = -1 }),
            ("oracle max high", { $0.oracleMaxPixels = 1.001 }),
            ("drift negative", { $0.maximumRelativeMomentumDrift = -1 }),
            ("drift high", { $0.maximumRelativeMomentumDrift = 0.000011 }),
            ("branch retention", { $0.branchRetentionPassed = false }),
            ("invalid samples", { $0.invalidSampleCount = 1 }),
            ("adaptive invalid", { $0.adaptiveInvalidIntervalCount = 1 }),
            ("adaptive tolerance", { $0.adaptiveToleranceFailureCount = 1 }),
            ("resource creation", {
                $0.measuredResourceCreations = MetalResourceCreationCounts(buffers: 1)
            }),
        ]

        func nonFiniteMutations(_ value: Double, label: String) -> [Mutation] {
            [
                ("p50 \(label)", { $0.p50GPUMilliseconds = value }),
                ("p95 \(label)", { $0.p95GPUMilliseconds = value }),
                ("CPU time \(label)", { $0.meanCPUMilliseconds = value }),
                ("wall time \(label)", { $0.measuredWallSeconds = value }),
                ("exposure \(label)", { $0.integratedExposure = value }),
                ("exposure delta \(label)", { $0.relativeExposureDelta = value }),
                ("centroid \(label)", { $0.centroidDistancePixels = value }),
                ("contour \(label)", { $0.contourDistancePixels = value }),
                ("identity RMS \(label)", { $0.identityRMSPixels = value }),
                ("identity max \(label)", { $0.identityMaxPixels = value }),
                ("oracle RMS \(label)", { $0.oracleRMSPixels = value }),
                ("oracle max \(label)", { $0.oracleMaxPixels = value }),
                ("drift \(label)", { $0.maximumRelativeMomentumDrift = value }),
            ]
        }
        let mutations = signedAndGateMutations
            + nonFiniteMutations(.nan, label: "NaN")
            + nonFiniteMutations(.infinity, label: "infinity")
        for (label, mutate) in mutations {
            var candidate = try measurements(
                include4K: true,
                p95At1080: 3.0,
                p95At4K: 7.0
            )
            mutate(&candidate[0])
            XCTAssertNotEqual(
                BenchmarkDecision.evaluate(
                    measurements: candidate,
                    thresholds: .approved
                ).status, .go, label
            )
        }
        XCTAssertEqual(
            BenchmarkDecision.evaluate(
                measurements: try measurements(
                    include4K: true,
                    p95At1080: 3.0,
                    p95At4K: 7.0
                ),
                thresholds: .approved,
                referenceValidationPassed: false
            ).status,
            .stop1080
        )
    }

    func testFailingNumericalReportStillJSONEncodes() throws {
        var values = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0
        )
        values[0].oracleMaxPixels = SpikeThresholds.approved.oracleMaxPixels + 1.0
        values[0].invalidSampleCount = 1
        let decision = BenchmarkDecision.evaluate(
            measurements: values,
            thresholds: .approved
        )
        let report = BenchmarkReport(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            hardware: HardwareRecord(
                deviceName: "Apple M5 Max",
                gpuCoreCount: 40,
                memoryGB: 128,
                operatingSystem: "test",
                swiftVersion: "test"
            ),
            thresholds: .approved,
            measurements: values,
            status: decision.status,
            recommendation: decision.recommendation,
            recommendedWorkload: decision.recommendedWorkload,
            referenceValidationPassed: true,
            referenceIdentityNormalizedExposureDelta: 0.0,
            referenceFoldNormalizedExposureDelta: 0.0
        )
        XCTAssertNoThrow(try JSONEncoder().encode(report))
        XCTAssertNotEqual(report.status, .go)
    }

    private func validThermalReport(
        matrix: BenchmarkReport
    ) throws -> BenchmarkReport {
        let selected = try XCTUnwrap(matrix.recommendedWorkload)
        var values = try measurements(
            include4K: true,
            p95At1080: 3.0,
            p95At4K: 7.0,
            grid: selected.samples,
            steps: selected.integrationSteps,
            fixtures: [.fold],
            representation: selected.representation
        )
        for index in values.indices {
            values[index].frameCount = 36_000
            values[index].measuredWallSeconds = 600.0
            values[index].thermalTargetSeconds = 600.0
            values[index].thermalTargetFramesPerSecond = 60.0
        }
        let decision = BenchmarkDecision.evaluate(
            measurements: values,
            thresholds: matrix.thresholds,
            requiredFixtures: [.fold]
        )
        return BenchmarkReport(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            hardware: matrix.hardware,
            thresholds: matrix.thresholds,
            measurements: values,
            status: decision.status,
            recommendation: decision.recommendation,
            recommendedWorkload: decision.recommendedWorkload,
            referenceValidationPassed: true,
            referenceIdentityNormalizedExposureDelta: 0.0,
            referenceFoldNormalizedExposureDelta: 0.0
        )
    }

    private func validMatrixReport(
        p95At1080: Double = 3.0,
        p95At4K: Double = 7.0
    ) throws -> BenchmarkReport {
        let grids = [
            SampleGrid(width: 480, height: 270),
            SampleGrid(width: 960, height: 540),
            SampleGrid(width: 1280, height: 720),
            SampleGrid(width: 1920, height: 1080),
        ]
        var values: [BenchmarkMeasurement] = []
        for representation in DepositionRepresentation.allCases {
            for grid in grids {
                for steps in [8, 16, 32] {
                    values += try measurements(
                        include4K: true,
                        p95At1080: p95At1080,
                        p95At4K: p95At4K,
                        grid: grid,
                        steps: steps,
                        representation: representation
                    )
                }
            }
        }
        let decision = BenchmarkDecision.evaluate(
            measurements: values,
            thresholds: .approved
        )
        return BenchmarkReport(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            hardware: HardwareRecord(
                deviceName: "Apple M5 Max",
                gpuCoreCount: 40,
                memoryGB: 128,
                operatingSystem: "test",
                swiftVersion: "test"
            ),
            thresholds: .approved,
            measurements: values,
            status: decision.status,
            recommendation: decision.recommendation,
            recommendedWorkload: decision.recommendedWorkload,
            referenceValidationPassed: true,
            referenceIdentityNormalizedExposureDelta: 0.0,
            referenceFoldNormalizedExposureDelta: 0.0
        )
    }

    private func assertSelectionRejected(
        _ report: BenchmarkReport,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "wobbulator-\(label)-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: .atomic)
        let options = try BenchmarkOptions.parse([
            "--suite", "thermal",
            "--output", "/tmp/wobbulator-thermal-test.json",
            "--selection-report", url.path,
        ])
        XCTAssertThrowsError(
            try options.selectedThermalWorkloads(),
            label,
            file: file,
            line: line
        )
    }

    private func measurements(
        include4K: Bool,
        p95At1080: Double,
        p95At4K: Double,
        grid: SampleGrid = SampleGrid(width: 960, height: 540),
        steps: Int = 16,
        fixtures: [SpikeFixture] = [.identity, .fold],
        representation: DepositionRepresentation = .scanlineRibbon
    ) throws -> [BenchmarkMeasurement] {
        let outputs: [RasterSize] = include4K ? [.hd1080, .uhd4K] : [.hd1080]
        return try outputs.flatMap { output in
            try fixtures.map { fixture in
                let workload = try SpikeWorkload(
                    output: output,
                    samples: grid,
                    integrationSteps: steps,
                    beamWidthPixelsAt1080: 1.25,
                    fixture: fixture,
                    representation: representation
                )
                return BenchmarkMeasurement(
                    workload: workload,
                    frameCount: 240,
                    p50GPUMilliseconds: output == .hd1080 ? p95At1080 * 0.8 : p95At4K * 0.8,
                    p95GPUMilliseconds: output == .hd1080 ? p95At1080 : p95At4K,
                    meanCPUMilliseconds: 0.3,
                    measuredWallSeconds: 4.0,
                    allocatedBytes: 1,
                    fieldEvaluationsPerFrame: grid.count * steps,
                    primitiveInstancesPerFrame: (grid.width - 1) * grid.height,
                    integratedExposure: Double(output.width) * Double(output.height),
                    relativeExposureDelta: 0.01,
                    centroidDistancePixels: output == .hd1080 ? 0.5 : 1.0,
                    contourDistancePixels: output == .hd1080 ? 1.0 : 2.0,
                    identityRMSPixels: 0.1,
                    identityMaxPixels: 0.2,
                    oracleRMSPixels: 0.1,
                    oracleMaxPixels: 0.2,
                    maximumRelativeMomentumDrift: 1e-7,
                    branchRetentionPassed: true,
                    invalidSampleCount: 0,
                    adaptiveInvalidIntervalCount: 0,
                    adaptiveToleranceFailureCount: 0,
                    measuredResourceCreations: .zero
                )
            }
        }
    }
}
~~~

- [ ] **Step 2: Run the benchmark tests to verify RED**

Run:

~~~bash
swift test --package-path WobbulatorKit --filter BenchmarkRunnerTests
~~~

Expected: compilation fails because the benchmark support module, workload expansion,
percentile helper, and decision engine do not exist.

- [ ] **Step 3: Implement exact CLI options and workload expansion**

Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkOptions.swift`:

~~~swift
import Foundation
import WobbulatorCore

public enum BenchmarkSuite: String, Codable, Sendable {
    case quick
    case matrix
    case thermal
}

public struct BenchmarkOptions: Equatable, Sendable {
    public var suite: BenchmarkSuite
    public var outputURL: URL
    public var decisionURL: URL?
    public var previewDirectoryURL: URL?
    public var selectionReportURL: URL?
    public var warmupFrames: Int
    public var measuredFrames: Int
    public var thermalSeconds: Double

    public static func parse(_ arguments: [String]) throws -> BenchmarkOptions {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw WobbulatorSpikeError.invalidArguments("expected --key value pairs")
            }
            guard values[key] == nil else {
                throw WobbulatorSpikeError.invalidArguments("duplicate argument \(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        let allowed = Set([
            "--suite", "--output", "--decision", "--previews", "--selection-report",
            "--warmup-frames", "--measured-frames", "--thermal-seconds",
        ])
        let unknown = Set(values.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw WobbulatorSpikeError.invalidArguments(
                "unknown arguments: \(unknown.sorted().joined(separator: ", "))"
            )
        }
        guard let suiteText = values["--suite"],
            let suite = BenchmarkSuite(rawValue: suiteText)
        else {
            throw WobbulatorSpikeError.invalidArguments(
                "--suite must be quick, matrix, or thermal"
            )
        }
        guard let output = values["--output"] else {
            throw WobbulatorSpikeError.invalidArguments("--output is required")
        }
        func positiveInt(_ key: String, default fallback: Int) throws -> Int {
            guard let raw = values[key] else { return fallback }
            guard let value = Int(raw), value > 0 else {
                throw WobbulatorSpikeError.invalidArguments("\(key) must be positive")
            }
            return value
        }
        func positiveDouble(_ key: String, default fallback: Double) throws -> Double {
            guard let raw = values[key] else { return fallback }
            guard let value = Double(raw), value.isFinite, value > 0 else {
                throw WobbulatorSpikeError.invalidArguments(
                    "\(key) must be finite and positive"
                )
            }
            return value
        }
        let selection = values["--selection-report"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if suite == .thermal, selection == nil {
            throw WobbulatorSpikeError.invalidArguments(
                "--selection-report is required for the thermal suite"
            )
        }
        let thermalSeconds = try positiveDouble("--thermal-seconds", default: 600)
        if suite == .thermal, thermalSeconds < 600 {
            throw WobbulatorSpikeError.invalidArguments(
                "the Phase 1 thermal suite requires at least 600 seconds per workload"
            )
        }
        return BenchmarkOptions(
            suite: suite,
            outputURL: URL(fileURLWithPath: output).standardizedFileURL,
            decisionURL: values["--decision"].map {
                URL(fileURLWithPath: $0).standardizedFileURL
            },
            previewDirectoryURL: values["--previews"].map {
                URL(fileURLWithPath: $0).standardizedFileURL
            },
            selectionReportURL: selection,
            warmupFrames: try positiveInt("--warmup-frames", default: 120),
            measuredFrames: try positiveInt("--measured-frames", default: 240),
            thermalSeconds: thermalSeconds
        )
    }

    public static func workloads(for suite: BenchmarkSuite) throws -> [SpikeWorkload] {
        guard suite != .thermal else {
            throw WobbulatorSpikeError.invalidArguments(
                "thermal workloads come from --selection-report"
            )
        }
        let grids = suite == .quick
            ? [SampleGrid(width: 960, height: 540)]
            : [
                SampleGrid(width: 480, height: 270),
                SampleGrid(width: 960, height: 540),
                SampleGrid(width: 1280, height: 720),
                SampleGrid(width: 1920, height: 1080),
            ]
        let stepCounts = suite == .quick ? [16] : [8, 16, 32]
        let representations = DepositionRepresentation.allCases
        var result: [SpikeWorkload] = []
        var conditionIndex = 0
        for output in [RasterSize.hd1080, .uhd4K] {
            for grid in grids {
                for steps in stepCounts {
                    for fixture in [SpikeFixture.identity, .fold] {
                        let rotation = conditionIndex % representations.count
                        for offset in 0..<representations.count {
                            let representation = representations[
                                (rotation + offset) % representations.count
                            ]
                            result.append(
                                try SpikeWorkload(
                                    output: output,
                                    samples: grid,
                                    integrationSteps: steps,
                                    beamWidthPixelsAt1080: 1.25,
                                    fixture: fixture,
                                    representation: representation
                                )
                            )
                        }
                        conditionIndex += 1
                    }
                }
            }
        }
        return result
    }

    public func selectedThermalWorkloads() throws -> [SpikeWorkload] {
        guard suite == .thermal, let selectionReportURL else {
            throw WobbulatorSpikeError.invalidArguments(
                "thermal selection report is unavailable"
            )
        }
        let data = try Data(contentsOf: selectionReportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(BenchmarkReport.self, from: data)
        let expectedWorkloads = Set(try Self.workloads(for: .matrix))
        let reportedWorkloads = Set(report.measurements.map(\.workload))
        guard report.schemaVersion == 1,
            report.referenceValidationPassed,
            report.referenceIdentityNormalizedExposureDelta.isFinite,
            report.referenceIdentityNormalizedExposureDelta >= 0,
            report.referenceIdentityNormalizedExposureDelta
                <= report.thresholds.exposureDeltaFraction,
            report.referenceFoldNormalizedExposureDelta.isFinite,
            report.referenceFoldNormalizedExposureDelta >= 0,
            report.referenceFoldNormalizedExposureDelta
                <= report.thresholds.exposureDeltaFraction,
            report.thresholds == .approved,
            report.hardware.deviceName.localizedCaseInsensitiveContains("M5 Max"),
            report.hardware.gpuCoreCount == 40,
            report.hardware.memoryGB >= 120,
            report.measurements.count == 144,
            reportedWorkloads == expectedWorkloads
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "selection report failed schema, authority, threshold, hardware, or matrix gates"
            )
        }
        let recomputed = BenchmarkDecision.evaluate(
            measurements: report.measurements,
            thresholds: .approved,
            referenceValidationPassed: true
        )
        guard recomputed.status == .go,
            report.status == recomputed.status,
            report.recommendation == recomputed.recommendation,
            report.recommendedWorkload == recomputed.recommendedWorkload,
            let selected = recomputed.recommendedWorkload
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "selection report decision does not reproduce from its 144 measurements"
            )
        }
        return try [RasterSize.hd1080, .uhd4K].map { output in
            try SpikeWorkload(
                output: output,
                samples: selected.samples,
                integrationSteps: selected.integrationSteps,
                beamWidthPixelsAt1080: selected.beamWidthPixelsAt1080,
                fixtureAmount: selected.fixtureAmount,
                fixture: .fold,
                representation: selected.representation
            )
        }
    }
}
~~~

The quick suite is exactly 3 representations x 2 resolutions x 2 fixtures = 12 cases. The full
matrix is exactly 3 x 2 x 2 x 4 grids x 3 integration counts = 144 cases. Thermal contains the
selected fold workload at 1080p and 4K, each paced for ten minutes by default. Matrix order keeps
the three representations adjacent for every otherwise identical condition and rotates which
representation leads each triplet; each representation leads exactly 16 of the 48 triplets. This
records and balances order-dependent thermal drift during screening.

- [ ] **Step 4: Implement threshold filtering, ranking, and the three terminal states**

Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkDecision.swift`:

~~~swift
import Foundation
import WobbulatorCore

public struct BenchmarkDecisionResult: Equatable, Sendable {
    public var status: BenchmarkStatus
    public var recommendation: String
    public var recommendedWorkload: SpikeWorkload?
    public var diagnosticWorkload: SpikeWorkload?
}

public enum BenchmarkDecision {
    private struct CandidateKey: Hashable {
        var representation: DepositionRepresentation
        var samples: SampleGrid
        var integrationSteps: Int
    }

    public static func normalizedExposureDelta(
        baselineExposure: Double,
        baselineOutput: RasterSize,
        comparisonExposure: Double,
        comparisonOutput: RasterSize
    ) -> Double {
        let baselinePixels = Double(baselineOutput.width) * Double(baselineOutput.height)
        let comparisonPixels = Double(comparisonOutput.width) * Double(comparisonOutput.height)
        guard baselineExposure.isFinite, baselineExposure > 0,
            comparisonExposure.isFinite, comparisonExposure > 0,
            baselinePixels.isFinite, baselinePixels > 0,
            comparisonPixels.isFinite, comparisonPixels > 0
        else {
            return .infinity
        }
        let baseline = baselineExposure / baselinePixels
        let comparison = comparisonExposure / comparisonPixels
        return abs(comparison - baseline) / baseline
    }

    public static func maximumNormalizedExposureSpread(
        _ measurements: [BenchmarkMeasurement]
    ) -> Double {
        guard !measurements.isEmpty else { return .infinity }
        var minimum = Double.infinity
        var maximum = -Double.infinity
        for measurement in measurements {
            let output = measurement.workload.output
            guard output.width > 0, output.height > 0,
                measurement.integratedExposure.isFinite,
                measurement.integratedExposure > 0,
                Double(output.width).isFinite,
                Double(output.height).isFinite
            else {
                return .infinity
            }
            let pixels = Double(output.width) * Double(output.height)
            let normalized = measurement.integratedExposure / pixels
            guard pixels.isFinite, pixels > 0,
                normalized.isFinite, normalized > 0
            else {
                return .infinity
            }
            minimum = min(minimum, normalized)
            maximum = max(maximum, normalized)
        }
        return (maximum - minimum) / minimum
    }

    public static func evaluate(
        measurements: [BenchmarkMeasurement],
        thresholds: SpikeThresholds,
        requiredFixtures: [SpikeFixture] = [.identity, .fold],
        referenceValidationPassed: Bool = true
    ) -> BenchmarkDecisionResult {
        guard referenceValidationPassed else {
            return BenchmarkDecisionResult(
                status: .stop1080,
                recommendation: "The bounded CPU reference authority gate failed.",
                recommendedWorkload: nil,
                diagnosticWorkload: nil
            )
        }
        guard let lastRequiredFixture = requiredFixtures.last else {
            return BenchmarkDecisionResult(
                status: .stop1080,
                recommendation: "At least one required fixture is mandatory.",
                recommendedWorkload: nil,
                diagnosticWorkload: nil
            )
        }
        let grouped = Dictionary(grouping: measurements) {
            CandidateKey(
                representation: $0.workload.representation,
                samples: $0.workload.samples,
                integrationSteps: $0.workload.integrationSteps
            )
        }
        func worstP95(_ key: CandidateKey) -> Double {
            let values = grouped[key]!.map(\.p95GPUMilliseconds)
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                return .infinity
            }
            return values.max() ?? .infinity
        }
        let rankedKeys = grouped.keys.sorted { lhs, rhs in
            let lhsQuality = lhs.samples.count * lhs.integrationSteps
            let rhsQuality = rhs.samples.count * rhs.integrationSteps
            if lhsQuality != rhsQuality { return lhsQuality > rhsQuality }
            let lhsWorst = worstP95(lhs)
            let rhsWorst = worstP95(rhs)
            if lhsWorst != rhsWorst { return lhsWorst < rhsWorst }
            if lhs.samples.width != rhs.samples.width {
                return lhs.samples.width > rhs.samples.width
            }
            if lhs.samples.height != rhs.samples.height {
                return lhs.samples.height > rhs.samples.height
            }
            if lhs.integrationSteps != rhs.integrationSteps {
                return lhs.integrationSteps > rhs.integrationSteps
            }
            return lhs.representation.rawValue < rhs.representation.rawValue
        }

        func qualifies(_ key: CandidateKey, outputs: [RasterSize]) -> Bool {
            guard let cases = grouped[key] else { return false }
            guard outputs.allSatisfy({ output in
                requiredFixtures.allSatisfy { fixture in
                    let matching = cases.filter {
                        $0.workload.output == output && $0.workload.fixture == fixture
                    }
                    guard matching.count == 1, let measurement = matching.first else {
                        return false
                    }
                    return passes(
                        measurement,
                        thresholds: thresholds
                    )
                }
            }) else {
                return false
            }
            let requestedOutputs = Set(outputs)
            return requiredFixtures.allSatisfy { fixture in
                let exposureRows = measurements.filter {
                    $0.workload.representation == key.representation
                        && requestedOutputs.contains($0.workload.output)
                        && $0.workload.fixture == fixture
                }
                return maximumNormalizedExposureSpread(
                    exposureRows
                ) <= thresholds.exposureDeltaFraction
            }
        }

        if let winner = rankedKeys.first(where: {
            qualifies($0, outputs: [.hd1080, .uhd4K])
        }) {
            let workload = grouped[winner]!.first(where: {
                $0.workload.output == .uhd4K
                    && $0.workload.fixture == lastRequiredFixture
            })!.workload
            return BenchmarkDecisionResult(
                status: .go,
                recommendation:
                    "\(winner.representation.rawValue), \(winner.samples.width)x"
                    + "\(winner.samples.height), \(winner.integrationSteps) steps",
                recommendedWorkload: workload,
                diagnosticWorkload: workload
            )
        }
        if let best1080 = rankedKeys.first(where: {
            qualifies($0, outputs: [.hd1080])
        }) {
            let diagnostic = grouped[best1080]!.first(where: {
                $0.workload.output == .hd1080
                    && $0.workload.fixture == lastRequiredFixture
            })!.workload
            return BenchmarkDecisionResult(
                status: .blocked4K,
                recommendation: "No candidate satisfies the paired 4K gate.",
                recommendedWorkload: nil,
                diagnosticWorkload: diagnostic
            )
        }
        let diagnostic = rankedKeys.first.flatMap { key in
            grouped[key]!.first(where: {
                $0.workload.output == .hd1080
                    && $0.workload.fixture == lastRequiredFixture
            })?.workload ?? grouped[key]!.first?.workload
        }
        return BenchmarkDecisionResult(
            status: .stop1080,
            recommendation: "No candidate satisfies the 1080p gate.",
            recommendedWorkload: nil,
            diagnosticWorkload: diagnostic
        )
    }

    public static func passes(
        _ measurement: BenchmarkMeasurement,
        thresholds: SpikeThresholds
    ) -> Bool {
        let is4K = measurement.workload.output == .uhd4K
        let timeLimit = is4K
            ? thresholds.p95Milliseconds4K
            : thresholds.p95Milliseconds1080
        let centroidLimit = is4K
            ? thresholds.centroidPixels4K
            : thresholds.centroidPixels1080
        let contourLimit = is4K
            ? thresholds.contourPixels4K
            : thresholds.contourPixels1080
        let thermalContractPasses: Bool
        switch (
            measurement.thermalTargetSeconds,
            measurement.thermalTargetFramesPerSecond
        ) {
        case (nil, nil):
            thermalContractPasses = true
        case let (targetSeconds?, targetFramesPerSecond?):
            thermalContractPasses = targetSeconds.isFinite
                && targetSeconds >= 600
                && targetFramesPerSecond == 60.0
                && measurement.measuredWallSeconds >= targetSeconds
                && Double(measurement.frameCount) >= targetSeconds * 50.0
        default:
            thermalContractPasses = false
        }
        return measurement.frameCount > 0
            && measurement.p50GPUMilliseconds.isFinite
            && measurement.p50GPUMilliseconds > 0
            && measurement.p95GPUMilliseconds.isFinite
            && measurement.p95GPUMilliseconds > 0
            && measurement.p50GPUMilliseconds <= measurement.p95GPUMilliseconds
            && measurement.p95GPUMilliseconds <= timeLimit
            && measurement.meanCPUMilliseconds.isFinite
            && measurement.meanCPUMilliseconds >= 0
            && measurement.measuredWallSeconds.isFinite
            && measurement.measuredWallSeconds > 0
            && thermalContractPasses
            && measurement.allocatedBytes > 0
            && measurement.fieldEvaluationsPerFrame > 0
            && measurement.primitiveInstancesPerFrame > 0
            && measurement.integratedExposure.isFinite
            && measurement.integratedExposure > 0
            && measurement.relativeExposureDelta.isFinite
            && measurement.relativeExposureDelta >= 0
            && measurement.relativeExposureDelta <= thresholds.exposureDeltaFraction
            && measurement.centroidDistancePixels.isFinite
            && measurement.centroidDistancePixels >= 0
            && measurement.centroidDistancePixels <= centroidLimit
            && measurement.contourDistancePixels.isFinite
            && measurement.contourDistancePixels >= 0
            && measurement.contourDistancePixels <= contourLimit
            && measurement.identityRMSPixels.isFinite
            && measurement.identityRMSPixels >= 0
            && measurement.identityRMSPixels <= thresholds.identityRMSPixels
            && measurement.identityMaxPixels.isFinite
            && measurement.identityMaxPixels >= 0
            && measurement.identityMaxPixels <= thresholds.identityMaxPixels
            && measurement.oracleRMSPixels.isFinite
            && measurement.oracleRMSPixels >= 0
            && measurement.oracleRMSPixels <= thresholds.oracleRMSPixels
            && measurement.oracleMaxPixels.isFinite
            && measurement.oracleMaxPixels >= 0
            && measurement.oracleMaxPixels <= thresholds.oracleMaxPixels
            && measurement.maximumRelativeMomentumDrift.isFinite
            && measurement.maximumRelativeMomentumDrift >= 0
            && measurement.maximumRelativeMomentumDrift <= thresholds.relativeMomentumDrift
            && measurement.branchRetentionPassed
            && measurement.invalidSampleCount == 0
            && measurement.adaptiveInvalidIntervalCount == 0
            && measurement.adaptiveToleranceFailureCount == 0
            && measurement.measuredResourceCreations == .zero
    }

    public static func selectedPreviewFilename(
        selected: SpikeWorkload,
        output: RasterSize,
        fixture: SpikeFixture
    ) -> String {
        "selected-\(selected.representation.rawValue)-\(output.width)x\(output.height)-"
            + "grid\(selected.samples.width)x\(selected.samples.height)-"
            + "steps\(selected.integrationSteps)-\(fixture.rawValue).ppm"
    }

    public static func markdown(
        matrix: BenchmarkReport,
        thermal: BenchmarkReport? = nil
    ) -> String {
        struct GateRow {
            var gate: String
            var observed: String
            var limit: String
            var result: String

            var markdown: String {
                "| \(gate) | \(observed) | \(limit) | \(result) |"
            }
        }

        func maximum(_ values: [Double]) -> Double {
            guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
                return .infinity
            }
            return values.max() ?? .infinity
        }

        func decimal(_ value: Double, suffix: String = "") -> String {
            value.isFinite ? String(format: "%.6f", value) + suffix : "unavailable"
        }

        func pass(_ condition: Bool) -> String { condition ? "PASS" : "FAIL" }

        let finalReport = thermal ?? matrix
        let matrixDecision = evaluate(
            measurements: matrix.measurements,
            thresholds: matrix.thresholds,
            referenceValidationPassed: matrix.referenceValidationPassed
        )
        let evidenceCandidate = matrix.recommendedWorkload
            ?? matrixDecision.diagnosticWorkload
        let matrixCandidateRows: [BenchmarkMeasurement]
        if let evidenceCandidate {
            matrixCandidateRows = matrix.measurements.filter {
                $0.workload.representation == evidenceCandidate.representation
                    && $0.workload.samples == evidenceCandidate.samples
                    && $0.workload.integrationSteps == evidenceCandidate.integrationSteps
            }
        } else {
            matrixCandidateRows = []
        }
        let thermalRows = thermal?.measurements ?? []
        let evidenceRows = matrixCandidateRows + thermalRows
        let hdRows = evidenceRows.filter { $0.workload.output == .hd1080 }
        let uhdRows = evidenceRows.filter { $0.workload.output == .uhd4K }
        let p951080 = maximum(hdRows.map(\.p95GPUMilliseconds))
        let p954K = maximum(uhdRows.map(\.p95GPUMilliseconds))
        let relativeExposure = maximum(evidenceRows.map(\.relativeExposureDelta))
        let centroid1080 = maximum(hdRows.map(\.centroidDistancePixels))
        let centroid4K = maximum(uhdRows.map(\.centroidDistancePixels))
        let contour1080 = maximum(hdRows.map(\.contourDistancePixels))
        let contour4K = maximum(uhdRows.map(\.contourDistancePixels))
        let identityRMS = maximum(evidenceRows.map(\.identityRMSPixels))
        let identityMaximum = maximum(evidenceRows.map(\.identityMaxPixels))
        let oracleRMS = maximum(evidenceRows.map(\.oracleRMSPixels))
        let oracleMaximum = maximum(evidenceRows.map(\.oracleMaxPixels))
        let momentumDrift = maximum(evidenceRows.map(\.maximumRelativeMomentumDrift))
        let branchFailures = evidenceRows.filter { !$0.branchRetentionPassed }.count
        let invalidSamples = evidenceRows.reduce(0) { $0 + $1.invalidSampleCount }
        let adaptiveInvalid = evidenceRows.reduce(0) {
            $0 + $1.adaptiveInvalidIntervalCount
        }
        let adaptiveTolerance = evidenceRows.reduce(0) {
            $0 + $1.adaptiveToleranceFailureCount
        }
        let resourceCreations = evidenceRows.reduce(0) {
            $0 + $1.measuredResourceCreations.total
        }
        let resourcePass = evidenceRows.allSatisfy {
            $0.measuredResourceCreations == .zero
        }

        let representationExposureRows: [BenchmarkMeasurement]
        if let evidenceCandidate {
            representationExposureRows = matrix.measurements.filter {
                $0.workload.representation == evidenceCandidate.representation
            } + thermalRows
        } else {
            representationExposureRows = []
        }
        let exposureSpreads = [SpikeFixture.identity, .fold].compactMap { fixture in
            let rows = representationExposureRows.filter {
                $0.workload.fixture == fixture
            }
            return rows.isEmpty ? nil : maximumNormalizedExposureSpread(rows)
        }
        let normalizedExposureSpread = maximum(exposureSpreads)
        let referenceFlagsPass = matrix.referenceValidationPassed
            && (thermal?.referenceValidationPassed ?? true)
        let referenceExposureDelta = maximum([
            matrix.referenceIdentityNormalizedExposureDelta,
            matrix.referenceFoldNormalizedExposureDelta,
            thermal?.referenceIdentityNormalizedExposureDelta ?? 0.0,
            thermal?.referenceFoldNormalizedExposureDelta ?? 0.0,
        ])
        let thresholds = matrix.thresholds
        let referencePass = referenceFlagsPass
            && referenceExposureDelta <= thresholds.exposureDeltaFraction
        var rows = [
            GateRow(
                gate: "Matrix workload universe",
                observed: "\(matrix.measurements.count) cases",
                limit: "exactly 144",
                result: pass(matrix.measurements.count == 144)
            ),
            GateRow(
                gate: "CPU/GPU reference authority",
                observed: referencePass
                    ? "pass; worst normalized delta \(decimal(referenceExposureDelta))"
                    : "failed; worst normalized delta \(decimal(referenceExposureDelta))",
                limit: decimal(thresholds.exposureDeltaFraction),
                result: pass(referencePass)
            ),
            GateRow(
                gate: "1080p effect-only p95",
                observed: decimal(p951080, suffix: " ms"),
                limit: decimal(thresholds.p95Milliseconds1080, suffix: " ms"),
                result: pass(p951080 <= thresholds.p95Milliseconds1080)
            ),
            GateRow(
                gate: "4K effect-only p95",
                observed: decimal(p954K, suffix: " ms"),
                limit: decimal(thresholds.p95Milliseconds4K, suffix: " ms"),
                result: pass(p954K <= thresholds.p95Milliseconds4K)
            ),
            GateRow(
                gate: "Candidate/reference exposure delta",
                observed: decimal(relativeExposure),
                limit: decimal(thresholds.exposureDeltaFraction),
                result: pass(relativeExposure <= thresholds.exposureDeltaFraction)
            ),
            GateRow(
                gate: "Exposure spread across resolution and quality",
                observed: decimal(normalizedExposureSpread),
                limit: decimal(thresholds.exposureDeltaFraction),
                result: pass(
                    normalizedExposureSpread <= thresholds.exposureDeltaFraction
                )
            ),
            GateRow(
                gate: "Centroid at 1080p / 4K",
                observed: "\(decimal(centroid1080)) / \(decimal(centroid4K)) px",
                limit: "\(decimal(thresholds.centroidPixels1080)) / "
                    + "\(decimal(thresholds.centroidPixels4K)) px",
                result: pass(
                    centroid1080 <= thresholds.centroidPixels1080
                        && centroid4K <= thresholds.centroidPixels4K
                )
            ),
            GateRow(
                gate: "95-percent contour at 1080p / 4K",
                observed: "\(decimal(contour1080)) / \(decimal(contour4K)) px",
                limit: "\(decimal(thresholds.contourPixels1080)) / "
                    + "\(decimal(thresholds.contourPixels4K)) px",
                result: pass(
                    contour1080 <= thresholds.contourPixels1080
                        && contour4K <= thresholds.contourPixels4K
                )
            ),
            GateRow(
                gate: "Identity RMS / maximum",
                observed: "\(decimal(identityRMS)) / \(decimal(identityMaximum)) px",
                limit: "\(decimal(thresholds.identityRMSPixels)) / "
                    + "\(decimal(thresholds.identityMaxPixels)) px",
                result: pass(
                    identityRMS <= thresholds.identityRMSPixels
                        && identityMaximum <= thresholds.identityMaxPixels
                )
            ),
            GateRow(
                gate: "Oracle RMS / maximum",
                observed: "\(decimal(oracleRMS)) / \(decimal(oracleMaximum)) px",
                limit: "\(decimal(thresholds.oracleRMSPixels)) / "
                    + "\(decimal(thresholds.oracleMaxPixels)) px",
                result: pass(
                    oracleRMS <= thresholds.oracleRMSPixels
                        && oracleMaximum <= thresholds.oracleMaxPixels
                )
            ),
            GateRow(
                gate: "Relative momentum drift",
                observed: decimal(momentumDrift),
                limit: decimal(thresholds.relativeMomentumDrift),
                result: pass(momentumDrift <= thresholds.relativeMomentumDrift)
            ),
            GateRow(
                gate: "Branch retention",
                observed: "\(branchFailures) failed rows",
                limit: "0",
                result: pass(branchFailures == 0 && !evidenceRows.isEmpty)
            ),
            GateRow(
                gate: "Numerically invalid samples",
                observed: "\(invalidSamples)",
                limit: "0",
                result: pass(invalidSamples == 0 && !evidenceRows.isEmpty)
            ),
            GateRow(
                gate: "Adaptive invalid / tolerance failures",
                observed: "\(adaptiveInvalid) / \(adaptiveTolerance)",
                limit: "0 / 0",
                result: pass(
                    adaptiveInvalid == 0 && adaptiveTolerance == 0
                        && !evidenceRows.isEmpty
                )
            ),
            GateRow(
                gate: "Measured persistent resource creations",
                observed: "\(resourceCreations)",
                limit: "0",
                result: pass(resourcePass && !evidenceRows.isEmpty)
            ),
        ]
        if let thermal {
            let sustained = thermal.measurements.count == 2
                && thermal.measurements.allSatisfy {
                    $0.thermalTargetSeconds == 600.0
                        && $0.thermalTargetFramesPerSecond == 60.0
                        && $0.measuredWallSeconds >= 600.0
                        && $0.frameCount >= 30_000
                }
            rows.append(
                GateRow(
                    gate: "Paired sustained thermal proof",
                    observed: "\(thermal.measurements.count) workloads",
                    limit: "1080p + 4K, 600 s each, >= 30,000 frames each",
                    result: pass(sustained)
                )
            )
        } else {
            rows.append(
                GateRow(
                    gate: "Paired sustained thermal proof",
                    observed: matrix.status == .go ? "pending" : "skipped after matrix stop",
                    limit: "required only after matrix go",
                    result: matrix.status == .go ? "PENDING" : "NOT REQUIRED"
                )
            )
        }

        let statusSummary: String
        switch finalReport.status {
        case .go:
            statusSummary = thermal == nil
                ? "PROVISIONAL GO: the matrix selected a candidate, but Phase 2 remains closed "
                    + "until paired thermal evidence and all human approvals pass."
                : "GO: the selected Full Beam renderer passed the Phase 1 matrix and paired "
                    + "thermal gates. This authorizes a Phase 2 plan only; product integration "
                    + "has not begun."
        case .stop1080:
            statusSummary = referencePass
                ? "STOP AT 1080P: no candidate satisfied the 1080p Phase 1 gate. "
                    + "Production work and Phase 2 remain closed."
                : "STOP AT REFERENCE AUTHORITY: the bounded CPU/GPU reference prerequisite "
                    + "failed. No candidate is approved; production work and Phase 2 remain closed."
        case .blocked4K:
            statusSummary = "BLOCKED AT 4K: a viable 1080p result exists, but the approved "
                + "paired 4K scope failed. Production work and Phase 2 remain closed."
        }

        let candidateSection: String
        if let evidenceCandidate {
            let label = matrix.recommendedWorkload == nil
                ? "Highest-ranked diagnostic candidate; not approved"
                : "Matrix-selected candidate"
            candidateSection = """
            ## Evidence candidate

            - Role: \(label)
            - Representation: \(evidenceCandidate.representation.rawValue)
            - Source grid: \(evidenceCandidate.samples.width)x\(evidenceCandidate.samples.height)
            - Integration steps: \(evidenceCandidate.integrationSteps)
            - Beam width at 1080p: \(evidenceCandidate.beamWidthPixelsAt1080) pixels
            """
        } else {
            candidateSection = """
            ## Evidence candidate

            No evidence candidate is available because reference authority or workload-universe
            prerequisites failed.
            """
        }

        let visualSection: String
        if let selected = matrix.recommendedWorkload {
            let paths = [RasterSize.hd1080, .uhd4K].flatMap { output in
                [SpikeFixture.identity, .fold].map { fixture in
                    "- `previews/"
                        + selectedPreviewFilename(
                            selected: selected,
                            output: output,
                            fixture: fixture
                        ) + "`"
                }
            }.joined(separator: "\n")
            visualSection = """
            ## Selected visual manifest

            Operator approval covers these exact selected-quality previews:

            \(paths)
            """
        } else {
            visualSection = """
            ## Selected visual manifest

            No selected-quality preview manifest exists for this stop result. The 12 comparison
            previews remain supporting diagnostic evidence only.
            """
        }

        let failedGateNames = rows.filter { $0.result == "FAIL" }.map(\.gate)
        let nextAction: String
        if !referencePass {
            nextAction = "Correct the reference-authority defect and rerun Phase 1. Do not "
                + "revise a signed threshold to bypass the failure."
        } else {
            switch finalReport.status {
            case .go where thermal == nil:
                nextAction = "Run the exact matrix-selected pair through the paced thermal gate, "
                    + "then complete visual, Mechanic, Client Success, and operator approval."
            case .go:
                nextAction = "After all approval markers are positive and evidence is committed, "
                    + "open the Phase 2 shared-native-backing plan. Do not add host code in Phase 1."
            case .stop1080:
                nextAction = "Stop after evidence closeout. Present a new representation research "
                    + "proposal or versioned scope/threshold revision for explicit approval."
            case .blocked4K:
                nextAction = "Stop after evidence closeout. Seek explicit approval for a "
                    + "separately estimated optimization phase or a versioned 4K scope revision."
            }
        }

        let estimate: String
        if finalReport.status != .go || thermal == nil {
            estimate = "Withheld. A production estimate is published only after a thermal go."
        } else {
            let headroom = min(
                1.0 - p951080 / thresholds.p95Milliseconds1080,
                1.0 - p954K / thresholds.p95Milliseconds4K
            )
            let range: String
            if headroom >= 0.25 {
                range = "24 to 32 focused days"
            } else if headroom >= 0.10 {
                range = "28 to 38 focused days"
            } else {
                range = "34 to 46 focused days, plus an explicit optimization gate"
            }
            let headroomPercent = decimal(headroom * 100.0, suffix: " percent")
            estimate = "Measured minimum effect-budget headroom: \(headroomPercent). "
                + "\(range) for Phases 2 through 9. A focused day is one day of focused "
                + "engineering effort, not calendar duration or a ship date. Operator/reviewer wait time and the "
                + "separately approved Conditional Fast Preview are excluded."
        }

        let approvalGate = """
        ## Human approval gate

        - Operator verdict: PENDING
        - Mechanic verdict: PENDING
        - Client Success verdict: PENDING
        - Open deviations: unresolved
        """
        let table = ([
            "| Signed gate | Observed | Limit | Result |",
            "|---|---:|---:|:---:|",
        ] + rows.map(\.markdown)).joined(separator: "\n")
        let failureSummary = failedGateNames.isEmpty
            ? "No failed numerical gate is recorded in the combined evidence."
            : "Failed gates: " + failedGateNames.joined(separator: ", ") + "."
        return [
            "# Wobbulator Phase 1 Decision",
            statusSummary,
            """
            ## What this proves

            This is sole-device evidence for the Full Beam effect on
            \(matrix.hardware.deviceName), \(matrix.hardware.gpuCoreCount) GPU cores,
            \(matrix.hardware.memoryGB) GB. Timing is effect-only. \(failureSummary)
            """,
            """
            ## What is not built or proven

            Phase 1 contains no ARShader stage, host integration, presets, Panic path,
            modulation, or operator controls. It does not prove a full 4K60 chain, another
            device, public compatibility, or inverse Fast Preview.
            """,
            candidateSection,
            visualSection,
            "## Combined matrix and thermal gates\n\n" + table,
            "## Next action\n\n" + nextAction,
            "## Revised estimate\n\n" + estimate,
            """
            The approved tolerances remain unchanged. Any revision requires a versioned spec
            change and explicit operator approval.
            """,
            approvalGate,
        ].joined(separator: "\n\n")
    }
}
~~~

Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkArtifactVerifier.swift`:

~~~swift
import Foundation
import WobbulatorCore

public enum BenchmarkArtifactVerifier {
    public static func verify(
        report: BenchmarkReport,
        suite: BenchmarkSuite,
        selectionReport: BenchmarkReport? = nil
    ) throws {
        guard report.schemaVersion == 1,
            report.thresholds == .approved,
            report.referenceValidationPassed,
            report.referenceIdentityNormalizedExposureDelta.isFinite,
            report.referenceIdentityNormalizedExposureDelta >= 0,
            report.referenceIdentityNormalizedExposureDelta
                <= report.thresholds.exposureDeltaFraction,
            report.referenceFoldNormalizedExposureDelta.isFinite,
            report.referenceFoldNormalizedExposureDelta >= 0,
            report.referenceFoldNormalizedExposureDelta
                <= report.thresholds.exposureDeltaFraction
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "artifact schema, thresholds, or reference authority is invalid"
            )
        }

        let requiredFixtures: [SpikeFixture]
        switch suite {
        case .quick:
            throw WobbulatorSpikeError.invalidArguments(
                "artifact verification accepts only matrix or thermal"
            )
        case .matrix:
            guard selectionReport == nil else {
                throw WobbulatorSpikeError.invalidArguments(
                    "matrix verification does not accept a selection report"
                )
            }
            requiredFixtures = [.identity, .fold]
            let expected = try BenchmarkOptions.workloads(for: .matrix)
            guard report.measurements.count == expected.count,
                Set(report.measurements.map(\.workload)) == Set(expected)
            else {
                throw WobbulatorSpikeError.evidenceFailure(
                    "matrix artifact does not contain the exact 144-workload universe"
                )
            }
        case .thermal:
            guard let selectionReport else {
                throw WobbulatorSpikeError.invalidArguments(
                    "thermal verification requires the matrix selection report"
                )
            }
            try verify(report: selectionReport, suite: .matrix)
            guard report.hardware == selectionReport.hardware,
                report.thresholds == selectionReport.thresholds,
                let selected = selectionReport.recommendedWorkload,
                selectionReport.status == .go
            else {
                throw WobbulatorSpikeError.evidenceFailure(
                    "thermal artifact is not tied to a valid matrix go selection"
                )
            }
            let expected = try [RasterSize.hd1080, .uhd4K].map { output in
                try SpikeWorkload(
                    output: output,
                    samples: selected.samples,
                    integrationSteps: selected.integrationSteps,
                    beamWidthPixelsAt1080: selected.beamWidthPixelsAt1080,
                    fixtureAmount: selected.fixtureAmount,
                    fixture: .fold,
                    representation: selected.representation
                )
            }
            guard report.measurements.count == expected.count,
                Set(report.measurements.map(\.workload)) == Set(expected)
            else {
                throw WobbulatorSpikeError.evidenceFailure(
                    "thermal artifact does not contain the matrix-selected 1080p and 4K pair"
                )
            }
            requiredFixtures = [.fold]
        }

        let recomputed = BenchmarkDecision.evaluate(
            measurements: report.measurements,
            thresholds: report.thresholds,
            requiredFixtures: requiredFixtures,
            referenceValidationPassed: report.referenceValidationPassed
        )
        guard report.status == recomputed.status,
            report.recommendation == recomputed.recommendation,
            report.recommendedWorkload == recomputed.recommendedWorkload
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "artifact terminal state does not match the recomputed decision"
            )
        }
        if suite == .thermal, report.status == .go {
            guard report.recommendedWorkload == selectionReport?.recommendedWorkload else {
                throw WobbulatorSpikeError.evidenceFailure(
                    "thermal go recommendation drifted from the matrix selection"
                )
            }
        }
    }

    public static func verifyCLI(arguments: [String]) throws {
        var suite: BenchmarkSuite?
        var reportURL: URL?
        var selectionURL: URL?
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else {
                throw WobbulatorSpikeError.invalidArguments(
                    "artifact verification flags require values"
                )
            }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--suite":
                guard suite == nil, let parsed = BenchmarkSuite(rawValue: value) else {
                    throw WobbulatorSpikeError.invalidArguments(
                        "artifact suite must be matrix or thermal and appear once"
                    )
                }
                suite = parsed
            case "--report":
                guard reportURL == nil else {
                    throw WobbulatorSpikeError.invalidArguments(
                        "artifact report path may appear only once"
                    )
                }
                reportURL = URL(fileURLWithPath: value)
            case "--selection-report":
                guard selectionURL == nil else {
                    throw WobbulatorSpikeError.invalidArguments(
                        "selection report path may appear only once"
                    )
                }
                selectionURL = URL(fileURLWithPath: value)
            default:
                throw WobbulatorSpikeError.invalidArguments(
                    "unknown artifact verification flag \(arguments[index])"
                )
            }
            index += 2
        }
        guard let suite, let reportURL else {
            throw WobbulatorSpikeError.invalidArguments(
                "artifact verification requires --suite and --report"
            )
        }
        let report = try loadReport(at: reportURL)
        let selection = try selectionURL.map { try loadReport(at: $0) }
        try verify(report: report, suite: suite, selectionReport: selection)
    }

    public static func loadReport(at url: URL) throws -> BenchmarkReport {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BenchmarkReport.self, from: Data(contentsOf: url))
        } catch {
            throw WobbulatorSpikeError.evidenceFailure(
                "could not decode \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }
}
~~~

The ranking is deliberately quality-first. A candidate must pass both fixtures at both
resolutions. Among survivors, maximize `sampleCount * integrationSteps`, then minimize the worst
p95, prefer the denser grid, prefer the higher integration count, and finally use the
representation name as a stable tie-break. Same-resolution candidate/reference exposure and the
maximum normalized exposure spread across every tested resolution and grid/step quality tier for
the representation must both remain within 2 percent. A 1080p-only survivor is not silently
accepted: it yields `blocked4K`. The artifact verifier decodes persisted evidence,
recomputes this decision from the complete workload universe, and rejects any mismatch in status,
recommendation, or selected workload.

- [ ] **Step 5: Implement the hardware gate, steady-state runner, and reference comparisons**

Create `WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkRunner.swift`:

~~~swift
import Foundation
import Metal
import simd
import WobbulatorCore
import WobbulatorMetal

public final class BenchmarkRunner {
    private let renderer: WobbulatorMetalRenderer
    private let hardware: HardwareRecord
    private let thresholds: SpikeThresholds
    private var referenceCache: [String: HDRMetrics] = [:]
    private var numericalCache: [CandidateValidationKey: NumericalValidation] = [:]
    private var adaptiveProbeCache: [CandidateValidationKey: AdaptiveDiagnostics] = [:]
    private var branchCache: [BranchValidationKey: Bool] = [:]
    private var referenceExposureDeltas: [SpikeFixture: Double] = [:]

    private struct CandidateValidationKey: Hashable {
        var output: RasterSize
        var samples: SampleGrid
        var integrationSteps: Int
    }

    struct BranchValidationKey: Hashable {
        var output: RasterSize
        var samples: SampleGrid
        var integrationSteps: Int
        var beamWidthPixelsAt1080: Double
        var fixtureAmount: Double
        var representation: DepositionRepresentation

        init(workload: SpikeWorkload) {
            output = workload.output
            samples = workload.samples
            integrationSteps = workload.integrationSteps
            beamWidthPixelsAt1080 = workload.beamWidthPixelsAt1080
            fixtureAmount = workload.fixtureAmount
            representation = workload.representation
        }

        func workload(sourcePattern: SpikeSourcePattern) throws -> SpikeWorkload {
            try SpikeWorkload(
                output: output,
                samples: samples,
                integrationSteps: integrationSteps,
                beamWidthPixelsAt1080: beamWidthPixelsAt1080,
                fixtureAmount: fixtureAmount,
                fixture: .branchOverlap,
                sourcePattern: sourcePattern,
                representation: representation
            )
        }
    }

    private struct NumericalValidation {
        var identityRMSPixels: Double
        var identityMaxPixels: Double
        var oracleRMSPixels: Double
        var oracleMaxPixels: Double
        var maximumRelativeMomentumDrift: Double
        var invalidSampleCount: Int
        var adaptiveInvalidIntervalCount: Int
        var adaptiveToleranceFailureCount: Int
    }

    private struct EndpointGate {
        var identityRMSPixels: Double
        var identityMaxPixels: Double
        var oracleRMSPixels: Double
        var oracleMaxPixels: Double
        var maximumRelativeMomentumDrift: Double
        var invalidSampleCount: Int
        var adaptive: AdaptiveDiagnostics
    }

    public init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        thresholds: SpikeThresholds = .approved
    ) throws {
        guard let device else { throw WobbulatorSpikeError.noMetalDevice }
        hardware = try HardwareProbe.current(device: device)
        guard device.name.localizedCaseInsensitiveContains("M5 Max"),
            hardware.gpuCoreCount == 40,
            hardware.memoryGB >= 120
        else {
            throw WobbulatorSpikeError.wrongMetalDevice(
                expected: "40-core Apple M5 Max with at least 120 GB visible memory",
                actual:
                    "\(device.name), \(hardware.gpuCoreCount) GPU cores, "
                    + "\(hardware.memoryGB) GB"
            )
        }
        renderer = try WobbulatorMetalRenderer(device: device)
        self.thresholds = thresholds
    }

    public func run(_ options: BenchmarkOptions) throws -> BenchmarkReport {
        let referenceValidationPassed = try validateReferenceAuthority()
        let identityReferenceExposureDelta = referenceExposureDeltas[.identity]
            ?? thresholds.exposureDeltaFraction + 1.0
        let foldReferenceExposureDelta = referenceExposureDeltas[.fold]
            ?? thresholds.exposureDeltaFraction + 1.0
        guard referenceValidationPassed else {
            let decision = BenchmarkDecision.evaluate(
                measurements: [],
                thresholds: thresholds,
                referenceValidationPassed: false
            )
            return BenchmarkReport(
                schemaVersion: 1,
                createdAt: Date(),
                hardware: hardware,
                thresholds: thresholds,
                measurements: [],
                status: decision.status,
                recommendation: decision.recommendation,
                recommendedWorkload: nil,
                referenceValidationPassed: false,
                referenceIdentityNormalizedExposureDelta: identityReferenceExposureDelta,
                referenceFoldNormalizedExposureDelta: foldReferenceExposureDelta
            )
        }
        let workloads = options.suite == .thermal
            ? try options.selectedThermalWorkloads()
            : try BenchmarkOptions.workloads(for: options.suite)
        branchCache.removeAll(keepingCapacity: true)
        let expectedBranchKeys = Set(
            workloads.map { BranchValidationKey(workload: $0) }
        )
        for workload in workloads {
            _ = try branchRetention(for: workload)
        }
        guard Set(branchCache.keys) == expectedBranchKeys else {
            throw WobbulatorSpikeError.evidenceFailure(
                "branch-retention preflight did not cover the exact workload universe"
            )
        }
        var measurements: [BenchmarkMeasurement] = []
        for workload in workloads {
            let measurement = try measure(workload, options: options)
            measurements.append(measurement)
        }
        let fixtures: [SpikeFixture] = options.suite == .thermal
            ? [.fold]
            : [.identity, .fold]
        let decision = BenchmarkDecision.evaluate(
            measurements: measurements,
            thresholds: thresholds,
            requiredFixtures: fixtures,
            referenceValidationPassed: referenceValidationPassed
        )
        if options.suite == .matrix, decision.status == .go,
            let selected = decision.recommendedWorkload,
            let directory = options.previewDirectoryURL
        {
            try writeSelectedPreviews(selected: selected, directory: directory)
        }
        return BenchmarkReport(
            schemaVersion: 1,
            createdAt: Date(),
            hardware: hardware,
            thresholds: thresholds,
            measurements: measurements,
            status: decision.status,
            recommendation: decision.recommendation,
            recommendedWorkload: decision.recommendedWorkload,
            referenceValidationPassed: referenceValidationPassed,
            referenceIdentityNormalizedExposureDelta: identityReferenceExposureDelta,
            referenceFoldNormalizedExposureDelta: foldReferenceExposureDelta
        )
    }

    public static func percentile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(fraction * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }

    private func measure(
        _ workload: SpikeWorkload,
        options: BenchmarkOptions
    ) throws -> BenchmarkMeasurement {
        let prepared = try renderer.prepare(workload)
        let steadyResourceBytes = prepared.allocatedBytes
        for frame in 0..<options.warmupFrames {
            _ = try prepared.render(frameIndex: frame)
        }
        let measuredResourceStart = prepared.resourceCreationSnapshot

        let measurementClock = ContinuousClock()
        let measurementStart = measurementClock.now
        var timings: [FrameTiming] = []
        if options.suite == .thermal {
            let end = measurementClock.now.advanced(by: .seconds(options.thermalSeconds))
            var frame = 0
            while measurementClock.now < end {
                let frameStart = measurementClock.now
                timings.append(try prepared.render(frameIndex: frame))
                frame += 1
                let elapsed = frameStart.duration(to: measurementClock.now)
                let elapsedSeconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
                Thread.sleep(
                    forTimeInterval: max(0, 1.0 / 60.0 - elapsedSeconds)
                )
            }
        } else {
            timings.reserveCapacity(options.measuredFrames)
            for frame in 0..<options.measuredFrames {
                timings.append(try prepared.render(frameIndex: frame))
            }
        }
        let measuredDuration = measurementStart.duration(to: measurementClock.now)
        let measuredWallSeconds = Double(measuredDuration.components.seconds)
            + Double(measuredDuration.components.attoseconds) / 1e18
        let measuredResourceCreations = prepared.resourceCreationSnapshot
            - measuredResourceStart

        let gpu = timings.map(\.gpuMilliseconds)
        guard !gpu.isEmpty, gpu.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw WobbulatorSpikeError.evidenceFailure(
                "Metal command-buffer GPU timestamps were unavailable"
            )
        }
        let image = try HDRImage(
            width: workload.output.width,
            height: workload.output.height,
            rgba16Bits: prepared.outputRGBA16Bits()
        )
        let metrics = try HDRMetrics.analyze(image)
        let reference = try referenceMetrics(
            output: workload.output,
            fixture: workload.fixture
        )
        let comparison = try metrics.compare(to: reference)
        let endpoints = try prepared.endpointSnapshot()
        let invalid = endpoints.filter {
            $0.energyValidityDrift.y != 1
                || !$0.destinationAndUV.x.isFinite
                || !$0.destinationAndUV.y.isFinite
                || !$0.energyValidityDrift.z.isFinite
                || $0.energyValidityDrift.z < 0.0
                || !$0.energyValidityDrift.w.isFinite
        }.count
        let adaptive = try prepared.adaptiveDiagnostics()
        let adaptiveTopologyFailure = workload.representation == .adaptiveScanlineSegment
            && !adaptive.completelyClassifies(
                (workload.samples.width - 1) * workload.samples.height
            ) ? 1 : 0
        let numerical = try numericalValidation(for: workload)
        guard let branchRetentionPassed = branchCache[BranchValidationKey(workload: workload)]
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "candidate-specific branch-retention evidence is unavailable"
            )
        }

        if let directory = options.previewDirectoryURL,
            workload.samples == SampleGrid(width: 1920, height: 1080),
            workload.integrationSteps == 32
        {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let name =
                "\(workload.representation.rawValue)-\(workload.output.width)x"
                + "\(workload.output.height)-\(workload.fixture.rawValue).ppm"
            try image.writePreviewPPM(to: directory.appendingPathComponent(name))
        }

        return BenchmarkMeasurement(
            workload: workload,
            frameCount: timings.count,
            p50GPUMilliseconds: Self.percentile(gpu, fraction: 0.50),
            p95GPUMilliseconds: Self.percentile(gpu, fraction: 0.95),
            meanCPUMilliseconds:
                timings.map(\.cpuMilliseconds).reduce(0, +) / Double(timings.count),
            measuredWallSeconds: measuredWallSeconds,
            thermalTargetSeconds: options.suite == .thermal ? options.thermalSeconds : nil,
            thermalTargetFramesPerSecond: options.suite == .thermal ? 60.0 : nil,
            allocatedBytes: steadyResourceBytes,
            fieldEvaluationsPerFrame: prepared.fieldEvaluationsPerFrame,
            primitiveInstancesPerFrame: prepared.primitiveInstancesPerFrame,
            integratedExposure: metrics.integratedExposure,
            relativeExposureDelta: comparison.relativeExposureDelta,
            centroidDistancePixels: comparison.centroidDistancePixels,
            contourDistancePixels: comparison.contourSymmetricMeanDistancePixels,
            identityRMSPixels: numerical.identityRMSPixels,
            identityMaxPixels: numerical.identityMaxPixels,
            oracleRMSPixels: numerical.oracleRMSPixels,
            oracleMaxPixels: numerical.oracleMaxPixels,
            maximumRelativeMomentumDrift: numerical.maximumRelativeMomentumDrift,
            branchRetentionPassed: branchRetentionPassed,
            invalidSampleCount: invalid + numerical.invalidSampleCount,
            adaptiveInvalidIntervalCount: adaptive.invalidIntervalCount
                + adaptiveTopologyFailure
                + numerical.adaptiveInvalidIntervalCount,
            adaptiveToleranceFailureCount: adaptive.toleranceFailureCount
                + numerical.adaptiveToleranceFailureCount,
            measuredResourceCreations: measuredResourceCreations
        )
    }

    private func validateReferenceAuthority() throws -> Bool {
        referenceExposureDeltas.removeAll(keepingCapacity: true)
        do {
            return try performReferenceAuthorityValidation()
        } catch WobbulatorSpikeError.evidenceFailure {
            return false
        }
    }

    private func performReferenceAuthorityValidation() throws -> Bool {
        let identityWorkload = try SpikeWorkload(
            output: RasterSize(width: 64, height: 36),
            samples: SampleGrid(width: 16, height: 8),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixture: .identity,
            sourcePattern: .solidWhite,
            representation: .adaptiveScanlineSegment
        )
        let identity = try CPUForwardDepositionReference.render(
            identityWorkload, frameIndex: 0
        )
        let identityMetrics = try HDRMetrics.analyze(identity)
        guard abs(identityMetrics.integratedExposure - 64.0 * 36.0) <= 1e-8,
            abs(identityMetrics.centroid.x - 32.0) <= 1e-8,
            abs(identityMetrics.centroid.y - 18.0) <= 1e-8
        else {
            return false
        }

        func cpuBranch(_ pattern: SpikeSourcePattern) throws -> HDRImage {
            let workload = try SpikeWorkload(
                output: RasterSize(width: 64, height: 36),
                samples: SampleGrid(width: 16, height: 8),
                integrationSteps: 32,
                beamWidthPixelsAt1080: 1.25,
                fixture: .branchOverlap,
                sourcePattern: pattern,
                representation: .adaptiveScanlineSegment
            )
            return try CPUForwardDepositionReference.render(workload, frameIndex: 0)
        }
        let leftBranch = try cpuBranch(.leftRedOnly)
        let rightBranch = try cpuBranch(.rightGreenOnly)
        let bothBranches = try cpuBranch(.twoBranchRedGreen)
        for index in bothBranches.pixels.indices {
            guard abs(
                bothBranches.pixels[index].x
                    - leftBranch.pixels[index].x
                    - rightBranch.pixels[index].x
            ) <= 1e-10,
                abs(
                    bothBranches.pixels[index].y
                        - leftBranch.pixels[index].y
                        - rightBranch.pixels[index].y
                ) <= 1e-10
            else {
                return false
            }
        }

        let workload = try SpikeWorkload(
            output: .hd1080,
            samples: SampleGrid(width: 160, height: 90),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixtureAmount: 0.42,
            fixture: .fold,
            sourcePattern: .solidWhite,
            representation: .adaptiveScanlineSegment
        )
        let q64 = try CPUForwardDepositionReference.render(
            workload, frameIndex: 0, quadratureCount: 64
        )
        let q128 = try CPUForwardDepositionReference.render(
            workload, frameIndex: 0, quadratureCount: 128
        )
        let q64Metrics = try HDRMetrics.analyze(q64)
        let q128Metrics = try HDRMetrics.analyze(q128)
        let convergence = try q64Metrics.compare(to: q128Metrics)
        let scale = Double(workload.output.height) / 1080.0
        guard convergence.relativeExposureDelta
                <= thresholds.exposureDeltaFraction / 4.0,
            convergence.centroidDistancePixels
                <= thresholds.centroidPixels1080 * scale / 4.0,
            convergence.contourSymmetricMeanDistancePixels
                <= thresholds.contourPixels1080 * scale / 4.0
        else {
            return false
        }

        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: 0)
        let gpu = try HDRImage(
            width: workload.output.width,
            height: workload.output.height,
            rgba16Bits: prepared.outputRGBA16Bits()
        )
        let gpuComparison = try HDRMetrics.analyze(gpu).compare(to: q128Metrics)
        let diagnostics = try prepared.adaptiveDiagnostics()
        guard gpuComparison.relativeExposureDelta <= thresholds.exposureDeltaFraction
            && gpuComparison.centroidDistancePixels
                <= thresholds.centroidPixels1080 * scale
            && gpuComparison.contourSymmetricMeanDistancePixels
                <= thresholds.contourPixels1080 * scale
            && diagnostics.completelyClassifies(
                (workload.samples.width - 1) * workload.samples.height
            )
        else {
            return false
        }
        for fixture in [SpikeFixture.identity, .fold] {
            let hd = try referenceMetrics(output: .hd1080, fixture: fixture)
            let uhd = try referenceMetrics(output: .uhd4K, fixture: fixture)
            let delta = BenchmarkDecision.normalizedExposureDelta(
                baselineExposure: hd.integratedExposure,
                baselineOutput: .hd1080,
                comparisonExposure: uhd.integratedExposure,
                comparisonOutput: .uhd4K
            )
            referenceExposureDeltas[fixture] = delta
            guard delta <= thresholds.exposureDeltaFraction else {
                return false
            }
        }
        return true
    }

    private func numericalValidation(
        for workload: SpikeWorkload
    ) throws -> NumericalValidation {
        let key = CandidateValidationKey(
            output: workload.output,
            samples: workload.samples,
            integrationSteps: workload.integrationSteps
        )
        var validation: NumericalValidation
        if let cached = numericalCache[key] {
            validation = cached
        } else {
            let identityWorkload = try SpikeWorkload(
                output: workload.output,
                samples: workload.samples,
                integrationSteps: workload.integrationSteps,
                beamWidthPixelsAt1080: workload.beamWidthPixelsAt1080,
                fixture: .identity,
                representation: .gaussianPointSprite
            )
            let sBendWorkload = try SpikeWorkload(
                output: workload.output,
                samples: workload.samples,
                integrationSteps: workload.integrationSteps,
                beamWidthPixelsAt1080: workload.beamWidthPixelsAt1080,
                fixtureAmount: 0.2,
                fixture: .sBend,
                representation: .gaussianPointSprite
            )
            let identity = try endpointGate(
                workload: identityWorkload,
                frameIndex: 0,
                requireAnalyticIdentity: true
            )
            let sBend = try endpointGate(
                workload: sBendWorkload,
                frameIndex: 36_000,
                requireAnalyticIdentity: false
            )
            validation = NumericalValidation(
                identityRMSPixels: identity.identityRMSPixels,
                identityMaxPixels: identity.identityMaxPixels,
                oracleRMSPixels: max(identity.oracleRMSPixels, sBend.oracleRMSPixels),
                oracleMaxPixels: max(identity.oracleMaxPixels, sBend.oracleMaxPixels),
                maximumRelativeMomentumDrift: max(
                    identity.maximumRelativeMomentumDrift,
                    sBend.maximumRelativeMomentumDrift
                ),
                invalidSampleCount: identity.invalidSampleCount
                    + sBend.invalidSampleCount,
                adaptiveInvalidIntervalCount: 0,
                adaptiveToleranceFailureCount: 0
            )
            numericalCache[key] = validation
        }

        if workload.representation == .adaptiveScanlineSegment {
            let adaptive: AdaptiveDiagnostics
            if let cached = adaptiveProbeCache[key] {
                adaptive = cached
            } else {
                let sBendWorkload = try SpikeWorkload(
                    output: workload.output,
                    samples: workload.samples,
                    integrationSteps: workload.integrationSteps,
                    beamWidthPixelsAt1080: workload.beamWidthPixelsAt1080,
                    fixtureAmount: 0.2,
                    fixture: .sBend,
                    representation: .adaptiveScanlineSegment
                )
                let prepared = try renderer.prepare(sBendWorkload)
                _ = try prepared.render(frameIndex: 36_000)
                var measured = try prepared.adaptiveDiagnostics()
                if !measured.completelyClassifies(
                    (workload.samples.width - 1) * workload.samples.height
                ) {
                    measured.invalidIntervalCount += 1
                }
                adaptiveProbeCache[key] = measured
                adaptive = measured
            }
            validation.adaptiveInvalidIntervalCount += adaptive.invalidIntervalCount
            validation.adaptiveToleranceFailureCount += adaptive.toleranceFailureCount
        }
        return validation
    }

    private func endpointGate(
        workload: SpikeWorkload,
        frameIndex: Int,
        requireAnalyticIdentity: Bool
    ) throws -> EndpointGate {
        let prepared = try renderer.prepare(workload)
        _ = try prepared.render(frameIndex: frameIndex)
        let endpoints = try prepared.endpointSnapshot()
        guard endpoints.count == workload.samples.count else {
            throw WobbulatorSpikeError.evidenceFailure(
                "endpoint count did not match the candidate grid"
            )
        }
        var identitySquaredError = 0.0
        var identityMaximumError = 0.0
        var validIdentityCount = 0
        var oracleSquaredError = 0.0
        var oracleMaximumError = 0.0
        var validOracleCount = 0
        var invalidCount = endpoints.filter {
            $0.energyValidityDrift.y != 1.0
                || !$0.destinationAndUV.x.isFinite
                || !$0.destinationAndUV.y.isFinite
                || !$0.energyValidityDrift.z.isFinite
                || $0.energyValidityDrift.z < 0.0
                || !$0.energyValidityDrift.w.isFinite
        }.count
        var maximumDrift = endpoints.reduce(0.0) { current, endpoint in
            let value = Double(endpoint.energyValidityDrift.z)
            return value.isFinite && value >= 0.0 ? max(current, value) : current
        }

        if requireAnalyticIdentity {
            for (index, endpoint) in endpoints.enumerated() {
                guard endpoint.energyValidityDrift.y == 1.0,
                    endpoint.destinationAndUV.x.isFinite,
                    endpoint.destinationAndUV.y.isFinite
                else {
                    continue
                }
                let x = index % workload.samples.width
                let y = index / workload.samples.width
                let u = (Double(x) + 0.5) / Double(workload.samples.width)
                let v = (Double(y) + 0.5) / Double(workload.samples.height)
                let actual = SIMD2(
                    Double(endpoint.destinationAndUV.x),
                    Double(endpoint.destinationAndUV.y)
                )
                let analytic = SIMD2(
                    u * Double(workload.output.width),
                    v * Double(workload.output.height)
                )
                let error = simd_length(actual - analytic)
                guard error.isFinite else {
                    invalidCount += 1
                    continue
                }
                identitySquaredError += error * error
                identityMaximumError = max(identityMaximumError, error)
                validIdentityCount += 1
            }
            oracleSquaredError = identitySquaredError
            oracleMaximumError = identityMaximumError
            validOracleCount = validIdentityCount
        }

        if !requireAnalyticIdentity {
            for index in endpoints.indices {
                let x = index % workload.samples.width
                let y = index / workload.samples.width
                let endpoint = endpoints[index]
                guard endpoint.energyValidityDrift.y == 1.0,
                    endpoint.destinationAndUV.x.isFinite,
                    endpoint.destinationAndUV.y.isFinite
                else {
                    continue
                }
                let u = (Double(x) + 0.5) / Double(workload.samples.width)
                let v = (Double(y) + 0.5) / Double(workload.samples.height)
                let launch = try CRTTiming.ntsc525.rasterLaunchTimeSeconds(
                    normalizedLine: Double(y) / Double(workload.samples.height),
                    horizontal: u,
                    fieldIndex: frameIndex
                )
                let field: OracleField
                switch workload.fixture {
                case .identity:
                    field = .zero
                case .sBend:
                    field = .sBend(
                        amplitude: workload.fixtureAmount,
                        angularFrequency: .pi * 120.0,
                        phase: 0.0
                    )
                case .dipole, .fold, .branchOverlap:
                    throw WobbulatorSpikeError.evidenceFailure(
                        "endpoint oracle gate received an unsupported fixture"
                    )
                }
                let oracle = RelativisticBorisOracle.trace(
                    initial: BorisState(
                        position: SIMD3(0.0, 0.0, -1.0),
                        momentum: SIMD3(u * 2.0 - 1.0, v * 2.0 - 1.0, 1.0),
                        rasterLaunchTimeSeconds: launch
                    ),
                    field: field,
                    steps: workload.integrationSteps,
                    screenZ: 0.0,
                    bounds: 8.0
                )
                guard oracle.termination == .hitScreen,
                    oracle.maximumRelativeMomentumDrift.isFinite,
                    oracle.maximumRelativeMomentumDrift >= 0.0
                else {
                    invalidCount += 1
                    continue
                }
                maximumDrift = max(maximumDrift, oracle.maximumRelativeMomentumDrift)
                let actual = SIMD2(
                    Double(endpoint.destinationAndUV.x),
                    Double(endpoint.destinationAndUV.y)
                )
                let oracleExpected = SIMD2(
                    (oracle.state.position.x * 0.5 + 0.5) * Double(workload.output.width),
                    (oracle.state.position.y * 0.5 + 0.5) * Double(workload.output.height)
                )
                let oracleError = simd_length(actual - oracleExpected)
                guard oracleError.isFinite else {
                    invalidCount += 1
                    continue
                }
                oracleSquaredError += oracleError * oracleError
                oracleMaximumError = max(oracleMaximumError, oracleError)
                validOracleCount += 1
            }
        }
        var adaptive = try prepared.adaptiveDiagnostics()
        if workload.representation == .adaptiveScanlineSegment,
            !adaptive.completelyClassifies(
                (workload.samples.width - 1) * workload.samples.height
            )
        {
            adaptive.invalidIntervalCount += 1
        }
        guard validOracleCount > 0,
            !requireAnalyticIdentity || validIdentityCount > 0
        else {
            return EndpointGate(
                identityRMSPixels: thresholds.identityRMSPixels + 1.0,
                identityMaxPixels: thresholds.identityMaxPixels + 1.0,
                oracleRMSPixels: thresholds.oracleRMSPixels + 1.0,
                oracleMaxPixels: thresholds.oracleMaxPixels + 1.0,
                maximumRelativeMomentumDrift: thresholds.relativeMomentumDrift + 1.0,
                invalidSampleCount: max(1, invalidCount),
                adaptive: adaptive
            )
        }
        return EndpointGate(
            identityRMSPixels: requireAnalyticIdentity
                ? sqrt(identitySquaredError / Double(validIdentityCount)) : 0.0,
            identityMaxPixels: requireAnalyticIdentity ? identityMaximumError : 0.0,
            oracleRMSPixels: sqrt(oracleSquaredError / Double(validOracleCount)),
            oracleMaxPixels: oracleMaximumError,
            maximumRelativeMomentumDrift: maximumDrift,
            invalidSampleCount: invalidCount,
            adaptive: adaptive
        )
    }

    private func writeSelectedPreviews(
        selected: SpikeWorkload,
        directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        for output in [RasterSize.hd1080, .uhd4K] {
            for fixture in [SpikeFixture.identity, .fold] {
                let workload = try SpikeWorkload(
                    output: output,
                    samples: selected.samples,
                    integrationSteps: selected.integrationSteps,
                    beamWidthPixelsAt1080: selected.beamWidthPixelsAt1080,
                    fixtureAmount: selected.fixtureAmount,
                    fixture: fixture,
                    representation: selected.representation
                )
                let prepared = try renderer.prepare(workload)
                for frame in 0..<30 { _ = try prepared.render(frameIndex: frame) }
                let image = try HDRImage(
                    width: output.width,
                    height: output.height,
                    rgba16Bits: prepared.outputRGBA16Bits()
                )
                try image.writePreviewPPM(
                    to: directory.appendingPathComponent(
                        BenchmarkDecision.selectedPreviewFilename(
                            selected: selected,
                            output: output,
                            fixture: fixture
                        )
                    )
                )
            }
        }
    }

    private func branchRetention(for candidate: SpikeWorkload) throws -> Bool {
        let key = BranchValidationKey(workload: candidate)
        if let cached = branchCache[key] { return cached }

        func render(_ pattern: SpikeSourcePattern) throws -> (
            image: HDRImage,
            diagnostics: AdaptiveDiagnostics
        ) {
            let workload = try key.workload(sourcePattern: pattern)
            let prepared = try renderer.prepare(workload)
            _ = try prepared.render(frameIndex: 0)
            return (
                try HDRImage(
                    width: workload.output.width,
                    height: workload.output.height,
                    rgba16Bits: prepared.outputRGBA16Bits()
                ),
                try prepared.adaptiveDiagnostics()
            )
        }

        let left = try render(.leftRedOnly)
        let right = try render(.rightGreenOnly)
        let both = try render(.twoBranchRedGreen)
        let expectedIntervals = (key.samples.width - 1) * key.samples.height
        func diagnosticsPass(_ value: AdaptiveDiagnostics) -> Bool {
            key.representation == .adaptiveScanlineSegment
                ? value.completelyClassifies(expectedIntervals)
                : value == .zero
        }
        guard diagnosticsPass(left.diagnostics), diagnosticsPass(right.diagnostics),
            diagnosticsPass(both.diagnostics)
        else {
            branchCache[key] = false
            return false
        }
        var coLocatedContributionPixels = 0
        var retainedEveryContribution = true
        for y in (left.image.height / 4)..<(left.image.height * 3 / 4) {
            for x in (left.image.width / 4)..<(left.image.width * 3 / 4) {
                let index = y * left.image.width + x
                let leftRed = left.image.pixels[index].x
                let rightGreen = right.image.pixels[index].y
                guard leftRed > 1e-6, rightGreen > 1e-6 else { continue }
                coLocatedContributionPixels += 1
                let bothRed = both.image.pixels[index].x
                let bothGreen = both.image.pixels[index].y
                retainedEveryContribution = retainedEveryContribution
                    && abs(bothRed - leftRed) <= max(1e-4, leftRed * 0.01)
                    && abs(bothGreen - rightGreen) <= max(1e-4, rightGreen * 0.01)
            }
        }
        let passed = coLocatedContributionPixels > 100 && retainedEveryContribution
        branchCache[key] = passed
        return passed
    }

    private func referenceMetrics(
        output: RasterSize,
        fixture: SpikeFixture
    ) throws -> HDRMetrics {
        let key = "\(output.width)x\(output.height)-\(fixture.rawValue)"
        if let cached = referenceCache[key] { return cached }
        let workload = try SpikeWorkload(
            output: output,
            samples: SampleGrid(width: 1920, height: 1080),
            integrationSteps: 32,
            beamWidthPixelsAt1080: 1.25,
            fixture: fixture,
            representation: .adaptiveScanlineSegment
        )
        let prepared = try renderer.prepare(workload)
        for frame in 0..<30 { _ = try prepared.render(frameIndex: frame) }
        let endpoints = try prepared.endpointSnapshot()
        let invalidEndpointCount = endpoints.filter {
            $0.energyValidityDrift.y != 1.0
                || !$0.destinationAndUV.x.isFinite
                || !$0.destinationAndUV.y.isFinite
                || !$0.energyValidityDrift.z.isFinite
                || $0.energyValidityDrift.z < 0.0
                || !$0.energyValidityDrift.w.isFinite
        }.count
        let adaptive = try prepared.adaptiveDiagnostics()
        guard invalidEndpointCount == 0,
            adaptive.completelyClassifies(
                (workload.samples.width - 1) * workload.samples.height
            )
        else {
            throw WobbulatorSpikeError.evidenceFailure(
                "canonical GPU reference failed endpoint or adaptive diagnostics"
            )
        }
        let image = try HDRImage(
            width: output.width,
            height: output.height,
            rgba16Bits: prepared.outputRGBA16Bits()
        )
        let metrics = try HDRMetrics.analyze(image)
        referenceCache[key] = metrics
        return metrics
    }
}

private enum HardwareProbe {
    static func current(device: MTLDevice) throws -> HardwareRecord {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int((Double(bytes) / 1_073_741_824.0).rounded())
        return HardwareRecord(
            deviceName: device.name,
            gpuCoreCount: try gpuCoreCount(),
            memoryGB: memoryGB,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            swiftVersion: command(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "--version"]
            ).split(separator: "\n").first.map(String.init) ?? "unknown"
        )
    }

    private static func gpuCoreCount() throws -> Int {
        let output = command(
            executable: "/usr/sbin/system_profiler",
            arguments: ["SPDisplaysDataType"]
        )
        for line in output.split(separator: "\n") {
            let pieces = line.split(separator: ":", maxSplits: 1)
            guard line.localizedCaseInsensitiveContains("Total Number of Cores"),
                pieces.count == 2,
                let token = pieces[1].split(whereSeparator: { !$0.isNumber }).first,
                let value = Int(token)
            else {
                continue
            }
            return value
        }
        throw WobbulatorSpikeError.evidenceFailure(
            "system_profiler did not report the GPU core count"
        )
    }

    private static func command(executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "unknown" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? "unknown"
        } catch {
            return "unknown"
        }
    }
}
~~~

The runner compiles the Metal library and pipelines when it constructs
`WobbulatorMetalRenderer`, before warm-up. `PreparedSpikeCase.render` performs no Metal texture,
buffer, pipeline, or queue creation. Output and endpoint readback happen once after the measured
loop and are excluded from timing. The high-quality adaptive reference is cached once per
resolution and fixture, is never included in candidate timing, and uses `1920x1080` samples with
32 steps. Numerical validation covers every valid endpoint, not a sampled subset: zero-field
identity uses the analytic closed form of the double-precision oracle, and the physical late
S-bend runs every endpoint through `RelativisticBorisOracle`. That result is cached across
representations for each output/grid/step tier only because the permanent cross-representation
test proves all three depositors consume the exact same endpoint generator. Branch retention is
not a representation-level proxy: its left-only, right-only, and overlapping-source renders use
the exact candidate output, source grid, integration steps, beam width, fixture amount, and
representation. The runner completes this exact-key branch universe as an untimed preflight,
proves the cache contains every and only requested candidate key, and then gives each measured
case its ordinary 120-frame warm-up; branch renders are never interleaved with measured cases.
A matrix `go` also triggers four untimed `selected-*` identity/fold previews at the chosen source
grid and step floor for both output resolutions; these are separate from the 12 high-quality
comparison previews.

- [ ] **Step 6: Add the CLI writer, stable exit codes, and decision output**

Create `WobbulatorKit/Sources/WobbulatorBench/main.swift`:

~~~swift
import Darwin
import Foundation
import WobbulatorBenchSupport
import WobbulatorCore

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "verify-artifact" {
        try BenchmarkArtifactVerifier.verifyCLI(
            arguments: Array(arguments.dropFirst())
        )
        print("artifact decision recomputation: PASS")
        exit(0)
    }
    let options = try BenchmarkOptions.parse(arguments)
    let report = try BenchmarkRunner().run(options)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    try FileManager.default.createDirectory(
        at: options.outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: options.outputURL, options: .atomic)
    if let decisionURL = options.decisionURL {
        try FileManager.default.createDirectory(
            at: decisionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let decisionMarkdown: String
        if options.suite == .thermal {
            guard let selectionReportURL = options.selectionReportURL else {
                throw WobbulatorSpikeError.invalidArguments(
                    "thermal decision output requires --selection-report"
                )
            }
            let matrix = try BenchmarkArtifactVerifier.loadReport(
                at: selectionReportURL
            )
            try BenchmarkArtifactVerifier.verify(
                report: matrix,
                suite: .matrix
            )
            decisionMarkdown = BenchmarkDecision.markdown(
                matrix: matrix,
                thermal: report
            )
        } else {
            decisionMarkdown = BenchmarkDecision.markdown(matrix: report)
        }
        try decisionMarkdown.write(
            to: decisionURL,
            atomically: true,
            encoding: .utf8
        )
    }
    print("\(report.status.rawValue): \(report.recommendation)")
    switch report.status {
    case .go: exit(0)
    case .stop1080: exit(2)
    case .blocked4K: exit(3)
    }
} catch {
    FileHandle.standardError.write(Data("WobbulatorBench: \(error)\n".utf8))
    exit(64)
}
~~~

Matrix output writes a provisional decision from all 144 rows. Thermal output reloads the exact
verified matrix selection report and rewrites `decision.md` as one combined matrix-plus-thermal
artifact; it never replaces the selection context with the two thermal rows alone. The combined
file preserves the matrix-selected candidate even if thermal ends in `stop1080` or `blocked4K`,
binds the four exact selected preview paths, names every failed signed gate with its observed value
and limit, states the Phase 1-only scope in operator language, and initializes all human verdicts
to pending.

- [ ] **Step 7: Run GREEN tests and prove the stop gate fires**

Run:

~~~bash
swift test --package-path WobbulatorKit --filter BenchmarkRunnerTests
~~~

Expected: all benchmark-support tests pass.

Temporarily change `p95Milliseconds1080` in `SpikeThresholds.approved` from `4.0` to `0.0` and
run:

~~~bash
swift test --package-path WobbulatorKit \
  --filter BenchmarkRunnerTests/testDecisionTransitionsFromStopToBlockedToGo
~~~

Expected: FAIL because the passing fixture set becomes `stop1080`. Restore `4.0` and rerun;
expected: PASS. This mutation proves the benchmark cannot report go when its timing guard is
disabled or bypassed.

Then temporarily replace the body of `BenchmarkDecision.normalizedExposureDelta` with
`return 0.0` and run:

~~~bash
swift test --package-path WobbulatorKit \
  --filter BenchmarkRunnerTests/testReferenceExposureDeltaNormalizesByOutputPixelArea
~~~

Expected: FAIL because a 3-percent normalized 4K reference gain is reported as zero. Restore the
normalized exposure calculation and rerun; expected: PASS.

Finally, temporarily replace the body of
`BenchmarkDecision.maximumNormalizedExposureSpread` with `return 0.0` and run:

~~~bash
swift test --package-path WobbulatorKit \
  --filter BenchmarkRunnerTests/testNormalizedExposureMustHoldAcrossEveryTestedQualityTier
~~~

Expected: FAIL because the 0.98-through-1.02 quality spread is incorrectly promoted from
`stop1080` to `go`. Restore the spread calculation and rerun; expected: PASS. Together these
mutations prove that same-resolution reference deltas cannot mask resolution- or
quality-dependent gain.

Run three additional mutation cycles against `BranchValidationKey.init(workload:)`. In separate
cycles, replace only the `output`, `samples`, or `integrationSteps` assignment with a fixed
approved value, then run:

~~~bash
swift test --package-path WobbulatorKit \
  --filter BenchmarkRunnerTests/testBranchProofAndSelectedPreviewUseTheExactCandidateQuality
~~~

Expected for each mutation: FAIL because a branch-retention proof can no longer identify the
exact candidate output, source grid, or integration-step tier. Restore after each cycle and rerun
to PASS. The same test permanently binds the selected-preview filename to those exact fields.

Run two final decision-artifact mutation cycles. First, replace
`let finalReport = thermal ?? matrix` with `let finalReport = matrix`, then run:

~~~bash
swift test --package-path WobbulatorKit \
  --filter BenchmarkRunnerTests/testThermalStopKeepsTheMatrixCandidateAndExactFailureEvidence
~~~

Expected: FAIL because the combined decision incorrectly reports the matrix `go` instead of the
thermal stop. Restore and rerun to PASS. Second, replace
`if let selected = matrix.recommendedWorkload` in the selected visual manifest with
`if let selected = Optional<SpikeWorkload>.none`, then run:

~~~bash
swift test --package-path WobbulatorKit \
  --filter BenchmarkRunnerTests/testDecisionMarkdownCombinesMatrixThermalAndSelectedVisualManifest
~~~

Expected: FAIL because the exact four selected preview paths disappear from the durable operator
artifact. Restore and rerun to PASS. These mutations bind the combined terminal state and visual
manifest rather than merely testing the filename helper in isolation.

- [ ] **Step 8: Document the exact clean-run protocol**

Create `docs/arshader/benchmarks/wobbulator-phase1/README.md`:

~~~~markdown
# Wobbulator Phase 1 M5 Evidence Protocol

Run only on the 40-GPU-core Apple M5 Max with at least 120 GB visible memory. Quit ARShader,
VDMX, TouchDesigner, games, renderers, model inference, and other GPU-heavy work first. Keep the
machine on power, disable Low Power Mode, use the same display topology for both runs, and restart
the matrix if another GPU workload starts. A result captured while another rendering session is
active is invalid evidence.

From the repository root:

~~~bash
swift test --package-path WobbulatorKit
swift build --package-path WobbulatorKit -c release --product WobbulatorBench

swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite quick \
  --output /tmp/wobbulator-quick.json

swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite matrix \
  --output docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
  --previews docs/arshader/benchmarks/wobbulator-phase1/previews \
  --decision docs/arshader/benchmarks/wobbulator-phase1/decision.md

swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  verify-artifact \
  --suite matrix \
  --report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json

swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite thermal \
  --selection-report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
  --thermal-seconds 600 \
  --output docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
  --decision docs/arshader/benchmarks/wobbulator-phase1/decision.md

swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  verify-artifact \
  --suite thermal \
  --report docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
  --selection-report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
~~~

Defaults are 120 untimed warm-up frames, 240 measured matrix frames, and 600 seconds per thermal
workload. GPU duration is the completed Metal command buffer's `gpuEndTime - gpuStartTime`. CPU
wall time is supplemental. Exit 0 means go, 2 means stop at 1080p, 3 means blocked at 4K, and 64
means invalid invocation or evidence.

JSON contains only the device name, GPU core count, memory size, OS, Swift version, approved
thresholds, workloads, metrics, and decision. The verifier decodes it, checks the exact workload
universe, recomputes the terminal state and recommendation, and ties thermal evidence back to the
matrix-selected workload. JSON must never contain a serial number, registry ID, UUID, username,
or home-directory path.

`decision.md` is the operator approval artifact. The matrix run writes a provisional summary;
the thermal run reloads that matrix and writes one combined summary with the exact selected
preview manifest, signed-gate table, plain-language state and next action, Phase 1 limitations,
estimate assumptions, and pending operator, Mechanic, and Client Success markers. A go opens only
Phase 2 planning after approval. It does not mean an ARShader effect or controls exist yet.
~~~~

Use four tildes around the outer Markdown block while creating the file so its inner shell fence
remains intact.

- [ ] **Step 9: Format, lint, test, build, run quick, and commit**

Run:

~~~bash
cd WobbulatorKit
swift format format --in-place --recursive Sources Tests
swift format lint --strict --recursive Sources Tests
swift test
swift build -c release --product WobbulatorBench
cd ..
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite quick \
  --output /tmp/wobbulator-quick.json
~~~

Expected: formatting and lint are clean, every test passes, the release executable builds, and
the quick command writes 12 measurements. Diagnose a non-go quick result before Task 6. A
reference-authority or implementation defect must be corrected and rerun to clean; a documented
performance-only miss proceeds to the full matrix so its lower quality tiers can be evaluated.

Commit only source, tests, and protocol documentation:

~~~bash
git add WobbulatorKit/Package.swift \
  WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkOptions.swift \
  WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkDecision.swift \
  WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkArtifactVerifier.swift \
  WobbulatorKit/Sources/WobbulatorBenchSupport/BenchmarkRunner.swift \
  WobbulatorKit/Sources/WobbulatorBench/main.swift \
  WobbulatorKit/Tests/WobbulatorBenchTests/BenchmarkRunnerTests.swift \
  docs/arshader/benchmarks/wobbulator-phase1/README.md
git commit -m "spike: add M5 wobbulator benchmark"
~~~

---

### Task 6: Capture clean M5 evidence, select the renderer, and freeze Phase 2 inputs

**Files:**
- Generate: `docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json`
- Generate: `docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json`
- Generate: `docs/arshader/benchmarks/wobbulator-phase1/previews/*.ppm`
- Generate: `docs/arshader/benchmarks/wobbulator-phase1/decision.md`
- Verify: `docs/arshader/benchmarks/wobbulator-phase1/README.md`

**Interfaces:**
- Consumes: the signed Phase 1 thresholds, Task 5 release executable, and an idle 40-core M5 Max.
- Produces exactly one of:
  - `go` with a frozen representation, source-grid floor, integration-step floor, measured
    headroom, and revised Phases 2 through 9 estimate;
  - `stop1080`, which ends production work before host integration;
  - `blocked4K`, which records a viable 1080p result but forbids claiming the approved 4K scope.

- [ ] **Step 1: Establish a clean, uncontaminated benchmark preflight**

From the repository root, close ARShader, VDMX, TouchDesigner, games, renderers, local model
inference, and any other GPU-heavy application. Connect power, disable Low Power Mode, keep the
display topology fixed, and ensure no other agent or terminal session is building or rendering.
Do not run matrix or thermal evidence in parallel with another workload.

Run:

~~~bash
/Users/arsonrivvers/Documents/_Projects/csuite-framework/bin/csuite-sync check
system_profiler SPDisplaysDataType | rg 'Chipset Model|Total Number of Cores'
sysctl -n hw.memsize
pmset -g custom | rg 'lowpowermode'
git status --short
mkdir -p docs/arshader/benchmarks/wobbulator-phase1/previews
rm -f docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
  docs/arshader/benchmarks/wobbulator-phase1/decision.md
find docs/arshader/benchmarks/wobbulator-phase1/previews -type f -delete
swift package --package-path WobbulatorKit clean
swift test --package-path WobbulatorKit
swift build --package-path WobbulatorKit -c release --product WobbulatorBench
~~~

Expected:

- c-suite sync reports `OK`, or its printed repair command is run before continuing;
- the GPU is Apple M5 Max with exactly 40 cores;
- physical memory is at least 128,000,000,000 bytes;
- Low Power Mode is 0 for the active power profile;
- only expected task paths and pre-existing unrelated user changes appear in Git status;
- every prior generated report, decision, and preview is removed before fresh evidence begins;
- the complete package suite passes and the release executable builds.

If another GPU workload starts after this preflight, discard that run and restart this step.

- [ ] **Step 2: Run the 12-case smoke matrix**

Run:

~~~bash
rm -f /tmp/wobbulator-quick.json
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite quick \
  --output /tmp/wobbulator-quick.json
jq -e '
  .schemaVersion == 1
  and .referenceValidationPassed == true
  and .referenceIdentityNormalizedExposureDelta >= 0
  and (.referenceIdentityNormalizedExposureDelta | isfinite)
  and .referenceIdentityNormalizedExposureDelta <= .thresholds.exposureDeltaFraction
  and .referenceFoldNormalizedExposureDelta >= 0
  and (.referenceFoldNormalizedExposureDelta | isfinite)
  and .referenceFoldNormalizedExposureDelta <= .thresholds.exposureDeltaFraction
  and (.measurements | length == 12)
  and ([.measurements[]
    | .frameCount > 0
      and .p50GPUMilliseconds > 0 and (.p50GPUMilliseconds | isfinite)
      and .p95GPUMilliseconds > 0 and (.p95GPUMilliseconds | isfinite)
      and .measuredWallSeconds > 0 and (.measuredWallSeconds | isfinite)
      and .thermalTargetSeconds == null
      and .thermalTargetFramesPerSecond == null
      and .integratedExposure > 0 and (.integratedExposure | isfinite)
      and (.branchRetentionPassed | type == "boolean")
      and .invalidSampleCount >= 0
      and .adaptiveInvalidIntervalCount >= 0
      and (.measuredResourceCreations
        | [.commandQueues, .buffers, .textures, .libraries,
           .computePipelines, .renderPipelines] | all(. == 0))] | all)
' \
  /tmp/wobbulator-quick.json
jq -r '.status, .recommendation' /tmp/wobbulator-quick.json
~~~

Expected: valid schema, exactly 12 measurements, zero runner errors, and a visible terminal status.
`stop1080` or `blocked4K` here is not a final decision, but it must be diagnosed before spending
time on the full matrix. A reference-authority or implementation defect blocks the matrix until
it is corrected and the smoke run is clean. A diagnosed performance-only miss is screening data,
not a terminal state; record it and run the full quality matrix, which may select a lower passing
tier. Do not loosen a signed threshold or add a representation-specific gain.

- [ ] **Step 3: Run the complete 144-case selection matrix**

Run:

~~~bash
mkdir -p docs/arshader/benchmarks/wobbulator-phase1/previews
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite matrix \
  --output docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
  --previews docs/arshader/benchmarks/wobbulator-phase1/previews \
  --decision docs/arshader/benchmarks/wobbulator-phase1/decision.md
~~~

The executable intentionally returns 2 for `stop1080` and 3 for `blocked4K` after atomically
writing the report. Preserve the JSON and inspect its status even when the command is nonzero.

Run the full-universe validations:

~~~bash
jq -e '
  def structurally_valid:
    .frameCount > 0
    and .p50GPUMilliseconds > 0 and (.p50GPUMilliseconds | isfinite)
    and .p95GPUMilliseconds > 0 and (.p95GPUMilliseconds | isfinite)
    and .p50GPUMilliseconds <= .p95GPUMilliseconds
    and .meanCPUMilliseconds >= 0 and (.meanCPUMilliseconds | isfinite)
    and .measuredWallSeconds > 0 and (.measuredWallSeconds | isfinite)
    and .thermalTargetSeconds == null
    and .thermalTargetFramesPerSecond == null
    and .allocatedBytes > 0
    and .fieldEvaluationsPerFrame > 0
    and .primitiveInstancesPerFrame > 0
    and .integratedExposure > 0 and (.integratedExposure | isfinite)
    and ([.relativeExposureDelta, .centroidDistancePixels, .contourDistancePixels,
          .identityRMSPixels, .identityMaxPixels, .oracleRMSPixels, .oracleMaxPixels,
          .maximumRelativeMomentumDrift] | all(. >= 0 and isfinite))
    and (.branchRetentionPassed | type == "boolean")
    and .invalidSampleCount >= 0
    and .adaptiveInvalidIntervalCount >= 0
    and .adaptiveToleranceFailureCount >= 0
    and (.measuredResourceCreations
      | [.commandQueues, .buffers, .textures, .libraries,
         .computePipelines, .renderPipelines] | all(. == 0));
  def passes($t):
    structurally_valid
    and .branchRetentionPassed == true
    and .invalidSampleCount == 0
    and .adaptiveInvalidIntervalCount == 0
    and .relativeExposureDelta <= $t.exposureDeltaFraction
    and .identityRMSPixels <= $t.identityRMSPixels
    and .identityMaxPixels <= $t.identityMaxPixels
    and .oracleRMSPixels <= $t.oracleRMSPixels
    and .oracleMaxPixels <= $t.oracleMaxPixels
    and .maximumRelativeMomentumDrift <= $t.relativeMomentumDrift
    and .adaptiveToleranceFailureCount == 0
    and .p95GPUMilliseconds <= (
      if .workload.output.height == 1080 then $t.p95Milliseconds1080
      else $t.p95Milliseconds4K end)
    and .centroidDistancePixels <= (
      if .workload.output.height == 1080 then $t.centroidPixels1080
      else $t.centroidPixels4K end)
    and .contourDistancePixels <= (
      if .workload.output.height == 1080 then $t.contourPixels1080
      else $t.contourPixels4K end);
  . as $r
  | .schemaVersion == 1
  and .referenceValidationPassed == true
  and .referenceIdentityNormalizedExposureDelta >= 0
  and (.referenceIdentityNormalizedExposureDelta | isfinite)
  and .referenceIdentityNormalizedExposureDelta <= .thresholds.exposureDeltaFraction
  and .referenceFoldNormalizedExposureDelta >= 0
  and (.referenceFoldNormalizedExposureDelta | isfinite)
  and .referenceFoldNormalizedExposureDelta <= .thresholds.exposureDeltaFraction
  and .hardware.deviceName == "Apple M5 Max"
  and .hardware.gpuCoreCount == 40
  and .hardware.memoryGB >= 120
  and .thresholds == {
    "identityRMSPixels":0.25, "identityMaxPixels":0.75,
    "oracleRMSPixels":0.25, "oracleMaxPixels":1,
    "relativeMomentumDrift":0.00001, "exposureDeltaFraction":0.02,
    "centroidPixels1080":1, "centroidPixels4K":2,
    "contourPixels1080":2, "contourPixels4K":4,
    "p95Milliseconds1080":4, "p95Milliseconds4K":8
  }
  and (.measurements | length == 144)
  and ([.measurements[] | structurally_valid] | all)
  and (.status == "go" or .status == "stop1080" or .status == "blocked4K")
  and (.recommendation | type == "string" and length > 0)
  and (if .status == "go" then
    .recommendedWorkload != null
    and ([.measurements[]
      | select(
          .workload.representation == $r.recommendedWorkload.representation
          and .workload.samples == $r.recommendedWorkload.samples
          and .workload.integrationSteps == $r.recommendedWorkload.integrationSteps
        )] | length == 4 and all(passes($r.thresholds)))
  else .recommendedWorkload == null end)
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
jq -e '
  ([.measurements[]
    | [.workload.representation, .workload.output.width, .workload.output.height,
       .workload.fixture, .workload.samples.width, .workload.samples.height,
       .workload.integrationSteps]] | sort) ==
  ([(["gaussianPointSprite", "scanlineRibbon", "adaptiveScanlineSegment"][]) as $r
    | ([[1920,1080], [3840,2160]][]) as $o
    | (["identity", "fold"][]) as $f
    | ([[480,270], [960,540], [1280,720], [1920,1080]][]) as $g
    | ([8,16,32][]) as $s
    | [$r, $o[0], $o[1], $f, $g[0], $g[1], $s]] | sort)
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  verify-artifact \
  --suite matrix \
  --report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
jq -e '
  def normalized_exposure:
    .integratedExposure
      / (.workload.output.width * .workload.output.height);
  def exposure_family_passes($report; $fixture; $expected):
    try (
      [$report.measurements[]
        | select(
            .workload.representation == $report.recommendedWorkload.representation
            and .workload.fixture == $fixture
          )
        | normalized_exposure] as $values
      | ($values | length) == $expected
        and ($values | all(isfinite and . > 0))
        and (((($values | max) - ($values | min)) / ($values | min))
          <= $report.thresholds.exposureDeltaFraction)
    ) catch false;
  . as $report
  | if .status == "go"
    then ["identity", "fold"] | all(
      . as $fixture
      | exposure_family_passes($report; $fixture; 24)
    )
    else true
    end
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
preview_count=$(find docs/arshader/benchmarks/wobbulator-phase1/previews \
  -type f -name '*.ppm' | wc -l | tr -d ' ')
echo "preview_count=$preview_count"
matrix_status=$(jq -r '.status' \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
if test "$matrix_status" = go; then
  selected_representation=$(jq -r '.recommendedWorkload.representation' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  selected_grid=$(jq -r \
    '.recommendedWorkload.samples | "\(.width)x\(.height)"' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  selected_steps=$(jq -r '.recommendedWorkload.integrationSteps' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  for selected_output in 1920x1080 3840x2160; do
    for selected_fixture in identity fold; do
      test -s \
        "docs/arshader/benchmarks/wobbulator-phase1/previews/selected-${selected_representation}-${selected_output}-grid${selected_grid}-steps${selected_steps}-${selected_fixture}.ppm"
    done
  done
  test "$preview_count" -eq 16
else
  test "$preview_count" -eq 12
fi
jq -r '.status, .recommendation' \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
~~~

Expected: both `jq` validations and the decoded-artifact verifier succeed, the complete workload
universe is exactly the signed 144 tuples, every report value is finite and domain-valid, and the
persisted status, recommendation, and selected workload exactly match a fresh decision
recomputation. Any `go` recommendation independently passes every signed gate, including
normalized 1080p/4K exposure, with zero invalids or adaptive failures. Every result has exactly 12
high-quality comparison previews: 3 representations x 2 resolutions x 2 fixtures. A `go` result
has four additional previews for both fixtures and resolutions rendered with the exact selected
representation, source grid, and integration-step floor.

- [ ] **Step 4: Enforce the matrix stop decision before thermal work**

Read the report's `status` and follow exactly one branch:

- `stop1080`: skip thermal work. Keep the matrix report, make `decision.md` state that native
  production integration is rejected pending a new approved representation or threshold
  revision, then complete Steps 6 through 9 and terminate before Phase 2.
- `blocked4K`: skip thermal work. Keep the matrix report, make `decision.md` state that the 1080p
  finding does not satisfy the approved 4K product scope, then complete Steps 6 through 9 and
  terminate before Phase 2.
- `go`: verify that `recommendedWorkload` is present, then continue to Step 5.

Run:

~~~bash
jq -e '
  if .status == "go"
  then .recommendedWorkload != null
  else .recommendedWorkload == null
  end
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
~~~

Do not substitute the fastest failing representation, average identity and fold results together,
or advance a 1080p-only configuration.

- [ ] **Step 5: Run the paced ten-minute thermal proof at both resolutions**

Repeat Step 1's idle-system checks immediately before this run. Then run:

~~~bash
rm -f docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  --suite thermal \
  --selection-report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
  --thermal-seconds 600 \
  --output docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
  --decision docs/arshader/benchmarks/wobbulator-phase1/decision.md
~~~

This executes two independent 600-second workloads, selected fold at 1080p and selected fold at
4K, paced at 60 Hz. If the command returns nonzero, preserve the report and enforce its stop state.

Validate the complete thermal report:

~~~bash
jq -e --slurpfile matrix \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json '
  def structurally_valid:
    .frameCount >= 30000
    and .p50GPUMilliseconds > 0 and (.p50GPUMilliseconds | isfinite)
    and .p95GPUMilliseconds > 0 and (.p95GPUMilliseconds | isfinite)
    and .p50GPUMilliseconds <= .p95GPUMilliseconds
    and .meanCPUMilliseconds >= 0 and (.meanCPUMilliseconds | isfinite)
    and .measuredWallSeconds >= 600 and (.measuredWallSeconds | isfinite)
    and .thermalTargetSeconds == 600
    and .thermalTargetFramesPerSecond == 60
    and .allocatedBytes > 0
    and .fieldEvaluationsPerFrame > 0
    and .primitiveInstancesPerFrame > 0
    and .integratedExposure > 0 and (.integratedExposure | isfinite)
    and ([.relativeExposureDelta, .centroidDistancePixels, .contourDistancePixels,
          .identityRMSPixels, .identityMaxPixels, .oracleRMSPixels, .oracleMaxPixels,
          .maximumRelativeMomentumDrift] | all(. >= 0 and isfinite))
    and (.branchRetentionPassed | type == "boolean")
    and .invalidSampleCount >= 0
    and .adaptiveInvalidIntervalCount >= 0
    and .adaptiveToleranceFailureCount >= 0
    and (.measuredResourceCreations
      | [.commandQueues, .buffers, .textures, .libraries,
         .computePipelines, .renderPipelines] | all(. == 0));
  def passes($t):
    structurally_valid
    and .branchRetentionPassed == true
    and .invalidSampleCount == 0
    and .adaptiveInvalidIntervalCount == 0
    and .relativeExposureDelta <= $t.exposureDeltaFraction
    and .identityRMSPixels <= $t.identityRMSPixels
    and .identityMaxPixels <= $t.identityMaxPixels
    and .oracleRMSPixels <= $t.oracleRMSPixels
    and .oracleMaxPixels <= $t.oracleMaxPixels
    and .maximumRelativeMomentumDrift <= $t.relativeMomentumDrift
    and .adaptiveToleranceFailureCount == 0
    and .p95GPUMilliseconds <= (
      if .workload.output.height == 1080 then $t.p95Milliseconds1080
      else $t.p95Milliseconds4K end)
    and .centroidDistancePixels <= (
      if .workload.output.height == 1080 then $t.centroidPixels1080
      else $t.centroidPixels4K end)
    and .contourDistancePixels <= (
      if .workload.output.height == 1080 then $t.contourPixels1080
      else $t.contourPixels4K end);
  . as $r
  | $matrix[0].recommendedWorkload as $selected
  | .schemaVersion == 1
  and .referenceValidationPassed == true
  and .referenceIdentityNormalizedExposureDelta >= 0
  and (.referenceIdentityNormalizedExposureDelta | isfinite)
  and .referenceIdentityNormalizedExposureDelta <= .thresholds.exposureDeltaFraction
  and .referenceFoldNormalizedExposureDelta >= 0
  and (.referenceFoldNormalizedExposureDelta | isfinite)
  and .referenceFoldNormalizedExposureDelta <= .thresholds.exposureDeltaFraction
  and .hardware.deviceName == "Apple M5 Max"
  and .hardware.gpuCoreCount == 40
  and .hardware.memoryGB >= 120
  and .thresholds == $matrix[0].thresholds
  and (.measurements | length == 2)
  and ([.measurements[].workload.output] | sort)
      == ([{"width":1920,"height":1080},{"width":3840,"height":2160}] | sort)
  and ([.measurements[]
    | .workload.fixture == "fold"
      and .workload.representation == $selected.representation
      and .workload.samples == $selected.samples
      and .workload.integrationSteps == $selected.integrationSteps
      and structurally_valid] | all)
  and (.status == "go" or .status == "stop1080" or .status == "blocked4K")
  and (.recommendation | type == "string" and length > 0)
  and (if .status == "go"
    then .recommendedWorkload != null and ([.measurements[] | passes($r.thresholds)] | all)
    else .recommendedWorkload == null end)
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  verify-artifact \
  --suite thermal \
  --report docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
  --selection-report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
jq -e '
  def normalized_exposure:
    .integratedExposure
      / (.workload.output.width * .workload.output.height);
  . as $report
  | if .status == "go"
    then [$report.measurements[] | normalized_exposure] as $values
      | ($values | length) == 2
        and ($values | all(isfinite and . > 0))
        and (((($values | max) - ($values | min)) / ($values | min))
          <= $report.thresholds.exposureDeltaFraction)
    else true
    end
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
jq -r '
  .measurements[]
  | [
      (.workload.output.width|tostring) + "x" + (.workload.output.height|tostring),
      "frames=" + (.frameCount|tostring),
      "p50=" + (.p50GPUMilliseconds|tostring),
      "p95=" + (.p95GPUMilliseconds|tostring),
      "invalid=" + (.invalidSampleCount|tostring)
    ]
  | @tsv
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
~~~

Expected: exactly two structurally valid measurements, each recording a requested 600-second,
60 Hz target, at least 600 measured wall seconds, and at least 30,000 paced frames. The verifier
also proves that the pair is the matrix-selected candidate and that the persisted terminal state
is a fresh exact recomputation. A thermal `go` additionally requires both rows to have zero
invalids, zero adaptive failures, normalized exposure within 2 percent across resolutions, and
every signed metric within bounds, including p95 <= 4 ms at 1080p and <= 8 ms at 4K.

- [ ] **Step 6: Perform the visual, reviewer, and operator approval checkpoints**

Open all 12 high-quality PPM comparison previews and compare each representation against the
CPU-authority-validated canonical GPU reference metrics recorded in JSON. For a matrix `go`, also
open the four `selected-*` previews. Confirm from their filenames and the matrix JSON that they
use the exact selected representation, source grid, and integration-step floor at both 1080p and
4K for identity and fold. The visual pass rejects:

- an absent fold branch or single-valued smear where two source-color branches should overlap;
- clipped caustic energy, unexplained exposure pumping, holes, NaNs, or non-black uncovered pixels;
- inconsistent beam width between 1080p and 4K;
- a result whose numerical contour passes but whose topology is visibly wrong.

Before review, prove that the durable decision binds the combined evidence and exact selected
visuals:

~~~bash
decision_path=docs/arshader/benchmarks/wobbulator-phase1/decision.md
for required_heading in \
  '## What this proves' \
  '## What is not built or proven' \
  '## Evidence candidate' \
  '## Selected visual manifest' \
  '## Combined matrix and thermal gates' \
  '## Next action' \
  '## Revised estimate' \
  '## Human approval gate'; do
  rg -F -x --quiet -- "$required_heading" "$decision_path"
done
matrix_status=$(jq -r '.status' \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
if test "$matrix_status" = go; then
  selected_representation=$(jq -r '.recommendedWorkload.representation' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  selected_grid=$(jq -r \
    '.recommendedWorkload.samples | "\(.width)x\(.height)"' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  selected_steps=$(jq -r '.recommendedWorkload.integrationSteps' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  for selected_output in 1920x1080 3840x2160; do
    for selected_fixture in identity fold; do
      expected_manifest_line="- \`previews/selected-${selected_representation}-${selected_output}-grid${selected_grid}-steps${selected_steps}-${selected_fixture}.ppm\`"
      rg -F -x --quiet -- "$expected_manifest_line" "$decision_path"
    done
  done
fi
~~~

Expected: every operator-facing section exists and, whenever the matrix selected a candidate,
the decision names exactly the same four relative preview paths that Step 3 proved exist.

Have the Mechanic reviewer inspect the exact selected rendering evidence, candidate-specific
branch-retention proof, allocation instrumentation, and GPU-timing methodology. Have the Client
Success reviewer inspect whether `decision.md` makes the stop/go state, supported scope,
limitations, operator controls, and next action unambiguous. Resolve every reviewer deviation;
an unresolved deviation blocks the evidence commit even when the numerical status is `go`.
These reviews are advisory on Codex and must be reported as such.

Present the terminal result and visual evidence to the operator and wait for an explicit positive
verdict. For `go`, that verdict approves the exact selected quality floor for Phase 2. For a stop
state, it approves the accuracy and completeness of the recorded stop evidence, not production
work. Silence is not approval. Only after the operator, Mechanic, and Client Success have each
returned a positive verdict and all deviations are resolved, replace the generated approval gate
in `decision.md` with these exact four lines:

~~~markdown
- Operator verdict: APPROVED
- Mechanic verdict: APPROVED
- Client Success verdict: APPROVED
- Open deviations: 0
~~~

Then run:

~~~bash
decision_path=docs/arshader/benchmarks/wobbulator-phase1/decision.md
test "$(rg -x -- '- Operator verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Mechanic verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Client Success verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Open deviations: 0' "$decision_path" | wc -l | tr -d ' ')" -eq 1
if rg -n 'PENDING|unresolved' "$decision_path"; then
  exit 1
fi
~~~

Expected: all four exact approval markers occur once and no pending verdict or unresolved review
deviation remains. This gate is required for both go and stop evidence closeout.

- [ ] **Step 7: Freeze the selected representation and revised delivery estimate**

For a thermal `go`, verify that `decision.md` contains the selected representation, source-grid
floor, integration-step floor, beam-width convention, 1080p and 4K worst p95, and minimum
effect-budget headroom. The runner maps that headroom to the following evidence-based estimate:

| Minimum headroom against both effect budgets | Phases 2 through 9 estimate |
|---|---|
| At least 25 percent | 24 to 32 focused days |
| At least 10 percent and below 25 percent | 28 to 38 focused days |
| Below 10 percent while still passing | 34 to 46 focused days, plus an explicit optimization gate |

A focused day is one day of focused engineering effort. It is not calendar duration or a ship
date; operator/reviewer wait time and the separately approved Conditional Fast Preview are
excluded from these ranges.

For `stop1080` or `blocked4K`, do not publish a production delivery estimate. State the failed
gate and the next research decision instead.

The approved tolerances are immutable in this evidence pass. If results show that a tolerance
must change, create a versioned revision of
`docs/superpowers/specs/2026-08-03-paik-abe-wobbulator-arshader.md`, present the evidence and
tradeoff to the operator, and wait for explicit approval before rerunning or advancing.

- [ ] **Step 8: Verify every artifact and prove the evidence set is clean**

Run:

~~~bash
swift format lint --strict --recursive WobbulatorKit/Sources WobbulatorKit/Tests
swift test --package-path WobbulatorKit
swift build --package-path WobbulatorKit -c release --product WobbulatorBench
git diff --check
jq empty docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
  verify-artifact \
  --suite matrix \
  --report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
jq -e '
  def normalized_exposure:
    .integratedExposure
      / (.workload.output.width * .workload.output.height);
  def exposure_family_passes($report; $fixture; $expected):
    try (
      [$report.measurements[]
        | select(
            .workload.representation == $report.recommendedWorkload.representation
            and .workload.fixture == $fixture
          )
        | normalized_exposure] as $values
      | ($values | length) == $expected
        and ($values | all(isfinite and . > 0))
        and (((($values | max) - ($values | min)) / ($values | min))
          <= $report.thresholds.exposureDeltaFraction)
    ) catch false;
  . as $report
  | if .status == "go"
    then ["identity", "fold"] | all(
      . as $fixture
      | exposure_family_passes($report; $fixture; 24)
    )
    else true
    end
' docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
matrix_status=$(jq -r '.status' \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
decision_path=docs/arshader/benchmarks/wobbulator-phase1/decision.md
preview_count=$(find docs/arshader/benchmarks/wobbulator-phase1/previews \
  -type f -name '*.ppm' | wc -l | tr -d ' ')
if test "$matrix_status" = go; then
  selected_representation=$(jq -r '.recommendedWorkload.representation' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  selected_grid=$(jq -r \
    '.recommendedWorkload.samples | "\(.width)x\(.height)"' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  selected_steps=$(jq -r '.recommendedWorkload.integrationSteps' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json)
  for selected_output in 1920x1080 3840x2160; do
    for selected_fixture in identity fold; do
      test -s \
        "docs/arshader/benchmarks/wobbulator-phase1/previews/selected-${selected_representation}-${selected_output}-grid${selected_grid}-steps${selected_steps}-${selected_fixture}.ppm"
      expected_manifest_line="- \`previews/selected-${selected_representation}-${selected_output}-grid${selected_grid}-steps${selected_steps}-${selected_fixture}.ppm\`"
      rg -F -x --quiet -- "$expected_manifest_line" "$decision_path"
    done
  done
  test "$preview_count" -eq 16
else
  test "$preview_count" -eq 12
fi
for required_heading in \
  '## What this proves' \
  '## What is not built or proven' \
  '## Evidence candidate' \
  '## Selected visual manifest' \
  '## Combined matrix and thermal gates' \
  '## Next action' \
  '## Revised estimate' \
  '## Human approval gate'; do
  rg -F -x --quiet -- "$required_heading" "$decision_path"
done
if test -f docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json; then
  jq empty docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
  swift run --package-path WobbulatorKit -c release --skip-build WobbulatorBench -- \
    verify-artifact \
    --suite thermal \
    --report docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
    --selection-report docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
  jq -e '
    def normalized_exposure:
      .integratedExposure
        / (.workload.output.width * .workload.output.height);
    . as $report
    | if .status == "go"
      then [$report.measurements[] | normalized_exposure] as $values
        | ($values | length) == 2
          and ($values | all(isfinite and . > 0))
          and (((($values | max) - ($values | min)) / ($values | min))
            <= $report.thresholds.exposureDeltaFraction)
      else true
      end
  ' docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
  artifact_leak_count=$(rg -ni \
    'serial|uuid|registry|[/]Users[/]|arson[r]ivvers' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json \
    docs/arshader/benchmarks/wobbulator-phase1/decision.md | wc -l | tr -d ' ')
else
  jq -e '.status != "go"' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
  artifact_leak_count=$(rg -ni \
    'serial|uuid|registry|[/]Users[/]|arson[r]ivvers' \
    docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
    docs/arshader/benchmarks/wobbulator-phase1/decision.md | wc -l | tr -d ' ')
fi
test "$(rg -x -- '- Operator verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Mechanic verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Client Success verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Open deviations: 0' "$decision_path" | wc -l | tr -d ' ')" -eq 1
if rg -n 'PENDING|unresolved' "$decision_path"; then
  exit 1
fi
echo "artifact_leak_count=$artifact_leak_count"
test "$artifact_leak_count" -eq 0
placeholder_count=$(rg -n \
  'TODO|TBD|FIXME|XXX|PLACEHOLDER' \
  WobbulatorKit \
  docs/arshader/benchmarks/wobbulator-phase1 | wc -l | tr -d ' ')
echo "placeholder_count=$placeholder_count"
test "$placeholder_count" -eq 0
~~~

Expected: lint, tests, release build, diff check, JSON parsing, decoded decision recomputation,
independent normalized-exposure checks, exact selected-preview checks, and all four human approval
markers pass; both exhaustive hygiene counts print 0. Thermal artifact absence is accepted only
when the matrix verifier confirms a stop state, and that absence is recorded explicitly.

- [ ] **Step 9: Commit evidence only after the gate result is final**

Do not stage evidence until Step 8 passes with the explicit operator, Mechanic, and Client Success
approval markers and zero open deviations. Recheck the three load-bearing approvals immediately
before staging:

~~~bash
decision_path=docs/arshader/benchmarks/wobbulator-phase1/decision.md
test "$(rg -x -- '- Operator verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Mechanic verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Client Success verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Open deviations: 0' "$decision_path" | wc -l | tr -d ' ')" -eq 1
~~~

Resolve the matrix and thermal branch before staging. A matrix stop has no thermal artifact. A
matrix `go` always has a thermal artifact, including when thermal ends in `stop1080` or
`blocked4K`; that failed thermal report is load-bearing stop evidence and must be committed.
Run exactly:

~~~bash
matrix_path=docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json
thermal_path=docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
matrix_status=$(jq -r '.status' "$matrix_path")
if test "$matrix_status" = go; then
  test -s "$thermal_path"
  thermal_status=$(jq -r '.status' "$thermal_path")
else
  test "$matrix_status" = stop1080 || test "$matrix_status" = blocked4K
  test ! -e "$thermal_path"
  thermal_status=not-run
fi
case "$matrix_status:$thermal_status" in
  go:go)
    evidence_commit_message="evidence: select M5 wobbulator renderer"
    include_thermal=yes
    ;;
  go:stop1080|go:blocked4K)
    evidence_commit_message="evidence: record M5 wobbulator thermal stop"
    include_thermal=yes
    ;;
  stop1080:not-run|blocked4K:not-run)
    evidence_commit_message="evidence: record M5 wobbulator matrix stop"
    include_thermal=no
    ;;
  *)
    exit 1
    ;;
esac
git add docs/arshader/benchmarks/wobbulator-phase1/README.md \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-matrix.json \
  docs/arshader/benchmarks/wobbulator-phase1/previews \
  docs/arshader/benchmarks/wobbulator-phase1/decision.md
if test "$include_thermal" = yes; then
  git add "$thermal_path"
fi
unexpected_staged_count=$(git diff --cached --name-only | rg -v \
  '^docs/arshader/benchmarks/wobbulator-phase1/(README[.]md|m5-max-matrix[.]json|m5-max-thermal[.]json|decision[.]md|previews/.+[.]ppm)$' \
  | wc -l | tr -d ' ')
echo "unexpected_staged_count=$unexpected_staged_count"
test "$unexpected_staged_count" -eq 0
git diff --cached --check
git commit -m "$evidence_commit_message"
~~~

Expected: thermal evidence is staged whenever and only whenever the matrix reached `go`. A failed
thermal report is committed with the matrix, previews, README, and approved stop decision. A
matrix stop proves the thermal path was never run and commits no invented thermal file. After
either stop commit, terminate this plan and do not execute Step 10. Only `go:go` continues.

- [ ] **Step 10: Open the evidence-gated Phase 2 plan**

Only after a committed thermal `go` result, exact `Operator verdict: APPROVED`,
`Mechanic verdict: APPROVED`, and `Client Success verdict: APPROVED` markers, and exact
`Open deviations: 0`, use the `prebuild` and `writing-plans` skills to create
`docs/superpowers/plans/2026-08-03-paik-abe-wobbulator-phase-2-native-stage.md`. Its first task
must consume the exact frozen representation and quality floor from `decision.md` and implement
the approved shared `FXStageDescriptor`, `FXStageRenderCore`, `FXRenderContext`, and
`FXEncodeResult` seam with an identity native stage. Do not modify the host in Phase 1 or draft
line-level Phase 3 work before the Phase 2 seam has live integration evidence.

Before opening that plan, run:

~~~bash
jq -e '.status == "go" and .recommendedWorkload != null' \
  docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
thermal_path=docs/arshader/benchmarks/wobbulator-phase1/m5-max-thermal.json
decision_path=docs/arshader/benchmarks/wobbulator-phase1/decision.md
test "$(rg -x -- '- Operator verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Mechanic verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Client Success verdict: APPROVED' "$decision_path" | wc -l | tr -d ' ')" -eq 1
test "$(rg -x -- '- Open deviations: 0' "$decision_path" | wc -l | tr -d ' ')" -eq 1
thermal_evidence_sha=$(git log -1 --format='%H' -- "$thermal_path")
decision_evidence_sha=$(git log -1 --format='%H' -- "$decision_path")
test -n "$thermal_evidence_sha"
test "$thermal_evidence_sha" = "$decision_evidence_sha"
evidence_sha=$thermal_evidence_sha
git diff --quiet "$evidence_sha" -- "$thermal_path" "$decision_path"
git diff --cached --quiet "$evidence_sha" -- "$thermal_path" "$decision_path"
echo "evidence_sha=$evidence_sha"
~~~

Expected: the thermal artifact is `go`, each approval marker exists exactly, both files have the
same last-touch commit, and neither the working tree nor index differs from that commit. Git
prints the binding evidence SHA. Any failure leaves Phase 2 closed.

---
