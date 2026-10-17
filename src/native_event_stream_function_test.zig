//! Prepared real-VM controls. C proposal is uncomposed; nothing executed here.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const core = @import("extensions/native_event_stream_core.zig");
const fatal = @import("extensions/native_promise_executor_fatal.zig");
const functions = @import("extensions/native_node_function.zig");
fn fixture(s: *Scope) !c.JSValue {
    const constructor = try s.own(try core.constructor(s.engine));
    const global = try s.own(c.JS_GetGlobalObject(s.engine.context)); try s.put(global, "ActualEventStream", constructor); return constructor;
}
test "native EventStream function actual VM class properties and lazy receiver" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit(); _ = try fixture(&s);
    const original = try s.own(try engine.eval("(async function*(){})", "actual-vm-generator-function.js", c.JS_EVAL_TYPE_GLOBAL));
    const actual = try s.own(try engine.eval("ActualEventStream.prototype[Symbol.asyncIterator]", "actual-native-generator-function.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(c.JS_GetClassID(original), c.JS_GetClassID(actual));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, actual));
    const checked = try s.own(try engine.evalModule("const fn=ActualEventStream.prototype[Symbol.asyncIterator],d=Object.getOwnPropertyDescriptor(fn,'prototype');if(d.enumerable||d.configurable||!d.writable||fn.name!=='[Symbol.asyncIterator]'||fn.length!==0)throw Error('metadata');let entered=false;const iterator=fn.call({get queue(){entered=true;return{length:0}},done:true});if(entered)throw Error('early body');await iterator.next();if(!entered)throw Error('no body');export const done=true;", "native-generator-function-invariants.mjs")); _ = checked;
}
test "native EventStream function live own prototype and borrowed input survive GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit(); _ = try fixture(&s);
    const prepared = try s.own(try engine.eval("(()=>{const f=ActualEventStream.prototype[Symbol.asyncIterator],p=f.prototype;f.prototype={owned:true};globalThis.ownedIterator=f.call({queue:{length:0},done:true});if(Object.getPrototypeOf(ownedIterator)!==f.prototype)throw Error('live proto');f.prototype=1;globalThis.fallbackIterator=f.call({queue:{length:0},done:true});if(Object.getPrototypeOf(fallbackIterator)!==Object.getPrototypeOf(p))throw Error('fallback');f.prototype=p;return true})()", "native-generator-live-prototype.js", c.JS_EVAL_TYPE_GLOBAL)); _ = prepared;
    c.JS_RunGC(engine.runtime);
    _ = try s.own(try engine.evalModule("if(!(await ownedIterator.next()).done||!(await fallbackIterator.next()).done)throw Error('retained receiver');export const done=true;", "native-generator-root-lifetime.mjs"));
}
var observed: ?c.JSValue = null;
var callback_count: usize = 0;
fn nativeFault(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    const err = fatal.recordFailure(engine, roots[0], error.OutOfMemory, generation);
    callback_count += 1; if (observed == null) observed = engine.captured_exception; return err;
}
test "native EventStream Promise holder first callback fatal survives real subclass throw and second fault" {
    for ([_][]const u8{ "super(executor);throw globalThis.marker;", "super(executor);executor(()=>{});" }, 0..) |body, index| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: Scope = .{ .engine = engine }; defer s.deinit(); observed = null; callback_count = 0;
        const owner = try s.own(try fatal.create(engine)); const executor = try s.own(try functions.createArrow(engine, "", 1, nativeFault, &.{owner}));
        const global = try s.own(c.JS_GetGlobalObject(engine.context)); try s.put(global, "marker", try s.object());
        const source = try std.fmt.allocPrint(std.testing.allocator, "(class extends Promise{{constructor(executor){{{s}}}}})", .{body}); defer std.testing.allocator.free(source);
        const constructor = try s.own(try engine.eval(source, "native-event-promise-subclass.js", c.JS_EVAL_TYPE_GLOBAL));
        try std.testing.expectError(error.JavaScriptException, fatal.constructOwned(engine, constructor, &.{executor}, owner));
        const actual = engine.captured_exception orelse return error.MissingNativeExecutorFatal;
        try std.testing.expect(observed != null and c.JS_IsStrictEqual(engine.context, actual, observed.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual)); try std.testing.expectEqual(@as(usize, if (index == 1) 2 else 1), callback_count);
    }
}
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
test "native EventStream Promise holder historical private and marked lookalike data are not new events" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const historical = try s.own(c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingHistoricalReason)); c.JS_SetUncatchableError(engine.context, historical);
    const lookalike = try s.own(try engine.checked(c.JS_NewError(engine.context))); c.JS_SetUncatchableError(engine.context, lookalike);
    try std.testing.expect(c.JS_IsUncatchableError(lookalike) and c.pi_js_native_allocation_error_generation(lookalike) == 0);
    for ([_]c.JSValue{ historical, lookalike }) |reason| {
        if (engine.captured_exception) |old| engine.freeValue(old); engine.captured_exception = c.JS_DupValue(engine.context, reason);
        const owner = try s.own(try fatal.create(engine));
        try std.testing.expectEqual(error.JavaScriptException, fatal.recordFailure(engine, owner, error.JavaScriptException, engine.native_allocation_generation));
        const executor = try s.own(try functions.createArrow(engine, "", 1, noop, &.{}));
        _ = try s.own(try fatal.constructOwned(engine, try s.global("Promise"), &.{executor}, owner));
    }
}
pub fn compareActualSource(engine: *em.Engine, actual_constructor: c.JSValue, bytes: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const observer = try s.own(try engine.evalModule(@embedFile("../verification/event-stream-generator-function-sourceonly-20261017/observer.mjs"), "actual-event-stream-factory-observer.mjs"));
    const observed_value = try s.own(try engine.awaitValue(try s.call(try s.get(observer, "observeEventStreamFactory"), c.pi_js_undefined(), &.{actual_constructor})));
    const terminated = try engine.gpa.dupeZ(u8, bytes); defer engine.gpa.free(terminated);
    const reference = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, bytes.len, "original-event-stream-factory.json")));
    try std.testing.expect(s.equal(try s.get(reference, "authority"), try s.text("actual-Pi1.3-8efd-EventStream-factory")));
    try std.testing.expect(s.equal(try s.get(try s.get(reference, "rows"), "length"), c.JS_NewInt32(engine.context, 13)));
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    try std.testing.expect(s.equal(try s.call(stringify, json, &.{reference}), try s.call(stringify, json, &.{observed_value})));
}
