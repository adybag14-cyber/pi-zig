// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual internal/modules/helpers execution-start lexical cells and four
//! ordinary method bodies. One private helper owner is shared per Engine.
//! This records actual execution; it supplies no loader/permission/ESM policy.
//! The carrier is not the complete helpers module and is never published as one.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const c = a.c;
const Scope = a.Scope;
const key = "pi-native:private/module-execution-state";
const State = struct {
    engine: *a.v.em.Engine,
    cjs_started: bool = false,
    esm_started: bool = false,
};
const Operation = enum(c_int) { has_cjs, set_cjs, has_esm, set_esm };

fn finalize(_: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    const engine = state.engine;
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn stateOwner(s: *Scope) !c.JSValue {
    const engine = s.engine;
    try s.pending();
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State);
    errdefer if (!attached) engine.gpa.destroy(state);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Module Execution State", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const generation = try s.beforeAllocation();
    const holder = try s.checkedAllocation(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), id), generation);
    state.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(holder, state);
    attached = true;
    return holder; // Borrowed from this expression's Scope.
}
fn callback(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    // Only these four known method captures can reach the private native cell.
    // Receiver and arguments are deliberately unused, as in the original bodies.
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])) orelse return error.ActualModuleExecutionStateRequired));
    if (state.engine != engine) return error.ActualModuleExecutionStateEngineMismatch;
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[1]) != 0) return error.ActualModuleExecutionOperationRequired;
    return switch (@as(Operation, @enumFromInt(raw))) {
        .has_cjs => c.JS_NewBool(engine.context, state.cjs_started),
        .has_esm => c.JS_NewBool(engine.context, state.esm_started),
        .set_cjs => blk: { state.cjs_started = true; break :blk c.pi_js_undefined(); },
        .set_esm => blk: { state.esm_started = true; break :blk c.pi_js_undefined(); },
    };
}
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const owner = try stateOwner(s);
    const exports = try s.object();
    inline for (.{
        .{ "hasStartedUserCJSExecution", Operation.has_cjs },
        .{ "setHasStartedUserCJSExecution", Operation.set_cjs },
        .{ "hasStartedUserESMExecution", Operation.has_esm },
        .{ "setHasStartedUserESMExecution", Operation.set_esm },
    }) |entry| {
        const function = try s.own(try functions.create(s.engine, entry[0], 0, false, callback,
            &.{ owner, c.JS_NewInt32(s.engine.context, @intFromEnum(entry[1])) }));
        try s.put(exports, entry[0], function);
    }
    return a.duplicate(s.engine, exports);
}
