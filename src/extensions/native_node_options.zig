// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original selected internal/options.js lazy declarations. The complete CLI
//! metadata/schema namespace remains separate; this completed private record
//! supplies only its real retained callable imports to the actual Module graph.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const sync = @import("native_sync_arguments.zig");
const functions = @import("native_node_module_callable.zig");
const binding = @import("native_node_options_binding.zig");
const publication = @import("native_node_fs_private_publication.zig");
const cache_key = "pi-native:private/node-options-values";
const State = struct {
    engine: *a.v.em.Engine,
    process: c.JSValue,
    values_binding: c.JSValue,
    embedder_binding: c.JSValue,
    options_dict: c.JSValue,
    embedder_options: c.JSValue,
    warn_on_allow_unauthorized: bool = true,
};
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    c.JS_FreeValueRT(runtime, state.process);
    c.JS_FreeValueRT(runtime, state.values_binding);
    c.JS_FreeValueRT(runtime, state.embedder_binding);
    c.JS_FreeValueRT(runtime, state.options_dict);
    c.JS_FreeValueRT(runtime, state.embedder_options);
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.process, marker);
    c.JS_MarkValue(runtime, state.values_binding, marker);
    c.JS_MarkValue(runtime, state.embedder_binding, marker);
    c.JS_MarkValue(runtime, state.options_dict, marker);
    c.JS_MarkValue(runtime, state.embedder_options, marker);
}
fn known(engine: *a.v.em.Engine, owner: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return error.ActualNodeOptionsOwnerRequired));
    if (state.engine != engine) return error.ActualNodeOptionsOwnerRequired;
    return state;
}
fn stateBody(s: *Scope, inputs: binding.Exports, process: c.JSValue) !c.JSValue {
    const registration = try s.beforeAllocation();
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual Node options lexical owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    _ = try s.checkedAllocation(c.pi_js_undefined(), registration);
    const allocation = try s.beforeAllocation();
    const owner = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context, c.pi_js_null(), id), allocation);
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    errdefer c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
    const state = try s.engine.gpa.create(State);
    state.* = .{ .engine = s.engine, .process = a.duplicate(s.engine, process),
        .values_binding = a.duplicate(s.engine, inputs.values),
        .embedder_binding = a.duplicate(s.engine, inputs.embedder),
        .options_dict = c.pi_js_undefined(), .embedder_options = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(owner, state);
    return a.duplicate(s.engine, owner);
}
const Cell = enum { options_dict, embedder_options };
fn lazyBody(s: *Scope, state: *State, comptime cell: Cell) !c.JSValue {
    const old = @field(state, @tagName(cell));
    if (!c.JS_IsNull(old) and !c.JS_IsUndefined(old)) return a.duplicate(s.engine, old);
    const function = if (cell == .options_dict) state.values_binding else state.embedder_binding;
    const result = try s.own(try a.call(s.engine, function, c.pi_js_undefined(), &.{}));
    // Nullish assignment selects its RHS even if the call reentered and wrote
    // this cell. Store before retiring that now-current previous value.
    const previous = @field(state, @tagName(cell));
    @field(state, @tagName(cell)) = a.duplicate(s.engine, result);
    var completion = a.owned.Completion.initVoid(s.engine, {});
    completion.release(previous);
    try completion.finishVoid();
    return a.duplicate(s.engine, result);
}
fn lazyCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, lazyBody, .{ try known(engine, roots[0]), Cell.options_dict });
}
fn optionBody(s: *Scope, get_values: c.JSValue, name: c.JSValue) !c.JSValue {
    // The receiver is selected and retained before computed-key conversion.
    // A key callback may refresh the shared cache without retiring this value.
    const dictionary = try s.own(try a.call(s.engine, get_values, c.pi_js_undefined(), &.{}));
    return a.duplicate(s.engine, try s.getKey(dictionary, name));
}
fn optionCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, optionBody, .{ roots[0], args.get(0) });
}
fn refreshBody(s: *Scope, state: *State) !c.JSValue {
    const previous = state.options_dict;
    state.options_dict = c.pi_js_undefined();
    var completion = a.owned.Completion.initVoid(s.engine, {});
    completion.release(previous);
    try completion.finishVoid();
    return c.pi_js_undefined();
}
fn refreshCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, refreshBody, .{try known(engine, roots[0])});
}
fn embedderCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, lazyBody, .{ try known(engine, roots[0]), Cell.embedder_options });
}
fn environment(s: *Scope, process: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.get(process, "env"));
}
fn unauthorizedValue(s: *Scope, process: c.JSValue) !c.JSValue {
    const env = try s.own(try a.expression(s.engine, environment, .{process}));
    return a.duplicate(s.engine, try s.get(env, "NODE_TLS_REJECT_UNAUTHORIZED"));
}
fn unauthorizedPredicate(s: *Scope, process: c.JSValue) !c.JSValue {
    const value = try s.own(try a.expression(s.engine, unauthorizedValue, .{process}));
    return a.boolean(s, s.equal(value, try s.text("0")));
}
fn warnUnauthorized(s: *Scope, process: c.JSValue) !c.JSValue {
    const emit = try s.get(process, "emitWarning");
    const text = try s.text("Setting the NODE_TLS_REJECT_UNAUTHORIZED " ++
        "environment variable to '0' makes TLS connections " ++
        "and HTTPS requests insecure by disabling " ++
        "certificate verification.");
    _ = try s.call(emit, process, &.{text});
    return c.pi_js_undefined();
}
fn unauthorizedBody(s: *Scope, state: *State) !c.JSValue {
    const allowed = try a.condition(s.engine, unauthorizedPredicate, .{state.process});
    if (allowed and state.warn_on_allow_unauthorized) {
        state.warn_on_allow_unauthorized = false;
        _ = try a.expression(s.engine, warnUnauthorized, .{state.process});
    }
    return a.boolean(s, allowed);
}
fn unauthorizedCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, unauthorizedBody, .{try known(engine, roots[0])});
}
fn createBody(s: *Scope) !c.JSValue {
    // BuiltinLoader supplies process as the real wrapper parameter. The
    // registered default is retained before evaluating this module body.
    const process = try s.own((try s.engine.requireBuiltin("node:process")) orelse return error.ActualNodeOptionsProcessRequired);
    const inputs = try binding.create(s.engine);
    var incoming = [_]c.JSValue{ inputs.values, inputs.embedder };
    for (&incoming, 0..) |*slot, position| {
        const value = slot.*; slot.* = c.pi_js_undefined();
        _ = s.own(value) catch |err| {
            for (incoming[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
    const owner = try s.own(try a.expression(s.engine, stateBody, .{ inputs, process }));
    const get_values = try s.own(try functions.createWithArguments(s.engine, "getCLIOptionsFromBinding", 0, true,
        .{ .formal_count = 0, .callback = lazyCallback }, &.{owner}));
    const get_option = try s.own(try functions.createWithArguments(s.engine, "getOptionValue", 1, true,
        .{ .formal_count = 1, .callback = optionCallback }, &.{get_values}));
    const refresh = try s.own(try functions.createWithArguments(s.engine, "refreshOptions", 0, true,
        .{ .formal_count = 0, .callback = refreshCallback }, &.{owner}));
    const embedder = try s.own(try functions.createWithArguments(s.engine, "getEmbedderOptions", 0, true,
        .{ .formal_count = 0, .callback = embedderCallback }, &.{owner}));
    const allow_unauthorized = try s.own(try functions.createWithArguments(s.engine, "getAllowUnauthorized", 0, true,
        .{ .formal_count = 0, .callback = unauthorizedCallback }, &.{owner}));
    const record = try s.objectProto(c.pi_js_null());
    try s.define(record, "getOptionValue", get_option, c.JS_PROP_C_W_E);
    try s.define(record, "getEmbedderOptions", embedder, c.JS_PROP_C_W_E);
    try s.define(record, "refreshOptions", refresh, c.JS_PROP_C_W_E);
    try s.define(record, "getAllowUnauthorized", allow_unauthorized, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, record);
}
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return a.duplicate(engine, cached);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, cached));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, cache_key, candidate);
}
