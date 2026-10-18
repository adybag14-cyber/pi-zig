// Test-only c268 theme.ts helper authority: 07FF17A690749AFA8B3B1724EFD271859FF889255FD494606230FEC99EC1C1BA.
// Bodies are copied from the frozen module with TypeScript annotations erased.
// Dependencies are the actual Theme/syntax owners, or explicit adversarial observer inputs.
globalThis.makePublicThemeSource = function(theme, supportsLanguage, highlight) {
"use strict";
let cachedHighlightThemeFor;
let cachedCliHighlightTheme;

function buildCliHighlightTheme(t) {
	return {
		keyword: (s) => t.fg("syntaxKeyword", s),
		built_in: (s) => t.fg("syntaxType", s),
		literal: (s) => t.fg("syntaxNumber", s),
		number: (s) => t.fg("syntaxNumber", s),
		regexp: (s) => t.fg("syntaxString", s),
		string: (s) => t.fg("syntaxString", s),
		subst: (s) => t.fg("text", s),
		comment: (s) => t.fg("syntaxComment", s),
		doctag: (s) => t.fg("syntaxComment", s),
		meta: (s) => t.fg("muted", s),
		function: (s) => t.fg("syntaxFunction", s),
		title: (s) => t.fg("syntaxFunction", s),
		class: (s) => t.fg("syntaxType", s),
		type: (s) => t.fg("syntaxType", s),
		tag: (s) => t.fg("syntaxPunctuation", s),
		name: (s) => t.fg("syntaxKeyword", s),
		attr: (s) => t.fg("syntaxVariable", s),
		variable: (s) => t.fg("syntaxVariable", s),
		params: (s) => t.fg("syntaxVariable", s),
		operator: (s) => t.fg("syntaxOperator", s),
		punctuation: (s) => t.fg("syntaxPunctuation", s),
		emphasis: (s) => t.italic(s),
		strong: (s) => t.bold(s),
		link: (s) => t.underline(s),
		addition: (s) => t.fg("toolDiffAdded", s),
		deletion: (s) => t.fg("toolDiffRemoved", s),
	};
}

function getCliHighlightTheme(t) {
	if (cachedHighlightThemeFor !== t || !cachedCliHighlightTheme) {
		cachedHighlightThemeFor = t;
		cachedCliHighlightTheme = buildCliHighlightTheme(t);
	}
	return cachedCliHighlightTheme;
}

/**
 * Highlight code with syntax coloring based on file extension or language.
 * Returns array of highlighted lines.
 */
function highlightCode(code, lang) {
	// Validate language before highlighting to avoid stderr spam from cli-highlight
	const validLang = lang && supportsLanguage(lang) ? lang : undefined;
	// Skip highlighting when no valid language is specified. cli-highlight's
	// auto-detection is unreliable and can misidentify prose as AppleScript,
	// LiveCodeServer, etc., coloring random English words as keywords.
	if (!validLang) {
		return code.split("\n").map((line) => theme.fg("mdCodeBlock", line));
	}
	const opts = {
		language: validLang,
		ignoreIllegals: true,
		theme: getCliHighlightTheme(theme),
	};
	try {
		return highlight(code, opts).split("\n");
	} catch {
		return code.split("\n");
	}
}

/**
 * Get language identifier from file path extension.
 */
function getLanguageFromPath(filePath) {
	const ext = filePath.split(".").pop()?.toLowerCase();
	if (!ext) return undefined;

	const extToLang = {
		ts: "typescript",
		tsx: "typescript",
		js: "javascript",
		jsx: "javascript",
		mjs: "javascript",
		cjs: "javascript",
		py: "python",
		rb: "ruby",
		rs: "rust",
		go: "go",
		java: "java",
		kt: "kotlin",
		swift: "swift",
		c: "c",
		h: "c",
		cpp: "cpp",
		cc: "cpp",
		cxx: "cpp",
		hpp: "cpp",
		cs: "csharp",
		php: "php",
		sh: "bash",
		bash: "bash",
		zsh: "bash",
		fish: "fish",
		ps1: "powershell",
		sql: "sql",
		html: "html",
		htm: "html",
		css: "css",
		scss: "scss",
		sass: "sass",
		less: "less",
		json: "json",
		yaml: "yaml",
		yml: "yaml",
		toml: "toml",
		xml: "xml",
		md: "markdown",
		markdown: "markdown",
		dockerfile: "dockerfile",
		makefile: "makefile",
		cmake: "cmake",
		lua: "lua",
		perl: "perl",
		r: "r",
		scala: "scala",
		clj: "clojure",
		ex: "elixir",
		exs: "elixir",
		erl: "erlang",
		hs: "haskell",
		ml: "ocaml",
		vim: "vim",
		graphql: "graphql",
		proto: "protobuf",
		tf: "hcl",
		hcl: "hcl",
	};

	return extToLang[ext];
}

function getMarkdownTheme() {
	return {
		heading: (text) => theme.fg("mdHeading", text),
		link: (text) => theme.fg("mdLink", text),
		linkUrl: (text) => theme.fg("mdLinkUrl", text),
		code: (text) => theme.fg("mdCode", text),
		codeBlock: (text) => theme.fg("mdCodeBlock", text),
		codeBlockBorder: (text) => theme.fg("mdCodeBlockBorder", text),
		quote: (text) => theme.fg("mdQuote", text),
		quoteBorder: (text) => theme.fg("mdQuoteBorder", text),
		hr: (text) => theme.fg("mdHr", text),
		listBullet: (text) => theme.fg("mdListBullet", text),
		bold: (text) => theme.bold(text),
		italic: (text) => theme.italic(text),
		underline: (text) => theme.underline(text),
		strikethrough: (text) => theme.strikethrough(text),
		highlightCode: (code, lang) => {
			// Validate language before highlighting to avoid stderr spam from cli-highlight
			const validLang = lang && supportsLanguage(lang) ? lang : undefined;
			// Skip highlighting when no valid language is specified. cli-highlight's
			// auto-detection is unreliable and can misidentify prose as AppleScript,
			// LiveCodeServer, etc., coloring random English words as keywords.
			if (!validLang) {
				return code.split("\n").map((line) => theme.fg("mdCodeBlock", line));
			}
			const opts = {
				language: validLang,
				ignoreIllegals: true,
				theme: getCliHighlightTheme(theme),
			};
			try {
				return highlight(code, opts).split("\n");
			} catch {
				return code.split("\n").map((line) => theme.fg("mdCodeBlock", line));
			}
		},
	};
}

function getSelectListTheme() {
	return {
		selectedPrefix: (text) => theme.fg("accent", text),
		selectedText: (text) => theme.fg("accent", text),
		description: (text) => theme.fg("muted", text),
		scrollInfo: (text) => theme.fg("muted", text),
		noMatch: (text) => theme.fg("muted", text),
	};
}

function getEditorTheme() {
	return {
		borderColor: (text) => theme.fg("borderMuted", text),
		selectList: getSelectListTheme(),
	};
}

function getSettingsListTheme() {
	return {
		label: (text, selected) => (selected ? theme.fg("accent", text) : text),
		value: (text, selected) => (selected ? theme.fg("accent", text) : theme.fg("muted", text)),
		description: (text) => theme.fg("dim", text),
		cursor: theme.fg("accent", "→ "),
		hint: (text) => theme.fg("dim", text),
	};
}

return { highlightCode, getLanguageFromPath, getMarkdownTheme, getSelectListTheme, getSettingsListTheme, getEditorTheme };
};
