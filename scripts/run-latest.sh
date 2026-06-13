#!/usr/bin/env bash
# Build the latest TrueISFEditor and launch it, guaranteeing the running app IS the fresh build.
#
# Solves two macOS gotchas that repeatedly serve stale code:
#   1. The default Xcode DerivedData silently serves stale incremental builds.
#   2. `open Foo.app` re-focuses an already-running instance instead of launching the new binary.
#
# Usage: ./scripts/run-latest.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${REPO}/App/TrueISFEditor.xcodeproj"
DDATA="${REPO}/build/ddata"            # gitignored (build/ in .gitignore)
APP="${DDATA}/Build/Products/Debug/TrueISFEditor.app"
LOG="${DDATA}/build.log"

mkdir -p "${DDATA}"

echo "▶ Building TrueISFEditor (arm64) → ${DDATA}"
if ! xcodebuild -project "${PROJECT}" \
      -scheme TrueISFEditor \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "${DDATA}" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > "${LOG}" 2>&1; then
  echo "✗ BUILD FAILED — last 25 lines of ${LOG}:"
  tail -25 "${LOG}"
  exit 1
fi
grep -q "BUILD SUCCEEDED" "${LOG}" && echo "✓ BUILD SUCCEEDED"

echo "▶ Quitting any running TrueISFEditor instance"
osascript -e 'quit app "TrueISFEditor"' 2>/dev/null || true
pkill -f "TrueISFEditor/Contents/MacOS/TrueISFEditor" 2>/dev/null || true
until ! pgrep -f "TrueISFEditor/Contents/MacOS/TrueISFEditor" >/dev/null 2>&1; do sleep 0.5; done

echo "▶ Launching fresh build"
open "${APP}"
echo "✓ Running the latest build: ${APP}"
