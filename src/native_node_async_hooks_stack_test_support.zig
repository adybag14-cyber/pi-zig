//! Actual-VM and actual-Environment controls for the selected JS async stack.
//! The three fallback bridges call the existing native Environment operations.
//! Unselected hook/fatal/queue policies fail explicitly and make no exit claim.
const std = @import("std");
pub const a = @import("extensions/native_node_argument_values.zig");
pub const c = a.c;
pub const callbacks = @import("extensions/native_node_callback_scope.zig");
pub const owner = @import("extensions/native_node_async_hooks_stack.zig");
const functions = @import("extensions/native_node_module_callable.zig");
pub const owner_key = "pi-native:private/async-hooks-id-stack";
pub const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    host_environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    host_environment_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    binding: c.JSValue = undefined,
    exported: c.JSValue = undefined,
    first_fatal: c.JSValue = undefined,
    native_push_count: usize = 0,
    native_pop_count: usize = 0,
    native_clear_count: usize = 0,
    corruption_count: usize = 0,
    expected_corruption_id: f64 = 0,
    native_receivers_undefined: bool = true,
    pub fn init(self: *Fixture, install_owner: bool) !void {
        return self.initUsing(std.testing.allocator, install_owner);
    }
    pub fn initUsing(self: *Fixture, allocator: std.mem.Allocator, install_owner: bool) !void {
        self.* = .{};
        self.host_environment = .init(std.testing.allocator);
        self.host_environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(allocator, .{});
        self.engine_alive = true;
        self.binding = c.pi_js_undefined();
        self.exported = c.pi_js_undefined();
        self.first_fatal = c.pi_js_undefined();
        self.engine.host_control_context = self;
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.host_environment, &.{"native-async-stack-control"});
        try self.engine.bindFunction("actualStackPush", nativePush, 2);
        try self.engine.bindFunction("actualStackPop", nativePop, 1);
        try self.engine.bindFunction("actualStackClear", nativeClear, 0);
        try self.engine.bindFunction("stackNativeFatal", rawFatal, 0);
        try self.engine.bindFunction("stackDropOwner", dropOwner, 0);
        try self.run("globalThis.stackTrace=[];globalThis.unselectedStackHook=function(){throw Error('unselected async hook')};");
        self.binding = try a.expression(self.engine, bootstrapBody, .{self});
        try self.publish("stackBinding", self.binding);
        const factory = try self.engine.eval(@embedFile("../durable/fixtures/native-node-async-hooks-stack-original.js"),
            "original-async-stack-selected.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(factory);
        const reference = try a.expression(self.engine, referenceBody, .{ factory, self.binding });
        defer self.engine.freeValue(reference);
        try self.publish("R", reference);
        if (install_owner) try self.install();
    }
    pub fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    pub fn install(self: *Fixture) !void {
        self.exported = try owner.create(self.engine, self.env(), self.binding);
        try self.publish("S", self.exported);
    }
    pub fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "native-async-stack-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    pub fn check(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "native-async-stack-control.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_IsStrictEqual(self.engine.context, result, c.JS_NewBool(self.engine.context, true)));
    }
    pub fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global_object);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global_object, name,
            a.duplicate(self.engine, value), c.JS_PROP_C_W_E) < 0)
            return error.ActualAsyncStackTestPublication;
    }
    pub fn get(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global_object = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global_object);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global_object, name));
    }
    pub fn reason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualAsyncStackTestReason;
    }
    pub fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
    pub fn closeEnvironment(self: *Fixture) !void {
        const environment = self.environment orelse return;
        try environment.cleanupRealmAfterIoJoin();
        try environment.disarm();
        self.environment = null;
        environment.release();
    }
    pub fn deinit(self: *Fixture) void {
        self.closeEnvironment() catch @panic("async stack Environment teardown failed");
        if (self.engine_alive) {
            self.engine.freeValue(self.exported);
            self.engine.freeValue(self.binding);
            self.engine.freeValue(self.first_fatal);
            self.engine.host_control_context = null;
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (self.host_environment_alive) {
            self.host_environment.deinit();
            self.host_environment_alive = false;
        }
    }
};
fn bootstrapBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    const global_object = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const process_value = try s.get(global_object, "process");
    const generation = try s.beforeAllocation();
    const resource_symbol = try s.checkedAllocation(
        c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), generation);
    fixture.environment = try callbacks.Environment.create(s.engine, .{
        .provider_names = &.{}, .resource_symbol = resource_symbol,
        .process_object = process_value, .async_context_frame = false,
        .operations = operations,
    });
    const environment = fixture.env();
    const resources = try s.own(try environment.acquireExecutionAsyncResources());
    const binding_value = try s.object();
    try s.define(binding_value, "async_hook_fields", environment.fields.view.?, c.JS_PROP_C_W_E);
    try s.define(binding_value, "async_id_fields", environment.uid.view.?, c.JS_PROP_C_W_E);
    try s.define(binding_value, "execution_async_resources", resources, c.JS_PROP_C_W_E);
    try s.define(binding_value, "async_ids_stack", environment.ids.view.?, c.JS_PROP_C_W_E);
    try s.define(binding_value, "pushAsyncContext", try s.get(global_object, "actualStackPush"), c.JS_PROP_C_W_E);
    try s.define(binding_value, "popAsyncContext", try s.get(global_object, "actualStackPop"), c.JS_PROP_C_W_E);
    try s.define(binding_value, "clearAsyncIdStack", try s.get(global_object, "actualStackClear"), c.JS_PROP_C_W_E);
    const constants = try s.object();
    inline for (.{
        .{ "kInit", callbacks.Field.init }, .{ "kBefore", callbacks.Field.before },
        .{ "kAfter", callbacks.Field.after }, .{ "kDestroy", callbacks.Field.destroy },
        .{ "kCheck", callbacks.Field.check }, .{ "kStackLength", callbacks.Field.stack_length },
    }) |entry| try s.define(constants, entry[0],
        c.JS_NewUint32(s.engine.context, @intFromEnum(entry[1])), c.JS_PROP_C_W_E);
    inline for (.{
        .{ "kExecutionAsyncId", callbacks.Uid.execution },
        .{ "kTriggerAsyncId", callbacks.Uid.trigger },
        .{ "kAsyncIdCounter", callbacks.Uid.counter },
        .{ "kDefaultTriggerAsyncId", callbacks.Uid.default_trigger },
    }) |entry| try s.define(constants, entry[0],
        c.JS_NewUint32(s.engine.context, @intFromEnum(entry[1])), c.JS_PROP_C_W_E);
    try s.define(binding_value, "constants", constants, c.JS_PROP_C_W_E);
    const guard = try s.get(global_object, "unselectedStackHook");
    try environment.installHooks(.{
        .init = guard, .before = guard, .after = guard,
        .destroy = guard, .promise_resolve = guard,
    }, binding_value);
    try s.define(global_object, "stackFields", environment.fields.view.?, c.JS_PROP_C_W_E);
    try s.define(global_object, "stackUid", environment.uid.view.?, c.JS_PROP_C_W_E);
    try s.define(global_object, "stackResources", resources, c.JS_PROP_C_W_E);
    try s.define(global_object, "originalStackView", environment.ids.view.?, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, binding_value);
}
fn referenceBody(s: *a.Scope, factory: c.JSValue, binding_value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(factory, c.pi_js_undefined(), &.{binding_value}));
}
fn fixtureFor(context: ?*c.JSContext) *Fixture {
    const engine = a.v.em.Engine.fromContext(context.?);
    return @ptrCast(@alignCast(engine.host_control_context.?));
}
fn nativePush(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = fixtureFor(context);
    fixture.native_push_count += 1;
    fixture.native_receivers_undefined = fixture.native_receivers_undefined and c.JS_IsUndefined(receiver);
    if (argc != 2 or !c.JS_IsNumber(argv[0]) or !c.JS_IsNumber(argv[1]))
        return functions.failure(fixture.engine, error.ActualNativePushTestInputs, 0);
    var async_id: f64 = 0; var trigger_id: f64 = 0;
    if (c.JS_ToFloat64(context, &async_id, argv[0]) < 0 or c.JS_ToFloat64(context, &trigger_id, argv[1]) < 0)
        return functions.failure(fixture.engine, error.JavaScriptException, 0);
    fixture.env().pushAsyncContext(.{ .async_id = async_id, .trigger_async_id = trigger_id }, null) catch |err|
        return functions.failure(fixture.engine, err, 0);
    return c.pi_js_undefined();
}
fn nativePop(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = fixtureFor(context);
    fixture.native_pop_count += 1;
    fixture.native_receivers_undefined = fixture.native_receivers_undefined and c.JS_IsUndefined(receiver);
    if (argc != 1 or !c.JS_IsNumber(argv[0]))
        return functions.failure(fixture.engine, error.ActualNativePopTestInputs, 0);
    var expected_id: f64 = 0;
    if (c.JS_ToFloat64(context, &expected_id, argv[0]) < 0)
        return functions.failure(fixture.engine, error.JavaScriptException, 0);
    const remaining = fixture.env().popAsyncContext(expected_id) catch |err|
        return functions.failure(fixture.engine, err, 0);
    return c.pi_js_bool(context, @intFromBool(remaining));
}
fn nativeClear(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = fixtureFor(context);
    fixture.native_clear_count += 1;
    fixture.env().clearAsyncIdStack() catch |err| return functions.failure(fixture.engine, err, 0);
    return c.pi_js_undefined();
}
fn unselected(_: *callbacks.Environment) anyerror!void { return error.UnselectedActualAsyncStackOperation; }
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror { return error.UnselectedActualAsyncStackCheck; }
fn unselectedCorruption(environment: *callbacks.Environment, expected_id: f64) anyerror {
    const engine = environment.requireEngine() catch return error.NativeNodeEnvironmentClosed;
    const fixture: *Fixture = @ptrCast(@alignCast(engine.host_control_context.?));
    fixture.corruption_count += 1;
    fixture.expected_corruption_id = expected_id;
    return error.UnselectedActualCorruptedStackExit;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected, .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption, .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected, .request_destroy_interrupt = unselected,
};
fn rawFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = fixtureFor(context);
    _ = fixture.engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(fixture.engine.context)) {
        const value = c.JS_GetException(fixture.engine.context);
        if (c.JS_IsUndefined(fixture.first_fatal)) fixture.first_fatal = a.duplicate(fixture.engine, value);
        fixture.engine.freeValue(value);
    }
    return c.pi_js_undefined();
}
fn dropOwner(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = fixtureFor(context);
    var completion = a.owned.Completion.initVoid(fixture.engine, {});
    if (fixture.engine.native_module_values.fetchRemove(owner_key)) |removed| completion.release(removed.value);
    completion.finishVoid() catch |err| return functions.failure(fixture.engine, err, 0);
    return c.pi_js_undefined();
}
