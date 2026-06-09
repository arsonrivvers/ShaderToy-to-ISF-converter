// Entry bundled by esbuild into App/TrueISFEditor/Resources/cm.bundle.js.
// Exposes a minimal global API the code-editor.html harness drives from Swift.
import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { cpp } from "@codemirror/lang-cpp";
import { setDiagnostics } from "@codemirror/lint";
import { oneDark } from "@codemirror/theme-one-dark";

// GLSL is close enough to C/C++ for highlighting; the ISF /*{ ... }*/ JSON header
// renders as a block comment, which is acceptable for P1.
window.__createEditor = function (parent, initialDoc, onChange) {
  return new EditorView({
    parent,
    state: EditorState.create({
      doc: initialDoc || "",
      extensions: [
        basicSetup,
        cpp(),
        oneDark,
        EditorView.lineWrapping,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) onChange(u.state.doc.toString());
        }),
      ],
    }),
  });
};

// (view, diagnostics) -> transaction; harness maps line numbers to ranges first.
window.__cmSetDiagnostics = setDiagnostics;
