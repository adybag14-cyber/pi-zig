const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const output = @import("extensions/native_durable_tool_output.zig");
const input_validators = @import("extensions/native_tool_validator_cache.zig");
const vm = @import("extensions/native_values.zig");
const json = @import("durable/backend/json.zig");
const c = engine_mod.c;

fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    var source = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/durable-eba-structured-output-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const tool = try vm.object(engine);
        defer engine.freeValue(tool);
        try vm.put(engine, tool, "name", try engine.checked(c.JS_NewString(engine.context, "target")));
        if (row.object.get("hasSchema").?.bool) {
            const schema = try engine.eval("({type:'object',properties:{count:{type:'number'}},required:['count']})", "structured-schema", c.JS_EVAL_TYPE_GLOBAL);
            try vm.put(engine, tool, "structuredOutputSchema", schema);
        }
        const result = try engine.fromJsonValue(row.object.get("input").?);
        defer engine.freeValue(result);
        const failure = try cache.failure(tool, result);
        defer if (failure) |message| gpa.free(message);
        var expected: ?[]const u8 = null;
        if (row.object.get("nested").?.bool) {
            if (row.object.get("result").?.object.get("diagnostics")) |diagnostics| for (diagnostics.array.items) |diagnostic| {
                const code = diagnostic.object.get("code") orelse continue;
                if (std.mem.eql(u8, code.string, "invalid_structured_output")) expected = diagnostic.object.get("message").?.string;
            };
        } else if (row.object.get("reports").?.array.items.len != 0) expected = row.object.get("reports").?.array.items[0].string;
        if (expected) |message| try std.testing.expectEqualStrings(message, failure orelse return error.MissingStructuredOutputError) else try std.testing.expect(failure == null);
        if (row.object.get("nested").?.bool and !row.object.get("hasSchema").?.bool) {
            const contents = try vm.get(engine, result, "output");
            defer engine.freeValue(contents);
            const actual = try output.outputValue(engine, contents);
            defer engine.freeValue(actual);
            const encoded = try engine.stringify(actual);
            defer gpa.free(encoded);
            const expected_json = try json.stringify(gpa, row.object.get("result").?.object.get("structuredOutput").?);
            defer gpa.free(expected_json);
            try std.testing.expectEqualStrings(expected_json, encoded);
            const length = try vm.length(engine, contents);
            if (length > 1) try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, contents));
            if (std.mem.eql(u8, row.object.get("name").?.string, "one-image")) {
                const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, contents, 0));
                defer engine.freeValue(first);
                try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, actual));
            }
        }
        if (row.object.get("nested").?.bool) {
            const final = try engine.fromJsonValue(row.object.get("result").?);
            defer engine.freeValue(final);
            const projected = try output.nestedResult(engine, c.JS_NewInt64(engine.context, 7), final, c.pi_js_undefined());
            defer engine.freeValue(projected);
            var expected_result: std.json.Value = .{ .object = .empty };
            const a = source.arena.allocator();
            try expected_result.object.put(a, "taskId", .{ .integer = 7 });
            var fields = row.object.get("result").?.object.iterator();
            while (fields.next()) |field| try expected_result.object.put(a, field.key_ptr.*, field.value_ptr.*);
            const expected_json = try json.stringify(gpa, expected_result);
            defer gpa.free(expected_json);
            const actual_json = try engine.stringify(projected);
            defer gpa.free(actual_json);
            try std.testing.expectEqualStrings(expected_json, actual_json);
        }
    }
}

test "native durable v2 output matches 22 actual Source Harness model and nested result cases" {
    try exercise(std.testing.allocator);
}
test "native durable v2 output caches and error construction release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercise, .{});
}
test "native durable v2 output cache is independent of argument compilation and uses strict content tags" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    const schema = try engine.eval("globalThis.schema={type:'object',properties:{count:{type:'number'}},required:['count']}", "schema-before", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(schema);
    const original = try input_validators.get(engine, schema);
    defer engine.freeValue(original);
    const changed = try engine.eval("schema.properties.count.type='string';({count:'changed'})", "schema-after", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(changed);
    try std.testing.expect(!try input_validators.check(engine, original, changed));
    const separate = try cache.get(schema);
    defer engine.freeValue(separate);
    try std.testing.expect(try input_validators.check(engine, separate, changed));
    const unusual = try engine.eval("globalThis.item={type:{toString(){throw Error('must not coerce tag')}}};[item]", "strict-content-tag", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(unusual);
    const projected = try output.outputValue(engine, unusual);
    defer engine.freeValue(projected);
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, unusual, 0));
    defer engine.freeValue(first);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, projected, first));
}
test "native durable v2 nested result definition and live checkpoints match actual Source documents" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_durable_builtin_documents.zig").install(engine, exports);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-documents-original.json"));
    defer source.deinit();
    const token = try vm.get(engine, exports, "NestedResultDoc");
    defer engine.freeValue(token);
    const definition = try vm.get(engine, token, "definition");
    defer engine.freeValue(definition);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try vm.get(engine, global, "Object");
    defer engine.freeValue(object);
    inline for (.{ .{ "tokenKeys", false }, .{ "definitionKeys", true } }) |item| {
        const keys = try vm.invoke(engine, object, "keys", &.{if (item[1]) definition else token});
        defer engine.freeValue(keys);
        const actual = try engine.stringify(keys);
        defer std.testing.allocator.free(actual);
        const expected = try json.stringify(std.testing.allocator, source.value.object.get("nested").?.object.get(item[0]).?);
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualStrings(expected, actual);
    }
    const initial = try vm.get(engine, definition, "initial");
    defer engine.freeValue(initial);
    const arity = try vm.get(engine, initial, "length");
    defer engine.freeValue(arity);
    var arity_value: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &arity_value, arity));
    try std.testing.expectEqual(@as(i32, @intCast(source.value.object.get("nested").?.object.get("arity").?.integer)), arity_value);
    inline for (.{ "kind", "version", "scope", "family" }) |name| {
        const actual = try vm.get(engine, definition, name);
        defer engine.freeValue(actual);
        const encoded = try engine.stringify(actual);
        defer std.testing.allocator.free(encoded);
        const expected = try json.stringify(std.testing.allocator, source.value.object.get("nested").?.object.get("definition").?.object.get(name).?);
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualStrings(expected, encoded);
    }
    const seed = try engine.eval("({result:{taskId:7,structuredOutput:{count:2},isError:false,diagnostics:[]}})", "nested-result-seed", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(seed);
    const initialized = try vm.invoke(engine, definition, "initial", &.{seed});
    defer engine.freeValue(initialized);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, seed, initialized));
    const empty = try vm.invoke(engine, definition, "initial", &.{});
    defer engine.freeValue(empty);
    try std.testing.expect(c.JS_IsUndefined(empty));
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const live_definition = try vm.get(engine, live, "definition");
    defer engine.freeValue(live_definition);
    for (source.value.object.get("live").?.array.items) |row| {
        const value = if (row.object.get("sparse").?.bool) try engine.eval("({tools:[,{status:'done'}],nestedTools:[,{status:'done'}]})", "sparse-live", c.JS_EVAL_TYPE_GLOBAL) else try engine.fromJsonValue(row.object.get("value").?);
        defer engine.freeValue(value);
        const actual = try vm.invoke(engine, live_definition, "checkpointWhen", &.{value});
        defer engine.freeValue(actual);
        try std.testing.expectEqual(row.object.get("result").?.bool, c.JS_ToBool(engine.context, actual) != 0);
    }
}
