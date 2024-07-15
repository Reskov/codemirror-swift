import * as CodeMirror from "codemirror";
import { javascript } from "@codemirror/lang-javascript";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { indentWithTab } from "@codemirror/commands";
import { json, jsonParseLinter } from "@codemirror/lang-json";
import { linter, lintGutter } from "@codemirror/lint"
import { xml } from "@codemirror/lang-xml";
import { python } from "@codemirror/lang-python";
import { yaml } from "@codemirror/lang-yaml";
import { PostgreSQL, sql } from "@codemirror/lang-sql";
import {foldGutter, codeFolding, syntaxTree} from "@codemirror/language"
import { oneDark } from "@codemirror/theme-one-dark";

import {
  lineNumbers,
  highlightActiveLineGutter,
  highlightSpecialChars,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
  highlightActiveLine,
  keymap,
} from "@codemirror/view";

import {
  indentOnInput,
  syntaxHighlighting,
  defaultHighlightStyle,
  bracketMatching,
  foldKeymap,
} from "@codemirror/language";

import { history, defaultKeymap, historyKeymap } from "@codemirror/commands";
import { search, openSearchPanel, closeSearchPanel, searchPanelOpen, highlightSelectionMatches, searchKeymap } from "@codemirror/search";
import {
  closeBrackets,
  autocompletion,
  closeBracketsKeymap,
  completionKeymap,
} from "@codemirror/autocomplete";

const theme = new Compartment();
const language = new Compartment();
const listener = new Compartment();
const readOnly = new Compartment();
const lineWrapping = new Compartment();
const SUPPORTED_LANGUAGES_MAP = {
  javascript,
  json: () => [json(), lintGutter(), linter(jsonParseLinter())],
  yaml,
  python,
  xml,
  sql: () =>  sql({ dialect: PostgreSQL, upperCaseKeywords: true }),
  txt: () => [],
};

const baseTheme = EditorView.baseTheme({
  "&light": {
    backgroundColor: "white", // the default codemirror light theme doesn't set this up
    "color-scheme": "light",
  },
  "&dark": {
    "color-scheme": "dark",
  },
});

const editorView = new CodeMirror.EditorView({
  doc: "",
  extensions: [
    search({top: true}),
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    indentOnInput(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    bracketMatching(),
    closeBrackets(),
    autocompletion(),
    rectangularSelection(),
    crosshairCursor(),
    highlightActiveLine(),
    highlightSelectionMatches(),
    keymap.of([
      ...closeBracketsKeymap,
      ...defaultKeymap,
      ...searchKeymap,
      ...historyKeymap,
      ...foldKeymap,
      ...completionKeymap,
      indentWithTab,
    ]),
    readOnly.of([]),
    lineWrapping.of([]),
    baseTheme,
    theme.of(oneDark),
    language.of([]),
    listener.of([]),
    foldGutter(),
    codeFolding({
        preparePlaceholder: preparePlaceholder,
        placeholderDOM: placeholderDOM
    })
  ],
  parent: document.body,
});


editorView.dom.addEventListener('focus', () => {
  editorView.dom.classList.remove('cm-no-first-line-highlight');
}, true);

// Search
// Ctrl-F / Cmd-F
// Start searching
// Ctrl-G / Cmd-G
// Find next
// Shift-Ctrl-G / Shift-Cmd-G
// Find previous
// Shift-Ctrl-F / Cmd-Option-F
// Replace
// Shift-Ctrl-R / Shift-Cmd-Option-F
// Replace all
// Alt-F
// Persistent search (dialog doesn't autoclose, enter to find next, Shift-Enter to find previous)
// Alt-G
// Jump to line

// https://github.com/codemirror/language/commit/edb239d35b66608c1e7f9ed37a27b571ecdf9907
// https://github.com/codemirror/language/blob/main/src/fold.ts
// Ctrl-Shift-[ (Cmd-Alt-[ on macOS): foldCode.
// Ctrl-Shift-] (Cmd-Alt-] on macOS): unfoldCode.
// Ctrl-Alt-[: foldAll.
// Ctrl-Alt-]: unfoldAll.
function preparePlaceholder(state, range) {
    const from = range.from;
    const to = range.to;
    const doc = state.doc;
    let count;
    let isObject = true;
    const internal = doc.sliceString(from, to);
    const plugin = language.get(state);
    const languageObject = Array.isArray(plugin) ? plugin[0] : plugin;
    const lang = languageObject.language.name;
    
    if (!["python", "javascript", "json"].includes(lang)) {
        // yaml todo
        return '\u2194';
    }

    // Determine if it's an object/dict or array/list
    const prevLine = doc.lineAt(from).text;
    if (prevLine.trim().endsWith(':') || prevLine.includes('{') || prevLine.includes('dict(')) {
        isObject = true;
    } else if (prevLine.includes('[') || prevLine.includes('list(')) {
        isObject = false;
    }

    let parsableContent = internal;

    if (lang === "python") {
        parsableContent = parsableContent
            .replace(/'/g, '"')  // Replace single quotes with double quotes
            .replace(/None/g, 'null')  // Replace None with null
            .replace(/True/g, 'true')  // Replace True with true
            .replace(/False/g, 'false')  // Replace False with false
            .replace(/,\s*}/g, '}')  // Remove trailing commas in objects
            .replace(/,\s*]/g, ']')  // Remove trailing commas in arrays
            .replace(/([{,]\s*)(\w+):/g, '$1"$2":');  // Add quotes to keys
    } else if (lang === "yaml") {
        // Convert YAML to JSON-like structure
        parsableContent = parsableContent
            .split('\n')
            .map(line => line.trim())
            .filter(line => line && !line.startsWith('#'))
            .map(line => line.replace(/^(\s*-\s*)/g, ''))
            .join(',');

        if (isObject) {
            parsableContent = '{' + parsableContent + '}';
        } else {
            parsableContent = '[' + parsableContent + ']';
        }
    }

    // Try parsing
    try {
        const parsed = JSON.parse(isObject && lang !== "yaml" ? `{${parsableContent}}` : `[${parsableContent}]`);
        count = isObject ? Object.keys(parsed).length : parsed.length;
    } catch (e) {
        // If parsing fails, fall back to line counting
        const lines = internal.split('\n').map(line => line.trim()).filter(line => line && !line.startsWith('#'));

        if (isObject) {
            // Count key-value pairs for objects/dicts
            count = lines.filter(line => line.includes(':')).length;
        } else {
            // Count items for arrays/lists
            count = lines.length;
        }
    }

    if (count !== undefined) {
        return isObject ? `\u21A4${count} keys\u21A6` : `\u21A4${count} items\u21A6`;
    } else {
        return '\u2194';
    }
}


function placeholderDOM(view, onclick, prepared) {
    let { state } = view
    let element = document.createElement("span")
    element.textContent = prepared
    element.setAttribute("aria-label", state.phrase("folded code"))
    element.title = state.phrase("unfold")
    element.className = "cm-foldPlaceholder"
    element.onclick = onclick
    return element
}

function getSupportedLanguages() {
  return Object.keys(SUPPORTED_LANGUAGES_MAP);
}

function setDarkMode(active) {
  editorView.dispatch({
    effects: theme.reconfigure(active ? [oneDark] : []),
  });
}

function toggleSearchPanel() {
  if (searchPanelOpen(editorView.state)) {
    closeSearchPanel(editorView);
  } else {
    openSearchPanel(editorView);
  }
}

function setLanguage(lang) {
  let langFn = SUPPORTED_LANGUAGES_MAP[lang];

  editorView.dispatch({
    effects: language.reconfigure(langFn ? langFn() : []),
  });
}

function setContent(text) {
    editorView.dispatch({
        changes: { from: 0, to: editorView.state.doc.length, insert: text },
        //selection: {anchor: text.length-1, head:text.length-1 },
      });
    editorView.dom.classList.add('cm-no-first-line-highlight');
}

function getContent() {
  return editorView.state.doc.toString();
}

function setListener(fn) {
  editorView.dispatch({
    effects: listener.reconfigure(
      EditorView.updateListener.of((v) => {
        if (v.docChanged) {
          fn();
        }
      })
    ),
  });
}

function setReadOnly(value) {
  editorView.dispatch({
    effects: readOnly.reconfigure(value ? EditorState.readOnly.of(true) : []),
  });
}

function setLineWrapping(enabled) {
  editorView.dispatch({
    effects: lineWrapping.reconfigure(enabled ? EditorView.lineWrapping : []),
  });
}

export {
  setDarkMode,
  setLanguage,
  getSupportedLanguages,
  setContent,
  getContent,
  setListener,
  setReadOnly,
  setLineWrapping,
  editorView,
  toggleSearchPanel,
};
