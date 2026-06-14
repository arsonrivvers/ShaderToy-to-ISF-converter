#!/usr/bin/env bash
# Build TrueISFEditor and install it as the ONE canonical app you open.
#
# Why this exists: Xcode scatters .app copies across DerivedData dirs, and Spotlight/Finder will
# happily open a stale one (this bit us repeatedly). This builds to a /tmp DerivedData path that
# Spotlight does NOT index, then installs a single copy to ~/Applications/TrueISFEditor.app — the
# only TrueISFEditor that appears in Spotlight. Run this, then just open "TrueISFEditor" from
# Spotlight; it is always the latest build.
#
# Usage: ./scripts/run-latest.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${REPO}/App/TrueISFEditor.xcodeproj"
DDATA="/tmp/trueisfeditor-ddata"          # /tmp is not Spotlight-indexed → never a stale entry
BUILT="${DDATA}/Build/Products/Debug/TrueISFEditor.app"
DEST="${HOME}/Applications/TrueISFEditor.app"
LOG="${DDATA}/build.log"

mkdir -p "${DDATA}" "${HOME}/Applications"

# Regenerate the .xcodeproj from project.yml so newly-added source files are always picked up
# (the .xcodeproj is gitignored/generated; a stale one silently omits new files).
if command -v xcodegen >/dev/null 2>&1; then
  echo "▶ Regenerating project (xcodegen)"
  ( cd "${REPO}/App" && xcodegen generate > /dev/null )
fi

echo "▶ Building TrueISFEditor (arm64) → ${DDATA}"
if ! xcodebuild -project "${PROJECT}" -scheme TrueISFEditor \
      -destination 'platform=macOS,arch=arm64' -derivedDataPath "${DDATA}" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > "${LOG}" 2>&1; then
  echo "✗ BUILD FAILED — last 25 lines of ${LOG}:"; tail -25 "${LOG}"; exit 1
fi
grep -q "BUILD SUCCEEDED" "${LOG}" && echo "✓ BUILD SUCCEEDED"

echo "▶ Quitting any running TrueISFEditor"
osascript -e 'quit app "TrueISFEditor"' 2>/dev/null || true
pkill -f "TrueISFEditor/Contents/MacOS/TrueISFEditor" 2>/dev/null || true
until ! pgrep -f "TrueISFEditor/Contents/MacOS/TrueISFEditor" >/dev/null 2>&1; do sleep 0.5; done

echo "▶ Installing → ${DEST}"
rm -rf "${DEST}"
ditto "${BUILT}" "${DEST}"

echo "▶ Launching the one canonical app"
open "${DEST}"
echo "✓ Running the latest: ${DEST}"
echo "  From now on just open \"TrueISFEditor\" in Spotlight — it points here."
