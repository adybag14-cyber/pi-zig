//! Actual Source private exchange/parser projection and matching native bodies.
//! Public login/callback/HTTP acceptance is a separate actual composition group.
const std = @import("std");
pub const x = @import("extensions/native_ai_auth_helper_values.zig");
pub const c = x.c;
pub const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
pub fn publish(engine: *x.em.Engine, name: [*:0]const u8, input: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, input));
}
pub fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
pub fn run(engine: *x.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-openrouter-private-caller.mjs");
    engine.freeValue(namespace);
}
pub fn prepare(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "oauthHooks", hooks);
    const source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-openrouter-private-c268-source.mjs"), "actual-openrouter-private-c268.mjs");
    defer engine.freeValue(source);
    try publish(engine, "openRouterSource", source);
    const native = try @import("extensions/native_ai_oauth_openrouter.zig").createTestInternals(engine);
    defer engine.freeValue(native);
    try publish(engine, "openRouterNative", native);
    try run(engine,
        \\globalThis.openRouterSourceMethods=openRouterSource.openRouterOAuth;
    );
}
pub fn select(engine: *x.em.Engine, native: bool) !void {
    try run(engine, if (native)
        "globalThis.selectedOpenRouter=openRouterNative;globalThis.selectedOpenRouterMethods=openRouterNative;"
    else
        "globalThis.selectedOpenRouter=openRouterSource;globalThis.selectedOpenRouterMethods=openRouterSourceMethods;");
}
pub const exchangeAmbient =
    \\globalThis.controlledSignal={aborted:false,addEventListener(){},removeEventListener(){}};
    \\globalThis.AbortController=function(){return {signal:{aborted:false},abort(){}}};
    \\globalThis.setTimeout=()=>1;globalThis.clearTimeout=()=>{};
;

/// A stack-owned control record remains live through the Engine's deinit.
/// Only real C object finalizers write this sequence; guest code cannot do so.
pub const OrderProbe = struct {
    engine: *x.em.Engine,
    holder_class: c.JSClassID = 0,
    order: [8]u8 = @splat(0),
    length: usize = 0,
    overflow: bool = false,
};
const OrderHolder = struct { probe: *OrderProbe, slot: u8 };
fn orderHolderFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const holder: *OrderHolder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const probe = holder.probe;
    if (probe.length < probe.order.len) {
        probe.order[probe.length] = holder.slot;
        probe.length += 1;
    } else probe.overflow = true;
    probe.engine.gpa.destroy(holder);
}
pub fn installOrderProbe(engine: *x.em.Engine, probe: *OrderProbe) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, installOrderProbeBody(&o, probe));
}
fn installOrderProbeBody(o: *x.Ops, probe: *OrderProbe) !void {
    const engine = o.s.engine;
    var record_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &record_class);
    const record_definition: c.JSClassDef = .{ .class_name = "Actual OpenRouter order probe" };
    if (c.JS_NewClass(engine.runtime, record_class, &record_definition) < 0) return error.OutOfMemory;
    _ = c.JS_NewClassID(engine.runtime, &probe.holder_class);
    const holder_definition: c.JSClassDef = .{ .class_name = "Actual OpenRouter order holder", .finalizer = orderHolderFinalizer };
    if (c.JS_NewClass(engine.runtime, probe.holder_class, &holder_definition) < 0) return error.OutOfMemory;
    const generation = try o.beforeAllocation();
    const record = try o.allocation(c.JS_NewObjectClass(engine.context, record_class), generation);
    _ = c.JS_SetOpaque(record, probe);
    const make = try o.own(try @import("extensions/native_node_function.zig").create(engine, "makeOrderHolder", 1, makeOrderHolder, &.{record}));
    try publish(engine, "makeOpenRouterOrderHolder", make);
}
fn makeOrderHolder(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, makeOrderHolderBody(&o, x.arg(args, 0), roots[0]));
}
fn makeOrderHolderBody(o: *x.Ops, slot_value: c.JSValue, record: c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    const probe: *OrderProbe = @ptrCast(@alignCast(c.JS_GetOpaque(record, c.JS_GetClassID(record)).?));
    var slot: u32 = 0;
    var boundary: x.guest.Boundary = .{ .engine = engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToUint32(engine.context, &slot, slot_value));
    if (slot > 1) return error.OpenRouterOrderHolderSlotOutOfRange;
    const generation = try o.beforeAllocation();
    const value = try o.allocation(c.JS_NewObjectClass(engine.context, probe.holder_class), generation);
    const holder = try engine.gpa.create(OrderHolder);
    holder.* = .{ .probe = probe, .slot = @intCast(slot) };
    _ = c.JS_SetOpaque(value, holder);
    return c.JS_DupValue(engine.context, value);
}
