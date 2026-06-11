// Entry bundled by esbuild into App/TrueISFEditor/Resources/cm.bundle.js.
// Exposes a minimal global API the code-editor.html harness drives from Swift.
import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { cpp } from "@codemirror/lang-cpp";
import { setDiagnostics } from "@codemirror/lint";
import { hoverTooltip } from "@codemirror/view";
import { oneDark } from "@codemirror/theme-one-dark";
import { autocompletion } from "@codemirror/autocomplete";

// Autocomplete sources: ISF builtins (window.__symbols, from symbols.json), the shader's own declared
// input names (window.__inputNames, pushed live from Swift), and a static GLSL keyword/builtin list.
const GLSL_KEYWORDS = ["void","float","int","bool","vec2","vec3","vec4","mat2","mat3","mat4",
  "return","if","else","for","while","const","in","out","inout","struct","break","continue",
  "discard","true","false","uniform","sampler2D"];
const GLSL_BUILTINS = ["sin","cos","tan","asin","acos","atan","pow","exp","log","exp2","log2",
  "sqrt","inversesqrt","abs","sign","floor","ceil","fract","mod","min","max","clamp","mix","step",
  "smoothstep","length","distance","dot","cross","normalize","reflect","refract","radians","degrees"];

function isfCompletions(context) {
  const word = context.matchBefore(/[A-Za-z_][A-Za-z0-9_]*/);
  if (!word || (word.from === word.to && !context.explicit)) return null;
  const options = [];
  const symbols = window.__symbols || {};
  for (const name in symbols) {
    const s = symbols[name];
    options.push({ label: name, type: "function", detail: s.signature, info: s.summary });
  }
  (window.__inputNames || []).forEach((n) => options.push({ label: n, type: "variable", detail: "input" }));
  GLSL_KEYWORDS.forEach((k) => options.push({ label: k, type: "keyword" }));
  GLSL_BUILTINS.forEach((b) => options.push({ label: b, type: "function" }));
  return { from: word.from, options };
}

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
        autocompletion({ override: [isfCompletions], activateOnTyping: true }),
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
