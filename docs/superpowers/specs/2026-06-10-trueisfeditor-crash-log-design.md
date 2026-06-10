# TrueISFEditor — Crash Log (design + plan)

**Date:** 2026-06-10
**Status:** Approved — building, then resuming Filter Input Sources Slice 2.

## Goal
A persistent, reviewable log of failures: both the **soft failures** the safe bridge already catches
(compile/render errors — frequent in shader dev) and **hard crashes** that terminate the process
(signals / uncaught exceptions / Metal asserts). In-app viewer + JSON log file.

## Architecture
- **`CrashEvent`** — Codable struct: `id`, `timestamp`, `kind` (`.compile/.render/.exception/.signal`),
  `message`, `context` (shader `DESCRIPTION`), `detail` (backtrace / signal name).
- **`CrashLog`** — `@MainActor` singleton `ObservableObject` (`CrashLog.shared`). `@Published events`,
  `crashedLastSession`. `record(_:)` (dedupes consecutive identical events; caps to last 500),
  `clear()`. Persists to `~/Library/Logs/TrueISFEditor/crash-log.json`. On init: loads the file and
  **ingests any pending hard-crash record** written by the reporter, then deletes it. `init(directory:)`
  override for tests.
- **`CrashWriter.c`** (+ `.h`, in the bridging header) — a pure-C, **async-signal-safe** writer:
  `tisf_write_signal_record(const char *path, int sig)` does `open`/`snprintf`/`write`/
  `backtrace_symbols_fd`/`close` with C string literals (no malloc). The signal→name switch lives in C.
- **`CrashReporter`** — `install(pendingURL:)` strdups the path into static storage, sets
  `NSSetUncaughtExceptionHandler` (writes `EXCEPTION …` via normal I/O — not a signal context), and
  installs `signal()` handlers (SIGSEGV/SIGABRT/SIGBUS/SIGILL/SIGFPE/SIGTRAP) whose `@convention(c)`
  body calls the C writer, restores `SIG_DFL`, and re-raises so the OS crash dialog still fires.
- **`CrashLogView`** + a `Window("Crash Log", id: "crash-log")` scene + a **Window ▸ Crash Log** command
  (`openWindow`). Newest-first list, selectable/copyable, **Clear** + **Reveal Log in Finder**. The menu
  item shows a ⚠︎ when `crashedLastSession`.

## Wiring (soft failures)
- `MetalPreviewController` stashes `lastLoadedSource` in `load(isf:)`.
- `applyCompile` failure branch → `CrashLog.shared.record(.compile, …, context: shaderName(from:))`.
- `draw` render-exception path (already sets `scene = nil`, so once-per-load) → `.record(.render, …)`.
- `shaderName(from:)` parses `DESCRIPTION` out of the ISF `/*{ … }*/` header.

## Pending-file format
`SIGNAL <NAME> <epoch>\n<backtrace…>` (signal path) or `EXCEPTION <name> <epoch>\n<reason>\n<stack>`
(exception path). `CrashLog.ingestPending` parses the header line and maps to `.signal`/`.exception`.

## Async-signal-safety note
The signal handler does only async-signal-safe work, delegated to pure C (`CrashWriter.c`). Swift String
interpolation / malloc is avoided on that path. The uncaught-exception handler is not a signal context,
so it uses ordinary Swift I/O. This is best-effort crash capture (standard for a dev tool), not a
hardened production crash reporter.

## Tasks
1. **`CrashEvent` + `CrashLog` + tests** (persistence, 500-cap, consecutive-dedup, Codable round-trip,
   pending-file ingest→event→delete, clear).
2. **`CrashWriter.c/.h` + `CrashReporter` + wiring** (bridging header, `App.init` install + touch
   `CrashLog.shared`, `MetalPreviewController` soft-failure hooks + `shaderName`).
3. **`CrashLogView` + Window scene + Window ▸ Crash Log command** (⚠︎ on `crashedLastSession`).

## Testing
Unit tests cover `CrashLog` + `CrashEvent` (Task 1). The signal handler and the viewer are verified
on-device (folded into the Slice 1 / next on-device gate).
