// Entry bundled by esbuild into App/TrueISFEditor/Resources/cm.bundle.js.
// Exposes a minimal global API the code-editor.html harness drives from Swift.
import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { cpp } from "@codemirror/lang-cpp";
import { setDiagnostics } from "@codemirror/lint";
import { hoverTooltip } from "@codemirror/view";
import { oneDark } from "@codemirror/theme-one-dark";

// Inline symbol lookup: hover an identifier; if it's in window.__symbols (set by the harness
// from the bundled symbols.json), show its signature + summary. Pure local lookup, no round-trip.
const symbolHover = hoverTooltip((view, pos) => {
  const { from, to, text } = view.state.doc.lineAt(pos);
  const word = /[A-Za-z_][A-Za-z0-9_]*/;
  let start = pos, end = pos;
  while (start > from && word.test(text[start - from - 1])) start--;
  while (end < to && word.test(text[end - from])) end++;
  if (start === end) return null;
  const name = text.slice(start - from, end - from);
  const sym = (window.__symbols || {})[name];
  if (!sym) return null;
  return {
    pos: start, end, above: true,
    create() {
      const dom = document.createElement("div");
      dom.className = "cm-symbol-tooltip";
      dom.style.padding = "4px 8px";
      dom.style.maxWidth = "320px";
      const sig = document.createElement("div");
      sig.style.fontWeight = "600";
      sig.textContent = sym.signature;
      const sum = document.createElement("div");
      sum.style.opacity = "0.8";
      sum.style.marginTop = "2px";
      sum.textContent = sym.summary;
      dom.appendChild(sig); dom.appendChild(sum);
      return { dom };
    },
  };
});

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
        symbolHover,
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
