//! Native terminal-friendly LaTeX math renderer.
//!
//! This is an allocation-explicit Zig port of Pi's dependency-free LaTeX
//! renderer. Unsupported or malformed input returns null so callers can retain
//! the original source verbatim. Supported expressions cover the symbol and
//! operator vocabulary used by the original TUI, Unicode scripts, fractions,
//! roots, accents, text wrappers, aligned/cases/matrix environments, and
//! vertical display layouts.
const std = @import("std");
const terminal_text = @import("terminal_text.zig");

pub const Options = struct {
    display: bool = false,
};

const symbols = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alpha", "α" },
    .{ "beta", "β" },
    .{ "gamma", "γ" },
    .{ "delta", "δ" },
    .{ "epsilon", "ϵ" },
    .{ "varepsilon", "ε" },
    .{ "zeta", "ζ" },
    .{ "eta", "η" },
    .{ "theta", "θ" },
    .{ "vartheta", "ϑ" },
    .{ "iota", "ι" },
    .{ "kappa", "κ" },
    .{ "varkappa", "ϰ" },
    .{ "lambda", "λ" },
    .{ "mu", "μ" },
    .{ "nu", "ν" },
    .{ "xi", "ξ" },
    .{ "pi", "π" },
    .{ "varpi", "ϖ" },
    .{ "rho", "ρ" },
    .{ "varrho", "ϱ" },
    .{ "sigma", "σ" },
    .{ "varsigma", "ς" },
    .{ "tau", "τ" },
    .{ "upsilon", "υ" },
    .{ "phi", "ϕ" },
    .{ "varphi", "φ" },
    .{ "chi", "χ" },
    .{ "psi", "ψ" },
    .{ "omega", "ω" },
    .{ "Gamma", "Γ" },
    .{ "Delta", "Δ" },
    .{ "Theta", "Θ" },
    .{ "Lambda", "Λ" },
    .{ "Xi", "Ξ" },
    .{ "Pi", "Π" },
    .{ "Sigma", "Σ" },
    .{ "Upsilon", "Υ" },
    .{ "Phi", "Φ" },
    .{ "Psi", "Ψ" },
    .{ "Omega", "Ω" },
    .{ "pm", "±" },
    .{ "mp", "∓" },
    .{ "times", "×" },
    .{ "div", "÷" },
    .{ "cdot", "·" },
    .{ "ast", "∗" },
    .{ "star", "⋆" },
    .{ "circ", "∘" },
    .{ "bullet", "•" },
    .{ "oplus", "⊕" },
    .{ "ominus", "⊖" },
    .{ "otimes", "⊗" },
    .{ "oslash", "⊘" },
    .{ "odot", "⊙" },
    .{ "bigcirc", "○" },
    .{ "dagger", "†" },
    .{ "ddagger", "‡" },
    .{ "amalg", "⨿" },
    .{ "uplus", "⊎" },
    .{ "sqcap", "⊓" },
    .{ "sqcup", "⊔" },
    .{ "triangleleft", "◁" },
    .{ "triangleright", "▷" },
    .{ "wr", "≀" },
    .{ "cap", "∩" },
    .{ "cup", "∪" },
    .{ "bigcap", "⋂" },
    .{ "bigcup", "⋃" },
    .{ "bigwedge", "⋀" },
    .{ "bigvee", "⋁" },
    .{ "bigsqcup", "⨆" },
    .{ "biguplus", "⨄" },
    .{ "bigoplus", "⨁" },
    .{ "bigotimes", "⨂" },
    .{ "bigodot", "⨀" },
    .{ "setminus", "∖" },
    .{ "in", "∈" },
    .{ "notin", "∉" },
    .{ "ni", "∋" },
    .{ "subset", "⊂" },
    .{ "supset", "⊃" },
    .{ "subseteq", "⊆" },
    .{ "supseteq", "⊇" },
    .{ "sqsubset", "⊏" },
    .{ "sqsupset", "⊐" },
    .{ "sqsubseteq", "⊑" },
    .{ "sqsupseteq", "⊒" },
    .{ "prec", "≺" },
    .{ "preceq", "≼" },
    .{ "succ", "≻" },
    .{ "succeq", "≽" },
    .{ "ll", "≪" },
    .{ "gg", "≫" },
    .{ "le", "≤" },
    .{ "leq", "≤" },
    .{ "leqslant", "≤" },
    .{ "ge", "≥" },
    .{ "geq", "≥" },
    .{ "geqslant", "≥" },
    .{ "ne", "≠" },
    .{ "neq", "≠" },
    .{ "equiv", "≡" },
    .{ "approx", "≈" },
    .{ "sim", "∼" },
    .{ "simeq", "≃" },
    .{ "cong", "≅" },
    .{ "asymp", "≍" },
    .{ "doteq", "≐" },
    .{ "propto", "∝" },
    .{ "parallel", "∥" },
    .{ "perp", "⊥" },
    .{ "mid", "∣" },
    .{ "vdash", "⊢" },
    .{ "dashv", "⊣" },
    .{ "models", "⊨" },
    .{ "Vdash", "⊩" },
    .{ "Vvdash", "⊪" },
    .{ "nvdash", "⊬" },
    .{ "nvDash", "⊭" },
    .{ "forall", "∀" },
    .{ "exists", "∃" },
    .{ "nexists", "∄" },
    .{ "neg", "¬" },
    .{ "land", "∧" },
    .{ "wedge", "∧" },
    .{ "lor", "∨" },
    .{ "vee", "∨" },
    .{ "to", "→" },
    .{ "rightarrow", "→" },
    .{ "longrightarrow", "→" },
    .{ "leftarrow", "←" },
    .{ "longleftarrow", "←" },
    .{ "gets", "←" },
    .{ "leftrightarrow", "↔" },
    .{ "longleftrightarrow", "↔" },
    .{ "hookleftarrow", "↩" },
    .{ "hookrightarrow", "↪" },
    .{ "twoheadleftarrow", "↞" },
    .{ "twoheadrightarrow", "↠" },
    .{ "leftharpoonup", "↼" },
    .{ "leftharpoondown", "↽" },
    .{ "rightharpoonup", "⇀" },
    .{ "rightharpoondown", "⇁" },
    .{ "rightleftharpoons", "⇌" },
    .{ "leftrightharpoons", "⇋" },
    .{ "nearrow", "↗" },
    .{ "searrow", "↘" },
    .{ "swarrow", "↙" },
    .{ "nwarrow", "↖" },
    .{ "rightsquigarrow", "⇝" },
    .{ "leadsto", "⇝" },
    .{ "Rightarrow", "⇒" },
    .{ "Longrightarrow", "⇒" },
    .{ "Leftarrow", "⇐" },
    .{ "Longleftarrow", "⇐" },
    .{ "Leftrightarrow", "⇔" },
    .{ "Longleftrightarrow", "⇔" },
    .{ "implies", "⇒" },
    .{ "iff", "⇔" },
    .{ "mapsto", "↦" },
    .{ "longmapsto", "↦" },
    .{ "uparrow", "↑" },
    .{ "downarrow", "↓" },
    .{ "partial", "∂" },
    .{ "nabla", "∇" },
    .{ "int", "∫" },
    .{ "iint", "∬" },
    .{ "iiint", "∭" },
    .{ "oint", "∮" },
    .{ "sum", "∑" },
    .{ "prod", "∏" },
    .{ "coprod", "∐" },
    .{ "infty", "∞" },
    .{ "emptyset", "∅" },
    .{ "varnothing", "∅" },
    .{ "angle", "∠" },
    .{ "therefore", "∴" },
    .{ "because", "∵" },
    .{ "aleph", "ℵ" },
    .{ "beth", "ℶ" },
    .{ "gimel", "ℷ" },
    .{ "daleth", "ℸ" },
    .{ "top", "⊤" },
    .{ "bot", "⊥" },
    .{ "triangle", "△" },
    .{ "square", "□" },
    .{ "lozenge", "◊" },
    .{ "checkmark", "✓" },
    .{ "complement", "∁" },
    .{ "wp", "℘" },
    .{ "prime", "′" },
    .{ "ldots", "…" },
    .{ "dots", "…" },
    .{ "cdots", "⋯" },
    .{ "vdots", "⋮" },
    .{ "ddots", "⋱" },
    .{ "ell", "ℓ" },
    .{ "hbar", "ℏ" },
    .{ "Im", "ℑ" },
    .{ "Re", "ℜ" },
    .{ "langle", "⟨" },
    .{ "rangle", "⟩" },
    .{ "vert", "|" },
    .{ "lvert", "|" },
    .{ "rvert", "|" },
    .{ "Vert", "‖" },
    .{ "lVert", "‖" },
    .{ "rVert", "‖" },
    .{ "lbrace", "{" },
    .{ "rbrace", "}" },
    .{ "backslash", "\\" },
    .{ "lfloor", "⌊" },
    .{ "rfloor", "⌋" },
    .{ "lceil", "⌈" },
    .{ "rceil", "⌉" },
    .{ "colon", ":" },
});

const negated_symbols = std.StaticStringMap([]const u8).initComptime(.{
    .{ "<", "≮" },
    .{ ">", "≯" },
    .{ "=", "≠" },
    .{ "∈", "∉" },
    .{ "∋", "∌" },
    .{ "∣", "∤" },
    .{ "∥", "∦" },
    .{ "∼", "≁" },
    .{ "≃", "≄" },
    .{ "≅", "≇" },
    .{ "≈", "≉" },
    .{ "≡", "≢" },
    .{ "≤", "≰" },
    .{ "≥", "≱" },
    .{ "≺", "⊀" },
    .{ "≻", "⊁" },
    .{ "⊂", "⊄" },
    .{ "⊃", "⊅" },
    .{ "⊆", "⊈" },
    .{ "⊇", "⊉" },
    .{ "⊢", "⊬" },
    .{ "⊨", "⊭" },
    .{ "↔", "↮" },
    .{ "←", "↚" },
    .{ "→", "↛" },
    .{ "⇒", "⇏" },
    .{ "⇐", "⇍" },
    .{ "⇔", "⇎" },
    .{ "≼", "⋠" },
    .{ "≽", "⋡" },
});

const blackboard = std.StaticStringMap([]const u8).initComptime(.{
    .{ "C", "ℂ" },
    .{ "H", "ℍ" },
    .{ "N", "ℕ" },
    .{ "P", "ℙ" },
    .{ "Q", "ℚ" },
    .{ "R", "ℝ" },
    .{ "Z", "ℤ" },
});

const superscripts = std.StaticStringMap([]const u8).initComptime(.{
    .{ "0", "⁰" },
    .{ "1", "¹" },
    .{ "2", "²" },
    .{ "3", "³" },
    .{ "4", "⁴" },
    .{ "5", "⁵" },
    .{ "6", "⁶" },
    .{ "7", "⁷" },
    .{ "8", "⁸" },
    .{ "9", "⁹" },
    .{ "+", "⁺" },
    .{ "-", "⁻" },
    .{ "=", "⁼" },
    .{ "(", "⁽" },
    .{ ")", "⁾" },
    .{ "a", "ᵃ" },
    .{ "b", "ᵇ" },
    .{ "c", "ᶜ" },
    .{ "d", "ᵈ" },
    .{ "e", "ᵉ" },
    .{ "f", "ᶠ" },
    .{ "g", "ᵍ" },
    .{ "h", "ʰ" },
    .{ "i", "ⁱ" },
    .{ "j", "ʲ" },
    .{ "k", "ᵏ" },
    .{ "l", "ˡ" },
    .{ "m", "ᵐ" },
    .{ "n", "ⁿ" },
    .{ "o", "ᵒ" },
    .{ "p", "ᵖ" },
    .{ "r", "ʳ" },
    .{ "s", "ˢ" },
    .{ "t", "ᵗ" },
    .{ "u", "ᵘ" },
    .{ "v", "ᵛ" },
    .{ "w", "ʷ" },
    .{ "x", "ˣ" },
    .{ "y", "ʸ" },
    .{ "z", "ᶻ" },
});

const subscripts = std.StaticStringMap([]const u8).initComptime(.{
    .{ "0", "₀" },
    .{ "1", "₁" },
    .{ "2", "₂" },
    .{ "3", "₃" },
    .{ "4", "₄" },
    .{ "5", "₅" },
    .{ "6", "₆" },
    .{ "7", "₇" },
    .{ "8", "₈" },
    .{ "9", "₉" },
    .{ "+", "₊" },
    .{ "-", "₋" },
    .{ "=", "₌" },
    .{ "(", "₍" },
    .{ ")", "₎" },
    .{ "a", "ₐ" },
    .{ "e", "ₑ" },
    .{ "h", "ₕ" },
    .{ "i", "ᵢ" },
    .{ "j", "ⱼ" },
    .{ "k", "ₖ" },
    .{ "l", "ₗ" },
    .{ "m", "ₘ" },
    .{ "n", "ₙ" },
    .{ "o", "ₒ" },
    .{ "p", "ₚ" },
    .{ "r", "ᵣ" },
    .{ "s", "ₛ" },
    .{ "t", "ₜ" },
    .{ "u", "ᵤ" },
    .{ "v", "ᵥ" },
    .{ "x", "ₓ" },
});

const accents = std.StaticStringMap([]const u8).initComptime(.{
    .{ "acute", "́" },
    .{ "bar", "̅" },
    .{ "breve", "̆" },
    .{ "check", "̌" },
    .{ "ddot", "̈" },
    .{ "dot", "̇" },
    .{ "grave", "̀" },
    .{ "hat", "̂" },
    .{ "mathring", "̊" },
    .{ "overleftarrow", "⃖" },
    .{ "overleftrightarrow", "⃡" },
    .{ "overline", "̅" },
    .{ "overrightarrow", "⃗" },
    .{ "tilde", "̃" },
    .{ "underline", "̲" },
    .{ "vec", "⃗" },
    .{ "widehat", "̂" },
    .{ "widetilde", "̃" },
});

const named_operators = std.StaticStringMap(void).initComptime(.{
    .{"arccos"},
    .{"arcsin"},
    .{"arctan"},
    .{"arg"},
    .{"cos"},
    .{"cosh"},
    .{"cot"},
    .{"coth"},
    .{"csc"},
    .{"deg"},
    .{"det"},
    .{"dim"},
    .{"exp"},
    .{"gcd"},
    .{"hom"},
    .{"inf"},
    .{"ker"},
    .{"lg"},
    .{"lim"},
    .{"liminf"},
    .{"limsup"},
    .{"ln"},
    .{"log"},
    .{"max"},
    .{"min"},
    .{"Pr"},
    .{"sec"},
    .{"sin"},
    .{"sinh"},
    .{"sup"},
    .{"tan"},
    .{"tanh"},
});

const limit_operators = std.StaticStringMap(void).initComptime(.{
    .{"argmax"},
    .{"argmin"},
    .{"inf"},
    .{"injlim"},
    .{"lim"},
    .{"liminf"},
    .{"limsup"},
    .{"max"},
    .{"min"},
    .{"projlim"},
    .{"sup"},
});

const display_limit_symbols = std.StaticStringMap(void).initComptime(.{
    .{"bigcap"},
    .{"bigcup"},
    .{"bigodot"},
    .{"bigoplus"},
    .{"bigotimes"},
    .{"bigsqcup"},
    .{"biguplus"},
    .{"bigvee"},
    .{"bigwedge"},
    .{"coprod"},
    .{"int"},
    .{"iint"},
    .{"iiint"},
    .{"oint"},
    .{"prod"},
    .{"sum"},
});

const relation_commands = std.StaticStringMap(void).initComptime(.{
    .{"Leftarrow"},
    .{"Leftrightarrow"},
    .{"Longleftarrow"},
    .{"Longleftrightarrow"},
    .{"Longrightarrow"},
    .{"Rightarrow"},
    .{"Vdash"},
    .{"Vvdash"},
    .{"approx"},
    .{"asymp"},
    .{"cong"},
    .{"dashv"},
    .{"doteq"},
    .{"downarrow"},
    .{"equiv"},
    .{"ge"},
    .{"geq"},
    .{"geqslant"},
    .{"gets"},
    .{"gg"},
    .{"hookleftarrow"},
    .{"hookrightarrow"},
    .{"iff"},
    .{"implies"},
    .{"in"},
    .{"leadsto"},
    .{"le"},
    .{"leftarrow"},
    .{"leftharpoondown"},
    .{"leftharpoonup"},
    .{"leftrightarrow"},
    .{"leftrightharpoons"},
    .{"leq"},
    .{"leqslant"},
    .{"ll"},
    .{"longleftarrow"},
    .{"longleftrightarrow"},
    .{"longmapsto"},
    .{"longrightarrow"},
    .{"mapsto"},
    .{"mid"},
    .{"models"},
    .{"ne"},
    .{"nearrow"},
    .{"neq"},
    .{"ni"},
    .{"notin"},
    .{"nvdash"},
    .{"nvDash"},
    .{"nwarrow"},
    .{"parallel"},
    .{"perp"},
    .{"prec"},
    .{"preceq"},
    .{"propto"},
    .{"rightharpoondown"},
    .{"rightharpoonup"},
    .{"rightleftharpoons"},
    .{"rightarrow"},
    .{"rightsquigarrow"},
    .{"searrow"},
    .{"sim"},
    .{"simeq"},
    .{"sqsubset"},
    .{"sqsubseteq"},
    .{"sqsupset"},
    .{"sqsupseteq"},
    .{"subset"},
    .{"subseteq"},
    .{"succ"},
    .{"succeq"},
    .{"supset"},
    .{"supseteq"},
    .{"swarrow"},
    .{"to"},
    .{"triangleleft"},
    .{"triangleright"},
    .{"twoheadleftarrow"},
    .{"twoheadrightarrow"},
    .{"uparrow"},
    .{"vdash"},
});

const spacing_commands = std.StaticStringMap(void).initComptime(.{
    .{","},
    .{":"},
    .{";"},
    .{" "},
    .{">"},
    .{"enspace"},
    .{"enskip"},
    .{"medspace"},
    .{"quad"},
    .{"qquad"},
    .{"thickspace"},
    .{"thinspace"},
});

const negative_spacing_commands = std.StaticStringMap(void).initComptime(.{
    .{"!"},
    .{"negmedspace"},
    .{"negthickspace"},
    .{"negthinspace"},
});

const ignored_commands = std.StaticStringMap(void).initComptime(.{
    .{"displaystyle"},
    .{"limits"},
    .{"nolimits"},
    .{"scriptstyle"},
    .{"scriptscriptstyle"},
    .{"textstyle"},
});

const size_commands = std.StaticStringMap(void).initComptime(.{
    .{"big"},
    .{"Big"},
    .{"bigg"},
    .{"Bigg"},
    .{"bigl"},
    .{"Bigl"},
    .{"biggl"},
    .{"Biggl"},
    .{"bigr"},
    .{"Bigr"},
    .{"biggr"},
    .{"Biggr"},
});

const plain_wrappers = std.StaticStringMap(void).initComptime(.{
    .{"emph"},
    .{"mathcal"},
    .{"mathbf"},
    .{"mathfrak"},
    .{"mathit"},
    .{"mathrm"},
    .{"mathnormal"},
    .{"mathscr"},
    .{"mathsf"},
    .{"mathtt"},
    .{"mathup"},
    .{"mbox"},
    .{"overbrace"},
    .{"pmb"},
    .{"smash"},
    .{"substack"},
    .{"text"},
    .{"textbf"},
    .{"textit"},
    .{"textmd"},
    .{"textnormal"},
    .{"textrm"},
    .{"textsc"},
    .{"textsf"},
    .{"textsl"},
    .{"texttt"},
    .{"textup"},
    .{"underbrace"},
    .{"bm"},
    .{"boldsymbol"},
});

const named_operator_start: u8 = 0x11;
const named_operator_end: u8 = 0x12;
const layout_marker_start: u8 = 0x13;
const layout_marker_end: u8 = 0x14;
const protected_space: u8 = 0x15;
const negative_space: u8 = 0x16;

fn contains(map: anytype, key: []const u8) bool {
    return map.has(key);
}

fn dupe(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    return gpa.dupe(u8, value);
}

fn appendOwned(out: *std.ArrayList(u8), gpa: std.mem.Allocator, value: []u8) !void {
    defer gpa.free(value);
    try out.appendSlice(gpa, value);
}

fn trimAscii(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn trimEndAscii(value: []const u8) []const u8 {
    return std.mem.trimEnd(u8, value, " \t\r\n");
}

fn utf8SequenceLength(bytes: []const u8, index: usize) usize {
    if (index >= bytes.len) return 0;
    return @min(std.unicode.utf8ByteSequenceLength(bytes[index]) catch 1, bytes.len - index);
}

fn codepointCount(value: []const u8) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (index < value.len) : (count += 1) index += utf8SequenceLength(value, index);
    return count;
}

pub fn visibleWidth(value: []const u8) usize {
    return terminal_text.visibleWidth(value);
}

fn isSimpleMathAtom(value: []const u8) bool {
    if (value.len == 0) return false;
    var index: usize = 0;
    while (index < value.len) {
        const byte = value[index];
        if (byte < 0x80) {
            if (!std.ascii.isAlphanumeric(byte) and byte != '.') return false;
            index += 1;
        } else {
            index += utf8SequenceLength(value, index);
        }
    }
    return true;
}

fn replaceScriptCharacters(
    gpa: std.mem.Allocator,
    value: []const u8,
    replacements: std.StaticStringMap([]const u8),
) !?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var index: usize = 0;
    while (index < value.len) {
        const length = utf8SequenceLength(value, index);
        const character = value[index .. index + length];
        const replacement = replacements.get(character) orelse {
            out.deinit(gpa);
            return null;
        };
        try out.appendSlice(gpa, replacement);
        index += length;
    }
    const owned = try out.toOwnedSlice(gpa);
    return @as(?[]u8, owned);
}

const ScriptKind = enum { sub, sup };

fn compactScriptOperators(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var index: usize = 0;
    while (index < value.len) {
        if (value[index] == ' ' or value[index] == '\t' or value[index] == '\r' or value[index] == '\n') {
            var probe = index;
            while (probe < value.len and std.ascii.isWhitespace(value[probe])) : (probe += 1) {}
            if (probe < value.len and (value[probe] == '=' or value[probe] == '+' or value[probe] == '-')) {
                index = probe;
                continue;
            }
            if (out.items.len > 0 and (out.items[out.items.len - 1] == '=' or out.items[out.items.len - 1] == '+' or out.items[out.items.len - 1] == '-')) {
                index = probe;
                continue;
            }
            try out.append(gpa, ' ');
            index = probe;
            continue;
        }
        try out.append(gpa, value[index]);
        index += 1;
    }
    return out.toOwnedSlice(gpa);
}

fn formatScript(gpa: std.mem.Allocator, raw: []const u8, kind: ScriptKind) ![]u8 {
    const trimmed = trimAscii(raw);
    const compact = try compactScriptOperators(gpa, trimmed);
    defer gpa.free(compact);
    const replacements = if (kind == .sub) subscripts else superscripts;
    if (try replaceScriptCharacters(gpa, compact, replacements)) |unicode| return unicode;
    const prefix: u8 = if (kind == .sub) '_' else '^';
    const count = codepointCount(compact);
    var ascii_letters = compact.len > 0;
    for (compact) |byte| {
        if (!std.ascii.isAlphabetic(byte)) {
            ascii_letters = false;
            break;
        }
    }
    if (count == 1 or (kind == .sub and ascii_letters)) return std.fmt.allocPrint(gpa, "{c}{s}", .{ prefix, compact });
    return std.fmt.allocPrint(gpa, "{c}({s})", .{ prefix, compact });
}

fn formatFraction(gpa: std.mem.Allocator, numerator_raw: []const u8, denominator_raw: []const u8) ![]u8 {
    const numerator = trimAscii(numerator_raw);
    const denominator = trimAscii(denominator_raw);
    const simple_numerator = isSimpleMathAtom(numerator);
    var simple_denominator = true;
    if (codepointCount(denominator) != 1) {
        for (denominator) |byte| {
            if (!std.ascii.isDigit(byte) and byte != '.') {
                simple_denominator = false;
                break;
            }
        }
    }
    return std.fmt.allocPrint(gpa, "{s}{s}{s}/{s}{s}{s}", .{
        if (simple_numerator) "" else "(",   numerator,   if (simple_numerator) "" else ")",
        if (simple_denominator) "" else "(", denominator, if (simple_denominator) "" else ")",
    });
}

fn formatRoot(gpa: std.mem.Allocator, value_raw: []const u8, symbol: []const u8) ![]u8 {
    const value = trimAscii(value_raw);
    if (isSimpleMathAtom(value)) return std.fmt.allocPrint(gpa, "{s}{s}", .{ symbol, value });
    return std.fmt.allocPrint(gpa, "{s}({s})", .{ symbol, value });
}

fn lastCodepoint(value: []const u8) ?u21 {
    if (value.len == 0) return null;
    var index = value.len - 1;
    while (index > 0 and (value[index] & 0xc0) == 0x80) index -= 1;
    const length = utf8SequenceLength(value, index);
    return std.unicode.utf8Decode(value[index .. index + length]) catch null;
}

fn firstCodepoint(value: []const u8) ?u21 {
    if (value.len == 0) return null;
    const length = utf8SequenceLength(value, 0);
    return std.unicode.utf8Decode(value[0..length]) catch null;
}

fn operatorNeedsSpace(codepoint: u21) bool {
    if (codepoint > 0x7f) return true;
    const byte: u8 = @intCast(codepoint);
    return std.ascii.isAlphanumeric(byte) or byte == ')' or byte == ']' or byte == '}';
}

fn nextNonSpace(value: []const u8, start: usize) ?usize {
    var index = start;
    while (index < value.len and (value[index] == ' ' or value[index] == '\t' or value[index] == '\r' or value[index] == '\n')) : (index += 1) {}
    return if (index < value.len) index else null;
}

fn normalizeLine(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var index: usize = 0;
    var pending_space = false;
    while (index < value.len) {
        const byte = value[index];
        if (byte == named_operator_start) {
            if (lastCodepoint(trimEndAscii(out.items))) |cp| {
                if (operatorNeedsSpace(cp)) pending_space = true;
            }
            index += 1;
            continue;
        }
        if (byte == named_operator_end) {
            if (nextNonSpace(value, index + 1)) |next| {
                if (value[next] == layout_marker_start) {
                    pending_space = true;
                } else if (firstCodepoint(value[next..])) |cp| {
                    if (operatorNeedsSpace(cp) and cp != '(' and cp != '[' and cp != '{') pending_space = true;
                }
            }
            index += 1;
            continue;
        }
        if (byte == negative_space) {
            while (out.items.len > 0 and (out.items[out.items.len - 1] == ' ' or out.items[out.items.len - 1] == '\t')) _ = out.pop();
            if (out.items.len > 0 and out.items[out.items.len - 1] == named_operator_end) _ = out.pop();
            pending_space = false;
            index += 1;
            continue;
        }
        if (byte == ' ' or byte == '\t' or byte == '\r') {
            pending_space = true;
            index += 1;
            continue;
        }
        if (pending_space and out.items.len > 0) try out.append(gpa, ' ');
        pending_space = false;
        try out.append(gpa, byte);
        index += 1;
    }
    while (out.items.len > 0 and (out.items[out.items.len - 1] == ' ' or out.items[out.items.len - 1] == '\t')) _ = out.pop();
    return out.toOwnedSlice(gpa);
}

fn normalizeOutput(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var lines: std.ArrayList([]u8) = .empty;
    defer {
        for (lines.items) |line| gpa.free(line);
        lines.deinit(gpa);
    }
    var iterator = std.mem.splitScalar(u8, value, '\n');
    while (iterator.next()) |line| {
        const normalized = try normalizeLine(gpa, line);
        if (normalized.len == 0 and (lines.items.len == 0 or iterator.peek() == null)) {
            gpa.free(normalized);
            continue;
        }
        try lines.append(gpa, normalized);
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (lines.items, 0..) |line, index| {
        if (index > 0) try out.append(gpa, '\n');
        try out.appendSlice(gpa, line);
    }
    return out.toOwnedSlice(gpa);
}

const FractionNode = struct { numerator: []u8, denominator: []u8 };
const OperatorNode = struct { operator: []u8, lower: ?[]u8 = null, upper: ?[]u8 = null };
const MatrixNode = struct { lines: [][]u8, baseline: usize = 0 };

const LayoutNode = union(enum) {
    fraction: FractionNode,
    operator: OperatorNode,
    matrix: MatrixNode,

    fn deinit(self: *LayoutNode, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .fraction => |node| {
                gpa.free(node.numerator);
                gpa.free(node.denominator);
            },
            .operator => |node| {
                gpa.free(node.operator);
                if (node.lower) |lower| gpa.free(lower);
                if (node.upper) |upper| gpa.free(upper);
            },
            .matrix => |node| {
                for (node.lines) |line| gpa.free(line);
                gpa.free(node.lines);
            },
        }
        self.* = undefined;
    }
};

fn appendMarker(gpa: std.mem.Allocator, out: *std.ArrayList(u8), index: usize) !void {
    try out.append(gpa, layout_marker_start);
    const digits = try std.fmt.allocPrint(gpa, "{d}", .{index});
    defer gpa.free(digits);
    try out.appendSlice(gpa, digits);
    try out.append(gpa, layout_marker_end);
}

fn parseMarker(value: []const u8, start: usize) ?struct { index: usize, end: usize } {
    if (start >= value.len or value[start] != layout_marker_start) return null;
    const close_rel = std.mem.indexOfScalar(u8, value[start + 1 ..], layout_marker_end) orelse return null;
    const close = start + 1 + close_rel;
    const index = std.fmt.parseUnsigned(usize, value[start + 1 .. close], 10) catch return null;
    return .{ .index = index, .end = close + 1 };
}

const Layout = struct {
    lines: [][]u8,
    width: usize,
    baseline: usize,

    fn deinit(self: *Layout, gpa: std.mem.Allocator) void {
        for (self.lines) |line| gpa.free(line);
        gpa.free(self.lines);
        self.* = undefined;
    }
};

fn repeatBytes(gpa: std.mem.Allocator, value: []const u8, count: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (0..count) |_| try out.appendSlice(gpa, value);
    return out.toOwnedSlice(gpa);
}

fn padLayoutLine(gpa: std.mem.Allocator, line: []const u8, width: usize, centered: bool) ![]u8 {
    const padding = width -| visibleWidth(line);
    const left = if (centered) padding / 2 else 0;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendNTimes(gpa, ' ', left);
    try out.appendSlice(gpa, line);
    try out.appendNTimes(gpa, ' ', padding - left);
    return out.toOwnedSlice(gpa);
}

fn textLayout(gpa: std.mem.Allocator, text: []const u8) !Layout {
    const lines = try gpa.alloc([]u8, 1);
    errdefer gpa.free(lines);
    lines[0] = try dupe(gpa, text);
    return .{ .lines = lines, .width = visibleWidth(text), .baseline = 0 };
}

fn joinLayouts(gpa: std.mem.Allocator, layouts: []const Layout) !Layout {
    if (layouts.len == 0) return textLayout(gpa, "");
    var baseline: usize = 0;
    var below: usize = 0;
    var total_width: usize = 0;
    for (layouts) |layout| {
        baseline = @max(baseline, layout.baseline);
        below = @max(below, layout.lines.len - layout.baseline - 1);
        total_width += layout.width;
    }
    const line_count = baseline + below + 1;
    const lines = try gpa.alloc([]u8, line_count);
    var initialized: usize = 0;
    errdefer {
        for (lines[0..initialized]) |line| gpa.free(line);
        gpa.free(lines);
    }
    for (0..line_count) |row| {
        var writer: std.ArrayList(u8) = .empty;
        errdefer writer.deinit(gpa);
        for (layouts) |layout| {
            const source_signed: isize = @as(isize, @intCast(row)) - @as(isize, @intCast(baseline)) + @as(isize, @intCast(layout.baseline));
            if (source_signed >= 0 and source_signed < layout.lines.len) {
                const padded = try padLayoutLine(gpa, layout.lines[@intCast(source_signed)], layout.width, false);
                defer gpa.free(padded);
                try writer.appendSlice(gpa, padded);
            } else {
                try writer.appendNTimes(gpa, ' ', layout.width);
            }
        }
        while (writer.items.len > 0 and writer.items[writer.items.len - 1] == ' ') writer.items.len -= 1;
        lines[row] = try writer.toOwnedSlice(gpa);
        initialized += 1;
    }
    return .{ .lines = lines, .width = total_width, .baseline = baseline };
}

fn nodeLayout(gpa: std.mem.Allocator, node: LayoutNode, nodes: []const LayoutNode) anyerror!Layout {
    return switch (node) {
        .fraction => |fraction| blk: {
            var numerator = try renderLayout(gpa, fraction.numerator, nodes);
            defer numerator.deinit(gpa);
            var denominator = try renderLayout(gpa, fraction.denominator, nodes);
            defer denominator.deinit(gpa);
            const content_width = @max(@max(numerator.width, denominator.width), 1);
            const width = content_width + 2;
            const count = numerator.lines.len + 1 + denominator.lines.len;
            const lines = try gpa.alloc([]u8, count);
            var initialized: usize = 0;
            errdefer {
                for (lines[0..initialized]) |line| gpa.free(line);
                gpa.free(lines);
            }
            for (numerator.lines) |line| {
                lines[initialized] = try padLayoutLine(gpa, line, width, true);
                initialized += 1;
            }
            var bar: std.ArrayList(u8) = .empty;
            errdefer bar.deinit(gpa);
            try bar.append(gpa, ' ');
            for (0..content_width) |_| try bar.appendSlice(gpa, "─");
            try bar.append(gpa, ' ');
            lines[initialized] = try bar.toOwnedSlice(gpa);
            initialized += 1;
            for (denominator.lines) |line| {
                lines[initialized] = try padLayoutLine(gpa, line, width, true);
                initialized += 1;
            }
            break :blk .{ .lines = lines, .width = width, .baseline = numerator.lines.len };
        },
        .operator => |operator| blk: {
            const content_width = @max(visibleWidth(operator.operator), @max(
                if (operator.lower) |lower| visibleWidth(lower) else 0,
                if (operator.upper) |upper| visibleWidth(upper) else 0,
            ));
            const count: usize = 1 + @as(usize, @intFromBool(operator.lower != null)) + @as(usize, @intFromBool(operator.upper != null));
            const lines = try gpa.alloc([]u8, count);
            var initialized: usize = 0;
            errdefer {
                for (lines[0..initialized]) |line| gpa.free(line);
                gpa.free(lines);
            }
            if (operator.upper) |upper| {
                const padded = try padLayoutLine(gpa, upper, content_width, true);
                defer gpa.free(padded);
                lines[initialized] = try std.fmt.allocPrint(gpa, "{s} ", .{padded});
                initialized += 1;
            }
            const padded_operator = try padLayoutLine(gpa, operator.operator, content_width, true);
            defer gpa.free(padded_operator);
            lines[initialized] = try std.fmt.allocPrint(gpa, "{s} ", .{padded_operator});
            initialized += 1;
            if (operator.lower) |lower| {
                const padded = try padLayoutLine(gpa, lower, content_width, true);
                defer gpa.free(padded);
                lines[initialized] = try std.fmt.allocPrint(gpa, "{s} ", .{padded});
                initialized += 1;
            }
            break :blk .{ .lines = lines, .width = content_width + 1, .baseline = if (operator.upper == null) 0 else 1 };
        },
        .matrix => |matrix| blk: {
            var width: usize = 0;
            for (matrix.lines) |line| width = @max(width, visibleWidth(line));
            const lines = try gpa.alloc([]u8, matrix.lines.len);
            var initialized: usize = 0;
            errdefer {
                for (lines[0..initialized]) |line| gpa.free(line);
                gpa.free(lines);
            }
            for (matrix.lines) |line| {
                lines[initialized] = try padLayoutLine(gpa, line, width, false);
                initialized += 1;
            }
            break :blk .{ .lines = lines, .width = width, .baseline = matrix.baseline };
        },
    };
}

fn renderLayout(gpa: std.mem.Allocator, source: []const u8, nodes: []const LayoutNode) anyerror!Layout {
    var rendered_lines: std.ArrayList([]u8) = .empty;
    errdefer {
        for (rendered_lines.items) |line| gpa.free(line);
        rendered_lines.deinit(gpa);
    }
    var first_baseline: usize = 0;
    var max_width: usize = 0;
    var source_iter = std.mem.splitScalar(u8, source, '\n');
    while (source_iter.next()) |source_line| {
        var pieces: std.ArrayList(Layout) = .empty;
        defer {
            for (pieces.items) |*piece| piece.deinit(gpa);
            pieces.deinit(gpa);
        }
        var position: usize = 0;
        var had_previous_node = false;
        var previous_matrix = false;
        var cursor: usize = 0;
        while (cursor < source_line.len) {
            if (source_line[cursor] != layout_marker_start) {
                cursor += 1;
                continue;
            }
            const marker = parseMarker(source_line, cursor) orelse {
                cursor += 1;
                continue;
            };
            if (marker.index >= nodes.len) {
                cursor = marker.end;
                continue;
            }
            if (cursor > position) {
                const raw = source_line[position..cursor];
                var text = if (had_previous_node) std.mem.trimStart(u8, raw, " \t") else raw;
                text = std.mem.trimEnd(u8, text, " \t");
                const next_matrix = switch (nodes[marker.index]) {
                    .matrix => true,
                    else => false,
                };
                const preserve_leading = previous_matrix and raw.len > 0 and std.ascii.isWhitespace(raw[0]);
                const preserve_trailing = next_matrix and raw.len > 0 and std.ascii.isWhitespace(raw[raw.len - 1]);
                if (text.len > 0 or preserve_leading or preserve_trailing) {
                    const decorated = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ if (preserve_leading) " " else "", text, if (preserve_trailing) " " else "" });
                    defer gpa.free(decorated);
                    try pieces.append(gpa, try textLayout(gpa, decorated));
                }
            }
            try pieces.append(gpa, try nodeLayout(gpa, nodes[marker.index], nodes));
            previous_matrix = switch (nodes[marker.index]) {
                .matrix => true,
                else => false,
            };
            had_previous_node = true;
            position = marker.end;
            cursor = marker.end;
        }
        if (position < source_line.len) {
            const raw = source_line[position..];
            const trimmed = if (had_previous_node) std.mem.trimStart(u8, raw, " \t") else raw;
            const decorated = if (previous_matrix and raw.len > 0 and std.ascii.isWhitespace(raw[0])) try std.fmt.allocPrint(gpa, " {s}", .{trimmed}) else try dupe(gpa, trimmed);
            defer gpa.free(decorated);
            try pieces.append(gpa, try textLayout(gpa, decorated));
        }
        var joined = try joinLayouts(gpa, pieces.items);
        defer {
            // Ownership of line strings is transferred below.
            gpa.free(joined.lines);
            joined.lines = &.{};
        }
        if (rendered_lines.items.len == 0) first_baseline = joined.baseline;
        max_width = @max(max_width, joined.width);
        for (joined.lines) |line| try rendered_lines.append(gpa, line);
    }
    return .{ .lines = try rendered_lines.toOwnedSlice(gpa), .width = max_width, .baseline = first_baseline };
}

fn commonIndent(lines: []const []u8) usize {
    var minimum: usize = std.math.maxInt(usize);
    for (lines) |line| {
        if (trimAscii(line).len == 0) continue;
        var count: usize = 0;
        while (count < line.len and line[count] == ' ') : (count += 1) {}
        minimum = @min(minimum, count);
    }
    return if (minimum == std.math.maxInt(usize)) 0 else minimum;
}

fn finalizeLayout(gpa: std.mem.Allocator, layout: *Layout) ![]u8 {
    const indentation = commonIndent(layout.lines);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (layout.lines, 0..) |line, index| {
        if (index > 0) try out.append(gpa, '\n');
        const sliced = if (indentation <= line.len) line[indentation..] else line;
        const trimmed = std.mem.trimEnd(u8, sliced, " \t");
        for (trimmed) |byte| try out.append(gpa, if (byte == protected_space) ' ' else byte);
    }
    while (out.items.len > 0 and (out.items[out.items.len - 1] == ' ' or out.items[out.items.len - 1] == '\n')) out.items.len -= 1;
    return out.toOwnedSlice(gpa);
}
fn removeAsciiSpaces(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (value) |byte| if (!std.ascii.isWhitespace(byte)) try out.append(gpa, byte);
    return out.toOwnedSlice(gpa);
}

fn trailingMarker(value: []const u8) ?usize {
    if (value.len < 3 or value[value.len - 1] != layout_marker_end) return null;
    var start = value.len - 1;
    while (start > 0) {
        start -= 1;
        if (value[start] == layout_marker_start) return (parseMarker(value, start) orelse return null).index;
        if (!std.ascii.isDigit(value[start])) return null;
    }
    return null;
}

const LowerStyle = enum { bracket, script };

const Parser = struct {
    gpa: std.mem.Allocator,
    source: []const u8,
    nodes: *std.ArrayList(LayoutNode),
    display: bool,
    position: usize = 0,
    supported: bool = true,
    stack_fractions: bool = true,

    fn render(self: *Parser) anyerror!?[]u8 {
        const parsed = try self.parseSequence(null);
        defer self.gpa.free(parsed);
        if (!self.supported or self.position != self.source.len) return null;
        return try normalizeOutput(self.gpa, parsed);
    }

    fn parseSequence(self: *Parser, end_character: ?u8) anyerror![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        while (self.position < self.source.len) {
            const character = self.source[self.position];
            if (end_character != null and character == end_character.?) {
                self.position += 1;
                return out.toOwnedSlice(self.gpa);
            }
            if (character == '}') {
                self.supported = false;
                return out.toOwnedSlice(self.gpa);
            }
            if (character == '{') {
                self.position += 1;
                const nested = try self.parseSequence('}');
                try appendOwned(&out, self.gpa, nested);
                continue;
            }
            if (character == '\\') {
                const command = try self.parseCommand();
                defer self.gpa.free(command);
                if (command.len == 1 and command[0] == negative_space) {
                    while (out.items.len > 0 and std.ascii.isWhitespace(out.items[out.items.len - 1])) out.items.len -= 1;
                    if (out.items.len > 0 and out.items[out.items.len - 1] == named_operator_end) out.items.len -= 1;
                } else {
                    try out.appendSlice(self.gpa, command);
                }
                continue;
            }
            if (character == '^' or character == '_') {
                self.position += 1;
                while (out.items.len > 0 and std.ascii.isWhitespace(out.items[out.items.len - 1])) out.items.len -= 1;
                const argument = try self.parseRequiredArgument(false);
                defer self.gpa.free(argument);
                const script = try formatScript(self.gpa, argument, if (character == '_') .sub else .sup);
                defer self.gpa.free(script);
                if (out.items.len > 0 and out.items[out.items.len - 1] == named_operator_end) {
                    out.items.len -= 1;
                    try out.appendSlice(self.gpa, script);
                    try out.append(self.gpa, named_operator_end);
                } else {
                    try out.appendSlice(self.gpa, script);
                }
                continue;
            }
            if (std.ascii.isWhitespace(character)) {
                while (self.position < self.source.len and std.ascii.isWhitespace(self.source[self.position])) self.position += 1;
                try out.append(self.gpa, ' ');
                continue;
            }
            if (character == '=' or character == '<' or character == '>') {
                while (out.items.len > 0 and std.ascii.isWhitespace(out.items[out.items.len - 1])) out.items.len -= 1;
                try out.append(self.gpa, ' ');
                try out.append(self.gpa, character);
                try out.append(self.gpa, ' ');
                self.position += 1;
                continue;
            }
            if (character == '&') {
                self.position += 1;
                continue;
            }
            if (character == '~') {
                self.position += 1;
                try out.append(self.gpa, ' ');
                continue;
            }
            if (character == '.') {
                if (trailingMarker(out.items)) |node_index| {
                    if (node_index < self.nodes.items.len) {
                        switch (self.nodes.items[node_index]) {
                            .matrix => {
                                const matrix = &self.nodes.items[node_index].matrix;
                                if (matrix.lines.len > 0) {
                                    const last = matrix.lines.len - 1;
                                    const extended = try std.fmt.allocPrint(self.gpa, "{s}.", .{matrix.lines[last]});
                                    self.gpa.free(matrix.lines[last]);
                                    matrix.lines[last] = extended;
                                    self.position += 1;
                                    continue;
                                }
                            },
                            else => {},
                        }
                    }
                }
            }
            const length = utf8SequenceLength(self.source, self.position);
            try out.appendSlice(self.gpa, self.source[self.position .. self.position + length]);
            self.position += length;
        }
        if (end_character != null) self.supported = false;
        return out.toOwnedSlice(self.gpa);
    }

    fn skipWhitespace(self: *Parser, include_newlines: bool) void {
        while (self.position < self.source.len) {
            const byte = self.source[self.position];
            if (byte == ' ' or byte == '\t' or (include_newlines and (byte == '\r' or byte == '\n'))) {
                self.position += 1;
            } else break;
        }
    }

    fn parseCommand(self: *Parser) anyerror![]u8 {
        self.position += 1;
        if (self.position >= self.source.len) {
            self.supported = false;
            return dupe(self.gpa, "");
        }
        const first = self.source[self.position];
        if (first == '\n' or first == '\r') {
            self.position += 1;
            if (first == '\r' and self.position < self.source.len and self.source[self.position] == '\n') self.position += 1;
            return dupe(self.gpa, " ");
        }
        const start = self.position;
        if (std.ascii.isAlphabetic(first)) {
            while (self.position < self.source.len and std.ascii.isAlphabetic(self.source[self.position])) self.position += 1;
        } else {
            self.position += utf8SequenceLength(self.source, self.position);
        }
        const command = self.source[start..self.position];

        if (std.mem.eql(u8, command, "\\")) return dupe(self.gpa, "\n");
        if (contains(spacing_commands, command)) return dupe(self.gpa, " ");
        if (contains(negative_spacing_commands, command)) return dupe(self.gpa, &.{negative_space});
        if (contains(ignored_commands, command)) return dupe(self.gpa, "");
        if (std.mem.eql(u8, command, "{") or std.mem.eql(u8, command, "}") or std.mem.eql(u8, command, "$") or
            std.mem.eql(u8, command, "%") or std.mem.eql(u8, command, "#") or std.mem.eql(u8, command, "_") or std.mem.eql(u8, command, "&"))
            return dupe(self.gpa, command);
        if (std.mem.eql(u8, command, "|")) return dupe(self.gpa, "‖");

        if (std.mem.eql(u8, command, "not")) {
            const argument = try self.parseRequiredArgument(false);
            defer self.gpa.free(argument);
            const value = trimAscii(argument);
            if (negated_symbols.get(value)) |negated| return std.fmt.allocPrint(self.gpa, " {s} ", .{negated});
            if (value.len == 0) {
                self.supported = false;
                return dupe(self.gpa, "");
            }
            const length = utf8SequenceLength(value, 0);
            return std.fmt.allocPrint(self.gpa, " {s}̸{s} ", .{ value[0..length], value[length..] });
        }

        if (contains(limit_operators, command)) return self.parseOperator(command, .bracket, true, true);
        if (symbols.get(command)) |symbol| {
            if (contains(display_limit_symbols, command)) return self.parseOperator(symbol, .script, true, false);
            if (std.mem.eql(u8, command, "cdot") or std.mem.eql(u8, command, "times") or contains(relation_commands, command))
                return std.fmt.allocPrint(self.gpa, " {s} ", .{symbol});
            return dupe(self.gpa, symbol);
        }
        if (contains(named_operators, command)) {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(self.gpa);
            try out.append(self.gpa, named_operator_start);
            try out.appendSlice(self.gpa, command);
            try out.append(self.gpa, named_operator_end);
            return out.toOwnedSlice(self.gpa);
        }
        if (contains(size_commands, command)) return dupe(self.gpa, "");
        if (std.mem.eql(u8, command, "left") or std.mem.eql(u8, command, "middle") or std.mem.eql(u8, command, "right")) {
            if (self.position < self.source.len and self.source[self.position] == '.') self.position += 1;
            return dupe(self.gpa, "");
        }
        if (std.mem.eql(u8, command, "frac") or std.mem.eql(u8, command, "dfrac") or std.mem.eql(u8, command, "tfrac")) {
            const should_stack = self.display and self.stack_fractions and !std.mem.eql(u8, command, "tfrac");
            const numerator = try self.parseRequiredArgument(!should_stack);
            defer self.gpa.free(numerator);
            const denominator = try self.parseRequiredArgument(!should_stack);
            defer self.gpa.free(denominator);
            if (should_stack) {
                const normalized_numerator = try normalizeOutput(self.gpa, numerator);
                errdefer self.gpa.free(normalized_numerator);
                const normalized_denominator = try normalizeOutput(self.gpa, denominator);
                errdefer self.gpa.free(normalized_denominator);
                const node_index = self.nodes.items.len;
                try self.nodes.append(self.gpa, .{ .fraction = .{ .numerator = normalized_numerator, .denominator = normalized_denominator } });
                var out: std.ArrayList(u8) = .empty;
                errdefer out.deinit(self.gpa);
                try appendMarker(self.gpa, &out, node_index);
                return out.toOwnedSlice(self.gpa);
            }
            return formatFraction(self.gpa, numerator, denominator);
        }
        if (std.mem.eql(u8, command, "sqrt")) {
            const degree_owned = try self.parseOptionalArgument();
            defer if (degree_owned) |degree| self.gpa.free(degree);
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            const degree = if (degree_owned) |degree| trimAscii(degree) else null;
            if (degree == null or std.mem.eql(u8, degree.?, "2")) return formatRoot(self.gpa, value, "√");
            if (std.mem.eql(u8, degree.?, "3")) return formatRoot(self.gpa, value, "∛");
            if (std.mem.eql(u8, degree.?, "4")) return formatRoot(self.gpa, value, "∜");
            const script = try formatScript(self.gpa, degree.?, .sup);
            defer self.gpa.free(script);
            const root = try formatRoot(self.gpa, value, "√");
            defer self.gpa.free(root);
            return std.fmt.allocPrint(self.gpa, "{s}{s}", .{ script, root });
        }
        if (std.mem.eql(u8, command, "boxed") or std.mem.eql(u8, command, "fbox")) {
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            return std.fmt.allocPrint(self.gpa, "[{s}]", .{trimAscii(value)});
        }
        if (std.mem.eql(u8, command, "binom") or std.mem.eql(u8, command, "dbinom") or std.mem.eql(u8, command, "tbinom")) {
            const top = try self.parseRequiredArgument(true);
            defer self.gpa.free(top);
            const bottom = try self.parseRequiredArgument(true);
            defer self.gpa.free(bottom);
            return std.fmt.allocPrint(self.gpa, "({s} choose {s})", .{ top, bottom });
        }
        if (accents.get(command)) |accent| {
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            if (codepointCount(value) == 1) return std.fmt.allocPrint(self.gpa, "{s}{s}", .{ value, accent });
            return std.fmt.allocPrint(self.gpa, "{s}({s})", .{ command, value });
        }
        if (std.mem.eql(u8, command, "mathbb")) {
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(self.gpa);
            var index: usize = 0;
            while (index < value.len) {
                const length = utf8SequenceLength(value, index);
                const character = value[index .. index + length];
                try out.appendSlice(self.gpa, blackboard.get(character) orelse character);
                index += length;
            }
            return out.toOwnedSlice(self.gpa);
        }
        if (std.mem.eql(u8, command, "operatorname")) {
            const starred = self.position < self.source.len and self.source[self.position] == '*';
            if (starred) self.position += 1;
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            const normalized = try normalizeOutput(self.gpa, value);
            defer self.gpa.free(normalized);
            return self.parseOperator(trimAscii(normalized), .bracket, starred, true);
        }
        if (std.mem.eql(u8, command, "mod") or std.mem.eql(u8, command, "bmod")) return dupe(self.gpa, " mod ");
        if (std.mem.eql(u8, command, "pmod") or std.mem.eql(u8, command, "pod")) {
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            if (std.mem.eql(u8, command, "pmod")) return std.fmt.allocPrint(self.gpa, " (mod {s})", .{trimAscii(value)});
            return std.fmt.allocPrint(self.gpa, " ({s})", .{trimAscii(value)});
        }
        if (std.mem.eql(u8, command, "overset") or std.mem.eql(u8, command, "stackrel")) {
            const upper = try self.parseRequiredArgument(true);
            defer self.gpa.free(upper);
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            const script = try formatScript(self.gpa, upper, .sup);
            defer self.gpa.free(script);
            return std.fmt.allocPrint(self.gpa, "{s}{s}", .{ trimAscii(value), script });
        }
        if (std.mem.eql(u8, command, "underset")) {
            const lower = try self.parseRequiredArgument(true);
            defer self.gpa.free(lower);
            const value = try self.parseRequiredArgument(true);
            defer self.gpa.free(value);
            const script = try formatScript(self.gpa, lower, .sub);
            defer self.gpa.free(script);
            return std.fmt.allocPrint(self.gpa, "{s}{s}", .{ trimAscii(value), script });
        }
        if (contains(plain_wrappers, command)) {
            const value = try self.parseRequiredArgument(true);
            if (std.mem.startsWith(u8, command, "text") or std.mem.eql(u8, command, "mbox")) return value;
            const trimmed = try dupe(self.gpa, trimAscii(value));
            self.gpa.free(value);
            return trimmed;
        }
        if (std.mem.eql(u8, command, "begin")) return self.parseEnvironment();
        if (std.mem.eql(u8, command, "end")) {
            self.supported = false;
            return dupe(self.gpa, "");
        }
        self.supported = false;
        return std.fmt.allocPrint(self.gpa, "\\{s}", .{command});
    }

    fn parseOperator(self: *Parser, operator_raw: []const u8, lower_style: LowerStyle, display_limits: bool, spaced: bool) anyerror![]u8 {
        var use_display_limits = display_limits;
        var modifier_position = self.position;
        while (modifier_position < self.source.len and (self.source[modifier_position] == ' ' or self.source[modifier_position] == '\t')) modifier_position += 1;
        if (std.mem.startsWith(u8, self.source[modifier_position..], "\\limits") and
            (modifier_position + 7 == self.source.len or !std.ascii.isAlphabetic(self.source[modifier_position + 7])))
        {
            use_display_limits = true;
            self.position = modifier_position + 7;
        } else if (std.mem.startsWith(u8, self.source[modifier_position..], "\\nolimits") and
            (modifier_position + 9 == self.source.len or !std.ascii.isAlphabetic(self.source[modifier_position + 9])))
        {
            use_display_limits = false;
            self.position = modifier_position + 9;
        }

        var lower: ?[]u8 = null;
        errdefer if (lower) |value| self.gpa.free(value);
        var upper: ?[]u8 = null;
        errdefer if (upper) |value| self.gpa.free(value);
        while (true) {
            var script_position = self.position;
            while (script_position < self.source.len and (self.source[script_position] == ' ' or self.source[script_position] == '\t')) script_position += 1;
            if (script_position >= self.source.len or (self.source[script_position] != '_' and self.source[script_position] != '^')) break;
            const kind = self.source[script_position];
            self.position = script_position + 1;
            const argument = try self.parseRequiredArgument(false);
            defer self.gpa.free(argument);
            const normalized = try normalizeOutput(self.gpa, argument);
            defer self.gpa.free(normalized);
            const compact = try removeAsciiSpaces(self.gpa, normalized);
            if (kind == '_') {
                if (lower) |old| {
                    self.gpa.free(old);
                    self.supported = false;
                }
                lower = compact;
            } else {
                if (upper) |old| {
                    self.gpa.free(old);
                    self.supported = false;
                }
                upper = compact;
            }
        }

        if (self.display and use_display_limits and (lower != null or upper != null)) {
            const node_index = self.nodes.items.len;
            const operator = try dupe(self.gpa, operator_raw);
            errdefer self.gpa.free(operator);
            try self.nodes.append(self.gpa, .{ .operator = .{ .operator = operator, .lower = lower, .upper = upper } });
            lower = null;
            upper = null;
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(self.gpa);
            try appendMarker(self.gpa, &out, node_index);
            return out.toOwnedSlice(self.gpa);
        }

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        if (spaced) try out.append(self.gpa, ' ');
        try out.appendSlice(self.gpa, operator_raw);
        if (lower) |value| {
            if (lower_style == .bracket) {
                try out.append(self.gpa, '[');
                try out.appendSlice(self.gpa, value);
                try out.append(self.gpa, ']');
            } else {
                const script = try formatScript(self.gpa, value, .sub);
                defer self.gpa.free(script);
                try out.appendSlice(self.gpa, script);
            }
            self.gpa.free(value);
            lower = null;
        }
        if (upper) |value| {
            const script = try formatScript(self.gpa, value, .sup);
            defer self.gpa.free(script);
            try out.appendSlice(self.gpa, script);
            self.gpa.free(value);
            upper = null;
        }
        if (spaced) try out.append(self.gpa, ' ');
        return out.toOwnedSlice(self.gpa);
    }

    fn parseRequiredArgument(self: *Parser, stack_fractions: bool) anyerror![]u8 {
        const previous = self.stack_fractions;
        self.stack_fractions = previous and stack_fractions;
        defer self.stack_fractions = previous;
        return self.parseRequiredArgumentValue();
    }

    fn parseRequiredArgumentValue(self: *Parser) anyerror![]u8 {
        self.skipWhitespace(true);
        if (self.position >= self.source.len) {
            self.supported = false;
            return dupe(self.gpa, "");
        }
        if (self.source[self.position] == '{') {
            self.position += 1;
            return self.parseSequence('}');
        }
        if (self.source[self.position] == '\\') return self.parseCommand();
        const length = utf8SequenceLength(self.source, self.position);
        const result = try dupe(self.gpa, self.source[self.position .. self.position + length]);
        self.position += length;
        return result;
    }

    fn parseOptionalArgument(self: *Parser) anyerror!?[]u8 {
        self.skipWhitespace(false);
        if (self.position >= self.source.len or self.source[self.position] != '[') return null;
        const end_rel = std.mem.indexOfScalar(u8, self.source[self.position + 1 ..], ']') orelse {
            self.supported = false;
            return null;
        };
        const end = self.position + 1 + end_rel;
        const raw = self.source[self.position + 1 .. end];
        self.position = end + 1;
        const rendered = try self.renderNested(raw, true);
        return @as(?[]u8, rendered);
    }

    fn readRawGroup(self: *Parser) ?[]const u8 {
        self.skipWhitespace(false);
        if (self.position >= self.source.len or self.source[self.position] != '{') {
            self.supported = false;
            return null;
        }
        self.position += 1;
        const start = self.position;
        var depth: usize = 1;
        while (self.position < self.source.len) {
            const character = self.source[self.position];
            if (character == '\\') {
                self.position += @min(@as(usize, 2), self.source.len - self.position);
                continue;
            }
            if (character == '{') depth += 1;
            if (character == '}') depth -= 1;
            if (depth == 0) {
                const value = self.source[start..self.position];
                self.position += 1;
                return value;
            }
            self.position += 1;
        }
        self.supported = false;
        return null;
    }

    fn renderNested(self: *Parser, source: []const u8, stack_fractions: bool) anyerror![]u8 {
        var nested = Parser{
            .gpa = self.gpa,
            .source = source,
            .nodes = self.nodes,
            .display = self.display and stack_fractions,
            .stack_fractions = stack_fractions,
        };
        const rendered = try nested.render();
        if (rendered) |value| return value;
        self.supported = false;
        return dupe(self.gpa, source);
    }

    fn parseEnvironment(self: *Parser) anyerror![]u8 {
        const environment = self.readRawGroup() orelse return dupe(self.gpa, "");
        const end_marker = try std.fmt.allocPrint(self.gpa, "\\end{{{s}}}", .{environment});
        defer self.gpa.free(end_marker);
        const relative_end = std.mem.indexOf(u8, self.source[self.position..], end_marker) orelse {
            self.supported = false;
            return dupe(self.gpa, "");
        };
        const end = self.position + relative_end;
        const body = self.source[self.position..end];
        self.position = end + end_marker.len;

        if (std.mem.eql(u8, environment, "equation") or std.mem.eql(u8, environment, "equation*") or std.mem.eql(u8, environment, "displaymath")) {
            const value = try self.renderNested(body, true);
            defer self.gpa.free(value);
            return dupe(self.gpa, trimAscii(value));
        }
        if (isAlignedEnvironment(environment)) return self.renderAligned(environment, body);
        if (std.mem.eql(u8, environment, "cases") or std.mem.eql(u8, environment, "cases*")) return self.renderCases(body);
        if (isMatrixEnvironment(environment)) return self.renderMatrix(environment, body);
        self.supported = false;
        return dupe(self.gpa, body);
    }

    fn renderAligned(self: *Parser, environment: []const u8, raw_body: []const u8) anyerror![]u8 {
        const aligned_at = std.mem.eql(u8, environment, "alignedat") or std.mem.eql(u8, environment, "alignat") or std.mem.eql(u8, environment, "alignat*");
        const body = if (aligned_at) stripLeadingRawGroup(raw_body) else raw_body;
        const rows = try splitEnvironmentRows(self.gpa, body);
        defer self.gpa.free(rows);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        var emitted: usize = 0;
        for (rows) |row| {
            var source: std.ArrayList(u8) = .empty;
            defer source.deinit(self.gpa);
            var cells = std.mem.splitScalar(u8, row, '&');
            var cell_index: usize = 0;
            while (cells.next()) |cell| : (cell_index += 1) {
                if (aligned_at and cell_index > 0 and cell_index % 2 == 0) try source.append(self.gpa, ' ');
                try source.appendSlice(self.gpa, cell);
            }
            const rendered = try self.renderNested(source.items, true);
            defer self.gpa.free(rendered);
            const trimmed = trimAscii(rendered);
            if (trimmed.len == 0) continue;
            if (emitted > 0) try out.append(self.gpa, '\n');
            try out.appendSlice(self.gpa, trimmed);
            emitted += 1;
        }
        return out.toOwnedSlice(self.gpa);
    }

    fn renderCases(self: *Parser, body: []const u8) anyerror![]u8 {
        const Row = struct { value: []u8, condition: []u8 };
        var rendered_rows: std.ArrayList(Row) = .empty;
        defer {
            for (rendered_rows.items) |row| {
                self.gpa.free(row.value);
                self.gpa.free(row.condition);
            }
            rendered_rows.deinit(self.gpa);
        }
        const rows = try splitEnvironmentRows(self.gpa, body);
        defer self.gpa.free(rows);
        for (rows) |raw_row| {
            var cells = std.mem.splitScalar(u8, raw_row, '&');
            const value_raw = cells.next() orelse "";
            const condition_raw = cells.next() orelse "";
            var value = try self.renderNested(value_raw, false);
            errdefer self.gpa.free(value);
            var condition = try self.renderNested(condition_raw, false);
            errdefer self.gpa.free(condition);
            const value_trimmed = trimAscii(value);
            var value_end = value_trimmed.len;
            if (value_end > 0 and value_trimmed[value_end - 1] == ',') value_end -= 1;
            const owned_value = try dupe(self.gpa, trimEndAscii(value_trimmed[0..value_end]));
            self.gpa.free(value);
            value = owned_value;
            const owned_condition = try dupe(self.gpa, trimAscii(condition));
            self.gpa.free(condition);
            condition = owned_condition;
            if (value.len == 0 and condition.len == 0) {
                self.gpa.free(value);
                self.gpa.free(condition);
                continue;
            }
            try rendered_rows.append(self.gpa, .{ .value = value, .condition = condition });
        }
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        for (rendered_rows.items, 0..) |row, index| {
            if (index > 0) try out.append(self.gpa, '\n');
            const delimiter = if (index == 0) "⎧" else if (index + 1 == rendered_rows.items.len) "⎩" else "⎨";
            try out.appendSlice(self.gpa, delimiter);
            try out.append(self.gpa, ' ');
            try out.appendSlice(self.gpa, row.value);
            if (row.condition.len > 0) {
                const natural = startsNaturalCondition(row.condition);
                try out.appendSlice(self.gpa, if (natural) " " else " if ");
                try out.appendSlice(self.gpa, row.condition);
            }
        }
        return out.toOwnedSlice(self.gpa);
    }

    fn renderMatrix(self: *Parser, environment: []const u8, raw_body: []const u8) anyerror![]u8 {
        const body = if (std.mem.eql(u8, environment, "array")) stripLeadingRawGroup(raw_body) else raw_body;
        const raw_rows = try splitEnvironmentRows(self.gpa, body);
        defer self.gpa.free(raw_rows);
        var rows: std.ArrayList([][]u8) = .empty;
        defer {
            for (rows.items) |row| {
                for (row) |cell| self.gpa.free(cell);
                self.gpa.free(row);
            }
            rows.deinit(self.gpa);
        }
        var column_count: usize = 0;
        for (raw_rows) |raw_row| {
            var cells_list: std.ArrayList([]u8) = .empty;
            errdefer {
                for (cells_list.items) |cell| self.gpa.free(cell);
                cells_list.deinit(self.gpa);
            }
            var cells = std.mem.splitScalar(u8, raw_row, '&');
            while (cells.next()) |cell_raw| {
                const rendered = try self.renderNested(cell_raw, false);
                defer self.gpa.free(rendered);
                try cells_list.append(self.gpa, try dupe(self.gpa, trimAscii(rendered)));
            }
            var any = false;
            for (cells_list.items) |cell| if (cell.len > 0) {
                any = true;
                break;
            };
            if (!any) {
                for (cells_list.items) |cell| self.gpa.free(cell);
                cells_list.deinit(self.gpa);
                continue;
            }
            const owned = try cells_list.toOwnedSlice(self.gpa);
            column_count = @max(column_count, owned.len);
            try rows.append(self.gpa, owned);
        }
        const widths = try self.gpa.alloc(usize, column_count);
        defer self.gpa.free(widths);
        @memset(widths, 0);
        for (rows.items) |row| {
            for (row, 0..) |cell, column| {
                widths[column] = @max(widths[column], visibleWidth(cell));
            }
        }

        const matrix_lines = try self.gpa.alloc([]u8, rows.items.len);
        var initialized: usize = 0;
        errdefer {
            for (matrix_lines[0..initialized]) |line| self.gpa.free(line);
            self.gpa.free(matrix_lines);
        }
        for (rows.items, 0..) |row, row_index| {
            var content: std.ArrayList(u8) = .empty;
            defer content.deinit(self.gpa);
            for (0..column_count) |column| {
                if (column > 0) try content.appendSlice(self.gpa, " │ ");
                const cell = if (column < row.len) row[column] else "";
                try content.appendSlice(self.gpa, cell);
                try content.appendNTimes(self.gpa, protected_space, widths[column] -| visibleWidth(cell));
            }
            if (std.mem.eql(u8, environment, "array") or std.mem.eql(u8, environment, "matrix") or std.mem.eql(u8, environment, "smallmatrix")) {
                matrix_lines[initialized] = try dupe(self.gpa, content.items);
            } else {
                const delimiters = matrixDelimiters(environment) orelse {
                    self.supported = false;
                    matrix_lines[initialized] = try dupe(self.gpa, content.items);
                    initialized += 1;
                    continue;
                };
                const left = if (row_index == 0) delimiters.top_left else if (row_index + 1 == rows.items.len) delimiters.bottom_left else delimiters.middle_left;
                const right = if (row_index == 0) delimiters.top_right else if (row_index + 1 == rows.items.len) delimiters.bottom_right else delimiters.middle_right;
                matrix_lines[initialized] = try std.fmt.allocPrint(self.gpa, "{s} {s} {s}", .{ left, content.items, right });
            }
            initialized += 1;
        }
        if (matrix_lines.len <= 1) {
            const result = if (matrix_lines.len == 0) try dupe(self.gpa, "") else try dupe(self.gpa, matrix_lines[0]);
            for (matrix_lines) |line| self.gpa.free(line);
            self.gpa.free(matrix_lines);
            return result;
        }
        const node_index = self.nodes.items.len;
        try self.nodes.append(self.gpa, .{ .matrix = .{ .lines = matrix_lines, .baseline = 0 } });
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        try appendMarker(self.gpa, &out, node_index);
        return out.toOwnedSlice(self.gpa);
    }
};
fn isAlignedEnvironment(environment: []const u8) bool {
    const environments = std.StaticStringMap(void).initComptime(.{
        .{"aligned"}, .{"align"},    .{"align*"},   .{"alignedat"}, .{"alignat"}, .{"alignat*"},
        .{"gather"},  .{"gathered"}, .{"multline"}, .{"multline*"}, .{"split"},
    });
    return environments.has(environment);
}

fn isMatrixEnvironment(environment: []const u8) bool {
    const environments = std.StaticStringMap(void).initComptime(.{
        .{"array"}, .{"matrix"}, .{"smallmatrix"}, .{"pmatrix"}, .{"bmatrix"}, .{"Bmatrix"}, .{"vmatrix"}, .{"Vmatrix"},
    });
    return environments.has(environment);
}

fn stripLeadingRawGroup(value: []const u8) []const u8 {
    var start: usize = 0;
    while (start < value.len and std.ascii.isWhitespace(value[start])) start += 1;
    if (start >= value.len or value[start] != '{') return value;
    var depth: usize = 1;
    var index = start + 1;
    while (index < value.len) : (index += 1) {
        if (value[index] == '\\') {
            index += @min(@as(usize, 1), value.len - index - 1);
            continue;
        }
        if (value[index] == '{') depth += 1;
        if (value[index] == '}') depth -= 1;
        if (depth == 0) return value[index + 1 ..];
    }
    return value;
}

fn splitEnvironmentRows(gpa: std.mem.Allocator, body: []const u8) ![]const []const u8 {
    var rows: std.ArrayList([]const u8) = .empty;
    errdefer rows.deinit(gpa);
    var start: usize = 0;
    var index: usize = 0;
    while (index + 1 < body.len) {
        if (body[index] == '\\' and body[index + 1] == '\\') {
            try rows.append(gpa, body[start..index]);
            index += 2;
            if (index < body.len and body[index] == '[') {
                if (std.mem.indexOfScalar(u8, body[index + 1 ..], ']')) |close_rel| index += close_rel + 2;
            }
            start = index;
            continue;
        }
        index += 1;
    }
    try rows.append(gpa, body[start..]);
    return rows.toOwnedSlice(gpa);
}

fn startsNaturalCondition(condition: []const u8) bool {
    const trimmed = trimAscii(condition);
    const words = [_][]const u8{ "if", "when", "for", "otherwise" };
    for (words) |word| {
        if (trimmed.len < word.len or !std.ascii.eqlIgnoreCase(trimmed[0..word.len], word)) continue;
        if (trimmed.len == word.len or !std.ascii.isAlphabetic(trimmed[word.len])) return true;
    }
    return false;
}

const MatrixDelimiters = struct {
    top_left: []const u8,
    top_right: []const u8,
    middle_left: []const u8,
    middle_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
};

fn matrixDelimiters(environment: []const u8) ?MatrixDelimiters {
    if (std.mem.eql(u8, environment, "pmatrix")) return .{ .top_left = "⎛", .top_right = "⎞", .middle_left = "⎜", .middle_right = "⎟", .bottom_left = "⎝", .bottom_right = "⎠" };
    if (std.mem.eql(u8, environment, "bmatrix")) return .{ .top_left = "⎡", .top_right = "⎤", .middle_left = "⎢", .middle_right = "⎥", .bottom_left = "⎣", .bottom_right = "⎦" };
    if (std.mem.eql(u8, environment, "Bmatrix")) return .{ .top_left = "⎧", .top_right = "⎫", .middle_left = "⎨", .middle_right = "⎬", .bottom_left = "⎩", .bottom_right = "⎭" };
    if (std.mem.eql(u8, environment, "vmatrix")) return .{ .top_left = "│", .top_right = "│", .middle_left = "│", .middle_right = "│", .bottom_left = "│", .bottom_right = "│" };
    if (std.mem.eql(u8, environment, "Vmatrix")) return .{ .top_left = "║", .top_right = "║", .middle_left = "║", .middle_right = "║", .bottom_left = "║", .bottom_right = "║" };
    return null;
}

fn replaceProtectedSpaces(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    const out = try dupe(gpa, value);
    for (out) |*byte| {
        if (byte.* == protected_space) byte.* = ' ';
    }
    return out;
}

/// Render supported LaTeX math into terminal-friendly Unicode. The returned
/// slice is owned by `gpa`. Null means the source is malformed or uses an
/// unsupported command and should be displayed verbatim by the caller.
pub fn renderLatex(gpa: std.mem.Allocator, source: []const u8, options: Options) anyerror!?[]u8 {
    var nodes: std.ArrayList(LayoutNode) = .empty;
    defer {
        for (nodes.items) |*node| node.deinit(gpa);
        nodes.deinit(gpa);
    }
    var parser = Parser{ .gpa = gpa, .source = source, .nodes = &nodes, .display = options.display };
    const rendered_optional = try parser.render();
    const rendered = rendered_optional orelse return null;
    defer gpa.free(rendered);
    if (nodes.items.len == 0) {
        const plain = try replaceProtectedSpaces(gpa, rendered);
        return @as(?[]u8, plain);
    }
    var layout = try renderLayout(gpa, rendered, nodes.items);
    defer layout.deinit(gpa);
    const final = try finalizeLayout(gpa, &layout);
    return @as(?[]u8, final);
}

fn expectLatex(source: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    const rendered = (try renderLatex(gpa, source, .{})) orelse return error.ExpectedSupportedLatex;
    defer gpa.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

fn expectDisplayLatex(source: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    const rendered = (try renderLatex(gpa, source, .{ .display = true })) orelse return error.ExpectedSupportedLatex;
    defer gpa.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "LaTeX common symbols scripts roots and fractions" {
    try expectLatex("\\mathbb{C}^3 \\to \\mathbb{C}^3", "ℂ³ → ℂ³");
    try expectLatex("F_1 = -\\frac{1}{4x^2}.", "F₁ = -1/(4x²).");
    try expectLatex("\\sum_{i=0}^n \\alpha_i + \\int_0^\\infty e^{-x^2}\\,dx = \\sqrt{\\pi}", "∑ᵢ₌₀ⁿ αᵢ + ∫₀^∞ e^(-x²) dx = √π");
    try expectLatex("\\sqrt[2]{x}+\\sqrt[3]{x}+\\sqrt[4]{x}+\\sqrt[n]{x}", "√x+∛x+∜x+ⁿ√x");
}

test "LaTeX relations operators wrappers and accents" {
    try expectLatex("A\\not\\subseteq B,\\quad x\\not\\in X", "A ⊈ B, x ∉ X");
    try expectLatex("\\sin^2 x+\\det(A)+a\\equiv b\\pmod n", "sin² x+det(A)+a ≡ b (mod n)");
    try expectLatex("\\binom{n}{k}+\\vec{x}+\\hat{y}+\\overline{AB}", "(n choose k)+x⃗+ŷ+overline(AB)");
    try expectLatex("\\textnormal{hello}+\\mbox{world}+\\boldsymbol{x}", "hello+world+x");
}

test "LaTeX aligned cases and matrices" {
    try expectLatex("\\begin{aligned}a&=b\\\\&=c\\end{aligned}", "a = b\n= c");
    try expectLatex("\\begin{cases}a & x<0 \\\\ b & \\text{if }x=0 \\\\ c & \\text{otherwise}\\end{cases}", "⎧ a if x < 0\n⎨ b if x = 0\n⎩ c otherwise");
    try expectLatex("\\begin{pmatrix}1&200\\\\3000&4\\end{pmatrix}", "⎛ 1    │ 200 ⎞\n⎝ 3000 │ 4   ⎠");
}

test "LaTeX display fractions operators and matrix composition" {
    try expectDisplayLatex("\\frac{x^2+1}{x-1}", "x²+1\n────\nx-1");
    try expectDisplayLatex("\\sum_{i=0}^n x_i", " n\n ∑  xᵢ\ni=0");
    try expectDisplayLatex("x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}", "    -b±√(b²-4ac)\nx = ────────────\n         2a");
}

test "LaTeX returns null for unsupported and malformed syntax" {
    const gpa = std.testing.allocator;
    try std.testing.expect((try renderLatex(gpa, "x + \\unknown{y}", .{})) == null);
    try std.testing.expect((try renderLatex(gpa, "\\frac{1}{x", .{})) == null);
    try std.testing.expect((try renderLatex(gpa, "x}", .{})) == null);
    try std.testing.expect((try renderLatex(gpa, "\\begin{matrix}1 & 2", .{})) == null);
}
