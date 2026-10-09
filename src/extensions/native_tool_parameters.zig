//! Canonical parameter objects belonging to loaded builtin modules. Selecting a
//! key is a private native operation, never derived from caller context JSON.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const put = @import("native_tool_info.zig").putData;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Key = enum { resource_list, resource_read, codemode, tool_search };
pub fn get(engine: *Engine, key: Key, data: std.json.Value) !c.JSValue {
    const slot = &engine.native_tool_parameter_constants[@intFromEnum(key)];
    if (slot.*) |value| return c.JS_DupValue(engine.context, value);
    if (key == .codemode or key == .tool_search) {
        try initialize(engine);
        return c.JS_DupValue(engine.context, slot.*.?);
    }
    const value = try engine.fromJsonValue(data);
    slot.* = value;
    return c.JS_DupValue(engine.context, value);
}
const std = @import("std");
fn described(engine: *Engine, types: c.JSValue, kind: [:0]const u8, description: []const u8) !c.JSValue {
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try put(engine, options, "description", try engine.checked(c.JS_NewStringLen(engine.context, description.ptr, description.len)));
    return vm.invoke(engine, types, kind, &.{options});
}
/// Call before extension input, just as the Source module's constants are
/// initialized before the builtin extension factory executes.
pub fn initialize(engine: *Engine) !void {
    if (engine.native_tool_parameter_constants[@intFromEnum(Key.codemode)] != null and engine.native_tool_parameter_constants[@intFromEnum(Key.tool_search)] != null) return;
    const types = try @import("typebox.zig").create(engine);
    defer engine.freeValue(types);
    if (engine.native_tool_parameter_constants[@intFromEnum(Key.codemode)] == null) {
        const properties = try vm.object(engine);
        defer engine.freeValue(properties);
        try put(engine, properties, "code", try described(engine, types, "String", "Raw JavaScript source."));
        engine.native_tool_parameter_constants[@intFromEnum(Key.codemode)] = try vm.invoke(engine, types, "Object", &.{properties});
    }
    if (engine.native_tool_parameter_constants[@intFromEnum(Key.tool_search)] == null) {
        const properties = try vm.object(engine);
        defer engine.freeValue(properties);
        try put(engine, properties, "query", try described(engine, types, "String", "Search query for deferred tools."));
        const number = try described(engine, types, "Number", "Maximum number of tools to return. Defaults to 8.");
        defer engine.freeValue(number);
        try put(engine, properties, "limit", try vm.invoke(engine, types, "Optional", &.{number}));
        engine.native_tool_parameter_constants[@intFromEnum(Key.tool_search)] = try vm.invoke(engine, types, "Object", &.{properties});
    }
}

test "native durable VM canonical builtin schemas retain module identity and genuine TypeBox optional metadata" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try initialize(engine);
    const code = try get(engine, .codemode, .null);
    defer engine.freeValue(code);
    const code_again = try get(engine, .codemode, .{ .bool = false });
    defer engine.freeValue(code_again);
    const search = try get(engine, .tool_search, .null);
    defer engine.freeValue(search);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, code, code_again));
    const kind = try vm.get(engine, code, "~kind");
    defer engine.freeValue(kind);
    const label = try engine.toString(kind);
    defer engine.gpa.free(label);
    try std.testing.expectEqualStrings("Object", label);
    const properties = try vm.get(engine, search, "properties");
    defer engine.freeValue(properties);
    const limit = try vm.get(engine, properties, "limit");
    defer engine.freeValue(limit);
    const optional = try vm.get(engine, limit, "~optional");
    defer engine.freeValue(optional);
    try std.testing.expect(c.JS_ToBool(engine.context, optional) != 0);
    const data = try std.json.parseFromSlice(std.json.Value, engine.gpa, "{\"type\":\"object\",\"properties\":{}}", .{});
    defer data.deinit();
    const list = try get(engine, .resource_list, data.value);
    defer engine.freeValue(list);
    const list_again = try get(engine, .resource_list, .null);
    defer engine.freeValue(list_again);
    const read = try get(engine, .resource_read, data.value);
    defer engine.freeValue(read);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, list, list_again));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, list, read));
    const plain = try vm.get(engine, list, "~kind");
    defer engine.freeValue(plain);
    try std.testing.expect(c.JS_IsUndefined(plain));
}
