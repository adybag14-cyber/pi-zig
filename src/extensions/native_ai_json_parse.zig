//! Original b06 JSON string repair and final complete tool-arguments helpers.
//! Scoped intrinsic syntax diagnostics preserve caller/delegate error origin.
//! Partial-json streaming is a separate algorithm, not exported by this module.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum { repairJson, parseJsonWithRepair, parseToolCallArguments };
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const characters = try scope.array();
    for ([_][]const u8{ "\"", "\\", "/", "b", "f", "n", "r", "t" }, 0..) |character, index| try scope.index(characters, @intCast(index), try scope.text(character));
    const valid = try scope.own(try js.builtin(engine, "Set", &.{characters}));
    const output = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                const input = if (args.len > 0) args[0] else c.pi_js_undefined();
                return switch (method) {
                    .repairJson => repair(host, input, roots[0]),
                    .parseJsonWithRepair => parseWithRepair(host, input, roots[0]),
                    .parseToolCallArguments => parseFinal(host, input, roots[0]),
                };
            }
        };
        try scope.put(output, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, 1, Adapter.call, &.{valid})));
    }
    return c.JS_DupValue(engine.context, output);
}
fn number(engine: *em.Engine, n: usize) c.JSValue {
    return c.JS_NewFloat64(engine.context, @floatFromInt(n));
}
fn same(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn append(engine: *em.Engine, target: *c.JSValue, value: c.JSValue) !void {
    const next = try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, target.*, value));
    engine.freeValue(target.*);
    target.* = next;
}
fn appendText(scope: *Scope, target: *c.JSValue, text: []const u8) !void {
    try append(scope.engine, target, try scope.text(text));
}
pub fn repair(engine: *em.Engine, input: c.JSValue, valid: c.JSValue) !c.JSValue {
    var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(engine);
    defer diagnostics.deinit();
    var output = try engine.checked(c.JS_NewString(engine.context, ""));
    defer engine.freeValue(output);
    var inside = false;
    var index: usize = 0;
    var steps: usize = 0;
    while (true) : (index += 1) {
        try @import("native_ai_budget.zig").step(engine, &steps);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        if (temp.nullish(input)) return js.typeError(engine, if (c.JS_IsNull(input)) "Cannot read properties of null (reading 'length')" else "Cannot read properties of undefined (reading 'length')");
        if (!try arithmetic.compare(engine, .less, number(engine, index), try row.get(input, "length"))) break;
        const char = try row.own(try js.getKey(engine, input, number(engine, index)));
        if (!inside) {
            try append(engine, &output, char);
            if (try same(&row, char, "\"")) inside = true;
            continue;
        }
        if (try same(&row, char, "\"")) {
            try append(engine, &output, char);
            inside = false;
            continue;
        }
        if (try same(&row, char, "\\")) {
            const next = try row.own(try js.getKey(engine, input, number(engine, index + 1)));
            if (c.JS_IsUndefined(next)) {
                try appendText(&row, &output, "\\\\");
                continue;
            }
            if (try same(&row, next, "u")) {
                const digits = try row.invoke(input, "slice", &.{ number(engine, index + 2), number(engine, index + 6) });
                var args = [_]c.JSValue{try row.text("^[0-9a-fA-F]{4}$")};
                const regex = try row.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, args.len, &args)));
                if (row.truthy(try row.invoke(regex, "test", &.{digits}))) {
                    try appendText(&row, &output, "\\u");
                    try append(engine, &output, try row.stringify(digits));
                    index += 5;
                    continue;
                }
            }
            if (row.truthy(try row.invoke(valid, "has", &.{next}))) {
                try appendText(&row, &output, "\\");
                try append(engine, &output, try row.stringify(next));
                index += 1;
                continue;
            }
            try appendText(&row, &output, "\\\\");
            continue;
        }
        const code = try row.invoke(char, "codePointAt", &.{c.JS_NewInt32(engine.context, 0)});
        if (!c.JS_IsUndefined(code) and try arithmetic.compare(engine, .greater_equal, code, c.JS_NewInt32(engine.context, 0)) and try arithmetic.compare(engine, .less_equal, code, c.JS_NewInt32(engine.context, 31))) {
            var escaped = false;
            inline for (.{ .{ "\x08", "\\b" }, .{ "\x0c", "\\f" }, .{ "\n", "\\n" }, .{ "\r", "\\r" }, .{ "\t", "\\t" } }) |pair| {
                if (!escaped and try same(&row, char, pair[0])) {
                    try appendText(&row, &output, pair[1]);
                    escaped = true;
                }
            }
            if (!escaped) {
                // Source intentionally reads codePointAt a second time here.
                const repeated = try row.invoke(char, "codePointAt", &.{c.JS_NewInt32(engine.context, 0)});
                const formatted = if (temp.nullish(repeated)) try row.text("0000") else try row.invoke(try row.invoke(repeated, "toString", &.{c.JS_NewInt32(engine.context, 16)}), "padStart", &.{ c.JS_NewInt32(engine.context, 4), try row.text("0") });
                try appendText(&row, &output, "\\u");
                try append(engine, &output, try row.stringify(formatted));
            }
        } else try append(engine, &output, char);
    }
    return c.JS_DupValue(engine.context, output);
}
fn caught(engine: *em.Engine, err: anyerror, generation: u64) !c.JSValue {
    const classified = engine.nativeAllocationError(err, generation);
    if (classified == error.OutOfMemory) return classified;
    const value = engine.captured_exception orelse return err;
    engine.captured_exception = null;
    return value;
}
fn throwValue(engine: *em.Engine, value: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value))) catch |err| return err;
    unreachable;
}
pub fn parseWithRepair(engine: *em.Engine, input: c.JSValue, valid: c.JSValue) !c.JSValue {
    var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(engine);
    defer diagnostics.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    return js.invoke(engine, try scope.global("JSON"), "parse", &.{input}) catch |err| {
        const reason = try scope.own(try caught(engine, err, generation));
        const repaired = try scope.own(try repair(engine, input, valid));
        if (!scope.equal(repaired, input)) return js.invoke(engine, try scope.global("JSON"), "parse", &.{repaired});
        return throwValue(engine, reason);
    };
}
pub fn parseFinal(engine: *em.Engine, input: c.JSValue, valid: c.JSValue) !c.JSValue {
    var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(engine);
    defer diagnostics.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.object();
    if (temp.nullish(input) or !scope.truthy(try scope.invoke(input, "trim", &.{}))) {
        try scope.put(output, "arguments", try scope.object());
        return c.JS_DupValue(engine.context, output);
    }
    const generation = engine.native_allocation_generation;
    const parsed = parseObject(&scope, input, valid) catch |err| {
        const reason = try scope.own(try caught(engine, err, generation));
        try scope.put(output, "arguments", try scope.object());
        const constructor = try scope.global("Error");
        const instance = c.JS_IsInstanceOf(engine.context, reason, constructor);
        if (instance < 0) return js.capture(engine);
        const message = if (instance == 1) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
        const prefix = try scope.concat(try scope.stringify(message), try scope.text("\n\nReceived arguments:\n"));
        try scope.put(output, "argumentsError", try scope.concat(prefix, try scope.stringify(input)));
        return c.JS_DupValue(engine.context, output);
    };
    try scope.put(output, "arguments", try scope.own(parsed));
    return c.JS_DupValue(engine.context, output);
}
fn parseObject(scope: *Scope, input: c.JSValue, valid: c.JSValue) !c.JSValue {
    const parsed = try scope.own(try parseWithRepair(scope.engine, input, valid));
    if (!c.JS_IsObject(parsed) or c.JS_IsFunction(scope.engine.context, parsed) or c.JS_IsNull(parsed) or scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{parsed}))) {
        const reason = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text("Tool arguments must be a JSON object")}));
        return throwValue(scope.engine, reason);
    }
    return c.JS_DupValue(scope.engine.context, parsed);
}
