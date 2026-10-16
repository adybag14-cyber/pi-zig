//! Actual Source omitReplacedExtensions and warning merge over live extension Maps.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Callback = enum(c_int) { nonreplaceable, owner_pairs, pair, name, lookup, present, keep, warning_pair };
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return observed(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn function(scope: *Scope, kind: Callback, roots: []c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), @intCast(roots.len), roots.ptr)));
}
fn names(scope: *Scope, extension: c.JSValue) !c.JSValue {
    const result = try scope.array();
    var count: u32 = 0;
    inline for (.{ .{ "tools", "tool:" }, .{ "commands", "command:" }, .{ "flags", "flag:" } }) |category| {
        const keys = try scope.invoke(try scope.get(extension, category[0]), "keys", &.{});
        const all = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, keys, null));
        const map = try scope.get(all, "map");
        var roots = [_]c.JSValue{try scope.text(category[1])};
        const mapped = try scope.call(map, all, &.{try function(scope, .name, &roots)});
        try @import("native_sdk_resource_spread.zig").literal(scope, result, mapped, &count);
    }
    return result;
}
fn pair(scope: *Scope, input: c.JSValue) ![2]c.JSValue {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var it = try js.Iterator.init(scope.engine, input, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    const first = if (try it.next()) |value| try scope.own(value) else c.pi_js_undefined();
    const second = if (try it.next()) |value| try scope.own(value) else c.pi_js_undefined();
    try it.close();
    return .{ first, second };
}
fn replacementWarning(scope: *Scope, extension: c.JSValue, replacement: c.JSValue, warnings: c.JSValue) !void {
    const builtin = try scope.invoke(try scope.get(extension, "path"), "slice", &.{c.JS_NewInt32(scope.engine.context, 8)});
    const parts = try pair(scope, try scope.invoke(try scope.get(replacement, "name"), "split", &.{ try scope.text(":"), c.JS_NewInt32(scope.engine.context, 2) }));
    const registered = if (scope.equal(parts[0], try scope.text("command"))) try scope.concat(try scope.text("/"), try scope.stringify(parts[1])) else if (scope.equal(parts[0], try scope.text("flag"))) try scope.concat(try scope.text("--"), try scope.stringify(parts[1])) else parts[1];
    if (temp.nullish(warnings)) return;
    const push = try scope.get(warnings, "push");
    const row = try scope.object();
    try scope.put(row, "path", try scope.get(extension, "path"));
    var message = try scope.concat(try scope.text("Extension "), try scope.stringify(try scope.get(try scope.get(replacement, "extension"), "path")));
    message = try scope.concat(try scope.concat(message, try scope.text(" registers ")), try scope.stringify(parts[0]));
    message = try scope.concat(try scope.concat(message, try scope.text(" `")), try scope.stringify(registered));
    message = try scope.concat(try scope.concat(message, try scope.text("`, so built-in extension `")), try scope.stringify(builtin));
    message = try scope.concat(try scope.concat(message, try scope.text("` was not loaded. To use `")), try scope.stringify(builtin));
    message = try scope.concat(message, try scope.text("`, run `pi config` and make sure it is enabled under Built-in extensions, then disable or remove the existing extension. We recommend only having one or the other loaded at a time."));
    try scope.put(row, "warning", message);
    _ = try scope.call(push, warnings, &.{row});
}
fn observed(engine: *em.Engine, kind: Callback, input: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = switch (kind) {
        .nonreplaceable => c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.get(input, "replaceable")))),
        .name => try scope.concat(roots[0], try scope.stringify(input)),
        .pair => made: {
            const result = try scope.array();
            try scope.index(result, 0, input);
            try scope.index(result, 1, roots[0]);
            break :made result;
        },
        .owner_pairs => made: {
            const values = try names(&scope, input);
            const map = try scope.get(values, "map");
            var data = [_]c.JSValue{input};
            break :made try scope.call(map, values, &.{try function(&scope, .pair, &data)});
        },
        .lookup => found: {
            const result = try scope.object();
            try scope.put(result, "name", input);
            try scope.put(result, "extension", try scope.invoke(roots[0], "get", &.{input}));
            break :found result;
        },
        .present => c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(try scope.get(input, "extension")))),
        .keep => kept: {
            if (!scope.truthy(try scope.get(input, "replaceable"))) break :kept c.pi_js_bool(engine.context, 1);
            const values = try names(&scope, input);
            const map = try scope.get(values, "map");
            var lookup_roots = [_]c.JSValue{roots[0]};
            const mapped = try scope.call(map, values, &.{try function(&scope, .lookup, &lookup_roots)});
            const find = try scope.get(mapped, "find");
            const replacement = try scope.call(find, mapped, &.{try function(&scope, .present, &.{})});
            if (!scope.truthy(replacement)) break :kept c.pi_js_bool(engine.context, 1);
            if (scope.truthy(try scope.invoke(try scope.get(input, "path"), "startsWith", &.{try scope.text("builtin:")}))) try replacementWarning(&scope, input, replacement, roots[1]);
            break :kept c.pi_js_bool(engine.context, 0);
        },
        .warning_pair => made: {
            const result = try scope.array();
            try scope.index(result, 0, try scope.get(input, "path"));
            try scope.index(result, 1, input);
            break :made result;
        },
    };
    return c.JS_DupValue(engine.context, value);
}
pub fn omit(scope: *Scope, extensions: c.JSValue, warnings: c.JSValue) !c.JSValue {
    const constructor = try scope.global("Map");
    const filter = try scope.get(extensions, "filter");
    const owners = try scope.call(filter, extensions, &.{try function(scope, .nonreplaceable, &.{})});
    const flat_map = try scope.get(owners, "flatMap");
    var args = [_]c.JSValue{try scope.call(flat_map, owners, &.{try function(scope, .owner_pairs, &.{})})};
    const taken = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
    const keep_filter = try scope.get(extensions, "filter");
    var roots = [_]c.JSValue{ taken, warnings };
    return scope.call(keep_filter, extensions, &.{try function(scope, .keep, &roots)});
}
pub fn mergeWarnings(scope: *Scope, result: c.JSValue, warnings: c.JSValue) !void {
    const constructor = try scope.global("Map");
    const previous = try scope.get(result, "warnings");
    const all = try scope.array();
    var count: u32 = 0;
    try @import("native_sdk_resource_spread.zig").literal(scope, all, if (temp.nullish(previous)) try scope.array() else previous, &count);
    try @import("native_sdk_resource_spread.zig").literal(scope, all, warnings, &count);
    const map = try scope.get(all, "map");
    var args = [_]c.JSValue{try scope.call(map, all, &.{try function(scope, .warning_pair, &.{})})};
    const collected = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
    try scope.set(result, "warnings", try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, try scope.invoke(collected, "values", &.{}), null)));
}
