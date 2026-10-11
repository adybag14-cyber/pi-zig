//! Actual structured prompt rendering through ordinary JS values and callbacks.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub fn initialize(engine: *em.Engine) !void {
    if (engine.native_sdk_prompt_section_regex != null) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var args = [_]c.JSValue{ try scope.text("^[a-z][a-z0-9_-]*$"), try scope.text("") };
    engine.native_sdk_prompt_section_regex = try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, args.len, &args));
}
const Callback = enum(c_int) { declared, visible, tool_line, rule_line, project_file, reader, skill_visible, part_visible };
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return callbackValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic), data) catch |err| sdk.fail(engine, err);
}
fn function(scope: *Scope, kind: Callback, data: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), @intCast(data.len), @constCast(data.ptr))));
}
fn callbackValue(engine: *em.Engine, value: c.JSValue, kind: Callback, data: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .declared => c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.invoke(data[0], "includes", &.{value})))),
        .reader => try scope.invoke(data[0], "includes", &.{value}),
        .visible => c.pi_js_bool(engine.context, @intFromBool(scope.truthy(try scope.own(try js.getKey(engine, data[0], value))))),
        .skill_visible => c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.get(value, "disableModelInvocation")))),
        .part_visible => c.pi_js_bool(engine.context, @intFromBool(try scope.positive(try scope.get(value, "length")))),
        .rule_line => try scope.concat(try scope.text("- "), try scope.stringify(value)),
        .tool_line => line: {
            const name = try scope.stringify(value);
            const snippet = try scope.own(try js.getKey(engine, data[0], value));
            break :line try scope.concat(try scope.concat(try scope.concat(try scope.text("- "), name), try scope.text(": ")), try scope.stringify(snippet));
        },
        .project_file => line: {
            const path = try scope.get(value, "path");
            const content = try scope.get(value, "content");
            const prefix = try scope.concat(try scope.text("<project_instructions path=\""), try scope.stringify(path));
            const middle = try scope.concat(try scope.concat(prefix, try scope.text("\">\n")), try scope.stringify(content));
            break :line try scope.concat(middle, try scope.text("\n</project_instructions>"));
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn map(scope: *Scope, receiver: c.JSValue, method_name: [*:0]const u8, kind: Callback, data: []const c.JSValue) !c.JSValue {
    const method = try scope.get(receiver, method_name);
    return scope.call(method, receiver, &.{try function(scope, kind, data)});
}
fn literalRegex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn addRule(scope: *Scope, rules: c.JSValue, seen: c.JSValue, rule: c.JSValue) !void {
    const normalized = try scope.invoke(rule, "trim", &.{});
    if (!scope.truthy(normalized) or scope.truthy(try scope.invoke(seen, "has", &.{normalized}))) return;
    _ = try scope.invoke(seen, "add", &.{normalized});
    _ = try scope.invoke(rules, "push", &.{normalized});
}
fn addRules(scope: *Scope, rows: c.JSValue, rules: c.JSValue, seen: c.JSValue, symbol: c.JSValue) !void {
    var iterator = try js.Iterator.init(scope.engine, rows, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |rule| {
        defer scope.engine.freeValue(rule);
        try addRule(scope, rules, seen, rule);
    }
}
fn rulesText(scope: *Scope, selected: c.JSValue, guidelines: c.JSValue, prompt: c.JSValue) !c.JSValue {
    const rules = try scope.array();
    const seen = try scope.own(try js.builtin(scope.engine, "Set", &.{}));
    var present: [5]bool = undefined;
    inline for (.{ "bash", "powershell", "grep", "find", "ls" }, 0..) |name, index| present[index] = scope.truthy(try scope.invoke(selected, "includes", &.{try scope.text(name)}));
    if ((present[0] or present[1]) and !present[2] and !present[3] and !present[4]) {
        try addRule(scope, rules, seen, try scope.text(if (present[0] and present[1]) "Use bash or PowerShell for file operations like listing, searching, and finding files" else if (present[1]) "Use PowerShell for file operations like listing, searching, and finding files" else "Use bash for file operations like ls, rg, find"));
    }
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, selected, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |name| {
        defer scope.engine.freeValue(name);
        const raw = try scope.own(try js.getKey(scope.engine, guidelines, name));
        try addRules(scope, if (temp.nullish(raw)) try scope.array() else raw, rules, seen, symbol);
    }
    try addRules(scope, prompt, rules, seen, symbol);
    try addRule(scope, rules, seen, try scope.text("Be concise in your responses"));
    try addRule(scope, rules, seen, try scope.text("Show file paths clearly when working with files"));
    const lines = try map(scope, rules, "map", .rule_line, &.{});
    return scope.invoke(lines, "join", &.{try scope.text("\n")});
}
fn packagePath(scope: *Scope, leaf: []const u8) !c.JSValue {
    const engine = scope.engine;
    const process = try scope.global("process");
    const configured = if (c.JS_IsUndefined(process)) c.pi_js_undefined() else try scope.get(try scope.get(process, "env"), "PI_PACKAGE_DIR");
    const directory = if (scope.truthy(configured)) try scope.own(try @import("native_sdk_settings.zig").normalizePath(engine, configured)) else blk: {
        const executable = try std.process.executablePathAlloc(engine.native_io orelse return error.NativeIoUnavailable, engine.gpa);
        defer engine.gpa.free(executable);
        break :blk try scope.text(std.fs.path.dirname(executable) orelse ".");
    };
    const raw = try engine.toString(directory);
    defer engine.gpa.free(raw);
    const cwd = try sdk.cwd(engine);
    defer engine.gpa.free(cwd);
    const path = try @import("node_path.zig").resolve(engine.gpa, cwd, &.{ raw, leaf }, if (builtin.os.tag == .windows) .win32 else .posix);
    defer engine.gpa.free(path);
    return scope.text(path);
}
fn docsText(scope: *Scope) !c.JSValue {
    var text = try scope.concat(try scope.text("Pi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):\n- Main documentation: "), try scope.stringify(try packagePath(scope, "README.md")));
    text = try scope.concat(try scope.concat(text, try scope.text("\n- Additional docs: ")), try scope.stringify(try packagePath(scope, "docs")));
    text = try scope.concat(try scope.concat(text, try scope.text("\n- Examples: ")), try scope.stringify(try packagePath(scope, "examples")));
    return scope.concat(text, try scope.text(" (extensions, custom tools, SDK)\n- When reading pi docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory\n- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), pi packages (docs/packages.md), environment variables (docs/environment-variables.md), MCP servers (docs/mcp.md), codemode scripts and non-LLM models such as classifiers and image models (docs/codemode.md)\n- When working on pi topics, read the docs and examples, and follow .md cross-references before implementing\n- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)"));
}
pub fn resolvePackagePath(engine: *em.Engine, leaf: []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try packagePath(&scope, leaf));
}
fn projectText(scope: *Scope, files: c.JSValue) !c.JSValue {
    const mapped = try map(scope, files, "map", .project_file, &.{});
    const lines = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, mapped, try scope.text("Project-specific instructions and guidelines:")));
    return scope.invoke(lines, "join", &.{try scope.text("\n\n")});
}
fn escapeXml(scope: *Scope, original: c.JSValue) !c.JSValue {
    var value = original;
    inline for (.{ .{ "&", "&amp;" }, .{ "<", "&lt;" }, .{ ">", "&gt;" }, .{ "\"", "&quot;" }, .{ "'", "&apos;" } }) |pair| {
        const method = try scope.get(value, "replace");
        value = try scope.call(method, value, &.{ try literalRegex(scope, pair[0], "g"), try scope.text(pair[1]) });
    }
    return value;
}
fn skillLine(scope: *Scope, lines: c.JSValue, skill: c.JSValue, field: [*:0]const u8, tag: []const u8) !void {
    const push = try scope.get(lines, "push");
    const raw = try scope.get(skill, field);
    const escaped = try escapeXml(scope, raw);
    const prefix = try scope.concat(try scope.concat(try scope.text("    <"), try scope.text(tag)), try scope.text(">"));
    const closing = try scope.concat(try scope.concat(try scope.text("</"), try scope.text(tag)), try scope.text(">"));
    _ = try scope.call(push, lines, &.{try scope.concat(try scope.concat(prefix, try scope.stringify(escaped)), closing)});
}
fn skillsText(scope: *Scope, skills: c.JSValue, reader: c.JSValue) !c.JSValue {
    const visible = try map(scope, skills, "filter", .skill_visible, &.{});
    if (scope.equal(try scope.get(visible, "length"), c.JS_NewInt32(scope.engine.context, 0))) return scope.text("");
    const lines = try scope.array();
    const hint = if (scope.equal(reader, try scope.text("read"))) "Use the read tool to load a skill's file when the task matches its description." else if (scope.equal(reader, try scope.text("bash"))) "Use bash to load a skill's file when the task matches its description." else "Load a skill's file when the task matches its description.";
    try scope.index(lines, 0, try scope.text("\n\nThe following skills provide specialized instructions for specific tasks."));
    try scope.index(lines, 1, try scope.text(hint));
    try scope.index(lines, 2, try scope.text("When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands."));
    try scope.index(lines, 3, try scope.text(""));
    try scope.index(lines, 4, try scope.text("<available_skills>"));
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, visible, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |skill| {
        defer scope.engine.freeValue(skill);
        _ = try scope.invoke(lines, "push", &.{try scope.text("  <skill>")});
        try skillLine(scope, lines, skill, "name", "name");
        try skillLine(scope, lines, skill, "description", "description");
        try skillLine(scope, lines, skill, "filePath", "location");
        _ = try scope.invoke(lines, "push", &.{try scope.text("  </skill>")});
    }
    _ = try scope.invoke(lines, "push", &.{try scope.text("</available_skills>")});
    return scope.invoke(lines, "join", &.{try scope.text("\n")});
}
fn entries(scope: *Scope, value: c.JSValue) !c.JSValue {
    const object = try scope.global("Object");
    return scope.invoke(object, "entries", &.{value});
}
fn sections(scope: *Scope, input: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const options = try scope.own(try @import("native_sdk_prompt_normalize.zig").normalize(engine, input));
    var fields: [11]c.JSValue = undefined;
    inline for (.{ "customPrompt", "selectedTools", "hiddenTools", "toolSnippets", "toolGuidelines", "promptGuidelines", "appendSystemPrompt", "sections", "cwd", "contextFiles", "skills" }, 0..) |name, index| fields[index] = try scope.get(options, name);
    const object = try scope.global("Object");
    const names = try scope.invoke(object, "keys", &.{fields[7]});
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var names_iterator = try js.Iterator.init(engine, names, symbol);
    defer names_iterator.deinit();
    errdefer names_iterator.closePreserving();
    while (try names_iterator.next()) |name| {
        defer engine.freeValue(name);
        if (!scope.truthy(try scope.invoke(engine.native_sdk_prompt_section_regex.?, "test", &.{name})) or scope.equal(name, try scope.text("preamble"))) {
            const constructor = try scope.global("Error");
            const message = try scope.concat(try scope.text("Invalid system prompt section name: "), try scope.stringify(name));
            var args = [_]c.JSValue{message};
            const reason = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
            _ = c.JS_Throw(engine.context, reason);
            return js.capture(engine);
        }
    }
    const declared = try map(scope, fields[1], "filter", .declared, &.{fields[2]});
    const prompt = try scope.object();
    if (scope.truthy(fields[0])) {
        try scope.set(prompt, "preamble", fields[0]);
    } else {
        try scope.set(prompt, "preamble", try scope.text("You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files."));
        const visible = try map(scope, declared, "filter", .visible, &.{fields[3]});
        const tools = if (try scope.positive(try scope.get(visible, "length"))) try scope.invoke(try map(scope, visible, "map", .tool_line, &.{fields[3]}), "join", &.{try scope.text("\n")}) else try scope.text("(none)");
        try scope.set(prompt, "tools", try scope.concat(try scope.stringify(tools), try scope.text("\n\nIn addition to the tools above, you may have access to other custom tools depending on the project.")));
        try scope.set(prompt, "rules", try rulesText(scope, declared, fields[4], fields[5]));
        try scope.set(prompt, "docs", try docsText(scope));
    }
    if (scope.truthy(fields[6])) try scope.set(prompt, "addendum", fields[6]);
    if (try scope.positive(try scope.get(fields[9], "length"))) try scope.set(prompt, "project_context", try projectText(scope, fields[9]));
    const readers = try scope.array();
    try scope.index(readers, 0, try scope.text("read"));
    try scope.index(readers, 1, try scope.text("bash"));
    var reader = try map(scope, readers, "find", .reader, &.{declared});
    if (temp.nullish(reader)) reader = if (scope.truthy(try map(scope, readers, "some", .reader, &.{fields[1]}))) try scope.text("indirect") else c.pi_js_undefined();
    if (scope.truthy(reader) and try scope.positive(try scope.get(fields[10], "length"))) {
        const rendered = try scope.invoke(try skillsText(scope, fields[10], reader), "trim", &.{});
        if (scope.truthy(rendered)) try scope.set(prompt, "skills", rendered);
    }
    const replace = try scope.get(fields[8], "replace");
    try scope.set(prompt, "cwd", try scope.call(replace, fields[8], &.{ try literalRegex(scope, "\\\\", "g"), try scope.text("/") }));
    const custom_entries = try entries(scope, fields[7]);
    var custom_iterator = try js.Iterator.init(engine, custom_entries, symbol);
    defer custom_iterator.deinit();
    errdefer custom_iterator.closePreserving();
    while (try custom_iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |value| engine.freeValue(value);
        if (scope.truthy(pair[1])) try js.setKey(engine, prompt, pair[0], pair[1]);
    }
    const result = try scope.object();
    try scope.put(result, "preamble", try scope.get(prompt, "preamble"));
    const prompt_entries = try entries(scope, prompt);
    var prompt_iterator = try js.Iterator.init(engine, prompt_entries, symbol);
    defer prompt_iterator.deinit();
    errdefer prompt_iterator.closePreserving();
    while (try prompt_iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |value| engine.freeValue(value);
        if (scope.equal(pair[0], try scope.text("preamble"))) continue;
        const atom = try js.atom(engine, pair[0]);
        defer c.JS_FreeAtom(engine.context, atom);
        const opening = try scope.concat(try scope.concat(try scope.text("<"), try scope.stringify(pair[0])), try scope.text(">\n"));
        const body = try scope.concat(try scope.concat(opening, try scope.stringify(pair[1])), try scope.text("\n</"));
        const text = try scope.concat(try scope.concat(body, try scope.stringify(pair[0])), try scope.text(">"));
        if (c.JS_SetProperty(engine.context, result, atom, c.JS_DupValue(engine.context, text)) < 0) return js.capture(engine);
    }
    return result;
}
pub fn render(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    const forced = try scope.get(input, "forceSystemPrompt");
    if (!c.JS_IsUndefined(forced)) {
        try scope.put(state, "content", try scope.get(input, "forceSystemPrompt"));
    } else {
        try scope.put(state, "content", try scope.text(""));
        try scope.put(state, "sections", try sections(&scope, input));
    }
    const parts = try scope.array();
    try scope.index(parts, 0, try scope.own(try @import("native_sdk_transcript_replay.zig").contentText(engine, try scope.get(state, "content"))));
    const object = try scope.global("Object");
    const values = try scope.get(object, "values");
    const raw = try scope.get(state, "sections");
    const texts = try scope.call(values, object, &.{if (temp.nullish(raw)) try scope.object() else raw});
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, texts, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |text| {
        defer engine.freeValue(text);
        if (!c.JS_IsNull(text)) _ = try scope.invoke(parts, "push", &.{text});
    }
    const shown = try map(&scope, parts, "filter", .part_visible, &.{});
    return c.JS_DupValue(engine.context, try scope.invoke(shown, "join", &.{try scope.text("\n\n")}));
}
