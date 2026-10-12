const std = @import("std");
const em = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const direct = @import("extensions/native_durable_json_value.zig");
const c = em.c;
fn legacy(engine: *em.Engine, value: json.Value) !c.JSValue {
    const encoded = try json.stringify(std.testing.allocator, value);
    defer std.testing.allocator.free(encoded);
    const terminated = try std.testing.allocator.dupeZ(u8, encoded);
    defer std.testing.allocator.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated, encoded.len, "native-durable"));
}
fn equivalent(engine: *em.Engine, value: json.Value) !void {
    const expected = try legacy(engine, value);
    defer engine.freeValue(expected);
    const actual = try durable.jsValue(engine, value);
    defer engine.freeValue(actual);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "expectedDto", c.JS_DupValue(engine.context, expected), c.JS_PROP_C_W_E) < 0 or c.JS_DefinePropertyValueStr(engine.context, global, "actualDto", c.JS_DupValue(engine.context, actual), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const checked = engine.eval(
        \\(function compare(actual,expected){
        \\ if(Object.is(actual,expected))return;
        \\ if(actual===null||expected===null||typeof actual!=='object'||typeof expected!=='object')throw Error('DTO scalar changed');
        \\ if(Object.getPrototypeOf(actual)!==Object.getPrototypeOf(expected))throw Error('DTO prototype changed');
        \\ const a=Reflect.ownKeys(actual),b=Reflect.ownKeys(expected);if(a.length!==b.length||a.some((key,index)=>key!==b[index]))throw Error('DTO own keys/order changed');
        \\ for(const key of a){const x=Object.getOwnPropertyDescriptor(actual,key),y=Object.getOwnPropertyDescriptor(expected,key);for(const flag of ['writable','enumerable','configurable'])if(x[flag]!==y[flag])throw Error('DTO descriptor changed');compare(x.value,y.value)}
        \\})(actualDto,expectedDto);
    , "native-durable-json-equivalence", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("DTO equivalence {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        return err;
    };
    engine.freeValue(checked);
}
test "native durable JSON DTO preserves actual C JSON.parse own properties scalar bits and prototypes" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const installed = try engine.eval("Object.defineProperty(Object.prototype,'blocked',{set(){throw Error('object setter ran')},configurable:true});Object.defineProperty(Array.prototype,'0',{set(){throw Error('array setter ran')},configurable:true});", "dto-inherited-setters", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(installed);
    const inputs = [_][]const u8{ "null", "true", "false", "[]", "{}", "[1,-0,0.1,5e-324,1.7976931348623157e308]", "{\"__proto__\":{\"polluted\":true},\"constructor\":\"literal\",\"prototype\":1,\"blocked\":2,\"2\":\"two\",\"1\":\"one\",\"01\":\"zero-one\",\"nul\\u0000key\":\"a\\u0000b\",\"unicode\":\"😀é\"}" };
    for (inputs) |input| {
        var owned = try json.Owned.parse(std.testing.allocator, input);
        defer owned.deinit();
        try std.testing.expect(direct.eligible(owned.value, 0));
        try equivalent(engine, owned.value);
    }
    try equivalent(engine, .{ .integer = std.math.maxInt(i64) });
    try equivalent(engine, .{ .integer = std.math.minInt(i64) });
    try equivalent(engine, .{ .float = -0.0 });
}
test "native durable JSON DTO keeps whole legacy path for lone surrogates raw numbers and deeper values" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var surrogate = try json.Owned.parse(std.testing.allocator, "{\"\\ud800\":\"x\\udfff\"}");
    defer surrogate.deinit();
    try std.testing.expect(!direct.eligible(surrogate.value, 0));
    try equivalent(engine, surrogate.value);
    const raw: json.Value = .{ .number_string = "{\"raw\":[1,2,3]}" };
    try std.testing.expect(!direct.eligible(raw, 0));
    try equivalent(engine, raw);
    var deep: std.ArrayList(u8) = .empty;
    defer deep.deinit(std.testing.allocator);
    try deep.appendNTimes(std.testing.allocator, '[', 130);
    try deep.append(std.testing.allocator, '0');
    try deep.appendNTimes(std.testing.allocator, ']', 130);
    var owned = try json.Owned.parse(std.testing.allocator, deep.items);
    defer owned.deinit();
    try std.testing.expect(!direct.eligible(owned.value, 0));
    try equivalent(engine, owned.value);
    try std.testing.expectError(error.NonfiniteJSONNumber, durable.jsValue(engine, .{ .float = std.math.inf(f64) }));
    try std.testing.expectError(error.NonfiniteJSONNumber, durable.jsValue(engine, .{ .float = std.math.nan(f64) }));
}
test "native durable JSON DTO ordinary construction uses no temporary host heap allocation" {
    var host = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(host.allocator(), .{});
    defer engine.deinit();
    var owned = try json.Owned.parse(std.testing.allocator, "{\"task\":17,\"input\":{\"text\":\"ordinary DTO\",\"values\":[true,null,1,0.1]},\"__proto__\":{\"own\":true}}");
    defer owned.deinit();
    host.fail_index = host.alloc_index;
    host.resize_fail_index = host.resize_index;
    defer {
        host.fail_index = std.math.maxInt(usize);
        host.resize_fail_index = std.math.maxInt(usize);
    }
    const actual = try durable.jsValue(engine, owned.value);
    engine.freeValue(actual);
    try std.testing.expect(!host.has_induced_failure);
}
