#!/usr/bin/env bash
# Run the conversion-conformance corpus harness over a list of Shadertoy IDs.
#
# Fetches + converts + transpiles each shader through the REAL ISFMSLKit (glslang→Metal) path and
# prints a pass/fail report bucketed by error — the proactive net for discovering failure classes
# before users hit them. Unlike the in-app `browse:` mode (which plateaus on ~12 popular shaders),
# this runs a curated, feature-diverse ID list.
#
# Usage:
#   ./scripts/corpus-run.sh                         # default: corpus/discovery-ids.txt
#   ./scripts/corpus-run.sh path/to/ids.txt         # a specific ID list (one id per line, # = comment)
#   ./scripts/corpus-run.sh -o /tmp/raw ids.txt     # also dump each raw shader JSON to /tmp/raw
#   ./scripts/corpus-run.sh --build ids.txt         # force a rebuild first (else reuse existing build)
#
# Output: a live per-shader report to stdout AND a saved copy at $TMPDIR/conversion-corpus-report.txt.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${REPO}/App/TrueISFEditor.xcodeproj"
DDATA="/tmp/trueisfeditor-ddata"
BIN="${DDATA}/Build/Products/Debug/TrueISFEditor.app/Contents/MacOS/TrueISFEditor"

FORCE_BUILD=0
OUT_DIR=""
IDS="${REPO}/corpus/discovery-ids.txt"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) FORCE_BUILD=1; shift ;;
    -o|--out) OUT_DIR="$2"; shift 2 ;;
    *) IDS="$1"; shift ;;
  esac
done

[[ -f "$IDS" ]] || { echo "✗ ids file not found: $IDS"; exit 1; }

if [[ $FORCE_BUILD -eq 1 || ! -x "$BIN" ]]; then
  echo "▶ Building TrueISFEditor → ${DDATA}"
  command -v xcodegen >/dev/null 2>&1 && ( cd "${REPO}/App" && xcodegen generate >/dev/null )
  xcodebuild -project "$PROJECT" -scheme TrueISFEditor \
      -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DDATA" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > "${DDATA}/corpus-build.log" 2>&1 \
    && grep -q "BUILD SUCCEEDED" "${DDATA}/corpus-build.log" \
    || { echo "✗ BUILD FAILED — tail of log:"; tail -25 "${DDATA}/corpus-build.log"; exit 1; }
  echo "✓ build ready"
fi

echo "▶ Running corpus over $(grep -vcE '^[[:space:]]*#' "$IDS") ids from $IDS"
pkill -f "TrueISFEditor/Contents/MacOS/TrueISFEditor" 2>/dev/null || true
sleep 1

if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  SHADERTOY_DEBUG_CORPUS="$IDS" SHADERTOY_DEBUG_CORPUS_OUT="$OUT_DIR" "$BIN" 2>/dev/null | grep -E '	OK	|	FAIL	|FETCH-FAIL|=== CORPUS'
else
  SHADERTOY_DEBUG_CORPUS="$IDS" "$BIN" 2>/dev/null | grep -E '	OK	|	FAIL	|FETCH-FAIL|=== CORPUS'
fi

echo "▶ Full report: ${TMPDIR:-/tmp/}conversion-corpus-report.txt"
