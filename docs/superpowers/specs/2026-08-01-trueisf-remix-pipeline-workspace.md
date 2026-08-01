---
schema_version: 1
topic: trueisf-remix-pipeline-workspace
date: 2026-08-01
tier: just-me
status: complete
correlation_id: trueisf-remix-pipeline-workspace-20260801
---

# TrueISF Remix Pipeline and Canvas Workspace Upgrade

## 1. What we're building

Retrofit the existing TrueISFEditor Remix Studio so every Claude or Codex response moves through a durable, observable child pipeline and reaches real Metal compilation without being lost at the streaming boundary. The same upgrade makes Remix Studio a maximized, canvas-first native workspace with moving Parent A and Parent B previews, compact expert controls, truthful progress, recoverable cancellation, a smaller deterministic prompt, and concurrency that changes only after measured 2, 3, and 5 worker trials.

## 2. User-visible output + trigger

- **Output the user sees:** Remix Studio opens maximized in a normal macOS window. A compact Setup surface shows synchronized moving Parent A and Parent B previews. Child cards remain in stable positions while they move through Queued, Starting, Thinking, Receiving, Extracting, Compiling, and Ready. The first child that passes real Metal compilation becomes a moving preview immediately. Failures name the actual boundary, and stopping a batch preserves every completed candidate.
- **What triggers it:** The user explicitly chooses Generate or Retry after selecting valid parents. The app never generates automatically on launch, restore, parent change, or verification completion.

## 3. Cousin pattern

**Retrofit:** `App/TrueISFEditor/Remix/`, `App/TrueISFEditor/ShaderAssist/`, and `docs/superpowers/specs/2026-07-24-accessible-remix-studio.md`. Reuse the current provider safety flags, request snapshots, session autosave, lineage graph, Metal preview engine, global live-preview budget, comparison clock, and editor identity handoff. Replace the overloaded child status, raw-string provider boundary, incomplete activity model, cluttered workspace chrome, and full-skill prompt fanout. The automated cousin scanner was degraded because it referenced obsolete repository roots; direct repository inspection identified these active cousins.

## 4. Tier + why

**Tier:** just-me

This is Conner's local professional shader-making tool. It should optimize for fast expert iteration while remaining fully usable with keyboard navigation, VoiceOver, Reduce Motion, and readable 14-point-or-larger text. There is no account, collaboration, hosted service, metered API billing, or client onboarding scope.

## 5. Surfaces

- **Native SwiftUI workspace:** A maximized canvas-first window, compact Setup surface, child canvas, focused-child actions, Lineage drawer, Workspace menu, and Activity drawer.
- **Provider protocol:** Typed Claude and Codex lifecycle events plus a structured run result for Remix, with a compatibility adapter that preserves the existing text-returning contract for every shared ShaderAssist consumer.
- **Child execution model:** One durable source of truth for queueing, provider activity, response assembly, extraction, compilation, cancellation, failure, and completion.
- **Generation scheduler:** A bounded worker pool that prevents unlaunched work after Stop and exposes active workers and queue position.
- **Prompt composition:** A deterministic local technique-card selector that keeps a mandatory ISF and safety core while reducing repeated prompt material.
- **Metal compilation and preview:** Pipeline-owned compilation that does not depend on a SwiftUI card being visible, followed by budgeted moving previews.
- **Local persistence:** A versioned Remix session with atomic, bounded saves, migration from schema version 1, retained request snapshots, and recoverable diagnostics.
- **Observability:** Per-child stage, elapsed time, last activity, received byte count, worker, queue position, provider retries, and boundary-specific diagnostics.
- **Accessibility:** Stable focus, concise VoiceOver announcements, Reduce Motion behavior, visible labels, context actions, and keyboard access to every command.
- **Main editor bridge:** Opening a ready child preserves the confirmed unique untitled identity, Save As requirement, and isolated version history.
- **Subscription usage:** Claude print-mode generations consume shared automation quota. The app and benchmark report quota pressure, never dollar estimates or metered API assumptions.

## 6. v1 vs v2

**v1 (ships now):**

- Replace `RemixNode.Status` as the execution source of truth with a durable per-child run record and explicit stages and failure boundaries.
- Assemble provider output from typed events, prefer only non-empty successful result text, and fall back to a complete assistant message when the successful result is empty.
- Add a legacy-session recovery path for an empty-source `No ISF in reply` child whose saved transcript contains a complete parseable candidate. Recovery sends the source through real Metal compilation before it can become Ready.
- Make Stop race-safe: block new launches, preserve completed responses, finish local extraction and compilation, terminate incomplete provider work, and move every remaining slot to a terminal state.
- Show per-child and aggregate progress with elapsed time, last activity, active worker count, queue count, received bytes, quiet-but-running state, and provider retry state.
- Make the first Metal-compiled child visible and moving immediately without waiting for the rest of the batch.
- Replace the persistent Breeding Bay column with a compact Setup surface containing synchronized moving parent previews and progressive-disclosure source controls.
- Replace the visible collapse, resize, and reset row with one keyboard- and VoiceOver-accessible Workspace menu.
- Move repeated child-card commands into a focused-child action strip, context menu, keyboard commands, and VoiceOver actions.
- Reduce the normal Remix expertise payload from about 80.4 KB to a mandatory core plus deterministically selected technique cards, with a bounded full-catalog fallback.
- Instrument and run a controlled 2, 3, and 5 worker benchmark. Keep two workers until another mode passes the defined reliability and performance gates.
- Preserve ShaderAssist final-message, live-transcript, timeout-salvage, suggestions, edit, rewrite, diagnose, research, and Quick Goals behavior while the shared runners gain typed events.
- Preserve all existing provider tool restrictions, preview limits, Shadertoy human verification, lineage behavior, and editor identity/history isolation.

**v2 (deferred):**

- Estimated completion times based on enough measured local history to be honest.
- Provider-native structured output as the only response contract. v1 may evaluate JSON schema output, but robust assistant-text assembly remains required.
- More than five provider workers, automatic worker adaptation, or unattended background generation.
- Embedding, search-service, or LLM-based technique retrieval.
- A direct metered API path, `--bare` Claude execution, or any authentication architecture that bypasses the existing subscription path.
- Native macOS full-screen Space behavior, freeform lineage canvas, accounts, collaboration, or cloud session sync.

## 7. Stage-by-stage

### Stage 1: Restore and migrate the session

- **Input:** A schema version 1 Remix session, a schema version 2 session, or no saved session.
- **Logic:** Schema version 2 stores an ordered `RemixChildRunRecord` for every slot. The record owns child ID, immutable request snapshot, stage, stage timestamps, provider metadata, worker and queue metadata, received byte count, candidate source, bounded diagnostic response, failure boundary, compile diagnostic, and terminal timestamp. `RemixNode` represents a compiled lineage artifact, not provider execution. A version 1 `.generating` child migrates to Interrupted. A version 1 `.compiled` child is treated as a candidate requiring real recompilation because the old value did not prove Metal compilation. A version 1 `.failed` child uses the saved compile-diagnostic map and known messages to classify Compile Failed, Response Failed, Provider Failed, or Cancelled. Unknown legacy failures remain inspectable and become Interrupted rather than being guessed as compiler failures.
- **Output:** Every restored child has one truthful stage. No restored slot claims to be actively generating, and every candidate with source is eligible for local recompilation.
- **Constraint:** Migration is deterministic and idempotent. Atomic autosave occurs on stage changes and coalesced checkpoints, not once per timer tick or token delta.

### Stage 2: Configure parents in the canvas-first workspace

- **Input:** Library, current-editor, pasted ISF, or Shadertoy sources for Parent A and Parent B; mode, steer, batch size, and crossover settings.
- **Logic:** The first Remix open maximizes a normal resizable window on its current screen. Later opens restore the user's last non-full-screen size and position. Setup defaults expanded when parents are missing and compact when the required parents are ready. Expanded Setup shows two synchronized moving preview cards with name, readiness, Replace, and Clear. Choosing a source reveals only that source's controls, so paste editors and Shadertoy fields do not remain permanently visible. Compact Setup preserves names, readiness, and Edit Setup. Starting a batch returns Setup to compact form and releases parent preview reservations.
- **Output:** The user can judge both parents in motion before generation while the Children Canvas remains the dominant surface.
- **Constraint:** Parent previews share the existing global Metal budget and comparison clock. Preview priority is: hero and compared ready children, newly ready payoff child, focused ready child, visible parents, favorites and recent children, then duplicate inspector surfaces. A ready child must not remain frozen solely because both parents are visible.

### Stage 3: Build and qualify a smaller deterministic prompt

- **Input:** Immutable parent sources, mode, steer, directive, crossover settings, mandatory ISF rules, and the local technique catalog.
- **Logic:** Build a compact mandatory core covering untrusted-parent handling, output-only ISF behavior, ISF 2.0 header rules, host globals, multipass rules, Metal portability, and the Arson Rivvers control-surface doctrine. Select stable technique-card IDs using local signals only: directive tags, enabled trait routes, parent header features, parent GLSL features, and steer terms. Preserve deterministic order for the same request. Normal selected expertise payload is capped at 32 KB at the 95th percentile and must reduce the current 80.4 KB payload by at least 50 percent on the fixed prompt corpus. If selection cannot produce a valid set, use the bounded full-catalog fallback and record that fallback in diagnostics. Before the selector replaces the legacy prompt, run at least five matched legacy-versus-selected request pairs spanning short and long parents, single-pass and feedback or multipass parents, and geometry, motion, and color directives. Hold provider, model, effort, request, and worker count constant. Randomize presentation labels and conduct a blinded manual review of parent-lineage fidelity, visual usefulness, and control-surface quality. Extraction and native compile success must be non-inferior, and the selected prompt must win or tie the blinded review on every required dimension in at least four of five pairs with no catastrophic miss.
- **Output:** After the paired gate passes, each child receives the smallest relevant expertise packet plus its original immutable generation request. Until then production keeps the legacy prompt and the selector remains diagnostic-only.
- **Constraint:** Do not add another LLM call, network service, hidden metered API, or heuristic that changes parent identity or directive meaning. Fixed-corpus tests must prove that every required host rule and requested trait remains represented. The minimum five-pair quality trial uses ten provider sessions and, at the observed response sizes, may consume roughly 750,000 to 940,000 provider tokens from the shared automation pool; disclose that pressure before running it.

### Stage 4: Queue a bounded batch

- **Input:** Batch size, immutable child requests, configured provider and model, and the currently enabled worker limit.
- **Logic:** Create stable Queued records for every slot before launching work. Assign explicit queue positions. The scheduler launches at most the enabled worker count and records a stable worker label for each active child. A Stop signal closes the launch gate before cancelling provider processes.
- **Output:** The canvas immediately shows all slots with truthful queue or worker state.
- **Constraint:** The production default remains two workers until the benchmark passes. No queued child can launch after Stop.

### Stage 5: Run the provider through typed events without breaking ShaderAssist

- **Input:** One child prompt and the existing safety-pinned Claude or Codex provider.
- **Logic:** Introduce a typed runner core that emits lifecycle events and returns an `AssistRunResult`. Events include session started, thinking activity, text delta, complete assistant message, API retry, successful result, error result, process exit, timeout, and cancellation. Claude enables partial messages. Text deltas update byte count and last activity without adding one terminal row per token. Complete assistant messages are indexed by message and content-block identity. The assembler either consumes deltas or replaces them with the complete snapshot; it never concatenates both and never duplicates cumulative assistant snapshots. Remix consumes the typed core directly. A text compatibility adapter continues satisfying the existing `AssistProvider.run(...) async throws -> String` behavior used by ShaderAssist until every shared consumer is explicitly migrated. The adapter must preserve final-message selection, humanized live transcript delivery, nonzero-exit mapping, completed-result timeout salvage, cancellation, suggestions parsing, edit/rewrite responses, diagnose, research, and Quick Goals completion.
- **Output:** The child moves through Starting, Thinking, and Receiving with a structured provider result and retained diagnostics.
- **Constraint:** Existing Claude tool removal, LSP denial, strict MCP configuration, slash-command disabling, neutral working directory, and Codex read-only sandbox remain unchanged. Provider events are treated as untrusted data. No shared ShaderAssist call site changes behavior merely because Remix needs richer events.

### Stage 6: Resolve the authoritative response

- **Input:** Successful or failed result event, assembled assistant message, process state, timeout or cancellation state, and any retained partial response.
- **Logic:** Apply this precedence matrix:
  1. A non-empty successful result wins.
  2. An empty or whitespace-only successful result falls back to the non-empty complete assistant message.
  3. A successful process exit with no result may use a complete assistant message whose provider stop reason is `end_turn`.
  4. An error result is always Provider Failed. Assistant text is retained diagnostically but never silently promoted to success.
  5. A timeout after a successful result uses the same precedence above.
  6. A timeout or cancellation with a syntactically complete ISF candidate may retain that candidate for explicit local extraction and compilation. Incomplete text remains inspectable and cannot become Ready.
  7. A cancelled task that already observed authoritative completion continues local extraction and compilation. Cancellation before authoritative completion terminates as Cancelled.
- **Output:** One authoritative response candidate or a boundary-specific terminal failure.
- **Constraint:** Non-empty means non-empty after trimming. Raw terminal presentation is never the source of truth. Diagnostic response storage is capped at 256 KB per child and batch/session history remains bounded.

### Stage 7: Extract and compile independently of the view

- **Input:** An authoritative response candidate or an explicitly recovered complete candidate.
- **Logic:** Extract the first complete fenced block containing an ISF header, or the raw source beginning at a valid `/*{` header. Validate the header JSON and required ISF structure. Then invoke an injected native Remix compiler service backed by the existing safe ISFMSL path. Compilation is owned by the pipeline and runs even if the card is off-screen or the Activity drawer is collapsed. Only a successful native compile creates or updates the lineage `RemixNode` and moves the run record to Ready.
- **Output:** A Ready child with compiled source and preview eligibility, or Extraction Failed / Compile Failed with retained source and exact diagnostics.
- **Constraint:** Parser success is not compilation success. The UI may never use `.compiled` to mean merely "text was extracted."

### Stage 8: Deliver the first payoff and continue the batch

- **Input:** Any child reaching Ready while siblings remain active or queued.
- **Logic:** Replace the stable placeholder in place, give the newly ready child temporary preview priority, and display a moving Metal preview immediately. Announce "Child N ready" once without changing keyboard or VoiceOver focus. Under Reduce Motion, show the compiled frame paused with an explicit Play action. Continue launching queued work while the launch gate remains open.
- **Output:** The user can inspect and act on the first successful child without waiting for the complete batch.
- **Constraint:** One child failure never blocks siblings. UI updates occur on the main actor and each child accepts only its first terminal transition.

### Stage 9: Show truthful progress and liveness

- **Input:** Child records, typed provider events, process liveness, timeout budget, and terminal counts.
- **Logic:** The compact strip summarizes stage counts, for example "2 receiving, 3 queued, 0 ready." Each child shows stage, elapsed time since start, last provider activity, received assistant bytes, worker, or queue position. Overall determinate progress counts terminal slots only. A child becomes "Quiet, still running" only when its process is confirmed alive and no provider event has arrived for the configured quiet threshold. "Possibly stalled" requires a watchdog inconsistency such as a dead process without a terminal event, a closed event stream before process resolution, or elapsed time beyond timeout plus teardown grace. Silence during long model thinking is not called stalled. API retry events show retry state without exposing raw JSON.
- **Output:** The user can distinguish queued, active, quiet, retrying, local processing, ready, failed, and cancelled work at a glance.
- **Constraint:** Do not invent an ETA or map unequal stages to a fake percentage. VoiceOver announces batch start, first Ready, failures, cancellation, and batch completion, not token-by-token activity.

### Stage 10: Stop, recover, and retry

- **Input:** Stop, app termination, provider failure, extraction failure, compile failure, preview failure, or retry action.
- **Logic:** Stop first closes the scheduler launch gate. Already-terminal records remain unchanged. A fully received authoritative response completes local extraction and compilation. Incomplete active provider work is terminated. Every unlaunched or unresolved child promptly becomes Cancelled, unless app termination requires Interrupted. When asynchronous callbacks race, the main-actor child store applies first-terminal-transition-wins. Retry reuses the immutable request snapshot and stable child ID, changes only an explicit steer override, and reruns only the selected failed, cancelled, or interrupted child.
- **Output:** Every slot ends Ready, Failed, Cancelled, or Interrupted. Completed value is preserved and retry remains scoped.
- **Constraint:** No batch may finish, cancel, restore, or relaunch with a Queued, Starting, Thinking, Receiving, Extracting, Compiling, or legacy Generating slot that has no live owner.

### Stage 11: Work in a less cluttered canvas

- **Input:** Ready, failed, active, and queued children plus workspace and lineage state.
- **Logic:** The Children Canvas owns most of the window. One Workspace menu contains Setup, Lineage, Activity, Focus Canvas, zone sizing, and Reset Layout commands with current-state labels and keyboard access. Child cards show preview, identity, directive, stage, and the smallest frequent action set. A focused-child action strip exposes Favorite, Compare, Hero, Promote A, Promote B, Open, Freeze, and relevant recovery. The same complete set remains available through a context menu, keyboard commands, and VoiceOver custom actions. Activity remains a compact persistent strip with an expandable diagnostic drawer.
- **Output:** Expert scanning and comparison are fast, while every command remains discoverable without permanent toolbar clutter.
- **Constraint:** Focus, favorite, comparison, parent promotion, failure, and preview state never depend on color, motion, hover, or an unlabeled icon alone.

### Stage 12: Screen and benchmark worker counts before enabling them

- **Input:** The same representative five-child request set run with worker limits 2, 3, and 5, pipeline instrumentation, native compile results, and system resource measurements.
- **Logic:** Before any live trial, show the planned session count and shared-quota pressure. First run one identical five-child batch per worker count as a viability screen, or 15 provider sessions total. A viability screen can reject a lane but can never change the production default. A lane that remains viable advances to a decision benchmark of at least three matched five-child trials per worker count. Interleave the lane order across trial cycles, for example 2/3/5, then 3/5/2, then 5/2/3, and hold parents, directives, provider, model, effort, and surrounding machine conditions as constant as practical. The decision benchmark uses 45 provider sessions total when all lanes remain viable. Based on the observed 64,000 input tokens plus roughly 9,000 to 30,000 output tokens per child, the viability screen can consume roughly 1.1 million to 1.4 million provider tokens and the full decision benchmark can consume roughly 3.3 million to 4.2 million provider tokens from the shared automation pool. Record first-ready latency, total makespan, provider retry/rate-limit count, authoritative-response recovery, extraction and compile success, peak worker and app RSS, CPU pressure, memory pressure, and UI input latency. Store each completed trial so the work is resumable after a quota reset.
- **Output:** A measured worker policy and retained benchmark report.
- **Constraint:** Compare lane medians across the matched decision trials. Three becomes the default only if it reduces median total makespan by at least 20 percent versus two, keeps median first-ready latency within 10 percent, causes no reliability regression or rate-limit increase, keeps memory pressure normal, keeps combined app and worker RSS at or below 6 GB, and keeps UI input response under 150 ms. Five-worker Fast mode ships only if its median makespan is at least 15 percent faster than three with the same reliability and responsiveness. If the viability screen is the only completed evidence, or any decision trial is missing, two remains default and 3/5 enablement stays deferred.

### Stage 13: Open a winner without identity leakage

- **Input:** One Ready child selected through the card, action strip, context menu, keyboard, or Lineage drawer.
- **Logic:** Use the existing unique untitled-document handoff. The child opens with `Unsaved - Save As required` and its own Imported version entry. Saving one child migrates only that child's active history.
- **Output:** A winner opens in the main editor ready for authoring and Save As.
- **Constraint:** No disk write occurs until the user saves. Opening multiple winners must preserve identity and version-history isolation.

## 8. Worked example end-to-end

Conner opens Remix Studio. The normal window maximizes on the current display and shows the canvas with Setup expanded because two parents are already selected. Parent A and Parent B move side by side on a shared clock. Their names, readiness, Replace, and Clear actions are visible; unused paste and Shadertoy editors are hidden.

Conner selects a five-child Crossover batch and chooses Generate. Setup becomes compact. Five stable slots appear immediately. The activity strip says "2 starting, 3 queued, 0 ready." As the provider emits partial events, the first two cards change from Starting to Thinking and Receiving, show elapsed time and received bytes, and keep the other three visibly queued.

The first Claude run sends a complete fenced ISF in an assistant event but an empty successful result, matching the August 1 failure. The response assembler ignores the empty result, selects the complete assistant text, extracts the shader, validates its header, and sends it through the native compiler. The card changes to Compiling and then Ready. Its moving preview appears immediately and the app announces "Child 1 ready" once. The other child continues without focus moving.

Conner chooses Stop while another child has already completed its assistant response. The launch gate closes before another worker starts. That complete response finishes local extraction and compilation. Incomplete workers terminate, queued slots become Cancelled, and no slot remains Generating. Conner retries only one cancelled child using its original parents, directive, settings, and steer.

After comparing two Ready children, Conner opens the winner. It arrives in the editor as a unique untitled document with `Unsaved - Save As required` and an isolated Imported version entry. Saving it cannot migrate the sibling child's history.

## 9. Tone constraints

- Use direct maker-facing states: Queued, Starting, Thinking, Receiving, Extracting, Compiling, Ready, Quiet, Retrying, Cancelled, Interrupted, Provider Failed, Response Incomplete, Extraction Failed, Compile Failed, and Preview Failed.
- Never call extraction or provider failure a compile failure.
- Never show a fake percentage, unmeasured ETA, or generic "something went wrong" message.
- Keep raw stream JSON, token accounting internals, process IDs, and provider jargon out of the normal UI. Put bounded technical detail in diagnostics.
- Minimum rendered text is 14 points. Secondary text remains readable and meets contrast requirements.
- Dark native macOS presentation remains the default. Visible text labels and accessible names carry meaning; icons are supplementary.
- The compact interface serves expert repetition. Progressive disclosure reveals uncommon source and recovery controls only when relevant.

## 10. Success criteria

- [ ] A captured stream fixture with a complete assistant ISF and an empty successful result resolves to the assistant source, reaches the real native Metal compiler, and becomes Ready.
- [ ] A non-empty successful result wins over assistant text, an error result never becomes success, and cumulative assistant snapshots never duplicate source text.
- [ ] The recoverable August 1 sources for r1-0, r1-1, and r1-3 remain available for local extraction and compilation rather than requiring paid or quota-consuming regeneration.
- [ ] Parser success alone never creates a Ready child or lineage artifact; every Ready child has a successful pipeline-owned native compile result.
- [ ] Stop before launch, during provider work, after authoritative completion, during extraction, and during compilation produces deterministic terminal states and preserves completed value.
- [ ] Zero slots remain Queued, Starting, Thinking, Receiving, Extracting, Compiling, or legacy Generating after Stop, relaunch, timeout resolution, or batch completion without a live owner.
- [ ] Provider, response, extraction, compile, preview, cancellation, and interruption failures display the correct boundary, diagnostic, and scoped actions.
- [ ] The compact activity strip reports active stage counts and queue counts; each child reports elapsed time, last activity, bytes, worker or queue position, and truthful liveness.
- [ ] The first Ready child appears as a moving preview immediately without waiting for batch completion or losing focus.
- [ ] Parent A and Parent B have synchronized moving previews while Setup is expanded, share the Metal budget, and release reservations when Setup becomes compact.
- [ ] The Workspace menu and focused-child action model remove repeated visual clutter while every operation remains available by pointer, keyboard, VoiceOver, and context menu.
- [ ] The normal selected expertise payload is no more than 32 KB at the 95th percentile and at least 50 percent smaller than the current 80.4 KB bundle on the fixed corpus, with no loss of mandatory ISF, safety, requested-trait, or compile expectations.
- [ ] At least five matched legacy-versus-selected prompt pairs preserve non-inferior extraction and Metal-compile success, and blinded review finds the selected prompt equal or better for lineage fidelity, visual usefulness, and control-surface quality in at least four of five pairs with no catastrophic miss.
- [ ] The 2, 3, and 5 worker viability screen can reject but cannot enable a lane. Only three matched, interleaved decision trials per viable lane can change the default or expose Fast mode.
- [ ] Existing ShaderAssist final-message, transcript, timeout salvage, suggestions, edit, rewrite, diagnose, research, Quick Goals, error, and cancellation behavior passes focused compatibility tests and a live smoke through the compatibility adapter.
- [ ] Reduce Motion starts compiled previews paused, offers an explicit Play action, and keeps all stages and outcomes understandable without animation.
- [ ] Keyboard-only, VoiceOver, focus restoration, contrast, 14-point text, narrow-window, and app-window-scoped Client Success checks pass.
- [ ] Two compiled winners opened before either is saved retain distinct untitled identities and isolated Imported, pinned, and v01 histories through Save As.
- [ ] Focused app tests, the complete TrueISFEditor suite, ShadertoyISFKit tests, arm64 Debug build, installed-binary freshness check, Mechanic review, Client Success live review, and CSO provider-boundary review pass before confirmation.

## 11. Failure modes + fallbacks

| Failure mode | Fallback |
|---|---|
| Claude or Codex is not authenticated | Mark only the affected child Provider Failed, preserve its request, and show the existing provider setup path. Do not reinterpret the failure as missing ISF. |
| Provider emits an API retry or rate-limit event | Keep the child active, show Retrying with attempt and wait state in human terms, update last activity, and preserve the provider's eventual terminal result. |
| Provider is silent while its process is alive | Show Quiet, still running with elapsed time and last activity. Do not claim failure or stall. |
| Provider process dies without a terminal event | Mark Provider Failed or Possibly Stalled based on watchdog evidence, retain complete or partial response diagnostics, and offer scoped Retry. |
| Successful result text is empty but assistant text is complete | Use the assembled complete assistant message and continue to extraction. This is the binding regression case. |
| Complete and partial assistant events overlap | Deduplicate by message and content-block identity. Never append a full snapshot after its deltas. |
| Error result contains shader-like assistant text | Keep Provider Failed. Retain text for View Response and diagnostics, but never silently promote it to Ready. |
| Response contains no complete ISF | Mark Response Incomplete or No ISF Found, preserve the response and request, and offer View Response, Copy Diagnostic, Open Source when non-empty, and Retry. |
| Fenced or raw source extraction fails | Mark Extraction Failed with the exact parser reason and retain the authoritative response. |
| Header parses but native compilation fails | Mark Compile Failed, retain candidate source and compiler diagnostic, and offer View Summary, Copy Diagnostic, Open to Fix, and Retry. |
| Preview fails after native compile | Keep the child Ready, show Preview Failed as a renderer state, retain a compiled-frame fallback when available, and offer Retry Preview and Open in Editor. |
| User stops while a response is complete | Finish local extraction and compilation, preserve the terminal result, and cancel only incomplete or unlaunched work. |
| User stops before response completion | Terminate provider work, retain bounded partial diagnostics, mark the child Cancelled, and preserve the immutable retry request. |
| App exits mid-batch | Restore live-owned stages as Interrupted, never active, and offer retry with original requests. |
| A schema version 1 child says compiled without compile provenance | Recompile locally before Ready. Do not trust the old overloaded status. |
| Saved session is corrupt | Quarantine it, start clean, and show the recoverable file location without deleting it. |
| Technique selector has no confident match | Use the bounded full-catalog fallback, record the fallback, and continue without an extra model call. |
| Selected prompt exceeds the cap | Drop lowest-priority technique cards deterministically while retaining the mandatory core and requested-trait cards. |
| Smaller prompt passes size tests but reduces remix quality | Keep the legacy prompt in production, retain the selector as diagnostic-only, record the failed paired gate, and revise the cards before another quota-approved trial. |
| Parent preview cannot compile | Keep the parent selected, show Parent Preview Failed with Open in Editor or Replace actions, and do not mislabel the parent source invalid unless source validation failed. |
| Live-preview budget is exhausted | Preserve the documented priority order, freeze lower-priority surfaces to a real frame, and never exceed the cap. |
| Three or five workers regress reliability or responsiveness | Keep that mode unavailable and retain two workers as the production default. |
| Typed provider work changes a ShaderAssist consumer | Block staging, keep that consumer on the compatibility adapter, and fix the focused behavioral regression before Remix execution continues. |
| Shared automation quota is insufficient for the benchmark | Do not fall back to a metered API. Preserve benchmark state and resume after the shared pool resets. |

## 12. HITL checkpoints

| Trigger | Reviewer | Channel | SLA |
|---|---|---|---|
| Architecture recommendation before implementation | Product Manager | Read-only spec review | Complete before filing this spec |
| Setup, progress, recovery, and first-payoff interaction contract | Client Success | Read-only spec review | Complete before filing this spec |
| Claude CLI streaming, structured output, concurrency, and subscription behavior recommendation | Librarian-equivalent primary-source research | Official Anthropic documentation | Complete before filing this spec |
| Live 2, 3, and 5 worker benchmark | Conner | Conversation with session count and shared-quota estimate | Before launching the benchmark |
| Legacy-versus-selected prompt quality trial | Conner | Blinded paired shader review with quota estimate | Before replacing the legacy production prompt |
| Provider event parsing, response retention, or safety boundary changes | CSO | Defensive code review | Before staging or push |
| Native UI implementation is build-complete | Mechanic | Source review, arm64 build, and native runtime inspection | Before asking Conner to test |
| Shared runner migration is build-complete | Conner and Mechanic | Live ShaderAssist smoke covering suggestions, rewrite, diagnose, research, and Quick Goals | Before staging Remix changes |
| Native workflow is staged | Client Success | App-window-scoped live review only | Before calling the redesign ready |
| Accessible Remix workflow is staged | Conner | Ordinary pointer, keyboard, VoiceOver, and Reduce Motion on-device gate | Before status becomes confirmed |
| Two winners open into the editor | Conner | Existing two-child identity and version-history checklist | Before confirming editor handoff integrity |
| Any local TrueISFEditor commit would be pushed | Conner and null_signal colleague | Existing courtesy heads-up | Before any push; nothing pushes without confirmation |

## 13. External assets

- Existing TrueISFEditor source under `App/TrueISFEditor/Remix/` and `App/TrueISFEditor/ShaderAssist/`.
- Existing `ClaudeCodeRunner`, `CodexRunner`, provider tool restrictions, local Claude and Codex subscription authentication, and CLI binaries.
- Official Anthropic headless, streaming-output, structured-output, subscription, and parallel-session documentation reviewed on 2026-08-01.
- Existing `MetalPreviewController`, safe ISFMSL compile bridge, `RenderClock`, comparison coordinator, snapshots, and four-surface live-preview budget.
- Existing Remix session store, lineage graph, immutable retry snapshots, and the August 1 saved session transcript containing recoverable r1-0, r1-1, and r1-3 candidates.
- Existing bundled `shader-lineage-remix`, `isf-shader-development`, `shader-dev`, and `arsonrivvers_technique_catalog` resources.
- Existing Shadertoy resolver and legitimate human verification flow.
- Existing unique untitled editor handoff and version-history migration logic.
- No new hosted service, domain, account, recurring task, metered API key, or paid infrastructure.

## 14. Anti-scope

- Do not ship a parser-only patch that leaves overloaded statuses, cancellation races, or dishonest progress intact.
- Do not regenerate r1-0, r1-1, or r1-3 merely because the old runner stored an empty source; recover their saved candidates first.
- Do not treat raw terminal display strings or the Activity drawer as the provider source of truth.
- Do not call provider, response, extraction, cancellation, or preview failure a compile failure.
- Do not mark a child Ready before a real pipeline-owned native Metal compile succeeds.
- Do not force Remix Studio into a native macOS full-screen Space.
- Do not leave the paste editor, Shadertoy editor, resize controls, or every child action permanently visible.
- Do not invent percentage progress or ETA from unequal stages.
- Do not increase the default above two workers or expose five-worker Fast mode without the binding benchmark gates.
- Do not run the worker benchmark without first disclosing its session count and shared-quota pressure.
- Do not use a metered API, `--bare`, hidden API-key fallback, or dollar-based cost framing.
- Do not add an LLM call, network service, embedding index, or nondeterministic router to select technique cards.
- Do not replace the legacy production prompt based on payload size or rule coverage without the paired generation-quality gate.
- Do not break or silently alter ShaderAssist to make the Remix provider path richer; preserve shared behavior through the adapter and focused smoke gate.
- Do not weaken Claude tool stripping, Codex read-only sandboxing, strict MCP behavior, neutral working directory, or untrusted-source boundaries.
- Do not exceed the global Metal preview budget or make every favorite and parent animate indefinitely.
- Do not automate Cloudflare verification, auto-generate on restore, or broaden this into a Shadertoy/importer cleanup.
- Do not rewrite unrelated editor, capture, cache, ARShader, or corpus systems as part of this upgrade.
- Do not push local TrueISFEditor commits until the standing null_signal colleague heads-up is explicitly confirmed.
