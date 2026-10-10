//! Durable nested-call admission primitives. Only explicit keys are checked;
//! positional default keys deliberately occupy the reserved positive integers.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const js = @import("native_js_values.zig");
const await_mod = @import("native_durable_await.zig");
pub const ErrorMessage = *const fn (*Engine, c.JSValue) anyerror!c.JSValue;
pub const Checked = union(enum) {
    arguments: c.JSValue,
    failure: c.JSValue,
    pub fn deinit(self: Checked, engine: *Engine) void {
        switch (self) {
            inline else => |value| engine.freeValue(value),
        }
    }
};

pub fn resolveTool(engine: *Engine, agent: c.JSValue, nested: bool, name: c.JSValue) !c.JSValue {
    const tools = try vm.get(engine, agent, if (nested) "callable" else "tools");
    defer engine.freeValue(tools);
    var captures = [_]c.JSValue{name};
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, matchesTool, "", 1, 0, captures.len, &captures));
    defer engine.freeValue(predicate);
    return vm.invoke(engine, tools, "find", &.{predicate});
}
fn matchesTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const item = if (argc > 0) argv[0] else c.pi_js_undefined();
    const name = vm.get(engine, item, "name") catch |err| return @import("native_durable.zig").reject(engine, err);
    defer engine.freeValue(name);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, name, data[0])));
}
pub fn prepare(engine: *Engine, tool: c.JSValue, arguments: c.JSValue, error_message: ErrorMessage) !Checked {
    const initial = try vm.get(engine, tool, "prepareArguments");
    defer engine.freeValue(initial);
    if (c.JS_IsUndefined(initial)) return .{ .arguments = c.JS_DupValue(engine.context, arguments) };
    // Source tests existence before its try, then reads the property again for
    // the call inside the try. Stateful getters must keep those two reads.
    const callback = vm.get(engine, tool, "prepareArguments") catch |err| return checkedFailure(engine, err, error_message);
    defer engine.freeValue(callback);
    var args = [_]c.JSValue{arguments};
    const result = c.JS_Call(engine.context, callback, tool, args.len, &args);
    if (!c.JS_IsException(result)) return .{ .arguments = result };
    _ = engine.checked(result) catch {};
    return checkedFailure(engine, error.JavaScriptException, error_message);
}
pub fn validate(engine: *Engine, tool: c.JSValue, call: c.JSValue, arguments: c.JSValue, error_message: ErrorMessage) !Checked {
    return validateOwned(engine, tool, call, arguments) catch |err| return checkedFailure(engine, err, error_message);
}
fn validateOwned(engine: *Engine, tool: c.JSValue, call: c.JSValue, arguments: c.JSValue) !Checked {
    const projected = try js.spread(engine, call);
    defer engine.freeValue(projected);
    try @import("native_tool_info.zig").putData(engine, projected, "arguments", c.JS_DupValue(engine.context, arguments));
    const result = try @import("native_tool_arguments.zig").validateArguments(engine, tool, projected);
    return .{ .arguments = result };
}
fn checkedFailure(engine: *Engine, err: anyerror, error_message: ErrorMessage) !Checked {
    if (err != error.JavaScriptException) return err;
    const failure = engine.captured_exception orelse return err;
    const retained = c.JS_DupValue(engine.context, failure);
    defer engine.freeValue(retained);
    return .{ .failure = try error_message(engine, retained) };
}

pub fn readCall(engine: *Engine, runtime: c.JSValue, input: c.JSValue, context: c.JSValue, assistant_entry: c.JSValue, intrinsics: *await_mod.Intrinsics) !c.JSValue {
    const kind = try vm.get(engine, input, "kind");
    defer engine.freeValue(kind);
    if (try equalsString(engine, kind, "nested")) {
        const call = try vm.get(engine, input, "call");
        defer engine.freeValue(call);
        const result = try js.spread(engine, call);
        defer engine.freeValue(result);
        const parent = try vm.object(engine);
        defer engine.freeValue(parent);
        const put = @import("native_tool_info.zig").putData;
        try put(engine, parent, "taskId", try vm.get(engine, input, "parent"));
        try put(engine, parent, "callId", try vm.get(engine, input, "parentCallId"));
        try put(engine, result, "parent", c.JS_DupValue(engine.context, parent));
        return intrinsics.chain(engine, result, c.pi_js_undefined(), c.pi_js_undefined());
    }
    const id = try vm.get(engine, input, "assistant");
    defer engine.freeValue(id);
    const entry = try vm.invoke(engine, runtime, "entry", &.{ assistant_entry, id, context });
    defer engine.freeValue(entry);
    var captures = [_]c.JSValue{input};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData2(engine.context, entryRead, "", 1, 0, captures.len, &captures));
    defer engine.freeValue(fulfilled);
    return intrinsics.chain(engine, entry, fulfilled, c.pi_js_undefined());
}
fn entryRead(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return modelCall(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn modelCall(engine: *Engine, entry: c.JSValue, input: c.JSValue) !c.JSValue {
    const id = try vm.get(engine, input, "callId");
    defer engine.freeValue(id);
    if (!c.JS_IsUndefined(entry) and !c.JS_IsNull(entry)) {
        const messages = try vm.get(engine, entry, "model");
        defer engine.freeValue(messages);
        if (!c.JS_IsUndefined(messages) and !c.JS_IsNull(messages)) {
            const message = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, 0));
            defer engine.freeValue(message);
            if (!c.JS_IsUndefined(message) and !c.JS_IsNull(message)) {
                const role = try vm.get(engine, message, "role");
                defer engine.freeValue(role);
                if (try equalsString(engine, role, "assistant")) {
                    const contents = try vm.get(engine, message, "content");
                    defer engine.freeValue(contents);
                    var captures = [_]c.JSValue{id};
                    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, matchesCall, "", 1, 0, captures.len, &captures));
                    defer engine.freeValue(predicate);
                    const found = try vm.invoke(engine, contents, "find", &.{predicate});
                    if (!c.JS_IsUndefined(found)) return found;
                    engine.freeValue(found);
                }
            }
        }
    }
    const assistant = try vm.get(engine, input, "assistant");
    defer engine.freeValue(assistant);
    const assistant_text = try engine.toString(assistant);
    defer engine.gpa.free(assistant_text);
    const id_text = try engine.toString(id);
    defer engine.gpa.free(id_text);
    const message = try std.fmt.allocPrint(engine.gpa, "Entry {s} has no tool call {s}", .{ assistant_text, id_text });
    defer engine.gpa.free(message);
    return throwError(engine, message);
}
fn matchesCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return matchesCallOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn matchesCallOwned(engine: *Engine, item: c.JSValue, id: c.JSValue) !c.JSValue {
    const kind = try vm.get(engine, item, "type");
    defer engine.freeValue(kind);
    if (!try equalsString(engine, kind, "toolCall")) return c.pi_js_bool(engine.context, 0);
    const actual = try vm.get(engine, item, "id");
    defer engine.freeValue(actual);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, actual, id)));
}
pub fn equalsString(engine: *Engine, value: c.JSValue, text: []const u8) !bool {
    if (!c.JS_IsString(value)) return false;
    const actual = try engine.toString(value);
    defer engine.gpa.free(actual);
    return std.mem.eql(u8, actual, text);
}
fn throwError(engine: *Engine, message: []const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const value = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(value);
    var args = [_]c.JSValue{value};
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
    return engine.checked(c.JS_Throw(engine.context, failure));
}

pub fn checkKey(engine: *Engine, key: c.JSValue) !void {
    var invalid = false;
    const text = if (c.JS_IsString(key)) try engine.toString(key) else null;
    defer if (text) |value| engine.gpa.free(value);
    if (text) |value| invalid = value.len == 0;
    if (!invalid) {
        const slash = try engine.checked(c.JS_NewString(engine.context, "/"));
        defer engine.freeValue(slash);
        const includes = try vm.invoke(engine, key, "includes", &.{slash});
        defer engine.freeValue(includes);
        invalid = c.JS_ToBool(engine.context, includes) != 0;
    }
    if (!invalid) {
        if (text) |value| invalid = std.mem.eql(u8, value, "__proto__");
    }
    if (!invalid) {
        const converted = if (text) |value| value else try engine.toString(key);
        defer if (text == null) engine.gpa.free(converted);
        if (converted.len != 0 and converted[0] >= '1' and converted[0] <= '9') {
            invalid = true;
            for (converted[1..]) |byte| if (byte < '0' or byte > '9') {
                invalid = false;
                break;
            };
        }
    }
    if (!invalid) return;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const json = try vm.get(engine, global, "JSON");
    defer engine.freeValue(json);
    const encoded_value = try vm.invoke(engine, json, "stringify", &.{key});
    defer engine.freeValue(encoded_value);
    const encoded = try engine.toString(encoded_value);
    defer engine.gpa.free(encoded);
    const message = try std.fmt.allocPrint(engine.gpa, "Nested call key {s} must be non-empty, without \"/\", not \"__proto__\", and not a positive integer", .{encoded});
    defer engine.gpa.free(message);
    const constructor = try vm.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const message_value = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(message_value);
    var arguments = [_]c.JSValue{message_value};
    const error_value = try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
    _ = try engine.checked(c.JS_Throw(engine.context, error_value));
    unreachable;
}
