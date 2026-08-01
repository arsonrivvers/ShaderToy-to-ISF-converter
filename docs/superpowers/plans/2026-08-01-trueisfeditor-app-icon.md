# TrueISFEditor App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate three TrueISFEditor icon concepts, select the strongest, and install a complete macOS AppIcon asset set.

**Architecture:** Use the built-in image generator for three square concept masters. After user selection, preserve the chosen 1024 × 1024 PNG as the source of truth and derive Xcode's required raster sizes from it without changing the artwork.

**Tech Stack:** Built-in image generation, PNG, macOS `sips`, Xcode asset catalogs

## Global Constraints

- Use a current macOS rounded-square application-icon silhouette.
- Keep important artwork inside a generous safe area.
- The icon must remain readable at 32 × 32 pixels.
- Use exact, unambiguous typography and no watermark.
- Do not alter ARShader branding or create a broader identity system.

---

### Task 1: Generate and review the concept set

**Files:**
- Create: `tmp/trueisfeditor-icon-options/trueisf-isf-monogram.png`
- Create: `tmp/trueisfeditor-icon-options/trueisf-shader-window.png`
- Create: `tmp/trueisfeditor-icon-options/trueisf-type-stack.png`

**Interfaces:**
- Consumes: approved icon design spec
- Produces: three 1024 × 1024 visual options suitable for side-by-side review

- [ ] **Step 1: Generate the ISF monogram concept**

  Generate a centered macOS rounded-square icon with large, exact `ISF` lettering and a restrained violet-to-cyan shader field.

- [ ] **Step 2: Generate the shader-window concept**

  Generate a centered macOS rounded-square icon using a minimal preview window, flowing shader field, and simple brace symbolism.

- [ ] **Step 3: Generate the True / ISF stack concept**

  Generate a centered macOS rounded-square icon with exact `True` and `ISF` text stacked in two lines.

- [ ] **Step 4: Validate and present**

  Inspect all three at full size and at 32 × 32. Reject any image with misspelled text, ambiguous letterforms, unsafe cropping, watermarking, or illegibility. Present all passing concepts inline.

### Task 2: Install the selected icon

**Files:**
- Create: `App/TrueISFEditor/Assets.xcassets/Contents.json`
- Create: `App/TrueISFEditor/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `App/TrueISFEditor/Assets.xcassets/AppIcon.appiconset/*.png`
- Modify: `project.yml`

**Interfaces:**
- Consumes: the user-selected 1024 × 1024 master from Task 1
- Produces: an Xcode AppIcon asset catalog referenced by the TrueISFEditor target

- [ ] **Step 1: Create the asset-catalog metadata**

  Add a standard macOS AppIcon set covering 16, 32, 128, 256, and 512 point sizes at 1× and 2× scale.

- [ ] **Step 2: Derive raster sizes**

  Use `sips -z <pixels> <pixels> <master> --out <destination>` for 16, 32, 64, 128, 256, 512, and 1024 pixel outputs. Do not regenerate or restyle between sizes.

- [ ] **Step 3: Wire the catalog into the app target**

  Ensure the generated Xcode project includes the asset catalog and sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` for TrueISFEditor.

- [ ] **Step 4: Verify the packaged icon**

  Regenerate the project, build TrueISFEditor, inspect the built `.app` resources, and confirm the packaged icon is not the generic fallback.

- [ ] **Step 5: Commit**

  Stage only the asset catalog, project configuration, and this task's generated icon files, then commit them with a focused message.

## Self-Review

- Spec coverage: format, three directions, small-size legibility, selection, master, and complete AppIcon output are covered.
- Placeholder scan: no unresolved placeholder instructions.
- Interface consistency: Task 2 consumes exactly one 1024 × 1024 PNG selected from Task 1.
