// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual helpers.js toRealPath and CommonJS condition declarations. These
//! private functions share their real lexical values across every Module call.
//! The complete graph supplies the actual options/FS/primordial owners.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const sync = @import("native_sync_arguments.zig");
const functions = @import("native_node_module_callable.zig");
const InitFrame = a.frames.Frame(enum { user_conditions, no_addons, addon_conditions });
pub const Inputs = struct {
    filesystem: c.JSValue,
    internal_fs: c.JSValue,
    safe_map: c.JSValue,
    safe_set: c.JSValue,
    get_option_value: c.JSValue,
    object_freeze: c.JSValue,
};
const State = struct {
    engine: *v.em.Engine,
    inputs: Inputs,
    realpath_cache: c.JSValue,
    conditions: c.JSValue,
    conditions_array: c.JSValue,
};
/// Each output is owned. The enclosing genuine Module assembler retains this
/// component and publishes its full namespace only after all dependencies bind.
pub const Exports = struct {
    to_real_path: c.JSValue,
    initialize_conditions: c.JSValue,
    get_conditions: c.JSValue,
    get_conditions_array: c.JSValue,
};
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (std.meta.fields(Inputs)) |field| c.JS_MarkValue(runtime, @field(state.inputs, field.name), marker);
    c.JS_MarkValue(runtime, state.realpath_cache, marker);
    c.JS_MarkValue(runtime, state.conditions, marker);
    c.JS_MarkValue(runtime, state.conditions_array, marker);
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    inline for (std.meta.fields(Inputs)) |field| c.JS_FreeValueRT(runtime, @field(state.inputs, field.name));
    c.JS_FreeValueRT(runtime, state.realpath_cache);
    c.JS_FreeValueRT(runtime, state.conditions);
    c.JS_FreeValueRT(runtime, state.conditions_array);
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn known(engine: *v.em.Engine, owner: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return error.RequiredActualCommonJSHelperOwner));
    if (state.engine != engine) return error.RequiredActualCommonJSHelperOwner;
    return state;
}
fn stateOwner(s: *Scope, inputs: Inputs) !c.JSValue {
    const registration = try s.beforeAllocation();
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual CommonJS helper bindings", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    _ = try s.checkedAllocation(c.pi_js_undefined(), registration);
    const generation = try s.beforeAllocation();
    const owner = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context, c.pi_js_null(), id), generation);
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    errdefer c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
    const state = try s.engine.gpa.create(State);
    state.* = .{ .engine = s.engine, .inputs = undefined,
        .realpath_cache = c.pi_js_undefined(), .conditions = c.pi_js_undefined(), .conditions_array = c.pi_js_undefined() };
    inline for (std.meta.fields(Inputs)) |field| @field(state.inputs, field.name) = a.duplicate(s.engine, @field(inputs, field.name));
    _ = c.JS_SetOpaque(owner, state);
    return a.duplicate(s.engine, owner);
}
fn createMap(s: *Scope, constructor: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.construct(constructor, &.{}));
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    var s = Scope.init(engine);
    var outputs: [4]c.JSValue = @splat(c.pi_js_undefined());
    var failure: ?anyerror = null;
    createBody(&s, inputs, &outputs) catch |err| { failure = err; };
    try s.boundary.finishMany(failure, &s.values, &outputs);
    return .{ .to_real_path = outputs[0], .initialize_conditions = outputs[1],
        .get_conditions = outputs[2], .get_conditions_array = outputs[3] };
}
fn createBody(s: *Scope, inputs: Inputs, outputs: *[4]c.JSValue) !void {
    const owner = try s.own(try a.expression(s.engine, stateOwner, .{inputs}));
    const state = try known(s.engine, owner);
    state.realpath_cache = try a.expression(s.engine, createMap, .{inputs.safe_map});
    const realpath = try s.own(try functions.createWithArguments(s.engine, "toRealPath", 1, true,
        .{ .formal_count = 1, .callback = realpathCallback }, &.{owner}));
    const initialize = try s.own(try functions.createWithArguments(s.engine, "initializeCjsConditions", 0, true,
        .{ .formal_count = 0, .callback = initializeCallback, .hooks = sync.frameHooks(InitFrame) }, &.{owner}));
    const conditions = try s.own(try functions.createWithArguments(s.engine, "getCjsConditions", 0, true,
        .{ .formal_count = 0, .callback = conditionsCallback }, &.{owner, initialize}));
    const conditions_array = try s.own(try functions.createWithArguments(s.engine, "getCjsConditionsArray", 0, true,
        .{ .formal_count = 0, .callback = arrayCallback }, &.{owner, initialize}));
    outputs.* = .{ a.duplicate(s.engine, realpath), a.duplicate(s.engine, initialize),
        a.duplicate(s.engine, conditions), a.duplicate(s.engine, conditions_array) };
}
fn propertyKey(s: *Scope, internal_fs: c.JSValue) !c.JSValue {
    const raw = try s.get(internal_fs, "realpathCacheKey");
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, raw);
    s.pending() catch |err| {
        if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
        return err;
    };
    if (atom == c.JS_ATOM_NULL) return error.MissingActualRealpathCacheKeyReason;
    defer c.JS_FreeAtom(s.engine.context, atom);
    const generation = try s.beforeAllocation();
    return a.duplicate(s.engine, try s.checkedAllocation(c.JS_AtomToValue(s.engine.context, atom), generation));
}
fn realpathOptions(s: *Scope, state: *State) !c.JSValue {
    const result = try s.object();
    const key = try s.own(try a.expression(s.engine, propertyKey, .{state.inputs.internal_fs}));
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    s.pending() catch |err| {
        if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
        return err;
    };
    if (atom == c.JS_ATOM_NULL) return error.MissingActualRealpathCacheKeyReason;
    defer c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    const status = c.JS_DefinePropertyValue(s.engine.context, result, atom,
        a.duplicate(s.engine, state.realpath_cache), c.JS_PROP_C_W_E | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualRealpathOptionsReason;
    return a.duplicate(s.engine, result);
}
fn realpathBody(s: *Scope, state: *State, request: c.JSValue) !c.JSValue {
    const filesystem = state.inputs.filesystem;
    const method = try s.get(filesystem, "realpathSync");
    const options = try s.own(try a.expression(s.engine, realpathOptions, .{state}));
    return a.duplicate(s.engine, try s.call(method, filesystem, &.{request, options}));
}
fn realpathCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, realpathBody, .{try known(engine, roots[0]), args.get(0)});
}
const Cell = enum { conditions, conditions_array };
fn assign(state: *State, comptime cell: Cell, incoming: anyerror!c.JSValue) !void {
    const value = try incoming;
    const previous = @field(state, @tagName(cell));
    @field(state, @tagName(cell)) = value;
    var completion = a.owned.Completion.initVoid(state.engine, {});
    completion.release(previous);
    return completion.finishVoid();
}
fn option(s: *Scope, function: c.JSValue, name: []const u8) !c.JSValue {
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{try s.text(name)}));
}
fn optionTruthy(s: *Scope, function: c.JSValue, name: []const u8) !c.JSValue {
    const value = try s.own(try a.expression(s.engine, option, .{function, name}));
    return a.boolean(s, s.truthy(value));
}
fn addons(s: *Scope, none: bool) !c.JSValue {
    const result = try a.array(s);
    if (!none) try a.index(s, result, 0, try s.text("node-addons"));
    return a.duplicate(s.engine, result);
}
fn conditionArray(s: *Scope, addon: c.JSValue, user: c.JSValue) !c.JSValue {
    const result = try a.array(s);
    try a.index(s, result, 0, try s.text("require"));
    try a.index(s, result, 1, try s.text("node"));
    var position: u32 = 2;
    try s.pending();
    const first = c.JS_PiArrayAppend(s.engine.context, result, &position, addon);
    try s.pending();
    if (first < 0) return error.MissingActualCommonJSConditionSpreadReason;
    try s.pending();
    const second = c.JS_PiArrayAppend(s.engine.context, result, &position, user);
    try s.pending();
    if (second < 0) return error.MissingActualCommonJSConditionSpreadReason;
    return a.duplicate(s.engine, result);
}
fn appendModuleSync(s: *Scope, state: *State) !c.JSValue {
    const receiver = try s.own(a.duplicate(s.engine, state.conditions_array));
    const method = try s.get(receiver, "push");
    _ = try s.call(method, receiver, &.{try s.text("module-sync")});
    return c.pi_js_undefined();
}
fn freeze(s: *Scope, state: *State) !c.JSValue {
    const function = state.inputs.object_freeze;
    const array = try s.own(a.duplicate(s.engine, state.conditions_array));
    _ = try s.call(function, c.pi_js_undefined(), &.{array});
    return c.pi_js_undefined();
}
fn conditionSet(s: *Scope, state: *State) !c.JSValue {
    const constructor = state.inputs.safe_set;
    const array = try s.own(a.duplicate(s.engine, state.conditions_array));
    return a.duplicate(s.engine, try s.construct(constructor, &.{array}));
}
fn initializeBody(s: *Scope, state: *State, frame: *InitFrame) !c.JSValue {
    try frame.take(.user_conditions, a.expression(s.engine, option, .{state.inputs.get_option_value, @as([]const u8, "--conditions")}));
    try frame.take(.no_addons, a.expression(s.engine, option, .{state.inputs.get_option_value, @as([]const u8, "--no-addons")}));
    try frame.take(.addon_conditions, a.expression(s.engine, addons, .{s.truthy(frame.get(.no_addons))}));
    try assign(state, .conditions_array, a.expression(s.engine, conditionArray, .{frame.get(.addon_conditions), frame.get(.user_conditions)}));
    if (try a.condition(s.engine, optionTruthy, .{state.inputs.get_option_value, @as([]const u8, "--experimental-require-module")}))
        _ = try a.expression(s.engine, appendModuleSync, .{state});
    _ = try a.expression(s.engine, freeze, .{state});
    try assign(state, .conditions, a.expression(s.engine, conditionSet, .{state}));
    return c.pi_js_undefined();
}
fn initializeCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, InitFrame) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    const state = known(engine, roots[0]) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return s.finish(initializeBody(&s, state, frame));
}
fn initializeStatement(s: *Scope, initialize: c.JSValue) !c.JSValue {
    _ = try s.call(initialize, c.pi_js_undefined(), &.{});
    return c.pi_js_undefined();
}
fn getBody(s: *Scope, state: *State, initialize: c.JSValue, comptime cell: Cell) !c.JSValue {
    if (c.JS_IsUndefined(@field(state, @tagName(cell))))
        _ = try a.expression(s.engine, initializeStatement, .{initialize});
    return a.duplicate(s.engine, @field(state, @tagName(cell)));
}
fn conditionsCallback(engine: *v.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, getBody, .{try known(engine, roots[0]), roots[1], Cell.conditions});
}
fn arrayCallback(engine: *v.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, getBody, .{try known(engine, roots[0]), roots[1], Cell.conditions_array});
}
