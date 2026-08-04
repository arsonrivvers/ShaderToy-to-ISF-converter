# TrueISF Remix Canvas Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Remix Studio into a maximized, canvas-first native workspace with moving parent previews, truthful child progress, immediate first-ready payoff, and one compact command surface.

**Architecture:** Bind every child card and aggregate status directly to the durable `RemixChildRunRecord` pipeline created by the reliability plan. Keep layout and accessibility decisions in pure presentation models, then make SwiftUI views thin renderers. Reuse `RemixThumbnailView`, the shared `RenderClock`, and the strict four-surface budget for parents and ready children.

**Tech Stack:** SwiftUI, AppKit `NSWindow`, Metal preview controller, Combine, XCTest, XcodeGen, macOS 13 or newer.

## Global Constraints

- The reliability plan `2026-08-01-remix-pipeline-reliability.md` must be complete first.
- Open maximized in a normal macOS window, never a native full-screen Space.
- Preserve later user window size and position.
- Parent A and Parent B both move on a shared clock while Setup is expanded before generation.
- The existing global live-preview cap remains four surfaces. A newly Ready child outranks parent previews.
- Starting a batch compacts Setup and releases both parent preview reservations.
- The first Ready child must animate immediately without waiting for siblings or stealing focus.
- Reduce Motion starts compiled previews paused and exposes a labeled Play action.
- Every rendered text style is at least 14 points and meaning never depends only on color, motion, hover, or an icon.
- Replace visible collapse, pixel-resize, and reset clutter with one Workspace menu.
- Keep every focused-child action available by pointer, keyboard, context menu, and VoiceOver custom action.
- Do not show a percentage or ETA for unequal stages. Determinate progress counts terminal slots only.
- Quiet means no provider event past the threshold while the provider process is confirmed alive. Silence alone is not a stall.
- Do not push until the standing null_signal colleague heads-up is confirmed. **CLOSED 2026-08-03 — the heads-up was given and the colleague confirmed go-ahead (operator, this session).**

---

### Task 1: Run-record presentation, truthful progress, and boundary-specific recovery

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixRunPresentation.swift`
- Modify: `App/TrueISFEditor/Remix/RemixActivity.swift`
- Modify: `App/TrueISFEditor/Remix/RemixActivityDrawerView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixLineagePresentation.swift`
- Modify: `App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixChildCardView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Create: `App/TrueISFEditorTests/RemixRunPresentationTests.swift`
- Modify: `App/TrueISFEditorTests/RemixActivityTests.swift`
- Modify: `App/TrueISFEditorTests/RemixLineagePresentationTests.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: ordered `RemixChildRunRecord` values, optional Ready `RemixNode` artifacts, optional `RemixPreviewState`, and the model's transient `activeProviderChildIDs` set.
- Produces: per-child status text, liveness text, aggregate stage counts, correct failure labels, and scoped recovery actions.

- [ ] **Step 1: Write failing presentation tests for every stage and failure boundary**

Use a fixed clock and assert exact maker-facing copy:

```swift
func testAggregateSummaryNamesActiveStagesAndQueue() {
    let summary = RemixRunPresentation.aggregate(
        records: [receivingA, receivingB, queuedA, queuedB, queuedC],
        now: date(120),
        quietThreshold: 30
    )
    XCTAssertEqual(summary.compactStatus, "2 receiving, 3 queued, 0 ready")
    XCTAssertEqual(summary.terminalCount, 0)
    XCTAssertEqual(summary.totalCount, 5)
}

func testFailureTitlesNameTheActualBoundary() {
    XCTAssertEqual(RemixRunPresentation.child(providerFailure, now: date(10)).title, "Provider Failed")
    XCTAssertEqual(RemixRunPresentation.child(responseFailure, now: date(10)).title, "Response Incomplete")
    XCTAssertEqual(RemixRunPresentation.child(extractionFailure, now: date(10)).title, "Extraction Failed")
    XCTAssertEqual(RemixRunPresentation.child(compileFailure, now: date(10)).title, "Compile Failed")
    XCTAssertEqual(
        RemixRunPresentation.child(readyRun, preview: failedPreview, now: date(10)).title,
        "Preview Failed"
    )
}

func testQuietRequiresConfirmedLiveness() {
    XCTAssertEqual(
        RemixRunPresentation.child(oldReceiving, now: date(90), processAlive: true).liveness,
        "Quiet, still running"
    )
    XCTAssertNotEqual(
        RemixRunPresentation.child(oldReceiving, now: date(90), processAlive: false).liveness,
        "Quiet, still running"
    )
}
```

Also test stage labels Queued, Starting, Thinking, Receiving, Retrying, Extracting, Compiling, Ready, Cancelled, and Interrupted. Retrying is reserved for a provider-reported API retry and includes its bounded attempt or wait detail. A user-triggered Retry instead replaces the terminal record with Queued in the same stable slot and uses the detail `Retry queued`. Provider, response, extraction, compile, cancellation, and interruption come from the run record; Preview Failed and Retry Preview come only from the separate preview state while the run remains Ready.

Add model tests proving `processStarted` adds only the matching child to `activeProviderChildIDs`, exit and terminal transitions remove it, and silence without membership never produces `Quiet, still running`. An API retry enters Retrying and displays bounded detail such as `Provider retry 2`; the next provider activity exits Retrying truthfully.

- [ ] **Step 2: Run the presentation tests and verify they fail**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace \
  -only-testing:TrueISFEditorTests/RemixRunPresentationTests \
  -only-testing:TrueISFEditorTests/RemixActivityTests \
  -only-testing:TrueISFEditorTests/RemixLineagePresentationTests \
  -only-testing:TrueISFEditorTests/RemixStudioModelTests
```

- [ ] **Step 3: Implement pure run presentation values**

Use these shapes:

```swift
struct RemixChildRunPresentation: Equatable {
    let title: String
    let detail: String
    let liveness: String?
    let elapsed: String?
    let accessibilityLabel: String
    let actions: [RemixRunAction]
}

struct RemixAggregateRunPresentation: Equatable {
    let compactStatus: String
    let accessibilityAnnouncement: String
    let stageCounts: [RemixChildRunRecord.Stage: Int]
    let terminalCount: Int
    let totalCount: Int
}

enum RemixRunAction: String, CaseIterable, Equatable {
    case viewResponse = "View Response"
    case viewSummary = "View Summary"
    case copyDiagnostic = "Copy Diagnostic"
    case openSource = "Open Source"
    case openToFix = "Open to Fix"
    case retryChild = "Retry Child"
    case retryPreview = "Retry Preview"
    case openInEditor = "Open in Editor"
}
```

Format durations as elapsed whole seconds below one minute, `Xm Ys` below one hour, and `Xh Ym` above one hour. Do not calculate ETA.

- [ ] **Step 4: Bind Activity and child cards to run records**

The Activity strip reads the aggregate presentation. The expanded drawer uses `LazyVStack`, lists boundary-specific failures first, and keeps raw JSON out of the normal surface. `RemixChildrenCanvasView` passes each stable item into `RemixChildCardView`, which receives `run: RemixChildRunRecord`, `artifact: RemixNode?`, `preview: RemixPreviewState?`, and `processAlive: Bool` derived from `model.activeProviderChildIDs.contains(run.id)`. It never switches on legacy `RemixNode.Status`. Never infer liveness from an async task, stage, spinner, or elapsed time.

- [ ] **Step 5: Update VoiceOver announcements to meaningful transitions only**

Announce batch start, first Ready, each terminal failure, Stop, and batch completion. Do not announce token deltas or every liveness tick. Preserve keyboard and accessibility focus.

- [ ] **Step 6: Run tests and commit**

Run the Step 2 command. Expected: all presentation tests pass.

```bash
git add App/TrueISFEditor/Remix/RemixRunPresentation.swift \
  App/TrueISFEditor/Remix/RemixActivity.swift \
  App/TrueISFEditor/Remix/RemixActivityDrawerView.swift \
  App/TrueISFEditor/Remix/RemixLineagePresentation.swift \
  App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift \
  App/TrueISFEditor/Remix/RemixChildCardView.swift \
  App/TrueISFEditor/Remix/RemixStudioModel.swift \
  App/TrueISFEditorTests/RemixRunPresentationTests.swift \
  App/TrueISFEditorTests/RemixActivityTests.swift \
  App/TrueISFEditorTests/RemixLineagePresentationTests.swift \
  App/TrueISFEditorTests/RemixStudioModelTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): present truthful child pipeline states"
```

### Task 2: Maximized normal window with later frame restoration

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixWindowConfigurator.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioView.swift:11-25`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift:330-345`
- Create: `App/TrueISFEditorTests/RemixWindowConfiguratorTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: the Remix `NSWindow`, its screen visible frame, and whether an autosaved frame exists.
- Produces: one first-open maximize decision and a stable autosave name for later AppKit restoration.

- [ ] **Step 1: Write failing pure launch-policy tests**

```swift
func testFirstOpenUsesVisibleFrameRatherThanFullScreenFrame() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let visibleFrame = CGRect(x: 0, y: 25, width: 1728, height: 1052)
    XCTAssertEqual(
        RemixWindowLaunchPolicy.frame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            hasAutosavedFrame: false
        ),
        visibleFrame
    )
}

func testLaterOpenDefersToAutosavedFrame() {
    XCTAssertNil(RemixWindowLaunchPolicy.frame(
        screenFrame: .zero,
        visibleFrame: CGRect(x: 10, y: 10, width: 100, height: 100),
        hasAutosavedFrame: true
    ))
}
```

- [ ] **Step 2: Run the window tests and verify the policy is missing**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace \
  -only-testing:TrueISFEditorTests/RemixWindowConfiguratorTests
```

- [ ] **Step 3: Implement an AppKit window accessor and launch policy**

`RemixWindowConfigurator` is an `NSViewRepresentable` whose attached view dispatches once to the main queue, finds `view.window`, calls `setFrameAutosaveName("TrueISFEditor.RemixStudio")`, and applies `window.screen?.visibleFrame` only when no autosaved frame exists. Never call `toggleFullScreen`, never modify `collectionBehavior`, and never maximize again from `updateNSView`.

- [ ] **Step 4: Wire the configurator without changing the 720 by 600 minimum**

Place the zero-sized configurator in the background of `RemixStudioView`. Keep `.defaultSize(width: 1280, height: 800)` as the fallback when no screen exists.

- [ ] **Step 5: Run tests, build, and commit**

Run Step 2, then:

```bash
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath ./ddata-remix-workspace build
```

Expected: tests pass and `BUILD SUCCEEDED`.

```bash
git add App/TrueISFEditor/Remix/RemixWindowConfigurator.swift \
  App/TrueISFEditor/Remix/RemixStudioView.swift App/TrueISFEditor/TrueISFEditorApp.swift \
  App/TrueISFEditorTests/RemixWindowConfiguratorTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): maximize the canvas workspace on first open"
```

### Task 3: Compact Setup with synchronized moving parent previews

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixParentPreviewCard.swift`
- Create: `App/TrueISFEditor/Remix/RemixParentSourceSheet.swift`
- Create: `App/TrueISFEditor/Remix/RemixParentPreviewCoordinator.swift`
- Modify: `App/TrueISFEditor/Remix/RemixBreedingBayView.swift:4-258`
- Modify: `App/TrueISFEditor/Remix/RemixBreedingBayPresentation.swift:68-249`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift:14-23,520-594`
- Modify: `App/TrueISFEditor/Remix/RemixWorkspaceState.swift`
- Modify: `App/TrueISFEditorTests/RemixBreedingBayPresentationTests.swift`
- Create: `App/TrueISFEditorTests/RemixParentPreviewCoordinatorTests.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/TrueISFEditorTests/RemixWorkspaceStateTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: selected parent artifacts, one shared `RenderClock`, Setup expanded state, Reduce Motion, and the four-surface preview budget.
- Produces: compact labeled Parent A and Parent B preview cards plus progressive-disclosure source selection.

- [ ] **Step 1: Write failing Setup and reservation-priority tests**

Assert:

```swift
XCTAssertTrue(presentation.showsParentPreview(.a))
XCTAssertTrue(presentation.showsParentPreview(.b))
XCTAssertFalse(presentation.showsPasteEditor(.a))
XCTAssertFalse(presentation.showsShadertoyField(.a))

let beforeGeneration = model.livePreviewReservations(reduceMotion: false)
XCTAssertTrue(beforeGeneration.contains(.init(nodeID: parentAID, surface: .parentA)))
XCTAssertTrue(beforeGeneration.contains(.init(nodeID: parentBID, surface: .parentB)))
XCTAssertLessThanOrEqual(beforeGeneration.count, 4)

model.applyPipelineUpdate(.artifact(newChild, record: readyRecord))
let withPayoff = model.livePreviewReservations(reduceMotion: false)
XCTAssertTrue(withPayoff.contains(.init(nodeID: newChild.id, surface: .canvas)))
XCTAssertLessThanOrEqual(withPayoff.count, 4)
```

Also prove starting generation compacts Setup and removes both parent reservations. Add clock tests with an injected time source proving global Pause, Reduce Motion, compact or hidden Setup, and zero parent reservations all freeze the shared clock; resuming continues without a jump; Reset Time resets the shared parent clock to zero.

- [ ] **Step 2: Run focused Setup tests and verify they fail**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace \
  -only-testing:TrueISFEditorTests/RemixBreedingBayPresentationTests \
  -only-testing:TrueISFEditorTests/RemixParentPreviewCoordinatorTests \
  -only-testing:TrueISFEditorTests/RemixStudioModelTests \
  -only-testing:TrueISFEditorTests/RemixWorkspaceStateTests
```

- [ ] **Step 3: Add Setup expansion and source-choice state**

Keep the persisted `RemixZone.breedingBay` raw value for schema compatibility, but display it as Setup. Add `setupExpanded` and `activeParentSourceChoice` state. `collapsedZones.contains(.breedingBay)` controls whether the entire Setup zone is visible; `setupExpanded` controls only whether visible Setup shows detailed source controls or compact parent cards. Setup is detailed when required parents are missing and compact after Generate. Edit Setup restores detailed content without changing parent identity.

Implement a custom `Codable` initializer for `RemixWorkspaceState`. Decode every newly added nonoptional field with `decodeIfPresent` and explicit defaults matching a fresh workspace. Add a literal pre-change schema-v2 JSON fixture and prove it restores successfully, keeps Setup visible, defaults Setup detail appropriately, and round-trips idempotently.

- [ ] **Step 4: Build the parent preview cards on one shared clock**

Each loaded parent card uses `RemixThumbnailView` at 16:9, shows Parent A or Parent B, display name, readiness, Replace, and Clear. Both cards receive the same model-owned `RenderClock` through `RemixParentPreviewCoordinator`. The coordinator is the sole owner of pausing, resuming, and resetting that shared clock. It pauses when global preview pause or Reduce Motion is active, Setup is compact or hidden, or neither parent has a live-surface reservation; it resumes without a time jump only when at least one parent is reserved and all pause conditions clear. Parent compile errors render `Parent Preview Failed` with Open in Editor and Replace actions; they do not clear the valid parent source.

- [ ] **Step 5: Move paste and Shadertoy entry into a source sheet**

The parent card's Add or Replace action opens `RemixParentSourceSheet`. Choosing Library or Current Editor acts immediately. Choosing Shadertoy reveals only its text field. Choosing Paste reveals only its editor. Preserve all existing human-verification recovery states and focus targets.

- [ ] **Step 6: Extend the preview budget and preserve payoff priority**

Add `.parentA` and `.parentB` surfaces. Priority is hero and compared Ready children, newly Ready payoff child, focused Ready child, visible parents, favorites and recent children, then duplicate inspector surfaces. Every reservation change updates `RemixParentPreviewCoordinator`, so losing the final parent reservation freezes the shared clock immediately. Setup compaction releases parent reservations. Reduce Motion returns zero animation reservations until the explicit Play command.

- [ ] **Step 7: Run tests and commit**

Run the Step 2 command. Expected: all tests pass and reservations never exceed four.

```bash
git add App/TrueISFEditor/Remix/RemixParentPreviewCard.swift \
  App/TrueISFEditor/Remix/RemixParentSourceSheet.swift \
  App/TrueISFEditor/Remix/RemixParentPreviewCoordinator.swift \
  App/TrueISFEditor/Remix/RemixBreedingBayView.swift \
  App/TrueISFEditor/Remix/RemixBreedingBayPresentation.swift \
  App/TrueISFEditor/Remix/RemixStudioModel.swift \
  App/TrueISFEditor/Remix/RemixWorkspaceState.swift \
  App/TrueISFEditorTests/RemixBreedingBayPresentationTests.swift \
  App/TrueISFEditorTests/RemixParentPreviewCoordinatorTests.swift \
  App/TrueISFEditorTests/RemixStudioModelTests.swift \
  App/TrueISFEditorTests/RemixWorkspaceStateTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): preview both parents in compact setup"
```

### Task 4: One Workspace menu and canvas-dominant layout

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixWorkspaceCommands.swift`
- Modify: `App/TrueISFEditor/Remix/RemixWorkspaceView.swift:3-193`
- Modify: `App/TrueISFEditor/Remix/RemixWorkspaceState.swift:28-181`
- Modify: `App/TrueISFEditor/Remix/RemixSplitLayout.swift:3-30`
- Modify: `App/TrueISFEditor/Remix/RemixActivityDrawerView.swift`
- Create: `App/TrueISFEditorTests/RemixWorkspaceCommandsTests.swift`
- Modify: `App/TrueISFEditorTests/RemixWorkspaceStateTests.swift`
- Modify: `App/TrueISFEditorTests/RemixSplitLayoutTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: persisted workspace state and available width.
- Produces: one `Workspace` menu with Setup, Lineage, Activity, Canvas Only, sizing, and Reset commands.

- [ ] **Step 1: Write failing command-routing tests**

Use a pure command enum:

```swift
enum RemixWorkspaceCommand: Equatable {
    case toggleSetup
    case toggleLineage
    case toggleActivity
    case focusCanvas
    case resize(RemixZone, Int)
    case resetLayout
}

enum RemixWorkspaceFocusTarget: Equatable {
    case workspaceMenu
    case setupFirstControl
    case lineageFirstControl
    case activityFirstControl
    case canvas
}

struct RemixWorkspaceCommandResult: Equatable {
    let state: RemixWorkspaceState
    let focusTarget: RemixWorkspaceFocusTarget
}
```

Tests must prove each command changes only its intended state, Canvas Only hides Setup, Lineage, and expanded Activity, Reset restores defaults, narrow layout never hides the canvas, and every command returns the correct explicit focus target.

- [ ] **Step 2: Run workspace tests and verify they fail**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace \
  -only-testing:TrueISFEditorTests/RemixWorkspaceCommandsTests \
  -only-testing:TrueISFEditorTests/RemixWorkspaceStateTests \
  -only-testing:TrueISFEditorTests/RemixSplitLayoutTests
```

- [ ] **Step 3: Replace the persistent layout toolbar with one menu**

The top row contains `Menu("Workspace")`, the compact activity summary, and the existing focused-child controls until Task 5 replaces them. Delete visible Collapse Setup, Resize Setup, Collapse Lineage, Resize Lineage, Focus Canvas, and Reset Layout buttons. This task must build independently without any Task 5 type.

Menu item labels reflect current state: Show or Hide Setup, Show or Hide Lineage, Show or Hide Activity, Focus Canvas or Restore Workspace. Keep keyboard-accessible increase and decrease size submenus.

- [ ] **Step 4: Route all layout changes through one tested command handler**

`RemixWorkspaceCommands.apply(_:to:) -> RemixWorkspaceCommandResult` is the sole state mutation path for menu layout commands. SwiftUI applies the returned target through `@FocusState`: after collapsing a zone, focus moves to the Workspace menu; after expanding, focus moves to that zone's first meaningful control; Reset returns focus to the canvas. A pure state mutator never claims to move AppKit or VoiceOver focus directly.

- [ ] **Step 5: Run tests and commit**

Run the Step 2 command. Expected: all layout tests pass.

```bash
git add App/TrueISFEditor/Remix/RemixWorkspaceCommands.swift \
  App/TrueISFEditor/Remix/RemixWorkspaceView.swift \
  App/TrueISFEditor/Remix/RemixWorkspaceState.swift \
  App/TrueISFEditor/Remix/RemixSplitLayout.swift \
  App/TrueISFEditor/Remix/RemixActivityDrawerView.swift \
  App/TrueISFEditorTests/RemixWorkspaceCommandsTests.swift \
  App/TrueISFEditorTests/RemixWorkspaceStateTests.swift \
  App/TrueISFEditorTests/RemixSplitLayoutTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): consolidate workspace controls"
```

### Task 5: Focused-child action strip, context menu, keyboard, and VoiceOver parity

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixFocusedChildActions.swift`
- Modify: `App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift:4-635`
- Modify: `App/TrueISFEditor/Remix/RemixChildCardView.swift:4-196`
- Modify: `App/TrueISFEditor/Remix/RemixWorkspaceView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditor/Remix/RemixWorkspaceState.swift:15-167`
- Create: `App/TrueISFEditorTests/RemixFocusedChildActionsTests.swift`
- Modify: `App/TrueISFEditorTests/RemixThumbnailTests.swift`
- Modify: `App/TrueISFEditorTests/RemixWorkspaceStateTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: focused run, optional Ready artifact, favorite, comparison, hero, parent, frozen, and recovery states.
- Produces: one action list routed identically from strip, context menu, key command, and VoiceOver custom action.

- [ ] **Step 1: Write failing availability and routing tests**

Define:

```swift
enum RemixFocusedChildAction: String, CaseIterable, Equatable {
    case favorite, compare, freeze, hero, promoteA, promoteB, open, retry
}

struct RemixFocusedChildActionPresentation: Equatable {
    let action: RemixFocusedChildAction
    let label: String
    let isEnabled: Bool
    let disabledReason: String?
    let requiresConfirmation: Bool
}

enum RemixFocusedChildModelMutation: Equatable {
    case favorite(String)
    case compare(String)
    case freeze(String)
    case hero(String)
    case retry(String)
}

enum RemixFocusedChildIntent: Equatable {
    case model(RemixFocusedChildModelMutation)
    case openArtifact(String)
    case confirmPromotion(slot: ParentSlot, artifactID: String)
}
```

Tests assert Open, Compare, Hero, Promote, and Freeze are disabled until Ready; retry is enabled only for Failed, Cancelled, or Interrupted; and Promote A and B require confirmation from every input path. `RemixFocusedChildIntentDispatcher.intent(for:item:)` is the single view-level router used by the strip, context menu, keyboard, and VoiceOver. Pure tests prove all four paths return the same typed intent.

- [ ] **Step 2: Run the focused-action tests and verify they fail**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace \
  -only-testing:TrueISFEditorTests/RemixFocusedChildActionsTests \
  -only-testing:TrueISFEditorTests/RemixThumbnailTests \
  -only-testing:TrueISFEditorTests/RemixWorkspaceStateTests
```

- [ ] **Step 3: Remove repeated normal actions from every card**

Cards show preview, identity, directive, stage, elapsed and liveness detail, plus inline failure recovery only when relevant. Remove the seven-button normal stack. Clicking or keyboard-focusing a card changes focus but never activates Open.

- [ ] **Step 4: Add the focused-child strip and complete alternate access**

The top strip shows the most frequent enabled actions and a More menu for the rest. The exact same array populates each card's context menu and VoiceOver custom actions. Every input calls one `RemixWorkspaceView` dispatcher: `.model` delegates to the model, `.openArtifact` invokes the existing `openInEditor` closure, and `.confirmPromotion` presents the one confirmation flow before delegating the accepted mutation to the model. Existing arrow movement, Favorite, Compare, Hero, Promote A, Promote B, and Escape commands remain; add Open and Freeze shortcuts only when they do not conflict with editor commands.

- [ ] **Step 5: Preserve focus through Ready and terminal transitions**

When a focused placeholder becomes Ready or Failed, keep its stable ID and focus. Announcing `Child N ready` must not move pointer, keyboard, or VoiceOver focus.

- [ ] **Step 6: Run tests and commit**

Run the Step 2 command. Expected: action availability and routing tests pass.

```bash
git add App/TrueISFEditor/Remix/RemixFocusedChildActions.swift \
  App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift \
  App/TrueISFEditor/Remix/RemixChildCardView.swift \
  App/TrueISFEditor/Remix/RemixWorkspaceView.swift \
  App/TrueISFEditor/Remix/RemixStudioModel.swift \
  App/TrueISFEditor/Remix/RemixWorkspaceState.swift \
  App/TrueISFEditorTests/RemixFocusedChildActionsTests.swift \
  App/TrueISFEditorTests/RemixThumbnailTests.swift \
  App/TrueISFEditorTests/RemixWorkspaceStateTests.swift App/project.yml App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): centralize focused child actions"
```

### Task 6: Immediate first-ready payoff, Reduce Motion, and native acceptance

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixReviewFixtureProvider.swift`
- Create: `App/TrueISFEditorTests/RemixReviewFixtureProviderTests.swift`
- Modify: `App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditor/Remix/RemixThumbnailView.swift`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/TrueISFEditorTests/RemixThumbnailTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: a Ready pipeline update while sibling runs remain nonterminal.
- Produces: an immediate moving preview in the existing stable slot and a paused explicit-Play fallback under Reduce Motion.

- [ ] **Step 1: Write failing first-payoff and Reduce Motion tests**

Assert the first artifact is eligible for animation while `model.isGenerating == true`, outranks both parent surfaces, leaves `workspace.canvasMode` unchanged, and leaves `focusedChildID` unchanged. Under Reduce Motion, no live reservation exists until `explicitlyPlayPreviews()`.

Add `RemixReviewFixtureProviderTests` proving the Debug-only fixture never starts `RealProcess` and offers three deterministic local scenarios:

- Progress: five stable children covering complete assistant plus empty successful result, confirmed-live quiet then success, Provider Failed, Response Incomplete, and one active provider that becomes Cancelled on Stop.
- Boundaries: five stable children covering Extraction Failed, Compile Failed, Preview Failed after pipeline compile success, a restored Interrupted run, and one Ready artifact.
- Identity: two independently compiled winners suitable for the binding unsaved-history sequence.

All successful candidates and the preview-failure candidate must pass through the real serialized native compiler. Tests prove every scenario emits exact stage, queue, elapsed, activity, byte, worker, queue-position, compiler-milestone, and scoped-action data without a percentage or ETA.

- [ ] **Step 2: Run focused payoff tests and verify they fail**

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace \
  -only-testing:TrueISFEditorTests/RemixReviewFixtureProviderTests \
  -only-testing:TrueISFEditorTests/RemixStudioModelTests \
  -only-testing:TrueISFEditorTests/RemixThumbnailTests
```

- [ ] **Step 3: Add temporary newly-Ready preview priority**

Store the most recently Ready child ID and insert it after hero and compared children but before focused child and parents in preview priority. Clear the temporary priority when another child becomes Ready, when the user explicitly focuses a Ready child, or when the batch ends.

- [ ] **Step 4: Render Ready in place and expose explicit Play under Reduce Motion**

The stable card switches from Compiling to Ready and mounts `RemixThumbnailView` immediately. Under Reduce Motion, show the real compiled frame paused with a labeled `Play Previews` button. Never substitute a generic spinner after Ready.

- [ ] **Step 5: Run focused and full app tests**

Run Step 2, then:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ./ddata-remix-workspace
```

Expected: focused and full app suites pass.

- [ ] **Step 6: Add a Debug-only local review fixture with no provider sessions**

`RemixReviewFixtureProvider` conforms to `AssistDetailedProvider`, emits typed lifecycle events on controlled delays, and returns the synthetic complete ISF fixtures described in Step 1. Compile it into Debug builds only with `#if DEBUG`. `TrueISFEditorApp` selects it only when `TRUEISF_REMIX_REVIEW_FIXTURE=canvas`; Release builds and ordinary Debug launches always use the real provider factory.

The fixture must not invoke Claude, Codex, shell, or `RealProcess`. Add a persistent in-window banner `Local review fixture, no provider sessions`, a Debug-only scenario picker for Progress, Boundaries, and Identity, and a visible `Live surfaces: N/4` diagnostic so captured evidence cannot be mistaken for a live generation benchmark or leave the preview budget inferred. These controls never compile into Release.

- [ ] **Step 7: Stage the app and perform Mechanic review**

Run `./scripts/run-latest.sh`. Verify app freshness from the build log and installed executable timestamp. Close the ordinary app, then launch the installed Debug executable with `TRUEISF_REMIX_REVIEW_FIXTURE=canvas` in its environment. In the Remix app window only, inspect normal maximization, Setup compactness and progressive disclosure, both moving parents, child-card density, first-ready motion, Workspace menu, focused-action decluttering, narrow layout, 14-point text, and the visible four-surface GPU count. Retain these observations for the exact packet in Step 8; an unrecorded inspection is not acceptance evidence.

- [ ] **Step 8: Perform Client Success and accessibility review**

Using app-window-scoped evidence only and the local fixture, capture this exact retained packet:

- A normal maximized window, not a full-screen Space; compact and progressively disclosed Setup; Workspace menu; focused-action decluttering; narrow layout; 14-point minimum text; and visible `Live surfaces: N/4` behavior never exceeding four.
- Synchronized moving Parent A and Parent B, immediate first Ready while siblings remain active, Reduce Motion paused until Play, and keyboard plus VoiceOver operation with stable focus.
- Aggregate stage and queue counts plus per-child elapsed time, last activity, received bytes, worker or queue position, with no percentage and no ETA.
- Quiet only while fixture process liveness is confirmed; Retrying with bounded provider detail; Provider Failed, Response Incomplete, Extraction Failed, Compile Failed, Preview Failed, Interrupted, Cancelled, and Ready, each with only its scoped actions.
- Stop preserving every already Ready child while all unresolved slots become terminal Cancelled.
- A Compiling to Ready transition whose retained compiler milestone proves the candidate passed the real serialized native Metal compiler before Ready. Preview Failed is shown only after that pipeline compile passed.
- The binding two-winner identity sequence: open both compiled winners before saving either; the first immediately shows `Unsaved - Save As required`; verify each starts with only its own `Imported` entry; pin `CHILD A ONLY` in the first and do not save it; verify the second never contains `CHILD A ONLY`; pin `CHILD B ONLY` in the second, Save As to a brand-new path, and verify its migrated history contains only `Imported`, `CHILD B ONLY`, and `v01`.

This review uses zero Claude or Codex sessions. If a reviewer requests any real provider run, stop first, disclose the exact session count and estimated shared-pool pressure, and obtain Conner's approval.

- [ ] **Step 9: Commit acceptance fixes if any**

Stage only Remix workspace files and tests, verify the cached file list, then commit:

```bash
git commit -m "test(remix): verify canvas-first workspace"
```

Do not push.
