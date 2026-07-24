---
schema_version: 1
topic: accessible-remix-studio
date: 2026-07-24
tier: just-me
status: complete
correlation_id: trueisf-remix-studio-accessibility-20260724
---

# Accessible Remix Studio Upgrade

## 1. What we're building

Retrofit TrueISFEditor's existing Remix Studio into a fully accessible professional workspace for breeding, comparing, selecting, recovering, and continuing ISF shader lineages. Preserve the proven genetic generation loop and replace the current information architecture with a resilient three-zone studio.

## 2. User-visible output + trigger

- **Output the user sees:** A persistent Remix Studio with an explicit Breeding Bay, adaptive Children Canvas, Lineage Inspector, and Activity Drawer. The end artifact is a compiled child the user has compared, selected, and opened in the main editor with its identity and version history intact.
- **What triggers it:** The user opens Remix Studio, restores the last session or starts a new one, chooses one or two parents, configures the remix, and explicitly selects Generate. Shadertoy verification may temporarily hand control to a visible browser challenge, then resumes the same parent import automatically.

## 3. Cousin pattern

**Retrofit:** `App/TrueISFEditor/Remix/` and the approved prior designs:

- `docs/superpowers/specs/2026-06-11-isf-remix-studio-design.md`
- `docs/superpowers/specs/2026-06-12-remix-lineage-tree-design.md`
- `docs/superpowers/specs/2026-06-13-remix-crossover-controls-design.md`

The existing domain model, generator, preview, crossover controls, lineage graph, snapshot swatches, and editor handoff remain the foundation. This spec changes interaction state, layout, accessibility, durability, and recovery. It does not replace generation behavior.

## 4. Tier + why

**Tier:** just-me

This is Conner's local professional shader-making tool. It must optimize for rapid expert iteration while remaining fully operable with keyboard navigation, VoiceOver, reduced motion, and non-pointer resizing. No multi-user tenancy, account system, or client-facing onboarding is required.

## 5. Surfaces

- **Native SwiftUI workspace:** The three-zone Remix Studio shell, adaptive comparison canvas, inspector, controls, and status surfaces.
- **State model:** Distinct focus, comparison, favorite, parent, generation, retry, layout, and session-restoration state.
- **Metal previews:** Synchronized live previews with a strict animation budget and frozen snapshots outside the budget.
- **Local persistence:** Autosaved session and layout state with bounded lineage, batches, activity, and recovery metadata.
- **Existing Claude/Codex providers:** The current subscription-backed generation path remains unchanged behind improved status and retry controls.
- **Shadertoy WKWebView resolver:** Challenge-aware source resolution with one accessible human verification handoff when Cloudflare requires it.
- **Accessibility:** VoiceOver landmarks and announcements, keyboard commands, visible focus, semantic labels, reduced-motion behavior, and non-color state communication.
- **Main editor bridge:** Opening a winner preserves the stable untitled identity and immediate Save As/version-history behavior already confirmed on-device.

## 6. v1 vs v2

**v1 (ships now):**

- Three resizable zones: Breeding Bay, Children Canvas, and Lineage Inspector.
- Adaptive Children Canvas with Grid default, synchronized 2-up, and Hero modes.
- Explicit and separate focused, compared, favorite, and Parent A/B states.
- Collapsible Activity Drawer with persistent compact progress and failure status.
- Explicit parent-source actions and direct A/B targeting.
- Challenge-aware Shadertoy verification handoff with automatic continuation.
- Per-child and batch-level retry for generation or compile failures.
- Local session autosave, crash recovery, and relaunch restoration.
- Full keyboard, VoiceOver, Reduce Motion, contrast, hit-target, and visible-focus contracts.
- Preview-budget enforcement, global pause, and synchronized comparison time and inputs.
- Responsive collapse rules and exact split-position restoration.

**v2 (deferred):**

- Freeform node-link or pan-and-zoom lineage canvas.
- Cross-device sync, accounts, collaboration, shared sessions, or cloud storage.
- Session export/import bundles.
- Automatic LLM repair of compile-failed children.
- More than two simultaneous comparison panes.
- Automated Shadertoy security verification.

## 7. Stage-by-stage

### Stage 1: Open or restore the studio

- **Input:** The Remix Studio command or app relaunch with a saved session.
- **Logic:** Load bounded local session state. Restore layout, parents, lineage, favorites, current batch, comparison mode, selection, crossover settings, and Activity Drawer state. If recovery data is corrupt, quarantine it and open a new session with a visible recovery notice.
- **Output:** The three-zone workspace appears in its last usable state, or a clean workspace appears with an explanation.
- **Constraint:** Never silently discard a recoverable lineage. "Start New Session" requires confirmation when the current session contains parents, generated children, favorites, or in-flight recovery state.

### Stage 2: Configure the Breeding Bay

- **Input:** Parent A/B sources, remix mode, steer text, batch size, balance, variation, trait routing, and directive pool.
- **Logic:** A new empty session leads with the maker goal "Choose a starting shader," presents Add to Parent A from Library, Current Editor, Paste, or Shadertoy in the normal tab order, and shows the shortest valid path for the selected mode. Parent slots use explicit Add or Replace actions for Library, Current Editor, Pasted ISF, and Shadertoy. Every source action names its target slot before it begins. Entered URLs and pasted content remain present after failure. When Generate is unavailable, its visible disabled reason names the exact missing or invalid input and the control or action that resolves it.
- **Output:** One valid parent for Mutate or two valid parents for Crossover, with labeled previews and a clear Generate readiness state.
- **Constraint:** No implicit "first empty else A" targeting. Iconography never substitutes for visible text or accessible names.

### Stage 3: Resolve a Shadertoy parent

- **Input:** A Shadertoy URL or ID targeted to Parent A or B.
- **Logic:** Drive the existing visible `WKWebView` through explicit states: fetching, verification required, waiting for human, resuming, fetched, converting, success, failure, or cancelled. When Cloudflare requires interaction, bring the challenge window forward once, fully expose the widget, announce the required action, and provide a keyboard-reachable Continue Verification affordance. Detect clearance and resume the exact pending import once. After clearance, return keyboard and VoiceOver focus to the originating Parent A/B source control, announce whether import resumed or needs further verification, and never report verification complete before the resolver confirms clearance.
- **Output:** The resolved and converted shader fills the originally chosen parent slot, or the Breeding Bay retains the request and shows a scoped fallback.
- **Constraint:** Never synthesize a click, invoke `AXPress`, promise a clearance duration, duplicate an import after racing completion signals, or lose the target slot. Offer API-key and pasted-code fallbacks.

### Stage 4: Generate a batch

- **Input:** Valid parents, mode, settings, steer text, and explicit Generate action.
- **Logic:** Reuse the current generator, concurrency cap, safety flags, prompt composition, and provider cancellation. Populate stable child placeholders immediately. Announce batch start once, update a compact progress summary, and stream humanized activity into the drawer without moving keyboard or VoiceOver focus for each child.
- **Output:** Compiled, failed, or cancelled child cards appear in stable positions.
- **Constraint:** Generation never starts automatically. Stop cancels all unlaunched and in-flight work. The compact status remains visible when the Activity Drawer is collapsed.

### Stage 5: Scan the Grid

- **Input:** A current batch of child cards.
- **Logic:** Grid is the default canvas mode. Arrow keys move focus spatially; Return enters Hero; Space toggles membership in the comparison set; F toggles favorite; A or B promotes after an explicit accessible confirmation of the target. Each card announces name, position, compile state, directive, favorite state, parent relationship, preview state, and available actions.
- **Output:** The user can scan the complete batch while maintaining one focused child and up to two compared children.
- **Constraint:** Focus, comparison, favorite, and promotion are separate state variables and visual treatments. No state depends on color, animation, glyph, hover, or tooltip alone.

### Stage 6: Compare or inspect

- **Input:** One focused child or two compared children.
- **Logic:** Hero shows one large preview. 2-up shows two equal previews with synchronized render time, resolution, pause state, and compatible input values. A global pause freezes all previews; per-card controls can freeze individual candidates. Exiting Hero or 2-up returns focus to the originating card.
- **Output:** The user can judge fine detail in Hero or deliberate differences in synchronized 2-up.
- **Constraint:** The preview budget remains bounded. Favorites do not create unbounded live engines. Reduce Motion defaults previews to paused snapshots until explicitly played.

### Stage 7: Select, retry, and continue lineage

- **Input:** A compiled child, a failed child, or a set of failed children.
- **Logic:** Compiled children support Favorite, Promote to A, Promote to B, Compare, Hero, and Open in Editor. A compile-failed child exposes View Compile Summary, Open Source in Editor to Fix, Retry This Child, and Copy Diagnostic. Retry clearly states that it regenerates the child and may produce different code. A preview-render failure exposes Retry Preview and Open in Editor in addition to a static fallback. The Activity Drawer supports Retry All Failed. Retry preserves parents, mode, crossover settings, directive, and steer unless the user explicitly edits the steer for the retry. Failed nodes remain inspectable in batch history but do not enter the compiled lineage tree.
- **Output:** A winner becomes a parent for the next round, opens in the editor, or a failed slot is regenerated without rerunning successful siblings.
- **Constraint:** Opening a winner uses the existing stable document identity handoff. No disk write occurs until the user saves in the editor.

### Stage 8: Navigate lineage and history

- **Input:** Compiled lineage, favorites, session batches, and a selected node.
- **Logic:** The Lineage Inspector retains the flattened stable tree, collapse state, crossover secondary-parent relationship, snapshot swatches, favorite filter, and selected-node action area. Replace ambiguous Step Back with Undo Parent Change and an adjacent history explanation. Disable it with a visible reason when no prior parent configuration exists.
- **Output:** The user can understand ancestry, select a prior node, restore prior parent configuration, and continue breeding.
- **Constraint:** Undo changes parent configuration only. It never deletes nodes, batches, favorites, activity, or snapshots.

### Stage 9: Adapt and recover the workspace

- **Input:** Window resizing, focus-mode toggle, app termination, provider crash, or renderer failure.
- **Logic:** Persist split positions and collapse state. On narrow windows collapse Lineage first, then Breeding Bay; the Children Canvas never disappears. Focus mode collapses both side zones and restores the exact prior configuration on exit. Each zone exposes keyboard-reachable Collapse, Expand, and Resize controls with current size or value, bounded increments, and Reset Layout. Resizing never traps focus or moves the focused control offscreen. After responsive auto-collapse, focus moves to the surviving zone's reopen control and VoiceOver announces what changed. Session autosave uses bounded, atomic replacement and does not serialize live Metal resources or provider processes.
- **Output:** The workspace remains usable at supported sizes and returns to the same conceptual state after interruption.
- **Constraint:** A resumed in-flight generation becomes interrupted, never falsely running. Offer Retry Interrupted Batch with the original inputs.

## 8. Worked example end-to-end

Conner opens Remix Studio and the last session restores with its lineage, favorites, split positions, and Grid mode. They start a new session, add a library shader to Parent A, then target Parent B and paste a Shadertoy URL. Shadertoy presents Cloudflare verification. The studio announces "Verification required for Parent B," brings forward a window with the checkbox fully visible, and waits. Conner activates it once. The app detects clearance, resumes the pending fetch, converts the shader, and fills Parent B without losing the URL or slot.

Conner sets Crossover, adjusts variation and Structure routing, enters a steer instruction, and generates five children. Stable cards appear immediately. The compact status says "5 generating"; the Activity Drawer shows humanized progress. Children stream into their existing positions without stealing focus.

Conner scans the Grid with arrow keys, marks Children 2 and 5 for comparison, and enters synchronized 2-up. Both previews share time, resolution, and compatible inputs. Child 5 has better motion, so Conner favorites it, promotes it to Parent A, and returns to Grid. One child failed compilation; Conner chooses Retry This Child without regenerating the other four.

Conner opens Child 5 in the main editor. It arrives as a uniquely identified untitled document with "Unsaved: Save As required" and its own Imported version entry. Later, Remix Studio restores the same session and lineage after relaunch.

## 9. Tone constraints

- Use concise maker-facing language, not onboarding copy or corporate gloss.
- Use direct states: "Generating 3 of 5," "Verification required," "Compile failed," "Paused," "Session restored."
- Never use "something went wrong" when the failing boundary is known.
- Never imply that Cloudflare verification can be automated.
- Never expose raw stream JSON or internal process jargon.
- Use visible text labels for primary actions. Symbols may reinforce meaning but never carry it alone.
- Minimum rendered text size is 14 px equivalent. Secondary text must remain readable and meet contrast requirements.

## 10. Success criteria

- [ ] The complete parent, generate, compare, promote, lineage, retry, and open-in-editor loop is usable without a pointer.
- [ ] VoiceOver exposes stable landmarks for Breeding Bay, Children Canvas, Lineage Inspector, and Activity, with useful card and node summaries.
- [ ] Grid, synchronized 2-up, and Hero modes preserve distinct focus, comparison, favorite, and parent state.
- [ ] When Shadertoy reports legitimate clearance, the app consumes that clearance once, resumes the exact pending import without another app-imposed confirmation, and ignores duplicate or stale completion signals. If Cloudflare requests further interaction, the app states that plainly and preserves the request and target slot.
- [ ] Generation, cancellation, quiet periods, partial failure, compile failure, verification, and retry never look hung.
- [ ] Session relaunch restores parents, lineage, favorites, batch history, settings, layout, and selection; interrupted work is labeled interrupted.
- [ ] Narrow-window collapse and focus mode always preserve the Children Canvas and restore exact prior split positions.
- [ ] All zone collapse, expansion, resizing, canvas-mode changes, Activity Drawer actions, and focus-mode entry and exit are discoverable and operable without drag, hover, or memorized shortcuts.
- [ ] Reduce Motion, Reduce Transparency, visible focus, contrast, text alternatives, and non-pointer resize controls pass manual accessibility review.
- [ ] The native app remains responsive with a batch of at least five children under the enforced live-preview budget.
- [ ] Existing generator safety, editor identity handoff, version history isolation, and all app/kit tests remain green.

## 11. Failure modes + fallbacks

| Failure mode | Fallback |
|---|---|
| Provider is unauthenticated | Keep the configured session and show the existing provider setup path. No child slots become failed until a run actually starts. |
| Provider timeout or process failure | Mark only affected children failed. Offer Retry This Child and Retry All Failed with original inputs. |
| User cancels generation | Stop unlaunched and in-flight processes, mark unresolved slots cancelled, preserve completed children, and offer retry. |
| Generation is quiet but alive | Keep elapsed time and last activity visible; announce a quiet state without claiming failure or inventing progress. |
| Child contains no parseable ISF | Mark the child failed with a human-readable reason and preserve its directive and retry inputs. |
| Child fails Metal compilation | Freeze the card in a failed state and expose View Compile Summary, Open Source in Editor to Fix, Copy Diagnostic, and Retry This Child. State that retry regenerates the child and may produce different code. |
| Preview renderer fails | Name that source generation succeeded, show a static fallback, make Retry Preview the primary next action, and keep Open in Editor available. Never present renderer failure as shader-generation failure. |
| Shadertoy requires verification | Enter the explicit human-handoff state, bring the challenge window forward once, and resume automatically after legitimate clearance. |
| Shadertoy verification times out or is cancelled | Preserve URL and parent target. Offer Continue Verification, Retry Fetch, Use API Key, or Paste ISF/code. |
| Shadertoy is offline or returns HTTP failure | Preserve the request and show status-specific retry/fallback actions. |
| Multiple parent fetches are requested | Serialize interactive challenges. Each request retains a unique token and target slot; stale completions are ignored. |
| Saved session is corrupt | Quarantine the bad payload, open a new session, and show a recovery notice with the stored file location. |
| App exits during generation | Restore the session with the batch labeled interrupted and offer Retry Interrupted Batch. Never claim the old provider process is still running. |
| Window becomes narrow | Collapse Lineage first, then Breeding Bay. Preserve keyboard access to reopen zones. |
| No undoable parent configuration exists | Disable Undo Parent Change and show the reason in visible help text. |

## 12. HITL checkpoints

| Trigger | Reviewer | Channel | SLA |
|---|---|---|---|
| Cloudflare presents interactive verification | Conner | Visible WKWebView with VoiceOver and keyboard access | Before the pending Shadertoy import can continue |
| Generate or Retry is requested | Conner | Explicit studio action | Immediate |
| A child is promoted or opened in the editor | Conner | Explicit card, canvas, or inspector action | Immediate |
| Implementation reaches build-done | Manual Mechanic review | Source review plus native build | Before on-device acceptance |
| Accessible workflow is staged | Client Success review | App-window-scoped captures plus on-device keyboard and VoiceOver evidence | Before declaring the redesign confirmed |
| Untrusted shader input or provider safety boundary changes | CSO | Defensive code review | Before push |
| Native feature is staged | Conner | Ordinary mouse, keyboard, and VoiceOver on-device gate | Before status becomes confirmed |

## 13. External assets

- Existing TrueISFEditor app, `ShadertoyISFKit`, native Metal renderer, and WKWebView fetcher.
- Existing local ISF library and current-editor source.
- Existing Claude and Codex CLI subscriptions and provider safety flags.
- Existing macOS persistent WebKit data store for legitimate Shadertoy clearance cookies.
- Existing Keychain-backed Shadertoy API key, when supplied.
- Existing Remix skill resources and Arson Rivvers technique catalog.
- No new hosted service, domain, account, recurring job, or paid infrastructure.

## 14. Anti-scope

- Do not automate, synthesize, or accessibility-press Cloudflare verification.
- Do not rewrite RemixPrompt, mutation semantics, provider concurrency, or the genetic domain model unless a required state boundary cannot be expressed safely.
- Do not add a freeform lineage canvas, collaboration, accounts, cloud sync, or cross-device sessions.
- Do not add more than two simultaneous comparison previews.
- Do not auto-generate on launch, parent change, restore, or verification completion.
- Do not make every favorite live indefinitely or bypass the preview budget.
- Do not use color, star, marriage glyph, animation, hover, or tooltip as the only communication channel.
- Do not force VoiceOver or keyboard focus onto each streamed child.
- Do not expose raw provider JSON or unsafe external content as instructions.
- Do not weaken the confirmed unique untitled identity and version-history isolation when opening winners.
