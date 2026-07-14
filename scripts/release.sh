#!/usr/bin/env bash
# Build a distributable TrueISFEditor DMG: Release archive → (optional) sign → (optional) notarize
# → staple → DMG. Without signing credentials it still produces an ad-hoc-signed DMG suitable for
# local testing and pre-release checks — the notarize steps are env-gated, never required.
#
# Usage:
#   ./scripts/release.sh                                # ad-hoc build + DMG
#   SIGN_IDENTITY="Developer ID Application: …" \
#   NOTARY_PROFILE="trueisf-notary" ./scripts/release.sh   # signed + notarized + stapled
#
# NOTARY_PROFILE is a keychain profile created once with:
#   xcrun notarytool store-credentials trueisf-notary --apple-id you@example.com \
#     --team-id TEAMID --password <app-specific-password>
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${REPO}/App/TrueISFEditor.xcodeproj"
DDATA="/tmp/trueisfeditor-release"
ARCHIVE="${DDATA}/TrueISFEditor.xcarchive"
STAGE="${DDATA}/dmg-stage"
VERSION="$(grep -m1 'MARKETING_VERSION' "${REPO}/App/project.yml" | sed 's/[^0-9.]//g')"
DMG="${REPO}/build/TrueISFEditor-${VERSION}.dmg"
LOG="${DDATA}/release.log"

mkdir -p "${DDATA}" "${REPO}/build"

echo "▶ Regenerating project (xcodegen)"
( cd "${REPO}/App" && xcodegen generate > /dev/null )

echo "▶ Archiving Release (arm64) → ${ARCHIVE}"
if ! xcodebuild -project "${PROJECT}" -scheme TrueISFEditor -configuration Release \
      -destination 'generic/platform=macOS' -archivePath "${ARCHIVE}" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=NO archive > "${LOG}" 2>&1; then
  echo "✗ ARCHIVE FAILED — last 25 lines of ${LOG}:"; tail -25 "${LOG}"; exit 1
fi

APP="${ARCHIVE}/Products/Applications/TrueISFEditor.app"
[ -d "${APP}" ] || { echo "✗ archived app not found at ${APP}"; exit 1; }

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "▶ Signing with: ${SIGN_IDENTITY}"
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" "${APP}"
  codesign --verify --deep --strict "${APP}"
else
  echo "▷ SIGN_IDENTITY not set — keeping the archive's ad-hoc signature (local testing only)"
fi

echo "▶ Staging DMG"
rm -rf "${STAGE}"; mkdir -p "${STAGE}"
ditto "${APP}" "${STAGE}/TrueISFEditor.app"
ln -s /Applications "${STAGE}/Applications"
cp "${REPO}/LICENSE" "${STAGE}/LICENSE.txt"

# Friends-distribution path (decision 2026-07-14: no notarization). macOS quarantines any
# downloaded unsigned app and blocks the first launch — and macOS 15 removed the right-click→Open
# bypass — so the DMG carries first-launch instructions where a friend will actually see them.
cat > "${STAGE}/FIRST LAUNCH — READ ME.txt" <<'READIT'
TrueISFEditor — opening it the first time

This app is shared friend-to-friend and isn't notarized by Apple, so macOS
blocks the very first launch. Fix it once, either way below — after that it
opens like any other app.

The easy way:
  1. Drag TrueISFEditor.app into Applications.
  2. Open it once — macOS will refuse. That's expected.
  3. System Settings → Privacy & Security → scroll down → click "Open Anyway".
  4. Open it again. Done.

The Terminal way (instant):
  xattr -cr /Applications/TrueISFEditor.app
Then open the app normally.
READIT

rm -f "${DMG}"
hdiutil create -volname "TrueISFEditor ${VERSION}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" > /dev/null
echo "✓ DMG: ${DMG}"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▶ Notarizing (profile: ${NOTARY_PROFILE}) — this can take a few minutes"
  xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
  echo "▶ Stapling"
  xcrun stapler staple "${DMG}"
  echo "✓ Notarized + stapled: ${DMG}"
else
  echo "▷ Not notarized (friends-distribution mode) — the DMG includes FIRST LAUNCH instructions"
  echo "  (Privacy & Security → Open Anyway, or: xattr -cr /Applications/TrueISFEditor.app)"
fi

echo "▶ Verify on a clean account: open the DMG, drag to /Applications, launch, import a"
echo "  Shadertoy URL, convert, preview, export, and load the export in VDMX."
