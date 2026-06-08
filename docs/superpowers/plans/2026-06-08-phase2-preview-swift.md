# Phase 2 — Swift Preview Integration — Plan

> Builds the app-side of the live preview. Harness (`isf-preview.html`) + bundle (`isf.bundle.js`)
> are committed and validated in real WebGL. This wires them into the SwiftUI app.

**Goal:** A live preview pane that renders the converted/edited ISF, surfaces compile errors in-app,
and shows live controls generated from the ISF INPUTS.

## Resource bundling (project.yml)

The harness + bundle + license live in `App/ShadertoyISF/Resources/`. Ensure they're copied into the
app bundle. In `App/project.yml`, under the `ShadertoyISF` target, add an explicit resources entry so
the folder is a Copy-Bundle-Resources input (xcodegen treats known non-source types as resources, but
make it explicit):
```yaml
    sources:
      - path: ShadertoyISF
      - path: ShadertoyISF/Resources
        buildPhase: resources
```
After build, verify: `ls App/ddata/Build/Products/Debug/ShadertoyISF.app/Contents/Resources/ | grep -E 'isf-preview.html|isf.bundle.js'` → both present.

## Task 1 — `ISFPreviewController` (WKWebView bridge)

Create `App/ShadertoyISF/ISFPreviewController.swift`:
```swift
import Foundation
import WebKit
import Combine

struct ISFPreviewInput: Identifiable, Equatable {
    let name: String
    let type: String          // "float","bool","color","point2D","long","image","event"
    let defaultValue: Any?
    let min: Any?
    let max: Any?
    var id: String { name }
    static func == (l: ISFPreviewInput, r: ISFPreviewInput) -> Bool { l.name == r.name && l.type == r.type }
}

@MainActor
final class ISFPreviewController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var compileValid = false
    @Published var compileError: String?
    @Published var compileErrorLine: Int?
    @Published var inputs: [ISFPreviewInput] = []

    let webView: WKWebView
    private var ready = false
    private var pendingISF: String?

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "isf")
        webView.navigationDelegate = self
        if let url = Bundle.main.url(forResource: "isf-preview", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// Render an ISF source string. Queues until the harness reports ready.
    func load(isf: String) {
        guard ready else { pendingISF = isf; return }
        guard let lit = jsStringLiteral(isf) else { return }
        webView.evaluateJavaScript("loadISF(\(lit));", completionHandler: nil)
    }

    func setInput(_ name: String, _ jsonValue: String) {
        guard let nameLit = jsStringLiteral(name) else { return }
        webView.evaluateJavaScript("setInput(\(nameLit), \(jsonValue));", completionHandler: nil)
    }

    private func jsStringLiteral(_ s: String) -> String? {
        // JSONEncoder turns a String into a valid, fully-escaped JS string literal.
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            if let p = pendingISF { pendingISF = nil; load(isf: p) }
        case "compile":
            compileValid = (dict["valid"] as? Bool) ?? false
            compileError = dict["error"] as? String
            compileErrorLine = dict["errorLine"] as? Int
            inputs = (dict["inputs"] as? [[String: Any]])?.map {
                ISFPreviewInput(name: $0["NAME"] as? String ?? "",
                                type: $0["TYPE"] as? String ?? "",
                                defaultValue: $0["DEFAULT"], min: $0["MIN"], max: $0["MAX"])
            } ?? []
        case "runtime":
            compileError = dict["error"] as? String
        default: break
        }
    }
}
```

## Task 2 — `ISFPreviewView` (NSViewRepresentable)

Create `App/ShadertoyISF/ISFPreviewView.swift`:
```swift
import SwiftUI
import WebKit

struct ISFPreviewView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
```

## Task 3 — `PreviewControlsView` (live sliders from inputs)

Create `App/ShadertoyISF/Views/PreviewControlsView.swift`. For each input, render a control and call
`controller.setInput(name, <json>)` on change. Support float/bool/color/point2D/long; show a disabled
label for image/event. Keep per-input values in a local `@State var values: [String: Double]` (floats),
`[String: Bool]`, `[String: [Double]]` (point2D/color) seeded from defaults. JSON values:
- float → `"\(v)"`
- bool → `"true"`/`"false"`
- point2D → `"[\(x), \(y)]"`
- color → `"[\(r), \(g), \(b), \(a)]"`
- long → `"\(intValue)"`

```swift
import SwiftUI

struct PreviewControlsView: View {
    @ObservedObject var controller: ISFPreviewController
    @State private var floats: [String: Double] = [:]
    @State private var bools: [String: Bool] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if controller.inputs.isEmpty {
                    Text("No adjustable inputs").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(controller.inputs) { input in
                    switch input.type {
                    case "float":
                        let lo = (input.min as? Double) ?? 0, hi = (input.max as? Double) ?? 1
                        let binding = Binding<Double>(
                            get: { floats[input.name] ?? (input.defaultValue as? Double) ?? lo },
                            set: { floats[input.name] = $0; controller.setInput(input.name, "\($0)") })
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.name).font(.caption)
                            Slider(value: binding, in: lo...hi)
                        }
                    case "bool":
                        let binding = Binding<Bool>(
                            get: { bools[input.name] ?? (input.defaultValue as? Bool ?? false) },
                            set: { bools[input.name] = $0; controller.setInput(input.name, $0 ? "true" : "false") })
                        Toggle(input.name, isOn: binding).font(.caption)
                    default:
                        Text("\(input.name) (\(input.type))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```
(point2D/color/long may be added the same way; float+bool cover the v1 essentials and our converter's
typical output. Keep this file focused.)

## Task 4 — ContentView integration

In `App/ShadertoyISF/ContentView.swift`:
- Add `@StateObject private var preview = ISFPreviewController()`.
- Make the main split three panes: imported · ISF output · preview. Right pane =
  `VStack { ISFPreviewView(webView: preview.webView); PreviewControlsView(controller: preview) }`.
- Show the preview compile status: if `preview.compileError != nil && !preview.compileValid`, show a red
  banner `Preview: <error first line> (line \(preview.compileErrorLine ?? -1))`; else a green
  "Preview: compiles" when `compileValid`.
- **Debounced render:** add `.onChange(of: model.isfOutput) { scheduleRender() }` and call
  `preview.load(isf: model.isfOutput)` after a 400ms debounce (store a `Task` in `@State`, cancel + sleep).
  Also call `preview.load(isf:)` once when output first becomes non-empty.

```swift
    @State private var renderTask: Task<Void, Never>?
    private func scheduleRender() {
        renderTask?.cancel()
        let isf = model.isfOutput
        guard !isf.isEmpty else { return }
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            preview.load(isf: isf)
        }
    }
```

## Task 5 — Verify (real app, not xctest)

WKWebView WebGL works in the real entitled app, not in bare xctest. Add a debug hook in
`ShadertoyISFApp.init()` (alongside the existing `SHADERTOY_DEBUG_FETCH`): if
`SHADERTOY_DEBUG_PREVIEW=1`, instantiate an `ISFPreviewController`, after a short delay `load(isf:)` a
known-good ISF then a known-bad (`tanh` without polyfill), print the posted `compileValid`/`compileError`,
and `exit(0)`. Run the built binary with that env and confirm: good → valid true; bad → valid false with
a `tanh` message. (Driving via the real app binary, as we did for the fetcher.)

Then build, refresh the project-root app copy, and manual-check: convert a shader → preview renders;
introduce a deliberate error in the ISF output text → red "Preview" banner appears.

## Commit
Group sensibly (controller+view, controls, integration, project.yml). Do not commit generated
.xcodeproj/ddata.
