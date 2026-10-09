//! Durable v2 structured-output primitives. The owning ToolTask driver keeps
//! this cache and calls these functions after output bounding and afterTool.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const validators = @import("native_tool_validator_cache.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;

pub const Cache = struct {
    engine: *Engine,
    weak: c.JSValue,
    iterator_symbol: c.JSValue,
    pub fn init(engine: *Engine) !Cache {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try vm.get(engine, global, "WeakMap");
        defer engine.freeValue(constructor);
        const weak = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
        errdefer engine.freeValue(weak);
        const symbol = try vm.get(engine, global, "Symbol");
        defer engine.freeValue(symbol);
        return .{ .engine = engine, .weak = weak, .iterator_symbol = try vm.get(engine, symbol, "iterator") };
    }
    pub fn deinit(self: *Cache) void {
        self.engine.freeValue(self.weak);
        self.engine.freeValue(self.iterator_symbol);
    }
    pub fn mark(self: *Cache, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        c.JS_MarkValue(runtime, self.weak, marker);
        c.JS_MarkValue(runtime, self.iterator_symbol, marker);
    }
    pub fn get(self: *Cache, schema: c.JSValue) !c.JSValue {
        const previous = try vm.invoke(self.engine, self.weak, "get", &.{schema});
        if (!c.JS_IsUndefined(previous)) return previous;
        self.engine.freeValue(previous);
        const compiled = try validators.compileFresh(self.engine, schema);
        errdefer self.engine.freeValue(compiled);
        const stored = try vm.invoke(self.engine, self.weak, "set", &.{ schema, compiled });
        self.engine.freeValue(stored);
        return compiled;
    }
    /// Owned error text, or null for a valid result. Getter order matches the
    /// Source's structuredOutputError, including the error-result exception.
    pub fn failure(self: *Cache, tool: c.JSValue, result: c.JSValue) !?[]u8 {
        const engine = self.engine;
        const schema = try vm.get(engine, tool, "structuredOutputSchema");
        defer engine.freeValue(schema);
        const value = try vm.get(engine, result, "structuredOutput");
        defer engine.freeValue(value);
        if (c.JS_IsUndefined(schema) and c.JS_IsUndefined(value)) return null;
        if (!c.JS_IsUndefined(schema) and c.JS_IsUndefined(value)) {
            const is_error = try vm.get(engine, result, "isError");
            defer engine.freeValue(is_error);
            if (c.JS_IsBool(is_error) and c.JS_ToBool(engine.context, is_error) != 0) return null;
        }
        if (c.JS_IsUndefined(schema) or c.JS_IsUndefined(value)) {
            const name_value = try vm.get(engine, tool, "name");
            defer engine.freeValue(name_value);
            const name = try engine.toString(name_value);
            defer engine.gpa.free(name);
            if (c.JS_IsUndefined(schema)) return std.fmt.allocPrint(engine.gpa, "Tool {s} returned structuredOutput but declares no structuredOutputSchema", .{name});
            return std.fmt.allocPrint(engine.gpa, "Tool {s} returned no structuredOutput", .{name});
        }
        const compiled = try self.get(schema);
        defer engine.freeValue(compiled);
        if (try validators.check(engine, compiled, value)) return null;
        const errors = try vm.invoke(engine, compiled, "Errors", &.{value});
        defer engine.freeValue(errors);
        var iterator = try js.Iterator.init(engine, errors, self.iterator_symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        const first = try iterator.next() orelse c.pi_js_undefined();
        defer engine.freeValue(first);
        try iterator.close();
        const path_value = if (c.JS_IsUndefined(first)) c.pi_js_undefined() else try vm.get(engine, first, "instancePath");
        defer engine.freeValue(path_value);
        const message_value = if (c.JS_IsUndefined(first)) c.pi_js_undefined() else try vm.get(engine, first, "message");
        defer engine.freeValue(message_value);
        const path = if (c.JS_IsUndefined(path_value)) try engine.gpa.dupe(u8, "") else try engine.toString(path_value);
        defer engine.gpa.free(path);
        const normalized = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;
        for (normalized) |*byte| if (byte.* == '/') {
            byte.* = '.';
        };
        const message = if (c.JS_IsUndefined(message_value) or c.JS_IsNull(message_value)) try engine.gpa.dupe(u8, "invalid") else try engine.toString(message_value);
        defer engine.gpa.free(message);
        const name_value = try vm.get(engine, tool, "name");
        defer engine.freeValue(name_value);
        const name = try engine.toString(name_value);
        defer engine.gpa.free(name);
        return std.fmt.allocPrint(engine.gpa, "Tool {s} returned structuredOutput that does not match its schema: {s}: {s}", .{ name, if (normalized.len == 0) "root" else normalized, message });
    }
};

/// Source's program-facing value for a tool without a structured schema.
/// The caller passes the bounded content; shared image/list references survive.
pub fn outputValue(engine: *Engine, output: c.JSValue) !c.JSValue {
    const count = try vm.length(engine, output);
    if (count == 0) return engine.checked(c.JS_NewString(engine.context, ""));
    if (count > 1) return c.JS_DupValue(engine.context, output);
    const only = try engine.checked(c.JS_GetPropertyUint32(engine.context, output, 0));
    errdefer engine.freeValue(only);
    const kind = try vm.get(engine, only, "type");
    defer engine.freeValue(kind);
    if (!c.JS_IsString(kind)) return only;
    const text = try engine.toString(kind);
    defer engine.gpa.free(text);
    if (!std.mem.eql(u8, text, "text")) return only;
    defer engine.freeValue(only);
    return vm.get(engine, only, "text");
}

/// The stored program result excludes model output and control. Strict Chord
/// copying supplies the same undefined-property removal and JSON boundary.
pub fn nestedResult(engine: *Engine, task_id: c.JSValue, result: c.JSValue, duration_ms: c.JSValue) !c.JSValue {
    const projected = try vm.object(engine);
    defer engine.freeValue(projected);
    const put = @import("native_tool_info.zig").putData;
    try put(engine, projected, "taskId", c.JS_DupValue(engine.context, task_id));
    try put(engine, projected, "structuredOutput", try vm.get(engine, result, "structuredOutput"));
    const is_error = try vm.get(engine, result, "isError");
    try put(engine, projected, "isError", if (c.JS_IsUndefined(is_error) or c.JS_IsNull(is_error)) value: {
        engine.freeValue(is_error);
        break :value c.pi_js_bool(engine.context, 0);
    } else is_error);
    try put(engine, projected, "details", try vm.get(engine, result, "details"));
    const diagnostics = try vm.get(engine, result, "diagnostics");
    try put(engine, projected, "diagnostics", if (c.JS_IsUndefined(diagnostics) or c.JS_IsNull(diagnostics)) value: {
        engine.freeValue(diagnostics);
        break :value try vm.array(engine);
    } else diagnostics);
    try put(engine, projected, "usage", try vm.get(engine, result, "usage"));
    try put(engine, projected, "durationMs", c.JS_DupValue(engine.context, duration_ms));
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    return @import("native_chord_json.zig").copyJson(engine, projected, options);
}
