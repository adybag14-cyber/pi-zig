const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    try @import("extensions/native_stream.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativePiAiModuleUnavailable;
    try sdk.put(engine, global, "__subject", c.JS_DupValue(engine.context, namespace));
}
fn evaluate(engine: *em.Engine, source: []const u8, name: [:0]const u8) !c.JSValue {
    return engine.evalModule(source, name) catch |err| {
        std.debug.print("live EventStream: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
}
test "native live EventStream matches actual ae7 Source27 surface queue metadata and borrowed receiver traces" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const module = try evaluate(engine, @embedFile("extensions/fixtures/event-stream-live-source27.input.txt"), "event-stream-live-source27.mjs");
    defer engine.freeValue(module);
    const rows = try js.get(engine, module, "rows");
    defer engine.freeValue(rows);
    const actual = try engine.stringify(rows);
    defer engine.gpa.free(actual);
    const original = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/event-stream-live-ae7-source27.json"), .{});
    defer original.deinit();
    const captured = original.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 27), captured.len);
    const expected = try std.json.Stringify.valueAlloc(std.testing.allocator, captured[0..26], .{});
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
    c.JS_RunGC(engine.runtime);
}
test "native live EventStream actual host GC checkpoints retain wait local across yield and release after return" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try evaluate(engine,
        \\let release;const receiver={queue:{length:0},done:false,waiting:{enqueue(resolve){release=resolve}}};globalThis.__gcIterator=__subject.EventStream.prototype[Symbol.asyncIterator].call(receiver);const pending=__gcIterator.next();let value={value:'event',done:false};globalThis.__gcWeak=new WeakRef(value);release(value);release=null;value=null;await pending;export const ready=true;
    , "event-stream-local-gc-prepare.mjs");
    engine.freeValue(prepared);
    // Each eval/await returns through Engine.finishJob: these are actual host
    // job checkpoints, not a synthetic microtask count or duration workaround.
    c.JS_RunGC(engine.runtime);
    const held = try evaluate(engine, "globalThis.__gcHeld=__gcWeak.deref()!==undefined;await __gcIterator.return();export const done=true;", "event-stream-local-gc-return.mjs");
    engine.freeValue(held);
    c.JS_RunGC(engine.runtime);
    const checked = try evaluate(engine, "export const trace=[['heldAcrossYield',__gcHeld],['releasedAfterReturn',__gcWeak.deref()===undefined]];delete globalThis.__gcIterator;delete globalThis.__gcWeak;delete globalThis.__gcHeld;", "event-stream-local-gc-check.mjs");
    defer engine.freeValue(checked);
    const trace = try js.get(engine, checked, "trace");
    defer engine.freeValue(trace);
    const actual = try engine.stringify(trace);
    defer engine.gpa.free(actual);
    const original = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/event-stream-live-ae7-source27.json"), .{});
    defer original.deinit();
    const expected = try std.json.Stringify.valueAlloc(std.testing.allocator, original.value.object.get("rows").?.array.items[26].object.get("trace").?, .{});
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
    c.JS_RunGC(engine.runtime);
}
test "native live EventStream every host allocation retains ownership and original tagged OOM" {
    const Probe = struct {
        fn check(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = evaluate(engine, "const stream=new __subject.AssistantMessageEventStream(),message={role:'assistant',content:[],timestamp:5000000000000};for(let i=0;i<128;i++)stream.push({type:'text_delta',delta:String(i),partial:message});stream.push({type:'done',message});if(await stream.result()!==message)throw Error('result');let count=0;for await(const event of stream)count++;if(count!==129)throw Error('long producer');export const done=true;", "event-stream-live-host-oom.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.check, .{});
}
comptime {
    _ = @import("native_node_function_exception_test.zig");
    _ = @import("native_async_generator_test.zig");
    _ = @import("native_agent_loop_test.zig");
}
