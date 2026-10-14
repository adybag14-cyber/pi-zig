//! Source settings-manager applyToolModifiers over live owner-local JS values.
//! Shared by latest transcript restore and future factory composition.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

pub fn apply(engine: *em.Engine, base: c.JSValue, entries: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, base, null));
    if (c.JS_IsNull(entries) or c.JS_IsUndefined(entries)) return js.typeError(engine, "entries is not iterable");
    const iterator_symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, entries, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        if (!c.JS_IsString(entry)) continue;
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        const plus = try frame.text("+");
        const minus = try frame.text("-");
        if (!frame.truthy(try frame.invoke(entry, "startsWith", &.{plus})) and !frame.truthy(try frame.invoke(entry, "startsWith", &.{minus}))) continue;
        const name = try frame.invoke(entry, "slice", &.{c.JS_NewInt32(engine.context, 1)});
        const index = try frame.invoke(tools, "indexOf", &.{name});
        const missing = frame.equal(index, c.JS_NewInt32(engine.context, -1));
        if (frame.truthy(try frame.invoke(entry, "startsWith", &.{plus})) and missing and frame.truthy(name)) {
            _ = try frame.invoke(tools, "push", &.{name});
        } else if (frame.truthy(try frame.invoke(entry, "startsWith", &.{minus})) and !missing) {
            _ = try frame.invoke(tools, "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
        }
    }
    return c.JS_DupValue(engine.context, tools);
}

pub fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return apply(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
