//! Guest custom find operations remain on the VM owner and use continuations.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const vm = @import("native_values.zig");
const durable = @import("native_durable.zig");
const truncation = @import("native_sdk_search_truncation.zig");
const c = em.c;
const Engine = em.Engine;
fn field(engine: *Engine, state: c.JSValue, name: [:0]const u8) !c.JSValue {
    return vm.get(engine, state, name);
}
fn stopped(engine: *Engine, state: c.JSValue) !bool {
    const value = try field(engine, state, "done");
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}
fn finish(engine: *Engine, state: c.JSValue, value: c.JSValue, failure: bool) !void {
    if (try stopped(engine, state)) return;
    try vm.put(engine, state, "done", c.pi_js_bool(engine.context, 1));
    const signal = try field(engine, state, "signal");
    defer engine.freeValue(signal);
    const abort = try field(engine, state, "abort");
    defer engine.freeValue(abort);
    if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and !c.JS_IsUndefined(abort)) {
        const name = try sdk.text(engine, "abort");
        defer engine.freeValue(name);
        const removed = try vm.invoke(engine, signal, "removeEventListener", &.{ name, abort });
        engine.freeValue(removed);
    }
    const resolve = try field(engine, state, if (failure) "reject" else "resolve");
    defer engine.freeValue(resolve);
    var args = [_]c.JSValue{value};
    const returned = try engine.checked(c.JS_Call(engine.context, resolve, c.pi_js_undefined(), 1, &args));
    engine.freeValue(returned);
}
fn exception(engine: *Engine, message: []const u8) !c.JSValue {
    const error_value = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(error_value);
    try vm.put(engine, error_value, "message", try sdk.text(engine, message));
    return error_value;
}
fn fail(engine: *Engine, state: c.JSValue, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const is_error = c.JS_IsInstanceOf(engine.context, value, constructor);
    if (is_error < 0) return error.JavaScriptException;
    if (is_error == 1) return finish(engine, state, value, true);
    const message = try engine.toString(value);
    defer engine.gpa.free(message);
    const normalized = try exception(engine, message);
    defer engine.freeValue(normalized);
    try finish(engine, state, normalized, true);
}
fn observe(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: c_int) !void {
    const pending = try sdk.promise(engine, value);
    defer engine.freeValue(pending);
    var data = [_]c.JSValue{state};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, continuation, 1, stage, 1, &data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, continuation, 1, 2, 1, &data));
    defer engine.freeValue(rejected);
    const ignored = try vm.invoke(engine, pending, "then", &.{ fulfilled, rejected });
    engine.freeValue(ignored);
}
fn continuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, stage: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    run(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), stage) catch |err| {
        _ = durable.reject(engine, err);
        const reason = c.JS_GetException(context);
        defer engine.freeValue(reason);
        fail(engine, data[0], reason) catch |failure| return durable.reject(engine, failure);
    };
    return c.pi_js_undefined();
}
fn run(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: c_int) !void {
    if (try stopped(engine, state)) return;
    if (stage == 2) return fail(engine, state, value);
    const signal = try field(engine, state, "signal");
    defer engine.freeValue(signal);
    if (stage == 3 or (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and aborted: {
        const aborted = try vm.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        break :aborted c.JS_ToBool(engine.context, aborted) == 1;
    })) {
        const error_value = try exception(engine, "Operation aborted");
        defer engine.freeValue(error_value);
        return finish(engine, state, error_value, true);
    }
    const root = try field(engine, state, "root");
    defer engine.freeValue(root);
    if (stage == 0) {
        if (c.JS_ToBool(engine.context, value) != 1) {
            const path = try engine.toString(root);
            defer engine.gpa.free(path);
            const message = try std.fmt.allocPrint(engine.gpa, "Path not found: {s}", .{path});
            defer engine.gpa.free(message);
            const error_value = try exception(engine, message);
            defer engine.freeValue(error_value);
            return finish(engine, state, error_value, true);
        }
        const operations = try field(engine, state, "operations");
        defer engine.freeValue(operations);
        const pattern = try field(engine, state, "pattern");
        defer engine.freeValue(pattern);
        const options = try field(engine, state, "options");
        defer engine.freeValue(options);
        const result = try vm.invoke(engine, operations, "glob", &.{ pattern, root, options });
        defer engine.freeValue(result);
        return observe(engine, state, result, 1);
    }
    const path = try engine.toString(root);
    defer engine.gpa.free(path);
    const limit_value = try field(engine, state, "limit");
    defer engine.freeValue(limit_value);
    var limit: f64 = 1000;
    if (c.JS_ToFloat64(engine.context, &limit, limit_value) < 0) return error.JavaScriptException;
    var output: std.Io.Writer.Allocating = .init(engine.gpa);
    defer output.deinit();
    const count = try vm.length(engine, value);
    for (0..count) |index| {
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
        defer engine.freeValue(entry);
        const text = try engine.toString(entry);
        defer engine.gpa.free(text);
        const relative = if (std.fs.path.isAbsolute(text)) try std.fs.path.relative(engine.gpa, ".", null, path, text) else try engine.gpa.dupe(u8, text);
        defer engine.gpa.free(relative);
        for (relative) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        if (index != 0) try output.writer.writeByte('\n');
        try output.writer.writeAll(relative);
        if ((std.mem.endsWith(u8, text, "/") or std.mem.endsWith(u8, text, "\\")) and !std.mem.endsWith(u8, relative, "/")) try output.writer.writeByte('/');
    }
    const cut = truncation.head(output.written());
    const limited = @as(f64, @floatFromInt(count)) >= limit;
    var formatted: std.Io.Writer.Allocating = .init(engine.gpa);
    defer formatted.deinit();
    try formatted.writer.writeAll(if (count == 0) "No files found matching pattern" else cut.content);
    if (count != 0 and (limited or cut.truncated)) {
        try formatted.writer.writeAll("\n\n[");
        if (limited) try formatted.writer.print("{d} results limit reached", .{limit});
        if (cut.truncated) {
            if (limited) try formatted.writer.writeAll(". ");
            try formatted.writer.writeAll("50.0KB limit reached");
        }
        try formatted.writer.writeByte(']');
    }
    const result = try vm.object(engine);
    defer engine.freeValue(result);
    const content = try vm.array(engine);
    defer engine.freeValue(content);
    const block = try vm.object(engine);
    defer engine.freeValue(block);
    try vm.put(engine, block, "type", try sdk.text(engine, "text"));
    try vm.put(engine, block, "text", try durable.jsValue(engine, .{ .string = formatted.written() }));
    if (c.JS_SetPropertyUint32(engine.context, content, 0, c.JS_DupValue(engine.context, block)) < 0) return error.JavaScriptException;
    try vm.put(engine, result, "content", c.JS_DupValue(engine.context, content));
    const details = if (count != 0 and (limited or cut.truncated)) details: {
        const encoded = try std.json.Stringify.valueAlloc(engine.gpa, .{ .resultLimitReached = if (limited) @as(?f64, limit) else null, .truncation = if (cut.truncated) @as(?truncation.Result, cut) else null }, .{ .emit_null_optional_fields = false });
        defer engine.gpa.free(encoded);
        break :details try engine.checked(c.JS_ParseJSON(engine.context, encoded.ptr, encoded.len, "custom-find-details"));
    } else c.pi_js_undefined();
    try vm.put(engine, result, "details", details);
    try finish(engine, state, result, false);
}
pub fn start(engine: *Engine, factory: c.JSValue, operations: c.JSValue, cwd: []const u8, arguments: c.JSValue, signal: c.JSValue, context: c.JSValue) !c.JSValue {
    const path = try vm.get(engine, arguments, "path");
    defer engine.freeValue(path);
    const requested = if (c.JS_ToBool(engine.context, path) == 1) try engine.toString(path) else try engine.gpa.dupe(u8, ".");
    defer engine.gpa.free(requested);
    const context_cwd = if (!c.JS_IsUndefined(context) and !c.JS_IsNull(context)) try vm.get(engine, context, "cwd") else c.pi_js_undefined();
    defer engine.freeValue(context_cwd);
    const base = if (c.JS_ToBool(engine.context, context_cwd) == 1) try engine.toString(context_cwd) else try engine.gpa.dupe(u8, cwd);
    defer engine.gpa.free(base);
    const resolved = try std.fs.path.resolve(engine.gpa, &.{ base, requested });
    defer engine.gpa.free(resolved);
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    var callbacks: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &callbacks));
    errdefer engine.freeValue(promise);
    defer for (callbacks) |callback| engine.freeValue(callback);
    try vm.put(engine, state, "resolve", c.JS_DupValue(engine.context, callbacks[0]));
    try vm.put(engine, state, "reject", c.JS_DupValue(engine.context, callbacks[1]));
    try vm.put(engine, state, "factory", c.JS_DupValue(engine.context, factory));
    try vm.put(engine, state, "operations", c.JS_DupValue(engine.context, operations));
    try vm.put(engine, state, "signal", c.JS_DupValue(engine.context, signal));
    try vm.put(engine, state, "done", c.pi_js_bool(engine.context, 0));
    try vm.put(engine, state, "root", try sdk.text(engine, resolved));
    try vm.put(engine, state, "pattern", try vm.get(engine, arguments, "pattern"));
    const supplied_limit = try vm.get(engine, arguments, "limit");
    defer engine.freeValue(supplied_limit);
    const limit = if (c.JS_IsUndefined(supplied_limit) or c.JS_IsNull(supplied_limit)) c.JS_NewInt32(engine.context, 1000) else c.JS_DupValue(engine.context, supplied_limit);
    defer engine.freeValue(limit);
    try vm.put(engine, state, "limit", c.JS_DupValue(engine.context, limit));
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    const ignore_source = "[\"**/node_modules/**\",\"**/.git/**\"]";
    const ignore = try engine.checked(c.JS_ParseJSON(engine.context, ignore_source, ignore_source.len, "custom-find-ignore"));
    try vm.put(engine, options, "ignore", ignore);
    try vm.put(engine, options, "limit", c.JS_DupValue(engine.context, limit));
    try vm.put(engine, state, "options", c.JS_DupValue(engine.context, options));
    var captures = [_]c.JSValue{state};
    const aborted = try engine.checked(c.JS_NewCFunctionData(engine.context, continuation, 0, 3, 1, &captures));
    defer engine.freeValue(aborted);
    // Register before the first delegated await, so the returned promise can
    // settle on abort while the custom operation itself remains pending.
    if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) {
        const active = try vm.get(engine, signal, "aborted");
        defer engine.freeValue(active);
        if (c.JS_ToBool(engine.context, active) == 1) {
            try run(engine, state, c.pi_js_undefined(), 3);
            return promise;
        }
        try vm.put(engine, state, "abort", c.JS_DupValue(engine.context, aborted));
        const name = try sdk.text(engine, "abort");
        defer engine.freeValue(name);
        const once = try vm.object(engine);
        defer engine.freeValue(once);
        try vm.put(engine, once, "once", c.pi_js_bool(engine.context, 1));
        const added = try vm.invoke(engine, signal, "addEventListener", &.{ name, aborted, once });
        engine.freeValue(added);
    }
    const root = try field(engine, state, "root");
    defer engine.freeValue(root);
    const value = vm.invoke(engine, operations, "exists", &.{root}) catch |err| {
        _ = durable.reject(engine, err);
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        try fail(engine, state, reason);
        return promise;
    };
    defer engine.freeValue(value);
    try observe(engine, state, value, 0);
    return promise;
}
