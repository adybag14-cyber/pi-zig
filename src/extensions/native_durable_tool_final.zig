//! Tool result projection after all reports, hooks, and retention limits.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const calls = @import("native_durable_tool_call.zig");
const awaiting = @import("native_durable_await.zig");
const output = @import("native_durable_tool_output.zig");
const window = @import("../durable/output_window.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Reported = struct { snapshot: c.JSValue, details: c.JSValue, diagnostics: c.JSValue, limits: window.Limits };
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, value: c.JSValue, name: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, value, name));
    }
};
fn put(engine: *Engine, target: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, target, name, c.JS_DupValue(engine.context, value));
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
pub fn run(engine: *Engine, intrinsics: *awaiting.Intrinsics, cache: *output.Cache, runtime: c.JSValue, input: c.JSValue, call: c.JSValue, tool: c.JSValue, result: c.JSValue, reported: Reported, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "runtime", runtime }, .{ "input", input }, .{ "call", call }, .{ "tool", tool }, .{ "context", context }, .{ "weak", cache.weak }, .{ "iterator", cache.iterator_symbol }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try put(engine, state, field[0], field[1]);
    try put(engine, state, "maxBytes", c.JS_NewFloat64(engine.context, @floatFromInt(reported.limits.maxBytes)));
    try put(engine, state, "maxLines", c.JS_NewFloat64(engine.context, @floatFromInt(reported.limits.maxLines)));
    try put(engine, state, "tail", c.pi_js_bool(engine.context, @intFromBool(reported.limits.retain == .tail)));
    const checked_output = try scope.get(result, "output");
    const retained = if (c.JS_IsUndefined(checked_output)) reported.snapshot else c.pi_js_undefined();
    const content = if (c.JS_IsUndefined(retained)) try scope.get(result, "output") else content: {
        const text = try scope.get(retained, "text");
        const array = try scope.own(try vm.array(engine));
        if (!try calls.equalsString(engine, text, "")) {
            const item = try scope.own(try vm.object(engine));
            try @import("native_tool_info.zig").putData(engine, item, "type", try engine.checked(c.JS_NewString(engine.context, "text")));
            try put(engine, item, "text", try scope.get(retained, "text"));
            try js.push(engine, array, item);
        }
        break :content array;
    };
    try put(engine, state, "retained", retained);
    try put(engine, state, "originalOutput", content);
    const final = try scope.own(try js.spread(engine, result));
    try put(engine, final, "output", content);
    const first_details = try scope.get(result, "details");
    try put(engine, final, "details", if (c.JS_IsUndefined(first_details)) reported.details else try scope.get(result, "details"));
    const diagnostics = try scope.own(try js.collect(engine, reported.diagnostics, cache.iterator_symbol));
    const raw_result_diagnostics = try scope.get(result, "diagnostics");
    const result_diagnostics = if (nullish(raw_result_diagnostics)) try scope.own(try vm.array(engine)) else raw_result_diagnostics;
    var iterator = try js.Iterator.init(engine, result_diagnostics, cache.iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        try js.push(engine, diagnostics, item);
    }
    try put(engine, final, "diagnostics", diagnostics);
    try put(engine, state, "final", final);
    var captures = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, hook, "", 1, 0, captures.len, &captures)));
    const hooks = try scope.get(runtime, "hooks");
    const event = try scope.own(try engine.checked(c.JS_NewString(engine.context, "afterTool")));
    const pending = try scope.own(try vm.invoke(engine, hooks, "each", &.{ event, callback }));
    return awaiting.continueWith(afterHooks, engine, intrinsics, state, pending, 0);
}
fn hook(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return invokeHook(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn invokeHook(engine: *Engine, state: c.JSValue, callback: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    var args = [_]c.JSValue{ try scope.get(state, "call"), try scope.get(state, "final"), try scope.get(state, "runtime"), try scope.get(state, "context") };
    const pending = try scope.own(try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), args.len, &args)));
    return awaiting.continueWith(hookResult, engine, &intrinsics, state, pending, 0);
}
fn hookResult(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    if (!nullish(value)) try put(engine, state, "final", value);
    return c.pi_js_undefined();
}
fn diagnostic(engine: *Engine, severity: [:0]const u8, code: [:0]const u8, message: []const u8) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try @import("native_tool_info.zig").putData(engine, result, "severity", try engine.checked(c.JS_NewString(engine.context, severity)));
    try @import("native_tool_info.zig").putData(engine, result, "code", try engine.checked(c.JS_NewString(engine.context, code)));
    try @import("native_tool_info.zig").putData(engine, result, "message", try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)));
    return result;
}
fn truncated(engine: *Engine, bytes: c.JSValue, lines: c.JSValue, tail: bool) !c.JSValue {
    const byte_text = try engine.toString(bytes);
    defer engine.gpa.free(byte_text);
    const line_text = try engine.toString(lines);
    defer engine.gpa.free(line_text);
    const message = try std.fmt.allocPrint(engine.gpa, "Output truncated to its {s}: {s} lines, {s} bytes dropped", .{ if (tail) "end" else "beginning", line_text, byte_text });
    defer engine.gpa.free(message);
    return diagnostic(engine, "warn", "truncated", message);
}
fn afterHooks(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    return finish(engine, state);
}
fn finish(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var final = try scope.get(state, "final");
    const harness = try scope.own(try vm.array(engine));
    const retained = try scope.get(state, "retained");
    const tail = c.JS_ToBool(engine.context, try scope.get(state, "tail")) != 0;
    if (!c.JS_IsUndefined(retained)) {
        const bytes = try scope.get(retained, "droppedBytes");
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, bytes) < 0) return js.capture(engine);
        if (number > 0) {
            const final_output = try scope.get(final, "output");
            const original = try scope.get(state, "originalOutput");
            if (c.JS_IsStrictEqual(engine.context, final_output, original)) {
                const item = try scope.own(try truncated(engine, bytes, try scope.get(retained, "droppedLines"), tail));
                try js.push(engine, harness, item);
            }
        }
    }
    var max_bytes: f64 = 0;
    var max_lines: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &max_bytes, try scope.get(state, "maxBytes")) < 0 or c.JS_ToFloat64(engine.context, &max_lines, try scope.get(state, "maxLines")) < 0) return js.capture(engine);
    const raw_content = try scope.get(final, "output");
    const content = if (nullish(raw_content)) try scope.own(try vm.array(engine)) else raw_content;
    const symbol = try scope.get(state, "iterator");
    var bounded = try @import("native_durable_tool_bound.zig").content(engine, content, .{ .maxBytes = @intFromFloat(max_bytes), .maxLines = @intFromFloat(max_lines), .retain = if (tail) .tail else .head }, symbol);
    defer bounded.deinit(engine);
    if (bounded.dropped_bytes > 0) {
        const item = try scope.own(try truncated(engine, c.JS_NewFloat64(engine.context, @floatFromInt(bounded.dropped_bytes)), c.JS_NewFloat64(engine.context, @floatFromInt(bounded.dropped_lines)), tail));
        try js.push(engine, harness, item);
    }
    var cache: output.Cache = .{ .engine = engine, .weak = try scope.get(state, "weak"), .iterator_symbol = symbol };
    const tool = try scope.get(state, "tool");
    const broken = try cache.failure(tool, final);
    defer if (broken) |text| engine.gpa.free(text);
    const input = try scope.get(state, "input");
    if (broken) |message| {
        _ = try scope.get(final, "structuredOutput");
        final = try scope.own(try restWithoutStructured(engine, final));
        const kind = try scope.get(input, "kind");
        if (try calls.equalsString(engine, kind, "nested")) {
            try put(engine, final, "isError", c.pi_js_bool(engine.context, 1));
            const item = try scope.own(try diagnostic(engine, "error", "invalid_structured_output", message));
            try js.push(engine, harness, item);
        } else {
            const constructor = try scope.own(try js.global(engine, "Error"));
            const text = try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)));
            var args = [_]c.JSValue{text};
            const failure = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
            const runtime = try scope.get(state, "runtime");
            _ = try scope.own(try vm.invoke(engine, runtime, "report", &.{failure}));
        }
    }
    const kind = try scope.get(input, "kind");
    if (try calls.equalsString(engine, kind, "nested") and c.JS_IsUndefined(try scope.get(tool, "structuredOutputSchema"))) {
        const projected = try scope.own(try js.spread(engine, final));
        const value = try scope.own(try output.outputValue(engine, bounded.content));
        try put(engine, projected, "structuredOutput", value);
        final = projected;
    }
    const result = try js.spread(engine, final);
    errdefer engine.freeValue(result);
    try put(engine, result, "output", bounded.content);
    const raw_diagnostics = try scope.get(final, "diagnostics");
    const source = if (nullish(raw_diagnostics)) try scope.own(try vm.array(engine)) else raw_diagnostics;
    const diagnostics = try scope.own(try js.collect(engine, source, symbol));
    var iterator = try js.Iterator.init(engine, harness, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        try js.push(engine, diagnostics, item);
    }
    try put(engine, result, "diagnostics", diagnostics);
    return result;
}
fn restWithoutStructured(engine: *Engine, source: c.JSValue) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    const excluded = c.JS_NewAtom(engine.context, "structuredOutput");
    defer c.JS_FreeAtom(engine.context, excluded);
    for (names[0..count]) |entry| {
        if (entry.atom == excluded) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, source, entry.atom);
        if (present < 0) return js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, source, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return result;
}
