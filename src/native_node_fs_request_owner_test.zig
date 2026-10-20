//! Selected native Node24.13 FS request-owner controls.
//! These controls use the actual Environment, AsyncWrap templates, BindingData,
//! native Global cells and FSReqPromise implementation. Resolve/Reject run in
//! a real nested CallbackScope under an explicit skip-task-queues outer scope.
//! Full task queues, fatal-hook handling, native scheduling and public FS
//! bootstrap are separate owners; an accidentally selected dependency fails.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const templates = @import("extensions/native_node_async_wrap.zig");
const native = @import("extensions/native_node_async_wrap_state.zig");
const bindings = @import("extensions/native_node_fs_binding_data.zig");
const requests = @import("extensions/native_node_fs_request_promise.zig");
const request_state = @import("extensions/native_node_request_state.zig");
const callable = @import("extensions/native_node_module_callable.zig");
const fs_io = @import("extensions/native_node_fs_request_io.zig");
const read_binding = @import("extensions/native_node_file_handle_read_binding.zig");
const uv = fs_io.uv;
const physical = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedFSRequestOwnerOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedFSRequestOwnerNativeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedFSRequestOwnerCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};
var active: ?*Fixture = null;
fn frame(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const f = active orelse return c.pi_js_exception();
    return f.env().currentContextFrame() catch |err|
        callable.failure(em.Engine.fromContext(context.?), err, 0);
}
fn initProbe(context: ?*c.JSContext, _: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f = active orelse return c.pi_js_exception();
    if (argc != 1) return callable.failure(f.engine, error.ActualInitProbeArgumentRequired, 0);
    return initProbeBody(f, argv[0]) catch |err|
        callable.failure(em.Engine.fromContext(context.?), err, 0);
}
fn initProbeBody(f: *Fixture, wrapper: c.JSValue) !c.JSValue {
    const state = (try f.registry()).unwrap(wrapper) orelse
        return error.ActualInitProbeWrapperRequired;
    if (state.provider != native.Provider.fsreqpromise)
        return error.ActualInitProbeRequestRequired;
    const req: *requests.Request = @alignCast(@fieldParentPtr("wrap", state));
    f.init_probe_calls += 1;
    const actual = req.native_request orelse return error.ActualInitProbeNativeStorageRequired;
    const info = uv.pi_uv_fs_request_info(actual);
    f.init_probe_prepared = info.kind == uv.PI_UV_FS_READ and info.accepted == 0 and
        info.cleaned == 0 and !req.constructed and !req.entry_initialized and req.binding_data == null;
    f.init_probe_before_queue = f.env().requests.head == null and
        f.env().requests.tail == null and f.env().requests.waiting == 0;
    return c.pi_js_undefined();
}
fn neverCancel(_: *request_state.Entry) void {
    @panic("unsubmitted FS request selected native cancellation");
}
const Options = struct { before_binding: []const u8 = "", physical_read: bool = false };
const Fixture = struct {
    native_environment: std.process.Environ.Map,
    engine: *em.Engine,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    owner: c.JSValue = undefined,
    factory: c.JSValue = undefined,
    target: c.JSValue = undefined,
    data: ?*bindings.BindingData = null,
    roots: [96]c.JSValue = undefined,
    root_count: usize = 0,
    controller: ?*fs_io.Controller = null,
    read_function: c.JSValue = undefined,
    use_promises: c.JSValue = undefined,
    init_probe_calls: usize = 0,
    init_probe_prepared: bool = false,
    init_probe_before_queue: bool = false,

    fn init(self: *Fixture, options: Options) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator), .engine = undefined };
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-fs-request-owner"});
        active = self;
        try self.engine.bindFunction("actualFsOwnerFrame", frame, 0);
        try self.engine.bindFunction("actualFsOwnerProbe", initProbe, 1);
        try self.evaluate(
            \\globalThis.ownerTrace = [];
            \\globalThis.ownerHooks = {
            \\  init: function(id, type, trigger, resource) {
            \\    ownerTrace.push(["init", id, type, trigger, this === resource, actualFsOwnerFrame()]);
            \\    if (globalThis.ownerInitProbe === true) actualFsOwnerProbe(resource);
            \\    if (globalThis.ownerInitAction !== undefined) ownerInitAction(resource);
            \\  },
            \\  before: function(id) { "use strict"; ownerTrace.push(["before", id, this === undefined, actualFsOwnerFrame()]); },
            \\  after: function(id) { "use strict"; ownerTrace.push(["after", id, this === undefined, actualFsOwnerFrame()]); },
            \\  destroy: function(id) { ownerTrace.push(["destroy", id]); },
            \\  promise_resolve: function(id) { ownerTrace.push(["resolve", id]); }
            \\};
        );
        if (options.before_binding.len != 0) try self.evaluate(options.before_binding);
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
        if (options.physical_read) try self.installPhysical();
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const allocation = try s.beforeAllocation();
        const resource_symbol = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), allocation);
        const environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false),
            .resource_symbol = resource_symbol,
            .process_object = process,
            .async_context_frame = true,
            .operations = operations,
        });
        self.environment = environment;
        const hook_binding = try s.object();
        try s.define(hook_binding, "async_ids_stack", environment.ids.view.?, c.JS_PROP_C_W_E);
        const hooks = try s.get(global, "ownerHooks");
        try environment.installHooks(.{
            .init = try s.get(hooks, "init"),
            .before = try s.get(hooks, "before"),
            .after = try s.get(hooks, "after"),
            .destroy = try s.get(hooks, "destroy"),
            .promise_resolve = try s.get(hooks, "promise_resolve"),
        }, hook_binding);
        environment.markBootstrapComplete();
        self.owner = self.keep(try templates.acquire(s.engine, environment));
        const object_constructor = try s.get(global, "Object");
        const object_prototype = try s.get(object_constructor, "prototype");
        const shape = try bindings.TargetTemplate.create(s);
        self.target = self.keep(a.duplicate(s.engine,
            try shape.newInstance(s, object_prototype)));
        const promise_string = try s.text("promise");
        self.data = try bindings.BindingData.create(s, shape, self.target, self.owner, promise_string);
        self.factory = self.keep(try requests.acquire(s.engine, self.data.?));
        const async_wrap = try s.own(try templates.constructor(s.engine, self.owner, .async_wrap));
        const fs_req = try s.own(try templates.constructor(s.engine, self.owner, .fsreqpromise));
        const close_req = try s.own(try templates.constructor(s.engine, self.owner, .filehandleclosereq));
        try s.define(global, "ActualAsyncWrap", async_wrap, c.JS_PROP_C_W_E);
        try s.define(global, "ActualFSReqPromise", fs_req, c.JS_PROP_C_W_E);
        try s.define(global, "ActualFileHandleCloseReq", close_req, c.JS_PROP_C_W_E);
        try s.define(global, "actualFsBinding", self.target, c.JS_PROP_C_W_E);
        try s.define(global, "actualFsResourceSymbol", resource_symbol, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn keep(self: *Fixture, owned: c.JSValue) c.JSValue {
        std.debug.assert(self.root_count < self.roots.len);
        self.roots[self.root_count] = owned;
        self.root_count += 1;
        return owned;
    }
    fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    fn registry(self: *Fixture) !*native.Registry {
        return templates.registry(self.engine, self.owner);
    }
    fn value(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "native-fs-request-owner.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.value(source);
        self.engine.freeValue(value);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const value = try self.value(source);
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_ToBool(self.engine.context, value) == 1);
    }
    fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn run(s: *a.Scope, key: [*:0]const u8, item: c.JSValue) !c.JSValue {
                const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.define(global, key, item, c.JS_PROP_C_W_E);
                return c.pi_js_undefined();
            }
        }.run, .{name, value});
        self.engine.freeValue(ignored);
    }
    fn request(self: *Fixture, bigint: bool) !*requests.Request {
        const wrapper = self.keep(try a.expression(self.engine, struct {
            fn create(s: *a.Scope, factory: c.JSValue, use_bigint: bool) !c.JSValue {
                return requests.createRequest(s, factory, use_bigint, neverCancel);
            }
        }.create, .{self.factory, bigint}));
        return requests.unwrap(self.engine, self.factory, wrapper);
    }
    fn outer(self: *Fixture, scope: *callbacks.Scope, resource: c.JSValue) !void {
        scope.initialized = false;
        errdefer if (scope.initialized and !scope.deinitialized) {
            scope.markFailed();
            scope.deinit() catch {};
        };
        try scope.init(self.env(), resource, .{ .async_id = 0, .trigger_async_id = 0 },
            .{ .skip_async_hooks = true, .skip_task_queues = true }, c.pi_js_undefined());
    }
    fn settle(self: *Fixture, request: *requests.Request, value: c.JSValue, rejecting: bool) !void {
        var outer_scope: callbacks.Scope = undefined;
        try self.outer(&outer_scope, try request.object());
        defer if (!outer_scope.deinitialized) {
            outer_scope.markFailed();
            outer_scope.deinit() catch {};
        };
        if (rejecting) try request.reject(value) else try request.resolve(value);
        try outer_scope.deinit();
    }
    fn takeCaught(self: *Fixture) !c.JSValue {
        const reason = self.engine.captured_exception orelse
            return error.ExpectedActualFSRequestCapturedReason;
        self.engine.captured_exception = null;
        return reason;
    }
    fn installPhysical(self: *Fixture) !void {
        self.controller = switch (try fs_io.acquire(self.engine, self.env())) {
            .ready => |value| value,
            .failed => return error.ActualFSReadServiceAdmissionFailed,
        };
        const ignored = try a.expression(self.engine, physicalBody, .{self});
        self.engine.freeValue(ignored);
    }
    fn physicalBody(s: *a.Scope, self: *Fixture) !c.JSValue {
        const generation = try s.beforeAllocation();
        const marker = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "fs_use_promises", false), generation);
        self.use_promises = self.keep(a.duplicate(s.engine, marker));
        self.read_function = self.keep(try read_binding.create(s.engine, .{
            .controller = self.controller.?,
            .use_promises = marker,
            .request_factory = self.factory,
        }));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.define(global, "actualNativeRead", self.read_function, c.JS_PROP_C_W_E);
        try s.define(global, "actualUsePromises", marker, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn firstRequest(self: *Fixture) !*requests.Request {
        const entry = self.env().requests.head orelse return error.ActualFSReadRequestRequired;
        return @alignCast(@fieldParentPtr("entry", entry));
    }
    fn retainNativeRequest(self: *Fixture) !*uv.PiUvFsRequest {
        const req = try self.firstRequest();
        const value = req.native_request orelse return error.ActualFSReadNativeStorageRequired;
        uv.pi_uv_fs_request_retain(value);
        return value;
    }
    fn pumpPending(self: *Fixture) !void {
        var outer_scope: callbacks.Scope = undefined;
        try self.outer(&outer_scope, self.target);
        defer if (!outer_scope.deinitialized) {
            outer_scope.markFailed();
            outer_scope.deinit() catch {};
        };
        const until = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (self.env().requests.waiting != 0) {
            // This control explicitly selects nested callback settlement, not
            // the separately unfinished production microtask checkpoint.
            if (c.JS_IsJobPending(self.engine.runtime))
                return error.UnselectedFSReadControlTaskQueue;
            const pump = self.engine.native_env_pump orelse return error.ActualFSReadHubRequired;
            _ = try pump(self.engine);
            if (self.env().requests.waiting == 0) break;
            if (physical.uv_hrtime() >= until) return error.ActualFSReadCompletionTimeout;
            physical.uv_sleep(1);
        }
        try outer_scope.deinit();
    }
    fn waitQueued(self: *Fixture, count: usize) !void {
        const service = self.controller.?.service;
        const until = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (uv.pi_uv_service_snapshot(service).queued_events < count) {
            if (physical.uv_hrtime() >= until) return error.ActualFSReadCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    fn expectPromiseInt(self: *Fixture, promise: c.JSValue, expected: i32) !void {
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(self.engine.context, promise));
        const result = c.JS_PromiseResult(self.engine.context, promise);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_IsNumber(result));
        var actual: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.engine.context, &actual, result));
        try std.testing.expectEqual(expected, actual);
    }
    fn stopIo(self: *Fixture) void {
        if (self.environment) |environment| environment.can_call_into_js = false;
        if (self.engine_alive) if (self.engine.native_env_deinit) |stop| stop(self.engine);
        self.controller = null;
    }
    fn closeRealm(self: *Fixture) !void {
        const environment = self.environment orelse return;
        self.stopIo();
        try environment.cleanupRealmAfterIoJoin();
        self.data = null;
    }
    fn deinit(self: *Fixture) void {
        if (self.environment) |environment| {
            self.closeRealm() catch @panic("FS request owner realm cleanup failed");
            environment.disarm() catch @panic("FS request owner environment disarm failed");
            self.environment = null;
            environment.release();
        }
        if (self.engine_alive) {
            while (self.root_count != 0) {
                self.root_count -= 1;
                self.engine.freeValue(self.roots[self.root_count]);
            }
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (active == self) active = null;
        self.native_environment.deinit();
    }
};

test "native FS request owner exposes real no-handler templates and converted receiver returns" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.expect(
        \\ActualAsyncWrap.name === "AsyncWrap" && ActualAsyncWrap.length === 0 &&
        \\ActualFSReqPromise.name === "FSReqPromise" && ActualFSReqPromise.length === 0 &&
        \\ActualFileHandleCloseReq.name === "FileHandleCloseReq" &&
        \\Object.getPrototypeOf(ActualFSReqPromise.prototype) === ActualAsyncWrap.prototype &&
        \\Object.getPrototypeOf(ActualFileHandleCloseReq.prototype) === ActualAsyncWrap.prototype &&
        \\Object.getOwnPropertyDescriptor(ActualFSReqPromise, "prototype").writable === true &&
        \\Object.getOwnPropertyDescriptor(ActualFSReqPromise, "prototype").configurable === false &&
        \\Object.keys(ActualAsyncWrap.prototype).join(",") === "getAsyncId,asyncReset,getProviderType" &&
        \\(() => { const receiver = {}; return ActualFSReqPromise.call(receiver) === receiver &&
        \\  ActualFSReqPromise.call(null) === globalThis &&
        \\  ActualFSReqPromise.call(7).valueOf() === 7; })()
    );
    const again = try templates.acquire(f.engine, f.env()); defer f.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, f.owner, again));
}

test "native FS request owner preserves actual template cache and subclass prototype selection" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\globalThis.firstTemplatePrototype = ActualFSReqPromise.prototype;
        \\globalThis.firstTemplateInstance = new ActualFSReqPromise();
        \\ActualFSReqPromise.prototype = { later: true };
        \\globalThis.secondTemplateInstance = new ActualFSReqPromise();
        \\function DerivedRequest() {}
        \\DerivedRequest.prototype = { derived: true };
        \\globalThis.derivedTemplateInstance = Reflect.construct(ActualFSReqPromise, [], DerivedRequest);
    );
    try f.expect(
        \\Object.getPrototypeOf(firstTemplateInstance) === firstTemplatePrototype &&
        \\Object.getPrototypeOf(secondTemplateInstance) === firstTemplatePrototype &&
        \\Object.getPrototypeOf(derivedTemplateInstance) === DerivedRequest.prototype &&
        \\firstTemplateInstance.getAsyncId() === -1 && firstTemplateInstance.getProviderType() === 0
    );
}

test "native FS request owner enforces the genuine signature and preserves a cleared template brand" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.expect(
        \\(() => {
        \\ const instance = new ActualFSReqPromise();
        \\ const method = ActualAsyncWrap.prototype.getAsyncId;
        \\ for (const receiver of [{}, Object.create(ActualFSReqPromise.prototype), new Proxy(instance, {})]) {
        \\   try { method.call(receiver); return false; } catch (error) { if (!(error instanceof TypeError)) return false; }
        \\ }
        \\ return method.call(instance) === -1 && instance.getProviderType() === 0;
        \\})()
    );
    const req = try f.request(false);
    const wrapper = try req.object();
    try f.expose("retiredRequest", wrapper);
    try f.settle(req, c.pi_js_undefined(), false);
    try req.wrap.retire(false);
    try std.testing.expect((try f.registry()).unwrap(wrapper) == null);
    try f.expect("retiredRequest.getAsyncId() === -1 && retiredRequest.getProviderType() === 0");
}

test "native FS request owner initializes the real provider IDs frame queue and derived aliases" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    f.env().field(.init).* = 1;
    f.env().uidField(.default_trigger).* = 73;
    const selected_frame = f.keep(try f.value("({requestFrame:true})"));
    try f.env().setContextFrame(selected_frame);
    const req = try f.request(false);
    const wrapper = try req.object();
    try f.expose("requestOwner", wrapper);
    try f.expose("requestFrame", selected_frame);
    try std.testing.expect(req.constructed and req.attached and req.entry_initialized and req.wrap.init_hook_ran);
    try std.testing.expect(req.native_request == null);
    try std.testing.expectEqual(@as(f64, 2), req.wrap.async_id);
    try std.testing.expectEqual(@as(f64, 73), req.wrap.trigger_async_id);
    try std.testing.expectEqual(native.Provider.fsreqpromise, req.wrap.provider);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, selected_frame, req.wrap.context_frame));
    try std.testing.expect(f.env().requests.head == &req.entry and f.env().requests.tail == &req.entry);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expect(!req.entry.dispatched and !req.entry.counted and req.wrap.wants_weak);
    switch (req.stats_field_array) {
        .number => |values| try std.testing.expectEqual(@as(usize, 18), values.data.len),
        else => return error.ExpectedActualNumberStatsAlias,
    }
    switch (req.statfs_field_array) {
        .number => |values| try std.testing.expectEqual(@as(usize, 7), values.data.len),
        else => return error.ExpectedActualNumberStatFsAlias,
    }
    try f.expect(
        \\requestOwner.getAsyncId() === 2 && requestOwner.getProviderType() === 9 &&
        \\ownerTrace.length === 1 && ownerTrace[0][0] === "init" && ownerTrace[0][1] === 2 &&
        \\ownerTrace[0][2] === "FSREQPROMISE" && ownerTrace[0][3] === 73 &&
        \\ownerTrace[0][4] === true && ownerTrace[0][5] === requestFrame
    );
}

test "native FS request owner keeps general reset resource and explicit ID ordering" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const req = try f.request(false);
    try f.expose("requestOwner", try req.object());
    f.env().field(.init).* = 1;
    f.env().uidField(.default_trigger).* = 81;
    const current_frame = f.keep(try f.value("({resetFrame:true})"));
    try f.env().setContextFrame(current_frame);
    try f.expose("resetFrame", current_frame);
    try f.evaluate(
        \\globalThis.resetResource = { resetResource:true };
        \\requestOwner.asyncReset(resetResource, 123);
    );
    try std.testing.expectEqual(@as(f64, 123), req.wrap.async_id);
    try std.testing.expectEqual(@as(f64, 81), req.wrap.trigger_async_id);
    try std.testing.expectEqual(@as(f64, 2), f.env().uidField(.counter).*);
    try f.expect(
        \\requestOwner[actualFsResourceSymbol] === resetResource &&
        \\ownerTrace.length === 1 && ownerTrace[0][1] === 123 &&
        \\ownerTrace[0][3] === 81 && ownerTrace[0][4] === true &&
        \\ownerTrace[0][5] === resetFrame
    );
}

test "native FS request owner publishes all four original BindingData views without AsyncWrap init" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.expect(
        \\actualFsBinding.statValues instanceof Float64Array && actualFsBinding.statValues.length === 36 &&
        \\actualFsBinding.bigintStatValues instanceof BigInt64Array && actualFsBinding.bigintStatValues.length === 36 &&
        \\actualFsBinding.statFsValues instanceof Float64Array && actualFsBinding.statFsValues.length === 7 &&
        \\actualFsBinding.bigintStatFsValues instanceof BigInt64Array && actualFsBinding.bigintStatFsValues.length === 7 &&
        \\new Set([actualFsBinding.statValues.buffer, actualFsBinding.bigintStatValues.buffer,
        \\  actualFsBinding.statFsValues.buffer, actualFsBinding.bigintStatFsValues.buffer]).size === 4 &&
        \\Object.keys(actualFsBinding).join(",") === "statValues,bigintStatValues,statFsValues,bigintStatFsValues" &&
        \\ownerTrace.length === 0
    );
    const data = f.data.?;
    try std.testing.expect(data.weak_wrapper and data.strong_wrapper == null);
    try std.testing.expect(data.stats_field_array.global.?.cell != null);
    try std.testing.expect(bindings.get(try f.registry()) == data);
    try std.testing.expectEqual(@as(f64, 1), f.env().uidField(.counter).*);
}

test "native FS request owner accepts normal false native alias Set and weakens the unreferenced view" {
    var f: Fixture = undefined;
    try f.init(.{ .before_binding =
        \\globalThis.originalStatValue = { readonly:true };
        \\Object.defineProperty(Object.prototype, "statValues", {
        \\  value: originalStatValue, writable:false, configurable:true
        \\});
    });
    defer f.deinit();
    try f.expect(
        \\actualFsBinding.statValues === originalStatValue &&
        \\!Object.hasOwn(actualFsBinding, "statValues") &&
        \\Object.hasOwn(actualFsBinding, "bigintStatValues") &&
        \\Object.hasOwn(actualFsBinding, "statFsValues") &&
        \\Object.hasOwn(actualFsBinding, "bigintStatFsValues")
    );
    c.JS_RunGC(f.engine.runtime);
    const actual = c.JS_PiNativeGlobalGet(f.data.?.stats_field_array.global.?.cell.?);
    defer f.engine.freeValue(actual);
    try std.testing.expect(c.JS_IsUndefined(actual));
    try f.evaluate("delete Object.prototype.statValues;");
}

test "native FS request owner retains native BindingData through each real derived request" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const data = f.data.?;
    try std.testing.expectEqual(@as(c_uint, 0), data.pointer_data.?.strong_count);
    const first = try f.request(false);
    const second = try f.request(true);
    try std.testing.expectEqual(@as(c_uint, 2), data.pointer_data.?.strong_count);
    try std.testing.expect(data.strong_wrapper != null and !data.weak_wrapper);
    switch (second.stats_field_array) {
        .bigint => |values| try std.testing.expectEqual(@as(usize, 18), values.data.len),
        else => return error.ExpectedActualBigIntStatsAlias,
    }
    try f.settle(first, c.pi_js_undefined(), false);
    try first.wrap.retire(false);
    try std.testing.expectEqual(@as(c_uint, 1), data.pointer_data.?.strong_count);
    try f.settle(second, c.pi_js_undefined(), false);
    try second.wrap.retire(false);
    try std.testing.expectEqual(@as(c_uint, 0), data.pointer_data.?.strong_count);
    try std.testing.expect(data.weak_wrapper and data.strong_wrapper == null);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
}

test "native FS request owner returns the original one pending Promise and reads its live property" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const req = try f.request(false);
    const wrapper = try req.object();
    try f.expose("requestOwner", wrapper);
    const returned = f.keep(try req.returnPromise());
    try f.expose("returnedOwnerPromise", returned);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, returned));
    try f.expect(
        \\returnedOwnerPromise === requestOwner.promise && returnedOwnerPromise instanceof Promise &&
        \\Object.keys(requestOwner).join(",") === "promise" &&
        \\Object.getOwnPropertyDescriptor(requestOwner, "promise").writable === true &&
        \\Object.getOwnPropertyDescriptor(requestOwner, "promise").enumerable === true &&
        \\Object.getOwnPropertyDescriptor(requestOwner, "promise").configurable === true
    );
    try f.evaluate(
        \\globalThis.promiseReads = 0;
        \\Object.defineProperty(requestOwner, "promise", {
        \\  configurable:true, get() { promiseReads++; return returnedOwnerPromise; }
        \\});
    );
    const second = f.keep(try req.returnPromise());
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, returned, second));
    try f.expect("promiseReads === 1");
    try std.testing.expect(!req.finished);
}

test "native FS request owner settles the live replacement Promise without replacing the earlier return" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const req = try f.request(false);
    try f.expose("requestOwner", try req.object());
    const original = f.keep(try req.returnPromise());
    const replacement = f.keep(try f.value("new Promise(() => {})"));
    const payload = f.keep(try f.value("({payload:true})"));
    try f.expose("replacementOwnerPromise", replacement);
    try f.expose("ownerPayload", payload);
    try f.evaluate(
        \\globalThis.promiseReads = 0;
        \\Object.defineProperty(requestOwner, "promise", { configurable:true,
        \\  get() { promiseReads++; return replacementOwnerPromise; }
        \\});
    );
    const live_return = f.keep(try req.returnPromise());
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, live_return, replacement));
    try f.settle(req, payload, false);
    try std.testing.expect(req.finished);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, original));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, replacement));
    const result = c.JS_PromiseResult(f.engine.context, replacement);
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, payload, result));
    try f.expect("promiseReads === 2");
}

test "native FS request owner uses the captured request frame through before Get after and restores the parent" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const captured = f.keep(try f.value("'request-frame'"));
    try f.env().setContextFrame(captured);
    const req = try f.request(false);
    try f.expose("requestOwner", try req.object());
    try f.evaluate(
        \\globalThis.storedOwnerPromise = requestOwner.promise;
        \\Object.defineProperty(requestOwner, "promise", { configurable:true,
        \\  get() { ownerTrace.push(["get", actualFsOwnerFrame()]); return storedOwnerPromise; }
        \\});
    );
    f.env().field(.before).* = 1;
    f.env().field(.after).* = 1;
    const parent = f.keep(try f.value("'outside-frame'"));
    try f.env().setContextFrame(parent);
    try f.settle(req, c.JS_NewInt32(f.engine.context, 41), false);
    const restored = try f.env().currentContextFrame();
    defer f.engine.freeValue(restored);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, parent, restored));
    try std.testing.expectEqual(@as(usize, 0), f.env().callback_depth);
    try std.testing.expectEqual(@as(u32, 0), f.env().field(.stack_length).*);
    try f.expect(
        \\JSON.stringify(ownerTrace) === JSON.stringify([
        \\  ["before",2,true,"request-frame"], ["get","request-frame"],
        \\  ["after",2,true,"request-frame"]
        \\])
    );
}

test "native FS request owner preserves ordinary Error data in both fulfill and reject settlement" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const fulfilled = try f.request(false);
    const rejected = try f.request(false);
    const fulfilled_promise = f.keep(try fulfilled.returnPromise());
    const rejected_promise = f.keep(try rejected.returnPromise());
    const payload = f.keep(try f.value("new Error('ordinary request data')"));
    try f.settle(fulfilled, payload, false);
    try f.settle(rejected, payload, true);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, fulfilled_promise));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.engine.context, rejected_promise));
    const first = c.JS_PromiseResult(f.engine.context, fulfilled_promise);
    defer f.engine.freeValue(first);
    const second = c.JS_PromiseResult(f.engine.context, rejected_promise);
    defer f.engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, payload, first));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, payload, second));
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native FS request owner completes its callback destructor after an ordinary live Promise Get throw" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const req = try f.request(false);
    try f.expose("requestOwner", try req.object());
    const original = f.keep(try req.returnPromise());
    const reason = f.keep(try f.value("({ordinaryPromiseGetter:true})"));
    try f.expose("ownerGetterReason", reason);
    f.env().field(.before).* = 1;
    f.env().field(.after).* = 1;
    try f.evaluate(
        \\Object.defineProperty(requestOwner, "promise", { configurable:true,
        \\  get() { ownerTrace.push(["get-throw"]); throw ownerGetterReason; }
        \\});
    );
    var outer_scope: callbacks.Scope = undefined;
    try f.outer(&outer_scope, try req.object());
    defer if (!outer_scope.deinitialized) {
        outer_scope.markFailed();
        outer_scope.deinit() catch {};
    };
    try std.testing.expectError(error.JavaScriptException, req.resolve(c.JS_NewInt32(f.engine.context, 99)));
    const actual = try f.takeCaught();
    defer f.engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, actual));
    try std.testing.expect(req.finished);
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expectEqual(@as(u32, 1), f.env().field(.stack_length).*);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, original));
    try outer_scope.deinit();
    try f.expect(
        \\ownerTrace.length === 3 && ownerTrace[0][0] === "before" &&
        \\ownerTrace[1][0] === "get-throw" && ownerTrace[2][0] === "after"
    );
}

test "native FS request owner settled Promise bypasses incoming then lookup through the actual native resolver" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const req = try f.request(false);
    const promise = f.keep(try req.returnPromise());
    try f.settle(req, c.JS_NewInt32(f.engine.context, 17), false);
    const later = f.keep(try f.value(
        "({get then(){ throw new Error('settled native resolver observed then'); }})"));
    try f.settle(req, later, false);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, promise));
    const result = c.JS_PromiseResult(f.engine.context, promise);
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsNumber(result));
    var number: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.engine.context, &number, result));
    try std.testing.expectEqual(@as(i32, 17), number);
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native FS request owner realm cleanup follows the actual BindingData then request FIFO and clears native slots" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const first = try f.request(false);
    const second = try f.request(true);
    const first_wrapper = try first.object();
    const second_wrapper = try second.object();
    const registry = try f.registry();
    try std.testing.expect(registry.head == &f.data.?.base_entry);
    try std.testing.expect(registry.head.?.next == &first.wrap.base_entry);
    try std.testing.expect(registry.tail == &second.wrap.base_entry);
    try std.testing.expectEqual(@as(c_uint, 2), f.data.?.pointer_data.?.strong_count);
    try f.closeRealm();
    try std.testing.expect(registry.head == null and registry.tail == null);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expect(bindings.get(registry) == null);
    try std.testing.expect(registry.unwrap(first_wrapper) == null and registry.unwrap(second_wrapper) == null);
    try std.testing.expect(c.JS_GetOpaque(f.target, c.JS_GetClassID(f.target)) == null);
    // Actual JS Locals may outlive their deleted BaseObject and keep the view
    // properties alive; native weak cells have already been freed before VM GC.
    const key = "statValues";
    const view = c.JS_GetPropertyStr(f.engine.context, f.target, key);
    defer f.engine.freeValue(view);
    try std.testing.expect(c.JS_GetTypedArrayType(view) == c.JS_TYPED_ARRAY_FLOAT64);
    c.JS_RunGC(f.engine.runtime);
}

test "native FS request owner retained factory observes the real empty Realm weak slot after cleanup" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    const registry = try f.registry();
    try f.closeRealm();
    try std.testing.expect(bindings.get(registry) == null);
    const result = a.expression(f.engine, struct {
        fn create(s: *a.Scope, factory: c.JSValue) !c.JSValue {
            return requests.createRequest(s, factory, false, neverCancel);
        }
    }.create, .{f.factory});
    if (result) |unexpected| {
        f.engine.freeValue(unexpected);
        return error.ExpectedEmptyRealmBindingFailure;
    } else |err| {
        try std.testing.expectEqual(error.ActualFSReqPromiseBindingDataRequired, err);
    }
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}

// Physical setup owns the actual libuv/CRT descriptor. It stops and joins the
// real Hub before closing that descriptor on every normal/assertion path.
const PhysicalFile = struct {
    fixture: *Fixture,
    temporary: std.testing.TmpDir = undefined,
    temporary_ready: bool = false,
    path: ?[:0]u8 = null,
    descriptor: c_int = -1,

    fn init(self: *PhysicalFile, fixture: *Fixture, bytes: []const u8) !void {
        self.* = .{ .fixture = fixture };
        errdefer self.deinit();
        self.temporary = std.testing.tmpDir(.{});
        self.temporary_ready = true;
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "read.bin", .data = bytes });
        const directory = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
        defer std.testing.allocator.free(directory);
        const joined = try std.fs.path.join(std.testing.allocator, &.{directory, "read.bin"});
        defer std.testing.allocator.free(joined);
        self.path = try std.testing.allocator.dupeZ(u8, joined);
        var request: physical.uv_fs_t = undefined;
        const result = physical.uv_fs_open(null, &request, self.path.?.ptr, physical.O_RDONLY, 0, null);
        physical.uv_fs_req_cleanup(&request);
        if (result >= 0) self.descriptor = result;
        if (result < 0) return error.ActualFSReadControlOpenFailed;
        try fixture.expose("actualReadFd", c.JS_NewInt32(fixture.engine.context, self.descriptor));
    }
    fn deinit(self: *PhysicalFile) void {
        self.fixture.stopIo();
        if (self.descriptor >= 0) {
            var request: physical.uv_fs_t = undefined;
            const result = physical.uv_fs_close(null, &request, self.descriptor, null);
            physical.uv_fs_req_cleanup(&request);
            if (result != 0) @panic("actual FS read control descriptor did not close");
            self.descriptor = -1;
        }
        if (self.path) |path| {
            self.path = null;
            std.testing.allocator.free(path);
        }
        if (self.temporary_ready) {
            self.temporary_ready = false;
            self.temporary.cleanup();
        }
    }
};
fn expectOwnInt(f: *Fixture, object: c.JSValue, key: [*:0]const u8, expected: i32) !void {
    const result = c.JS_GetPropertyStr(f.engine.context, object, key);
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsNumber(result) and !c.JS_HasException(f.engine.context));
    var actual: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.engine.context, &actual, result));
    try std.testing.expectEqual(expected, actual);
}

test "native FS request owner physical Read constructs native storage before init and dispatches the actual view span" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    var file: PhysicalFile = undefined; try file.init(&f, "0123456789"); defer file.deinit();
    f.env().field(.init).* = 1;
    try f.evaluate(
        \\globalThis.ownerInitProbe = true;
        \\globalThis.actualReadBuffer = new ArrayBuffer(12);
        \\globalThis.actualReadView = new Uint8Array(actualReadBuffer, 3, 6);
    );
    const promise = f.keep(try f.value(
        "actualNativeRead(actualReadFd, actualReadView, 1, 4, 1, actualUsePromises)"));
    const request = try f.firstRequest();
    const wrapper = f.keep(a.duplicate(f.engine, try request.object()));
    const native_request = try f.retainNativeRequest();
    defer uv.pi_uv_fs_request_release(native_request);
    try std.testing.expectEqual(@as(usize, 1), f.init_probe_calls);
    try std.testing.expect(f.init_probe_prepared and f.init_probe_before_queue);
    try std.testing.expect(request.constructed and request.entry.dispatched and request.entry.counted);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
    try f.pumpPending();
    try f.expectPromiseInt(promise, 4);
    try f.expect(
        \\Array.from(new Uint8Array(actualReadBuffer)).join(",") === "0,0,0,0,49,50,51,52,0,0,0,0"
    );
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
    try std.testing.expect((try f.registry()).unwrap(wrapper) == null);
    const info = uv.pi_uv_fs_request_info(native_request);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    try std.testing.expectEqual(@as(c_int, 1), info.cleaned);
    try std.testing.expectEqual(@as(i64, 4), info.result);
}

test "native FS request owner physical Read uses DataView and wider typed-array byte spans" {
    const selected_views = [_][]const u8{
        "new DataView(actualReadBuffer, 4, 8)",
        "new Uint16Array(actualReadBuffer, 4, 4)",
    };
    for (selected_views) |view_source| {
        var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
        var file: PhysicalFile = undefined; try file.init(&f, "abcdefgh"); defer file.deinit();
        try f.evaluate("globalThis.actualReadBuffer = new ArrayBuffer(16);");
        const view = f.keep(try f.value(view_source));
        try f.expose("actualReadView", view);
        const promise = f.keep(try f.value(
            "actualNativeRead(actualReadFd, actualReadView, 1, 3, 2, actualUsePromises)"));
        try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
        try f.pumpPending();
        try f.expectPromiseInt(promise, 3);
        try f.expect(
            \\Array.from(new Uint8Array(actualReadBuffer)).join(",") === "0,0,0,0,0,99,100,101,0,0,0,0,0,0,0,0"
        );
        try std.testing.expect(f.env().requests.head == null);
    }
}

test "native FS request owner physical Read preserves BigInt wrapping safe minus zero and zero length" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    var file: PhysicalFile = undefined; try file.init(&f, "ABCDEFGH"); defer file.deinit();
    try f.evaluate("globalThis.actualReadView = new Uint8Array(8);");
    const first = f.keep(try f.value(
        "actualNativeRead(actualReadFd, actualReadView, -0, 1, (1n << 64n) + 3n, actualUsePromises)"));
    try f.pumpPending();
    try f.expectPromiseInt(first, 1);
    try f.expect("actualReadView[0] === 68 && actualReadView.slice(1).every(value => value === 0)");
    const second = f.keep(try f.value(
        "actualNativeRead(actualReadFd, actualReadView, -0, 0, -0, actualUsePromises)"));
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try f.pumpPending();
    try f.expectPromiseInt(second, 0);
    try f.expect("actualReadView[0] === 68 && actualReadView.slice(1).every(value => value === 0)");
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
}

test "native FS request owner physical Read retains backing storage before the real init hook transfers its buffer" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    var file: PhysicalFile = undefined; try file.init(&f, "storage"); defer file.deinit();
    f.env().field(.init).* = 1;
    try f.evaluate(
        \\globalThis.actualReadBuffer = new ArrayBuffer(8);
        \\globalThis.actualReadView = new Uint8Array(actualReadBuffer);
        \\globalThis.ownerInitAction = resource => {
        \\  globalThis.transferredReadPromise = resource.promise;
        \\  globalThis.transferredReadBuffer = actualReadBuffer.transfer();
        \\  delete globalThis.ownerInitAction;
        \\};
    );
    const promise = f.keep(try f.value(
        "actualNativeRead(actualReadFd, actualReadView, 0, 7, 0, actualUsePromises)"));
    const original = f.keep(try f.value("transferredReadPromise"));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, promise, original));
    try f.expect("actualReadBuffer.byteLength === 0 && actualReadView.byteLength === 0 && transferredReadBuffer.byteLength === 8");
    try f.pumpPending();
    try f.expectPromiseInt(promise, 7);
    try f.expect(
        \\Array.from(new Uint8Array(transferredReadBuffer)).join(",") === "115,116,111,114,97,103,101,0"
    );
    try std.testing.expect(f.env().requests.head == null);
}

test "native FS request owner physical Read still dispatches after the ordinary void return-Promise Get fails" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    var file: PhysicalFile = undefined; try file.init(&f, "GET"); defer file.deinit();
    f.env().field(.init).* = 1;
    try f.evaluate(
        \\globalThis.actualReadView = new Uint8Array(4);
        \\globalThis.readGetReason = { originalReturnGet: true };
        \\globalThis.readGetProgress = { gets: 0 };
        \\globalThis.ownerInitAction = resource => {
        \\  globalThis.readGetPromise = resource.promise;
        \\  Object.defineProperty(resource, "promise", { configurable: true, get() {
        \\    if (++readGetProgress.gets === 1) throw readGetReason;
        \\    return readGetPromise;
        \\  }});
        \\  delete globalThis.ownerInitAction;
        \\};
    );
    const reason = f.keep(try f.value("readGetReason"));
    const result = f.value(
        "actualNativeRead(actualReadFd, actualReadView, 0, 3, 0, actualUsePromises)");
    if (result) |unexpected| {
        f.engine.freeValue(unexpected);
        return error.ExpectedActualReturnPromiseGetFailure;
    } else |err| {
        try std.testing.expectEqual(error.JavaScriptException, err);
    }
    const caught = try f.takeCaught();
    defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, caught));
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    const request = try f.firstRequest();
    try std.testing.expect(request.entry.dispatched and request.entry.counted);
    const original = f.keep(try f.value("readGetPromise"));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, original));
    try f.pumpPending();
    try f.expectPromiseInt(original, 3);
    try f.expect("readGetProgress.gets === 2 && Array.from(actualReadView).join(',') === '71,69,84,0'");
    try std.testing.expect(f.env().requests.head == null and !c.JS_HasException(f.engine.context));
}

test "native FS request owner physical Read rejects accepted bad descriptors through actual UVException" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    try f.expose("actualReadEBADF", c.JS_NewInt32(f.engine.context, physical.UV_EBADF));
    const promise = f.keep(try f.value(
        "actualNativeRead(-1, new Uint8Array(4), 0, 1, 0, actualUsePromises)"));
    const native_request = try f.retainNativeRequest();
    defer uv.pi_uv_fs_request_release(native_request);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
    try f.pumpPending();
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.engine.context, promise));
    const reason = f.keep(c.JS_PromiseResult(f.engine.context, promise));
    try f.expose("actualReadRejection", reason);
    try f.expect(
        \\actualReadRejection instanceof Error && actualReadRejection.errno === actualReadEBADF &&
        \\actualReadRejection.code === "EBADF" && actualReadRejection.syscall === "read" &&
        \\!Object.hasOwn(actualReadRejection, "path") && !Object.hasOwn(actualReadRejection, "dest")
    );
    const info = uv.pi_uv_fs_request_info(native_request);
    try std.testing.expectEqual(@as(i64, physical.UV_EBADF), info.result);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    try std.testing.expectEqual(@as(c_int, 1), info.cleaned);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.waiting == 0);
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native FS request owner physical completion preserves live Promise getter failure and still retires the request" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    var file: PhysicalFile = undefined; try file.init(&f, "CALL"); defer file.deinit();
    f.env().field(.init).* = 1;
    f.env().field(.before).* = 1;
    f.env().field(.after).* = 1;
    try f.evaluate(
        \\globalThis.actualReadView = new Uint8Array(4);
        \\globalThis.readCompletionReason = { originalCompletionGet: true };
        \\globalThis.readCompletionProgress = { gets: 0 };
        \\globalThis.ownerInitAction = resource => {
        \\  globalThis.readCompletionPromise = resource.promise;
        \\  Object.defineProperty(resource, "promise", { configurable: true, get() {
        \\    if (++readCompletionProgress.gets === 2) {
        \\      ownerTrace.push(["completion-get"]);
        \\      throw readCompletionReason;
        \\    }
        \\    return readCompletionPromise;
        \\  }});
        \\  delete globalThis.ownerInitAction;
        \\};
    );
    const reason = f.keep(try f.value("readCompletionReason"));
    const promise = f.keep(try f.value(
        "actualNativeRead(actualReadFd, actualReadView, 0, 4, 0, actualUsePromises)"));
    const wrapper = f.keep(a.duplicate(f.engine, try (try f.firstRequest()).object()));
    const native_request = try f.retainNativeRequest();
    defer uv.pi_uv_fs_request_release(native_request);
    try std.testing.expectError(error.JavaScriptException, f.pumpPending());
    const caught = try f.takeCaught();
    defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, caught));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expectEqual(@as(usize, 0), f.env().callback_depth);
    try std.testing.expectEqual(@as(u32, 0), f.env().field(.stack_length).*);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.waiting == 0);
    try std.testing.expect((try f.registry()).unwrap(wrapper) == null);
    try std.testing.expectEqual(@as(c_int, 1), uv.pi_uv_fs_request_info(native_request).cleaned);
    try f.expect(
        \\readCompletionProgress.gets === 2 &&
        \\ownerTrace.map(row => row[0]).join(",") === "init,before,completion-get,after" &&
        \\Array.from(actualReadView).join(",") === "67,65,76,76"
    );
}

test "native FS request owner disabled Hub shutdown drains genuine queued reads without Promise or guest callbacks" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    var file: PhysicalFile = undefined; try file.init(&f, "DRAIN"); defer file.deinit();
    f.env().field(.init).* = 1;
    f.env().field(.before).* = 1;
    f.env().field(.after).* = 1;
    try f.evaluate(
        \\globalThis.readShutdownProgress = { gets: 0 };
        \\globalThis.ownerInitAction = resource => {
        \\  const promise = resource.promise;
        \\  Object.defineProperty(resource, "promise", { configurable: true, get() {
        \\    ++readShutdownProgress.gets;
        \\    return promise;
        \\  }});
        \\};
    );
    const progress = f.keep(try f.value("readShutdownProgress"));
    const trace = f.keep(try f.value("ownerTrace"));
    var native_requests: [3]*uv.PiUvFsRequest = undefined;
    var native_count: usize = 0;
    defer {
        for (native_requests[0..native_count]) |request| uv.pi_uv_fs_request_release(request);
    }
    var promises: [3]c.JSValue = undefined;
    var wrappers: [3]c.JSValue = undefined;
    for (&promises, &wrappers, &native_requests) |*promise, *wrapper, *actual| {
        promise.* = f.keep(try f.value(
            "actualNativeRead(actualReadFd, new Uint8Array(5), 0, 5, 0, actualUsePromises)"));
        const entry = f.env().requests.tail orelse return error.ActualFSReadRequestRequired;
        const request: *requests.Request = @alignCast(@fieldParentPtr("entry", entry));
        wrapper.* = f.keep(a.duplicate(f.engine, try request.object()));
        actual.* = request.native_request orelse return error.ActualFSReadNativeStorageRequired;
        uv.pi_uv_fs_request_retain(actual.*);
        native_count += 1;
    }
    try f.waitQueued(3);
    try std.testing.expectEqual(@as(c_int, 3), f.env().requests.waiting);
    f.stopIo();
    // Only known intrinsic/own-data observations follow actual JS disable.
    try std.testing.expect(!f.env().canCallIntoJs());
    try std.testing.expect(f.engine.native_env_context == null and f.engine.native_env_pump == null and
        f.engine.native_env_deinit == null);
    try expectOwnInt(&f, progress, "gets", 3);
    try expectOwnInt(&f, trace, "length", 3);
    for (promises, wrappers, native_requests) |promise, wrapper, actual| {
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
        try std.testing.expect((try f.registry()).unwrap(wrapper) == null);
        const info = uv.pi_uv_fs_request_info(actual);
        try std.testing.expectEqual(@as(c_int, 1), info.accepted);
        try std.testing.expectEqual(@as(c_int, 1), info.cleaned);
        try std.testing.expectEqual(@as(i64, 5), info.result);
    }
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native FS request owner retained Read controller refuses admission after the real Hub is retired" {
    var f: Fixture = undefined; try f.init(.{ .physical_read = true }); defer f.deinit();
    const retained = f.controller.?.retain();
    defer retained.release();
    f.stopIo();
    try std.testing.expect(retained.stopping);
    try std.testing.expect(f.engine.native_env_context == null and f.engine.native_env_pump == null and
        f.engine.native_env_deinit == null);
    try std.testing.expectError(error.NativeEnvClosed, retained.beginCall(f.engine));
    const result = read_binding.create(f.engine, .{
        .controller = retained, .use_promises = f.use_promises, .request_factory = f.factory,
    });
    if (result) |unexpected| {
        f.engine.freeValue(unexpected);
        return error.ExpectedActualStoppedReadAdmissionFailure;
    } else |err| {
        try std.testing.expectEqual(error.NativeEnvClosed, err);
    }
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
}
