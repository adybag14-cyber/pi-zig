const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const headers = @import("native_headers.zig");
const c = em.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    errdefer engine.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try headers.install(engine);
    try engine.bindFunction("nativeCollectHeadersFixture", collect, 0);
    const result = try engine.eval(
        \\globalThis.collectHeadersGarbage=async()=>{for(let i=0;i<3;i++){await new Promise(resolve=>setTimeout(resolve,0));nativeCollectHeadersFixture()}await new Promise(resolve=>setTimeout(resolve,0))};
    , "actual-headers-gc-adapter.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    return engine;
}
fn compare(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const expected = @embedFile("fixtures/web-headers-node24.json");
    try js.define(engine, global, "headersSourceRows", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-node24-headers.json")));
    const pending = try engine.evalModule(@embedFile("fixtures/web-headers-node24.input.txt") ++
        \\
        \\if(webHeadersRows.length!==headersSourceRows.rows.length)throw Error('Headers inventory mismatch');
        \\for(let i=0;i<webHeadersRows.length;i++){const actual=webHeadersRows[i],expected=headersSourceRows.rows[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}))}
    , "actual-node24-headers-replay.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}
test "Headers Source189 genuine Node24 descriptors WebIDL live iterators callbacks and actual GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    compare(engine) catch |err| {
        if (engine.last_error) |message| std.debug.print("Headers Source189: {s}\n", .{message});
        return err;
    };
}
test "Headers native helper authentic brand idempotent install and immutable guard" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const first = try js.global(engine, "Headers");
    defer engine.freeValue(first);
    try headers.install(engine);
    const again = try js.global(engine, "Headers");
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, again));
    const record = try engine.eval("({X:'one',other:null})", "headers-init.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(record);
    const value = try headers.fromRecord(engine, record);
    defer engine.freeValue(value);
    try std.testing.expect(headers.isHeaders(engine, value));
    try std.testing.expect(!headers.isHeaders(engine, record));
    try headers.setGuard(engine, value, .immutable);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeHeadersValue", c.JS_DupValue(engine.context, value));
    const result = try engine.eval(
        \\if(!(nativeHeadersValue instanceof Headers)||nativeHeadersValue.get('other')!=='null')throw Error('actual Headers identity/coercion');
        \\for(const method of ['append','set','delete']){let caught;try{nativeHeadersValue[method]('x','changed')}catch(e){caught=e}if(!(caught instanceof TypeError)||caught.message!=='immutable')throw Error('immutable guard '+method)}
        \\if(nativeHeadersValue.get('x')!=='one')throw Error('immutable mutation');
    , "headers-native-helper.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
test "Headers native helper preserves thrown identity without diagnostic ToString before guest catch" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const result = try engine.eval(
        \\let diagnosticCalls=0;const marker={toString(){diagnosticCalls++;nativeCollectHeadersFixture();throw 'diagnostic must not run'}};
        \\const headers=new Headers({x:'one'});const operations=[()=>new Headers({[Symbol.iterator](){throw marker}}),()=>headers.get({toString(){throw marker}}),()=>headers.forEach(()=>{throw marker})];
        \\for(const operation of operations){let caught;try{operation()}catch(error){caught=error}if(caught!==marker)throw Error('Headers replaced original guest throw');if(diagnosticCalls!==0)throw Error('Headers converted original throw before guest catch')}
        \\const original=TypeError.prototype.toString;TypeError.prototype.toString=function(){diagnosticCalls++;nativeCollectHeadersFixture();throw marker};
        \\try{let caught;try{headers.append('bad name','value')}catch(error){caught=error}if(!(caught instanceof TypeError)||!caught.message.includes('invalid header name'))throw Error('Headers replaced its original TypeError');if(diagnosticCalls!==0)throw Error('Headers formatted own TypeError before guest catch')}finally{TypeError.prototype.toString=original}
    , "headers-caught-error-identity.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const engine = try setup(gpa);
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    compare(engine) catch |err| return engine.nativeAllocationError(err, generation);
}
const ownership_script =
    \\const h=new Headers([['X','one'],['Cookie','a=1'],['set-cookie','a=1'],['set-cookie','b=2']]);
    \\h.append('x','two');h.set('y','three');const copy=new Headers(h),i=copy.entries();
    \\i.next();copy.delete('x');copy.append('z','end');i.next();copy.forEach((v,k)=>{if(k==='y')copy.set('y','changed')});
    \\const values=copy.getSetCookie();if(values.length!==2||copy.get('z')!=='end')throw Error('ownership semantic check');
;
fn ownershipOperation(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(ownership_script, "headers-owned-operation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Headers native helper selected actual operation allocation failures release all bytes" {
    var measurement = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const measured_engine = try setup(measurement.allocator());
    const beginning = measurement.alloc_index;
    try ownershipOperation(measured_engine);
    const allocations = measurement.alloc_index - beginning;
    measured_engine.deinit();
    try std.testing.expect(allocations > 0);
    try std.testing.expectEqual(measurement.allocated_bytes, measurement.freed_bytes);
    const offsets = [_]usize{ 0, allocations / 4, allocations / 2, allocations * 3 / 4, allocations - 1 };
    for (offsets) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try setup(failing.allocator());
        failing.fail_index = failing.alloc_index + offset;
        const result = ownershipOperation(engine);
        engine.deinit();
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectError(error.OutOfMemory, result);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        std.debug.print("Headers operation allocation offset={d}/{d} induced=true all-bytes-freed=true\n", .{ offset, allocations });
    }
}
test "Headers full-engine exhaustive ownership OOM Source189" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
