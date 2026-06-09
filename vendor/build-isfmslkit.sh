#!/usr/bin/env bash
set -euo pipefail
# One-time build of ISFMSLKit + framework deps into vendor/prebuilt/.
# Re-run only to update the kit. Output binaries are committed to the repo.
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/_isfmslkit-build"
OUT="$HERE/prebuilt"
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"

# 1. Clone + recursive submodules (VVMetalKit, PINCache, ISFGLSLGenerator; transpiler dylibs ship in extern/)
git clone --depth 1 https://github.com/mrRay/ISFMSLKit.git "$WORK/ISFMSLKit"
git -C "$WORK/ISFMSLKit" submodule update --init --recursive

# 2. Xcode 26 environment (each blocks the build if missing)
xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain || true   # already present on this machine; no-op
command -v cmake >/dev/null || brew install cmake

# 3. Patch the Vidvox codesign identity to ad-hoc (their signing identity is not present)
BUILD_SCRIPT="$(find "$WORK/ISFMSLKit" -name 'ISFGLSLGenerator_build_script.sh' | head -1)"
if [ -n "${BUILD_SCRIPT:-}" ]; then
  sed -i '' -E 's#codesign .*Developer ID Application: Vidvox, LLC.*#codesign -f -s - "$FRAMEWORK" || true#' "$BUILD_SCRIPT" || true
fi

# 4. Build frameworks (no signing during build; we sign after)
WORKSPACE="$(find "$WORK/ISFMSLKit" -maxdepth 2 -name 'ISFMSLKit.xcworkspace' | head -1)"
xcodebuild -workspace "$WORKSPACE" \
  -scheme ISFMSLKit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$WORK/dd" \
  CODE_SIGNING_ALLOWED=NO build

# 5. Collect the 4 frameworks (Syphon intentionally omitted)
PRODUCTS="$WORK/dd/Build/Products/Debug"
for fw in ISFMSLKit VVMetalKit PINCache PINOperation; do
  if [ -d "$PRODUCTS/$fw.framework" ]; then
    rm -rf "$OUT/$fw.framework"
    ditto "$PRODUCTS/$fw.framework" "$OUT/$fw.framework"
  else
    echo "WARN: $fw.framework not found in $PRODUCTS"
  fi
done

# 6. Pre-sign nested transpiler dylibs (otherwise app embed-codesign fails:
#    "code object is not signed at all in subcomponent")
find "$OUT/ISFMSLKit.framework" -name '*.dylib' -print0 2>/dev/null | while IFS= read -r -d '' dylib; do
  codesign -f -s - "$dylib"
done

git -C "$WORK/ISFMSLKit" rev-parse HEAD > "$OUT/.isfmslkit-source-sha"
echo "Done. Frameworks in $OUT"
ls -d "$OUT"/*.framework 2>/dev/null || echo "NO FRAMEWORKS PRODUCED"
