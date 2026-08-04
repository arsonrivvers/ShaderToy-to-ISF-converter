# Security Policy

## Reporting

Report suspected vulnerabilities via [GitHub Security Advisories](https://github.com/arsonrivvers/ShaderToy-to-ISF-converter/security/advisories/new)
(preferred) or by opening an issue asking for a private contact — please don't post exploit details
in a public issue.

## What the apps do with your data

This repo ships **two** applications. Unless a bullet names ARShader, it describes TrueISFEditor.

### TrueISFEditor

- **Camera:** filter shaders auto-load the webcam as their image source. Frames are processed
  locally on the GPU and are never transmitted anywhere. The capture session stops itself when
  nothing is sampling it.
- **ShaderAssist / Remix (AI):** shader text is sent only to your own locally installed `claude`
  CLI, on your own subscription. The CLI is invoked with all tools disabled
  (`--tools "" --allowedTools ""` etc.), so the model performs a pure text-in/text-out transform:
  no file reads, no shell, no network actions driven by model output. Shader source is treated as
  untrusted data — instructions embedded in shader comments are explicitly out-of-contract.
- **Shadertoy API key (optional):** stored only in the macOS Keychain
  (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never on disk or in the repo.
- The app makes no network requests of its own except fetching a Shadertoy page/API when you ask
  it to import a shader.

### ARShader

ARShader is the live performance instrument (`App/ARShader/`). It is a local renderer: it loads
ISF shaders from disk, composites them, and draws to your screen.

- **Camera:** same as above — filter shaders may open the webcam, frames stay on the GPU, and the
  capture session stops when nothing samples it.
- **Network: none.** ARShader makes no network requests at all. It has no importer, no AI provider,
  and no telemetry.
- **Agent capture surface (`InstrumentControlFacade`): DEBUG-only, and it serves nothing.** Debug
  builds can expose a read-only capture of the instrument's own program and deck output to a local
  agent tool. Three things bound it: the entire file is fenced `#if DEBUG && SPYGLASS`, so it is
  absent from Release; the `SPYGLASS` condition is defined only by `App/spyglass-local.yml`, an
  optional overlay that a clean clone does not apply, so a clone built from this repo does not
  compile it at all; and nothing in the app opens a socket, starts a listener, or instantiates a
  transport — the shipped binary links no networking stack. The surface is a capture *provider*,
  not a server.
- **Presets and shaders** are read from and written to your own disk only.
