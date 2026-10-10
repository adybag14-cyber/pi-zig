//! Private startup-owned monotonic performance object for the TUI scheduler.
//! This is not a complete node:perf_hooks module or Performance API claim.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const private_module = "#pi-native-process-clock";
const State = struct { gpa: std.mem.Allocator, io: std.Io, origin_ns: i96 };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.gpa.destroy(state);
}
fn now(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])) orelse return c.JS_ThrowTypeError(context, "Native process clock unavailable")));
    const elapsed = std.Io.Clock.awake.now(state.io).toNanoseconds() - state.origin_ns;
    return c.JS_NewFloat64(context, @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms);
}
pub fn install(engine: *js.Engine, io: std.Io) !void {
    if (engine.native_module_values.contains(private_module)) return;
    const origin = std.Io.Clock.awake.now(io).toNanoseconds();
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Process Clock Owner", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    defer engine.freeValue(holder);
    const state = try engine.gpa.create(State);
    state.* = .{ .gpa = engine.gpa, .io = io, .origin_ns = origin };
    _ = c.JS_SetOpaque(holder, state);
    const object = try js.object(engine);
    defer engine.freeValue(object);
    var data = [_]c.JSValue{holder};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, now, "now", 0, 0, 1, &data));
    try js.define(engine, object, "now", function);
    const record = try js.object(engine);
    defer engine.freeValue(record);
    try js.define(engine, record, "performance", c.JS_DupValue(engine.context, object));
    // JS_NewContext installs QuickJS's bootstrap performance data property.
    // Capture that exact descriptor at native process startup, before factories;
    // a later guest replacement must never be mistaken for this VM default.
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const atom = c.JS_NewAtom(engine.context, "performance");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const present = c.JS_GetOwnProperty(engine.context, &descriptor, root, atom);
    if (present < 0) return js.capture(engine);
    defer if (present != 0) {
        engine.freeValue(descriptor.value);
        engine.freeValue(descriptor.getter);
        engine.freeValue(descriptor.setter);
    };
    try js.define(engine, record, "bootstrapPerformanceFound", c.pi_js_bool(engine.context, @intFromBool(present != 0)));
    if (present != 0) {
        try js.define(engine, record, "bootstrapPerformance", c.JS_DupValue(engine.context, descriptor.value));
        try js.define(engine, record, "bootstrapPerformanceFlags", c.JS_NewInt32(engine.context, descriptor.flags & (c.JS_PROP_C_W_E | c.JS_PROP_GETSET)));
    }
    try engine.registerValueModule(private_module, record);
}
/// Returns the rooted object, so ordinary mutable `.now` lookups and overrides
/// are shared by every class which imports this process clock.
pub fn performance(engine: *js.Engine) !c.JSValue {
    const record = engine.native_module_values.get(private_module) orelse return error.NativeProcessClockUnavailable;
    return js.get(engine, record, "performance");
}
fn globalGet(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return js.get(engine, values[0], "globalPerformanceValue");
}
fn globalSet(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    try js.define(engine, values[0], "globalPerformanceValue", c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined()));
    return c.pi_js_undefined();
}
/// Install the default ambient clock once at process startup. The actual Node
/// Source uses constructible ordinary getter/setter functions, and the setter
/// changes the global value independently of the imported perf_hooks object.
/// The exact VM bootstrap descriptor captured by install is eligible for
/// replacement; intervening guest descriptor/value edits are preserved. This
/// supplies the narrow monotonic `now` body, not a complete Web Performance
/// namespace. Repeat calls preserve guest replacement or deletion.
pub fn installDefaultGlobal(engine: *js.Engine) !void {
    const record = engine.native_module_values.get(private_module) orelse return error.NativeProcessClockUnavailable;
    const installed = try js.get(engine, record, "defaultGlobalInstalled");
    defer engine.freeValue(installed);
    if (c.JS_ToBool(engine.context, installed) != 0) return;
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const atom = c.JS_NewAtom(engine.context, "performance");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    var current: c.JSPropertyDescriptor = undefined;
    const present = c.JS_GetOwnProperty(engine.context, &current, root, atom);
    if (present < 0) return js.capture(engine);
    defer if (present != 0) {
        engine.freeValue(current.value);
        engine.freeValue(current.getter);
        engine.freeValue(current.setter);
    };
    const bootstrap_found = try js.get(engine, record, "bootstrapPerformanceFound");
    defer engine.freeValue(bootstrap_found);
    var preserve_guest = false;
    if (present != 0) {
        const bootstrap = try js.get(engine, record, "bootstrapPerformance");
        defer engine.freeValue(bootstrap);
        const flags = try js.get(engine, record, "bootstrapPerformanceFlags");
        defer engine.freeValue(flags);
        const descriptor_flags = current.flags & (c.JS_PROP_C_W_E | c.JS_PROP_GETSET);
        preserve_guest = c.JS_ToBool(engine.context, bootstrap_found) == 0 or
            descriptor_flags & c.JS_PROP_GETSET != 0 or
            !c.JS_IsStrictEqual(engine.context, flags, c.JS_NewInt32(engine.context, descriptor_flags)) or
            !c.JS_IsStrictEqual(engine.context, bootstrap, current.value);
    } else if (c.JS_ToBool(engine.context, bootstrap_found) != 0) {
        preserve_guest = true;
    } else {
        const inherited = c.JS_HasProperty(engine.context, root, atom);
        if (inherited < 0) return js.capture(engine);
        preserve_guest = inherited != 0;
    }
    if (preserve_guest) {
        try js.define(engine, record, "defaultGlobalInstalled", c.pi_js_bool(engine.context, 1));
        return;
    }
    try js.define(engine, record, "globalPerformanceValue", try performance(engine));
    const getter = try @import("native_node_function.zig").create(engine, "get performance", 0, globalGet, &.{record});
    const setter = @import("native_node_function.zig").create(engine, "set performance", 1, globalSet, &.{record}) catch |err| {
        engine.freeValue(getter);
        return err;
    };
    if (c.JS_DefinePropertyGetSet(engine.context, root, atom, getter, setter, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    try js.define(engine, record, "defaultGlobalInstalled", c.pi_js_bool(engine.context, 1));
}
