//! Durable usage ledgers retain JavaScript numeric and own-property semantics.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn add(engine: *Engine, total: c.JSValue, usage: c.JSValue, key: [:0]const u8, optional: bool) !void {
    const supplied = try vm.get(engine, usage, key);
    defer engine.freeValue(supplied);
    if (optional and c.JS_IsUndefined(supplied)) return;
    const previous = try vm.get(engine, total, key);
    defer engine.freeValue(previous);
    var left: f64 = 0;
    var right: f64 = 0;
    if (!(optional and (c.JS_IsUndefined(previous) or c.JS_IsNull(previous))) and c.JS_ToFloat64(engine.context, &left, previous) < 0) return js.capture(engine);
    if (c.JS_ToFloat64(engine.context, &right, supplied) < 0) return js.capture(engine);
    try @import("native_tool_info.zig").putData(engine, total, key, c.JS_NewFloat64(engine.context, left + right));
}
pub fn addUsage(engine: *Engine, total: c.JSValue, usage: c.JSValue) !void {
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try add(engine, total, usage, key, false);
    inline for (.{ "cacheWrite1h", "reasoning" }) |key| try add(engine, total, usage, key, true);
    const total_cost = try vm.get(engine, total, "cost");
    defer engine.freeValue(total_cost);
    const usage_cost = try vm.get(engine, usage, "cost");
    defer engine.freeValue(usage_cost);
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try add(engine, total_cost, usage_cost, key, false);
}
pub fn recordInDocument(engine: *Engine, document: c.JSValue, bucket: [:0]const u8, key: c.JSValue, usage: c.JSValue) !void {
    const totals = try vm.get(engine, document, bucket);
    defer engine.freeValue(totals);
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const has = try vm.invoke(engine, object, "hasOwn", &.{ totals, key });
    defer engine.freeValue(has);
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const total = if (c.JS_ToBool(engine.context, has) != 0) try engine.checked(c.JS_GetProperty(engine.context, totals, atom)) else c.pi_js_undefined();
    defer engine.freeValue(total);
    if (!c.JS_IsUndefined(total)) return addUsage(engine, total, usage);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try @import("native_tool_info.zig").putData(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    const copied = try @import("native_chord_json.zig").copyJson(engine, usage, options);
    if (c.JS_SetProperty(engine.context, totals, atom, copied) < 0) return js.capture(engine);
}
const awaiting = @import("native_durable_await.zig");
pub fn record(engine: *Engine, captured: *awaiting.Intrinsics, tx: c.JSValue, conversation: c.JSValue, bucket: [:0]const u8, key: c.JSValue, usage: c.JSValue, usage_token: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    const bucket_value = try engine.checked(c.JS_NewString(engine.context, bucket));
    defer engine.freeValue(bucket_value);
    inline for (.{ .{ "bucket", bucket_value }, .{ "key", key }, .{ "usage", usage } }) |field| try @import("native_tool_info.zig").putData(engine, state, field[0], c.JS_DupValue(engine.context, field[1]));
    const pending = try vm.invoke(engine, tx, "doc", &.{ usage_token, conversation });
    defer engine.freeValue(pending);
    return awaiting.continueWith(recordReady, engine, captured, state, pending, 0);
}
fn recordReady(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    const bucket = try vm.get(engine, state, "bucket");
    defer engine.freeValue(bucket);
    const key = try vm.get(engine, state, "key");
    defer engine.freeValue(key);
    const usage = try vm.get(engine, state, "usage");
    defer engine.freeValue(usage);
    const bucket_text = try engine.toString(bucket);
    defer engine.gpa.free(bucket_text);
    const terminated = try engine.gpa.dupeZ(u8, bucket_text);
    defer engine.gpa.free(terminated);
    try recordInDocument(engine, value, terminated, key, usage);
    return c.pi_js_undefined();
}
