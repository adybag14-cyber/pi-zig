//! Response-only projection against the immutable genuine Node24 Body176 packet.
//! The graph bootstrap calls actual native stream classes, never fixture doubles.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const response = @import("native_web_response.zig");
const body = @import("native_web_body.zig");
const streams = @import("native_readable_stream.zig");
const blob = @import("native_web_blob.zig");
const c = em.c;
fn disturbed(scope: *Scope, _: c.JSValue, stream: c.JSValue) anyerror!bool {
    return streams.isDisturbed(scope.engine, stream);
}
fn errored(scope: *Scope, _: c.JSValue, stream: c.JSValue) anyerror!bool {
    return streams.isErrored(scope.engine, stream);
}
fn close(scope: *Scope, _: c.JSValue, controller: c.JSValue) anyerror!void {
    return streams.closeController(scope.engine, controller);
}
fn fromBytes(engine: *em.Engine, _: c.JSValue, bytes: c.JSValue) anyerror!c.JSValue {
    return streams.fromBytes(engine, bytes);
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
pub fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    errdefer engine.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_url.zig").install(engine);
    try @import("abort_signal.zig").install(engine);
    try @import("native_web_form_data.zig").install(engine);
    try streams.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const readable = try scope.global("ReadableStream");
    try body.install(engine, .{ .bindings = readable, .constructor = readable, .is_disturbed = disturbed, .is_errored = errored, .close_controller = close });
    try blob.bindStreams(engine, .{ .owner = readable, .create = fromBytes });
    const has_instance = try scope.own(try js.getKey(engine, try scope.get(try scope.global("Function"), "prototype"), try scope.get(try scope.global("Symbol"), "hasInstance")));
    try response.install(engine, .{ .has_instance = has_instance, .readable = readable, .blob = try scope.global("Blob"), .form_data = try scope.global("FormData"), .url_params = try scope.global("URLSearchParams"), .abort_signal = try scope.global("AbortSignal"), .request = c.pi_js_undefined() });
    try engine.bindFunction("nativeCollectResponseFixture", collect, 0);
    const result = try engine.eval(
        \\globalThis.collectWebBodyGarbage=async()=>{for(let i=0;i<3;i++){await new Promise(resolve=>setTimeout(resolve,0));nativeCollectResponseFixture()}await new Promise(resolve=>setTimeout(resolve,0))};
    , "actual-response-gc-adapter.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    return engine;
}
pub fn replay(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const expected = @embedFile("fixtures/web-body-node24.json");
    try js.define(engine, global, "responseSourcePacket", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "genuine-node24-Body176.json")));
    const pending = try engine.evalModule(@embedFile("fixtures/web-response-node24.input.txt") ++
        \\
        \\const expectedResponseRows=responseSourcePacket.rows.filter(row=>row.name.startsWith('Response ')||row.name==='global descriptor Response'||row.name==='actual GC retained body independent Response lifetime'||row.name==='actual GC released Response body graph');
        \\if(expectedResponseRows.length!==114||webResponseRows.length!==114||new Set(webResponseRows.map(row=>row.name)).size!==114)throw Error('Response Source176 projection inventory mismatch');
        \\for(let i=0;i<webResponseRows.length;i++){const actual=webResponseRows[i],expected=expectedResponseRows[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}))}
    , "actual-node24-response-Source176-projection.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}
test "Response Source176 actual 114 row projection descriptors WebIDL Body and GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    replay(engine) catch |err| {
        if (engine.last_error) |message| std.debug.print("Response Source176: {s}\n", .{message});
        return err;
    };
}
const ownership_script =
    \\const target=function Target(){};target.prototype=null;const constructed=Reflect.construct(Response,[null],target);if(Object.getPrototypeOf(constructed)!==Object.prototype)throw Error('Response newTarget intrinsic fallback');
    \\class DerivedResponse extends Response{};const derived=new DerivedResponse(null,{status:203});if(!(derived instanceof Response)||derived.status!==203)throw Error('Response subclass brand');
    \\for(const field of ['status','headers']){let failure;try{Object.getOwnPropertyDescriptor(Response.prototype,field).get.call(Object.create(Response.prototype))}catch(e){failure=e}if(!(failure instanceof TypeError)||!failure.message.includes(field==='headers'?'#headers':'#state'))throw Error('Response private field '+field)}
    \\const response=new Response('{"owned":true}',{status:201,statusText:'Created',headers:[['X','one'],['Set-Cookie','a=1'],['Set-Cookie','b=2']]});
    \\const copy=response.clone();copy.headers.set('X','copy');
    \\if(response.headers.get('x')!=='one'||copy.status!==201||copy.statusText!=='Created'||copy.headers.getSetCookie().length!==2)throw Error('Response clone owned fields');
    \\const result=await Promise.all([response.json(),copy.text()]);
    \\if(result[0].owned!==true||result[1]!=='{"owned":true}'||!response.bodyUsed||!copy.bodyUsed)throw Error('Response independent Body consumers');
    \\const locked=new Response('locked'),reader=locked.body.getReader();if(locked.bodyUsed)throw Error('lock alone disturbed body');reader.releaseLock();if(await locked.text()!=='locked')throw Error('release lock');
    \\const json=Response.json({value:'native'});if(json.headers.get('content-type')!=='application/json'||(await json.json()).value!=='native')throw Error('Response static JSON');
    \\const networkError=Response.error();if(networkError.status!==0||networkError.ok||networkError.type!=='error'||networkError.body!==null)throw Error('Response network error');
    \\let immutable=false;try{networkError.headers.set('x','bad')}catch(e){immutable=e instanceof TypeError&&e.message==='immutable'}if(!immutable)throw Error('Response immutable headers');
;
fn ownershipOperation(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    const pending = engine.evalModule(ownership_script, "response-owned-operation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(settled);
    c.JS_RunGC(engine.runtime);
}
test "Response native actual identity transport immutable headers and source ownership" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try ownershipOperation(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bytes = try scope.own(try engine.eval("new Uint8Array([65,66])", "response-owned-bytes.js", c.JS_EVAL_TYPE_GLOBAL));
    const pairs = try scope.own(try engine.eval("[['X','one'],['Set-Cookie','a=1'],['Set-Cookie','b=2']]", "response-owned-headers.js", c.JS_EVAL_TYPE_GLOBAL));
    const value = try scope.own(try response.fromTransport(engine, .{ .body = bytes, .status = 202, .status_text = try scope.text("Accepted"), .headers = pairs, .url = try scope.text("https://example.test/path#fragment"), .redirected = true }));
    try std.testing.expect(response.isResponse(engine, value));
    try std.testing.expect(!response.isResponse(engine, pairs));
    try js.define(engine, try scope.own(c.JS_GetGlobalObject(engine.context)), "nativeTransportResponse", c.JS_DupValue(engine.context, value));
    const pending = try engine.evalModule(
        \\if(!(nativeTransportResponse instanceof Response)||!(nativeTransportResponse.headers instanceof Headers)||!(nativeTransportResponse.body instanceof ReadableStream))throw Error('transport genuine graph');
        \\if(nativeTransportResponse.status!==202||nativeTransportResponse.statusText!=='Accepted'||!nativeTransportResponse.ok||!nativeTransportResponse.redirected||nativeTransportResponse.url!=='https://example.test/path')throw Error('transport metadata');
        \\if(nativeTransportResponse.headers.getSetCookie().length!==2)throw Error('transport raw duplicate headers');
        \\const copy=nativeTransportResponse.clone();let immutable=false;try{copy.headers.append('x','bad')}catch(e){immutable=e instanceof TypeError&&e.message==='immutable'}if(!immutable)throw Error('transport clone guard');
        \\if((await Promise.all([nativeTransportResponse.text(),copy.text()])).join(',')!=='AB,AB')throw Error('transport owned Body');
    , "actual-response-transport.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}
test "Response native selected operation OOM preserves ownership" {
    var measured = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const measured_engine = try setup(measured.allocator());
    const beginning = measured.alloc_index;
    try ownershipOperation(measured_engine);
    const allocations = measured.alloc_index - beginning;
    measured_engine.deinit();
    try std.testing.expect(allocations > 0);
    try std.testing.expectEqual(measured.allocated_bytes, measured.freed_bytes);
    for ([_]usize{ 0, allocations / 4, allocations / 2, allocations * 3 / 4, allocations - 1 }) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try setup(failing.allocator());
        failing.fail_index = failing.alloc_index + offset;
        const result = ownershipOperation(engine);
        engine.deinit();
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectError(error.OutOfMemory, result);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        std.debug.print("Response operation allocation offset={d}/{d} induced=true all-bytes-freed=true\n", .{ offset, allocations });
    }
}
