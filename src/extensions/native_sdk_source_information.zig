//! Actual core/source-info.ts exports, shared by the extension initializer
//! and the public SDK. Each predicate and member expression owns its result.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const cache_key = "\x00sdk-source-information-c268";
const Method = enum { getSyntheticPathSource, isSyntheticPath, createSourceInfo, createSyntheticSourceInfo };

pub fn create(engine: *h.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *h.Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "BUILTIN_PATH_PREFIX", try v.text(s, "builtin:"));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const operation: Method = @enumFromInt(field.value);
        const length: c_int = if (operation == .getSyntheticPathSource or operation == .isSyntheticPath) 1 else 2;
        try v.put(s, result, field.name, try v.ordinary(s, field.name, length, Dispatch(operation).call, &.{}));
    }
    return v.duplicate(s, result);
}
fn Dispatch(comptime operation: Method) type {
    return struct {
        fn call(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            try engine.checkNativeEntry();
            return switch (operation) {
                .getSyntheticPathSource => h.expression(engine, getPathSourceBody, .{v.arg(args, 0)}),
                .isSyntheticPath => h.expression(engine, isSyntheticBody, .{v.arg(args, 0)}),
                .createSourceInfo, .createSyntheticSourceInfo => h.expression(engine, informationBody, .{
                    v.arg(args, 0), v.arg(args, 1), operation == .createSyntheticSourceInfo,
                }),
            };
        }
    };
}
fn getPathSourceBody(s: *h.Scope, path: c.JSValue) !c.JSValue {
    if (try v.testText(s, path, "startsWith", "builtin:"))
        return v.duplicate(s, try v.text(s, "builtin"));
    if (try v.testText(s, path, "startsWith", "<") and try v.testText(s, path, "endsWith", ">")) {
        const source = try v.own(s, try h.expression(s.engine, firstSourceBody, .{path}));
        return v.duplicate(s, if (v.truthy(s, source)) source else try v.text(s, "temporary"));
    }
    return c.pi_js_undefined();
}
fn sliceBody(s: *h.Scope, path: c.JSValue) !c.JSValue {
    const method = try v.get(s, path, "slice");
    return v.duplicate(s, try v.call(s, method, path, &.{
        c.JS_NewInt32(s.engine.context, 1), c.JS_NewInt32(s.engine.context, -1),
    }));
}
fn splitBody(s: *h.Scope, path: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, sliceBody, .{path}));
    const method = try v.get(s, receiver, "split");
    const separator = try v.text(s, ":");
    return v.duplicate(s, try v.call(s, method, receiver, &.{separator}));
}
fn firstSourceBody(s: *h.Scope, path: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, splitBody, .{path}));
    return v.duplicate(s, try v.at(s, receiver, 0));
}
fn isSyntheticBody(s: *h.Scope, path: c.JSValue) !c.JSValue {
    // The Source || expression returns the selected value, including an
    // arbitrary object returned by a replaced startsWith method.
    const first = try v.own(s, try v.invokeTextOwned(s.engine, path, "startsWith", "builtin:"));
    if (v.truthy(s, first)) return v.duplicate(s, first);
    return v.invokeTextOwned(s.engine, path, "startsWith", "<");
}
fn informationBody(s: *h.Scope, path: c.JSValue, options: c.JSValue, comptime synthetic: bool) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "path", path);
    try h.statement(s.engine, fieldBody, .{ result, options, "source", @as(?[]const u8, null) });
    try h.statement(s.engine, fieldBody, .{ result, options, "scope", if (synthetic) @as(?[]const u8, "temporary") else null });
    try h.statement(s.engine, fieldBody, .{ result, options, "origin", if (synthetic) @as(?[]const u8, "top-level") else null });
    try h.statement(s.engine, fieldBody, .{ result, options, "baseDir", @as(?[]const u8, null) });
    return v.duplicate(s, result);
}
fn fieldBody(s: *h.Scope, result: c.JSValue, options: c.JSValue, comptime name: [*:0]const u8, fallback: ?[]const u8) !void {
    const input = try v.get(s, options, name);
    const value = if (fallback != null and v.nullish(input)) try v.text(s, fallback.?) else input;
    return v.put(s, result, name, value);
}
