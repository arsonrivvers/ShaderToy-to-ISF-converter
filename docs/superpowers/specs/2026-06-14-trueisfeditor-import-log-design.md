# TrueISFEditor — Import Log + inline import summary

**Date:** 2026-06-14
**Status:** Approved (design)

## Motivation

Shadertoy imports could fail with opaque messages. The recently-fixed N323DD bug
(internal-endpoint `type` vs `ctype`) surfaced as a misleading "Shader not found, or it isn't
public." for a public shader — the real failure (a Codable mismatch) was masked. The parser now
distinguishes genuine not-found from malformed, and `AppModel` already shows honest, actionable
messages. This feature makes the import pipeline **legible**: a persistent record of every import
attempt and an at-a-glance inline outcome, so a user (or a bug report) can see *which stage* failed
and *what came back* — without the developer-only `SHADERTOY_DEBUG_FETCH` hook.

Scope is the **import action**: fetch → parse → convert. Preview-**compile** diagnostics already
live in `DiagnosticsPanel` / `CrashLog` and are NOT duplicated here.

## Architecture

Mirrors the existing `CrashLog` pattern (`App/TrueISFEditor/CrashLog.swift` +
`CrashEvent.swift` + `Views/CrashLogView.swift`): a singleton `ObservableObject`, JSON-persisted,
a capped event list, surfaced in a dedicated `Window`. This keeps the new code consistent with a
pattern the codebase already proves and tests.

### Components

1. **`ImportEvent` (model, `Codable`, `Equatable`)** — one import attempt:
   - `timestamp: Date`
   - `query: String` — exactly what the user entered (URL or ID)
   - `shaderID: String?` — resolved ID (nil if the query wasn't a recognizable URL/ID)
   - `fetchSource: FetchSource` — `.api` | `.webView` (mirrors `FetchStrategy`)
   - `httpStatus: Int?` — the in-page `/shadertoy` POST status (webView) when known
   - `stage: Stage` — `.urlInvalid | .fetched | .parsed | .converted` — the furthest stage reached
   - `outcome: Outcome` — `.success | .warning | .error`
   - `message: String` — the same friendly copy shown in the status area
   - `responseSnippet: String?` — first ~300 chars of the raw `/shadertoy` body; populated **only**
     on a parse failure (the case where the body is the diagnostic signal)
   - `warningCount: Int` — conversion warnings (0 unless `.converted`)

2. **`ImportLog` (model)** — `ImportLog.shared`, `@MainActor`, `ObservableObject`:
   - `@Published private(set) var events: [ImportEvent]`
   - persisted to `~/Library/Logs/TrueISFEditor/import-log.json` (same dir as the crash log)
   - `maxEvents = 200`, oldest trimmed
   - `record(_:)` (append + persist; **no** de-dup — distinct attempts are individually meaningful,
     unlike CrashLog's per-keystroke compile spam), `clear()`, `load()`/`persist()`
   - `init(directory: URL? = nil)` override for tests (same shape as CrashLog)

3. **Recording point** — `AppModel.convert()` records exactly one `ImportEvent` at the end of every
   path: the success branch and each `catch`. It already holds `webFetcher.lastResponseStatus`,
   `webFetcher.lastResponseBody`, the resolved `id`, the chosen `FetchStrategy`, the warnings, and
   the error. A small private helper assembles the event from those; no new plumbing through the
   fetch/convert layers.

4. **Inline summary** — a one-line outcome in `Views/ShadertoyImportSheet.swift`, adjacent to the
   existing `model.statusMessage` line (currently rendered at ~line 76, under the URL `TextField` +
   "Fetch & Convert" button). Shows e.g. `✓ Converted (1 warning)` / `✗ Parse failed — format
   unsupported` with a trailing `Import Log ▸` affordance that opens the window. Bound to
   `AppModel`'s latest `ImportEvent`. The summary STRING is produced by a pure function
   (`ImportEvent.summaryLine`) so it's unit-tested without the UI. The existing `statusMessage`
   stays as-is; the inline summary adds the severity icon + the link to the full log.

5. **`Import Log` window** — `Window("Import Log")` in `TrueISFEditorApp.body` next to the existing
   Crash Log window, with a matching menu item. `Views/ImportLogView.swift` mirrors
   `CrashLogView`: newest-first rows (time · query · severity icon · message), each row expandable
   (disclosure) to a stage breakdown — fetch source + HTTP status, parse stage, and the response
   snippet when present. A `Clear` button calls `ImportLog.shared.clear()`.

## Data flow

```
user enters URL/ID → AppModel.convert()
  ├─ ShadertoyURL.shaderID == nil → record(.urlInvalid, .error)
  ├─ fetch (api|webView) → on HTTP/no-data/challenge error → record(.fetched, .error, httpStatus)
  ├─ parse → .shaderNotFound → record(.fetched, .error)            (genuine not-found)
  │        → .malformed(detail) → record(.fetched, .error, snippet) (body captured)
  └─ convert → record(.converted, warnings>0 ? .warning : .success, warningCount)
ImportLog.shared.record(event) → @Published events → inline summary + window update
```

## Error handling

- Recording is best-effort and never throws into the import path (persist failures are swallowed,
  exactly like CrashLog).
- The response snippet is bounded to ~300 chars and only attached on parse failure, so the log file
  stays small even with large shader payloads.

## Testing

- `ImportLogTests`: record appends + persists; `clear()` empties + persists; cap trims oldest at
  `maxEvents`; load round-trips from disk (temp `directory:` override).
- `ImportEventTests`: pure `summaryLine` / detail-formatting for each outcome (success, warning,
  url-invalid, fetch HTTP error, not-found, malformed-with-snippet).
- UI (`ImportLogView`, inline summary) verified by on-device review (mirrors CrashLogView; no logic
  beyond the tested pure formatters). Client Success live UX review tracked as a deferred item.

## Out of scope (YAGNI)

- Preview-compile diagnostics (already in DiagnosticsPanel/CrashLog).
- Full raw-body viewer / copy-raw (short snippet only, per decision).
- Re-run / retry-from-log actions.
- Filtering/search in the window.
