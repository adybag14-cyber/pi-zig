//! Actual Node Environment and callback-scope state controls.
//! These controls install the real process object, intrinsic shared buffers,
//! actual JavaScript hook functions, and the distinct VM continuation slot.
//! Task-queue/fatal/scheduling operations are guarded as unselected in this
//! root; no stand-in queue is used to claim those separate owners complete.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const callable = @import("extensions/native_node_module_callable.zig");

fn unselectedHookException(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedActualFatalHookPolicy;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedActualNativeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedActualCorruptedStack;
}
fn unselectedCheckpoint(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedActualTaskQueueCheckpoint;
}
fn unselectedSchedule(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedActualDestroyImmediate;
}
fn unselectedInterrupt(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedActualDestroyInterrupt;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselectedHookException,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselectedCheckpoint,
    .schedule_destroy_immediate = unselectedSchedule,
    .request_destroy_interrupt = unselectedInterrupt,
};

var active_fixture: ?*Fixture = null;
fn currentFrame(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = active_fixture.?;
    return fixture.env().currentContextFrame() catch |err|
        callable.failure(em.Engine.fromContext(context.?), err, 0);
}
fn replaceTick(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = active_fixture.?;
    fixture.env().setTickCallback(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err|
        return callable.failure(em.Engine.fromContext(context.?), err, 0);
    return c.pi_js_undefined();
}

const Fixture = struct {
    native_environment: std.process.Environ.Map,
    engine: *em.Engine,
    environment: ?*callbacks.Environment = null,
    engine_alive: bool = false,

    fn init(self: *Fixture, context_frames: bool, crypto: bool) !void {
        self.* = .{
            .native_environment = .init(std.testing.allocator),
            .engine = undefined,
        };
        errdefer self.native_environment.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        errdefer self.engine.deinit();
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"actual-node-callback-scope"});
        active_fixture = self;
        errdefer active_fixture = null;
        try self.engine.bindFunction("actualNodeFrame", currentFrame, 0);
        try self.engine.bindFunction("actualReplaceTick", replaceTick, 1);
        try self.evaluate(
            \\globalThis.trace = [];
            \\globalThis.actualHookSource = {
            \\  init: function(id, type, trigger, resource) {
            \\    trace.push(["init", id, type, trigger, this === resource, resource.tag, actualNodeFrame()]);
            \\  },
            \\  before: function(id) { "use strict"; trace.push(["before", id, this === undefined, uid[0], uid[1], actualNodeFrame()]); },
            \\  after: function(id) { "use strict"; trace.push(["after", id, this === undefined, uid[0], uid[1], actualNodeFrame()]); },
            \\  destroy: function(id) { "use strict"; trace.push(["destroy", id, this === undefined]); },
            \\  promise_resolve: function(id) { "use strict"; trace.push(["resolve", id, this === undefined]); }
            \\};
        );
        const result = try a.expression(self.engine, bootstrapBody, .{ self, context_frames, crypto });
        self.engine.freeValue(result);
    }
    fn bootstrapBody(s: *a.Scope, self: *Fixture, context_frames: bool, crypto: bool) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const before = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), before);
        const environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(crypto),
            .resource_symbol = symbol,
            .process_object = process,
            .async_context_frame = context_frames,
            .operations = operations,
        });
        self.environment = environment;
        errdefer {
            environment.disarm() catch {};
            environment.release();
            self.environment = null;
        }
        const binding = try s.object();
        try s.define(binding, "async_ids_stack", environment.ids.view.?, c.JS_PROP_C_W_E);
        const hooks = try s.get(global, "actualHookSource");
        try environment.installHooks(.{
            .init = try s.get(hooks, "init"),
            .before = try s.get(hooks, "before"),
            .after = try s.get(hooks, "after"),
            .destroy = try s.get(hooks, "destroy"),
            .promise_resolve = try s.get(hooks, "promise_resolve"),
        }, binding);
        try s.define(global, "fields", environment.fields.view.?, c.JS_PROP_C_W_E);
        try s.define(global, "uid", environment.uid.view.?, c.JS_PROP_C_W_E);
        try s.define(global, "ticks", environment.ticks.view.?, c.JS_PROP_C_W_E);
        try s.define(global, "ids", environment.ids.view.?, c.JS_PROP_C_W_E);
        try s.define(global, "binding", binding, c.JS_PROP_C_W_E);
        try s.define(global, "actualResourceSymbol", symbol, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    fn initScope(self: *Fixture, scope: *callbacks.Scope, resource: c.JSValue,
        id: callbacks.AsyncContext, flags: callbacks.Flags, frame: c.JSValue) !void {
        // init acquires native/JS owners before its fallible hook and stack work.
        // Retire a partially initialized scope before the fixture can disarm.
        scope.initialized = false;
        errdefer if (scope.initialized and !scope.deinitialized) {
            scope.markFailed();
            scope.deinit() catch {};
        };
        try scope.init(self.env(), resource, id, flags, frame);
    }
    fn value(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "actual-node-callback-state.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const result = try self.value(source);
        self.engine.freeValue(result);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const result = try self.value(source);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
    }
    fn closeEnvironment(self: *Fixture) !void {
        const environment = self.environment orelse return;
        try environment.cleanupRealmAfterIoJoin();
        try environment.disarm();
        self.environment = null;
        environment.release();
    }
    fn deinit(self: *Fixture) void {
        self.closeEnvironment() catch @panic("actual callback environment failed to close");
        if (self.engine_alive) self.engine.deinit();
        self.engine_alive = false;
        active_fixture = null;
        self.native_environment.deinit();
    }
};

test "native Node callback scope exposes intrinsic aliases with actual shared native bytes" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    try f.expect(
        \\fields instanceof Uint32Array && fields.length === 9 &&
        \\uid instanceof Float64Array && uid.length === 4 &&
        \\ticks instanceof Uint8Array && ticks.length === 2 &&
        \\ids instanceof Float64Array && ids.length === 32 &&
        \\fields[6] === 1 && uid[2] === 1 && uid[3] === -1 &&
        \\fields.buffer !== uid.buffer && uid.buffer !== ids.buffer &&
        \\binding.async_ids_stack === ids
    );
    try f.evaluate("uid[0] = 41; uid[1] = 13; fields[0] = 2; ticks[0] = 1;");
    try std.testing.expectEqual(@as(f64, 41), f.env().executionAsyncId());
    try std.testing.expectEqual(@as(f64, 13), f.env().triggerAsyncId());
    try std.testing.expectEqual(@as(u32, 2), f.env().field(.init).*);
    try std.testing.expect(f.env().hasTickScheduled());
    f.env().uidField(.execution).* = 0;
    f.env().tickField(.has_rejection_to_warn).* = 1;
    try f.expect("uid[0] === 0 && ticks[1] === 1");
}

test "native Node callback scope uses live default trigger and shared async ID counter" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    try f.evaluate("uid[0] = 57; uid[2] = 900; uid[3] = -1;");
    try std.testing.expectEqual(@as(f64, 57), f.env().getDefaultTriggerAsyncId());
    try std.testing.expectEqual(@as(f64, 901), f.env().newAsyncId());
    try f.evaluate("uid[3] = 0;");
    try std.testing.expectEqual(@as(f64, 0), f.env().getDefaultTriggerAsyncId());
    try f.expect("uid[2] === 901");
    try std.testing.expect(!f.env().has_run_bootstrapping_code);
    f.env().markBootstrapComplete();
    try std.testing.expect(f.env().has_run_bootstrapping_code);
}

test "native Node callback scope caches the selected provider table and actual shared symbol" {
    var f: Fixture = undefined; try f.init(true, true); defer f.deinit();
    try std.testing.expectEqual(@as(usize, 69), f.env().provider_strings.len);
    const file_handle = try f.env().providerString(providers.file_handle);
    const symbol = try f.env().resourceSymbol();
    try std.testing.expect(c.JS_IsSymbol(symbol));
    const result = try a.expression(f.engine, struct {
        fn publish(s: *a.Scope, value: c.JSValue) !c.JSValue {
            const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
            try s.define(global, "actualProvider", value, c.JS_PROP_C_W_E);
            return c.pi_js_undefined();
        }
    }.publish, .{file_handle});
    f.engine.freeValue(result);
    try f.expect("actualProvider === 'FILEHANDLE' && typeof actualResourceSymbol === 'symbol'");
    const again = try f.env().resourceSymbol();
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, symbol, again));
}

test "native Node callback scope invokes actual init receiver arguments and frame" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().field(.init).* = 1;
    const resource = try f.value("({tag: 'request'})"); defer f.engine.freeValue(resource);
    const frame = try f.value("'init-frame'"); defer f.engine.freeValue(frame);
    try f.env().setContextFrame(frame);
    try f.env().emitInit(29, try f.env().providerString(providers.fs_request_promise), 7, resource);
    try f.expect("JSON.stringify(trace) === JSON.stringify([['init',29,'FSREQPROMISE',7,true,'request','init-frame']])");
}

test "native Node callback scope nests actual IDs resources hooks and continuation frames" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const resource = try f.value("({tag:'nested'})"); defer f.engine.freeValue(resource);
    const initial = try f.value("'initial'"); defer f.engine.freeValue(initial);
    const outer_frame = try f.value("'outer'"); defer f.engine.freeValue(outer_frame);
    const inner_frame = try f.value("'inner'"); defer f.engine.freeValue(inner_frame);
    try f.env().setContextFrame(initial);
    var outer: callbacks.Scope = undefined;
    try f.initScope(&outer, resource, .{ .async_id = 2, .trigger_async_id = 0 }, .{ .skip_task_queues = true }, outer_frame);
    defer if (!outer.deinitialized) outer.deinit() catch {};
    var inner: callbacks.Scope = undefined;
    try f.initScope(&inner, resource, .{ .async_id = 3, .trigger_async_id = 2 }, .{ .skip_task_queues = true }, inner_frame);
    defer if (!inner.deinitialized) inner.deinit() catch {};
    try std.testing.expectEqual(@as(usize, 2), f.env().callback_depth);
    try std.testing.expect(f.env().native_resources.items[1].? == &inner.resource);
    try inner.deinit();
    try std.testing.expectEqual(@as(f64, 2), f.env().executionAsyncId());
    try outer.deinit();
    try std.testing.expect(f.env().js_resources != null);
    try f.expect(
        \\uid[0] === 0 && uid[1] === 0 && fields[7] === 0 &&
        \\actualNodeFrame() === 'initial' &&
        \\JSON.stringify(trace) === JSON.stringify([
        \\  ['before',2,true,2,0,'outer'],['before',3,true,3,2,'inner'],
        \\  ['after',3,true,3,2,'inner'],['after',2,true,2,0,'outer']])
    );
}

test "native Node callback scope closes once before releasing the callback-depth owner" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().field(.after).* = 1;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 2, .trigger_async_id = 0 }, .{ .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!scope.deinitialized) scope.deinit() catch {};
    try scope.close(); try scope.close();
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expectEqual(@as(u32, 0), f.env().field(.stack_length).*);
    try f.expect("trace.length === 1 && trace[0][0] === 'after'");
    try scope.deinit();
    try std.testing.expectEqual(@as(usize, 0), f.env().callback_depth);
    try std.testing.expect(f.env().callback_scope == null);
}

test "native Node callback scope marked failure restores context while suppressing after and queues" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const initial = try f.value("'before-failure'"); defer f.engine.freeValue(initial);
    const current = try f.value("'inside-failure'"); defer f.engine.freeValue(current);
    try f.env().setContextFrame(initial);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 6, .trigger_async_id = 0 }, .{}, current);
    defer if (!scope.deinitialized) scope.deinit() catch {};
    scope.markFailed();
    try scope.deinit();
    try f.expect("trace.length === 1 && trace[0][0] === 'before' && uid[0] === 0 && actualNodeFrame() === 'before-failure'");
}

test "native Node callback scope skip hooks and task queues preserves actual push and pop" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 8, .trigger_async_id = 4 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!scope.deinitialized) scope.deinit() catch {};
    try f.expect("uid[0] === 8 && uid[1] === 4 && fields[7] === 1 && trace.length === 0");
    try scope.deinit();
    try f.expect("uid[0] === 0 && fields[7] === 0 && trace.length === 0");
}

test "native Node callback scope zero async ID skips hooks without skipping context ownership" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 0, .trigger_async_id = 0 },
        .{ .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!scope.deinitialized) scope.deinit() catch {};
    try std.testing.expectEqual(@as(u32, 1), f.env().field(.stack_length).*);
    try scope.deinit();
    try f.expect("trace.length === 0 && fields[7] === 0");
}

test "native Node callback scope native call prohibition registers depth without pushing IDs" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    f.env().can_call_into_js = false;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 19, .trigger_async_id = 0 }, .{}, c.pi_js_undefined());
    defer if (!scope.deinitialized) scope.deinit() catch {};
    try std.testing.expect(scope.failed and !scope.pushed_ids);
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expectEqual(@as(u32, 0), f.env().field(.stack_length).*);
    try scope.deinit();
    try std.testing.expectEqual(@as(usize, 0), f.env().callback_depth);
}

test "native Node callback scope stopping clears IDs before frame restoration or idle reset" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const initial = try f.value("'initial'"); defer f.engine.freeValue(initial);
    const current = try f.value("'stopping'"); defer f.engine.freeValue(current);
    try f.env().setContextFrame(initial);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 9, .trigger_async_id = 2 },
        .{ .skip_task_queues = true }, current);
    defer if (!scope.deinitialized) scope.deinit() catch {};
    f.env().stopping = true;
    try scope.deinit();
    try std.testing.expect(scope.failed and !f.env().idle);
    try f.expect("uid[0] === 0 && uid[1] === 0 && fields[7] === 0 && actualNodeFrame() === 'stopping'");
}

test "native Node callback scope disabled context-frame option leaves the distinct slot unchanged" {
    var f: Fixture = undefined; try f.init(false, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const frame = try f.value("({context:'disabled'})"); defer f.engine.freeValue(frame);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_task_queues = true }, frame);
    defer if (!scope.deinitialized) scope.deinit() catch {};
    try f.expect("actualNodeFrame() === undefined");
    try scope.deinit();
    try f.expect("actualNodeFrame() === undefined");
}

test "native Node callback scope growth replaces intrinsic storage and preserves retained old view" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var scopes: [17]callbacks.Scope = undefined;
    var live: usize = 0;
    defer while (live > 0) { live -= 1; scopes[live].deinit() catch {}; };
    for (0..scopes.len) |index| {
        try f.initScope(&scopes[index], resource, .{
            .async_id = @floatFromInt(index + 2), .trigger_async_id = 0,
        }, .{ .skip_task_queues = true }, c.pi_js_undefined());
        live += 1;
    }
    try std.testing.expectEqual(@as(usize, 96), f.env().ids.data.len);
    try f.expect("ids.length === 32 && binding.async_ids_stack.length === 96 && ids.buffer !== binding.async_ids_stack.buffer && ids.byteLength === 256");
    try f.evaluate("ids[0] = 700;");
    try std.testing.expectEqual(@as(f64, 0), f.env().ids.data[0]);
    while (live > 0) { live -= 1; try scopes[live].deinit(); }
    try f.expect("uid[0] === 0 && fields[7] === 0 && ids[0] === 700");
}

test "native Node callback scope disabled hooks and destroy gate do not dispatch native queues" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    try f.env().emitBefore(4); try f.env().emitAfter(4); try f.env().emitPromiseResolve(4); try f.env().emitDestroy(4);
    f.env().field(.destroy).* = 1;
    f.env().can_call_into_js = false;
    try f.env().emitDestroy(5);
    try std.testing.expectEqual(@as(usize, 0), f.env().destroy_ids.items.len);
    try f.expect("trace.length === 0");
}

test "native Node callback scope tick calls actual process receiver and retains replaced function" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    {
        const callback = try f.value(
            \\(function first() {
            \\  trace.push(this === process ? 'first-process' : 'wrong-receiver');
            \\  actualReplaceTick(function second() { trace.push(this === process ? 'second-process' : 'wrong-receiver'); });
            \\  trace.push('first-continued');
            \\})
        ); defer f.engine.freeValue(callback);
        try f.env().setTickCallback(callback);
    }
    // Only the Environment owns the selected function before the actual call.
    f.env().tickField(.has_tick_scheduled).* = 1;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var first: callbacks.Scope = undefined;
    try f.initScope(&first, resource, .{ .async_id = 0, .trigger_async_id = 0 }, .{}, c.pi_js_undefined());
    defer if (!first.deinitialized) first.deinit() catch {};
    try first.deinit();
    var second: callbacks.Scope = undefined;
    try f.initScope(&second, resource, .{ .async_id = 0, .trigger_async_id = 0 }, .{}, c.pi_js_undefined());
    defer if (!second.deinitialized) second.deinit() catch {};
    try second.deinit();
    try f.expect("JSON.stringify(trace) === JSON.stringify(['first-process','first-continued','second-process'])");
}

test "native Node callback scope tick retains the bootstrap process after guest global replacement" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const callback = try f.value("(function(){ trace.push(this === originalProcess); })");
    defer f.engine.freeValue(callback);
    try f.env().setTickCallback(callback);
    try f.evaluate("globalThis.originalProcess = process; globalThis.process = {replacement:true};");
    f.env().tickField(.has_tick_scheduled).* = 1;
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    var scope: callbacks.Scope = undefined;
    try f.initScope(&scope, resource, .{ .async_id = 0, .trigger_async_id = 0 }, .{}, c.pi_js_undefined());
    defer if (!scope.deinitialized) scope.deinit() catch {};
    try scope.deinit();
    try f.expect("trace.length === 1 && trace[0] === true && process !== originalProcess");
}

const CleanupProbe = struct {
    slot: callbacks.RealmCleanup,
    calls: usize = 0,
    fn run(environment: *callbacks.Environment, raw: ?*anyopaque) !void {
        const self: *CleanupProbe = @ptrCast(@alignCast(raw.?));
        try std.testing.expect(self.slot.environment == null and self.slot.previous == null and self.slot.next == null);
        try std.testing.expect(!environment.canCallIntoJs() and environment.engine != null);
        self.calls += 1;
    }
};
test "native Node callback scope realm cleanup unlinks real slots before native owner retirement" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    var probe: CleanupProbe = .{ .slot = .{ .raw = null, .run = CleanupProbe.run } };
    probe.slot.raw = &probe;
    const references = f.env().references.load(.monotonic);
    try f.env().registerRealmCleanup(&probe.slot);
    try std.testing.expectEqual(references + 1, f.env().references.load(.monotonic));
    try f.env().cleanupRealmAfterIoJoin();
    try f.env().cleanupRealmAfterIoJoin();
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expect(f.env().cleanup_head == null);
    try std.testing.expectEqual(references, f.env().references.load(.monotonic));
}

test "native Node callback scope native entitlement safely outlives the retired VM" {
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const environment = f.env().retain();
    var released = false;
    defer if (!released) environment.release();
    try f.closeEnvironment();
    try std.testing.expect(environment.disarmed and environment.engine == null);
    f.engine.deinit(); f.engine_alive = false;
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    environment.release(); released = true;
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}


// InternalMakeCallback controls use actual nested callback scopes to exercise
// selected invocation semantics without substituting task-queue/fatal owners.
const make_callback = @import("extensions/native_node_make_callback.zig");

fn replaceTrampoline(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = active_fixture.?;
    fixture.env().setCallbackTrampoline(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err|
        return callable.failure(em.Engine.fromContext(context.?), err, 0);
    return c.pi_js_undefined();
}
fn stopNodeEnvironment(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    active_fixture.?.env().stopping = true;
    return c.pi_js_undefined();
}

test "native Node callback scope MakeCallback preserves actual receiver argument identities hook order and return" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("globalThis.actualResource = {tag:'resource'}"); defer f.engine.freeValue(resource);
    const receiver = try f.value("globalThis.actualReceiver = {tag:'receiver'}"); defer f.engine.freeValue(receiver);
    const returned = try f.value("globalThis.actualReturned = {tag:'returned'}"); defer f.engine.freeValue(returned);
    const callback = try f.value(
        \\(function(first, second) {
        \\  trace.push(['body',this === actualReceiver,first === actualResource,second === actualReturned,
        \\    arguments.length,uid[0],uid[1],actualNodeFrame()]);
        \\  return second;
        \\})
    ); defer f.engine.freeValue(callback);
    const parent_frame = try f.value("'parent-frame'"); defer f.engine.freeValue(parent_frame);
    const child_frame = try f.value("'child-frame'"); defer f.engine.freeValue(child_frame);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, parent_frame);
    defer if (!parent.deinitialized) parent.deinit() catch {};
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const result = (try make_callback.call(f.env(), resource, receiver, callback, &.{resource, returned},
        .{ .async_id = 7, .trigger_async_id = 2 }, child_frame)) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result, returned));
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expect(f.env().callback_scope == &parent);
    try f.expect(
        \\uid[0] === 2 && uid[1] === 0 && actualNodeFrame() === 'parent-frame' &&
        \\JSON.stringify(trace) === JSON.stringify([
        \\  ['before',7,true,7,2,'child-frame'],
        \\  ['body',true,true,true,2,7,2,'child-frame'],
        \\  ['after',7,true,7,2,'child-frame']])
    );
}

test "native Node callback scope MakeCallback selects the actual trampoline receiver and native argument prefix" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("globalThis.actualResource = {}"); defer f.engine.freeValue(resource);
    const receiver = try f.value("globalThis.actualReceiver = {}"); defer f.engine.freeValue(receiver);
    const argument = try f.value("globalThis.actualArgument = {}"); defer f.engine.freeValue(argument);
    const callback = try f.value(
        \\globalThis.actualCallback = function(value) {
        \\  trace.push(['body',this === actualReceiver,value === actualArgument,arguments.length]);
        \\  return value;
        \\}
    ); defer f.engine.freeValue(callback);
    const trampoline = try f.value(
        \\(function(id, resource, callback, value) {
        \\  trace.push(['trampoline',this === actualReceiver,id,resource === actualResource,
        \\    callback === actualCallback,value === actualArgument,arguments.length]);
        \\  return callback.call(this,value);
        \\})
    ); defer f.engine.freeValue(trampoline);
    try f.env().setCallbackTrampoline(trampoline);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!parent.deinitialized) parent.deinit() catch {};
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const result = (try make_callback.call(f.env(), resource, receiver, callback, &.{argument},
        .{ .async_id = 11, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result, argument));
    try f.expect(
        \\JSON.stringify(trace) === JSON.stringify([
        \\  ['trampoline',true,11,true,true,true,4],['body',true,true,1]])
    );
}

test "native Node callback scope MakeCallback resource field alone selects trampoline with heap sized native arguments" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("globalThis.actualResource = {}"); defer f.engine.freeValue(resource);
    const receiver = try f.value("globalThis.actualReceiver = {}"); defer f.engine.freeValue(receiver);
    const callback = try f.value("globalThis.actualCallback = function(){ throw 'unexpected direct callback'; }");
    defer f.engine.freeValue(callback);
    const trampoline = try f.value(
        \\(function(id, resource, callback, ...args) {
        \\  trace.push(this === actualReceiver && id === 12 && resource === actualResource &&
        \\    callback === actualCallback && args.length === 14 &&
        \\    args.every((value,index) => value === index + 100));
        \\  return args[13];
        \\})
    ); defer f.engine.freeValue(trampoline);
    try f.env().setCallbackTrampoline(trampoline);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!parent.deinitialized) parent.deinit() catch {};
    f.env().field(.uses_execution_async_resource).* = 1;
    var arguments: [14]c.JSValue = undefined;
    for (&arguments, 0..) |*value, index| value.* = c.JS_NewInt32(f.engine.context, @intCast(index + 100));
    const result = (try make_callback.call(f.env(), resource, receiver, callback, &arguments,
        .{ .async_id = 12, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result, arguments[13]));
    try f.expect("trace.length === 1 && trace[0] === true");
}

test "native Node callback scope MakeCallback zero and wrapped unsigned sums keep direct invocation with trampoline installed" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const callback = try f.value("(function(){ trace.push('direct'); return 71; })"); defer f.engine.freeValue(callback);
    const trampoline = try f.value("(function(){ throw 'unexpected trampoline'; })"); defer f.engine.freeValue(trampoline);
    try f.env().setCallbackTrampoline(trampoline);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!parent.deinitialized) parent.deinit() catch {};
    const selectors = [_][3]u32{ .{0,0,0}, .{std.math.maxInt(u32),1,0}, .{std.math.maxInt(u32),0,1} };
    for (selectors) |selector| {
        f.env().field(.before).* = selector[0];
        f.env().field(.after).* = selector[1];
        f.env().field(.uses_execution_async_resource).* = selector[2];
        const result = (try make_callback.call(f.env(), resource, resource, callback, &.{},
            .{ .async_id = 13, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
        defer f.engine.freeValue(result);
        try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result, c.JS_NewInt32(f.engine.context, 71)));
    }
    try f.expect("JSON.stringify(trace) === JSON.stringify(['direct','direct','direct'])");
}

test "native Node callback scope MakeCallback nonfunction trampoline clearing restores actual native hooks" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const callback = try f.value("(function(){ trace.push(['body']); return undefined; })"); defer f.engine.freeValue(callback);
    const trampoline = try f.value("(function(){ throw 'cleared trampoline ran'; })"); defer f.engine.freeValue(trampoline);
    try f.env().setCallbackTrampoline(trampoline);
    try f.env().setCallbackTrampoline(resource);
    try std.testing.expect(f.env().trampoline == null);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!parent.deinitialized) parent.deinit() catch {};
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    const result = (try make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 14, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsUndefined(result));
    try f.expect("trace.length === 3 && trace[0][0] === 'before' && trace[1][0] === 'body' && trace[2][0] === 'after'");
}

test "native Node callback scope MakeCallback retains the selected trampoline through actual replacement during call" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    try f.engine.bindFunction("actualReplaceTrampoline", replaceTrampoline, 1);
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const callback = try f.value("(function(){ throw 'unexpected direct callback'; })"); defer f.engine.freeValue(callback);
    {
        const trampoline = try f.value(
            \\(function first() {
            \\  trace.push('first');
            \\  actualReplaceTrampoline(function second() { trace.push('second'); return 202; });
            \\  trace.push('first-continued');
            \\  return 101;
            \\})
        ); defer f.engine.freeValue(trampoline);
        try f.env().setCallbackTrampoline(trampoline);
    }
    // Its construction handle is gone; the Environment and actual invocation
    // supply the selected roots across replacement.
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!parent.deinitialized) parent.deinit() catch {};
    f.env().field(.uses_execution_async_resource).* = 1;
    const first = (try make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 15, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(first);
    const second = (try make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 16, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, first, c.JS_NewInt32(f.engine.context, 101)));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, second, c.JS_NewInt32(f.engine.context, 202)));
    try f.expect("JSON.stringify(trace) === JSON.stringify(['first','first-continued','second'])");
}

test "native Node callback scope MakeCallback preserves actual thrown identity while unwinding child scope" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const reason = try f.value("globalThis.actualThrown = {tag:'ordinary thrown object'}"); defer f.engine.freeValue(reason);
    const callback = try f.value("(function(){ trace.push(['body']); throw actualThrown; })"); defer f.engine.freeValue(callback);
    const parent_frame = try f.value("'parent'"); defer f.engine.freeValue(parent_frame);
    const child_frame = try f.value("'child'"); defer f.engine.freeValue(child_frame);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, parent_frame);
    defer if (!parent.deinitialized) parent.deinit() catch {};
    f.env().field(.before).* = 1; f.env().field(.after).* = 1;
    var failure: ?anyerror = null;
    if (make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 17, .trigger_async_id = 2 }, child_frame)) |result|
    {
        // Retire any unexpected successful value before asserting failure.
        if (result) |value| f.engine.freeValue(value);
    } else |err| failure = err;
    try std.testing.expect(failure != null);
    try std.testing.expect(failure.? == error.JavaScriptException);
    const actual = f.engine.captured_exception orelse return error.ExpectedActualCapturedCallbackReason;
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, reason));
    try std.testing.expect(!c.JS_IsUncatchableError(actual));
    f.engine.captured_exception = null;
    f.engine.freeValue(actual);
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expect(f.env().callback_scope == &parent);
    try f.expect("uid[0] === 2 && uid[1] === 0 && actualNodeFrame() === 'parent' && trace.length === 2 && trace[0][0] === 'before' && trace[1][0] === 'body'");
}

test "native Node callback scope MakeCallback returns an actual Error object as a successful value" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const returned = try f.value("globalThis.actualReturnedError = new Error('out of memory')"); defer f.engine.freeValue(returned);
    const callback = try f.value("(function(){ return actualReturnedError; })"); defer f.engine.freeValue(callback);
    var parent: callbacks.Scope = undefined;
    try f.initScope(&parent, resource, .{ .async_id = 2, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    defer if (!parent.deinitialized) parent.deinit() catch {};
    const result = (try make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 18, .trigger_async_id = 2 }, c.pi_js_undefined())) orelse return error.ExpectedActualCallbackValue;
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result, returned));
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native Node callback scope MakeCallback prohibited call returns empty without inventing a pending exception" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const callback = try f.value("(function(){ throw 'prohibited callback ran'; })"); defer f.engine.freeValue(callback);
    f.env().can_call_into_js = false;
    const result = try make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 19, .trigger_async_id = 0 }, c.pi_js_undefined());
    defer if (result) |value| f.engine.freeValue(value);
    try std.testing.expect(result == null);
    try std.testing.expectEqual(@as(usize, 0), f.env().callback_depth);
    try std.testing.expect(f.env().callback_scope == null);
    try std.testing.expectEqual(@as(u32, 0), f.env().field(.stack_length).*);
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native Node callback scope MakeCallback stopping after actual call returns empty and preserves stopping cleanup order" {
    var f: Fixture = undefined; try f.init(true, false); defer f.deinit();
    try f.engine.bindFunction("actualStopNodeEnvironment", stopNodeEnvironment, 0);
    const resource = try f.value("({})"); defer f.engine.freeValue(resource);
    const frame = try f.value("'stopped-frame'"); defer f.engine.freeValue(frame);
    const callback = try f.value("(function(){ trace.push('body'); actualStopNodeEnvironment(); return {}; })");
    defer f.engine.freeValue(callback);
    const result = try make_callback.call(f.env(), resource, resource, callback, &.{},
        .{ .async_id = 20, .trigger_async_id = 0 }, frame);
    defer if (result) |value| f.engine.freeValue(value);
    try std.testing.expect(result == null and f.env().stopping and !f.env().idle);
    try std.testing.expectEqual(@as(usize, 0), f.env().callback_depth);
    try std.testing.expect(f.env().callback_scope == null);
    try f.expect("uid[0] === 0 && uid[1] === 0 && fields[7] === 0 && actualNodeFrame() === 'stopped-frame' && trace.length === 1 && trace[0] === 'body'");
}
