//! Actual b45 computeEditsDiff asynchronous file/read/normalization/apply/diff path.
//! Requires real native fs access/readFile/constants, native text edits and jsdiff.
//! No callback-success or empty-preview substitutes; private unqualified draft.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const async_api = @import("native_agent_async.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Stage = enum(c_int) { access, read };
fn getArg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn isError(s: *Scope, value: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(s.engine.context, value, try s.global("Error"));
    if (result < 0) return js.capture(s.engine);
    return result != 0;
}
fn string(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.call(try s.global("String"), c.pi_js_undefined(), &.{value});
}
fn outputError(s: *Scope, message: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.put(result, "error", message);
    return result;
}
fn outerFailure(engine: *em.Engine, state: c.JSValue, reason: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const message = if (try isError(&s, reason)) try s.get(reason, "message") else try string(&s, reason);
    try async_api.settle(engine, state, false, try outputError(&s, message));
}
fn accessFailure(engine: *em.Engine, state: c.JSValue, reason: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const code = if (try isError(&s, reason) and try js.hasKey(engine, reason, try s.text("code"))) try s.concat(try s.text("Error code: "), try s.stringify(try s.get(reason, "code"))) else try string(&s, reason);
    const prefix = try s.concat(try s.concat(try s.text("Could not edit file: "), try s.stringify(try s.get(state, "path"))), try s.text(". "));
    try async_api.settle(engine, state, false, try outputError(&s, try s.concat(try s.concat(prefix, code), try s.text("."))));
}
fn handleError(engine: *em.Engine, state: c.JSValue, err: anyerror, access_error: bool) !void {
    const reason = async_api.reason(engine, err);
    defer engine.freeValue(reason);
    if (access_error) accessFailure(engine, state, reason) catch |failure| {
        const outer = async_api.reason(engine, failure);
        defer engine.freeValue(outer);
        try outerFailure(engine, state, outer);
    } else try outerFailure(engine, state, reason);
}
fn step(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage_value: c_int) anyerror!void {
    const stage: Stage = @enumFromInt(stage_value);
    if (rejected) {
        if (stage == .access) accessFailure(engine, state, value) catch |err| try handleError(engine, state, err, false) else try outerFailure(engine, state, value);
        return;
    }
    continueSuccess(engine, state, value, stage) catch |err| try handleError(engine, state, err, false);
}
fn continueSuccess(engine: *em.Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    switch (stage) {
        .access => {
            const pending = try s.call(try s.get(state, "readFile"), c.pi_js_undefined(), &.{ try s.get(state, "absolutePath"), try s.text("utf-8") });
            try async_api.wait(step, engine, state, pending, @intFromEnum(Stage.read));
        },
        .read => {
            const content = if (s.truthy(try s.invoke(value, "startsWith", &.{try s.text("\u{feff}")}))) try s.invoke(value, "slice", &.{c.JS_NewInt32(engine.context, 1)}) else value;
            const normalized = try s.own(try @import("native_sdk_edit_apply.zig").normalizeLF(engine, content));
            const applied = try s.own(try @import("native_sdk_edit_apply.zig").applyNormalized(engine, normalized, try s.get(state, "edits"), try s.get(state, "path")));
            const rendered = try s.own(try @import("native_sdk_edit_diff_display.zig").generateDefault(engine, try s.get(applied, "baseContent"), try s.get(applied, "newContent")));
            try async_api.settle(engine, state, false, rendered);
        },
    }
}
fn begin(engine: *em.Engine, state: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try s.put(state, "path", getArg(args, 0));
    try s.put(state, "edits", getArg(args, 1));
    try s.put(state, "readFile", roots[1]);
    const options = try s.object();
    try s.put(options, "normalizeUnicodeSpaces", c.pi_js_bool(engine.context, 1));
    try s.put(options, "stripAtPrefix", c.pi_js_bool(engine.context, 1));
    // Resolution is deliberately before the outer Source try: its failures
    // reject the async function rather than producing an {error} preview.
    const absolute = try s.own(try @import("native_sdk_source_paths.zig").resolve(engine, getArg(args, 0), getArg(args, 2), options));
    try s.put(state, "absolutePath", absolute);
    accessStart(engine, state, roots[0], roots[2]) catch |err| try handleError(engine, state, err, true);
}
fn accessStart(engine: *em.Engine, state: c.JSValue, access: c.JSValue, constants: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try s.call(access, c.pi_js_undefined(), &.{ try s.get(state, "absolutePath"), try s.get(constants, "R_OK") });
    try async_api.wait(step, engine, state, pending, @intFromEnum(Stage.access));
}
fn call(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    const pending = try async_api.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, args, roots) catch |err| try async_api.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return call(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..3]) catch |err| sdk.fail(engine, err);
}
pub fn create(engine: *em.Engine, access: c.JSValue, read_file: c.JSValue, constants: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, access) or !c.JS_IsFunction(engine.context, read_file)) return error.NativeActualFsPromisesRequired;
    var roots = [_]c.JSValue{ access, read_file, constants };
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "computeEditsDiff", 3, 0, roots.len, &roots));
    errdefer engine.freeValue(function);
    const async_prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(async_prototype);
    if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
    return function;
}
/// Keep the actual async filesystem functions and platform read-access constant
/// rooted by the asynchronous preview function.
pub fn createNative(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!engine.native_module_values.contains("node:fs/promises")) try @import("node_fs.zig").install(engine, engine.native_io orelse return error.NativeEditPreviewRequiresIo);
    const fs = engine.native_module_values.get("node:fs/promises").?;
    const constants = try scope.get(engine.native_module_values.get("node:fs").?, "constants");
    return create(engine, try scope.get(fs, "access"), try scope.get(fs, "readFile"), constants);
}
