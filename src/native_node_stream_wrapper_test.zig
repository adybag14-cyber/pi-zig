//! Native StreamBase wrapper internal-field ownership controls.
//! The actual Registry/State classes, Environment and QuickJS collector are
//! exercised directly. No substitute FileHandle constructor or public onread
//! accessor is installed. Hook/checkpoint/fatal operations are unselected.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const native = @import("extensions/native_node_async_wrap_state.zig");
const callable = @import("extensions/native_node_module_callable.zig");

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedStreamFieldsOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedStreamFieldsNativeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedStreamFieldsCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

const Probe = struct {
    fixture: *Fixture,
    count: usize = 0,
    observe_replacement: bool = false,
    wrapper: c.JSValue = undefined, // borrowed only during the replacement call
    replacement: c.JSValue = undefined,
    saw_replacement: bool = false,
    read_failed: bool = false,
};
fn markerFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    p.count += 1;
    p.fixture.append('m');
    if (p.observe_replacement) {
        p.observe_replacement = false;
        const selected = p.fixture.getOnRead(p.wrapper) catch |err| {
            p.read_failed = true;
            _ = callable.failure(p.fixture.engine, err, 0);
            return;
        };
        p.saw_replacement = c.JS_IsStrictEqual(p.fixture.engine.context, selected, p.replacement);
        p.fixture.engine.freeValue(selected);
    }
}
fn onRead(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    return c.pi_js_undefined();
}

const Node = struct {
    state: native.State = undefined,
    fixture: *Fixture,
    stream_token: u8 = 0,

    fn retire(state: *native.State, _: *a.Scope) !void {
        const self: *Node = @alignCast(@fieldParentPtr("state", state));
        self.fixture.retired += 1;
        self.fixture.append('r');
    }
    fn destroy(state: *native.State) void {
        const self: *Node = @alignCast(@fieldParentPtr("state", state));
        const allocator = state.registry.environment.allocator();
        self.fixture.destroyed += 1;
        self.fixture.append('d');
        allocator.destroy(self);
    }
    fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {}
    const derived: native.Derived = .{ .mark = mark, .retire = retire, .destroy = destroy };
};

const Fixture = struct {
    native_environment: std.process.Environ.Map,
    native_environment_alive: bool = true,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    registry_owner: ?*native.Registry = null,
    prototype: ?c.JSValue = null,
    marker_class: c.JSClassID = 0,
    probes: [4]Probe = undefined,
    retired: usize = 0,
    destroyed: usize = 0,
    trace: [32]u8 = undefined,
    trace_length: usize = 0,

    fn init(self: *Fixture) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator) };
        for (&self.probes) |*probe| probe.* = .{ .fixture = self };
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-stream-fields"});
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const allocation = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), allocation);
        const environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false),
            .resource_symbol = symbol,
            .process_object = process,
            .async_context_frame = true,
            .operations = operations,
        });
        self.environment = environment;
        environment.markBootstrapComplete();
        self.registry_owner = try native.Registry.create(s.engine, environment);
        const object = try s.get(global, "Object");
        self.prototype = a.duplicate(s.engine, try s.get(object, "prototype"));
        const generation = try s.beforeAllocation();
        if (c.JS_NewClassID(s.engine.runtime, &self.marker_class) == 0)
            return error.OutOfMemory;
        const definition: c.JSClassDef = .{
            .class_name = "Actual StreamFields edge marker",
            .finalizer = markerFinalizer,
        };
        const status = c.JS_NewClass(s.engine.runtime, self.marker_class, &definition);
        try s.boundary.checkPendingSince(generation);
        if (status < 0) return error.OutOfMemory;
        return c.pi_js_undefined();
    }
    fn registry(self: *Fixture) *native.Registry { return self.registry_owner.?; }
    fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    fn append(self: *Fixture, byte: u8) void {
        std.debug.assert(self.trace_length < self.trace.len);
        self.trace[self.trace_length] = byte;
        self.trace_length += 1;
    }
    fn wrapper(self: *Fixture) !c.JSValue {
        return a.expression(self.engine, wrapperBody, .{self});
    }
    fn wrapperBody(s: *a.Scope, self: *Fixture) !c.JSValue {
        return a.duplicate(s.engine,
            try self.registry().newInstance(s, .filehandle, self.prototype.?));
    }
    fn callback(self: *Fixture, probe_index: usize, back_edge: c.JSValue) !c.JSValue {
        return a.expression(self.engine, callbackBody, .{ self, probe_index, back_edge });
    }
    fn callbackBody(s: *a.Scope, self: *Fixture, probe_index: usize, back_edge: c.JSValue) !c.JSValue {
        const allocation = try s.beforeAllocation();
        const marker = try s.checkedAllocation(
            c.JS_NewObjectClass(s.engine.context, self.marker_class), allocation);
        _ = c.JS_SetOpaque(marker, &self.probes[probe_index]);
        var roots = [_]c.JSValue{ marker, back_edge };
        const function_allocation = try s.beforeAllocation();
        const function = try s.checkedAllocation(c.JS_NewCFunctionData2(s.engine.context,
            onRead, "actualStreamOnRead", 1, 0, roots.len, &roots), function_allocation);
        return a.duplicate(s.engine, function);
    }
    fn getOnRead(self: *Fixture, wrapper_value: c.JSValue) !c.JSValue {
        return a.expression(self.engine, struct {
            fn body(s: *a.Scope, registry_value: *native.Registry, object: c.JSValue) !c.JSValue {
                try s.pending();
                return a.duplicate(s.engine, try registry_value.streamOnRead(s, object));
            }
        }.body, .{ self.registry(), wrapper_value });
    }
    fn setOnRead(self: *Fixture, wrapper_value: c.JSValue, function: c.JSValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, registry_value: *native.Registry, object: c.JSValue, callback_value: c.JSValue) !c.JSValue {
                try s.pending();
                try registry_value.setStreamOnRead(s, object, callback_value);
                return c.pi_js_undefined();
            }
        }.body, .{ self.registry(), wrapper_value, function });
        self.engine.freeValue(ignored);
    }
    fn attach(self: *Fixture, wrapper_value: c.JSValue) !*Node {
        const node = try self.env().allocator().create(Node);
        node.* = .{ .fixture = self };
        // Once attached, the real Registry/realm cleanup owns this allocation,
        // including an initialize failure after BaseObject publication.
        errdefer if (self.registry().unwrap(wrapper_value) != &node.state)
            self.env().allocator().destroy(node);
        try node.state.initialize(self.registry(), wrapper_value, Node.derived,
            native.Provider.filehandle, -1);
        return node;
    }
    fn hasOwnOnRead(self: *Fixture, wrapper_value: c.JSValue) !bool {
        const result = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, object: c.JSValue) !c.JSValue {
                return a.boolean(s, try s.hasOwn(object, try s.text("onread")));
            }
        }.body, .{wrapper_value});
        defer self.engine.freeValue(result);
        return c.JS_ToBool(self.engine.context, result) == 1;
    }
    fn expose(self: *Fixture, wrapper_value: c.JSValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, object: c.JSValue) !c.JSValue {
                const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.define(global, "actualStreamWrapper", object, c.JS_PROP_C_W_E);
                return c.pi_js_undefined();
            }
        }.body, .{wrapper_value});
        self.engine.freeValue(ignored);
    }
    fn drop(self: *Fixture, value: *c.JSValue) void {
        const previous = value.*;
        value.* = c.pi_js_undefined();
        self.engine.freeValue(previous);
    }
    fn takeCaught(self: *Fixture) !c.JSValue {
        const reason = self.engine.captured_exception orelse
            return error.ExpectedActualStreamFieldsReason;
        self.engine.captured_exception = null;
        return reason;
    }
    fn closeRealm(self: *Fixture) !void {
        if (self.environment) |environment| {
            environment.can_call_into_js = false;
            try environment.cleanupRealmAfterIoJoin();
        }
    }
    fn disarm(self: *Fixture) !void {
        if (self.environment) |environment| {
            if (!environment.disarmed) {
                try self.closeRealm();
                try environment.disarm();
            }
        }
    }
    fn deinit(self: *Fixture) void {
        self.disarm() catch @panic("StreamFields realm/environment teardown failed");
        if (self.registry_owner) |registry_value| {
            self.registry_owner = null;
            registry_value.release();
        }
        if (self.prototype) |value| {
            self.prototype = null;
            self.engine.freeValue(value);
        }
        if (self.environment) |environment| {
            self.environment = null;
            environment.release();
        }
        if (self.engine_alive) {
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (self.native_environment_alive) {
            self.native_environment_alive = false;
            self.native_environment.deinit();
        }
    }
};

test "Node StreamFields initial internal value is undefined and wrapper brand precedes native attachment" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    try std.testing.expect(f.registry().hasTemplateBrand(wrapper));
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try std.testing.expect(f.registry().streamPointer(wrapper) == null);
    const initial = try f.getOnRead(wrapper); defer f.engine.freeValue(initial);
    try std.testing.expect(c.JS_IsUndefined(initial));
    try std.testing.expect(!try f.hasOwnOnRead(wrapper));
    try std.testing.expect(f.registry().head == null and f.registry().tail == null);
}

test "Node StreamFields real callback edge is internal and survives collection while wrapper remains rooted" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    var function = try f.callback(0, c.pi_js_undefined()); defer f.drop(&function);
    try f.setOnRead(wrapper, function);
    {
        const selected = try f.getOnRead(wrapper); defer f.engine.freeValue(selected);
        try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, selected, function));
    }
    try std.testing.expect(!try f.hasOwnOnRead(wrapper));
    f.drop(&function);
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(@as(usize, 0), f.probes[0].count);
}

test "Node StreamFields replacement is published before the previous sole callback edge retires" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    var first = try f.callback(0, c.pi_js_undefined()); defer f.drop(&first);
    var second = try f.callback(1, c.pi_js_undefined()); defer f.drop(&second);
    try f.setOnRead(wrapper, first);
    f.drop(&first);
    f.probes[0].observe_replacement = true;
    f.probes[0].wrapper = wrapper;
    f.probes[0].replacement = second;
    try f.setOnRead(wrapper, second);
    try std.testing.expectEqual(@as(usize, 1), f.probes[0].count);
    try std.testing.expect(f.probes[0].saw_replacement and !f.probes[0].read_failed);
    try std.testing.expectEqual(@as(usize, 0), f.probes[1].count);
}

test "Node StreamFields native deletion clears only the State slot and leaves the actual onread value" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    const node = try f.attach(wrapper);
    try f.registry().setStreamPointer(wrapper, &node.stream_token);
    try std.testing.expect(f.registry().streamPointer(wrapper) == @as(*anyopaque, &node.stream_token));
    var function = try f.callback(0, c.pi_js_undefined()); defer f.drop(&function);
    try f.setOnRead(wrapper, function);
    try node.state.deleteMe();
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expectEqual(@as(usize, 1), f.destroyed);
    try std.testing.expect(f.registry().hasTemplateBrand(wrapper));
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try std.testing.expect(f.registry().streamPointer(wrapper) == null);
    const selected = try f.getOnRead(wrapper); defer f.engine.freeValue(selected);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, selected, function));
    try std.testing.expectEqual(@as(usize, 0), f.probes[0].count);
}

test "Node StreamFields native strong wrapper root retains a real callback cycle until DeleteMe" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    const node = try f.attach(wrapper);
    var function = try f.callback(0, wrapper); defer f.drop(&function);
    try f.setOnRead(wrapper, function);
    f.drop(&function);
    f.drop(&wrapper);
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(@as(usize, 0), f.destroyed);
    try std.testing.expectEqual(@as(usize, 0), f.probes[0].count);
    try node.state.deleteMe();
    try std.testing.expectEqual(@as(usize, 1), f.destroyed);
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(@as(usize, 1), f.probes[0].count);
    try std.testing.expect(f.registry().head == null and f.registry().tail == null);
}

test "Node StreamFields real weak wrapper retirement destroys native state before its callback edge" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    const node = try f.attach(wrapper);
    var function = try f.callback(0, c.pi_js_undefined()); defer f.drop(&function);
    try f.setOnRead(wrapper, function);
    f.drop(&function);
    try node.state.makeWeak();
    f.drop(&wrapper);
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expectEqual(@as(usize, 1), f.destroyed);
    try std.testing.expectEqual(@as(usize, 1), f.probes[0].count);
    try std.testing.expectEqualSlices(u8, "rdm", f.trace[0..f.trace_length]);
}

test "Node StreamFields realm cleanup detaches native state while late wrapper releases after disarm" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var wrapper = try f.wrapper(); defer f.drop(&wrapper);
    _ = try f.attach(wrapper);
    var function = try f.callback(0, c.pi_js_undefined()); defer f.drop(&function);
    try f.setOnRead(wrapper, function);
    f.drop(&function);
    try f.closeRealm();
    try std.testing.expectEqual(@as(usize, 1), f.destroyed);
    try std.testing.expectEqual(@as(usize, 0), f.probes[0].count);
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try f.disarm();
    try std.testing.expect(f.env().engine == null and f.env().disarmed);
    f.drop(&wrapper);
    try std.testing.expectEqual(@as(usize, 1), f.probes[0].count);
}

test "Node StreamFields VM teardown retires detached onread after Fixture registry and Environment entitlements" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    {
        var wrapper = try f.wrapper(); defer f.drop(&wrapper);
        _ = try f.attach(wrapper);
        var function = try f.callback(0, c.pi_js_undefined()); defer f.drop(&function);
        try f.setOnRead(wrapper, function);
        try f.expose(wrapper);
    }
    f.deinit();
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expectEqual(@as(usize, 1), f.destroyed);
    try std.testing.expectEqual(@as(usize, 1), f.probes[0].count);
    try std.testing.expectEqualSlices(u8, "rdm", f.trace[0..f.trace_length]);
}

test "Node StreamFields existing pending reason wins before native fields allocation at exhausted quota" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const reason = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(reason);
    const references = f.registry().references;
    const charged = f.env().charged.used.load(.acquire);
    const generation = f.engine.native_allocation_generation;
    var scope = a.Scope.init(f.engine);
    _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, reason));
    const budget = f.engine.options.memory_limit - c.pi_js_native_memory_used(f.engine.native_memory_owner);
    const reserved = c.pi_js_native_memory_reserve(f.engine.native_memory_owner, budget);
    // Restore quota before finish can produce any ordinary diagnostic bytes.
    const outcome = Fixture.wrapperBody(&scope, &f);
    if (reserved != 0) c.pi_js_native_memory_release(f.engine.native_memory_owner, budget);
    const result = scope.finish(outcome);
    if (result) |unexpected| {
        f.engine.freeValue(unexpected);
        return error.ExpectedActualStreamFieldsPendingFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    const actual = try f.takeCaught(); defer f.engine.freeValue(actual);
    try std.testing.expectEqual(@as(c_int, 1), reserved);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, actual));
    try std.testing.expectEqual(generation, f.engine.native_allocation_generation);
    try std.testing.expectEqual(references, f.registry().references);
    try std.testing.expectEqual(charged, f.env().charged.used.load(.acquire));
}

test "Node StreamFields failed intrinsic wrapper allocation retires unattached native field storage" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const references = f.registry().references;
    const charged = f.env().charged.used.load(.acquire);
    var scope = a.Scope.init(f.engine);
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const outcome = Fixture.wrapperBody(&scope, &f);
    c.JS_SetMemoryLimit(f.engine.runtime, f.engine.options.memory_limit);
    const result = scope.finish(outcome);
    if (result) |unexpected| {
        f.engine.freeValue(unexpected);
        return error.ExpectedActualStreamFieldsAllocationFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    const reason = try f.takeCaught(); defer f.engine.freeValue(reason);
    try std.testing.expectEqual(references, f.registry().references);
    try std.testing.expectEqual(charged, f.env().charged.used.load(.acquire));
    try std.testing.expect(f.registry().head == null and f.registry().tail == null);
}
