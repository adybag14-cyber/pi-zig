//! Uncompiled private bookkeeping boundary tests. No Engine/global activation.
const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const rejection_mod = @import("extensions/native_promise_rejections.zig");
const scopes = @import("extensions/native_async_scope.zig");
const c = engine_mod.c;
fn tracker(_: ?*c.JSContext, promise: c.JSValue, reason: c.JSValue, handled: bool, raw: ?*anyopaque) callconv(.c) void {
    const queue: *rejection_mod.Queue = @ptrCast(@alignCast(raw.?));
    queue.observe(promise, reason, handled);
}
fn install(engine: *engine_mod.Engine, queue: *rejection_mod.Queue) void {
    c.JS_SetHostPromiseRejectionTracker(engine.runtime, tracker, queue);
}
fn uninstall(engine: *engine_mod.Engine) void {
    c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
}
fn script(engine: *engine_mod.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "private-rejection-bookkeeping.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
fn field(engine: *engine_mod.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn drain(engine: *engine_mod.Engine) !void {
    _ = try engine.drainReadyJobs();
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}

test "Promise rejection bookkeeping raw roots survive GC and reporting keeps only a weak promise key" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    try script(engine, "globalThis.calls=0;globalThis.reason={get then(){calls++;throw 1},toString(){calls++;throw 2}};globalThis.p=Promise.reject(reason);globalThis.weak=new WeakRef(p);");
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(usize, 1), queue.entries.items.len);
    queue.checkpoint();
    const rejection = (try queue.take()).?;
    const reason = try field(engine, "reason");
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, rejection.reason));
    try queue.noteReported(rejection);
    rejection.deinit(engine.context);
    try script(engine, "p=null;if(calls!==0)throw Error('tracker invoked guest');");
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    try script(engine, "if(weak.deref()!==undefined)throw Error('reported map retained promise');");
}

test "Promise rejection bookkeeping same-turn and microtask catches cancel before complete checkpoint" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    try script(engine, "Promise.reject('sync').catch(()=>{});globalThis.p=Promise.reject('micro');Promise.resolve().then(()=>p.catch(()=>{}));");
    try std.testing.expectEqual(@as(usize, 1), queue.entries.items.len);
    try std.testing.expect((try queue.take()) == null);
    _ = try engine.runReadyJobs(0);
    try std.testing.expect((try queue.take()) == null);
    try drain(engine);
    queue.checkpoint();
    try std.testing.expect((try queue.take()) == null);
    try std.testing.expect((try queue.takeHandled()) == null);
}

test "Promise rejection bookkeeping distinct promises sharing one raw reason retain independent records" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    try script(engine, "globalThis.reason={};globalThis.p=Promise.reject(reason);globalThis.q=Promise.reject(reason);");
    queue.checkpoint();
    const first = (try queue.take()).?;
    defer first.deinit(engine.context);
    const second = (try queue.take()).?;
    defer second.deinit(engine.context);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first.reason, second.reason));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first.promise, second.promise));
    try std.testing.expect(first.uid != second.uid);
}

test "Promise rejection bookkeeping fixed snapshot preserves Source sibling report without false late-handled event" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    try script(engine, "globalThis.p=Promise.reject('first');globalThis.q=Promise.reject('second');");
    queue.checkpoint();
    const first = (try queue.take()).?;
    defer first.deinit(engine.context);
    try queue.noteReported(first);
    try script(engine, "q.catch(()=>{});");
    const second = (try queue.take()).?;
    defer second.deinit(engine.context);
    try queue.noteReported(second);
    try drain(engine);
    try std.testing.expect((try queue.takeHandled()) == null);
}

test "Promise rejection bookkeeping catch after report yields original promise and uid after reactions" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    try script(engine, "globalThis.caught=false;globalThis.p=Promise.reject('late');");
    queue.checkpoint();
    const rejection = (try queue.take()).?;
    defer rejection.deinit(engine.context);
    try queue.noteReported(rejection);
    try script(engine, "p.catch(()=>{caught=true});");
    try drain(engine);
    try script(engine, "if(!caught)throw Error('reaction order');");
    const handled = (try queue.takeHandled()).?;
    defer handled.deinit(engine.context);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, rejection.promise, handled.promise));
    try std.testing.expectEqual(rejection.uid, handled.uid);
    try std.testing.expect((try queue.takeHandled()) == null);
}

fn noScopeCallback(_: ?*anyopaque) void {}
test "Promise rejection bookkeeping captures exact original private scope without callback execution" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    const token = try scopes.create(engine, null, noScopeCallback, noScopeCallback);
    defer engine.freeValue(token);
    const guard = scopes.enter(engine, token);
    try script(engine, "Promise.reject('scoped');");
    guard.restore();
    scopes.retire(engine, token);
    queue.checkpoint();
    const rejection = (try queue.take()).?;
    defer rejection.deinit(engine.context);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, token, rejection.scope));
    try std.testing.expect(!scopes.isActive(engine));
}

fn allocationProbe(gpa: std.mem.Allocator, engine: *engine_mod.Engine, promise: c.JSValue, reason: c.JSValue) !void {
    var queue = try rejection_mod.Queue.init(engine, gpa);
    defer queue.deinit();
    queue.observe(promise, reason, false);
    queue.checkpoint();
    const rejection = (try queue.take()) orelse return error.MissingRejection;
    defer rejection.deinit(engine.context);
    try queue.noteReported(rejection);
    queue.observe(promise, reason, true);
    const handled = (try queue.takeHandled()) orelse return error.MissingHandled;
    defer handled.deinit(engine.context);
}
test "Promise rejection bookkeeping complete host allocation failure sweep preserves raw roots and callback OOM" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    const promise = try engine.eval("Promise.resolve(0)", "queue-allocation-promise.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const reason = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(reason);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{ engine, promise, reason });
}

test "Promise rejection bookkeeping private weak intrinsics survive guest global and prototype replacement" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    try script(engine, "WeakMap.prototype.get=WeakMap.prototype.set=WeakMap.prototype.delete=function(){throw Error('guest weak operation')};globalThis.WeakMap=function(){throw Error('guest weak constructor')};globalThis.p=Promise.reject('untampered');");
    queue.checkpoint();
    const rejection = (try queue.take()).?;
    defer rejection.deinit(engine.context);
    try queue.noteReported(rejection);
    try script(engine, "p.catch(()=>{});");
    try drain(engine);
    const handled = (try queue.takeHandled()).?;
    defer handled.deinit(engine.context);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, rejection.promise, handled.promise));
}

test "Promise rejection bookkeeping explicit native await ownership consumes genuine rejection before pumping" {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
    defer queue.deinit();
    install(engine, &queue);
    defer uninstall(engine);
    const promise = try engine.eval("Promise.reject(Error('native-consumed-original'))", "native-rejection-ownership.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    try std.testing.expectEqual(@as(usize, 1), queue.entries.items.len);
    c.JS_PromiseMarkAsHandled(engine.context, promise);
    try std.testing.expectEqual(@as(usize, 0), queue.entries.items.len);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(promise));
    queue.checkpoint();
    try std.testing.expect((try queue.take()) == null);
    try std.testing.expect((try queue.takeHandled()) == null);
}
