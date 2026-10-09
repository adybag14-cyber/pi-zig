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
    try std.testing.expectEqual(@as(i32, @intCast(try json.asInteger(source.value.object.get("nested").?.object.get("arity").?))), arity_value);
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
test "native durable v2 awaited continuations preserve intrinsic Promise and raw thrown identity" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const inputs = try engine.eval("globalThis.original={identity:7};({value:{then(resolve){resolve(21)}},fulfilled:value=>value*2,rejected:error=>error,throwing:()=>{throw original},check:error=>error===original})", "await-inputs", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(inputs);
    const patched = try engine.eval("Promise.resolve=()=>{throw Error('mutable global resolve')};Promise.prototype.then=()=>{throw Error('mutable prototype then')}", "await-overrides", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(patched);
    const value = try vm.get(engine, inputs, "value");
    defer engine.freeValue(value);
    const fulfilled = try vm.get(engine, inputs, "fulfilled");
    defer engine.freeValue(fulfilled);
    const rejected = try vm.get(engine, inputs, "rejected");
    defer engine.freeValue(rejected);
    const pending = try intrinsics.chain(engine, value, fulfilled, rejected);
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    var number: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &number, result));
    try std.testing.expectEqual(@as(i32, 42), number);
    const throwing = try vm.get(engine, inputs, "throwing");
    defer engine.freeValue(throwing);
    const failed = try intrinsics.chain(engine, c.pi_js_undefined(), throwing, rejected);
    defer engine.freeValue(failed);
    const identity_check = try vm.get(engine, inputs, "check");
    defer engine.freeValue(identity_check);
    const caught = try intrinsics.chain(engine, failed, fulfilled, identity_check);
    defer engine.freeValue(caught);
    const same = try engine.awaitValue(caught);
    defer engine.freeValue(same);
    try std.testing.expect(c.JS_ToBool(engine.context, same) != 0);
}
test "native durable v2 explicit nested keys match actual Source calls and preserve raw includes failures" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-nested-keys-original.json"));
    defer source.deinit();
    const calls = @import("extensions/native_durable_tool_call.zig");
    for (source.value.object.get("rows").?.array.items) |row| {
        const key = try engine.fromJsonValue(row.object.get("key").?);
        defer engine.freeValue(key);
        if (row.object.get("error")) |expected| {
            try std.testing.expectError(error.JavaScriptException, calls.checkKey(engine, key));
            const failure = engine.captured_exception.?;
            const name_value = try vm.get(engine, failure, "name");
            defer engine.freeValue(name_value);
            const name = try engine.toString(name_value);
            defer std.testing.allocator.free(name);
            try std.testing.expectEqualStrings(expected.object.get("name").?.string, name);
            if (row.object.get("key").? == .string) {
                const message_value = try vm.get(engine, failure, "message");
                defer engine.freeValue(message_value);
                const message = try engine.toString(message_value);
                defer std.testing.allocator.free(message);
                try std.testing.expectEqualStrings(expected.object.get("message").?.string, message);
            }
        } else try calls.checkKey(engine, key);
    }
    const key = try engine.eval("globalThis.originalKeyError={raw:true};({includes(){throw originalKeyError}})", "key-raw-error", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(key);
    try std.testing.expectError(error.JavaScriptException, calls.checkKey(engine, key));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const original = try vm.get(engine, global, "originalKeyError");
    defer engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
}
test "native durable v2 calls retain original entry tool and nested parent identities" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const calls = @import("extensions/native_durable_tool_call.zig");
    const state = try engine.eval("globalThis.entryType={entry:true};globalThis.ctx={context:true};globalThis.wanted={type:'toolCall',id:'wanted',name:'target',arguments:{value:7}};({runtime:{async entry(type,id,context){if(type!==entryType||context!==ctx||id!==42)throw Error('entry identity');return{model:[{role:'assistant',content:[{type:'text',text:'skip'},wanted]}]}}},input:{kind:'model',assistant:42,callId:'wanted'},context:ctx,token:entryType,call:wanted,agent:{tools:[{name:'model'}],callable:[{name:'target'}]}})", "call-admission", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(state);
    const runtime = try vm.get(engine, state, "runtime");
    defer engine.freeValue(runtime);
    const input = try vm.get(engine, state, "input");
    defer engine.freeValue(input);
    const context = try vm.get(engine, state, "context");
    defer engine.freeValue(context);
    const token = try vm.get(engine, state, "token");
    defer engine.freeValue(token);
    const original = try vm.get(engine, state, "call");
    defer engine.freeValue(original);
    const pending = try calls.readCall(engine, runtime, input, context, token, &intrinsics);
    defer engine.freeValue(pending);
    const call = try engine.awaitValue(pending);
    defer engine.freeValue(call);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, call));
    const nested_input = try engine.eval("({kind:'nested',parent:9,parentCallId:'parent-call',call:wanted})", "nested-admission", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(nested_input);
    const nested_pending = try calls.readCall(engine, c.pi_js_undefined(), nested_input, context, token, &intrinsics);
    defer engine.freeValue(nested_pending);
    const nested = try engine.awaitValue(nested_pending);
    defer engine.freeValue(nested);
    const parent = try vm.get(engine, nested, "parent");
    defer engine.freeValue(parent);
    const parent_json = try engine.stringify(parent);
    defer std.testing.allocator.free(parent_json);
    try std.testing.expectEqualStrings("{\"taskId\":9,\"callId\":\"parent-call\"}", parent_json);
    const arguments = try vm.get(engine, original, "arguments");
    defer engine.freeValue(arguments);
    const nested_arguments = try vm.get(engine, nested, "arguments");
    defer engine.freeValue(nested_arguments);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, arguments, nested_arguments));
    const agent = try vm.get(engine, state, "agent");
    defer engine.freeValue(agent);
    const name = try engine.checked(c.JS_NewString(engine.context, "target"));
    defer engine.freeValue(name);
    const model_tool = try calls.resolveTool(engine, agent, false, name);
    defer engine.freeValue(model_tool);
    try std.testing.expect(c.JS_IsUndefined(model_tool));
    const nested_tool = try calls.resolveTool(engine, agent, true, name);
    defer engine.freeValue(nested_tool);
    const callable = try vm.get(engine, agent, "callable");
    defer engine.freeValue(callable);
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, callable, 0));
    defer engine.freeValue(first);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, nested_tool, first));
}
fn testErrorMessage(engine: *engine_mod.Engine, failure: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const string = try vm.get(engine, global, "String");
    defer engine.freeValue(string);
    var args = [_]c.JSValue{failure};
    return engine.checked(c.JS_Call(engine.context, string, c.pi_js_undefined(), args.len, &args));
}
test "native durable v2 preparation preserves Source getter try boundaries and validation clones arguments" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const calls = @import("extensions/native_durable_tool_call.zig");
    const source = try engine.eval("globalThis.reads=0;globalThis.firstFailure={first:true};globalThis.args={count:'2'};({tool:{get prepareArguments(){reads++;if(reads===1)return()=>{throw Error('wrong first callback')};return function(value){if(this!==sourceTool)throw Error('receiver');return value}},parameters:{type:'object',properties:{count:{type:'number'}},required:['count']},name:'target'},call:{type:'toolCall',id:'c1',name:'target'},args})", "prepare-getters", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(source);
    const tool = try vm.get(engine, source, "tool");
    defer engine.freeValue(tool);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "sourceTool", c.JS_DupValue(engine.context, tool)) < 0) return error.JavaScriptException;
    const args = try vm.get(engine, source, "args");
    defer engine.freeValue(args);
    const prepared = try calls.prepare(engine, tool, args, testErrorMessage);
    defer prepared.deinit(engine);
    try std.testing.expect(prepared == .arguments and c.JS_IsStrictEqual(engine.context, prepared.arguments, args));
    const call = try vm.get(engine, source, "call");
    defer engine.freeValue(call);
    const validated = try calls.validate(engine, tool, call, prepared.arguments, testErrorMessage);
    defer validated.deinit(engine);
    try std.testing.expect(validated == .arguments);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, validated.arguments, args));
    const encoded = try engine.stringify(validated.arguments);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"count\":2}", encoded);
    const original = try engine.stringify(args);
    defer std.testing.allocator.free(original);
    try std.testing.expectEqualStrings("{\"count\":\"2\"}", original);
    const first_throws = try engine.eval("({get prepareArguments(){throw firstFailure}})", "prepare-first-getter", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(first_throws);
    try std.testing.expectError(error.JavaScriptException, calls.prepare(engine, first_throws, args, testErrorMessage));
    const first_failure = try vm.get(engine, global, "firstFailure");
    defer engine.freeValue(first_failure);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first_failure, engine.captured_exception.?));
    const second_throws = try engine.eval("globalThis.secondReads=0;({get prepareArguments(){if(++secondReads===1)return()=>{};throw 'second-getter'}})", "prepare-second-getter", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(second_throws);
    const checked = try calls.prepare(engine, second_throws, args, testErrorMessage);
    defer checked.deinit(engine);
    try std.testing.expect(checked == .failure);
    const failure = try engine.toString(checked.failure);
    defer std.testing.allocator.free(failure);
    try std.testing.expectEqualStrings("second-getter", failure);
}
