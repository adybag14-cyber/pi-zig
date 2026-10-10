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
test "native durable v2 live slots match Source identity cleanup and logarithmic draft reads" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try output.Cache.init(engine);
    defer intrinsics.deinit();
    const slots = @import("extensions/native_durable_tool_slots.zig");
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-live-slots-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const kind = row.object.get("kind").?.string;
        if (std.mem.eql(u8, kind, "binary")) continue;
        const original = if (row.object.get("before")) |value| value else row.object.get("live").?;
        const value = try engine.fromJsonValue(original);
        defer engine.freeValue(value);
        if (std.mem.eql(u8, kind, "find")) {
            const id = try engine.fromJsonValue(row.object.get("taskId").?);
            defer engine.freeValue(id);
            const found = try slots.find(engine, value, id);
            defer engine.freeValue(found);
            if (row.object.get("found").? == .null) {
                try std.testing.expect(c.JS_IsUndefined(found));
                continue;
            }
            const actual = try engine.stringify(found);
            defer std.testing.allocator.free(actual);
            const expected = try json.stringify(std.testing.allocator, row.object.get("found").?);
            defer std.testing.allocator.free(expected);
            try std.testing.expectEqualStrings(expected, actual);
            const second = try slots.find(engine, value, id);
            defer engine.freeValue(second);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, found, second));
        } else {
            if (std.mem.eql(u8, kind, "finish")) try slots.finish(engine, value) else {
                const array = try vm.get(engine, value, "nestedTools");
                defer engine.freeValue(array);
                const id = try engine.fromJsonValue(row.object.get("taskId").?);
                defer engine.freeValue(id);
                try slots.removeBelow(engine, value, id, intrinsics.iterator_symbol);
                const after = try vm.get(engine, value, "nestedTools");
                defer engine.freeValue(after);
                try std.testing.expect(c.JS_IsUndefined(after) or c.JS_IsStrictEqual(engine.context, array, after));
            }
            const actual = try engine.stringify(value);
            defer std.testing.allocator.free(actual);
            const expected = try json.stringify(std.testing.allocator, row.object.get("after").?);
            defer std.testing.allocator.free(expected);
            try std.testing.expectEqualStrings(expected, actual);
        }
    }
    const large = try engine.eval("globalThis.slotReads=0;globalThis.nested=Array.from({length:1024},(_,i)=>({get taskId(){slotReads++;return i+10},parentTaskId:1}));({nestedTools:nested})", "binary-slot-reads", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(large);
    const found = try slots.find(engine, large, c.JS_NewInt32(engine.context, 777));
    defer engine.freeValue(found);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const reads = try vm.get(engine, global, "slotReads");
    defer engine.freeValue(reads);
    var count: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &count, reads));
    const binary = source.value.object.get("rows").?.array.items[source.value.object.get("rows").?.array.items.len - 1];
    try std.testing.expectEqual(@as(i32, @intCast(try json.asInteger(binary.object.get("reads").?))), count);
}
test "native durable v2 terminal transactions match actual Source model and nested ToolTask traces" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_durable_builtin_documents.zig").install(engine, exports);
    try @import("extensions/native_durable_entries.zig").install(engine, exports);
    const calls_token = try engine.eval("({definition:{kind:'pi.tool.nested',version:1,scope:'task',initial:()=>({calls:{}})}})", "nested-calls-token", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(calls_token);
    const live_token = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live_token);
    const result_token = try vm.get(engine, exports, "NestedResultDoc");
    defer engine.freeValue(result_token);
    const tool_result = try vm.get(engine, exports, "ToolResultEntry");
    defer engine.freeValue(tool_result);
    const assistant = try vm.get(engine, exports, "AssistantEntry");
    defer engine.freeValue(assistant);
    const usage_token = try vm.get(engine, exports, "UsageDoc");
    defer engine.freeValue(usage_token);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-eba-settle-runtime.txt"), "actual-source-runtime-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-settle-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        var args = [_]c.JSValue{c.pi_js_bool(engine.context, @intFromBool(row.object.get("nested").?.bool))};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        const runtime = try vm.get(engine, fixture, "runtime");
        defer engine.freeValue(runtime);
        const input = try vm.get(engine, fixture, "input");
        defer engine.freeValue(input);
        const context = try vm.get(engine, fixture, "context");
        defer engine.freeValue(context);
        const call_pending = try @import("extensions/native_durable_tool_call.zig").readCall(engine, runtime, input, context, assistant, &intrinsics);
        defer engine.freeValue(call_pending);
        const call = try engine.awaitValue(call_pending);
        defer engine.freeValue(call);
        const agent_pending = try vm.invoke(engine, runtime, "agent", &.{context});
        defer engine.freeValue(agent_pending);
        const agent = try engine.awaitValue(agent_pending);
        defer engine.freeValue(agent);
        const name = try vm.get(engine, call, "name");
        defer engine.freeValue(name);
        const tool = try @import("extensions/native_durable_tool_call.zig").resolveTool(engine, agent, row.object.get("nested").?.bool, name);
        defer engine.freeValue(tool);
        try std.testing.expect(c.JS_IsUndefined(tool));
        const result = try vm.get(engine, fixture, "result");
        defer engine.freeValue(result);
        const pending = try @import("extensions/native_durable_tool_settle.zig").run(engine, &intrinsics, .{ .live = live_token, .nested_calls = calls_token, .nested_results = result_token, .tool_result = tool_result, .usage = usage_token, .iterator_symbol = cache.iterator_symbol }, runtime, input, call, .completed, .{ .final = result }, context, c.pi_js_undefined(), c.pi_js_undefined());
        defer engine.freeValue(pending);
        const done = try engine.awaitValue(pending);
        defer engine.freeValue(done);
        try std.testing.expect(c.JS_IsUndefined(done));
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const actual = try engine.stringify(inspected);
        defer std.testing.allocator.free(actual);
        var expected = row;
        _ = expected.object.swapRemove("nested");
        const wanted = try json.stringify(std.testing.allocator, expected);
        defer std.testing.allocator.free(wanted);
        var actual_value = try json.Owned.parse(std.testing.allocator, actual);
        defer actual_value.deinit();
        var expected_value = try json.Owned.parse(std.testing.allocator, wanted);
        defer expected_value.deinit();
        try std.testing.expect(json.equal(expected_value.value, actual_value.value));
    }
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

test "native durable v2 preflight cancellation and unsafe recovery match actual Source terminal handlers" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_durable_builtin_documents.zig").install(engine, exports);
    try @import("extensions/native_durable_entries.zig").install(engine, exports);
    const calls_token = try engine.eval("({definition:{kind:'pi.tool.nested',version:1,scope:'task',initial:()=>({calls:{}})}})", "nested-calls-token", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(calls_token);
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const nested_results = try vm.get(engine, exports, "NestedResultDoc");
    defer engine.freeValue(nested_results);
    const tool_result = try vm.get(engine, exports, "ToolResultEntry");
    defer engine.freeValue(tool_result);
    const assistant = try vm.get(engine, exports, "AssistantEntry");
    defer engine.freeValue(assistant);
    const usage = try vm.get(engine, exports, "UsageDoc");
    defer engine.freeValue(usage);
    const tokens: @import("extensions/native_durable_tool_task.zig").Tokens = .{ .assistant = assistant, .terminal = .{ .live = live, .nested_calls = calls_token, .nested_results = nested_results, .tool_result = tool_result, .usage = usage, .iterator_symbol = cache.iterator_symbol } };
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-eba-settle-runtime.txt"), "actual-source-runtime-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const prepare = try engine.eval("(fixture,nested,mode,partial)=>{const slot=(nested?fixture.inspect().live.nestedTools:fixture.inspect().live.tools).find(slot=>slot.taskId===7);if(partial)Object.assign(slot,{output:'partial λ\\n',details:{retained:true},droppedBytes:24,droppedLines:2,diagnostics:[{severity:'info',code:'earlier',message:'Before interruption'}]});if(mode==='safe-recovery'){const original=fixture.runtime.agent;fixture.runtime.agent=async(ctx)=>{await original(ctx);return{tools:[{name:'absent',replay:'safe'}],callable:[{name:'absent',replay:'safe'}]}}}return{input:fixture.input,state:{checkpoint:{phase:mode==='restart-call'?'call':'execute',arguments:mode==='safe-recovery'?{count:2}:{},replay:mode==='safe-recovery'?'safe':'unsafe'}},abortReason:mode.startsWith('restart')?'restart':'explicit'}}", "source-recovery-test-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prepare);
    const prepare_preflight = try engine.eval(@embedFile("extensions/fixtures/durable-eba-preflight-runtime.txt"), "actual-source-preflight-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prepare_preflight);
    for ([_][]const u8{ @embedFile("extensions/fixtures/durable-eba-recovery-original.json"), @embedFile("extensions/fixtures/durable-eba-preflight-original.json"), @embedFile("extensions/fixtures/durable-eba-intent-original.json"), @embedFile("extensions/fixtures/durable-eba-safe-replay-original.json") }) |corpus| {
        var source = try json.Owned.parse(std.testing.allocator, corpus);
        defer source.deinit();
        for (source.value.object.get("rows").?.array.items) |row| {
            const nested = row.object.get("nested").?.bool;
            const is_preflight = row.object.contains("variant");
            const is_intent = is_preflight and std.mem.startsWith(u8, row.object.get("variant").?.string, "intent-");
            const mode = if (is_preflight) "preflight" else row.object.get("mode").?.string;
            var make_args = [_]c.JSValue{c.pi_js_bool(engine.context, @intFromBool(nested))};
            const fixture = fixture: {
                if (!is_preflight) break :fixture try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), make_args.len, &make_args));
                const variant = row.object.get("variant").?.string;
                const variant_value = try engine.checked(c.JS_NewStringLen(engine.context, variant.ptr, variant.len));
                defer engine.freeValue(variant_value);
                var args = [_]c.JSValue{ make, make_args[0], variant_value };
                break :fixture try engine.checked(c.JS_Call(engine.context, prepare_preflight, c.pi_js_undefined(), args.len, &args));
            };
            defer engine.freeValue(fixture);
            const mode_value = try engine.checked(c.JS_NewStringLen(engine.context, mode.ptr, mode.len));
            defer engine.freeValue(mode_value);
            var prepare_args = [_]c.JSValue{ fixture, make_args[0], mode_value, c.pi_js_bool(engine.context, @intFromBool(if (row.object.get("partial")) |partial| partial.bool else false)) };
            const task = try engine.checked(c.JS_Call(engine.context, prepare, c.pi_js_undefined(), prepare_args.len, &prepare_args));
            defer engine.freeValue(task);
            const runtime = try vm.get(engine, fixture, "runtime");
            defer engine.freeValue(runtime);
            const context = try vm.get(engine, fixture, "context");
            defer engine.freeValue(context);
            const handlers = @import("extensions/native_durable_tool_task.zig");
            const pending = if (is_preflight) try handlers.prepareCall(engine, &intrinsics, tokens, task, runtime, context) else if (std.mem.endsWith(u8, mode, "recovery")) try handlers.prepareRecovery(engine, &intrinsics, tokens, task, runtime, context) else try handlers.abort(engine, &intrinsics, tokens, task, runtime, context);
            defer engine.freeValue(pending);
            const done = try engine.awaitValue(pending);
            defer engine.freeValue(done);
            if (is_intent) {
                try std.testing.expect(c.JS_IsObject(done));
                const intent_pending = try @import("extensions/native_durable_tool_intent.zig").commit(engine, &intrinsics, live, task, runtime, done, context, false);
                defer engine.freeValue(intent_pending);
                const committed = try engine.awaitValue(intent_pending);
                engine.freeValue(committed);
            } else if (std.mem.eql(u8, mode, "safe-recovery")) {
                const args = try vm.get(engine, done, "arguments");
                defer engine.freeValue(args);
                const encoded = try engine.stringify(args);
                defer std.testing.allocator.free(encoded);
                try std.testing.expectEqualStrings("{\"count\":2}", encoded);
            } else try std.testing.expect(c.JS_IsUndefined(done));
            const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
            defer engine.freeValue(inspected);
            const text = try engine.stringify(inspected);
            defer std.testing.allocator.free(text);
            var actual = try json.Owned.parse(std.testing.allocator, text);
            defer actual.deinit();
            var expected = row;
            _ = expected.object.swapRemove("nested");
            _ = expected.object.swapRemove("mode");
            _ = expected.object.swapRemove("partial");
            _ = expected.object.swapRemove("variant");
            try std.testing.expect(json.equal(expected, actual.value));
        }
    }
}

test "native durable v2 content bounding matches 160 actual Source Unicode retention cases" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-bound-content-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const content = try engine.fromJsonValue(row.object.get("content").?);
        defer engine.freeValue(content);
        const limits = row.object.get("limits").?;
        var bounded = try @import("extensions/native_durable_tool_bound.zig").content(engine, content, .{ .maxBytes = @floatFromInt(try json.asInteger(limits.object.get("maxBytes").?)), .maxLines = @floatFromInt(try json.asInteger(limits.object.get("maxLines").?)), .retain = if (std.mem.eql(u8, limits.object.get("retain").?.string, "head")) .head else .tail }, cache.iterator_symbol);
        defer bounded.deinit(engine);
        const expected = row.object.get("result").?;
        try std.testing.expectEqual(@as(usize, @intCast(try json.asInteger(expected.object.get("droppedBytes").?))), bounded.dropped_bytes);
        try std.testing.expectEqual(@as(u64, @intCast(try json.asInteger(expected.object.get("droppedLines").?))), bounded.dropped_lines);
        try std.testing.expectEqual(row.object.get("same").?.bool, c.JS_IsStrictEqual(engine.context, content, bounded.content));
        const image = try engine.checked(c.JS_GetPropertyUint32(engine.context, content, 1));
        defer engine.freeValue(image);
        const contains = try vm.invoke(engine, bounded.content, "includes", &.{image});
        defer engine.freeValue(contains);
        try std.testing.expectEqual(row.object.get("imageSame").?.bool, c.JS_ToBool(engine.context, contains) != 0);
        const text = try engine.stringify(bounded.content);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(expected.object.get("content").?, actual.value));
    }
}

fn exerciseFinal(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    return exerciseFinalWithEngine(gpa, engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseFinalWithEngine(gpa: std.mem.Allocator, engine: *engine_mod.Engine) !void {
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-eba-final-runtime.txt"), "actual-source-final-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/durable-eba-final-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const variant = row.object.get("variant").?.string;
        const variant_value = try engine.checked(c.JS_NewStringLen(engine.context, variant.ptr, variant.len));
        defer engine.freeValue(variant_value);
        var args = [_]c.JSValue{ c.pi_js_bool(engine.context, @intFromBool(row.object.get("nested").?.bool)), variant_value };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 8;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "input", "call", "tool", "result", "reported", "context", "snapshot" }, 0..) |field, index| values[index] = try vm.get(engine, fixture, field);
        const diagnostics = try vm.get(engine, values[5], "diagnostics");
        defer engine.freeValue(diagnostics);
        const details = try vm.get(engine, values[5], "details");
        defer engine.freeValue(details);
        // The Source fixture records its private OutputBuffer.snapshot call.
        // The native driver computes the same snapshot using its native buffer.
        if (std.mem.eql(u8, variant, "retained") or std.mem.eql(u8, variant, "replace-retained")) {
            const buffer = try vm.get(engine, values[5], "output");
            defer engine.freeValue(buffer);
            const snapshot = try vm.invoke(engine, buffer, "snapshot", &.{});
            engine.freeValue(snapshot);
        }
        const pending = try @import("extensions/native_durable_tool_final.zig").run(engine, &intrinsics, &cache, values[0], values[1], values[2], values[3], values[4], .{ .snapshot = values[7], .details = details, .diagnostics = diagnostics, .limits = .{ .maxBytes = 8, .maxLines = 2, .retain = if (std.mem.eql(u8, variant, "tail")) .tail else .head } }, values[6]);
        defer engine.freeValue(pending);
        const result = engine.awaitValue(pending) catch |err| {
            std.debug.print("Final projection {s}: {s}\n", .{ variant, engine.last_error orelse "no diagnostic" });
            return err;
        };
        defer engine.freeValue(result);
        const actual_json = try engine.stringify(result);
        defer gpa.free(actual_json);
        var actual = try json.Owned.parse(gpa, actual_json);
        defer actual.deinit();
        try std.testing.expect(json.equal(row.object.get("result").?, actual.value));
        inline for (.{ "reports", "trace" }) |field| {
            const value = try vm.get(engine, fixture, field);
            defer engine.freeValue(value);
            const text = try engine.stringify(value);
            defer gpa.free(text);
            var parsed = try json.Owned.parse(gpa, text);
            defer parsed.deinit();
            try std.testing.expect(json.equal(row.object.get(field).?, parsed.value));
        }
    }
}

test "native durable v2 final projection matches actual Source hooks bounding and structured output" {
    try exerciseFinal(std.testing.allocator);
}
test "native durable v2 final projection releases continuations and results at every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseFinal, .{});
}

test "native durable v2 progress matches actual Source coalescing throttling failure and stop traces" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const Factory = struct {
        fn create(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = engine_mod.Engine.fromContext(context.?);
            var intrinsics = @import("extensions/native_durable_await.zig").Intrinsics.init(owner) catch |err| return @import("extensions/native_durable.zig").reject(owner, err);
            defer intrinsics.deinit(owner);
            if (argc < 3) return c.JS_ThrowTypeError(context, "Progress fixture requires three arguments");
            return @import("extensions/native_durable_progress.zig").create(owner, &intrinsics, argv[0], argv[1], argv[2]) catch |err| @import("extensions/native_durable.zig").reject(owner, err);
        }
    };
    const factory = try engine.checked(c.JS_NewCFunction(engine.context, Factory.create, "nativeProgress", 3));
    defer engine.freeValue(factory);
    const exercise_progress = try engine.eval(@embedFile("extensions/fixtures/durable-eba-progress-runtime.txt"), "actual-source-progress-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(exercise_progress);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-progress-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const scenario_value = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(scenario_value);
        var args = [_]c.JSValue{ factory, scenario_value };
        const pending = try engine.checked(c.JS_Call(engine.context, exercise_progress, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(pending);
        const result = engine.awaitValue(pending) catch |err| {
            std.debug.print("Progress {s}: {s}\n", .{ scenario, engine.last_error orelse "no diagnostic" });
            return err;
        };
        defer engine.freeValue(result);
        const text = try engine.stringify(result);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        var expected = row;
        _ = expected.object.swapRemove("scenario");
        if (!json.equal(expected, actual.value)) std.debug.print("Progress {s} actual: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

fn exerciseBuffer(gpa: std.mem.Allocator, allocation_case: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    return exerciseBufferWithEngine(gpa, engine, allocation_case) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseBufferWithEngine(gpa: std.mem.Allocator, engine: *engine_mod.Engine, allocation_case: bool) !void {
    try @import("extensions/text_decoder.zig").install(engine);
    const pattern = try engine.eval("(/[\\x00-\\x08\\x0b-\\x1f\\ufff9-\\ufffb]/g)", "source-output-sanitizer", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pattern);
    const Factory = struct {
        fn create(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = engine_mod.Engine.fromContext(context.?);
            return createOwned(owner, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| @import("extensions/native_durable.zig").reject(owner, err);
        }
        fn createOwned(owner: *engine_mod.Engine, limits: c.JSValue, sanitizer: c.JSValue) !c.JSValue {
            const max_bytes = try vm.get(owner, limits, "maxBytes");
            defer owner.freeValue(max_bytes);
            const max_lines = try vm.get(owner, limits, "maxLines");
            defer owner.freeValue(max_lines);
            const retain = try vm.get(owner, limits, "retain");
            defer owner.freeValue(retain);
            var bytes: f64 = 0;
            var lines: f64 = 0;
            if (c.JS_ToFloat64(owner.context, &bytes, max_bytes) < 0 or c.JS_ToFloat64(owner.context, &lines, max_lines) < 0) return error.JavaScriptException;
            return @import("extensions/native_durable_output_buffer.zig").create(owner, .{ .maxBytes = bytes, .maxLines = lines, .retain = if (try @import("extensions/native_durable_tool_call.zig").equalsString(owner, retain, "tail")) .tail else .head }, sanitizer);
        }
    };
    var captures = [_]c.JSValue{pattern};
    const factory = try engine.checked(c.JS_NewCFunctionData2(engine.context, Factory.create, "nativeOutputBuffer", 1, 0, captures.len, &captures));
    defer engine.freeValue(factory);
    const exercise_buffer = try engine.eval(@embedFile("extensions/fixtures/durable-eba-buffer-runtime.txt"), "actual-source-buffer-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(exercise_buffer);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-buffer-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        if (allocation_case) {
            const limits = row.object.get("limits").?;
            if (try json.asInteger(limits.object.get("maxBytes").?) != 9 or try json.asInteger(limits.object.get("maxLines").?) != 3) continue;
        }
        const limits = try engine.fromJsonValue(row.object.get("limits").?);
        defer engine.freeValue(limits);
        var args = [_]c.JSValue{ factory, limits };
        const generation = engine.native_allocation_generation;
        const result = try engine.checked(c.JS_Call(engine.context, exercise_buffer, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(result);
        // The fixture catches ordinary Source push errors, including a head
        // skip. An induced native allocator failure must still fail this run.
        if (engine.native_allocation_generation != generation) return error.OutOfMemory;
        const text = try engine.stringify(result);
        defer gpa.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        if (!json.equal(row.object.get("steps").?, actual.value)) std.debug.print("Running output actual: {s}\n", .{text});
        try std.testing.expect(json.equal(row.object.get("steps").?, actual.value));
    }
}

test "native durable v2 running output matches actual Source streaming decoding and UTF16 retention" {
    try exerciseBuffer(std.testing.allocator, false);
}
test "native durable v2 running output releases decoder chunks and closures on every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseBuffer, .{true});
}

test "native durable v2 progress publication matches actual Source draft mutations and failure bookkeeping" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_durable_builtin_documents.zig").install(engine, exports);
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const Factory = struct {
        fn create(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = engine_mod.Engine.fromContext(context.?);
            if (argc < 4) return c.JS_ThrowTypeError(context, "Progress publication fixture requires four arguments");
            var intrinsics = @import("extensions/native_durable_await.zig").Intrinsics.init(owner) catch |err| return @import("extensions/native_durable.zig").reject(owner, err);
            defer intrinsics.deinit(owner);
            return @import("extensions/native_durable_tool_progress.zig").create(owner, &intrinsics, argv[0], argv[1], c.JS_ToBool(owner.context, argv[2]) != 0, argv[3], data[0], data[1]) catch |err| @import("extensions/native_durable.zig").reject(owner, err);
        }
    };
    var captures = [_]c.JSValue{ live, cache.iterator_symbol };
    const factory = try engine.checked(c.JS_NewCFunctionData2(engine.context, Factory.create, "nativePublishProgress", 4, 0, captures.len, &captures));
    defer engine.freeValue(factory);
    const exercise_publication = try engine.eval(@embedFile("extensions/fixtures/durable-eba-publication-runtime.txt"), "actual-source-publication-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(exercise_publication);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-publication-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const scenario_value = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(scenario_value);
        var args = [_]c.JSValue{ factory, scenario_value };
        const pending = try engine.checked(c.JS_Call(engine.context, exercise_publication, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(pending);
        const result = engine.awaitValue(pending) catch |err| {
            std.debug.print("Publication {s}: {s}\n", .{ scenario, engine.last_error orelse "no diagnostic" });
            return err;
        };
        defer engine.freeValue(result);
        const text = try engine.stringify(result);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        var expected = row;
        _ = expected.object.swapRemove("scenario");
        if (!json.equal(expected, actual.value)) std.debug.print("Publication {s} actual: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

fn exerciseExecution(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    return exerciseExecutionWithEngine(gpa, engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseExecutionWithEngine(gpa: std.mem.Allocator, engine: *engine_mod.Engine) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    const exports = try vm.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_durable_builtin_documents.zig").install(engine, exports);
    try @import("extensions/native_durable_entries.zig").install(engine, exports);
    const index_token = try engine.eval("({definition:{kind:'pi.tool.nested',version:1,scope:'task',initial:()=>({calls:{}})}})", "actual-index-definition", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(index_token);
    const pattern = try engine.eval("(/[\\x00-\\x08\\x0b-\\x1f\\ufff9-\\ufffb]/g)", "source-output-sanitizer", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pattern);
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    defer for (tokens) |token| engine.freeValue(token);
    inline for (.{ "LiveDoc", "NestedResultDoc", "ToolResultEntry", "UsageDoc" }, 0..) |name, index| tokens[index] = try vm.get(engine, exports, name);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-eba-settle-runtime.txt"), "actual-source-runtime-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const prepare_attempt = try engine.eval(@embedFile("extensions/fixtures/durable-eba-execute-runtime.txt"), "actual-source-attempt-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prepare_attempt);
    const prepare_phase = try engine.eval("(prepare,make,nested,variant)=>{const f=prepare(make,nested,variant),original=f.runtime.agent;f.tool.parameters={type:'object',properties:{count:{type:'number'}},required:['count']};f.call.arguments=f.arguments;f.runtime.agent=async(ctx)=>{await original(ctx);return{tools:[f.tool],callable:[f.tool]}};return f}", "actual-source-phase-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prepare_phase);
    const registered = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const tool_task = try vm.get(engine, registered, "ToolTask");
    defer engine.freeValue(tool_task);
    const definition = try vm.get(engine, tool_task, "definition");
    defer engine.freeValue(definition);
    const phases = try vm.get(engine, definition, "phases");
    defer engine.freeValue(phases);
    for ([_][]const u8{ @embedFile("extensions/fixtures/durable-eba-execute-original.json"), @embedFile("extensions/fixtures/durable-eba-tool-phase-original.json") }, 0..) |corpus, corpus_index| {
        var source = try json.Owned.parse(gpa, corpus);
        defer source.deinit();
        for (source.value.object.get("rows").?.array.items) |row| {
            const clock = try engine.eval("globalThis.attemptTick=0;globalThis.performance={now(){const value=attemptTick;attemptTick+=5;return value}}", "source-controlled-performance", c.JS_EVAL_TYPE_GLOBAL);
            engine.freeValue(clock);
            const variant = row.object.get("variant").?.string;
            const variant_value = try engine.checked(c.JS_NewStringLen(engine.context, variant.ptr, variant.len));
            defer engine.freeValue(variant_value);
            var args = [_]c.JSValue{ make, c.pi_js_bool(engine.context, @intFromBool(row.object.get("nested").?.bool)), variant_value };
            const fixture = fixture: {
                if (corpus_index == 0) break :fixture try engine.checked(c.JS_Call(engine.context, prepare_attempt, c.pi_js_undefined(), args.len, &args));
                var phase_args = [_]c.JSValue{ prepare_attempt, make, args[1], variant_value };
                break :fixture try engine.checked(c.JS_Call(engine.context, prepare_phase, c.pi_js_undefined(), phase_args.len, &phase_args));
            };
            defer engine.freeValue(fixture);
            var values = [_]c.JSValue{c.pi_js_undefined()} ** 7;
            defer for (values) |value| engine.freeValue(value);
            inline for (.{ "runtime", "input", "call", "tool", "arguments", "context", "marker" }, 0..) |name, index| values[index] = try vm.get(engine, fixture, name);
            const pending = pending: {
                if (corpus_index == 0) break :pending try @import("extensions/native_durable_tool_execute.zig").run(engine, &intrinsics, &cache, .{ .tool_task = tool_task, .terminal = .{ .live = tokens[0], .nested_calls = index_token, .nested_results = tokens[1], .tool_result = tokens[2], .usage = tokens[3], .iterator_symbol = cache.iterator_symbol }, .sanitize_pattern = pattern }, .{ .maxBytes = 8, .maxLines = 2, .retain = if (std.mem.eql(u8, variant, "tail")) .tail else .head }, values[0], values[1], values[2], values[3], values[4], values[5]);
                const task = try vm.object(engine);
                defer engine.freeValue(task);
                try @import("extensions/native_tool_info.zig").putData(engine, task, "input", c.JS_DupValue(engine.context, values[1]));
                break :pending try vm.invoke(engine, phases, "call", &.{ task, values[0], values[5] });
            };
            defer engine.freeValue(pending);
            if (row.object.get("failure").? == .null) {
                const completed = engine.awaitValue(pending) catch |err| {
                    std.debug.print("Attempt {s}: {s}\n", .{ variant, engine.last_error orelse "no diagnostic" });
                    return err;
                };
                defer engine.freeValue(completed);
                try std.testing.expect(c.JS_IsUndefined(completed));
            } else {
                try std.testing.expectError(error.JavaScriptException, engine.awaitValue(pending));
                try std.testing.expect(c.JS_IsStrictEqual(engine.context, values[6], engine.captured_exception.?));
            }
            const inspected = try vm.invoke(engine, fixture, "inspectExecution", &.{});
            defer engine.freeValue(inspected);
            const text = try engine.stringify(inspected);
            defer gpa.free(text);
            var actual = try json.Owned.parse(gpa, text);
            defer actual.deinit();
            var expected = row;
            _ = expected.object.swapRemove("nested");
            _ = expected.object.swapRemove("variant");
            _ = expected.object.swapRemove("failure");
            if (!json.equal(expected, actual.value)) std.debug.print("Attempt {s} actual: {s}\n", .{ variant, text });
            try std.testing.expect(json.equal(expected, actual.value));
        }
        if (source.value.object.get("shape")) |shape| {
            const inspect = try engine.eval("(ToolTask)=>{const checkpoint={phase:'execute',arguments:{count:2},replay:'safe'},migrated=ToolTask.definition.migrate({assistant:11,callId:'c1',extra:true},checkpoint);return{tokenKeys:Object.keys(ToolTask),definitionKeys:Object.keys(ToolTask.definition),name:ToolTask.definition.name,version:ToolTask.definition.version,initial:ToolTask.definition.initial(),arity:{initial:ToolTask.definition.initial.length,migrate:ToolTask.definition.migrate.length,call:ToolTask.definition.phases.call.length,execute:ToolTask.definition.phases.execute.length,abort:ToolTask.definition.abort.length},migrated,checkpointIdentity:migrated.checkpoint===checkpoint}}", "actual-source-task-shape", c.JS_EVAL_TYPE_GLOBAL);
            defer engine.freeValue(inspect);
            var args = [_]c.JSValue{tool_task};
            const actual_shape = try engine.checked(c.JS_Call(engine.context, inspect, c.pi_js_undefined(), args.len, &args));
            defer engine.freeValue(actual_shape);
            const text = try engine.stringify(actual_shape);
            defer gpa.free(text);
            var parsed = try json.Owned.parse(gpa, text);
            defer parsed.deinit();
            try std.testing.expect(json.equal(shape, parsed.value));
        }
    }
}

test "native durable v2 execution matches actual Source attempt API and terminal transaction traces" {
    try exerciseExecution(std.testing.allocator);
}
test "native durable v2 execution releases task continuations at every failed allocation" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseExecution(baseline.allocator());
    for (0..baseline.alloc_index) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        if (exerciseExecution(failing.allocator())) |_| {
            // Guest code can contain a failed allocation and finish cleanup.
            // Engine allocations can vary after earlier VM jobs have completed.
        } else |err| {
            if (!failing.has_induced_failure) return err;
        }
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("Execution allocation leak {d}/{d}: {d} allocated, {d} freed\n", .{ fail_index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

test "native durable v2 nested admissions match actual Source creation reattachment and conflicts" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const tool_task = try vm.get(engine, exports, "ToolTask");
    defer engine.freeValue(tool_task);
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const index = try @import("extensions/native_durable_tool_builtin.zig").indexToken(engine);
    defer engine.freeValue(index);
    const Factory = struct {
        fn admit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = engine_mod.Engine.fromContext(context.?);
            if (argc < 6) return c.JS_ThrowTypeError(context, "Nested admission fixture requires six arguments");
            return admitOwned(owner, argv[0..6], data) catch |err| @import("extensions/native_durable.zig").rejectedPromise(owner, err);
        }
        fn admitOwned(owner: *engine_mod.Engine, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
            var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(owner);
            defer intrinsics.deinit(owner);
            const key = try vm.get(owner, args[4], "key");
            defer owner.freeValue(key);
            const progress = try vm.get(owner, args[4], "progress");
            defer owner.freeValue(progress);
            const abandon = try vm.get(owner, args[4], "abandonOnRestart");
            defer owner.freeValue(abandon);
            return @import("extensions/native_durable_nested_call.zig").admit(owner, &intrinsics, .{ .task = data[0], .index = data[1], .live = data[2] }, args[0], args[1], args[2], args[3], key, progress, c.JS_ToBool(owner.context, abandon) != 0, args[5]);
        }
    };
    var captures = [_]c.JSValue{ tool_task, index, live };
    const admit = try engine.checked(c.JS_NewCFunctionData2(engine.context, Factory.admit, "nativeAdmit", 6, 0, captures.len, &captures));
    defer engine.freeValue(admit);
    const exercise_admission = try engine.eval(@embedFile("extensions/fixtures/durable-eba-admission-runtime.txt"), "actual-source-admission-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(exercise_admission);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-admission-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const variant = row.object.get("variant").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, variant.ptr, variant.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ admit, tool_task, name };
        const pending = try engine.checked(c.JS_Call(engine.context, exercise_admission, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const text = try engine.stringify(result);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        var expected = row;
        _ = expected.object.swapRemove("variant");
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

test "native durable v2 full nested tool calls match actual Source task family results and cleanup" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const tool_task = try vm.get(engine, exports, "ToolTask");
    defer engine.freeValue(tool_task);
    const exercise_nested = try engine.eval(@embedFile("extensions/fixtures/durable-eba-nested-runtime.txt"), "actual-source-nested-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(exercise_nested);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-eba-nested-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const clock = try engine.eval("globalThis.nestedTick=0;globalThis.performance={now(){const value=nestedTick;nestedTick+=5;return value}}", "source-controlled-nested-performance", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(clock);
        const variant = row.object.get("variant").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, variant.ptr, variant.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ tool_task, name };
        const pending = try engine.checked(c.JS_Call(engine.context, exercise_nested, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(pending);
        const result = engine.awaitValue(pending) catch |err| {
            std.debug.print("Nested {s}: {s}\n", .{ variant, engine.last_error orelse "no diagnostic" });
            return err;
        };
        defer engine.freeValue(result);
        const text = try engine.stringify(result);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        var expected = row;
        _ = expected.object.swapRemove("variant");
        if (!json.equal(expected, actual.value)) std.debug.print("Nested {s} actual: {s}\n", .{ variant, text });
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

test "native durable v2 real session scheduler executes genuine ToolTask and owned nested calls" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const durable = @import("extensions/native_durable.zig");
    const tasks = @import("extensions/native_durable_tasks.zig");
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    if (c.JS_AddPerformance(engine.context) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const token = try vm.get(engine, exports, "ToolTask");
    defer engine.freeValue(token);
    const builtins = try vm.array(engine);
    defer engine.freeValue(builtins);
    try @import("extensions/native_js_values.zig").push(engine, builtins, token);
    const registry = try @import("extensions/native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_tool_info.zig").putData(engine, global, "toolKernelSession", c.JS_DupValue(engine.context, session));
    try @import("extensions/native_tool_info.zig").putData(engine, global, "toolKernelRegistry", c.JS_DupValue(engine.context, registry));
    const setup = engine.evalModule(
        \\import{ToolTask,AssistantEntry,LiveDoc,AgentDoc,defineExtension,defineTool}from'@earendil-works/pi-durable';
        \\globalThis.toolKernelCalls=[];globalThis.toolKernelNested=[];globalThis.toolKernelReports=[];
        \\const inner=defineTool({name:'kernel-inner',description:'inner',parameters:{type:'object',properties:{count:{type:'number'}},required:['count']},callers:['tools'],execute:async(args,api,ctx)=>{
        \\ toolKernelCalls.push(['inner',args.count]);api.output('inner report\n');await api.details({owned:true},ctx);
        \\ return {output:[{type:'text',text:'inner '+args.count}],details:{owned:true}};
        \\}});
        \\const outer=defineTool({name:'kernel-outer',description:'outer',parameters:{type:'object'},callers:['model'],execute:async(args,api,ctx)=>{
        \\ globalThis.toolKernelSavedApi=api;toolKernelCalls.push(['outer',api.taskId]);const first=await api.executeTool('kernel-inner',{count:2},ctx,{key:'child'});const second=await api.executeTool('kernel-inner',{count:2},ctx,{key:'child'});
        \\ toolKernelNested.push(first,second);if(first===second)throw Error('returned nested copies alias');return {output:[{type:'text',text:'kernel done'}]};
        \\}});
        \\toolKernelRegistry.install(defineExtension({name:'kernel-tools',tools:[outer,inner]}));
        \\globalThis.toolKernelOptions={registry:toolKernelRegistry,onReport:error=>toolKernelReports.push(String(error?.stack??error)),settings:{progress:{outputIntervalMs:0}}};
        \\globalThis.toolKernelConversation=(await toolKernelSession.commit(tx=>tx.createRootConversation(),{})).id;
        \\await toolKernelSession.commit(async tx=>{await tx.doc(AgentDoc,toolKernelConversation);await tx.doc(LiveDoc,toolKernelConversation)},{});
        \\globalThis.toolKernelAssistant=await toolKernelSession.commit(tx=>tx.appendEntry(AssistantEntry,toolKernelConversation,{model:[{role:'assistant',content:[{type:'toolCall',id:'root',name:'kernel-outer',arguments:{}}]}]}),{});
        \\globalThis.toolKernelTask=await toolKernelSession.commit(tx=>tx.createTask(ToolTask,{kind:'model',assistant:toolKernelAssistant.id,callId:'root'},{conversationId:toolKernelConversation,ownership:{kind:'conversation'}}),{});
        \\await toolKernelSession.commit(async tx=>{const live=await tx.doc(LiveDoc,toolKernelConversation);live.tools=[{taskId:toolKernelTask,callId:'root',name:'kernel-outer',arguments:{},status:'pending'}]},{});
    , "real-native-tool-kernel-setup") catch |err| {
        std.debug.print("Tool kernel setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(setup);
    const options = try vm.get(engine, global, "toolKernelOptions");
    defer engine.freeValue(options);
    const context = try vm.object(engine);
    defer engine.freeValue(context);
    try tasks.attach(engine, session, options, context);
    const manager = try tasks.getManager(engine, session);
    const id = try vm.get(engine, global, "toolKernelTask");
    defer engine.freeValue(id);
    const pending = try tasks.wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| {
        std.debug.print("Real ToolTask kernel: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(settled);
    const record = try engine.stringify(settled);
    defer std.testing.allocator.free(record);
    var parsed = try json.Owned.parse(std.testing.allocator, record);
    defer parsed.deinit();
    const outcome = parsed.value.object.get("state").?.object.get("outcome").?;
    if (!std.mem.eql(u8, outcome.object.get("status").?.string, "completed")) {
        std.debug.print("Real ToolTask outcome: {s}\n", .{record});
        return error.ToolKernelDidNotComplete;
    }
    const source_bytes = @embedFile("extensions/fixtures/durable-eba-real-tool-kernel-original.json");
    try @import("extensions/native_tool_info.zig").putData(engine, global, "toolKernelSource", try engine.checked(c.JS_ParseJSON(engine.context, source_bytes.ptr, source_bytes.len, "actual-source-tool-kernel")));
    const proof = try engine.evalModule(
        \\import{LiveDoc}from'@earendil-works/pi-durable';
        \\if(toolKernelCalls.length!==2||toolKernelCalls[0][0]!=='outer'||toolKernelCalls[1][0]!=='inner')throw Error(JSON.stringify(toolKernelCalls));
        \\if(toolKernelNested.length!==2||toolKernelNested[0].structuredOutput!=='inner 2'||toolKernelNested[1].structuredOutput!=='inner 2'||toolKernelNested[0].taskId!==toolKernelNested[1].taskId)throw Error(JSON.stringify(toolKernelNested));
        \\const live=await toolKernelSession.snapshot(LiveDoc,toolKernelConversation,{});if(live.nestedTools!==undefined||live.tools[0].status!=='done'||live.tools[0].entry===undefined)throw Error(JSON.stringify(live));
        \\if(toolKernelReports.length)throw Error(JSON.stringify(toolKernelReports));
        \\const actual={calls:toolKernelCalls.map(row=>row[0]==='outer'?['outer']:row),nested:[...toolKernelNested.map(row=>({value:row.structuredOutput,owned:row.details?.owned})),toolKernelNested[0]!==toolKernelNested[1],toolKernelNested[0].taskId===toolKernelNested[1].taskId],status:'completed',liveDone:live.tools[0].status==='done',entryPresent:live.tools[0].entry!==undefined,nestedRemoved:live.nestedTools===undefined,reports:toolKernelReports};
        \\const {source,...expected}=toolKernelSource;if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));
        \\for(const call of[()=>toolKernelSavedApi.output('late'),()=>toolKernelSavedApi.diagnostic({severity:'info',message:'late'}),()=>toolKernelSavedApi.retainedOutput()]){let denied=false;try{call()}catch(error){denied=error.message===`Tool call root has settled`}if(!denied)throw Error('retained sync tool API admitted after settlement')}
        \\for(const call of[()=>toolKernelSavedApi.details({late:true},{}),()=>toolKernelSavedApi.executeTool('kernel-inner',{count:3},{})]){let denied=false;try{await call()}catch(error){denied=error.message===`Tool call root has settled`}if(!denied)throw Error('retained async tool API admitted after settlement')}
        \\await toolKernelSession.close({});
    , "real-native-tool-kernel-proof");
    engine.freeValue(proof);
}

test "native durable v2 numeric output limits match actual Source edge corpus" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/text_decoder.zig").install(engine);
    const sanitizer = try engine.eval("(/[\\x00-\\x08\\x0b-\\x1f\\ufff9-\\ufffb]/g)", "numeric-output-sanitizer", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(sanitizer);
    const corpus = @embedFile("extensions/fixtures/durable-output-numeric-original.json");
    const source = try engine.checked(c.JS_ParseJSON(engine.context, corpus.ptr, corpus.len, "actual-numeric-source"));
    defer engine.freeValue(source);
    const rows = try vm.get(engine, source, "rows");
    defer engine.freeValue(rows);
    const number_from = try engine.eval("value=>Number(value)", "numeric-source-values", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(number_from);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const limit_values = try vm.get(engine, row, "limits");
        defer engine.freeValue(limit_values);
        var limits: @import("extensions/native_durable_output_limits.zig").Limits = .{};
        inline for (.{ "maxBytes", "maxLines" }) |name| {
            const text = try vm.get(engine, limit_values, name);
            defer engine.freeValue(text);
            var args = [_]c.JSValue{text};
            const value = try engine.checked(c.JS_Call(engine.context, number_from, c.pi_js_undefined(), 1, &args));
            defer engine.freeValue(value);
            if (c.JS_ToFloat64(engine.context, &@field(limits, name), value) < 0) return error.InvalidNumericSource;
        }
        const retain = try vm.get(engine, limit_values, "retain");
        defer engine.freeValue(retain);
        const retention = try engine.toString(retain);
        defer std.testing.allocator.free(retention);
        limits.retain = if (std.mem.eql(u8, retention, "head")) .head else if (std.mem.eql(u8, retention, "tail")) .tail else .other;
        const source_text = try vm.get(engine, row, "text");
        defer engine.freeValue(source_text);
        const encoded = try engine.toString(source_text);
        defer std.testing.allocator.free(encoded);
        try std.unicode.wtf8ToUtf8Lossy(encoded, encoded);
        const bounded = try @import("extensions/native_durable_output_limits.zig").boundOutput(std.testing.allocator, encoded, limits);
        defer std.testing.allocator.free(bounded.text);
        const expected_bound = try vm.get(engine, row, "bounded");
        defer engine.freeValue(expected_bound);
        inline for (.{ .{ "bytes", bounded.bytes }, .{ "droppedBytes", bounded.droppedBytes }, .{ "droppedLines", bounded.droppedLines } }) |field| {
            const expected = try vm.get(engine, expected_bound, field[0]);
            defer engine.freeValue(expected);
            var actual: i64 = 0;
            if (c.JS_ToInt64(engine.context, &actual, expected) < 0) return error.InvalidNumericSource;
            try std.testing.expectEqual(actual, @as(i64, @intCast(field[1])));
        }
        const actual_text = if (bounded.droppedBytes == 0) c.JS_DupValue(engine.context, source_text) else try engine.checked(c.JS_NewStringLen(engine.context, bounded.text.ptr, bounded.text.len));
        defer engine.freeValue(actual_text);
        const expected_text = try vm.get(engine, expected_bound, "text");
        defer engine.freeValue(expected_text);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual_text, expected_text));
        const buffer = try @import("extensions/native_durable_output_buffer.zig").create(engine, limits, sanitizer);
        defer engine.freeValue(buffer);
        const compare = try engine.eval("(buffer,row)=>{buffer.push(row.text.slice(0,1));buffer.snapshot();buffer.push(row.text.slice(1));buffer.end();const actual=buffer.snapshot();if(JSON.stringify(actual)!==JSON.stringify(row.buffer))throw Error(JSON.stringify({limits:row.limits,text:row.text,actual,expected:row.buffer}));}", "actual-source-numeric-buffer-comparison", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(compare);
        var args = [_]c.JSValue{ buffer, row };
        const result = engine.checked(c.JS_Call(engine.context, compare, c.pi_js_undefined(), args.len, &args)) catch |err| {
            std.debug.print("Numeric Source case {d}: {s}\n", .{ index, engine.last_error orelse "missing diagnostic" });
            return err;
        };
        engine.freeValue(result);
    }
}

test "native durable v2 ToolTask numeric limit phases match actual Source traces" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "numericMake", "extensions/fixtures/durable-eba-settle-runtime.txt" }, .{ "numericPrepare", "extensions/fixtures/durable-eba-execute-runtime.txt" } }) |item| {
        try @import("extensions/native_tool_info.zig").putData(engine, global, item[0], try engine.eval(@embedFile(item[1]), "actual-source-numeric-fixture", c.JS_EVAL_TYPE_GLOBAL));
    }
    const bytes = @embedFile("extensions/fixtures/durable-eba-limits-original.json");
    try @import("extensions/native_tool_info.zig").putData(engine, global, "numericSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "numeric-task-source")));
    const result = engine.evalModule(
        \\import{ToolTask}from'@earendil-works/pi-durable';
        \\for(const[name,limits]of[['infinite',{maxBytes:Infinity,maxLines:Infinity}],['nan',{maxBytes:NaN,maxLines:NaN}],['fractional',{maxBytes:3.5,maxLines:1.5}],['negative',{maxBytes:-1,maxLines:-1}],['zero',{maxBytes:0,maxLines:0}],['null',{maxBytes:null,maxLines:null,retain:null}],['unknown-retain',{maxBytes:4,maxLines:1,retain:'other'}]]){
        \\let tick=0;globalThis.performance={now:()=>{const value=tick;tick+=5;return value}};const f=numericPrepare(numericMake,false,'plain'),oldAgent=f.runtime.agent;f.tool.parameters={type:'object'};f.tool.outputLimits=limits;f.call.arguments={};f.runtime.agent=async(ctx)=>{await oldAgent(ctx);return{tools:[f.tool],callable:[f.tool]}};
        \\let failure;try{await ToolTask.definition.phases.call({input:f.input,state:{checkpoint:{phase:'call'}}},f.runtime,f.context)}catch(error){failure={name:error.name,message:error.message}}
        \\const actual={name,failure,...f.inspectExecution()},expected=numericSource.rows.find(row=>row.name===name);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));}
    , "actual-source-numeric-task-comparison") catch |err| {
        std.debug.print("Numeric ToolTask: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 prompt planning matches actual Source head and ordered sections" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bytes = @embedFile("extensions/fixtures/durable-prompt-original.json");
    const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-prompt-source"));
    defer engine.freeValue(corpus);
    const make = try engine.eval("(corpus,row)=>{const messages=corpus.variants[row.variant],entries=messages.map((message,index)=>({id:index+1,kind:'pi.system',model:[message]}));return{view:{head:row.head?{id:10}:undefined,entries,messages},desired:new Map(corpus.desireds[row.desired])}}", "actual-prompt-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const rows = try vm.get(engine, corpus, "rows");
    defer engine.freeValue(rows);
    const tools = try vm.array(engine);
    defer engine.freeValue(tools);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        var args = [_]c.JSValue{ corpus, row };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 2, &args));
        defer engine.freeValue(fixture);
        const view = try vm.get(engine, fixture, "view");
        defer engine.freeValue(view);
        const desired = try vm.get(engine, fixture, "desired");
        defer engine.freeValue(desired);
        const planned = try @import("extensions/native_durable_prompt.zig").planSystemEntries(engine, view, desired, tools, c.JS_NewInt32(engine.context, 5));
        defer engine.freeValue(planned);
        const actual = try engine.stringify(planned);
        defer std.testing.allocator.free(actual);
        const expected = try vm.get(engine, row, "planned");
        defer engine.freeValue(expected);
        const expected_text = try engine.stringify(expected);
        defer std.testing.allocator.free(expected_text);
        try std.testing.expectEqualStrings(expected_text, actual);
    }
}

test "native durable v2 prompt section and tool patches match actual Source matrices" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    for ([_][]const u8{ @embedFile("extensions/fixtures/durable-prompt-sections-original.json"), @embedFile("extensions/fixtures/durable-prompt-tools-original.json") }, 0..) |bytes, corpus_index| {
        const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-prompt-patches"));
        defer engine.freeValue(corpus);
        const variants = try vm.get(engine, corpus, "variants");
        defer engine.freeValue(variants);
        const rows = try vm.get(engine, corpus, "rows");
        defer engine.freeValue(rows);
        const make = try engine.eval("(variants,index,map)=>map?new Map(variants[index]):variants[index]", "prompt-patches-input", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(make);
        for (0..try vm.length(engine, rows)) |index| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
            defer engine.freeValue(row);
            const left_index = try vm.get(engine, row, if (corpus_index == 0) "shown" else "offered");
            defer engine.freeValue(left_index);
            const right_index = try vm.get(engine, row, "desired");
            defer engine.freeValue(right_index);
            var args = [_]c.JSValue{ variants, left_index, c.pi_js_bool(engine.context, @intFromBool(corpus_index == 0)) };
            const left = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 3, &args));
            defer engine.freeValue(left);
            args[1] = right_index;
            const right = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 3, &args));
            defer engine.freeValue(right);
            const result = if (corpus_index == 0) try @import("extensions/native_durable_prompt.zig").planSections(engine, left, right) else try @import("extensions/native_durable_prompt.zig").planTools(engine, left, right);
            defer engine.freeValue(result);
            const expected = try vm.get(engine, row, if (corpus_index == 0) "patches" else "changes");
            defer engine.freeValue(expected);
            const actual_text = try engine.stringify(result);
            defer std.testing.allocator.free(actual_text);
            const expected_text = try engine.stringify(expected);
            defer std.testing.allocator.free(expected_text);
            try std.testing.expectEqualStrings(expected_text, actual_text);
        }
    }
}

test "native durable v2 prompt rendering matches actual Source errors and cancellation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const make = try engine.eval("scenario=>{const trace=[],reason={original:true},context={abortSignal:{aborted:scenario==='aborted'}},input={original:true},shown=new Map([['a','shown']]),sections=[{key:'a',tag:scenario==='plain'?false:undefined,render:async(i,c)=>{trace.push(['render',i===input,c===context]);if(scenario.startsWith('throw')||scenario==='aborted')throw reason;if(scenario==='omit')return undefined;return'new'}},{key:'b',render:()=>{trace.push(['second']);return'B'}}];if(scenario==='throw-new')sections[0].key='new';return{sections,input,shown,context,report:error=>trace.push(['report',error===reason]),reason,inspect:(result,failure)=>({scenario,result:result===undefined?undefined:[...result],failure,trace})}}", "actual-render-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-prompt-render-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{name};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 6;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "sections", "input", "shown", "report", "context", "reason" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_prompt.zig").renderSections(engine, &captured, values[0], values[1], values[2], values[3], values[4]);
        defer engine.freeValue(pending);
        var rendered = c.pi_js_undefined();
        defer engine.freeValue(rendered);
        var failure = c.pi_js_undefined();
        if (engine.awaitValue(pending)) |result| {
            rendered = result;
        } else |err| {
            if (!std.mem.eql(u8, scenario, "aborted")) return err;
            failure = c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, values[5], engine.captured_exception.?)));
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{ rendered, failure });
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 compaction text matches actual Source response and transcript cases" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const text_module = @import("extensions/native_durable_compaction_text.zig");
    const bytes = @embedFile("extensions/fixtures/durable-compaction-helpers-original.json");
    const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-compaction-source"));
    defer engine.freeValue(corpus);
    const rows = try vm.get(engine, corpus, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const message = try vm.get(engine, row, "message");
        defer engine.freeValue(message);
        const text = try text_module.summaryText(engine, message);
        defer engine.freeValue(text);
        const expected_text = try vm.get(engine, row, "text");
        defer engine.freeValue(expected_text);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, text, expected_text));
        const failure = try text_module.summaryFailure(engine, message);
        defer engine.freeValue(failure);
        const expected_failure = try vm.get(engine, row, "failure");
        defer engine.freeValue(expected_failure);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, failure, expected_failure));
    }
    const serialized = try vm.get(engine, corpus, "serialized");
    defer engine.freeValue(serialized);
    for (0..try vm.length(engine, serialized)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, serialized, @intCast(index)));
        defer engine.freeValue(row);
        const messages = try vm.get(engine, row, "messages");
        defer engine.freeValue(messages);
        const text = try text_module.serializeConversation(engine, messages);
        defer engine.freeValue(text);
        const expected = try vm.get(engine, row, "text");
        defer engine.freeValue(expected);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, text, expected));
        const focus = try engine.checked(c.JS_NewString(engine.context, "focus"));
        defer engine.freeValue(focus);
        const prompt = try text_module.summaryPrompt(engine, messages, focus);
        defer engine.freeValue(prompt);
        const expected_prompt = try vm.get(engine, row, "prompt");
        defer engine.freeValue(expected_prompt);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, prompt, expected_prompt));
    }
}

test "native durable v2 compaction cut and estimate match actual Source cases" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = @import("extensions/native_durable_compaction_text.zig");
    const bytes = @embedFile("extensions/fixtures/durable-compaction-selection-original.json");
    const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-compaction-selection"));
    defer engine.freeValue(corpus);
    const make = try engine.eval("(corpus,row)=>{const contributions=corpus.variants[row.variant],entries=contributions.map((_,index)=>({id:index+1}));return{head:row.head?{id:1}:undefined,entries,contributions,messages:contributions.flat()}}", "actual-compaction-selection-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const number_from = try engine.eval("value=>Number(value)", "actual-compaction-selection-number", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(number_from);
    const extra = try engine.eval("([{role:'user',content:'extra',timestamp:1}])", "actual-compaction-selection-extra", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(extra);
    const rows = try vm.get(engine, corpus, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        var args = [_]c.JSValue{ corpus, row };
        const view = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(view);
        const raw_keep = try vm.get(engine, row, "keepRecentTokens");
        defer engine.freeValue(raw_keep);
        var number_args = [_]c.JSValue{raw_keep};
        const keep_value = try engine.checked(c.JS_Call(engine.context, number_from, c.pi_js_undefined(), 1, &number_args));
        defer engine.freeValue(keep_value);
        var keep: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &keep, keep_value) < 0) return error.InvalidNumericSource;
        const cut = try module.selectCut(engine, view, keep);
        const expected_cut = try vm.get(engine, row, "cut");
        defer engine.freeValue(expected_cut);
        if (cut) |selected| {
            var expected: i64 = 0;
            if (c.JS_ToInt64(engine.context, &expected, expected_cut) < 0) return error.InvalidNumericSource;
            try std.testing.expectEqual(expected, @as(i64, @intCast(selected)));
        } else try std.testing.expect(c.JS_IsUndefined(expected_cut));
        const estimate = try module.estimateContext(engine, view, extra);
        const expected_estimate = try vm.get(engine, row, "estimate");
        defer engine.freeValue(expected_estimate);
        var expected: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &expected, expected_estimate) < 0) return error.InvalidNumericSource;
        try std.testing.expectEqual(expected, estimate);
    }
}

test "native durable v2 compaction terminal cleanup preserves Source live status contract" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const fixture = try engine.eval("(()=>{const live={compactions:[{taskId:6},{taskId:7},{taskId:8}]};let state;const token={};const runtime={taskId:7,conversationId:3,commit:async(change,context)=>{if(context!==ctx)throw Error('context');state=await change({doc:async(t,id)=>{if(t!==token||id!==3)throw Error('doc');return live}})}};const ctx={};return{runtime,context:ctx,token,inspect:()=>({live,state})}})()", "compaction-terminal-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    const runtime = try vm.get(engine, fixture, "runtime");
    defer engine.freeValue(runtime);
    const context = try vm.get(engine, fixture, "context");
    defer engine.freeValue(context);
    const token = try vm.get(engine, fixture, "token");
    defer engine.freeValue(token);
    const outcome = try engine.eval("({status:'aborted'})", "compaction-terminal-outcome", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(outcome);
    const pending = try @import("extensions/native_durable_compaction_task.zig").terminal(engine, &intrinsics, runtime, context, token, outcome);
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    defer engine.freeValue(settled);
    const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
    defer engine.freeValue(inspected);
    const text = try engine.stringify(inspected);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"live\":{\"compactions\":[{\"taskId\":6},{\"taskId\":8}]},\"state\":{\"status\":\"terminal\",\"outcome\":{\"status\":\"aborted\"}}}", text);
}

test "native durable v2 compaction retry matches Source checkpoint and live status" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const fixture = try engine.eval("(()=>{const live={compactions:[{taskId:7,reason:'manual',blocking:false,attempt:1,retry:{at:10,error:'previous'}}]},trace=[];let state;const token={},ctx={};const runtime={taskId:7,conversationId:3,sleep:async(until,context)=>trace.push(['sleep',until,context===ctx]),commit:async(change,context)=>{trace.push(['commit',context===ctx]);state=await change({doc:async(t,id)=>{trace.push(['doc',t===token,id]);return live}});trace.push(['next',state])}};return{runtime,context:ctx,token,checkpoint:{phase:'retry',until:10,attempt:1,model:{provider:'p',modelId:'m'},thinkingLevel:'off',streamOptions:{},maxTokens:50,tail:9,firstKept:4},inspect:()=>({trace,live,state})}})()", "compaction-retry-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    var values = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    defer for (values) |value| engine.freeValue(value);
    inline for (.{ "runtime", "context", "token", "checkpoint" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
    const pending = try @import("extensions/native_durable_compaction_task.zig").retry(engine, &intrinsics, values[0], values[1], values[2], values[3]);
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
    defer engine.freeValue(inspected);
    const text = try engine.stringify(inspected);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-compaction-select-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        if (!std.mem.eql(u8, row.object.get("scenario").?.string, "retry")) continue;
        var expected = row;
        _ = expected.object.swapRemove("scenario");
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

test "native durable v2 compaction model failures and empty context match actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const make = try engine.eval("scenario=>{const trace=[],live={compactions:[{taskId:7,reason:'manual',blocking:false,attempt:1,retry:{at:10,error:'previous'}}]},state={},token={},ctx={};const runtime={taskId:7,conversationId:3,now:()=>5,settings:{compaction:{keepRecentTokens:10,reserveTokens:100},stream:{}},models:{getModel:()=>scenario==='missing-model'?undefined:{maxTokens:100}},agent:async()=>scenario==='no-model'?{}:{model:{provider:'p',modelId:'m'},thinkingLevel:'off'},context:async()=>{const messages=[{role:'user',content:'old '.repeat(100),timestamp:1},{role:'assistant',content:[{type:'text',text:'recent '.repeat(100)}],timestamp:2}];return scenario==='nothing'||scenario==='no-model'||scenario==='missing-model'?{entries:[],contributions:[],messages:[]}:{entries:[{id:1},{id:2}],contributions:messages.map(message=>[message]),messages}},hooks:{async each(event,callback){trace.push(['hooks',event]);if(scenario==='decline')await callback(async()=>({decline:true}));if(scenario==='hook-summary')await callback(async()=>({summary:'hook summary'}))}},commit:async(change,context)=>{trace.push(['commit',context===ctx]);const next=await change({doc:async(t,id)=>{trace.push(['doc',t===token,id]);return live},appendEntry:async(id,entry)=>{trace.push(['appendEntry',id,entry]);return{id:20}}},{input:{reason:'manual'},owner:1});Object.assign(state,next);trace.push(['next',next])}};return{runtime,context:ctx,token,task:{input:{reason:'manual'}},inspect:()=>({trace,live,state})}}", "compaction-select-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-compaction-select-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        if (!std.mem.eql(u8, scenario, "no-model") and !std.mem.eql(u8, scenario, "missing-model") and !std.mem.eql(u8, scenario, "nothing") and !std.mem.eql(u8, scenario, "decline") and !std.mem.eql(u8, scenario, "request") and !std.mem.eql(u8, scenario, "hook-summary")) continue;
        const scenario_value = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(scenario_value);
        var args = [_]c.JSValue{scenario_value};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 4;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "token", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_compaction_task.zig").select(engine, &intrinsics, values[0], values[1], values[2], values[3]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        var expected = row;
        _ = expected.object.swapRemove("scenario");
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

test "native durable v2 inbox boundary matches actual Source write and user ordering" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const bytes = @embedFile("extensions/fixtures/durable-inbox-boundary-original.json");
    const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-inbox-source"));
    defer engine.freeValue(corpus);
    const make = try engine.eval("(corpus,row)=>{const trace=[],boundary={conversationId:7,inbox:{items:JSON.parse(JSON.stringify(corpus.variants[row.variant]))},head:3,steeringMode:row.steeringMode,followUpMode:row.followUpMode};let next=10;const tx={appendEntry:async(...args)=>{const id=next++;trace.push(['append',...args,id]);return{id}},placeSubmission:(...args)=>trace.push(['place',...args]),settleSubmission:(...args)=>trace.push(['settle',...args])};return{tx,boundary,token:{kind:'pi.user'},inspect:result=>({result,trace,boundary})}}", "inbox-boundary-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const rows = try vm.get(engine, corpus, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        var args = [_]c.JSValue{ corpus, row };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 2, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "tx", "boundary", "token" }, 0..) |key, position| values[position] = try vm.get(engine, fixture, key);
        const at = try vm.get(engine, row, "at");
        defer engine.freeValue(at);
        const text_at = try engine.toString(at);
        defer std.testing.allocator.free(text_at);
        const pending = try @import("extensions/native_durable_inbox.zig").apply(engine, &intrinsics, values[0], values[1], std.mem.eql(u8, text_at, "final"), c.JS_NewInt32(engine.context, 5), values[2]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{result});
        defer engine.freeValue(inspected);
        const serialized = try engine.stringify(inspected);
        defer std.testing.allocator.free(serialized);
        var actual = try json.Owned.parse(std.testing.allocator, serialized);
        defer actual.deinit();
        const expected_text = try engine.stringify(row);
        defer std.testing.allocator.free(expected_text);
        var expected = try json.Owned.parse(std.testing.allocator, expected_text);
        defer expected.deinit();
        inline for (.{ "variant", "at", "steeringMode", "followUpMode" }) |key| _ = expected.value.object.swapRemove(key);
        if (!json.equal(expected.value, actual.value)) std.debug.print("Inbox {d}: {s}\n", .{ index, serialized });
        try std.testing.expect(json.equal(expected.value, actual.value));
    }
}

test "native durable v2 inbox preparation reads table before document draft" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var intrinsics = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    const fixture = try engine.eval("(()=>{const trace=[],token={},inbox={items:[]};return{token,inbox,trace,tx:{latestHeadMarker:async id=>{trace.push(['head',id]);return{head:3}},doc:async(t,id)=>{trace.push(['doc',t===token,id]);return inbox}},modes:{steeringMode:'all',followUpMode:'one'}}})()", "native-inbox-prepare-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    defer for (values) |value| engine.freeValue(value);
    inline for (.{ "tx", "modes", "token" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
    const pending = try @import("extensions/native_durable_inbox.zig").prepare(engine, &intrinsics, values[0], c.JS_NewInt32(engine.context, 7), values[1], values[2]);
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    const text = try engine.stringify(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"conversationId\":7,\"inbox\":{\"items\":[]},\"steeringMode\":\"all\",\"followUpMode\":\"one\",\"head\":3}", text);
    const trace = try vm.get(engine, fixture, "trace");
    defer engine.freeValue(trace);
    const trace_text = try engine.stringify(trace);
    defer std.testing.allocator.free(trace_text);
    try std.testing.expectEqualStrings("[[\"head\",7],[\"doc\",true,7]]", trace_text);
}

test "native durable v2 write admission matches actual Source traces" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const setup = try engine.evalModule(
        \\import{LiveDoc,InboxDoc,UserEntry}from'@earendil-works/pi-durable';
        \\globalThis.makeWriteAdmission=scenario=>{const trace=[],live=scenario==='busy-write'?{run:{taskId:9,inputs:[]}}:{},inbox={items:scenario==='queued-write'?[{id:1,mode:'write',entry:{kind:'custom',model:[]}}]:[]},draft={type:'write',requestId:'request',entry:{kind:'custom',head:scenario==='stale-write'?1:4,model:[]}};let next=10;const tx={submissionByRequest:async(...args)=>{trace.push(['request',...args]);return scenario==='reuse'?{id:8,type:'write'}:scenario==='conflict'?{id:8,type:'input'}:undefined},doc:async(token,id)=>{trace.push(['doc',token===LiveDoc?'live':token===InboxDoc?'inbox':'other',id]);return token===LiveDoc?live:inbox},latestHeadMarker:async id=>{trace.push(['head',id]);return{head:3}},createSubmission:async record=>{trace.push(['create',record]);return{id:next++}},appendEntry:async(...args)=>{const id=next++;trace.push(['append',...args,id]);return{id}},placeSubmission:(...args)=>trace.push(['place',...args]),settleSubmission:(...args)=>trace.push(['settle',...args])};return{tx,draft,inspect:(id,failure)=>({scenario,id,failure,trace,live,inbox})}};
    , "write-admission-fixture");
    engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const make = try vm.get(engine, global, "makeWriteAdmission");
    defer engine.freeValue(make);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "InboxDoc", "UserEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const modes = try engine.eval("({steeringMode:'all',followUpMode:'all'})", "admission-modes", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(modes);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-submission-write-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const scenario_value = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(scenario_value);
        var args = [_]c.JSValue{scenario_value};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        const tx = try vm.get(engine, fixture, "tx");
        defer engine.freeValue(tx);
        const draft = try vm.get(engine, fixture, "draft");
        defer engine.freeValue(draft);
        const pending = try @import("extensions/native_durable_submissions.zig").admit(engine, &captured, .{ .live = tokens[0], .inbox = tokens[1], .user = tokens[2], .generation = c.pi_js_undefined() }, tx, c.JS_NewInt32(engine.context, 7), draft, c.JS_NewInt32(engine.context, 5), modes);
        defer engine.freeValue(pending);
        var id = c.pi_js_undefined();
        defer engine.freeValue(id);
        var failure = c.pi_js_undefined();
        defer engine.freeValue(failure);
        if (engine.awaitValue(pending)) |result| {
            id = result;
        } else |err| {
            if (!std.mem.eql(u8, scenario, "conflict")) return err;
            const error_value = engine.captured_exception orelse return err;
            failure = try vm.object(engine);
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "name", try vm.get(engine, error_value, "name"));
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "message", try vm.get(engine, error_value, "message"));
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{ id, failure });
        defer engine.freeValue(inspected);
        const serialized = try engine.stringify(inspected);
        defer std.testing.allocator.free(serialized);
        var actual = try json.Owned.parse(std.testing.allocator, serialized);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("Admission {s}: {s}\n", .{ scenario, serialized });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 conversation compaction placement matches actual Source admission" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-compaction-placement-runtime.txt"), "actual-compaction-placement-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const inbox = try vm.get(engine, exports, "InboxDoc");
    defer engine.freeValue(inbox);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-compaction-placement-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        if (!std.mem.startsWith(u8, scenario, "hook-summary")) continue;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, live, inbox };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_compaction_task.zig").select(engine, &captured, values[0], values[1], live, values[2]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("Placement {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 provider identity reads existing state and migrates legacy once" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const make = try engine.eval("legacy=>{const trace=[],ctx={},token={};const runtime={conversationId:7,snapshot:async(t,id,c)=>{trace.push(['snapshot',t===token,id,c===ctx]);return legacy?undefined:{sessionId:'existing'}},commit:async(change,c)=>{trace.push(['commit',c===ctx]);return change({doc:async(t,id)=>{trace.push(['doc',t===token,id]);return{sessionId:'created'}}})}};return{runtime,context:ctx,token,trace}}", "provider-identity-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    for ([_]bool{ false, true }) |legacy| {
        var args = [_]c.JSValue{c.pi_js_bool(engine.context, @intFromBool(legacy))};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "token" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_provider.zig").ensure(engine, &captured, values[0], values[1], values[2]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const text = try engine.toString(result);
        defer std.testing.allocator.free(text);
        try std.testing.expectEqualStrings(if (legacy) "created" else "existing", text);
        const trace = try vm.get(engine, fixture, "trace");
        defer engine.freeValue(trace);
        const serialized = try engine.stringify(trace);
        defer std.testing.allocator.free(serialized);
        try std.testing.expectEqualStrings(if (legacy) "[[\"snapshot\",true,7,true],[\"commit\",true],[\"doc\",true,7]]" else "[[\"snapshot\",true,7,true]]", serialized);
    }
}

test "native durable v2 usage counters match actual Source optional totals" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const make = try engine.eval("row=>{const base=()=>({input:1,output:2,cacheRead:3,cacheWrite:4,totalTokens:10,cost:{input:0.1,output:0.2,cacheRead:0.3,cacheWrite:0.4,total:1}});return{total:{...base(),...row.prior},usage:{...base(),...row.optional}}}", "usage-counter-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const bytes = @embedFile("extensions/fixtures/durable-usage-original.json");
    const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-usage-source"));
    defer engine.freeValue(corpus);
    const rows = try vm.get(engine, corpus, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        var args = [_]c.JSValue{row};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        const total = try vm.get(engine, fixture, "total");
        defer engine.freeValue(total);
        const usage = try vm.get(engine, fixture, "usage");
        defer engine.freeValue(usage);
        try @import("extensions/native_durable_usage.zig").addUsage(engine, total, usage);
        const expected = try vm.get(engine, row, "total");
        defer engine.freeValue(expected);
        const text = try engine.stringify(total);
        defer std.testing.allocator.free(text);
        const expected_text = try engine.stringify(expected);
        defer std.testing.allocator.free(expected_text);
        try std.testing.expectEqualStrings(expected_text, text);
    }
}

test "native durable v2 usage record matches Source own key and prototype behavior" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bytes = @embedFile("extensions/fixtures/durable-usage-original.json");
    const corpus = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-usage-record-source"));
    defer engine.freeValue(corpus);
    const rows = try vm.get(engine, corpus, "records");
    defer engine.freeValue(rows);
    const usage = try engine.eval("({input:1,output:2,cacheRead:3,cacheWrite:4,totalTokens:10,cost:{input:0.1,output:0.2,cacheRead:0.3,cacheWrite:0.4,total:1}})", "usage-record-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(usage);
    const second = try @import("extensions/native_js_values.zig").spread(engine, usage);
    defer engine.freeValue(second);
    try @import("extensions/native_tool_info.zig").putData(engine, second, "reasoning", c.JS_NewInt32(engine.context, 3));
    const inspect = try engine.eval("(document,key)=>({document,own:Object.hasOwn(document.models,key),prototypeIsUsage:Object.getPrototypeOf(document.models)?.input===1})", "usage-record-inspect", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(inspect);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const key = try vm.get(engine, row, "key");
        defer engine.freeValue(key);
        const document = try engine.eval("({models:{},tools:{}})", "usage-document", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(document);
        try @import("extensions/native_durable_usage.zig").recordInDocument(engine, document, "models", key, usage);
        try @import("extensions/native_durable_usage.zig").recordInDocument(engine, document, "models", key, second);
        var args = [_]c.JSValue{ document, key };
        const result = try engine.checked(c.JS_Call(engine.context, inspect, c.pi_js_undefined(), 2, &args));
        defer engine.freeValue(result);
        const text = try engine.stringify(result);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        const expected_text = try engine.stringify(row);
        defer std.testing.allocator.free(expected_text);
        var expected = try json.Owned.parse(std.testing.allocator, expected_text);
        defer expected.deinit();
        _ = expected.value.object.swapRemove("key");
        _ = expected.value.object.swapRemove("trace");
        try std.testing.expect(json.equal(expected.value, actual.value));
    }
}

fn exerciseCompaction(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    return exerciseCompactionWithEngine(gpa, engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseCompactionWithEngine(gpa: std.mem.Allocator, engine: *engine_mod.Engine) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try @import("extensions/native_durable.zig").install(engine);

    const make = try engine.eval(@embedFile("extensions/fixtures/durable-compaction-summarize-runtime.txt"), "actual-summary-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const token = try vm.get(engine, exports, "CompactionTask");
    defer engine.freeValue(token);
    const definition = try vm.get(engine, token, "definition");
    defer engine.freeValue(definition);
    const phases = try vm.get(engine, definition, "phases");
    defer engine.freeValue(phases);
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "UsageDoc", "ProviderDoc" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    var source = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/durable-compaction-summarize-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try vm.invoke(engine, phases, "summarize", &.{ values[2], values[0], values[1] });
        defer engine.freeValue(pending);
        var failure = c.pi_js_undefined();
        defer engine.freeValue(failure);
        if (engine.awaitValue(pending)) |result| engine.freeValue(result) else |err| {
            if (!std.mem.eql(u8, scenario, "aborted")) {
                std.debug.print("Summary {s}: {s}\n", .{ scenario, engine.last_error orelse "missing" });
                return err;
            }
            const exception = engine.captured_exception orelse return err;
            failure = try vm.object(engine);
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "name", try vm.get(engine, exception, "name"));
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "message", try vm.get(engine, exception, "message"));
        }
        const result = try vm.invoke(engine, fixture, "inspect", &.{failure});
        defer engine.freeValue(result);
        const text = try engine.stringify(result);
        defer gpa.free(text);
        var actual = try json.Owned.parse(gpa, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("Summary {s} actual: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 full compaction summary flow matches actual Source" {
    try exerciseCompaction(std.testing.allocator);
}
test "native durable v2 compaction continuations release every failed allocation" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseCompaction(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseCompaction(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("Compaction leak at {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

test "native durable v2 genuine CompactionTask export matches actual Source definition" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    const actual = try engine.evalModule(
        \\import{CompactionTask}from'@earendil-works/pi-durable';
        \\globalThis.compactionDefinitionShape={keys:Object.keys(CompactionTask.definition),name:CompactionTask.definition.name,version:CompactionTask.definition.version,initial:CompactionTask.definition.initial(),phases:Object.keys(CompactionTask.definition.phases)};
        \\for(const[name,fn]of Object.entries(CompactionTask.definition.phases)){if(fn.length!==3)throw Error(name+' arity');}if(CompactionTask.definition.abort.length!==3)throw Error('abort arity');
    , "genuine-native-compaction-export");
    engine.freeValue(actual);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const shape = try vm.get(engine, global, "compactionDefinitionShape");
    defer engine.freeValue(shape);
    const text = try engine.stringify(shape);
    defer std.testing.allocator.free(text);
    var parsed = try json.Owned.parse(std.testing.allocator, text);
    defer parsed.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-compaction-helpers-original.json"));
    defer source.deinit();
    try std.testing.expect(json.equal(source.value.object.get("shape").?, parsed.value));
}

test "native durable v2 real scheduler runs genuine CompactionTask no-model terminal" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const durable = @import("extensions/native_durable.zig");
    const tasks = @import("extensions/native_durable_tasks.zig");
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const token = try vm.get(engine, exports, "CompactionTask");
    defer engine.freeValue(token);
    const builtins = try vm.array(engine);
    defer engine.freeValue(builtins);
    try @import("extensions/native_js_values.zig").push(engine, builtins, token);
    const registry = try @import("extensions/native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelSession", c.JS_DupValue(engine.context, session));
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelRegistry", c.JS_DupValue(engine.context, registry));
    const setup = try engine.evalModule(
        \\import{CompactionTask,LiveDoc,AgentDoc}from'@earendil-works/pi-durable';
        \\globalThis.compactionKernelReports=[];globalThis.compactionKernelOptions={registry:compactionKernelRegistry,onReport:error=>compactionKernelReports.push(String(error)),settings:{}};
        \\globalThis.compactionKernelConversation=(await compactionKernelSession.commit(tx=>tx.createRootConversation(),{})).id;
        \\await compactionKernelSession.commit(async tx=>{await tx.doc(AgentDoc,compactionKernelConversation);await tx.doc(LiveDoc,compactionKernelConversation)},{});
        \\globalThis.compactionKernelTask=await compactionKernelSession.commit(tx=>tx.createTask(CompactionTask,{reason:'manual'},{conversationId:compactionKernelConversation,ownership:{kind:'conversation'}}),{});
        \\await compactionKernelSession.commit(async tx=>{const live=await tx.doc(LiveDoc,compactionKernelConversation);live.compactions=[{taskId:compactionKernelTask,reason:'manual',blocking:false,attempt:1}]},{});
    , "real-compaction-kernel-setup");
    engine.freeValue(setup);
    const options = try vm.get(engine, global, "compactionKernelOptions");
    defer engine.freeValue(options);
    const context = try vm.object(engine);
    defer engine.freeValue(context);
    try tasks.attach(engine, session, options, context);
    const manager = try tasks.getManager(engine, session);
    const id = try vm.get(engine, global, "compactionKernelTask");
    defer engine.freeValue(id);
    const pending = try tasks.wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const record = try engine.awaitValue(pending);
    defer engine.freeValue(record);
    const text = try engine.stringify(record);
    defer std.testing.allocator.free(text);
    var parsed = try json.Owned.parse(std.testing.allocator, text);
    defer parsed.deinit();
    const outcome = parsed.value.object.get("state").?.object.get("outcome").?;
    try std.testing.expectEqualStrings("failed", outcome.object.get("status").?.string);
    try std.testing.expectEqualStrings("No model is configured", outcome.object.get("error").?.object.get("message").?.string);
}

test "native durable v2 real scheduler runs genuine CompactionTask model summary terminal" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const durable = @import("extensions/native_durable.zig");
    const tasks = @import("extensions/native_durable_tasks.zig");
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const token = try vm.get(engine, exports, "CompactionTask");
    defer engine.freeValue(token);
    const builtins = try vm.array(engine);
    defer engine.freeValue(builtins);
    try @import("extensions/native_js_values.zig").push(engine, builtins, token);
    const registry = try @import("extensions/native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelSession", c.JS_DupValue(engine.context, session));
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelRegistry", c.JS_DupValue(engine.context, registry));
    const setup = try engine.evalModule(
        \\import{CompactionTask,LiveDoc,AgentDoc,UserEntry,AssistantEntry}from'@earendil-works/pi-durable';
        \\globalThis.compactionKernelReports=[];globalThis.compactionKernelOptions={registry:compactionKernelRegistry,onReport:error=>compactionKernelReports.push(String(error)),settings:{compaction:{keepRecentTokens:1,reserveTokens:100}},models:{getModel:()=>({id:'m',maxTokens:100}),completeSimple:async()=>({role:'assistant',provider:'p',model:'m',content:[{type:'text',text:'actual kernel summary'}],stopReason:'stop',usage:{input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}})}};
        \\globalThis.compactionKernelConversation=(await compactionKernelSession.commit(tx=>tx.createRootConversation(),{})).id;
        \\await compactionKernelSession.commit(async tx=>{const agent=await tx.doc(AgentDoc,compactionKernelConversation);agent.model={provider:"p",modelId:"m"};await tx.doc(LiveDoc,compactionKernelConversation)},{});
        \\await compactionKernelSession.commit(async tx=>{await tx.appendEntry(UserEntry,compactionKernelConversation,{model:[{role:"user",content:"old ".repeat(100),timestamp:1}]});await tx.appendEntry(AssistantEntry,compactionKernelConversation,{model:[{role:"assistant",content:[{type:"text",text:"recent ".repeat(100)}],timestamp:2}]})},{});
        \\globalThis.compactionKernelTask=await compactionKernelSession.commit(tx=>tx.createTask(CompactionTask,{reason:'manual'},{conversationId:compactionKernelConversation,ownership:{kind:'conversation'}}),{});
        \\await compactionKernelSession.commit(async tx=>{const live=await tx.doc(LiveDoc,compactionKernelConversation);live.compactions=[{taskId:compactionKernelTask,reason:'manual',blocking:false,attempt:1}]},{});
    , "real-compaction-kernel-setup");
    engine.freeValue(setup);
    const options = try vm.get(engine, global, "compactionKernelOptions");
    defer engine.freeValue(options);
    const context = try vm.object(engine);
    defer engine.freeValue(context);
    try tasks.attach(engine, session, options, context);
    const manager = try tasks.getManager(engine, session);
    const id = try vm.get(engine, global, "compactionKernelTask");
    defer engine.freeValue(id);
    const pending = try tasks.wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const record = try engine.awaitValue(pending);
    defer engine.freeValue(record);
    const text = try engine.stringify(record);
    defer std.testing.allocator.free(text);
    var parsed = try json.Owned.parse(std.testing.allocator, text);
    defer parsed.deinit();
    const outcome = parsed.value.object.get("state").?.object.get("outcome").?;
    if (!std.mem.eql(u8, "completed", outcome.object.get("status").?.string)) {
        std.debug.print("Compaction model kernel: {s}\n", .{text});
        const reports = try vm.get(engine, global, "compactionKernelReports");
        defer engine.freeValue(reports);
        const report_text = try engine.stringify(reports);
        defer std.testing.allocator.free(report_text);
        std.debug.print("Compaction kernel reports: {s}\n", .{report_text});
    }
    try std.testing.expectEqualStrings("completed", outcome.object.get("status").?.string);
    try std.testing.expect(outcome.object.get("result").?.object.get("submissionId") != null);
    const golden = @embedFile("extensions/fixtures/durable-compaction-real-kernel-original.json");
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelSource", try engine.checked(c.JS_ParseJSON(engine.context, golden.ptr, golden.len, "actual-source-compaction-kernel")));
    const proof = try engine.evalModule(
        \\import{LiveDoc,UsageDoc}from'@earendil-works/pi-durable';
        \\const live=await compactionKernelSession.snapshot(LiveDoc,compactionKernelConversation,{}),usage=await compactionKernelSession.snapshot(UsageDoc,compactionKernelConversation,{});
        \\const actual={status:'completed',submissionPresent:true,live,usage,reports:compactionKernelReports};const{source,...expected}=compactionKernelSource;if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));
        \\await compactionKernelSession.close({});
    , "real-compaction-source-lifecycle-proof");
    engine.freeValue(proof);
}

test "native durable v2 submission transaction settles latest candidates and fences table reads" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    const result = engine.evalModule(
        \\import{MemoryStorage,createSession}from'@earendil-works/pi-durable';const storage=new MemoryStorage(),session=createSession(storage);
        \\const conversation=(await session.commit(tx=>tx.createRootConversation(),{})).id;const publications=[];session.subscribeCommits(event=>publications.push(event));
        \\const id=await session.commit(async tx=>{const row=await tx.createSubmission({conversationId:conversation,type:'input',status:'queued',requestId:'one'});tx.placeSubmission(row.id,2);tx.settleSubmission(row.id,{status:'done',answer:3});return row.id},{});
        \\if(publications.length!==1||publications[0].changes.filter(change=>change.type==='submission').length!==1)throw Error('submission candidate publication duplicates');
        \\const row=await storage.submission(id,{});if(row.status!=='done'||row.entry!==2||row.answer!==3)throw Error(JSON.stringify(row));
        \\await session.commit(tx=>{tx.settleSubmission(id,{status:'unanswered',reason:'aborted'})},{});if((await storage.submission(id,{})).status!=='done')throw Error('settled submission changed');
        \\let denied=false;try{await session.commit(async tx=>{await tx.createSubmission({conversationId:conversation,type:'write',status:'queued'});await tx.submissionByRequest(conversation,'one')},{})}catch(error){denied=true}if(!denied)throw Error('table read admitted after write');
        \\await session.close({});
    , "native-submission-transaction-kernel") catch |err| {
        std.debug.print("Submission transaction: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 generation retry and no-model outcomes match actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const make = try engine.eval("scenario=>{const trace=[],live={run:{taskId:7,inputs:[1,2]},generation:{attempt:1},tools:[],nestedTools:[]},context={},token={},task={state:{checkpoint:{phase:'retry',attempt:1,compacted:9,until:10}}},runtime={taskId:7,conversationId:3,sleep:async(until,ctx)=>trace.push(['sleep',until,ctx===context]),commit:async(change,ctx)=>{trace.push(['commit',ctx===context]);const next=await change({doc:async(t,id)=>{trace.push(['doc',t===token,id]);return live},settleSubmission:(...args)=>trace.push(['settle',...args])});trace.push(['next',next])}};return{runtime,context,token,task,ref:scenario==='no-model'?undefined:{provider:'p',modelId:'m'},inspect:()=>({scenario,trace,live})}}", "actual-generation-basic-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-basic-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{name};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 5;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "token", "task", "ref" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const task_module = @import("extensions/native_durable_generation_task.zig");
        const pending = if (std.mem.eql(u8, scenario, "retry")) try task_module.retry(engine, &captured, values[0], values[1], values[2], values[3]) else try task_module.failNoModel(engine, &captured, values[0], values[1], values[2], values[4]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation deferred checkpoints match actual Source poll timing" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const bytes = @embedFile("extensions/fixtures/durable-generation-deferred-original.json");
    const source = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-generation-deferred-source"));
    defer engine.freeValue(source);
    const make = try engine.eval("row=>{const trace=[],live={},context={},token={},request={attempt:2,compacted:9,model:{provider:'p',modelId:'m'},cutoff:4,...(row.pollAt===undefined?{}:{pollAt:row.pollAt})},message={stopReason:'deferred',deferred:{id:'handle',...(row.pollAfterMs===undefined?{}:{pollAfterMs:row.pollAfterMs})}},runtime={conversationId:3,signal:{throwIfAborted(){}},now:()=>100,commit:async(change,ctx)=>{trace.push(['commit',ctx===context]);trace.push(['next',await change({doc:async(t,id)=>{trace.push(['doc',t===token,id]);return live}})])}};return{runtime,context,token,request,message,inspect:()=>({pollAt:row.pollAt,pollAfterMs:row.pollAfterMs,trace,live})}}", "actual-generation-deferred-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const rows = try vm.get(engine, source, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        var args = [_]c.JSValue{row};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 5;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "token", "request", "message" }, 0..) |key, position| values[position] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_task.zig").deferred(engine, &captured, values[0], values[1], values[2], values[3], values[4]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const actual_text = try engine.stringify(inspected);
        defer std.testing.allocator.free(actual_text);
        const expected_text = try engine.stringify(row);
        defer std.testing.allocator.free(expected_text);
        try std.testing.expectEqualStrings(expected_text, actual_text);
    }
}

test "native durable v2 generation preparation matches actual Source pinned requests" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const system = try vm.get(engine, exports, "SystemEntry");
    defer engine.freeValue(system);
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-prepare-runtime.txt"), "actual-generation-prepare-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-prepare-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, system };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 2, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_task.zig").prepare(engine, &captured, values[0], values[1], live, values[2]);
        defer engine.freeValue(pending);
        var failure = c.pi_js_undefined();
        defer engine.freeValue(failure);
        if (engine.awaitValue(pending)) |result| engine.freeValue(result) else |err| {
            if (!std.mem.eql(u8, scenario, "empty")) return err;
            const exception = engine.captured_exception orelse return err;
            failure = try vm.object(engine);
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "name", try vm.get(engine, exception, "name"));
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "message", try vm.get(engine, exception, "message"));
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{failure});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation preparation matches actual Source compaction admission" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const system = try vm.get(engine, exports, "SystemEntry");
    defer engine.freeValue(system);
    const live = try vm.get(engine, exports, "LiveDoc");
    defer engine.freeValue(live);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-prepare-threshold-runtime.txt"), "actual-generation-prepare-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-prepare-threshold-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, system, live };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 3, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_task.zig").prepare(engine, &captured, values[0], values[1], live, values[2]);
        defer engine.freeValue(pending);
        var failure = c.pi_js_undefined();
        defer engine.freeValue(failure);
        if (engine.awaitValue(pending)) |result| engine.freeValue(result) else |err| {
            if (!std.mem.eql(u8, scenario, "empty")) return err;
            const exception = engine.captured_exception orelse return err;
            failure = try vm.object(engine);
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "name", try vm.get(engine, exception, "name"));
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "message", try vm.get(engine, exception, "message"));
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{failure});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation streaming matches actual Source partial publication" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const token = try vm.object(engine);
    defer engine.freeValue(token);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-stream-runtime.txt"), "actual-generation-stream-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const model = try engine.eval("({id:'m'})", "stream-model", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(model);
    const messages = try engine.eval("([{role:'user',content:'hi'}])", "stream-messages", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(messages);
    const options = try engine.eval("({original:true})", "stream-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-stream-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, token };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 2, &args));
        defer engine.freeValue(fixture);
        const runtime = try vm.get(engine, fixture, "runtime");
        defer engine.freeValue(runtime);
        const context = try vm.get(engine, fixture, "context");
        defer engine.freeValue(context);
        const pending = try @import("extensions/native_durable_generation_stream.zig").run(engine, &captured, runtime, model, messages, options, c.JS_NewInt32(engine.context, 2), context, token);
        defer engine.freeValue(pending);
        var output_value = c.pi_js_undefined();
        defer engine.freeValue(output_value);
        var failure = c.pi_js_undefined();
        if (engine.awaitValue(pending)) |result| {
            output_value = result;
        } else |err| {
            if (!std.mem.eql(u8, scenario, "throw")) return err;
            const original = engine.captured_exception orelse return err;
            const marker = try vm.get(engine, original, "original");
            defer engine.freeValue(marker);
            failure = c.pi_js_bool(engine.context, c.JS_ToBool(engine.context, marker));
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{ output_value, failure });
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("Stream {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation error classification matches actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "UsageDoc", "AssistantEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-classify-error-runtime.txt"), "actual-generation-error-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-classify-error-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 4;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "request", "message" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_task.zig").classify(engine, &captured, values[0], values[1], tokens[0], values[2], values[3]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation final answer matches actual Source normal and reset boundary" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const generation_token = try vm.get(engine, exports, "GenerationTask");
    defer engine.freeValue(generation_token);
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "InboxDoc", "UsageDoc", "AssistantEntry", "UserEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-answer-runtime.txt"), "actual-generation-answer-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-answer-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;

        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2], tokens[3], tokens[4], generation_token };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "message" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_answer.zig").run(engine, &captured, values[0], values[1], values[2], generation_token);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation tool result writer matches actual Source content" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const token = try vm.get(engine, exports, "ToolResultEntry");
    defer engine.freeValue(token);
    const usage_token = try vm.get(engine, exports, "UsageDoc");
    defer engine.freeValue(usage_token);
    const make = try engine.eval("(token,usageToken)=>{const trace=[],ledger={tools:{},models:{}};return{tx:{doc:async(t,id)=>{trace.push(['doc',t===usageToken,id]);return ledger},appendEntry:async(t,id,entry)=>{trace.push(['append',t===token,id,entry]);return{id:10}}},inspect:entry=>({trace,ledger,entry})}}", "actual-tool-result-writer-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-tool-result-writer-original.json"));
    defer source.deinit();
    const call = try engine.eval("({id:'c1',name:'tool'})", "writer-call", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(call);
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        var args = [_]c.JSValue{ token, usage_token };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 2, &args));
        defer engine.freeValue(fixture);
        const tx = try vm.get(engine, fixture, "tx");
        defer engine.freeValue(tx);
        const input = try engine.fromJsonValue(row.object.get("result").?);
        defer engine.freeValue(input);
        const pending = try @import("extensions/native_durable_tool_result.zig").append(engine, &captured, tx, c.JS_NewInt32(engine.context, 3), call, input, c.JS_NewInt32(engine.context, 5), if (std.mem.eql(u8, scenario, "text")) c.JS_NewInt32(engine.context, 7) else c.pi_js_undefined());
        defer engine.freeValue(pending);
        const entry = try engine.awaitValue(pending);
        defer engine.freeValue(entry);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{entry});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        var expected = row;
        _ = expected.object.swapRemove("scenario");
        _ = expected.object.swapRemove("result");
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

test "native durable v2 generation abort content matches actual Source partial and pending calls" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "UsageDoc", "AssistantEntry", "ToolResultEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-abort-content-runtime.txt"), "actual-generation-abort-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-abort-content-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2], tokens[3] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_abort.zig").run(engine, &captured, values[0], values[1], values[2]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation tool round admission matches actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "UsageDoc", "ToolTask", "AssistantEntry", "ToolResultEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-tool-round-runtime.txt"), "actual-generation-tool-round-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-tool-round-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2], tokens[3], tokens[4] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 5;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "request", "message", "calls" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_tools.zig").start(engine, &captured, values[0], values[1], values[2], values[3], values[4]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("ToolRound {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation terminal tool controls match actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const generation_token = try vm.get(engine, exports, "GenerationTask");
    defer engine.freeValue(generation_token);
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "InboxDoc", "AgentDoc", "ResetEntry", "UserEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-finish-tools-runtime.txt"), "actual-generation-finish-tools-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    const tools = try engine.eval("[10,11]", "finish-tools-ids", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(tools);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-finish-tools-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;

        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2], tokens[3], generation_token, tokens[4] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        const runtime = try vm.get(engine, fixture, "runtime");
        defer engine.freeValue(runtime);
        const context = try vm.get(engine, fixture, "context");
        defer engine.freeValue(context);
        const pending = try @import("extensions/native_durable_generation_finish_tools.zig").run(engine, &captured, runtime, context, c.JS_NewInt32(engine.context, 4), tools, generation_token);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("FinishTools {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation public token matches actual Source definition" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    const proof = try engine.evalModule(
        \\import{GenerationTask}from'@earendil-works/pi-durable';globalThis.generationShape={name:GenerationTask.definition.name,version:GenerationTask.definition.version,initial:GenerationTask.definition.initial(),keys:Object.keys(GenerationTask.definition),phases:Object.keys(GenerationTask.definition.phases)};for(const fn of Object.values(GenerationTask.definition.phases)){if(fn.length!==3)throw Error('phase arity')}if(GenerationTask.definition.abort.length!==3)throw Error('abort arity');
    , "genuine-generation-definition");
    engine.freeValue(proof);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const value = try vm.get(engine, global, "generationShape");
    defer engine.freeValue(value);
    const text = try engine.stringify(value);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-basic-original.json"));
    defer source.deinit();
    try std.testing.expect(json.equal(source.value.object.get("shape").?, actual.value));
}

test "native durable v2 generation real scheduler runs genuine GenerationTask model answer" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const durable = @import("extensions/native_durable.zig");
    const tasks = @import("extensions/native_durable_tasks.zig");
    try durable.install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const token = try vm.get(engine, exports, "GenerationTask");
    defer engine.freeValue(token);
    const builtins = try vm.array(engine);
    defer engine.freeValue(builtins);
    try @import("extensions/native_js_values.zig").push(engine, builtins, token);
    const registry = try @import("extensions/native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelSession", c.JS_DupValue(engine.context, session));
    try @import("extensions/native_tool_info.zig").putData(engine, global, "compactionKernelRegistry", c.JS_DupValue(engine.context, registry));
    const setup = try engine.evalModule(
        \\import{GenerationTask,LiveDoc,AgentDoc,UserEntry,AssistantEntry}from'@earendil-works/pi-durable';
        \\globalThis.compactionKernelReports=[];globalThis.compactionKernelOptions={registry:compactionKernelRegistry,onReport:error=>compactionKernelReports.push(String(error)),settings:{compaction:{enabled:false,keepRecentTokens:1,reserveTokens:100}},models:{getModel:()=>({id:'m',maxTokens:100,contextWindow:10000}),streamSimple:()=>({async *[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>({role:'assistant',provider:'p',model:'m',content:[{type:'text',text:'actual kernel answer'}],stopReason:'stop',usage:{input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}})})}};
        \\globalThis.compactionKernelConversation=(await compactionKernelSession.commit(tx=>tx.createRootConversation(),{})).id;
        \\await compactionKernelSession.commit(async tx=>{const agent=await tx.doc(AgentDoc,compactionKernelConversation);agent.model={provider:"p",modelId:"m"};await tx.doc(LiveDoc,compactionKernelConversation)},{});
        \\await compactionKernelSession.commit(async tx=>{await tx.appendEntry(UserEntry,compactionKernelConversation,{model:[{role:"user",content:"old ".repeat(100),timestamp:1}]});await tx.appendEntry(AssistantEntry,compactionKernelConversation,{model:[{role:"assistant",content:[{type:"text",text:"recent ".repeat(100)}],timestamp:2,usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}}]})},{});
        \\globalThis.compactionKernelTask=await compactionKernelSession.commit(tx=>tx.createTask(GenerationTask,{},{conversationId:compactionKernelConversation,ownership:{kind:'conversation'}}),{});
        \\await compactionKernelSession.commit(async tx=>{const live=await tx.doc(LiveDoc,compactionKernelConversation);live.run={taskId:compactionKernelTask,inputs:[]}},{});
    , "real-compaction-kernel-setup");
    engine.freeValue(setup);
    const options = try vm.get(engine, global, "compactionKernelOptions");
    defer engine.freeValue(options);
    const context = try vm.object(engine);
    defer engine.freeValue(context);
    try tasks.attach(engine, session, options, context);
    const manager = try tasks.getManager(engine, session);
    const id = try vm.get(engine, global, "compactionKernelTask");
    defer engine.freeValue(id);
    const pending = try tasks.wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const record = try engine.awaitValue(pending);
    defer engine.freeValue(record);
    const text = try engine.stringify(record);
    defer std.testing.allocator.free(text);
    var parsed = try json.Owned.parse(std.testing.allocator, text);
    defer parsed.deinit();
    const outcome = parsed.value.object.get("state").?.object.get("outcome").?;
    if (!std.mem.eql(u8, "completed", outcome.object.get("status").?.string)) {
        std.debug.print("Compaction model kernel: {s}\n", .{text});
        const reports = try vm.get(engine, global, "compactionKernelReports");
        defer engine.freeValue(reports);
        const report_text = try engine.stringify(reports);
        defer std.testing.allocator.free(report_text);
        std.debug.print("Compaction kernel reports: {s}\n", .{report_text});
    }
    try std.testing.expectEqualStrings("completed", outcome.object.get("status").?.string);
    try std.testing.expect(outcome.object.get("result").?.object.get("entryId") != null);
    const golden = @embedFile("extensions/fixtures/durable-generation-real-kernel-original.json");
    try @import("extensions/native_tool_info.zig").putData(engine, global, "generationKernelSource", try engine.checked(c.JS_ParseJSON(engine.context, golden.ptr, golden.len, "actual-generation-kernel-source")));
    const proof = try engine.evalModule(
        \\import{LiveDoc,UsageDoc}from'@earendil-works/pi-durable';const live=await compactionKernelSession.snapshot(LiveDoc,compactionKernelConversation,{}),usage=await compactionKernelSession.snapshot(UsageDoc,compactionKernelConversation,{});const actual={status:'completed',entryPresent:true,live,usage,reports:compactionKernelReports};const{source,...expected}=generationKernelSource;if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));await compactionKernelSession.close({});
    , "actual-generation-kernel-lifecycle");
    engine.freeValue(proof);
}

test "native durable v2 generation input admission matches actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "InboxDoc", "UserEntry", "GenerationTask" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const modes = try engine.eval("({steeringMode:'all',followUpMode:'all'})", "input-admission-modes", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(modes);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-submission-input-runtime.txt"), "actual-input-admission-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-submission-input-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2], tokens[3] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        const tx = try vm.get(engine, fixture, "tx");
        defer engine.freeValue(tx);
        const draft = try vm.get(engine, fixture, "draft");
        defer engine.freeValue(draft);
        var id = c.pi_js_undefined();
        defer engine.freeValue(id);
        var failure = c.pi_js_undefined();
        defer engine.freeValue(failure);
        const pending = try @import("extensions/native_durable_submissions.zig").admit(engine, &captured, .{ .live = tokens[0], .inbox = tokens[1], .user = tokens[2], .generation = tokens[3] }, tx, c.JS_NewInt32(engine.context, 3), draft, c.JS_NewInt32(engine.context, 5), modes);
        defer engine.freeValue(pending);
        if (engine.awaitValue(pending)) |result| {
            id = result;
        } else |err| {
            if (!std.mem.eql(u8, scenario, "busy-reject")) return err;
            const exception = engine.captured_exception orelse return err;
            failure = try vm.object(engine);
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "name", try vm.get(engine, exception, "name"));
            try @import("extensions/native_tool_info.zig").putData(engine, failure, "message", try vm.get(engine, exception, "message"));
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{ id, failure });
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation public Harness submits input and waits for answer" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry,LiveDoc,UsageDoc}from'@earendil-works/pi-durable';const context={},reports=[];const model={id:'m',maxTokens:100,contextWindow:10000},usage={input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};const models={getModel:()=>model,streamSimple:()=>({async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>({role:'assistant',provider:'p',model:'m',content:[{type:'text',text:'answer'}],stopReason:'stop',usage})})};
        \\const harness=await Harness.open(new MemoryStorage(),{registry:createRegistry(),models,settings:{compaction:{enabled:false}},onReport:error=>reports.push(String(error))},context);try{const root=await harness.root(context,{agent:{model:{provider:'p',modelId:'m'}}});const submission=await root.submit({type:'input',content:'hello'},context);const record=await submission.wait(context);if(record.status!=='done'||record.answer===undefined)throw Error(JSON.stringify(record));if((await submission.status(context)).status!=='done')throw Error('status');const again=await harness.submission(submission.id,context);if(again.id!==submission.id)throw Error('lookup');if((await again.abort(context))!=='settled')throw Error('terminal abort');if(reports.length)throw Error(JSON.stringify(reports));}finally{await harness.close(context)}
    , "public-native-generation-submission") catch |err| {
        std.debug.print("Public Generation: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 generation submission handle matches actual Source class and delegation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    const storage = try @import("extensions/native_durable.zig").memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try @import("extensions/native_durable.zig").sessionObject(engine, storage);
    defer engine.freeValue(session);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    const handle = try @import("extensions/native_durable_submission_handle.zig").handle(engine, session, options, c.JS_NewInt32(engine.context, 2));
    defer engine.freeValue(handle);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_tool_info.zig").putData(engine, global, "sourceHandle", c.JS_DupValue(engine.context, handle));
    const bytes = @embedFile("extensions/fixtures/durable-submission-handle-original.json");
    try @import("extensions/native_tool_info.zig").putData(engine, global, "sourceHandleExpected", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source-handle")));
    const proof = engine.evalModule(
        \\const handle=sourceHandle,context={},prototype=Object.getPrototypeOf(handle),ctor=prototype.constructor,trace=[],marker={original:true},host={status(...args){trace.push(['status',this===host,...args]);return marker},wait(...args){trace.push(['wait',this===host,...args]);return marker},abort(...args){trace.push(['abort',this===host,...args]);throw marker}},fake=new ctor(7,host);const statusIdentity=fake.status({ctx:1})===marker;fake.id=8;const waitIdentity=fake.wait({ctx:2})===marker;let throwIdentity;try{await fake.abort({ctx:3})}catch(error){throwIdentity=error===marker}let brand;try{prototype.status.call({},context)}catch(error){brand={name:error.name,message:error.message}}const actual={shape:{keys:Object.keys(handle),prototypeKeys:Reflect.ownKeys(prototype),name:ctor.name,arity:ctor.length,methods:Object.fromEntries(['status','wait','abort'].map(key=>[key,{arity:prototype[key].length,enumerable:Object.getOwnPropertyDescriptor(prototype,key).enumerable}]))},statusIdentity,waitIdentity,throwIdentity,trace,brand};const{source,...expected}=sourceHandleExpected;if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));
    , "actual-source-submission-handle") catch |err| {
        std.debug.print("Submission handle: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(proof);
}

test "native durable v2 generation submission waiters cancel independently and preserve raw cause" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry}from'@earendil-works/pi-durable';let ready,resolve;const started=new Promise(r=>ready=r),answer=new Promise(r=>resolve=r),usage={input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};const models={getModel:()=>({id:'m',maxTokens:100,contextWindow:10000}),streamSimple:()=>({async*[Symbol.asyncIterator](){ready();yield{type:'start',partial:{content:[]}}},result:()=>answer})};const harness=await Harness.open(new MemoryStorage(),{registry:createRegistry(),models,settings:{compaction:{enabled:false}}},{});try{const root=await harness.root({},{agent:{model:{provider:'p',modelId:'m'}}}),submission=await root.submit({type:'input',content:'hello'},{});await started;const controller=new AbortController(),reason={original:true};let caught;const first=submission.wait({abortSignal:controller.signal}).catch(error=>{caught=error}),second=submission.wait({});await Promise.resolve();await Promise.resolve();controller.abort(reason);await first;if(caught!==reason)throw Error('waiter cause identity');if((await submission.abort({}))!=='already_placed')throw Error('placed abort result');resolve({role:'assistant',provider:'p',model:'m',content:[{type:'text',text:'done'}],stopReason:'stop',usage});if((await second).status!=='done')throw Error('other waiter lost');if((await submission.wait({})).status!=='done')throw Error('settled wait');}finally{await harness.close({})}
    , "native-submission-waiter-cancel") catch |err| {
        std.debug.print("Submission waiters: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 generation public tool round executes and continues to final answer" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry,defineExtension,defineTool,LiveDoc,UsageDoc}from'@earendil-works/pi-durable';let calls=0,executed=0;const usage={input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},registry=createRegistry();registry.install(defineExtension({name:'native-test',tools:[defineTool({name:'echo',description:'echo',parameters:{type:'object'},execute:async(args,api,context)=>{executed++;api.output('progress');return{output:[{type:'text',text:'tool done'}]}}})]}));const models={getModel:()=>({id:'m',maxTokens:100,contextWindow:10000}),streamSimple:()=>{calls++;const first=calls===1;return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>({role:'assistant',provider:'p',model:'m',content:first?[{type:'toolCall',id:'c1',name:'echo',arguments:{}}]:[{type:'text',text:'final answer'}],stopReason:first?'toolUse':'stop',usage})}}};const reports=[],harness=await Harness.open(new MemoryStorage(),{registry,models,settings:{compaction:{enabled:false}},onReport:error=>reports.push(String(error))},{});try{const root=await harness.root({},{agent:{model:{provider:'p',modelId:'m'}}}),submission=await root.submit({type:'input',content:'run tool'},{});const record=await submission.wait({});if(record.status!=='done'||calls!==2||executed!==1)throw Error(JSON.stringify({record,calls,executed,reports}));const live=await harness.snapshot(LiveDoc,root.id,{}),ledger=await harness.snapshot(UsageDoc,root.id,{});if(Object.keys(live).length||ledger.models['p/m'].totalTokens!==6||reports.length)throw Error(JSON.stringify({live,ledger,reports}));}finally{await harness.close({})}
    , "native-generation-real-tool-round") catch |err| {
        std.debug.print("Public tool round: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 generation repeated idle submissions retry and deferred polling" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry,UsageDoc}from'@earendil-works/pi-durable';const results=[];for(const scenario of['repeat','retry','deferred']){let calls=0,polls=0;const usage={input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},final=()=>({role:'assistant',provider:'p',model:'m',content:[{type:'text',text:'answer'}],stopReason:'stop',usage}),models={getModel:()=>({id:'m',maxTokens:100,contextWindow:10000}),streamSimple:()=>{calls++;const message=scenario==='retry'&&calls===1?{...final(),content:[],stopReason:'error',errorMessage:'503 unavailable'}:scenario==='deferred'?{role:'assistant',content:[],stopReason:'deferred',deferred:{id:'h',pollAfterMs:0}}:final();return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>message}},fetchDeferred:async(model,handle,options)=>{polls++;if(handle.id!=='h'||!(options.signal instanceof AbortSignal))throw Error('deferred binding');return final()}};const reports=[],harness=await Harness.open(new MemoryStorage(),{registry:createRegistry(),models,settings:{compaction:{enabled:false},retry:{enabled:true,maxRetries:1,baseDelayMs:0}},onReport:error=>reports.push(String(error))},{});try{const root=await harness.root({},{agent:{model:{provider:'p',modelId:'m'}}});for(let index=0;index<(scenario==='repeat'?2:1);index++){const submission=await root.submit({type:'input',content:'hello'},{});if((await submission.wait({})).status!=='done')throw Error('not done');await root.waitForIdle({});await new Promise(resolve=>setTimeout(resolve,0));}const ledger=await harness.snapshot(UsageDoc,root.id,{});const expectedCalls=scenario==='deferred'?1:2;if(calls!==expectedCalls||polls!==(scenario==='deferred'?1:0)||ledger.models['p/m'].totalTokens!==(scenario==='deferred'?3:6)||reports.length)throw Error(JSON.stringify({scenario,calls,polls,ledger,reports}));results.push({scenario,calls,polls,tokens:ledger.models['p/m'].totalTokens});}finally{await harness.close({})}}globalThis.generationProgressScenarios=results;
    , "native-generation-repeated-retry-deferred") catch |err| {
        std.debug.print("Generation scenarios: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 generation public sequential parallel and unavailable tool rounds" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-generation-round-policies-runtime.txt"), "native-generation-round-policies") catch |err| {
        std.debug.print("Generation round policies: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
}

test "native durable v2 generation queued submission withdrawal and closing waiters match Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-submission-lifecycle-runtime.txt"), "native-submission-lifecycle") catch |err| {
        std.debug.print("Submission lifecycle {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "missing" });
        return err;
    };
    engine.freeValue(result);
}

fn exerciseGenerationOwnership(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    return exerciseGenerationOwnershipWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseGenerationOwnershipWithEngine(engine: *engine_mod.Engine) !void {
    engine.native_io = std.testing.io;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try @import("extensions/native_durable.zig").install(engine);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    var tokens = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    defer for (tokens) |value| engine.freeValue(value);
    inline for (.{ "LiveDoc", "UsageDoc", "ToolTask", "AssistantEntry", "ToolResultEntry" }, 0..) |key, index| tokens[index] = try vm.get(engine, exports, key);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-tool-round-runtime.txt"), "allocation-generation-tool-round", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    for ([_][]const u8{ "parallel", "sequential", "unavailable" }) |scenario| {
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0], tokens[1], tokens[2], tokens[3], tokens[4] };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 5;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "request", "message", "calls" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_tools.zig").start(engine, &captured, values[0], values[1], values[2], values[3], values[4]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
    }
    const prepare_factory = try engine.eval(@embedFile("extensions/fixtures/durable-generation-prepare-runtime.txt"), "allocation-generation-prepare", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prepare_factory);
    const system = try vm.get(engine, exports, "SystemEntry");
    defer engine.freeValue(system);
    for ([_][]const u8{ "plain", "section", "env-error" }) |scenario| {
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, system };
        const fixture = try engine.checked(c.JS_Call(engine.context, prepare_factory, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "runtime", "context", "task" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        const pending = try @import("extensions/native_durable_generation_task.zig").prepare(engine, &captured, values[0], values[1], tokens[0], values[2]);
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
    }
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const stream_factory = try engine.eval(@embedFile("extensions/fixtures/durable-generation-stream-protocol-runtime.txt"), "allocation-generation-stream", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(stream_factory);
    const model = try vm.object(engine);
    defer engine.freeValue(model);
    const messages = try vm.array(engine);
    defer engine.freeValue(messages);
    const stream_options = try vm.object(engine);
    defer engine.freeValue(stream_options);
    for ([_][]const u8{ "async", "sync", "sync-promise", "body-close", "body-return-reject" }) |scenario| {
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, tokens[0] };
        const fixture = try engine.checked(c.JS_Call(engine.context, stream_factory, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        const runtime = try vm.get(engine, fixture, "runtime");
        defer engine.freeValue(runtime);
        const context = try vm.get(engine, fixture, "context");
        defer engine.freeValue(context);
        const generation = engine.native_allocation_generation;
        const pending = try @import("extensions/native_durable_generation_stream.zig").run(engine, &captured, runtime, model, messages, stream_options, c.JS_NewInt32(engine.context, 1), context, tokens[0]);
        defer engine.freeValue(pending);
        if (engine.awaitValue(pending)) |result| engine.freeValue(result) else |err| {
            if (engine.native_allocation_generation != generation or !std.mem.startsWith(u8, scenario, "body-")) return err;
        }
    }
    const storage = try @import("extensions/native_durable.zig").memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try @import("extensions/native_durable.zig").sessionObject(engine, storage);
    defer engine.freeValue(session);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    const handle = try @import("extensions/native_durable_submission_handle.zig").handle(engine, session, options, c.JS_NewInt32(engine.context, 1));
    defer engine.freeValue(handle);
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, handle));
    defer engine.freeValue(prototype);
    const constructor = try vm.get(engine, prototype, "constructor");
    defer engine.freeValue(constructor);
    const host = try engine.eval("({status:()=>({done:true}),wait:()=>Promise.resolve({done:true}),abort:()=>Promise.resolve('settled')})", "allocation-submission-host", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(host);
    var args = [_]c.JSValue{ c.JS_NewInt32(engine.context, 7), host };
    const delegated = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
    defer engine.freeValue(delegated);
    inline for (.{ "status", "wait", "abort" }) |key| {
        const pending = try vm.invoke(engine, delegated, key, &.{options});
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        defer engine.freeValue(result);
    }
}

test "native durable v2 generation tool continuations and submission private state release allocation failures" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseGenerationOwnership(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseGenerationOwnership(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("Generation ownership leak at {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

test "native durable v2 generation stream iteration protocol matches actual Source" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var captured = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer captured.deinit(engine);
    const token = try vm.object(engine);
    defer engine.freeValue(token);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-generation-stream-protocol-runtime.txt"), "stream-protocol-factory", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-stream-protocol-original.json"));
    defer source.deinit();
    const model = try engine.eval("({id:'m'})", "protocol-model", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(model);
    const messages = try vm.array(engine);
    defer engine.freeValue(messages);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var args = [_]c.JSValue{ name, token };
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(fixture);
        const runtime = try vm.get(engine, fixture, "runtime");
        defer engine.freeValue(runtime);
        const context = try vm.get(engine, fixture, "context");
        defer engine.freeValue(context);
        var result_value = c.pi_js_undefined();
        defer engine.freeValue(result_value);
        var failure = c.pi_js_undefined();
        defer engine.freeValue(failure);
        const pending = try @import("extensions/native_durable_generation_stream.zig").run(engine, &captured, runtime, model, messages, options, c.JS_NewInt32(engine.context, 1), context, token);
        defer engine.freeValue(pending);
        if (engine.awaitValue(pending)) |value| result_value = value else |err| {
            if (err != error.JavaScriptException) return err;
            failure = c.JS_DupValue(engine.context, engine.captured_exception orelse return err);
        }
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{ result_value, failure });
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer std.testing.allocator.free(text);
        var actual = try json.Owned.parse(std.testing.allocator, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("Stream protocol {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}

test "native durable v2 generation public blocking background and manual compaction with reset" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-generation-compaction-runtime.txt"), "native-generation-real-compaction") catch |err| {
        std.debug.print("Generation compaction: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try vm.get(engine, global, "generationCompactionRows");
    defer engine.freeValue(rows);
    const text = try engine.stringify(rows);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-generation-compaction-original.json"));
    defer source.deinit();
    try std.testing.expect(json.equal(source.value.object.get("rows").?, actual.value));
}

test "native durable v2 generation transaction scans retain source order bounds cursors and lifecycle" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 30000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-transaction-source-query-runtime.txt"), "native-transaction-source-query") catch |err| {
        std.debug.print("Transaction source query: {s}\n", .{engine.last_error orelse "missing"});
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try vm.get(engine, global, "transactionSourceQueryRows");
    defer engine.freeValue(rows);
    const text = try engine.stringify(rows);
    defer std.testing.allocator.free(text);
    var actual = try json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/durable-transaction-source-query-original.json"));
    defer source.deinit();
    if (!json.equal(source.value.object.get("rows").?, actual.value)) std.debug.print("Source query mismatch: {s}\n", .{text});
    try std.testing.expect(json.equal(source.value.object.get("rows").?, actual.value));
}

fn exerciseSourceQueryOwnership(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    try @import("extensions/native_durable.zig").install(engine);
    // The captured upstream program creates pending tasks but never resumes the
    // scheduler, so allocation failure counters remain on this owner thread.
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-transaction-source-query-runtime.txt"), "allocation-source-query") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
}

test "native durable v2 generation source query snapshots release every failed owner allocation" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseSourceQueryOwnership(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseSourceQueryOwnership(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("Source query ownership leak at {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

test "native durable v2 generation new publication refills an enabled scheduler after its empty driver stopped" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 2000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_durable.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const prepared = try engine.evalModule(@embedFile("extensions/fixtures/durable-generation-empty-refill-setup.txt"), "native-empty-refill-setup");
    engine.freeValue(prepared);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const harness = try vm.get(engine, global, "emptyRefillHarness");
    defer engine.freeValue(harness);
    const host = try @import("extensions/native_durable_harness.zig").state(engine, harness);
    const manager = try @import("extensions/native_durable_tasks.zig").getManager(engine, host.session);
    try manager.@"resume"();
    const deadline = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 2000;
    while (manager.thread != null) {
        _ = try engine.native_durable_control_pump.?(engine);
        if (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() >= deadline) return error.EmptyDriverDidNotStop;
        if (manager.thread != null) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    }
    try std.testing.expectEqual(@as(usize, 0), manager.last_count);
    const result = engine.evalModule(@embedFile("extensions/fixtures/durable-generation-empty-refill-run.txt"), "native-empty-refill-after-commit") catch |err| {
        std.debug.print("Enabled empty refill {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "missing" });
        return err;
    };
    engine.freeValue(result);
}
