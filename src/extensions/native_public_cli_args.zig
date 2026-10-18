//! Actual c268 cli/args.ts module. Public parseArgs consumes its argument as
//! Source does: live JS length/index/method reads, recoverable diagnostics,
//! ordinary Map storage, and an explicit IteratorClose for the "--" tail.
//! Source authority: cli/args.ts EF7B54F02939D2EBC8EC2DEFCF4C2D9BE90FE979C2C74675D970A4DD14AADAD3.
const v = @import("native_public_values.zig");
const c = v.c;
const Scope = v.Scope;
const Engine = v.em.Engine;
const levels = [_][]const u8{ "off", "minimal", "low", "medium", "high", "xhigh", "max" };

pub fn create(engine: *Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, createBody(&s));
}
fn createBody(s: *Scope) !c.JSValue {
    const thinking = try v.array(s);
    for (levels, 0..) |level, position| try v.index(s, thinking, @intCast(position), try v.text(s, level));
    const valid = try v.ordinary(s, "isValidThinkingLevel", 1, validThinking, &.{thinking});
    const modifier = try v.ordinary(s, "isToolModifier", 1, isToolModifier, &.{});
    const tool_error = try v.ordinary(s, "getToolListError", 1, getToolListError, &.{modifier});
    const exports = try v.object(s);
    try v.put(s, exports, "parseArgs", try v.ordinary(s, "parseArgs", 1, parseArgs, &.{ thinking, valid, tool_error }));
    try v.put(s, exports, "isValidThinkingLevel", valid);
    try v.put(s, exports, "normalizeSessionName", try v.ordinary(s, "normalizeSessionName", 1, normalizeSessionName, &.{}));
    return v.duplicate(s, exports);
}
fn validThinking(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.invokeOwned(engine, roots[0], "includes", &.{v.arg(args, 0)});
}
fn normalizeSessionName(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, normalizeBody(&s, v.arg(args, 0)));
}
fn normalizeBody(s: *Scope, input: c.JSValue) !c.JSValue {
    const name = try v.invoke(s, input, "trim", &.{});
    const positive = v.truthy(s, try v.binary(s, 6, try v.get(s, name, "length"), v.number(s, 0)));
    return if (positive) v.duplicate(s, name) else c.pi_js_undefined();
}
fn trim(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.invokeOwned(engine, v.arg(args, 0), "trim", &.{});
}
fn nonempty(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, nonemptyBody(&s, v.arg(args, 0)));
}
fn nonemptyBody(s: *Scope, input: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.binary(s, 6, try v.get(s, input, "length"), v.number(s, 0)));
}
fn isToolModifier(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, modifierBody(&s, v.arg(args, 0)));
}
fn modifierBody(s: *Scope, entry: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(entry)) return v.boolean(s, false);
    const plus = try v.own(s, try v.invokeTextOwned(s.engine, entry, "startsWith", "+"));
    if (v.truthy(s, plus)) return v.duplicate(s, plus);
    return v.invokeTextOwned(s.engine, entry, "startsWith", "-");
}
fn patternEntry(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.invokeTextOwned(engine, v.arg(args, 0), "includes", "*");
}
fn getToolListError(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, toolErrorBody(&s, v.arg(args, 0), roots[0]));
}
fn toolErrorBody(s: *Scope, entries: c.JSValue, modifier: c.JSValue) !c.JSValue {
    const modifiers = try v.invoke(s, entries, "filter", &.{modifier});
    if (try modifierLengthTest(s.engine, modifiers, entries, true)) return c.pi_js_undefined();
    if (try modifierLengthTest(s.engine, modifiers, entries, false))
        return v.duplicate(s, try v.text(s, "tool names cannot be mixed with +name or -name entries"));
    const pattern = try v.own(s, try findPattern(s.engine, modifiers));
    if (v.truthy(s, pattern)) return templateOwned(s.engine, "+name and -name entries take exact tool names, not patterns: ", pattern, "");
    return c.pi_js_undefined();
}

fn modifierLengthTest(engine: *Engine, modifiers: c.JSValue, entries: c.JSValue, zero: bool) !bool {
    var s: Scope = .{ .engine = engine };
    const result = try v.owned.finishValue(&s, modifierLengthBody(&s, modifiers, entries, zero));
    return c.JS_ToBool(engine.context, result) == 1;
}
fn modifierLengthBody(s: *Scope, modifiers: c.JSValue, entries: c.JSValue, zero: bool) !c.JSValue {
    const left = try v.get(s, modifiers, "length");
    if (zero) return v.boolean(s, v.equal(s, left, v.number(s, 0)));
    const right = try v.get(s, entries, "length");
    return v.duplicate(s, try v.binary(s, 4, left, right));
}
fn findPattern(engine: *Engine, modifiers: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, findPatternBody(&s, modifiers));
}
fn findPatternBody(s: *Scope, modifiers: c.JSValue) !c.JSValue {
    const find = try v.get(s, modifiers, "find");
    const pattern = try v.call(s, find, modifiers, &.{try v.arrow(s, "", 1, patternEntry, &.{})});
    return v.duplicate(s, pattern);
}

fn parseArgs(engine: *Engine, _: c.JSValue, arguments: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, parseBody(&s, v.arg(arguments, 0), roots));
}
fn parseBody(s: *Scope, arguments: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const result = try v.own(s, try initialResult(s.engine));
    var i: f64 = 0;
    var steps: usize = 0;
    while (try loopTest(s.engine, arguments, i, &steps)) : (i += 1) {
        if (try iteration(s.engine, result, arguments, &i, roots)) break;
    }
    return v.duplicate(s, result);
}
fn initialResult(engine: *Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, initialBody(&s));
}
fn initialBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "messages", try v.array(s));
    try v.put(s, result, "fileArgs", try v.array(s));
    try v.put(s, result, "unknownFlags", try v.construct(s, try v.global(s, "Map"), &.{}));
    try v.put(s, result, "diagnostics", try v.array(s));
    return v.duplicate(s, result);
}
fn loopTest(engine: *Engine, arguments: c.JSValue, position: f64, steps: *usize) !bool {
    try v.poll(engine, steps);
    return hasNext(engine, arguments, position);
}
fn hasNext(engine: *Engine, arguments: c.JSValue, position: f64) !bool {
    var s: Scope = .{ .engine = engine };
    const value = try v.owned.finishValue(&s, lengthTest(&s, arguments, position));
    return c.JS_ToBool(engine.context, value) == 1;
}
fn lengthTest(s: *Scope, arguments: c.JSValue, position: f64) !c.JSValue {
    return v.duplicate(s, try v.binary(s, 4, v.number(s, position), try v.get(s, arguments, "length")));
}
fn atPosition(s: *Scope, arguments: c.JSValue, position: f64) !c.JSValue { return v.key(s, arguments, v.number(s, position)); }
fn iteration(engine: *Engine, result: c.JSValue, arguments: c.JSValue, position: *f64, roots: []const c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    const value = try v.owned.finishValue(&s, iterationBody(&s, result, arguments, position, roots));
    return c.JS_ToBool(engine.context, value) == 1;
}
const Flag = struct { long: []const u8, short: ?[]const u8 = null, field: [*:0]const u8, value: bool = true };
const flags = [_]Flag{
    .{ .long = "--help", .short = "-h", .field = "help" },
    .{ .long = "--version", .short = "-v", .field = "version" },
    .{ .long = "--continue", .short = "-c", .field = "continue" },
    .{ .long = "--resume", .short = "-r", .field = "resume" },
    .{ .long = "--no-session", .field = "noSession" },
    .{ .long = "--no-tools", .short = "-nt", .field = "noTools" },
    .{ .long = "--no-builtin-tools", .short = "-nbt", .field = "noBuiltinTools" },
    .{ .long = "--no-extensions", .short = "-ne", .field = "noExtensions" },
    .{ .long = "--no-mcp", .field = "noMcp" },
    .{ .long = "--no-skills", .short = "-ns", .field = "noSkills" },
    .{ .long = "--no-prompt-templates", .short = "-np", .field = "noPromptTemplates" },
    .{ .long = "--no-themes", .field = "noThemes" },
    .{ .long = "--no-context-files", .short = "-nc", .field = "noContextFiles" },
    .{ .long = "--verbose", .field = "verbose" },
    .{ .long = "--approve", .short = "-a", .field = "projectTrustOverride" },
    .{ .long = "--no-approve", .short = "-na", .field = "projectTrustOverride", .value = false },
    .{ .long = "--offline", .field = "offline" },
};
const ValueFlag = struct { long: []const u8, field: [*:0]const u8 };
const value_flags = [_]ValueFlag{
    .{ .long = "--provider", .field = "provider" }, .{ .long = "--model", .field = "model" },
    .{ .long = "--api-key", .field = "apiKey" }, .{ .long = "--system-prompt", .field = "systemPrompt" },
    .{ .long = "--session", .field = "session" }, .{ .long = "--session-id", .field = "sessionId" },
    .{ .long = "--fork", .field = "fork" }, .{ .long = "--session-dir", .field = "sessionDir" },
    .{ .long = "--export", .field = "export" },
};
const AppendFlag = struct { long: []const u8, short: ?[]const u8 = null, field: [*:0]const u8 };
const append_flags = [_]AppendFlag{
    .{ .long = "--append-system-prompt", .field = "appendSystemPrompt" },
    .{ .long = "--extension", .short = "-e", .field = "extensions" },
    .{ .long = "--skill", .field = "skills" },
    .{ .long = "--prompt-template", .field = "promptTemplates" },
    .{ .long = "--theme", .field = "themes" },
};
fn matches(s: *Scope, value: c.JSValue, long: []const u8, short: ?[]const u8) !bool {
    return try v.eq(s, value, long) or if (short) |alias| try v.eq(s, value, alias) else false;
}
fn iterationBody(s: *Scope, result: c.JSValue, arguments: c.JSValue, position: *f64, roots: []const c.JSValue) !c.JSValue {
    const arg = try atPosition(s, arguments, position.*);
    if (try v.eq(s, arg, "--")) {
        try positionalTail(s.engine, result, arguments, position.* + 1);
        return v.boolean(s, true);
    }
    for (flags) |flag| if (try matches(s, arg, flag.long, flag.short)) {
        try v.set(s, result, flag.field, v.boolean(s, flag.value));
        return v.boolean(s, false);
    };
    if (try v.eq(s, arg, "--mode")) {
        const mode = try atPosition(s, arguments, position.* + 1);
        if (c.JS_IsUndefined(mode) or try v.testText(s, mode, "startsWith", "-")) {
            try diagnosticText(s.engine, result, "error", "--mode requires text, json, or rpc");
            return v.boolean(s, false);
        }
        position.* += 1;
        if (!try v.eq(s, mode, "text") and !try v.eq(s, mode, "json") and !try v.eq(s, mode, "rpc")) {
            try diagnosticTemplate(s.engine, result, "error", "Invalid mode \"", mode, "\". Valid values: text, json, rpc");
            return v.boolean(s, false);
        }
        try v.set(s, result, "mode", mode);
        return v.boolean(s, false);
    }
    for (value_flags) |flag| if (try v.eq(s, arg, flag.long)) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            position.* += 1;
            try v.set(s, result, flag.field, try atPosition(s, arguments, position.*));
            return v.boolean(s, false);
        }
        break;
    };
    for (append_flags) |flag| if (try matches(s, arg, flag.long, flag.short)) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            try ensureArray(s.engine, result, flag.field);
            try appendNext(s.engine, result, flag.field, arguments, position);
            return v.boolean(s, false);
        }
        break;
    };
    if (try matches(s, arg, "--name", "-n")) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            position.* += 1;
            try v.set(s, result, "name", try atPosition(s, arguments, position.*));
        } else try diagnosticText(s.engine, result, "error", "--name requires a value");
        return v.boolean(s, false);
    }
    if (try v.eq(s, arg, "--models")) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            position.* += 1;
            const patterns = try v.own(s, try commaList(s.engine, arguments, position.*));
            try v.set(s, result, "models", patterns);
            return v.boolean(s, false);
        }
    }
    if (try matches(s, arg, "--tools", "-t")) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            position.* += 1;
            const tools = try v.own(s, try commaList(s.engine, arguments, position.*));
            const error_value = try v.call(s, roots[2], c.pi_js_undefined(), &.{tools});
            if (v.truthy(s, error_value)) try diagnosticPair(s.engine, result, "error", arg, error_value)
            else try v.set(s, result, "tools", tools);
            return v.boolean(s, false);
        }
    }
    if (try matches(s, arg, "--exclude-tools", "-xt")) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            position.* += 1;
            const excluded = try v.own(s, try commaList(s.engine, arguments, position.*));
            try v.set(s, result, "excludeTools", excluded);
            return v.boolean(s, false);
        }
    }
    if (try v.eq(s, arg, "--thinking")) {
        if (try hasNext(s.engine, arguments, position.* + 1)) {
            position.* += 1;
            const level = try atPosition(s, arguments, position.*);
            if (try validLevelTest(s.engine, roots[1], level)) try v.set(s, result, "thinking", level)
            else try invalidThinking(s.engine, result, roots[0], level);
            return v.boolean(s, false);
        }
    }
    if (try matches(s, arg, "--print", "-p")) {
        try v.set(s, result, "print", v.boolean(s, true));
        const next = try atPosition(s, arguments, position.* + 1);
        if (!c.JS_IsUndefined(next) and !try v.testText(s, next, "startsWith", "@") and
            (!try v.testText(s, next, "startsWith", "-") or try v.testText(s, next, "startsWith", "---")))
        {
            try appendValue(s.engine, result, "messages", next); position.* += 1;
        }
        return v.boolean(s, false);
    }
    if (try v.eq(s, arg, "--use-theme")) {
        const name = try atPosition(s, arguments, position.* + 1);
        if (c.JS_IsUndefined(name) or try v.testText(s, name, "startsWith", "-"))
            try diagnosticText(s.engine, result, "error", "--use-theme requires a theme name")
        else { try v.set(s, result, "useTheme", name); position.* += 1; }
        return v.boolean(s, false);
    }
    if (try v.eq(s, arg, "--list-models")) {
        if (try hasNext(s.engine, arguments, position.* + 1) and
            !try nextStarts(s.engine, arguments, position.* + 1, "-") and
            !try nextStarts(s.engine, arguments, position.* + 1, "@"))
        {
            position.* += 1; try v.set(s, result, "listModels", try atPosition(s, arguments, position.*));
        } else try v.set(s, result, "listModels", v.boolean(s, true));
        return v.boolean(s, false);
    }
    if (try v.eq(s, arg, "--tui-mode")) {
        const mode = try atPosition(s, arguments, position.* + 1);
        if (try v.eq(s, mode, "regular") or try v.eq(s, mode, "fullscreen")) {
            try v.set(s, result, "tuiMode", mode); position.* += 1;
        } else if (c.JS_IsUndefined(mode) or try v.testText(s, mode, "startsWith", "-")) {
            try diagnosticText(s.engine, result, "error", "--tui-mode requires regular or fullscreen");
        } else {
            position.* += 1;
            try diagnosticTemplate(s.engine, result, "error", "Invalid TUI mode \"", mode, "\". Valid values: regular, fullscreen");
        }
        return v.boolean(s, false);
    }
    if (try v.testText(s, arg, "startsWith", "@")) {
        try appendSliced(s.engine, result, arg);
    } else if (try v.testText(s, arg, "startsWith", "--")) {
        const eq_index = try v.own(s, try v.invokeTextOwned(s.engine, arg, "indexOf", "="));
        if (!v.equal(s, eq_index, v.number(s, -1))) {
            try unknownEquals(s.engine, result, arg, eq_index);
        } else {
            const flag_name = try v.invoke(s, arg, "slice", &.{v.number(s, 2)});
            const next = try atPosition(s, arguments, position.* + 1);
            if (!c.JS_IsUndefined(next) and !try v.testText(s, next, "startsWith", "-") and !try v.testText(s, next, "startsWith", "@")) {
                try unknownValue(s.engine, result, flag_name, next); position.* += 1;
            } else try unknownValue(s.engine, result, flag_name, v.boolean(s, true));
        }
    } else if (try v.testText(s, arg, "startsWith", "-") and !try v.testText(s, arg, "startsWith", "--")) {
        try diagnosticTemplate(s.engine, result, "error", "Unknown option: ", arg, "");
    } else if (!try v.testText(s, arg, "startsWith", "-")) {
        try appendValue(s.engine, result, "messages", arg);
    }
    return v.boolean(s, false);
}

fn ensureArray(engine: *Engine, result: c.JSValue, field: [*:0]const u8) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, ensureBody(&s, result, field));
}
fn ensureBody(s: *Scope, result: c.JSValue, field: [*:0]const u8) !void {
    const previous = try v.get(s, result, field);
    try v.set(s, result, field, if (v.nullish(previous)) try v.array(s) else previous);
}
fn appendNext(engine: *Engine, result: c.JSValue, field: [*:0]const u8, arguments: c.JSValue, position: *f64) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, appendNextBody(&s, result, field, arguments, position));
}
fn appendNextBody(s: *Scope, result: c.JSValue, field: [*:0]const u8, arguments: c.JSValue, position: *f64) !void {
    const receiver = try v.get(s, result, field);
    const push = try v.get(s, receiver, "push");
    position.* += 1;
    _ = try v.call(s, push, receiver, &.{try atPosition(s, arguments, position.*)});
}
fn appendValue(engine: *Engine, result: c.JSValue, field: [*:0]const u8, value: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, appendValueBody(&s, result, field, value));
}
fn appendValueBody(s: *Scope, result: c.JSValue, field: [*:0]const u8, value: c.JSValue) !void {
    const receiver = try v.get(s, result, field);
    _ = try v.call(s, try v.get(s, receiver, "push"), receiver, &.{value});
}
fn appendSliced(engine: *Engine, result: c.JSValue, value: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, appendSlicedBody(&s, result, value));
}
fn appendSlicedBody(s: *Scope, result: c.JSValue, value: c.JSValue) !void {
    const receiver = try v.get(s, result, "fileArgs");
    const push = try v.get(s, receiver, "push");
    _ = try v.call(s, push, receiver, &.{try v.invoke(s, value, "slice", &.{v.number(s, 1)})});
}
fn commaList(engine: *Engine, arguments: c.JSValue, position: f64) !c.JSValue {
    const split = try splitNext(engine, arguments, position);
    const mapped = try arrayCallback(engine, split, "map", trim);
    return arrayCallback(engine, mapped, "filter", nonempty);
}
fn splitNext(engine: *Engine, arguments: c.JSValue, position: f64) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, splitNextBody(&s, arguments, position));
}
fn splitNextBody(s: *Scope, arguments: c.JSValue, position: f64) !c.JSValue {
    const input = try atPosition(s, arguments, position);
    return v.invokeTextOwned(s.engine, input, "split", ",");
}
fn arrayCallback(engine: *Engine, incoming: c.JSValue, name: [*:0]const u8, callback: v.function.Callback) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, arrayCallbackBody(&s, incoming, name, callback));
}
fn arrayCallbackBody(s: *Scope, incoming: c.JSValue, name: [*:0]const u8, callback: v.function.Callback) !c.JSValue {
    const receiver = try v.own(s, incoming);
    const callable = try v.get(s, receiver, name);
    const transform = try v.arrow(s, "", 1, callback, &.{});
    return v.duplicate(s, try v.call(s, callable, receiver, &.{transform}));
}
fn nextStarts(engine: *Engine, arguments: c.JSValue, position: f64, prefix: []const u8) !bool {
    var s: Scope = .{ .engine = engine };
    const value = try v.owned.finishValue(&s, nextStartsBody(&s, arguments, position, prefix));
    return c.JS_ToBool(engine.context, value) == 1;
}
fn nextStartsBody(s: *Scope, arguments: c.JSValue, position: f64, prefix: []const u8) !c.JSValue {
    return v.boolean(s, try v.testText(s, try atPosition(s, arguments, position), "startsWith", prefix));
}
fn validLevelTest(engine: *Engine, valid: c.JSValue, level: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    const value = try v.owned.finishValue(&s, validLevelBody(&s, valid, level));
    return c.JS_ToBool(engine.context, value) == 1;
}
fn validLevelBody(s: *Scope, valid: c.JSValue, level: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.call(s, valid, c.pi_js_undefined(), &.{level})));
}
fn templateOwned(engine: *Engine, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, templateBody(&s, prefix, value, suffix));
}
fn templateBody(s: *Scope, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    const start = try v.binary(s, 0, try v.text(s, prefix), try v.stringify(s, value));
    return v.duplicate(s, try v.binary(s, 0, start, try v.text(s, suffix)));
}
fn diagnosticText(engine: *Engine, result: c.JSValue, kind: []const u8, message: []const u8) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, diagnosticTextBody(&s, result, kind, message));
}
fn diagnosticTextBody(s: *Scope, result: c.JSValue, kind: []const u8, message: []const u8) !void {
    const receiver = try v.get(s, result, "diagnostics");
    const push = try v.get(s, receiver, "push");
    const entry = try v.object(s);
    try v.put(s, entry, "type", try v.text(s, kind));
    try v.put(s, entry, "message", try v.text(s, message));
    _ = try v.call(s, push, receiver, &.{entry});
}
fn diagnosticTemplate(engine: *Engine, result: c.JSValue, kind: []const u8, prefix: []const u8, value: c.JSValue, suffix: []const u8) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, diagnosticTemplateBody(&s, result, kind, prefix, value, suffix));
}
fn diagnosticTemplateBody(s: *Scope, result: c.JSValue, kind: []const u8, prefix: []const u8, value: c.JSValue, suffix: []const u8) !void {
    const receiver = try v.get(s, result, "diagnostics");
    const push = try v.get(s, receiver, "push");
    const entry = try v.object(s);
    try v.put(s, entry, "type", try v.text(s, kind));
    const message = try v.own(s, try templateOwned(s.engine, prefix, value, suffix));
    try v.put(s, entry, "message", message);
    _ = try v.call(s, push, receiver, &.{entry});
}
fn diagnosticPair(engine: *Engine, result: c.JSValue, kind: []const u8, left: c.JSValue, right: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, diagnosticPairBody(&s, result, kind, left, right));
}
fn diagnosticPairBody(s: *Scope, result: c.JSValue, kind: []const u8, left: c.JSValue, right: c.JSValue) !void {
    const receiver = try v.get(s, result, "diagnostics");
    const push = try v.get(s, receiver, "push");
    const entry = try v.object(s);
    try v.put(s, entry, "type", try v.text(s, kind));
    const prefix = try v.binary(s, 0, try v.stringify(s, left), try v.text(s, ": "));
    try v.put(s, entry, "message", try v.binary(s, 0, prefix, try v.stringify(s, right)));
    _ = try v.call(s, push, receiver, &.{entry});
}
fn invalidThinking(engine: *Engine, result: c.JSValue, valid_levels: c.JSValue, level: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, invalidThinkingBody(&s, result, valid_levels, level));
}
fn invalidThinkingBody(s: *Scope, result: c.JSValue, valid_levels: c.JSValue, level: c.JSValue) !void {
    const receiver = try v.get(s, result, "diagnostics");
    const push = try v.get(s, receiver, "push");
    const entry = try v.object(s);
    try v.put(s, entry, "type", try v.text(s, "warning"));
    const message = try v.own(s, try invalidThinkingMessage(s.engine, valid_levels, level));
    try v.put(s, entry, "message", message);
    _ = try v.call(s, push, receiver, &.{entry});
}
fn invalidThinkingMessage(engine: *Engine, valid_levels: c.JSValue, level: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, invalidThinkingMessageBody(&s, valid_levels, level));
}
fn invalidThinkingMessageBody(s: *Scope, valid_levels: c.JSValue, level: c.JSValue) !c.JSValue {
    const prefix = try v.own(s, try templateOwned(s.engine, "Invalid thinking level \"", level, "\". Valid values: "));
    const joined = try v.own(s, try v.invokeTextOwned(s.engine, valid_levels, "join", ", "));
    return v.duplicate(s, try v.binary(s, 0, prefix, try v.stringify(s, joined)));
}
fn unknownValue(engine: *Engine, result: c.JSValue, name: c.JSValue, value: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, unknownValueBody(&s, result, name, value));
}
fn unknownValueBody(s: *Scope, result: c.JSValue, name: c.JSValue, value: c.JSValue) !void {
    const receiver = try v.get(s, result, "unknownFlags");
    _ = try v.call(s, try v.get(s, receiver, "set"), receiver, &.{ name, value });
}
fn unknownEquals(engine: *Engine, result: c.JSValue, value: c.JSValue, equal_index: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, unknownEqualsBody(&s, result, value, equal_index));
}
fn unknownEqualsBody(s: *Scope, result: c.JSValue, value: c.JSValue, equal_index: c.JSValue) !void {
    const receiver = try v.get(s, result, "unknownFlags");
    const set = try v.get(s, receiver, "set");
    const name = try v.invoke(s, value, "slice", &.{ v.number(s, 2), equal_index });
    const slice = try v.get(s, value, "slice");
    const start = try v.binary(s, 0, equal_index, v.number(s, 1));
    const flag_value = try v.call(s, slice, value, &.{start});
    _ = try v.call(s, set, receiver, &.{ name, flag_value });
}

fn positionalTail(engine: *Engine, result: c.JSValue, arguments: c.JSValue, position: f64) !void {
    const sliced = try v.invokeOwned(engine, arguments, "slice", &.{c.JS_NewFloat64(engine.context, position)});
    var iterator = try v.Iterator.initOwned(engine, sliced);
    return iterator.finish(tailBody(engine, result, &iterator));
}
fn tailBody(engine: *Engine, result: c.JSValue, iterator: *v.Iterator) !void {
    while (try iterator.next()) |value| {
        var s: Scope = .{ .engine = engine };
        try v.owned.finishVoid(&s, tailItem(&s, result, value));
    }
}
fn tailItem(s: *Scope, result: c.JSValue, incoming: c.JSValue) !void {
    const value = try v.own(s, incoming);
    if (try v.testText(s, value, "startsWith", "@")) try appendSliced(s.engine, result, value)
    else try appendValue(s.engine, result, "messages", value);
}
