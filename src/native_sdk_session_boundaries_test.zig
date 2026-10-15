//! Source 5ab actual boundary bodies and real nested pipeline composition.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-sdk-boundaries"});
    try @import("extensions/native_crypto_random.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const api = try scope.object();
    try sdk.install(engine, api);
    try scope.put(api, "NestedToolCallRunner", try scope.own(try @import("extensions/native_nested_tool_calls.zig").constructor(engine)));
    try scope.put(api, "NestedCallRecorder", try scope.own(try @import("extensions/native_nested_call_recorder.zig").constructor(engine)));
    try scope.put(api, "runToolCall", try scope.own(try @import("extensions/native_agent_single_tool.zig").create(engine)));
    try scope.put(api, "convertToLlm", try scope.own(try @import("extensions/native_sdk_messages.zig").create(engine)));
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, api);
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_boundaries.zig").install(engine, prototype, api);
    try scope.put(api, "prototype", prototype);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "boundaryAPI", api);
}
test "native SDK boundaries actual latest Source differential and real nested collaborators" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-boundaries-5ab.input.txt"), "sdk-session-boundaries-5ab.mjs") catch |err| {
        std.debug.print("Boundary fixture failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "boundaryRows"));
    defer std.testing.allocator.free(actual);
    const expected_bytes = @embedFile("extensions/fixtures/sdk-session-boundaries-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "sdk-session-boundaries-5ab.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer std.testing.allocator.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual boundary rows:\n{s}\nExpected:\n{s}\n", .{ actual, raw });
        return error.NativeBoundaryDifferentialMismatch;
    }
}

test "native SDK boundaries pending extension emit retains session and releases complete graph" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\(()=>{const s=Object.assign(Object.create(boundaryAPI.prototype),{agent:{toolExecution:'parallel'},_nestedToolCalls:undefined,_getCallableTools(){return[]},_findLastAssistantMessage(){return undefined},_extensionRunner:{emit(event){if(event.type==='tool_execution_start')return new Promise(resolve=>{globalThis.boundaryGcRelease=resolve})}},_emit(event){boundaryGcEvents.push(event.type)}});globalThis.boundaryGcEvents=[];globalThis.boundaryGcWeak=new WeakRef(s);globalThis.boundaryGcPending=s._executeNestedToolCall('parent','echo',{},{});})();export const ready=true;
    , "native-boundary-gc-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("boundaryGcWeak.deref()!==undefined&&typeof boundaryGcRelease==='function'", "native-boundary-gc-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const completed = try engine.evalModule(
        \\boundaryGcRelease();const result=await boundaryGcPending;if(!result.isError||result.result.content[0].text!=='No assistant message issued this call'||JSON.stringify(boundaryGcEvents)!==JSON.stringify(['tool_execution_start','tool_execution_end']))throw Error('nested pending graph lost');delete globalThis.boundaryGcPending;delete globalThis.boundaryGcRelease;delete globalThis.boundaryGcEvents;export const complete=true;
    , "native-boundary-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("boundaryGcWeak.deref()===undefined", "native-boundary-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}

test "native SDK boundaries pending raw emit rejection releases session and skips listener" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\(()=>{const s=Object.assign(Object.create(boundaryAPI.prototype),{_nestedToolCalls:undefined,_extensionRunner:{emit(){return new Promise((resolve,reject)=>{globalThis.boundaryGcReject=reject})}},_emit(){throw Error('listener must not run')}});globalThis.boundaryGcWeak=new WeakRef(s);globalThis.boundaryGcReason={raw:'owned'};globalThis.boundaryGcPending=s._executeNestedToolCall('parent','echo',{},{});})();export const ready=true;
    , "native-boundary-gc-reject-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(!boundaryGcWeak.deref())throw Error('lost pending receiver');boundaryGcReject(boundaryGcReason);let caught=false;try{await boundaryGcPending}catch(error){if(error!==boundaryGcReason)throw Error('raw reason replaced');caught=true}if(!caught)throw Error('missing rejection');delete globalThis.boundaryGcPending;delete globalThis.boundaryGcReject;delete globalThis.boundaryGcReason;export const complete=true;
    , "native-boundary-gc-reject-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("boundaryGcWeak.deref()===undefined", "native-boundary-gc-reject-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}
