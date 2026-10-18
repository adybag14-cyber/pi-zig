//! Source normalizeSpawnArguments expressed as real VM values. The returned
//! object is the actual object passed to live child.spawn; there is no Config
//! sidecar, argv reconstruction, opaque adapter record or ignored stand-in.
const js = @import("native_js_values.zig");
const c = js.c;
const frontier = @import("native_child_process_scope.zig");
const Scope = frontier.Scope;
const common = @import("native_child_process_options.zig");
const std = @import("std");
const fnc = @import("native_child_process_function.zig");
pub const Primordials = struct {
    array_slice: c.JSValue, array_unshift: c.JSValue, array_join: c.JSValue,
    array_sort: c.JSValue, array_filter: c.JSValue, array_push: c.JSValue,
    string_upper: c.JSValue, has_own: c.JSValue, iterator_symbol: c.JSValue,
    regexp_constructor: c.JSValue, regexp_exec: c.JSValue,
};
pub const Permission = union(enum) {
    // Explicit actual bootstrap fact, not an inference from absent guest state.
    disabled,
    enabled: *const fn (*js.Engine, c.JSValue, c.JSValue) anyerror!void,
};
pub const Inputs = struct { process: c.JSValue, primordials: Primordials, permission: Permission };
pub const State = struct { emitted_shell_warning: bool = false };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return common.arg(args, index); }
fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn invalid(engine: *js.Engine, code: []const u8, message: []const u8) anyerror { return @import("node_events.zig").codedError(engine, "TypeError", code, message); }
fn requireObject(engine: *js.Engine, value: c.JSValue) !void {
    if (!c.JS_IsObject(value) or c.JS_IsNull(value) or c.JS_IsArray(value) or c.JS_IsFunction(engine.context, value)) return invalid(engine, "ERR_INVALID_ARG_TYPE", "The options argument must be an object");
}
fn requireString(engine: *js.Engine, value: c.JSValue, message: []const u8) !void { if (!c.JS_IsString(value)) return invalid(engine, "ERR_INVALID_ARG_TYPE", message); }
fn requireBoolean(engine: *js.Engine, value: c.JSValue, message: []const u8) !void { if (!nullish(value) and !c.JS_IsBool(value)) return invalid(engine, "ERR_INVALID_ARG_TYPE", message); }
fn nullCheck(scope: *Scope, value: c.JSValue, label: []const u8) !void {
    // Preserve the original error construction with a temporary original scope;
    // its input is already a primitive string, not a coercion/getter boundary.
    try frontier.pending(scope.engine);
    var original: @import("native_sdk_prompt_scope.zig").Scope = .{ .engine = scope.engine };
    defer original.deinit();
    @import("native_child_process_options.zig").nullCheck(&original, value, label) catch |err| return frontier.failure(scope.engine, err);
    try frontier.pending(scope.engine);
}
fn requireInt32(engine: *js.Engine, value: c.JSValue, message: []const u8) !void {
    if (nullish(value)) return;
    if (!c.JS_IsNumber(value)) return invalid(engine, "ERR_INVALID_ARG_TYPE", message);
    var number: f64 = 0; if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
    if (@trunc(number) != number or number < -2147483648 or number > 2147483647) return invalid(engine, "ERR_INVALID_ARG_TYPE", message);
}
fn snapshot(scope: *Scope, value: c.JSValue) !c.JSValue {
    const copy = try scope.objectProto(c.pi_js_null());
    if (!c.JS_IsUndefined(value)) try frontier.spreadInto(scope, copy, value);
    return copy;
}
fn element(scope: *Scope, array: c.JSValue, index: u32) !c.JSValue { return scope.getIndex(array, index); }
fn length(scope: *Scope, value: c.JSValue) !u32 {
    var result: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &result, try scope.get(value, "length")) < 0) return js.capture(scope.engine); try frontier.pending(scope.engine); return result;
}
fn append(scope: *Scope, array: c.JSValue, value: c.JSValue, push: c.JSValue) !void { _ = try scope.call(push, array, &.{value}); }
fn ownKeys(scope: *Scope, environment: c.JSValue, push: c.JSValue) !c.JSValue {
    const keys = try scope.array();
    var seen: std.StringHashMap(void) = .init(scope.engine.gpa);
    defer { var iterator = seen.keyIterator(); while (iterator.next()) |key| scope.engine.gpa.free(key.*); seen.deinit(); }
    var object = environment;
    while (!c.JS_IsNull(object)) {
        var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, object, c.JS_GPN_STRING_MASK) < 0) return js.capture(scope.engine);
        defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
        try frontier.pending(scope.engine);
        for (0..count) |index| {
            var row: Scope = .{ .engine = scope.engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
            const key = try row.own(try row.engine.checked(c.JS_AtomToValue(row.engine.context, names[index].atom)));
            const text = try row.engine.toString(key);
            if (seen.contains(text)) { row.engine.gpa.free(text); continue; }
            var descriptor: c.JSPropertyDescriptor = undefined;
            const exists = c.JS_GetOwnProperty(row.engine.context, &descriptor, object, names[index].atom);
            if (exists < 0) { row.engine.gpa.free(text); return js.capture(row.engine); }
            if (exists == 0) { row.engine.gpa.free(text); try frontier.pending(row.engine); continue; }
            // key is the first root. Adopt all descriptor owners atomically
            // before any pending check can unwind/retire one of the others.
            row.inline_values[1] = descriptor.value; row.inline_values[2] = descriptor.getter; row.inline_values[3] = descriptor.setter; row.inline_count = 4;
            frontier.pending(row.engine) catch |err| { row.engine.gpa.free(text); return err; };
            seen.put(text, {}) catch |failure| { row.engine.gpa.free(text); return failure; };
            if (descriptor.flags & c.JS_PROP_ENUMERABLE != 0) try append(&row, keys, key, push);
        }
        object = try frontier.prototype(scope, object);
    }
    return keys;
}
fn loopBudget(engine: *js.Engine) !void {
    engine.interrupts +|= 1;
    if (!engine.cancelled.load(.acquire) and engine.interrupts <= engine.options.interrupt_budget) return;
    _ = c.JS_ThrowInternalError(engine.context, "interrupted"); const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason); _ = try engine.checked(c.JS_Throw(engine.context, reason));
}
fn copyCoverage(scope: *Scope, process: c.JSValue, environment: c.JSValue, option_env: c.JSValue, has_own: c.JSValue) !void {
    const name = try scope.text("NODE_V8_COVERAGE");
    const first = try scope.get(try scope.get(process, "env"), "NODE_V8_COVERAGE");
    if (scope.truthy(first) and (!scope.truthy(option_env) or !scope.truthy(try scope.call(has_own, option_env, &.{name})))) {
        const current = try scope.get(try scope.get(process, "env"), "NODE_V8_COVERAGE");
        try js.setKey(scope.engine, environment, name, current);
        try frontier.pending(scope.engine);
    }
}
fn uniqueEnvKey(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const uppercase = try scope.call(roots[0], arg(args, 0), &.{});
    const seen = roots[1];
    for (0..try length(&scope, seen)) |index| if (scope.equal(uppercase, try element(&scope, seen, @intCast(index)))) return c.pi_js_bool(engine.context, 0);
    // Private safe-set storage is never exposed, and intentionally cannot invoke
    // a later Array.prototype indexed setter on behalf of SafeSet.add.
    try scope.index(seen, try length(&scope, seen), uppercase);
    return c.pi_js_bool(engine.context, 1);
}
fn envPairs(scope: *Scope, inputs: Inputs, environment: c.JSValue, windows: bool) !c.JSValue {
    const boxed = try frontier.toObject(scope, environment);
    var keys = try ownKeys(scope, boxed, inputs.primordials.array_push);
    if (windows) {
        _ = try scope.call(inputs.primordials.array_sort, keys, &.{});
        const seen = try scope.array();
        const predicate = try scope.own(try fnc.createArrow(scope.engine, "", 1, uniqueEnvKey, &.{ inputs.primordials.string_upper, seen }));
        keys = try scope.call(inputs.primordials.array_filter, keys, &.{predicate});
    }
    const result = try scope.array();
    var iterator = try js.Iterator.init(scope.engine, keys, inputs.primordials.iterator_symbol); defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |owned_key| {
        var row: Scope = .{ .engine = scope.engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        const key = try row.own(owned_key);
        const value = try frontier.getKey(&row, environment, key);
        if (c.JS_IsUndefined(value)) continue;
        const key_text = try row.engine.toString(key); defer row.engine.gpa.free(key_text);
        const label = try @import("std").fmt.allocPrint(row.engine.gpa, "options.env['{s}']", .{key_text}); defer row.engine.gpa.free(label);
        try nullCheck(&row, key, label); try nullCheck(&row, value, label);
        // Template ToString is a genuine VM conversion and preserves ordinary
        // object/symbol failures. Native env serialization happens only later.
        const serialized = try row.concat(try row.concat(key, try row.text("=")), try row.stringify(value));
        try append(&row, result, serialized, inputs.primordials.array_push);
    }
    return result;
}
pub fn normalize(engine: *js.Engine, args: []const c.JSValue, inputs: Inputs, state: *State) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try frontier.pending(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    var file = arg(args, 0);
    try requireString(engine, file, "The file argument must be a string"); try nullCheck(&scope, file, "file");
    const file_text = try engine.toString(file); defer engine.gpa.free(file_text);
    if (file_text.len == 0) return invalid(engine, "ERR_INVALID_ARG_VALUE", "The file argument cannot be empty");
    var arguments = arg(args, 1); var options = arg(args, 2);
    if (c.JS_IsArray(arguments)) arguments = try scope.call(inputs.primordials.array_slice, arguments, &.{})
    else if (nullish(arguments)) arguments = try scope.array()
    else if (!c.JS_IsObject(arguments) or c.JS_IsFunction(engine.context, arguments)) return invalid(engine, "ERR_INVALID_ARG_TYPE", "The args argument must be an object")
    else { options = arguments; arguments = try scope.array(); }
    var index: f64 = 0;
    while (true) : (index += 1) {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        const more = try frontier.binary(&row, 4, c.JS_NewFloat64(engine.context, index), try row.get(arguments, "length"));
        if (!row.truthy(more)) break;
        try loopBudget(engine);
        const index_text = try engine.toString(c.JS_NewFloat64(engine.context, index)); defer engine.gpa.free(index_text);
        const label = try std.fmt.allocPrint(engine.gpa, "args[{s}]", .{index_text}); defer engine.gpa.free(label);
        try nullCheck(&row, try frontier.getKey(&row, arguments, c.JS_NewFloat64(engine.context, index)), label);
    }
    if (!c.JS_IsUndefined(options)) try requireObject(engine, options);
    options = try snapshot(&scope, options);
    var cwd = try scope.get(options, "cwd");
    if (!nullish(cwd)) {
        // Genuine validated Node path value; no mutable process.cwd call or
        // native executable/PATH lookup occurs in Source normalization.
        const path = try @import("node_fs_metadata.zig").pathTextNamed(engine, cwd, false, "options.cwd"); defer engine.gpa.free(path);
        if (!c.JS_IsString(cwd) and c.JS_GetTypedArrayType(cwd) != c.JS_TYPED_ARRAY_UINT8) cwd = try scope.text(path);
    }
    try requireBoolean(engine, try scope.get(options, "detached"), "The options.detached property must be a boolean");
    try requireInt32(engine, try scope.get(options, "uid"), "The options.uid property must be int32");
    try requireInt32(engine, try scope.get(options, "gid"), "The options.gid property must be int32");
    const shell = try scope.get(options, "shell");
    if (!nullish(shell) and !c.JS_IsBool(shell) and !c.JS_IsString(shell)) return invalid(engine, "ERR_INVALID_ARG_TYPE", "The options.shell property must be a boolean or string");
    const argv0 = try scope.get(options, "argv0");
    if (!nullish(argv0)) { try requireString(engine, argv0, "The options.argv0 property must be a string"); try nullCheck(&scope, argv0, "options.argv0"); }
    try requireBoolean(engine, try scope.get(options, "windowsHide"), "The options.windowsHide property must be a boolean");
    var verbatim = try scope.get(options, "windowsVerbatimArguments");
    try requireBoolean(engine, verbatim, "The options.windowsVerbatimArguments property must be a boolean");
    const platform = try scope.get(inputs.process, "platform"); const windows = scope.equal(platform, try scope.text("win32"));
    if (scope.truthy(shell)) {
        try nullCheck(&scope, shell, "options.shell");
        const has_args = try scope.positive(try scope.get(arguments, "length"));
        if (has_args and !state.emitted_shell_warning) {
            _ = try scope.invoke(inputs.process, "emitWarning", &.{ try scope.text("Passing args to a child process with shell option true can lead to security vulnerabilities, as the arguments are not escaped, only concatenated."), try scope.text("DeprecationWarning"), try scope.text("DEP0190") });
            state.emitted_shell_warning = true;
        }
        const command_has_args = try scope.positive(try scope.get(arguments, "length"));
        const command = if (command_has_args) try scope.concat(try scope.concat(file, try scope.text(" ")), try scope.call(inputs.primordials.array_join, arguments, &.{try scope.text(" ")})) else file;
        arguments = try scope.array();
        if (windows) {
            const comspec = if (c.JS_IsString(shell)) shell else try scope.get(try scope.get(inputs.process, "env"), "comspec");
            file = if (c.JS_IsString(shell) or scope.truthy(comspec)) comspec else try scope.text("cmd.exe");
            const pattern = try scope.call(inputs.primordials.regexp_constructor, c.pi_js_undefined(), &.{try scope.text("^(?:.*\\\\)?cmd(?:\\.exe)?$"), try scope.text("i")});
            const match = try scope.call(inputs.primordials.regexp_exec, pattern, &.{file});
            if (!c.JS_IsNull(match)) {
                try scope.index(arguments, 0, try scope.text("/d")); try scope.index(arguments, 1, try scope.text("/s")); try scope.index(arguments, 2, try scope.text("/c"));
                try scope.index(arguments, 3, try scope.concat(try scope.concat(try scope.text("\""), command), try scope.text("\"")));
                verbatim = c.pi_js_bool(engine.context, 1);
            } else { try scope.index(arguments, 0, try scope.text("-c")); try scope.index(arguments, 1, command); }
        } else {
            file = if (c.JS_IsString(shell)) shell else try scope.text(if (scope.equal(platform, try scope.text("android"))) "/system/bin/sh" else "/bin/sh");
            try scope.index(arguments, 0, try scope.text("-c")); try scope.index(arguments, 1, command);
        }
    }
    _ = try scope.call(inputs.primordials.array_unshift, arguments, &.{if (c.JS_IsString(argv0)) argv0 else file});
    const option_env = try scope.get(options, "env");
    const environment = if (scope.truthy(option_env)) option_env else try snapshot(&scope, try scope.get(inputs.process, "env"));
    try copyCoverage(&scope, inputs.process, environment, option_env, inputs.primordials.has_own);
    switch (inputs.permission) { .disabled => {}, .enabled => |copy| try copy(engine, environment, arguments) }
    try frontier.pending(engine);
    const pairs = try envPairs(&scope, inputs, environment, windows);
    const result = try snapshot(&scope, options);
    try scope.put(result, "args", arguments); try scope.put(result, "cwd", cwd);
    try scope.put(result, "detached", c.pi_js_bool(engine.context, @intFromBool(scope.truthy(try scope.get(options, "detached")))));
    try scope.put(result, "envPairs", pairs); try scope.put(result, "file", file);
    try scope.put(result, "windowsHide", c.pi_js_bool(engine.context, @intFromBool(scope.truthy(try scope.get(options, "windowsHide")))));
    try scope.put(result, "windowsVerbatimArguments", c.pi_js_bool(engine.context, @intFromBool(scope.truthy(verbatim))));
    return c.JS_DupValue(engine.context, result);
}
