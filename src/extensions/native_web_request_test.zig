//! Strict Request projection of immutable genuine Node24 Body176 rows.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const request = @import("native_web_request.zig");
const c = em.c;
pub fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("timers.zig").install(engine, std.testing.io);
    try request.install(engine);
    return engine;
}
pub fn replay(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const original = @embedFile("fixtures/web-body-node24.json");
    try js.define(engine, global, "requestSourcePacket", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "genuine-node24-Body176.json")));
    const pending = try engine.evalModule(@embedFile("fixtures/web-request-node24.input.txt") ++
        \\
        \\const expectedRequestRows=requestSourcePacket.rows.filter(row=>row.name.startsWith('Request ')||row.name==='global descriptor Request');
        \\if(expectedRequestRows.length!==55||webRequestRows.length!==55||new Set(webRequestRows.map(row=>row.name)).size!==55)throw Error('Request Source176 projection inventory mismatch');
        \\const requestMismatches=[];for(let i=0;i<webRequestRows.length;i++){const actual=webRequestRows[i],expected=expectedRequestRows[i];if(JSON.stringify(actual)!==JSON.stringify(expected))requestMismatches.push({index:i,actual,expected})}
        \\if(requestMismatches.length)throw Error(JSON.stringify({mapped:55,mismatches:requestMismatches}));
    , "actual-node24-request-Source176-projection.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}
test "Request Source176 actual 55 row projection retains all dependency negatives" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    replay(engine) catch |err| {
        if (engine.last_error) |message| std.debug.print("Request Source176: {s}\n", .{message});
        return err;
    };
}
const ownership_script =
    \\const controller=new AbortController(),marker={reason:'owned'},a=new Request('https://example.test/',{method:'POST',body:'owned',headers:[['X','one'],['Set-Cookie','a=1'],['Set-Cookie','b=2']],signal:controller.signal}),b=a.clone();
    \\b.headers.set('x','two');controller.abort(marker);if(!(a instanceof Request)||a.signal===controller.signal||a.signal===b.signal||a.signal.reason!==marker||b.signal.reason!==marker||a.headers.get('x')!=='one'||b.headers.getSetCookie().length!==2)throw Error('Request private owned clone graph');
    \\if((await Promise.all([a.text(),b.text()])).join(',')!=='owned,owned'||!a.bodyUsed||!b.bodyUsed)throw Error('Request independent Body consumption');
;
fn ownership(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    const pending = engine.evalModule(ownership_script, "request-owned-operation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(settled);
    c.JS_RunGC(engine.runtime);
}
test "Request selected operation OOM keeps genuine ownership and diagnostics" {
    var measured = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const baseline = try setup(measured.allocator());
    const first = measured.alloc_index;
    try ownership(baseline);
    const count = measured.alloc_index - first;
    baseline.deinit();
    try std.testing.expect(count > 0);
    try std.testing.expectEqual(measured.allocated_bytes, measured.freed_bytes);
    for ([_]usize{ 0, count / 4, count / 2, count * 3 / 4, count - 1 }) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try setup(failing.allocator());
        failing.fail_index = failing.alloc_index + offset;
        const result = ownership(engine);
        engine.deinit();
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectError(error.OutOfMemory, result);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        std.debug.print("Request operation allocation offset={d}/{d} all-bytes-freed=true\n", .{ offset, count });
    }
}
