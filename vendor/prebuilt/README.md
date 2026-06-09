# vendor/prebuilt — ISFMSLKit framework binaries

Built once by `../build-isfmslkit.sh`. Committed binaries; do not hand-edit.

- Source: https://github.com/mrRay/ISFMSLKit @ `cac7d662c73d9e40e80a69b24a9bdb880fd8f197`
- Built: 2026-06-09, Xcode 26.1.1 (17B100), macOS 26.1 SDK, Debug, universal (arm64+x86_64),
  `CODE_SIGNING_ALLOWED=NO` + ad-hoc nested-dylib signing.
- Frameworks: ISFMSLKit, VVMetalKit, PINCache, PINOperation.
  (Syphon intentionally excluded — no Syphon output in P1.5.)
- Nested transpiler dylibs inside `ISFMSLKit.framework/Versions/A/Frameworks/`
  (`libGLSLangValidatorLib`, `libSPIRVCrossLib`, `libISFGLSLGenerator`) are ad-hoc signed so the app's
  embed-codesign passes.
- Real API reference: `docs/superpowers/notes/2026-06-09-isfmslkit-real-api.md`.

To update: re-run `../build-isfmslkit.sh` and commit the changed binaries.
