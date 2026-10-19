// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual realm.js normalizeRequirableId over the independently admitted Node
//! v24.14 public policy. This private predicate does not represent installed
//! providers or a completed public BuiltinModule namespace.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const ids = @import("native_node_builtin_node24_data.zig").ids;
pub const Inputs = struct { string_starts_with: c.JSValue, string_slice: c.JSValue };
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn frozen(s: *Scope, value: c.JSValue) !void {
    try s.pending();
    const status = c.JS_FreezeObject(s.engine.context, value);
    try s.pending();
    if (status < 0) return error.MissingActualBuiltinPolicyFreezeReason;
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    if (!c.JS_IsFunction(s.engine.context, inputs.string_starts_with) or
        !c.JS_IsFunction(s.engine.context, inputs.string_slice)) return error.ActualBuiltinPrimordialsRequired;
    const by_users = try a.array(s);
    const without_scheme = try a.array(s);
    var bare_count: u32 = 0;
    for (ids, 0..) |id, index| {
        const scheme_only = std.mem.startsWith(u8, id, "node:");
        try a.index(s, by_users, @intCast(index), try s.text(if (scheme_only) id[5..] else id));
        if (!scheme_only) {
            try a.index(s, without_scheme, bare_count, try s.text(id));
            bare_count += 1;
        }
    }
    try frozen(s, by_users);
    try frozen(s, without_scheme);
    return @import("native_node_module_callable.zig").create(s.engine, "normalizeRequirableId", 1, false,
        invoke, &.{inputs.string_starts_with, inputs.string_slice, by_users, without_scheme,
            c.JS_NewUint32(s.engine.context, bare_count)});
}
fn startsWithNode(s: *Scope, id: c.JSValue, function: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(function, id, &.{try s.text("node:")})));
}
fn sliced(s: *Scope, id: c.JSValue, function: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(function, id, &.{c.JS_NewInt32(s.engine.context, 5)}));
}
fn contains(s: *Scope, list: c.JSValue, count: u32, id: c.JSValue) !bool {
    // The real policy sets contain primitive string keys only. Their SameValueZero
    // membership equals strict string equality and never coerces the candidate.
    // Every array slot here is an immutable own data field, with no holes.
    if (!c.JS_IsString(id)) return false;
    for (0..count) |position| {
        try s.pending();
        const candidate = try s.checked(c.JS_GetPropertyUint32(s.engine.context, list, @intCast(position)));
        if (s.equal(candidate, id)) return true;
    }
    return false;
}
fn invoke(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, body, .{a.arg(args, 0), roots});
}
fn body(s: *Scope, id: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // Unlike public isBuiltin, this actual Source operation always calls the
    // captured StartsWith first, even for a non-string value. The prefixed
    // branch then calls captured Slice on that same original value.
    if (try a.condition(s.engine, startsWithNode, .{id, roots[0]})) {
        const normalized = try s.own(try a.expression(s.engine, sliced, .{id, roots[1]}));
        if (try contains(s, roots[2], ids.len, normalized)) return a.duplicate(s.engine, normalized);
    } else {
        var count: u32 = 0;
        try s.pending();
        const status = c.JS_ToUint32(s.engine.context, &count, roots[4]);
        try s.pending();
        if (status < 0) return error.MissingActualBuiltinPolicyCountReason;
        if (try contains(s, roots[3], count, id)) return a.duplicate(s.engine, id);
    }
    return c.pi_js_undefined();
}
