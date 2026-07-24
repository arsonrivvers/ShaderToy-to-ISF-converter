# Accessible Remix Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retrofit TrueISFEditor's Remix Studio into a persistent, keyboard and VoiceOver operable three-zone workspace with adaptive comparison, scoped recovery, and a challenge-aware Shadertoy handoff.

**Architecture:** Add pure Codable workspace and session state around the existing Remix domain, then let `RemixStudioModel` own focus, comparison, retry, activity, layout, and restoration. Split the current monolithic view into Breeding Bay, Children Canvas, Lineage Inspector, and Activity Drawer views over the same model. Keep RemixPrompt, provider safety, concurrency, parsing, and genetic semantics unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, Combine, XCTest, XcodeGen, existing Metal preview engine.

## Global Constraints

- Preserve `RemixPrompt`, mutation semantics, provider concurrency, safety flags, and the existing response parser.
- Focused child, comparison membership, favorite state, and Parent A/B assignment are separate state.
- Grid is the default canvas mode; 2-up accepts at most two children; Hero accepts one.
- The Children Canvas never auto-collapses. On narrow windows collapse Lineage first, then Breeding Bay.
- Minimum rendered text size is 14 px equivalent.
- Primary actions use visible text. Color, glyph, animation, hover, and tooltips are never the only state channel.
- Full parent, generate, compare, promote, retry, lineage, and editor-open flow must be keyboard operable.
- VoiceOver focus is never forced onto each streaming child.
- Reduce Motion defaults child previews to frozen until explicitly played.
- Cloudflare verification is never synthesized, clicked through `AXPress`, or reported complete before the resolver confirms clearance.
- Persist only serializable session state. Never serialize Metal resources, provider processes, `CGImage`, or stale "running" state.
- Opening a winner must retain the confirmed unique untitled identity and version-history isolation.
- New testable app sources must be added to the explicit `TrueISFEditorTests` list in `App/project.yml`, followed by `cd App && xcodegen generate`.
- Every logic change follows RED, GREEN, refactor. Each task commits only its named files.
- Native builds use arm64 and an explicit derived data path.

---

### Task 1: Pure workspace interaction state

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixWorkspaceState.swift`
- Create: `App/TrueISFEditor/Remix/RemixSplitLayout.swift`
- Create: `App/TrueISFEditorTests/RemixWorkspaceStateTests.swift`
- Create: `App/TrueISFEditorTests/RemixSplitLayoutTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: child ids as `String`.
- Produces: `RemixCanvasMode`, `RemixZone`, `RemixWorkspaceState`, `RemixSplitLayout`, `RemixKeyboardCommand`, `focus(_:)`, `toggleComparison(_:)`, `showHero(_:)`, `showGrid()`, `showComparison()`, `collapse(_:)`, `expand(_:)`, `resize(_:to:)`, `enterFocusMode()`, `exitFocusMode()`, `applyNarrowLayout()`, `moveFocus(_:columns:childIDs:)`, and stable accessibility summaries.

- [ ] **Step 1: Add the new source to the test target and write failing interaction tests**

Create tests that pin:

```swift
func test_defaultState_isGridWithNoSelection() {
    let state = RemixWorkspaceState()
    XCTAssertEqual(state.canvasMode, .grid)
    XCTAssertNil(state.focusedChildID)
    XCTAssertEqual(state.comparedChildIDs, [])
}

func test_comparison_isStableOrderedAndCappedAtTwo() {
    var state = RemixWorkspaceState()
    state.toggleComparison("a")
    state.toggleComparison("b")
    state.toggleComparison("c")
    XCTAssertEqual(state.comparedChildIDs, ["b", "c"])
    XCTAssertEqual(state.canvasMode, .comparison)
}

func test_focusMode_restoresExactZoneState() {
    var state = RemixWorkspaceState()
    state.resize(.breedingBay, to: 312)
    state.collapse(.lineage)
    state.enterFocusMode()
    XCTAssertTrue(state.collapsedZones.contains(.breedingBay))
    state.exitFocusMode()
    XCTAssertEqual(state.zoneWidths[.breedingBay], 312)
    XCTAssertTrue(state.collapsedZones.contains(.lineage))
}

func test_narrowLayout_collapsesLineageThenBreedingBay_neverCanvas() {
    var state = RemixWorkspaceState()
    state.applyNarrowLayout(availableWidth: 850)
    XCTAssertTrue(state.collapsedZones.contains(.lineage))
    state.applyNarrowLayout(availableWidth: 620)
    XCTAssertTrue(state.collapsedZones.contains(.breedingBay))
}

func test_pointerDrag_recordsClampedWidth_andRestoredLayoutReappliesIt()
func test_keyboardResize_usesBoundedTwentyPointSteps()
func test_gridMovement_clampsWithoutLosingFocus()
func test_accessibilitySummary_namesStatusPositionDirectiveAndActions()
```

Add both new sources to `App/project.yml`, then run `cd App && xcodegen generate`.

- [ ] **Step 2: Run RED**

Run:

```bash
cd App
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:TrueISFEditorTests/RemixWorkspaceStateTests
```

Expected: compile failure because the workspace types do not exist.

- [ ] **Step 3: Implement the pure state**

Use these exact public shapes:

```swift
enum RemixCanvasMode: String, Codable, Equatable { case grid, comparison, hero }
enum RemixZone: String, Codable, Hashable, CaseIterable {
    case breedingBay, lineage, activity
}

enum RemixKeyboardCommand: Equatable {
    case moveLeft, moveRight, moveUp, moveDown
    case toggleComparison, favorite, hero, promoteA, promoteB
}

struct RemixWorkspaceState: Codable, Equatable {
    var canvasMode: RemixCanvasMode = .grid
    var focusedChildID: String?
    var comparedChildIDs: [String] = []
    var heroChildID: String?
    var collapsedZones: Set<RemixZone> = []
    var zoneWidths: [RemixZone: Double] = [.breedingBay: 280, .lineage: 300, .activity: 180]
    var previewsPaused = false
    private var preFocusCollapsed: Set<RemixZone>?
    private var preFocusWidths: [RemixZone: Double]?
}

struct RemixSplitLayout: Equatable {
    var state: RemixWorkspaceState
    mutating func recordPointerWidth(_ width: Double, zone: RemixZone)
    mutating func resizeByKeyboard(_ zone: RemixZone, direction: Int)
    func appliedWidth(for zone: RemixZone) -> Double
}
```

`toggleComparison` removes an existing id or appends a new one; when adding a third id, remove the oldest. A nonempty comparison set selects `.comparison`. `showHero` focuses the id and selects `.hero`. `showGrid` clears only mode, not favorites or parent assignments. Widths clamp to Breeding 240...420, Lineage 260...420, Activity 120...320. `RemixSplitLayout` is the only divider-width adapter used by the view: explicit frames apply persisted widths, a zero-distance `DragGesture` plus geometry records pointer changes, and keyboard resize uses 20 point increments. Do not rely on `HSplitView` to persist divider positions.

- [ ] **Step 4: Run GREEN and commit**

Run the focused tests, then:

```bash
git add App/project.yml App/TrueISFEditor/Remix/RemixWorkspaceState.swift \
  App/TrueISFEditor/Remix/RemixSplitLayout.swift \
  App/TrueISFEditorTests/RemixWorkspaceStateTests.swift \
  App/TrueISFEditorTests/RemixSplitLayoutTests.swift App/TrueISFEditor.xcodeproj
git commit -m "feat(remix): add accessible workspace state" \
  -m "Co-Authored-By: OpenAI Codex <noreply@openai.com>"
```

---

### Task 2: Serializable session domain and collision-free identity

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixSession.swift`
- Create: `App/TrueISFEditor/Remix/RemixActivity.swift`
- Create: `App/TrueISFEditorTests/RemixSessionTests.swift`
- Modify: `App/TrueISFEditor/Remix/RemixNode.swift`
- Modify: `App/TrueISFEditor/Remix/RemixLineage.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift` (only `ParentSlot` Codable conformance)
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: `RemixWorkspaceState`, `RemixNode`, `RemixLineage`, `RemixCrossoverSettings`.
- Produces: `RemixGenerationRequestSnapshot`, `RemixBatchRecord`, `RemixParentConfiguration`, `RemixActivityState`, and `RemixSession`.

- [ ] **Step 1: Write failing codec and identity tests**

Pin these behaviors:

```swift
func test_roundTrip_restoresLineageParentsFavoritesAndWorkspace() throws
func test_roundTrip_restoresCountersParentHistorySelectionSettingsActivityAndRequest() throws
func test_generationRequestSnapshot_preservesOriginalSettingsAfterControlsChange() throws
func test_normalizedAfterRestore_mapsGeneratingToInterruptedOnlyAtSessionBoundary()
func test_nextIDs_afterRestoreCannotCollideWithLineage()
```

- [ ] **Step 2: Run RED**

Run `RemixSessionTests`. Expected: missing session types.

- [ ] **Step 3: Implement the complete serializable domain**

Make `RemixMode`, `RemixNode`, `RemixNode.Status`, and `RemixLineage` Codable. Add a real `.interrupted` node status. Generic decoding preserves the encoded status; only `RemixSession.normalizedAfterRestore()` converts `.generating` to `.interrupted`. Use:

```swift
enum ParentSlot: String, Codable, Equatable { case a, b }

struct RemixGenerationRequestSnapshot: Codable, Equatable {
    let parentIDs: [String]
    let parentSources: [String]
    let mode: RemixMode
    let steer: String
    let directive: String
    let settings: RemixCrossoverSettings
}

struct RemixBatchRecord: Codable, Equatable {
    let round: Int
    var nodes: [RemixNode]
    let requestsByNodeID: [String: RemixGenerationRequestSnapshot]
}

struct RemixParentConfiguration: Codable, Equatable {
    let parentAID: String?
    let parentBID: String?
}

enum RemixParentSourceSnapshot: Codable, Equatable {
    case pastedISF(String)
    case libraryPath(String)
    case shadertoyLink(String)
    case currentEditorSource(String)
}

enum RemixParentRequestPhase: String, Codable, Equatable {
    case fetching, verificationRequired, waitingForHuman, resuming, converting
}

struct RemixParentRequestSnapshot: Codable, Equatable {
    let id: UUID
    let slot: ParentSlot
    let source: RemixParentSourceSnapshot
    let displayInput: String
    let phase: RemixParentRequestPhase
}

enum RemixActivityState: Codable, Equatable {
    case idle
    case generating(total: Int, completed: Int, lastEventAt: Date?)
    case quiet(total: Int, completed: Int, lastEventAt: Date?)
    case verificationRequired(slot: ParentSlot, requestID: UUID)
    case resuming(slot: ParentSlot, requestID: UUID)
    case childFailed(id: String, message: String)
    case partialFailure(total: Int, failed: Int)
    case interrupted
    case completed(failed: Int)
    case cancelled
}

struct RemixSession: Codable, Equatable {
    var schemaVersion = 1
    var round: Int
    var seedCounter: Int
    var parentAID: String?
    var parentBID: String?
    var parentHistory: [RemixParentConfiguration]
    var mode: RemixMode
    var steer: String
    var batchSize: Int
    var currentBatch: [RemixNode]
    var batchHistory: [RemixBatchRecord]
    var lineage: RemixLineage
    var workspace: RemixWorkspaceState
    var selectedLineageNodeID: String?
    var crossoverSettings: RemixCrossoverSettings
    var activity: RemixActivityState
    var pendingParentRequest: RemixParentRequestSnapshot?
    var transcript: [String]
}
```

`normalizedAfterRestore()` derives `round` and `seedCounter` upward from every existing id as a defense in depth even when stored counters are stale. It never maps `.interrupted` to `.failed`.

- [ ] **Step 4: Run GREEN and commit**

Define the canonical `RemixActivityState` in `RemixActivity.swift`; later tasks add derivation methods but never redeclare or migrate it. Run `RemixSessionTests`, then commit the domain, activity type, tests, project file, and regenerated project.

---

### Task 3: Atomic session storage and corruption quarantine

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixSessionStore.swift`
- Create: `App/TrueISFEditorTests/RemixSessionStoreTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: `RemixSession`.
- Produces: `RemixSessionStore.load()`, `save(_:)`, and `RemixSessionRecovery`.

- [ ] **Step 1: Write failing storage tests**

```swift
func test_firstSave_atomicallyMovesTemporaryFileIntoPlace() throws
func test_overwrite_atomicallyReplacesExistingFile() throws
func test_load_corruptPayload_quarantinesAndReturnsRecoveryNotice() throws
func test_store_boundsBatchHistoryAndTranscript() throws
```

The corruption test verifies the payload is moved to a timestamped `.corrupt` sibling, never deleted.

- [ ] **Step 2: Run RED**

Run `RemixSessionStoreTests`. Expected: missing store.

- [ ] **Step 3: Implement first-save and overwrite algorithms**

Encode to a sibling temporary file. If the destination does not exist, use `FileManager.moveItem(at:to:)`. If it exists, use `replaceItemAt`. Bound history to 20 batches and transcript to 2,000 lines before encoding. `load()` returns the normalized session or a recovery notice.

- [ ] **Step 4: Run GREEN and commit**

Run focused tests, then commit the store, tests, project file, and regenerated project.

---

### Task 4: Model restoration and autosave integration

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces: `restoreSession()`, `persistSession()`, `startNewSession()`, collision-free id generation, restored parent undo, selected lineage, activity, pending request, and settings.

- [ ] **Step 1: Write failing model restoration tests**

```swift
func test_restoreSession_restoresEverySpecifiedSurface()
func test_restoreThenGenerate_usesCollisionFreeRoundAndSeedIDs()
func test_restorePreservesUndoParentHistory()
func test_restorePendingShadertoyRequest_preservesUUIDSlotSourceAndTypedPhase()
func test_startNewSession_clearsSessionButKeepsUserDefaultsProviderChoice()
func test_modelPersistsAfterEveryNamedMutation()
```

- [ ] **Step 2: Run RED**

Run the named model tests. Expected: missing integration.

- [ ] **Step 3: Integrate storage without serializing runtime resources**

Inject `sessionStore` with a production default. Publish workspace, batch history, recovery notice, structured activity, and pending parent request. Restore in `init`. A restored Shadertoy request reconstructs the same UUID, slot, URL or ID, and typed phase, but waits for explicit Continue Verification before re-entering WebKit. Persist after parent, favorite, selection, layout, batch, compile, retry, stop, and undo transitions. Never persist snapshots, `CGImage`, provider instances, `generationTask`, or a live running claim.

- [ ] **Step 4: Run GREEN and commit**

Run `RemixStudioModelTests`, then commit only model and tests.

---

### Task 5: Explicit parent targeting and challenge-aware resolver state

**Files:**
- Modify: `App/TrueISFEditor/WebKitShaderFetcher.swift`
- Modify: `App/TrueISFEditor/Remix/RemixParentResolver.swift`
- Create: `App/TrueISFEditor/Remix/RemixParentLoadState.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Create: `App/TrueISFEditorTests/RemixParentLoadStateTests.swift`
- Modify: `App/TrueISFEditorTests/RemixParentResolverTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Produces: `RemixParentLoadState`, `RemixParentRequest`, `loadParent(_:from:)`, `cancelParentLoad()`, and `WebKitShaderFetcher.State`.
- Preserves: `RemixParentResolver.resolve(_:)`.

- [ ] **Step 1: Write failing state-machine tests**

Cover:

```swift
func test_request_retainsTargetAndInputAcrossVerification()
func test_confirmedClearance_resumesExactlyOnce()
func test_staleCompletionToken_isIgnored()
func test_cancel_preservesInputAndTargetForRetry()
func test_furtherVerification_returnsWaitingStateNotSuccess()
func test_success_returnsFocusTargetForOriginatingParentControl()
func test_snapshotRoundTrip_reconstructsLiveShadertoyRequestWithSameIdentity()
```

- [ ] **Step 2: Run RED**

Expected: missing request/state APIs.

- [ ] **Step 3: Implement deterministic request state**

Use:

```swift
struct RemixParentRequest: Equatable, Identifiable {
    let id: UUID
    let slot: ParentSlot
    let spec: ParentSpec
    let displayInput: String
}

enum RemixParentLoadState: Equatable {
    case idle
    case fetching(RemixParentRequest)
    case verificationRequired(RemixParentRequest)
    case waitingForHuman(RemixParentRequest)
    case resuming(RemixParentRequest)
    case converting(RemixParentRequest)
    case succeeded(slot: ParentSlot, requestID: UUID)
    case failed(RemixParentRequest, message: String)
    case cancelled(RemixParentRequest)
}
```

`WebKitShaderFetcher` publishes or callbacks `.loading`, `.verificationRequired`, `.cleared`, and `.failed`; it never clicks the page. Readiness must remain positive host plus nonchallenge title. `RemixParentRequest` converts to and from the typed snapshot; restored Shadertoy requests preserve UUID, slot, URL or ID, display input, and phase. The model serializes interactive verification requests, ignores completions whose UUID is not current, retains display input on failure, and returns an accessibility focus token for the originating slot control.

- [ ] **Step 4: Run GREEN and commit**

Run `RemixParentLoadStateTests|RemixParentResolverTests|LiveFetchIntegrationTests` (live tests remain skipped without `RUN_LIVE=1`), then commit named files.

---

### Task 6: Generation-request fidelity and scoped retry

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixGenerator.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditorTests/RemixGeneratorTests.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`

**Interfaces:**
- Consumes: immutable `RemixGenerationRequestSnapshot` values from Task 2.
- Produces: `retryChild(id:steerOverride:)`, `retryFailed()`, and `retryInterruptedBatch()`.

- [ ] **Step 1: Write failing retry-fidelity tests**

Pin that retry-one replaces only the selected failed slot, preserves successful siblings, and uses the stored original parent sources, mode, crossover settings, directive, and steer after every current control has been changed. Pin retry-all touches only failed/interrupted nodes. Pin restored interrupted batches retain their request snapshots.

- [ ] **Step 2: Run RED**

Expected: missing retry and activity APIs.

- [ ] **Step 3: Add single-slot generator entry point and model retry**

Extract a generator method that accepts one fixed node id plus `RemixGenerationRequestSnapshot` and uses the same prompt and safety path as batch generation. Do not duplicate prompt assembly. A retry may apply an explicit steer override by copying the stored snapshot and replacing only `steer`.

- [ ] **Step 4: Run GREEN and commit**

Run focused generator and model tests, then commit named files.

---

### Task 7: Structured activity derivation, compile salvage, and preview retry

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixActivity.swift`
- Create: `App/TrueISFEditorTests/RemixActivityTests.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Extends the Task 2 canonical `RemixActivityState` with `RemixActivitySummary`, `compileSalvageActions(for:)`, `retryPreview(id:)`, and stable accessibility announcement strings.

- [ ] **Step 1: Write failing activity and salvage tests**

Pin compact status and announcements for generating, quiet, partial failure, cancelled, verification required, resuming, interrupted, and idle. Pin compile failures retain source plus diagnostic and expose View Compile Summary, Open Source in Editor to Fix, Copy Diagnostic, and Retry This Child. Pin preview failure exposes Retry Preview and Open in Editor, does not call the provider, and never changes generation status.

- [ ] **Step 2: Run RED**

Run `RemixActivityTests` and named model tests. Expected: missing activity APIs.

- [ ] **Step 3: Implement structured activity**

Use a Codable enum with associated batch counts, child id, timestamps, and human-readable message. Derive summaries and accessibility announcements as pure strings. Keep transcript humanized but separate. Preview failures live in `previewFailuresByNodeID: [String: String]`.

- [ ] **Step 4: Run GREEN and commit**

Run focused tests, then commit activity, model, tests, project file, and regenerated project.

---

### Task 8: Three-zone shell and accessible Breeding Bay

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixWorkspaceView.swift`
- Create: `App/TrueISFEditor/Remix/RemixBreedingBayView.swift`
- Create: `App/TrueISFEditor/Remix/RemixBreedingBayPresentation.swift`
- Create: `App/TrueISFEditorTests/RemixBreedingBayPresentationTests.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixCrossoverPopover.swift`
- Modify: `App/TrueISFEditor/TrueISFEditorApp.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: Tasks 1 to 7 model APIs.
- Produces: resizable/collapsible three-zone shell, focus mode, explicit parent actions, visible disabled reasons, keyboard resize controls, and verification status.

- [ ] **Step 1: Write failing presentation and focus-routing tests**

Pin the exact empty-state goal, mode-dependent shortest path, explicit slot-target labels, Generate disabled reasons and resolving action, parent-load state copy, collapse/reopen focus tokens, resize value descriptions, Reset Layout result, and crossover popover focus return.

- [ ] **Step 2: Run RED and implement pure presentation**

Create `RemixBreedingBayPresentation` pure derivations and focus tokens, run GREEN, then wire views.

- [ ] **Step 3: Replace the monolithic layout with focused view units**

`RemixStudioView` becomes a composition root. `RemixWorkspaceView` uses an `HStack` with explicit frames from `RemixSplitLayout` and custom keyboard/pointer dividers. It exposes visible buttons: `Collapse Breeding Bay`, `Collapse Lineage`, `Focus Canvas`, `Reset Layout`, and per-zone resize menus with bounded increments. Pointer drag updates the same persisted width binding tested in Task 1.

- [ ] **Step 4: Build the Breeding Bay**

Lead an empty session with `Choose a starting shader`. Each slot owns visible `Add Parent A/B` or `Replace Parent A/B` menus for Library, Current Editor, Paste, and Shadertoy. Do not clear URL/paste input on failure. Generate's disabled help is also visible text naming the missing parent. Crossover sliders expose percent plus semantic value descriptions and restore focus when the popover closes.

- [ ] **Step 5: Add semantic accessibility**

Add named landmarks, headings, sort priorities, help, and labels. Use 14 pt or larger text. Ensure every icon button also has visible text in its normal presentation. Respect Reduce Transparency in zone backgrounds.

- [ ] **Step 6: Build and commit**

Run:

```bash
cd App
xcodegen generate
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `** BUILD SUCCEEDED **`. Add `RemixBreedingBayPresentation.swift` to the explicit test-source list, regenerate Xcode, and commit named view files, `project.yml`, and regenerated project.

---

### Task 9: Adaptive Children Canvas and preview budget

**Files:**
- Create: `App/TrueISFEditor/Remix/RemixChildrenCanvasView.swift`
- Create: `App/TrueISFEditor/Remix/RemixChildCardView.swift`
- Create: `App/TrueISFEditor/Remix/RemixComparisonCoordinator.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Modify: `App/TrueISFEditor/Remix/RemixThumbnailView.swift`
- Create: `App/TrueISFEditorTests/RemixComparisonCoordinatorTests.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: `RemixWorkspaceState`.
- Produces: Grid, synchronized 2-up, Hero, global pause, per-child freeze, focus restoration, accessible keyboard commands, and `RemixComparisonCoordinator`.

- [ ] **Step 1: Add failing preview-budget and selection tests**

Pin that compared and Hero ids get priority within `maxLivePreviews`; favorites do not exceed the cap; failed or explicitly frozen children never animate; global pause freezes all; Reduce Motion initial state is paused. Pin focus and comparison remain separate across mode changes. Pin keyboard command routing and focus restoration using Task 1's pure router.

Add coordinator tests:

```swift
func test_twoUp_usesOneSharedClockAndResolution()
func test_compatibleInputs_propagateToBothPreviews()
func test_incompatibleInputs_areReportedAndRemainPerChild()
func test_pauseAndReset_applyAtomicallyToBothPreviews()
```

- [ ] **Step 2: Run RED, implement model priority, run GREEN**

Replace the current favorite-over-cap behavior with a strict budget:

```swift
func livePreviewIDs(reduceMotion: Bool) -> Set<String>
```

Priority is Hero, compared ids, focused id, then newest compiled favorites, then newest compiled children, always truncated to `maxLivePreviews`. Return empty when globally paused or Reduce Motion is active before explicit play.

- [ ] **Step 3: Implement synchronized comparison state**

`RemixComparisonCoordinator` owns one `RenderClock`, a shared render size, global pause/reset, and a dictionary of compatible parameter values. Compatibility requires the same input name and ISF type in both parsed headers; incompatible inputs remain per-child and produce visible explanatory text.

- [ ] **Step 4: Implement the adaptive canvas**

Grid is default. A segmented control provides Grid, Compare 2, and Hero. Cards expose visible Favorite, Compare, Hero, Promote A, Promote B, Open, and failure salvage actions. 2-up uses equal frames and a shared pause/time reset control. Arrow keys move grid focus, Return enters Hero, Space toggles comparison, F favorites, and explicit labeled commands promote.

- [ ] **Step 5: Build and commit**

Add `RemixComparisonCoordinator.swift` to the explicit test-source list, regenerate Xcode, run focused model and comparison coordinator tests plus native arm64 build, then commit named files, `project.yml`, and regenerated project.

---

### Task 10: Accessible Lineage Inspector and Activity Drawer

**Files:**
- Modify: `App/TrueISFEditor/Remix/RemixLineageTreeView.swift`
- Create: `App/TrueISFEditor/Remix/RemixActivityDrawerView.swift`
- Create: `App/TrueISFEditor/Remix/RemixLineagePresentation.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioView.swift`
- Modify: `App/TrueISFEditor/Remix/RemixStudioModel.swift`
- Create: `App/TrueISFEditorTests/RemixLineagePresentationTests.swift`
- Modify: `App/TrueISFEditorTests/RemixStudioModelTests.swift`
- Modify: `App/project.yml`

**Interfaces:**
- Consumes: lineage, activity, retry, diagnostic, and workspace APIs.
- Produces: accessible tree rows, Undo Parent Change, compact status, Activity Drawer, retry-all, copy diagnostic, and focus-safe announcements.

- [ ] **Step 1: Add failing parent-history and presentation tests**

Replace `stepBack()` tests with `canUndoParentChange`, `undoParentChange()`, and `undoParentChangeReason`. Pin that undo changes parent ids only and never deletes lineage, favorites, batches, activity, or snapshots.

Pin pure accessibility summaries for root, nested, crossover-secondary-parent, favorite, failed, selected, and collapsed rows. Pin Activity Drawer action lists for every activity/failure state and compact status when collapsed.

- [ ] **Step 2: Run RED, implement parent history and presentation derivations, run GREEN**

Retain history semantics but expose accurate names and disabled reasons. `RemixLineagePresentation` is the only source of row labels, values, help, and available-action names.

- [ ] **Step 3: Upgrade the inspector and activity surface**

Tree rows announce label, depth, favorite state, primary parent, secondary parent, compile status, and available actions. Replace glyph-only relationships with accessible text. Activity compact status remains visible when collapsed. Drawer provides Stop, Retry All Failed, Copy Activity, per-child View Compile Summary, Copy Diagnostic, Open Source in Editor to Fix, and Retry This Child.

- [ ] **Step 4: Build and commit**

Add `RemixLineagePresentation.swift` to the explicit test-source list, regenerate Xcode, run `RemixTreeBuilderTests|RemixStudioModelTests|RemixLineagePresentationTests`, native arm64 build, then commit named files, `project.yml`, and regenerated project.

---

### Task 11: Full verification, native staging, and acceptance package

**Files:**
- Modify only if review finds a defect in Tasks 1 to 10.
- Update: `docs/ROADMAP.md` only with the landed accessible Remix Studio entry.

**Interfaces:**
- Consumes: complete feature.
- Produces: test, build, security, accessibility, and on-device evidence.

- [ ] **Step 1: Run full tests**

```bash
cd App
xcodegen generate
xcodebuild test -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -derivedDataPath ./ddata-review -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
cd ../ShadertoyISFKit
swift test
```

Expected: every app and kit test passes, with live network tests skipped unless explicitly enabled.

- [ ] **Step 2: Run release-shaped arm64 build**

```bash
cd App
xcodebuild -project TrueISFEditor.xcodeproj -scheme TrueISFEditor \
  -derivedDataPath ./ddata -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify the staged binary is fresh**

Choose a unique visible string longer than 15 characters from the new workspace and run:

```bash
strings App/ddata/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor.debug.dylib \
  | rg -F "Choose a starting shader"
```

Expected: one or more hits. If absent, the binary is stale and must not be launched.

- [ ] **Step 4: Manual native Mechanic review**

Audit every changed SwiftUI file for nil safety, stable `ForEach` identity, focus loops, unreachable actions, minimum text size, layout compression, animation misuse, and runtime state inconsistencies. Fix findings with covering tests.

- [ ] **Step 5: CSO defensive review**

Review the Shadertoy input path and provider boundary. Required verdict: SHIP. No synthetic verification, new tool capability, private-data leg, or exfiltration path may exist.

- [ ] **Step 6: Client Success accessibility review**

Capture exact app-window states for empty session, populated parents, Grid, 2-up, Hero, generation, partial failure, compile failure, preview failure, collapsed zones, narrow window, restored session, and verification required. Review keyboard traversal, visible focus, VoiceOver labels/announcements, Reduce Motion, contrast, hit targets, and next-action clarity.

- [ ] **Step 7: On-device pre-flight and launch**

Before asking Conner to test, confirm the staged binary path, process absence or identity, and app version. Launch the fresh staged app once.

- [ ] **Step 8: Ordinary-interaction acceptance**

Verify:

1. Restore or start a session.
2. Add explicit Parent A and B.
3. Generate five children and stop a live batch.
4. Use Grid, synchronized 2-up, and Hero.
5. Favorite, promote A/B, retry one failed child, retry all failed, and open a winner.
6. Collapse, resize, focus, reset, narrow, and restore zones without a pointer.
7. Relaunch and restore the same session.
8. Trigger Shadertoy verification through ordinary interaction, complete any requested human step, and confirm exact-slot resume.
9. Confirm no ordinary mouse, keyboard, or VoiceOver crash.

- [ ] **Step 9: Close ROADMAP and commit**

Add one landed entry without changing unrelated roadmap items. Run `git diff --check`, confirm a clean scoped status after commit, and use:

```bash
git commit -m "feat(remix): ship accessible studio workspace" \
  -m "Co-Authored-By: OpenAI Codex <noreply@openai.com>"
```

---

## Plan Completion Gate

1. Eleven task commits exist after the final plan commit.
2. Every new logic path captured RED before GREEN.
3. Full app and kit suites pass.
4. Explicit arm64 build succeeds and the staged binary contains a unique new string.
5. Manual Mechanic review passes.
6. Client Success accessibility review has no fix-first findings.
7. CSO verdict is SHIP.
8. No Cloudflare click automation or AXPress exists.
9. On-device status remains STAGED until Conner confirms the ordinary-interaction checklist.
10. Run the `gate` skill before push or completion claims.
