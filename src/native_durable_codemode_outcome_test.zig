//! Raw actual upstream deliveries and nested records were captured first with
//! real CodemodeSandbox workers, MemoryStorage, Harness and strict tool schemas.
const std = @import("std");
const em = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const mapping = @import("extensions/native_durable_codemode_outcome.zig");
const c = em.c;
test "native durable CodeMode actual148622 nested outcome16 preserves raw values and own field presence" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try durable.install(engine);
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-148622-codemode-outcomes-source.json"));
    defer source.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    for (source.value.array.items) |row| {
        const result = try durable.jsValue(engine, try json.required(row, "result"));
        defer engine.freeValue(result);
        const name = try sdk.text(engine, "echo");
        defer engine.freeValue(name);
        const actual = try mapping.fromNested(engine, name, (try json.required(row, "structured")).bool, result);
        defer engine.freeValue(actual);
        const expected = try durable.jsValue(engine, try json.required(row, "expected"));
        defer engine.freeValue(expected);
        if (c.JS_DefinePropertyValueStr(engine.context, global, "actualOutcome", c.JS_DupValue(engine.context, actual), c.JS_PROP_C_W_E) < 0 or c.JS_DefinePropertyValueStr(engine.context, global, "expectedOutcome", c.JS_DupValue(engine.context, expected), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        const verified = engine.eval(
            \\{const observed={outcome:actualOutcome,outcomeKeys:Object.keys(actualOutcome),hasValue:Object.hasOwn(actualOutcome,'value'),valueType:typeof actualOutcome.value};
            \\if(JSON.stringify(observed)!==JSON.stringify(expectedOutcome))throw Error(JSON.stringify({observed,expected:expectedOutcome}));}
        , "native-codemode-outcome-source", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
            std.debug.print("CodeMode outcome row={s} failure={s}: {s}\n", .{ (try json.required(row, "name")).string, @errorName(err), engine.last_error orelse "no VM diagnostic" });
            return err;
        };
        engine.freeValue(verified);
    }
}
