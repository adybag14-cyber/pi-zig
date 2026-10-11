//! Source prompt argument parsing and substitution through native VM callbacks.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const utf16 = @import("native_utf16.zig");
const c = em.c;

pub fn expand(owner: *sdk.State, receiver: c.JSValue, input: c.JSValue) !c.JSValue {
    const expanded_skill = try @import("native_sdk_skill_expansion.zig").expand(owner, receiver, input);
    defer owner.engine.freeValue(expanded_skill);
    // Source evaluates [...this.promptTemplates] before entering
    // expandPromptTemplate, including for ordinary text and missing matches.
    const templates = try sdk.get(owner.engine, receiver, "promptTemplates");
    defer owner.engine.freeValue(templates);
    const snapshot = try @import("native_iterator_spread.zig").snapshot(owner.engine, templates);
    defer owner.engine.freeValue(snapshot);
    return expandTemplate(owner, expanded_skill, snapshot);
}
fn regexp(engine: *em.Engine, pattern: []const u8, flags: []const u8) !c.JSValue {
    const constructor = c.JS_DupValue(engine.context, engine.intrinsic_regexp_constructor);
    defer engine.freeValue(constructor);
    const expression = try sdk.text(engine, pattern);
    defer engine.freeValue(expression);
    const options = try sdk.text(engine, flags);
    defer engine.freeValue(options);
    var args = [_]c.JSValue{ expression, options };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
}
fn whitespace(unit: u16) bool {
    return switch (unit) {
        0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
pub fn parseArgs(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    const units = try utf16.unitsAlloc(engine, input);
    defer engine.gpa.free(units);
    const args = try sdk.array(engine);
    errdefer engine.freeValue(args);
    var current: std.ArrayList(u16) = .empty;
    defer current.deinit(engine.gpa);
    var quote: ?u16 = null;
    for (units) |unit| {
        if (quote) |active| {
            if (unit == active) quote = null else try current.append(engine.gpa, unit);
        } else if (unit == '\'' or unit == '"') {
            quote = unit;
        } else if (whitespace(unit)) {
            if (current.items.len > 0) {
                try appendArgument(engine, args, current.items);
                current.clearRetainingCapacity();
            }
        } else try current.append(engine.gpa, unit);
    }
    if (current.items.len > 0) try appendArgument(engine, args, current.items);
    return args;
}
fn appendArgument(engine: *em.Engine, args: c.JSValue, units: []const u16) !void {
    const push = try sdk.get(engine, args, "push");
    defer engine.freeValue(push);
    var parameters = [_]c.JSValue{try utf16.string(engine, units)};
    defer engine.freeValue(parameters[0]);
    const ignored = try engine.checked(c.JS_Call(engine.context, push, args, 1, &parameters));
    engine.freeValue(ignored);
}
pub fn substitute(engine: *em.Engine, content: c.JSValue, args: c.JSValue) !c.JSValue {
    const separator = try sdk.text(engine, " ");
    defer engine.freeValue(separator);
    const all = try sdk.invoke(engine, args, "join", &.{separator});
    defer engine.freeValue(all);
    const pattern = try regexp(engine, "\\$\\{(\\d+|ARGUMENTS|@):-([^}]*)\\}|\\$\\{@:(\\d+)(?::(\\d+))?\\}|\\$(ARGUMENTS|@|\\d+)", "g");
    defer engine.freeValue(pattern);
    var roots = [_]c.JSValue{ args, all };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, replaceArgs, "sdkPromptSubstitute", 6, 0, roots.len, &roots));
    defer engine.freeValue(callback);
    return sdk.invoke(engine, content, "replace", &.{ pattern, callback });
}
fn literal(engine: *em.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try sdk.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn parsedNumber(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function = try sdk.get(engine, global, "parseInt");
    defer engine.freeValue(function);
    var parameters = [_]c.JSValue{ value, c.JS_NewInt32(engine.context, 10) };
    // Source invokes the identifier parseInt(...), with undefined receiver.
    // A user replacement must not receive the global object as its `this`.
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), parameters.len, &parameters));
}
fn number(engine: *em.Engine, value: c.JSValue) !f64 {
    const parsed = try parsedNumber(engine, value);
    defer engine.freeValue(parsed);
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, parsed) < 0) return @import("native_js_values.zig").capture(engine);
    return result;
}
fn positional(engine: *em.Engine, args: c.JSValue, index: f64) !c.JSValue {
    const atom = c.JS_ValueToAtom(engine.context, c.JS_NewFloat64(engine.context, index));
    defer c.JS_FreeAtom(engine.context, atom);
    return engine.checked(c.JS_GetProperty(engine.context, args, atom));
}
fn replaceArgs(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return replacement(engine, roots[0], roots[1], args[0..@intCast(argc)]) catch |err| sdk.fail(engine, err);
}
fn replacement(engine: *em.Engine, args: c.JSValue, all: c.JSValue, captures: []const c.JSValue) !c.JSValue {
    if (captures.len < 6) return error.InvalidSDKPromptMatch;
    if (c.JS_ToBool(engine.context, captures[1]) == 1) {
        const value = if (try literal(engine, captures[1], "@") or try literal(engine, captures[1], "ARGUMENTS")) c.JS_DupValue(engine.context, all) else try positional(engine, args, try number(engine, captures[1]) - 1);
        defer engine.freeValue(value);
        return c.JS_DupValue(engine.context, if (c.JS_ToBool(engine.context, value) == 1) value else captures[2]);
    }
    if (c.JS_ToBool(engine.context, captures[3]) == 1) {
        var start = try number(engine, captures[3]) - 1;
        if (start < 0) start = 0;
        const length = if (c.JS_ToBool(engine.context, captures[4]) == 1) try parsedNumber(engine, captures[4]) else c.pi_js_undefined();
        defer engine.freeValue(length);
        const slice = try sdk.get(engine, args, "slice");
        defer engine.freeValue(slice);
        const selected = if (c.JS_ToBool(engine.context, captures[4]) == 1) sliced: {
            const symbol = try engine.checked(c.JS_GetToPrimitiveSymbol(engine.context));
            defer engine.freeValue(symbol);
            const end = try @import("native_tui_value_arithmetic.zig").add(engine, c.JS_NewFloat64(engine.context, start), length, symbol);
            defer engine.freeValue(end);
            var parameters = [_]c.JSValue{ c.JS_NewFloat64(engine.context, start), end };
            break :sliced try engine.checked(c.JS_Call(engine.context, slice, args, parameters.len, &parameters));
        } else sliced: {
            var parameters = [_]c.JSValue{c.JS_NewFloat64(engine.context, start)};
            break :sliced try engine.checked(c.JS_Call(engine.context, slice, args, parameters.len, &parameters));
        };
        defer engine.freeValue(selected);
        const separator = try sdk.text(engine, " ");
        defer engine.freeValue(separator);
        return sdk.invoke(engine, selected, "join", &.{separator});
    }
    if (try literal(engine, captures[5], "ARGUMENTS") or try literal(engine, captures[5], "@")) return c.JS_DupValue(engine.context, all);
    const value = try positional(engine, args, try number(engine, captures[5]) - 1);
    if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) return value;
    engine.freeValue(value);
    return sdk.text(engine, "");
}
pub fn expandTemplate(owner: *sdk.State, input: c.JSValue, snapshot: c.JSValue) !c.JSValue {
    const engine = owner.engine;
    const slash = try sdk.text(engine, "/");
    defer engine.freeValue(slash);
    const begins = try sdk.invoke(engine, input, "startsWith", &.{slash});
    defer engine.freeValue(begins);
    if (c.JS_ToBool(engine.context, begins) != 1) return c.JS_DupValue(engine.context, input);
    const pattern = try regexp(engine, "^/([^\\s]+)(?:\\s+([\\s\\S]*))?$", "");
    defer engine.freeValue(pattern);
    const matched = try sdk.invoke(engine, input, "match", &.{pattern});
    defer engine.freeValue(matched);
    if (c.JS_IsNull(matched)) return c.JS_DupValue(engine.context, input);
    const name = try engine.checked(c.JS_GetPropertyUint32(engine.context, matched, 1));
    defer engine.freeValue(name);
    const tail = try engine.checked(c.JS_GetPropertyUint32(engine.context, matched, 2));
    defer engine.freeValue(tail);
    var roots = [_]c.JSValue{name};
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, templateMatches, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(predicate);
    // Resolve the actual mutable find property once, then call it with the
    // snapshot receiver. User replacements observe exactly this call.
    const find = try sdk.get(engine, snapshot, "find");
    defer engine.freeValue(find);
    var parameters = [_]c.JSValue{predicate};
    const row = try engine.checked(c.JS_Call(engine.context, find, snapshot, 1, &parameters));
    defer engine.freeValue(row);
    if (c.JS_ToBool(engine.context, row) == 1) {
        const empty = try sdk.text(engine, "");
        defer engine.freeValue(empty);
        const args = try parseArgs(engine, if (c.JS_IsUndefined(tail) or c.JS_IsNull(tail)) empty else tail);
        defer engine.freeValue(args);
        const content = try sdk.get(engine, row, "content");
        defer engine.freeValue(content);
        return substitute(engine, content, args);
    }
    return c.JS_DupValue(engine.context, input);
}
fn templateMatches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const row_name = sdk.get(engine, if (argc > 0) args[0] else c.pi_js_undefined(), "name") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(row_name);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, row_name, roots[0])));
}
