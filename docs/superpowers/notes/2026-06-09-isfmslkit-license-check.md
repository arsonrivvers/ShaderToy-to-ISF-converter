# ISFMSLKit transpiler — runtime license check (2026-06-09)

P1.5 open item from the handoff: "confirm glslang's GPL-3 component is build-tool-only, not in the
linked path" before any commercial distribution. This is a **distribution gate, not a build/dev blocker.**

## What is actually in the shipped runtime path
`TrueISFEditor.app` embeds `ISFMSLKit.framework`, whose binary links three dylibs at runtime
(`otool -L` → all `@rpath`), embedded under `ISFMSLKit.framework/Versions/A/Frameworks/`:

| Runtime dylib | Component | License (as found / known) |
|---|---|---|
| `libISFGLSLGenerator.dylib` | Vidvox's GLSL→generator wrapper | **BSD-3-Clause** (LICENSE.txt: "Copyright (c) 2025, Vidvox LLC") |
| ↳ bundles exprtk (header) | Arash Partow exprtk | **MIT** (license.txt verified) |
| ↳ bundles nlohmann_json | nlohmann/json | **MIT** (LICENSE.MIT verified) |
| `libGLSLangValidatorLib.dylib` | Khronos glslang (GLSL→SPIR-V) | prebuilt binary (see "Open item") |
| `libSPIRVCrossLib.dylib` | SPIRV-Cross (SPIR-V→MSL) | prebuilt binary (see "Open item") |

The app's own binary links only `@rpath` frameworks (ISFMSLKit/VVMetalKit/PINCache/PINOperation); the
transpiler dylibs are reached transitively through ISFMSLKit.

## Finding: no GPL anywhere in the vendored tree
A recursive search for `GPL` / `GNU General Public` across every `LICENSE*`, `*.txt`, `*.md` in the
ISFMSLKit clone + submodules + `extern/` returned **zero hits**. The "glslang GPL-3 component" concern
is **not substantiated** by anything present in what we actually ship. glslang's canonical upstream
license (KhronosGroup/glslang) is a mix of permissive terms (BSD-3-Clause / Apache-2.0 / MIT) with no
copyleft in the linked library; SPIRV-Cross upstream is Apache-2.0. Both are commercial-friendly.

## Open item before commercial distribution (NOT a blocker for dev)
glslang and SPIRV-Cross ship here as **prebuilt binaries** (`extern/GLSLangValidatorLib/bin/`,
`extern/SPIRVCrossLib/bin/`) with **no upstream LICENSE file in this tree**. Before distributing
commercially:
1. Obtain the upstream `LICENSE.txt` for KhronosGroup/glslang and KhronosGroup/SPIRV-Cross (the exact
   versions Vidvox built) and **bundle them as attribution** — BSD-3-Clause and Apache-2.0 both require
   reproducing the copyright/license in binary distributions.
2. Have @lib (Librarian) produce a **sourced** confirmation of those two upstream licenses with citations,
   rather than relying on this note's "known" column. (Per accuracy policy, the upstream terms are stated
   here as well-known but not first-party-verified, since the files aren't in our tree.)
3. Also bundle attribution for ISFGLSLGenerator (BSD-3-Clause), exprtk (MIT), nlohmann_json (MIT), and
   ISFMSLKit/VVMetalKit (MIT/BSD per their repos).

## Conclusion
No copyleft (GPL/LGPL) code was found in the runtime path; the transpiler stack is permissively licensed
and suitable for commercial distribution, **pending** the attribution-bundling + sourced upstream-license
confirmation above. Nothing here blocks continued development or testing.
