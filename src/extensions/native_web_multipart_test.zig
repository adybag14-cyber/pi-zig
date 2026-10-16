//! Original genuine Source176 multipart/formData observations, never rewritten.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("timers.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try @import("native_web_response.zig").install(engine, try @import("native_web_platform.zig").prepare(&scope));
    return engine;
}
fn replay(engine: *em.Engine) !void {
    const packet = @embedFile("fixtures/web-body-node24.json");
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "originalMultipartPacket", try engine.checked(c.JS_ParseJSON(engine.context, packet.ptr, packet.len, "genuine-body176.json")));
    const pending = try engine.evalModule(@embedFile("fixtures/web-multipart-node24.input.txt") ++
        \\
        \\const names=['Response form urlencoded roundtrip','Response FormData actual multipart roundtrip','Response formData unsupported type'];
        \\const expected=originalMultipartPacket.rows.filter(row=>names.includes(row.name));
        \\if(expected.length!==3||webMultipartRows.length!==3)throw Error('Multipart Source176 inventory mismatch');
        \\const mismatches=[];for(let i=0;i<expected.length;i++)if(JSON.stringify(webMultipartRows[i])!==JSON.stringify(expected[i]))mismatches.push({index:i,actual:webMultipartRows[i],expected:expected[i]});
        \\if(mismatches.length)throw Error(JSON.stringify({mapped:3,mismatches}));
    , "actual-multipart-Source176-projection.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}
test "Web multipart exact original Source176 roundtrip urlencoded and type error" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    replay(engine) catch |err| {
        if (engine.last_error) |message| std.debug.print("Multipart Source176: {s}\n", .{message});
        return err;
    };
}
const ownership_script =
    \\const data=new FormData();data.append('a','one');data.append('a','é');data.append('file',new File(['owned bytes'],'sample.txt',{type:'text/plain'}));
    \\const response=new Response(data),copy=response.clone(),parsed=await Promise.all([response.formData(),copy.formData()]);
    \\for(const form of parsed){const file=form.get('file');if(!(form instanceof FormData)||!(file instanceof File)||await file.text()!=='owned bytes'||form.getAll('a').join(',')!=='one,é')throw Error('multipart owned graph');}
;
fn ownership(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    const pending = engine.evalModule(ownership_script, "multipart-owned-operation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(settled);
    c.JS_RunGC(engine.runtime);
}
test "Web multipart selected operation OOM retains allocation identity and frees every owner" {
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
        std.debug.print("Web multipart operation allocation offset={d}/{d} all-bytes-freed=true\n", .{ offset, count });
    }
}
