//! Mutable normalized base prompt options exposed to live command contexts.
//! Rendering, per-request loadout and hidden declaration parity remain separate.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
pub fn rebuild(owner: *sdk.State) !void {
    const engine = owner.engine;
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    const loader = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(loader);
    try sdk.put(engine, options, "customPrompt", try sdk.invoke(engine, loader, "getSystemPrompt", &.{}));
    try sdk.put(engine, options, "forceSystemPrompt", c.pi_js_undefined());
    const selected = try @import("native_sdk_tool_catalog.zig").activeNames(owner);
    defer engine.freeValue(selected);
    try sdk.put(engine, options, "selectedTools", try copyRows(engine, selected, false));
    try sdk.put(engine, options, "hiddenTools", try sdk.array(engine));
    const metadata = try @import("native_sdk_tool_catalog.zig").promptMetadata(owner);
    defer engine.freeValue(metadata.snippets);
    defer engine.freeValue(metadata.guidelines);
    try sdk.put(engine, options, "toolSnippets", try js.spread(engine, metadata.snippets));
    try sdk.put(engine, options, "toolGuidelines", try copyGuidelines(engine, metadata.guidelines));
    try sdk.put(engine, options, "promptGuidelines", try sdk.array(engine));
    const appended = try sdk.invoke(engine, loader, "getAppendSystemPrompt", &.{});
    defer engine.freeValue(appended);
    const separator = try sdk.text(engine, "\n\n");
    defer engine.freeValue(separator);
    try sdk.put(engine, options, "appendSystemPrompt", try sdk.invoke(engine, appended, "join", &.{separator}));
    try sdk.put(engine, options, "sections", try sdk.object(engine));
    const cwd_value = try sdk.get(engine, owner.data, "_sdkToolCwd");
    defer engine.freeValue(cwd_value);
    const requested = try engine.toString(cwd_value);
    defer engine.gpa.free(requested);
    const current = try sdk.cwd(engine);
    defer engine.gpa.free(current);
    const normalized = try @import("node_path.zig").resolve(engine.gpa, current, &.{requested}, if (@import("builtin").os.tag == .windows) .win32 else .posix);
    defer engine.gpa.free(normalized);
    try sdk.put(engine, options, "cwd", try sdk.text(engine, normalized));
    const agents = try sdk.invoke(engine, loader, "getAgentsFiles", &.{});
    defer engine.freeValue(agents);
    const files = try sdk.get(engine, agents, "agentsFiles");
    defer engine.freeValue(files);
    try sdk.put(engine, options, "contextFiles", try copyRows(engine, files, true));
    const found = try sdk.invoke(engine, loader, "getSkills", &.{});
    defer engine.freeValue(found);
    const skills = try sdk.get(engine, found, "skills");
    defer engine.freeValue(skills);
    try sdk.put(engine, options, "skills", try copyRows(engine, skills, true));
    try sdk.put(engine, owner.data, "_baseSystemPromptOptions", c.JS_DupValue(engine.context, options));
}
pub const Metadata = struct { snippets: c.JSValue, guidelines: c.JSValue };
/// Source refresh normalizes all snippets first, then all guidelines. Activation
/// rebuilds copy this retained cache without reading definition getters again.
pub fn normalizeMetadata(engine: *em.Engine, records: anytype) !Metadata {
    const snippets = try sdk.object(engine);
    errdefer engine.freeValue(snippets);
    const guidelines = try sdk.object(engine);
    errdefer engine.freeValue(guidelines);
    for (records) |record| {
        const snippet = try sdk.get(engine, record.definition, "promptSnippet");
        defer engine.freeValue(snippet);
        if (c.JS_ToBool(engine.context, snippet) != 1) continue;
        const normalized = try normalizeSnippet(engine, snippet);
        defer engine.freeValue(normalized);
        const size = try sdk.get(engine, normalized, "length");
        defer engine.freeValue(size);
        if (c.JS_ToBool(engine.context, size) != 1) continue;
        const name = try sdk.get(engine, record.definition, "name");
        defer engine.freeValue(name);
        try js.setKey(engine, snippets, name, normalized);
    }
    for (records) |record| {
        const raw = try sdk.get(engine, record.definition, "promptGuidelines");
        defer engine.freeValue(raw);
        const normalized = try normalizeGuidelines(engine, raw);
        defer engine.freeValue(normalized);
        if (try sdk.length(engine, normalized) == 0) continue;
        const name = try sdk.get(engine, record.definition, "name");
        defer engine.freeValue(name);
        try js.setKey(engine, guidelines, name, normalized);
    }
    return .{ .snippets = snippets, .guidelines = guidelines };
}
fn copyGuidelines(engine: *em.Engine, source: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |name| {
        const rows = try engine.checked(c.JS_GetProperty(engine.context, source, name.atom));
        defer engine.freeValue(rows);
        if (c.JS_DefinePropertyValue(engine.context, result, name.atom, try copyRows(engine, rows, false), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return result;
}
fn copyRows(engine: *em.Engine, rows: c.JSValue, shallow: bool) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        try sdk.append(engine, result, if (shallow) try js.spread(engine, row) else c.JS_DupValue(engine.context, row));
    }
    return result;
}
fn normalizeSnippet(engine: *em.Engine, raw: c.JSValue) !c.JSValue {
    const flags = try sdk.text(engine, "g");
    defer engine.freeValue(flags);
    const lines = try sdk.text(engine, "[\r\n]+");
    defer engine.freeValue(lines);
    const spaces = try sdk.text(engine, "\\s+");
    defer engine.freeValue(spaces);
    const line_regex = try js.builtin(engine, "RegExp", &.{ lines, flags });
    defer engine.freeValue(line_regex);
    const space_regex = try js.builtin(engine, "RegExp", &.{ spaces, flags });
    defer engine.freeValue(space_regex);
    const space = try sdk.text(engine, " ");
    defer engine.freeValue(space);
    const first = try sdk.invoke(engine, raw, "replace", &.{ line_regex, space });
    defer engine.freeValue(first);
    const second = try sdk.invoke(engine, first, "replace", &.{ space_regex, space });
    defer engine.freeValue(second);
    return sdk.invoke(engine, second, "trim", &.{});
}
fn normalizeGuidelines(engine: *em.Engine, rows: c.JSValue) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsUndefined(rows) or c.JS_IsNull(rows)) return result;
    const seen = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(seen);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const normalized = try sdk.invoke(engine, row, "trim", &.{});
        defer engine.freeValue(normalized);
        const size = try sdk.get(engine, normalized, "length");
        defer engine.freeValue(size);
        if (c.JS_ToBool(engine.context, size) != 1) continue;
        const exists = try sdk.invoke(engine, seen, "has", &.{normalized});
        defer engine.freeValue(exists);
        if (c.JS_ToBool(engine.context, exists) == 1) continue;
        const ignored = try sdk.invoke(engine, seen, "add", &.{normalized});
        engine.freeValue(ignored);
        try sdk.append(engine, result, c.JS_DupValue(engine.context, normalized));
    }
    return result;
}
