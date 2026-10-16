//! Prepared source-contract regressions. Unrun; no captured Source golden.
const std = @import("std");
const em = @import("extensions/engine.zig");
const host = @import("extensions/native_durable_host_inputs.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn reentrantOrdinary(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.checked(c.JS_Throw(context, c.JS_DupValue(context, data[0]))) catch return engine.throwCaptured();
    unreachable;
}
fn freshAllocation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}

test "8efd captured host supplier calls bare each time and preserves raw throw" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const supplier = try engine.eval(
        \\globalThis.hostProbe={current:{id:1},calls:0,receivers:[],reason:{original:true},fail:false};
        \\(function(){'use strict';hostProbe.calls++;hostProbe.receivers.push(this===undefined);if(hostProbe.fail)throw hostProbe.reason;return hostProbe.current})
    , "8efd-host-supplier-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(supplier);
    const first = try host.resolve(engine, supplier);
    defer engine.freeValue(first);
    const change = try engine.eval("hostProbe.current={id:2}", "8efd-host-replace-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(change);
    const second = try host.resolve(engine, supplier);
    defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, second, change));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first, second));
    const plain = try host.resolve(engine, first);
    defer engine.freeValue(plain);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, plain, first));
    const cause = try engine.eval("hostProbe.fail=true;hostProbe.reason", "8efd-host-throw-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cause);
    try std.testing.expectError(error.JavaScriptException, host.resolve(engine, supplier));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, cause, engine.captured_exception.?));
    const checked = try engine.eval("if(hostProbe.calls!==3||hostProbe.receivers.some(value=>!value))throw Error('supplier call contract');true", "8efd-host-call-contract", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
}

test "8efd real tool API retains live models and per-attempt env getters without eager read" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const state = try engine.eval(
        \\globalThis.toolHostProbe={current:{id:1},reads:0};
        \\({runtime:{taskId:1,conversationId:2,registry:{},agent(){},get models(){if(this!==toolHostProbe.runtime)throw Error('runtime receiver');toolHostProbe.reads++;return toolHostProbe.current}},call:{id:'call'}})
    , "8efd-tool-host-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(state);
    const runtime = try sdk.get(engine, state, "runtime");
    defer engine.freeValue(runtime);
    const probe = try engine.eval("toolHostProbe", "8efd-tool-probe", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(probe);
    try sdk.put(engine, probe, "runtime", c.JS_DupValue(engine.context, runtime));
    const api = try @import("extensions/native_durable_tool_api.zig").create(engine, state, .{ .retain = .head }, .{ .commit = c.pi_js_undefined(), .create_task = c.pi_js_undefined(), .execute_tool = c.pi_js_undefined() });
    defer engine.freeValue(api);
    try sdk.put(engine, probe, "api", c.JS_DupValue(engine.context, api));
    const checked = try engine.eval(
        \\if(toolHostProbe.reads!==0||toolHostProbe.api.env!==undefined)throw Error('eager host read');
        \\const first=toolHostProbe.api.models;toolHostProbe.current={id:2};const second=toolHostProbe.api.models;
        \\if(first===second||second!==toolHostProbe.current||toolHostProbe.reads!==2)throw Error('models snapshot');
        \\for(const name of ['models','env']){const d=Object.getOwnPropertyDescriptor(toolHostProbe.api,name);if(typeof d.get!=='function'||d.get.name!=='get '+name||!d.enumerable||!d.configurable||'value'in d)throw Error('getter descriptor')}
        \\true
    , "8efd-tool-getter-contract", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    const caught = try engine.eval(
        \\const reason={ordinary:true};Object.defineProperty(toolHostProbe.runtime,'models',{get(){throw reason}});
        \\try{toolHostProbe.api.models;throw Error('missing throw')}catch(error){if(error!==reason)throw error}true
    , "8efd-tool-caught-getter-contract", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(caught);
    try std.testing.expect(engine.captured_exception == null);
}

test "8efd retention restores prior cause after actual native supplier ordinary capture" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const prior = try engine.eval("({operation:true})", "8efd-prior-operation-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prior);
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, prior))) catch {};
    const message = if (engine.last_error) |value| try std.testing.allocator.dupe(u8, value) else null;
    defer if (message) |value| std.testing.allocator.free(value);
    const ordinary = try engine.eval("({bookkeeping:true})", "8efd-bookkeeping-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(ordinary);
    var data = [_]c.JSValue{ordinary};
    const supplier = try engine.checked(c.JS_NewCFunctionData2(engine.context, reentrantOrdinary, "nativeRetentionSupplier", 0, 0, data.len, &data));
    defer engine.freeValue(supplier);
    try std.testing.expectEqual(@as(f64, 600_000), try @import("extensions/native_durable_document_retention.zig").readCapturedSettings(engine, supplier));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, prior, engine.captured_exception.?));
    if (message) |value| try std.testing.expectEqualStrings(value, engine.last_error.?) else try std.testing.expect(engine.last_error == null);
}

test "8efd retention exact fresh fatal overrides prior cause without replacement" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const prior = try engine.eval("({operation:true})", "8efd-prior-fatal-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(prior);
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, prior))) catch {};
    const supplier = try engine.checked(c.JS_NewCFunction(engine.context, freshAllocation, "nativeRetentionAllocation", 0));
    defer engine.freeValue(supplier);
    try std.testing.expectError(error.JavaScriptException, @import("extensions/native_durable_document_retention.zig").readCapturedSettings(engine, supplier));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.native_allocation_exception.?, engine.captured_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, prior, engine.captured_exception.?));
}
