//! Original pi-ai text/content/system-section presentation helpers.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum { contentText, getSystemMessageText, renderSystemMessageUpdate };
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return switch (method) {
                    .contentText => content(host, arg(args, 0), arg(args, 1)),
                    .getSystemMessageText => system(host, arg(args, 0), false),
                    .renderSystemMessageUpdate => system(host, arg(args, 0), true),
                };
            }
        };
        try scope.put(result, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, 1, Adapter.call, &.{})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (args.len > i) args[i] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const host = em.Engine.fromContext(context.?);
    return predicate(host, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| @import("native_sdk.zig").fail(host, err);
}
fn predicate(engine: *em.Engine, value: c.JSValue, kind: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return switch (kind) {
        0 => c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "type"), try scope.text("text")))),
        1 => js.get(engine, value, "text"),
        2 => c.pi_js_bool(engine.context, @intFromBool(try arithmetic.compare(engine, .greater, try scope.get(value, "length"), c.JS_NewInt32(engine.context, 0)))),
        else => unreachable,
    };
}
fn function(scope: *Scope, kind: c_int) !c.JSValue {
    return scope.own(try scope.engine.checked(c.pi_js_function_magic(scope.engine.context, callback, "", 1, kind)));
}
pub fn content(engine: *em.Engine, value: c.JSValue, supplied_separator: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const separator = if (c.JS_IsUndefined(supplied_separator)) try scope.text("\n") else supplied_separator;
    if (c.JS_IsString(value)) return c.JS_DupValue(engine.context, value);
    const filter = try scope.get(value, "filter");
    const filtered = try scope.call(filter, value, &.{try function(&scope, 0)});
    const map = try scope.get(filtered, "map");
    const mapped = try scope.call(map, filtered, &.{try function(&scope, 1)});
    return js.invoke(engine, mapped, "join", &.{separator});
}
pub fn system(engine: *em.Engine, message: c.JSValue, update: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const parts = try scope.array();
    const text = try scope.own(try content(engine, try scope.get(message, "content"), c.pi_js_undefined()));
    if (!update or try arithmetic.compare(engine, .greater, try scope.get(text, "length"), c.JS_NewInt32(engine.context, 0))) _ = try scope.invoke(parts, "push", &.{text});
    const object = try scope.global("Object");
    const enumerate = try scope.get(object, if (update) "entries" else "values");
    const sections = try scope.get(message, "sections");
    const entries = try scope.call(enumerate, object, &.{if (temp.nullish(sections)) try scope.object() else sections});
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, entries, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        _ = try step.own(entry);
        if (!update) {
            if (!c.JS_IsNull(entry)) _ = try step.invoke(parts, "push", &.{entry});
        } else {
            const pair = try js.pair(engine, entry, symbol);
            for (pair) |value| _ = try step.own(value);
            const removed = c.JS_IsNull(pair[1]);
            var sentence = try step.concat(try step.text(if (removed) "Removed system prompt section \"" else "Updated system prompt section \""), try step.stringify(pair[0]));
            sentence = try step.concat(sentence, try step.text(if (removed) "\"." else "\":\n\n"));
            if (!removed) sentence = try step.concat(sentence, try step.stringify(pair[1]));
            _ = try step.invoke(parts, "push", &.{sentence});
        }
    }
    const output = if (update) parts else filter: {
        const callee = try scope.get(parts, "filter");
        break :filter try scope.call(callee, parts, &.{try function(&scope, 2)});
    };
    return js.invoke(engine, output, "join", &.{try scope.text("\n\n")});
}
