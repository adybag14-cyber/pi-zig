//! Public typed durable entry tokens and their exact discriminator guards.
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    try sdk.put(engine, exports, "defineEntry", try engine.checked(c.JS_NewCFunction(engine.context, define, "defineEntry", 1)));
    inline for (.{ "UserEntry", "AssistantEntry", "SystemEntry", "ToolResultEntry", "ResetEntry", "CompactionEntry" }, .{ "pi.user", "pi.assistant", "pi.system", "pi.tool-result", "pi.reset", "pi.compaction" }) |name, kind| {
        const label = try sdk.text(engine, kind);
        defer engine.freeValue(label);
        try sdk.put(engine, exports, name, try token(engine, label));
    }
}
fn token(engine: *Engine, kind: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "kind", c.JS_DupValue(engine.context, kind));
    var data = [_]c.JSValue{kind};
    try sdk.put(engine, result, "is", try engine.checked(c.JS_NewCFunctionData(engine.context, guard, 1, 0, 1, &data)));
    return result;
}
fn define(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const kind = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (!c.JS_IsString(kind)) return c.JS_ThrowTypeError(context, "Entry kind must be a non-empty string");
    const name = engine.toString(kind) catch |err| return durable.reject(engine, err);
    defer engine.gpa.free(name);
    if (name.len == 0) return c.JS_ThrowTypeError(context, "Entry kind must be a non-empty string");
    return token(engine, kind) catch |err| durable.reject(engine, err);
}
fn guard(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc == 0 or c.JS_IsUndefined(argv[0])) return c.pi_js_bool(context, 0);
    const engine = Engine.fromContext(context.?);
    const kind = sdk.get(engine, argv[0], "kind") catch |err| return durable.reject(engine, err);
    defer engine.freeValue(kind);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, kind, data[0])));
}
