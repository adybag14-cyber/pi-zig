//! Narrow native process event/queued warning producer. The host still owns
//! environment, cwd, argv and IO; this does not synthesize a whole Node process.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const events = @import("node_events.zig");
const Method = enum(c_int) { emitWarning, doEmitWarning, throwWarning, onWarning };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native process events: %s", @as([*:0]const u8, @errorName(err)));
}
fn equals(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn truthy(engine: *js.Engine, object: c.JSValue, key: [*:0]const u8) !bool {
    const value = try js.get(engine, object, key);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn invalid(engine: *js.Engine, value: c.JSValue, name: []const u8, expected: []const u8) anyerror {
    const received = try events.description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" argument must be {s}. Received {s}", .{ name, expected, received });
    defer engine.gpa.free(message);
    return events.codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn makeFunction(engine: *js.Engine, state: c.JSValue, method: Method, name: [*:0]const u8, length: c_int) !c.JSValue {
    if (method == .throwWarning) {
        var data = [_]c.JSValue{state};
        return engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(method), 1, &data));
    }
    return @import("native_node_function.zig").create(engine, name, length, ordinaryCall, &.{ state, c.JS_NewInt32(engine.context, @intFromEnum(method)) });
}
fn ordinaryCall(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return operation(engine, values[0], @enumFromInt(@as(c_int, @intFromFloat(try v.number(engine, values[1])))), args);
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn operation(engine: *js.Engine, state: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const process = try js.get(engine, state, "process");
    defer engine.freeValue(process);
    if (method == .throwWarning) {
        _ = try engine.checked(c.JS_Throw(engine.context, try js.get(engine, state, "warning")));
        unreachable;
    }
    if (method == .doEmitWarning) {
        const event = try v.text(engine, "warning");
        defer engine.freeValue(event);
        const result = try js.invoke(engine, process, "emit", &.{ event, v.arg(args, 0) });
        engine.freeValue(result);
        return c.pi_js_undefined();
    }
    if (method == .onWarning) {
        try printWarning(engine, state, process, v.arg(args, 0));
        return c.pi_js_undefined();
    }
    var type_value = c.JS_DupValue(engine.context, v.arg(args, 1));
    defer engine.freeValue(type_value);
    if (try truthy(engine, process, "noDeprecation") and try equals(engine, type_value, "DeprecationWarning")) return c.pi_js_undefined();
    var code = c.JS_DupValue(engine.context, v.arg(args, 2));
    defer engine.freeValue(code);
    var detail = c.pi_js_undefined();
    defer engine.freeValue(detail);
    if (!c.JS_IsNull(type_value) and c.JS_IsObject(type_value) and !c.JS_IsFunction(engine.context, type_value) and !c.JS_IsArray(type_value)) {
        // Getter order is part of Node's options contract, including the
        // deliberately repeated detail read after its string type check.
        const ctor = try js.get(engine, type_value, "ctor");
        engine.freeValue(ctor);
        engine.freeValue(code);
        code = try js.get(engine, type_value, "code");
        const first_detail = try js.get(engine, type_value, "detail");
        defer engine.freeValue(first_detail);
        if (c.JS_IsString(first_detail)) detail = try js.get(engine, type_value, "detail");
        const actual_type = try js.get(engine, type_value, "type");
        engine.freeValue(type_value);
        type_value = if (v.truthy(engine, actual_type)) actual_type else blk: {
            engine.freeValue(actual_type);
            break :blk try v.text(engine, "Warning");
        };
    } else if (c.JS_IsFunction(engine.context, type_value)) {
        engine.freeValue(type_value);
        type_value = try v.text(engine, "Warning");
        engine.freeValue(code);
        code = c.pi_js_undefined();
    }
    if (!c.JS_IsUndefined(type_value) and !c.JS_IsString(type_value)) return invalid(engine, type_value, "type", "of type string");
    if (c.JS_IsFunction(engine.context, code)) {
        engine.freeValue(code);
        code = c.pi_js_undefined();
    } else if (!c.JS_IsUndefined(code) and !c.JS_IsString(code)) return invalid(engine, code, "code", "of type string");
    var warning = c.JS_DupValue(engine.context, v.arg(args, 0));
    defer engine.freeValue(warning);
    if (c.JS_IsString(warning)) {
        const error_constructor = try js.get(engine, state, "Error");
        defer engine.freeValue(error_constructor);
        var values = [_]c.JSValue{warning};
        const created = try engine.checked(c.JS_CallConstructor(engine.context, error_constructor, 1, &values));
        engine.freeValue(warning);
        warning = created;
        try js.define(engine, warning, "name", if (v.truthy(engine, type_value)) c.JS_DupValue(engine.context, type_value) else try v.text(engine, "Warning"));
        if (!c.JS_IsUndefined(code)) try js.define(engine, warning, "code", c.JS_DupValue(engine.context, code));
        if (!c.JS_IsUndefined(detail)) try js.define(engine, warning, "detail", c.JS_DupValue(engine.context, detail));
    } else {
        const error_constructor = try js.get(engine, state, "Error");
        defer engine.freeValue(error_constructor);
        const instance = c.JS_IsInstanceOf(engine.context, warning, error_constructor);
        if (instance < 0) return js.capture(engine);
        if (instance == 0) return invalid(engine, warning, "warning", "of type string or an instance of Error");
    }
    const name = try js.get(engine, warning, "name");
    defer engine.freeValue(name);
    var throw_deprecation = false;
    if (try equals(engine, name, "DeprecationWarning")) {
        if (try truthy(engine, process, "noDeprecation")) return c.pi_js_undefined();
        throw_deprecation = try truthy(engine, process, "throwDeprecation");
    }
    const callback_state = if (throw_deprecation) try js.object(engine) else c.JS_DupValue(engine.context, state);
    defer engine.freeValue(callback_state);
    if (throw_deprecation) {
        try js.define(engine, callback_state, "process", c.JS_DupValue(engine.context, process));
        try js.define(engine, callback_state, "warning", c.JS_DupValue(engine.context, warning));
    }
    const callback = try makeFunction(engine, callback_state, if (throw_deprecation) .throwWarning else .doEmitWarning, if (throw_deprecation) "" else "doEmitWarning", if (throw_deprecation) 0 else 1);
    defer engine.freeValue(callback);
    const result = try js.invoke(engine, process, "nextTick", if (throw_deprecation) &.{callback} else &.{ callback, warning });
    engine.freeValue(result);
    return c.pi_js_undefined();
}
fn printWarning(engine: *js.Engine, state: c.JSValue, process: c.JSValue, warning: c.JSValue) !void {
    if (!c.JS_IsError(warning)) return;
    const name = try js.get(engine, warning, "name");
    defer engine.freeValue(name);
    const deprecation = try equals(engine, name, "DeprecationWarning");
    if (deprecation and try truthy(engine, process, "noDeprecation")) return;
    const trace = try truthy(engine, process, "traceProcessWarnings") or (deprecation and try truthy(engine, process, "traceDeprecation"));
    var text: []u8 = undefined;
    if (trace) {
        const stack = try js.get(engine, warning, "stack");
        defer engine.freeValue(stack);
        text = try engine.toString(stack);
    } else {
        const result = try js.invoke(engine, warning, "toString", &.{});
        defer engine.freeValue(result);
        text = try engine.toString(result);
    }
    defer engine.gpa.free(text);
    const code = try js.get(engine, warning, "code");
    defer engine.freeValue(code);
    const code_text = if (v.truthy(engine, code)) try engine.toString(code) else try engine.gpa.dupe(u8, "");
    defer engine.gpa.free(code_text);
    const detail = try js.get(engine, warning, "detail");
    defer engine.freeValue(detail);
    const detail_text = if (c.JS_IsString(detail)) try engine.toString(detail) else try engine.gpa.dupe(u8, "");
    defer engine.gpa.free(detail_text);
    const pid: u32 = switch (builtin.os.tag) {
        .windows => std.os.windows.GetCurrentProcessId(),
        .linux => @intCast(std.os.linux.getpid()),
        else => @intCast(std.c.getpid()),
    };
    const prefix = if (code_text.len > 0) try std.fmt.allocPrint(engine.gpa, "(pi:{d}) [{s}] ", .{ pid, code_text }) else try std.fmt.allocPrint(engine.gpa, "(pi:{d}) ", .{pid});
    defer engine.gpa.free(prefix);
    const hint = !trace and !try truthy(engine, state, "hintShown");
    if (hint) try v.set(engine, state, "hintShown", c.pi_js_bool(engine.context, 1));
    const line = try std.fmt.allocPrint(engine.gpa, "{s}{s}{s}{s}{s}\n", .{ prefix, text, if (c.JS_IsString(detail)) "\n" else "", detail_text, if (hint) (if (deprecation) "\n(Use `pi --trace-deprecation ...` to show where the warning was created)" else "\n(Use `pi --trace-warnings ...` to show where the warning was created)") else "" });
    defer engine.gpa.free(line);
    if (engine.native_io) |io| try std.Io.File.stderr().writeStreamingAll(io, line) else return error.NativeProcessWarningRequiresIO;
}
pub fn install(engine: *js.Engine, process: c.JSValue) !void {
    try events.install(engine);
    const exports = engine.native_module_values.get("node:events") orelse return error.NativeEventEmitterMissing;
    const constructor = try js.get(engine, exports, "EventEmitter");
    defer engine.freeValue(constructor);
    const initialized = try js.call(engine, constructor, process, &.{});
    engine.freeValue(initialized);
    const prototype = try js.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    // Only the genuine event operations are exposed on the existing host
    // process. Its prototype is not branded as a complete Node Process.
    inline for (.{ "setMaxListeners", "getMaxListeners", "emit", "addListener", "on", "prependListener", "once", "prependOnceListener", "removeListener", "off", "removeAllListeners", "listeners", "rawListeners", "listenerCount", "eventNames" }) |name| try js.define(engine, process, name, try js.get(engine, prototype, name));
    try js.define(engine, process, "nextTick", try events.nextTickFunction(engine, process));
    const state = try js.object(engine);
    defer engine.freeValue(state);
    try js.define(engine, state, "process", c.JS_DupValue(engine.context, process));
    try js.define(engine, state, "Error", try js.global(engine, "Error"));
    try js.define(engine, state, "hintShown", c.pi_js_bool(engine.context, 0));
    try js.define(engine, process, "emitWarning", try makeFunction(engine, state, .emitWarning, "emitWarning", 4));
    const callback = try makeFunction(engine, state, .onWarning, "onWarning", 1);
    defer engine.freeValue(callback);
    const event = try v.text(engine, "warning");
    defer engine.freeValue(event);
    const result = try js.invoke(engine, process, "on", &.{ event, callback });
    engine.freeValue(result);
}
