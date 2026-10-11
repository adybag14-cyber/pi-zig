//! Actual latest upstream compaction contract, frozen before the native port.
const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = engine_mod.c;

test "native durable actual 89 compaction failure public contract preserves real blocking and events" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-89-compaction-failure-program.txt"), "actual-89-compaction-failure") catch |err| {
        std.debug.print("Actual 89 compaction failure {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        if (engine.captured_exception) |reason| {
            // Read the existing stack without checked()/captureException(), so
            // a diagnostic accessor failure cannot replace the original cause.
            const stack = c.JS_GetPropertyStr(engine.context, reason, "stack");
            if (c.JS_IsException(stack)) {
                engine.freeValue(c.JS_GetException(engine.context));
            } else {
                defer engine.freeValue(stack);
                var length: usize = 0;
                if (c.JS_ToCStringLen(engine.context, &length, stack)) |bytes| {
                    defer c.JS_FreeCString(engine.context, bytes);
                    std.debug.print("Actual 89 captured exception stack: {s}\n", .{bytes[0..length]});
                } else engine.freeValue(c.JS_GetException(engine.context));
            }
        }
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "latestCompactionFailureTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-89-compaction-failure-source.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual 89 compaction failure trace: {s}\n", .{encoded});
        return error.SourceCompactionFailureContractMismatch;
    }
}

test "native durable actual 89 compaction failure public contract latest serializer omits thinking" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-89-compaction-serialization-source.json"));
    defer source.deinit();
    const text = @import("extensions/native_durable_compaction_text.zig");
    for ((try json.required(source.value, "rows")).array.items) |row| {
        const messages = try durable.jsValue(engine, try json.required(row, "messages"));
        defer engine.freeValue(messages);
        const result = try text.serializeConversation(engine, messages);
        defer engine.freeValue(result);
        const actual = try engine.toString(result);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(try json.asString(try json.required(row, "durable")), actual);
    }
    const messages = try engine.eval("([{role:'assistant',content:[{type:'thinking',get thinking(){throw Error('omitted getter was read')}}]}])", "latest-omitted-thinking-getter", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(messages);
    const result = try text.serializeConversation(engine, messages);
    defer engine.freeValue(result);
    const actual = try engine.toString(result);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("", actual);
}

test "native durable actual 89 compaction failure public contract full inspection preserves task fit and public pagination" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const began = std.Io.Clock.real.now(std.testing.io).toMilliseconds();
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-89-inspection-program.txt"), "actual-89-full-inspection") catch |err| {
        std.debug.print("Actual 89 full inspection {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        if (engine.captured_exception) |reason| {
            printInspectionFailure(engine, reason, "exception");
            const cause = c.JS_GetPropertyStr(engine.context, reason, "cause");
            if (c.JS_IsException(cause)) {
                engine.freeValue(c.JS_GetException(engine.context));
            } else {
                defer engine.freeValue(cause);
                printInspectionFailure(engine, cause, "cause");
            }
        }
        return err;
    };
    engine.freeValue(result);
    const ended = std.Io.Clock.real.now(std.testing.io).toMilliseconds();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "latestInspectionTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-89-inspection-source.json"));
    defer expected.deinit();
    // The fixture retains the actual Source wall times. Compare presence and
    // all other fields exactly; separately require native times within this
    // real execution, stable for every repeated observation of the same task.
    try @import("native_durable_inspection_compare.zig").normalize(&actual.value, &expected.value, began, ended);
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual 89 full inspection trace: {s}\n", .{encoded});
        return error.SourceInspectionContractMismatch;
    }
}

fn printInspectionFailure(engine: *engine_mod.Engine, reason: c.JSValue, label: []const u8) void {
    // Failure-only diagnostics never use checked()/captureException(): a user
    // accessor/coercion cannot replace the retained original rejection.
    for ([_][:0]const u8{ "name", "message", "stack" }) |key| {
        const value = c.JS_GetPropertyStr(engine.context, reason, key.ptr);
        if (c.JS_IsException(value)) {
            engine.freeValue(c.JS_GetException(engine.context));
            continue;
        }
        defer engine.freeValue(value);
        var length: usize = 0;
        if (c.JS_ToCStringLen(engine.context, &length, value)) |bytes| {
            defer c.JS_FreeCString(engine.context, bytes);
            std.debug.print("Actual inspection {s}.{s}: {s}\n", .{ label, key, bytes[0..length] });
        } else engine.freeValue(c.JS_GetException(engine.context));
    }
}
