# Security Policy

## Reporting

Report suspected vulnerabilities via [GitHub Security Advisories](https://github.com/arsonrivvers/ShaderToy-to-ISF-converter/security/advisories/new)
(preferred) or by opening an issue asking for a private contact — please don't post exploit details
in a public issue.

## What the app does with your data

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
