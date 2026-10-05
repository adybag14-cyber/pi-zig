//! Original upstream extension input; its evaluated byte digest is regression-tested.
pub const upstream_commit = "031b24aa6425067253cb94095fb806a9df9d619c";
pub const source_sha256 = "4742283930949fad1920359540aa9d42c833d2d24eaa49564bfc08f90e328b0d";
pub const source: []const u8 =
    "/**\n" ++
    " * Modal Editor - vim-like modal editing example\n" ++
    " *\n" ++
    " * Usage: pi --extension ./examples/extensions/modal-editor.ts\n" ++
    " *\n" ++
    " * - Escape: insert → normal mode (in normal mode, aborts agent)\n" ++
    " * - i: normal → insert mode\n" ++
    " * - hjkl: navigation in normal mode\n" ++
    " * - ctrl+c, ctrl+d, etc. work in both modes\n" ++
    " */\n" ++
    "\n" ++
    "import { CustomEditor, type ExtensionAPI } from \"@earendil-works/pi-coding-agent\";\n" ++
    "import { matchesKey, truncateToWidth, visibleWidth } from \"@earendil-works/pi-tui\";\n" ++
    "\n" ++
    "// Normal mode key mappings: key -> escape sequence (or null for mode switch)\n" ++
    "const NORMAL_KEYS: Record<string, string | null> = {\n" ++
    "\th: \"\\x1b[D\", // left\n" ++
    "\tj: \"\\x1b[B\", // down\n" ++
    "\tk: \"\\x1b[A\", // up\n" ++
    "\tl: \"\\x1b[C\", // right\n" ++
    "\t\"0\": \"\\x01\", // line start\n" ++
    "\t$: \"\\x05\", // line end\n" ++
    "\tx: \"\\x1b[3~\", // delete char\n" ++
    "\ti: null, // insert mode\n" ++
    "\ta: null, // append (insert + right)\n" ++
    "};\n" ++
    "\n" ++
    "class ModalEditor extends CustomEditor {\n" ++
    "\tprivate mode: \"normal\" | \"insert\" = \"insert\";\n" ++
    "\n" ++
    "\thandleInput(data: string): void {\n" ++
    "\t\t// Escape toggles to normal mode, or passes through for app handling\n" ++
    "\t\tif (matchesKey(data, \"escape\")) {\n" ++
    "\t\t\tif (this.mode === \"insert\") {\n" ++
    "\t\t\t\tthis.mode = \"normal\";\n" ++
    "\t\t\t} else {\n" ++
    "\t\t\t\tsuper.handleInput(data); // abort agent, etc.\n" ++
    "\t\t\t}\n" ++
    "\t\t\treturn;\n" ++
    "\t\t}\n" ++
    "\n" ++
    "\t\t// Insert mode: pass everything through\n" ++
    "\t\tif (this.mode === \"insert\") {\n" ++
    "\t\t\tsuper.handleInput(data);\n" ++
    "\t\t\treturn;\n" ++
    "\t\t}\n" ++
    "\n" ++
    "\t\t// Normal mode: check mapped keys\n" ++
    "\t\tif (data in NORMAL_KEYS) {\n" ++
    "\t\t\tconst seq = NORMAL_KEYS[data];\n" ++
    "\t\t\tif (data === \"i\") {\n" ++
    "\t\t\t\tthis.mode = \"insert\";\n" ++
    "\t\t\t} else if (data === \"a\") {\n" ++
    "\t\t\t\tthis.mode = \"insert\";\n" ++
    "\t\t\t\tsuper.handleInput(\"\\x1b[C\"); // move right first\n" ++
    "\t\t\t} else if (seq) {\n" ++
    "\t\t\t\tsuper.handleInput(seq);\n" ++
    "\t\t\t}\n" ++
    "\t\t\treturn;\n" ++
    "\t\t}\n" ++
    "\n" ++
    "\t\t// Pass control sequences (ctrl+c, etc.) to super, ignore printable chars\n" ++
    "\t\tif (data.length === 1 && data.charCodeAt(0) >= 32) return;\n" ++
    "\t\tsuper.handleInput(data);\n" ++
    "\t}\n" ++
    "\n" ++
    "\trender(width: number): string[] {\n" ++
    "\t\tconst lines = super.render(width);\n" ++
    "\t\tif (lines.length === 0) return lines;\n" ++
    "\n" ++
    "\t\t// Add mode indicator to bottom border\n" ++
    "\t\tconst label = this.mode === \"normal\" ? \" NORMAL \" : \" INSERT \";\n" ++
    "\t\tconst last = lines.length - 1;\n" ++
    "\t\tif (visibleWidth(lines[last]!) >= label.length) {\n" ++
    "\t\t\tlines[last] = truncateToWidth(lines[last]!, width - label.length, \"\") + label;\n" ++
    "\t\t}\n" ++
    "\t\treturn lines;\n" ++
    "\t}\n" ++
    "}\n" ++
    "\n" ++
    "export default function (pi: ExtensionAPI) {\n" ++
    "\tpi.on(\"session_start\", (_event, ctx) => {\n" ++
    "\t\tctx.ui.setEditorComponent((tui, theme, kb) => new ModalEditor(tui, theme, kb));\n" ++
    "\t});\n" ++
    "}\n";
