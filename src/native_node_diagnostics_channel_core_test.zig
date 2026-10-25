//! Actual-VM and literal-source controls for the complete Channel registry core.
//! Compilation, metadata and runtime remain Root-owned. The explicit native
//! error-binding probe records exact calls; production report/exit admission
//! is deliberately not fabricated or claimed by these controls.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const em = a.v.em;
const owner = @import("extensions/native_node_diagnostics_channel_core.zig");
const errors = @import("extensions/native_node_argument_errors.zig");
const bootstrap = @import("extensions/native_node_argument_bootstrap.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
const weak_owner = @import("extensions/native_node_weak_reference.zig");
const weak_maps = @import("extensions/native_node_weak_ref_map.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const events = @import("extensions/node_events.zig");
const async_scope = @import("extensions/native_async_scope.zig");
const original = @embedFile("extensions/fixtures/node-diagnostics-channel-core-original.js");
const observer = @embedFile("extensions/fixtures/node-diagnostics-channel-core-observer.js");
const cache_key = "pi-native:private/diagnostics-channel-core";

const Fixture = struct {
    engine: *em.Engine = undefined,
    environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    environment_alive: bool = false,
    prepared: ?bootstrap.Prepared = null,
    process: c.JSValue = undefined,
    trigger: c.JSValue = undefined,
    weak: c.JSValue = undefined,
    subject: c.JSValue = undefined,
    report_count: usize = 0,
    reasons: [32]c.JSValue = undefined,
    origins: [32]c.JSValue = undefined,
    scopes: [32]c.JSValue = undefined,
    arities: [32]usize = undefined,
    receiver_undefined: [32]bool = undefined,
    probe_class: c.JSClassID = 0,
    retired: usize = 0,
    message_calls: usize = 0,
    emit_fatal: bool = false,
    first_fatal: c.JSValue = undefined,
    scope_active: bool = false,
    partner: ?*Fixture = null,
    cross_error: ?anyerror = null,

    fn init(self: *Fixture, source: bool, create_subject: bool) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator);
        self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        self.process = c.pi_js_undefined(); self.trigger = c.pi_js_undefined();
        self.weak = c.pi_js_undefined(); self.subject = c.pi_js_undefined();
        self.first_fatal = c.pi_js_undefined();
        self.engine.host_control_context = self;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-channel-core-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.prepared = try bootstrap.prepare(self.engine);
        const safe_map = try collections.acquireSafeMap(self.engine);
        defer self.engine.freeValue(safe_map);
        const safe_finalizers = try collections.acquireSafeFinalizationRegistry(self.engine);
        defer self.engine.freeValue(safe_finalizers);
        self.weak = try weak_owner.create(self.engine);
        const process_record = self.engine.native_module_values.get("node:process").?;
        self.process = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, process_record, "default"));
        try self.engine.bindFunction("dcTrigger", rawTrigger, 2);
        try self.engine.bindFunction("dcCrossAcquire", rawCrossAcquire, 0);
        try self.engine.bindFunction("dcReports", rawReports, 0);
        try self.engine.bindFunction("dcDropReports", rawDropReports, 0);
        try self.engine.bindFunction("dcPending", rawPending, 0);
        try self.engine.bindFunction("dcFatal", rawFatal, 0);
        try self.engine.bindFunction("dcRetired", rawRetired, 0);
        try self.engine.bindFunction("dcEntryProbe", rawEntryProbe, 2);
        try self.engine.bindFunction("dcMessageProbe", rawMessageProbe, 0);
        self.trigger = try self.global("dcTrigger");
        try self.publish("P", self.process);
        try self.publish("WeakReferenceOwner", self.weak);
        if (create_subject) try self.createSubject(source);
        try self.run(observer);
    }
    fn inputs(self: *Fixture) owner.Inputs {
        return .{ .process = self.process, .trigger_uncaught_exception = self.trigger, .weak_reference = self.weak };
    }
    fn createSubject(self: *Fixture, source: bool) !void {
        const next = if (source) try a.expression(self.engine, sourceBody, .{self})
            else try owner.acquire(self.engine, self.inputs());
        self.engine.freeValue(self.subject);
        self.subject = next;
        try self.publish("D", next);
    }
    fn eval(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "native-channel-core-control.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn run(self: *Fixture, source: []const u8) !void { self.engine.freeValue(try self.eval(source)); }
    fn check(self: *Fixture, source: []const u8) !void {
        const value = try self.eval(source); defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_IsStrictEqual(self.engine.context, value, c.JS_NewBool(self.engine.context, true)));
    }
    fn global(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const object = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(object);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, object, name));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const object = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(object);
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name,
            a.duplicate(self.engine, value), c.JS_PROP_C_W_E) < 0)
            return @import("extensions/native_js_values.zig").capture(self.engine);
    }
    fn drain(self: *Fixture) !void {
        try events.drainHostTicks(self.engine);
        _ = try self.engine.runReadyJobs(256);
        self.engine.finishJob();
        try std.testing.expect(!c.JS_IsJobPending(self.engine.runtime));
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expect(!c.JS_HasException(self.engine.context));
        try std.testing.expect(self.engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
    }
    fn takeReason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| {
            self.engine.captured_exception = null;
            return value;
        }
        return error.ActualChannelControlReasonRequired;
    }
    fn dropReports(self: *Fixture) void {
        for (0..self.report_count) |i| {
            self.engine.freeValue(self.reasons[i]); self.engine.freeValue(self.origins[i]);
            self.engine.freeValue(self.scopes[i]);
        }
        self.report_count = 0;
    }
    fn deinit(self: *Fixture) void {
        self.emit_fatal = false;
        if (self.engine_alive) {
            self.dropReports();
            self.engine.freeValue(self.subject); self.engine.freeValue(self.trigger);
            self.engine.freeValue(self.weak); self.engine.freeValue(self.process);
            self.engine.freeValue(self.first_fatal);
            if (self.prepared) |prepared| prepared.deinit(self.engine);
            self.engine.deinit(); self.engine_alive = false;
        }
        if (self.environment_alive) { self.environment.deinit(); self.environment_alive = false; }
    }
};
fn sourceBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    const factory = try s.own(try fixture.eval(original));
    const map = try s.own(try weak_maps.create(s.engine, .{ .weak_reference = fixture.weak }));
    const safe_map = try s.own(try collections.acquireSafeMap(s.engine));
    const validate = try s.own(try errors.validateFunction(s.engine));
    const apply = try s.own(try errors.reflectApply(s.engine));
    return a.duplicate(s.engine, try s.call(factory, c.pi_js_undefined(), &.{
        fixture.process, fixture.trigger, map, safe_map, fixture.prepared.?.arguments.invalid_arg_type,
        validate, s.engine.intrinsic_clone_operations, apply,
    }));
}
fn current(context: ?*c.JSContext) *Fixture {
    const engine = em.Engine.fromContext(context.?);
    return @ptrCast(@alignCast(engine.host_control_context.?));
}
fn rawCrossAcquire(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const f = current(context);
    const other = f.partner orelse return c.JS_ThrowTypeError(context, "Missing control partner");
    const value = owner.acquire(other.engine, other.inputs()) catch |err| {
        f.cross_error = err;
        return c.pi_js_undefined();
    };
    other.engine.freeValue(value);
    return c.pi_js_undefined();
}
fn rawTrigger(context: ?*c.JSContext, receiver: c.JSValue,
    argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f = current(context);
    if (f.report_count == f.reasons.len) return c.JS_ThrowTypeError(context, "Control report capacity exceeded");
    const i = f.report_count;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    f.reasons[i] = a.duplicate(f.engine, a.arg(args, 0));
    f.origins[i] = a.duplicate(f.engine, a.arg(args, 1));
    f.scopes[i] = async_scope.capture(f.engine);
    f.arities[i] = args.len;
    f.receiver_undefined[i] = c.JS_IsUndefined(receiver);
    f.report_count += 1;
    return c.pi_js_undefined();
}
fn reportsBody(s: *a.Scope, f: *Fixture) !c.JSValue {
    const result = try a.array(s);
    for (0..f.report_count) |i| {
        const entry = try a.array(s);
        try a.index(s, entry, 0, f.reasons[i]);
        try a.index(s, entry, 1, f.origins[i]);
        try a.index(s, entry, 2, c.JS_NewInt64(s.engine.context, @intCast(f.arities[i])));
        try a.index(s, entry, 3, a.boolean(s, f.receiver_undefined[i]));
        try a.index(s, entry, 4, a.boolean(s, !c.JS_IsUndefined(f.scopes[i])));
        try a.index(s, result, @intCast(i), entry);
    }
    return a.duplicate(s.engine, result);
}
fn rawReports(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const f = current(context);
    return a.expression(f.engine, reportsBody, .{f}) catch |err| functions.failure(f.engine, err, 0);
}
fn rawDropReports(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    current(context).dropReports();
    return c.pi_js_undefined();
}
fn rawPending(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const f = current(context);
    const reason = f.global("dcError") catch |err| return functions.failure(f.engine, err, 0);
    _ = c.JS_Throw(f.engine.context, reason);
    return c.JS_NewInt32(f.engine.context, 17);
}
fn publishFatal(f: *Fixture) void {
    _ = f.engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(f.engine.context)) {
        const reason = c.JS_GetException(f.engine.context);
        if (c.JS_IsUndefined(f.first_fatal)) f.first_fatal = a.duplicate(f.engine, reason);
        f.engine.freeValue(reason);
    }
}
fn rawFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    publishFatal(current(context));
    return c.pi_js_undefined();
}
fn retireProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const f: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    f.retired += 1;
    if (f.emit_fatal) publishFatal(f);
}
fn probeBody(s: *a.Scope, f: *Fixture, args: []const c.JSValue) !c.JSValue {
    if (f.probe_class == 0) {
        if (c.JS_NewClassID(s.engine.runtime, &f.probe_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual channel lexical retirement probe", .finalizer = retireProbe };
        if (c.JS_NewClass(s.engine.runtime, f.probe_class, &definition) < 0) return error.OutOfMemory;
    }
    const generation = try s.beforeAllocation();
    const value = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, f.probe_class), generation);
    _ = c.JS_SetOpaque(value, f);
    if (args.len != 0) {
        try s.define(value, "0", a.arg(args, 0), c.JS_PROP_C_W_E);
        try s.define(value, "1", a.arg(args, 1), c.JS_PROP_C_W_E);
    }
    return a.duplicate(s.engine, value);
}
fn rawEntryProbe(context: ?*c.JSContext, _: c.JSValue,
    argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f = current(context);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return a.expression(f.engine, probeBody, .{f, args}) catch |err| functions.failure(f.engine, err, 0);
}
fn messageProbeCall(engine: *em.Engine, _: c.JSValue,
    _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    const f: *Fixture = @ptrCast(@alignCast(engine.host_control_context.?));
    f.message_calls += 1;
    return c.pi_js_undefined();
}
fn messageProbeBody(s: *a.Scope, f: *Fixture) !c.JSValue {
    const probe = try s.own(try a.expression(s.engine, probeBody, .{f, @as([]const c.JSValue, &.{})}));
    return functions.create(s.engine, "", 2, false, messageProbeCall, &.{probe});
}
fn rawMessageProbe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const f = current(context);
    return a.expression(f.engine, messageProbeBody, .{f}) catch |err| functions.failure(f.engine, err, 0);
}
fn rawRetired(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const f = current(context);
    return c.JS_NewInt64(f.engine.context, @intCast(f.retired));
}
fn capture(comptime name: []const u8, source: bool) ![]u8 {
    var f: Fixture = undefined; try f.init(source, true); defer f.deinit();
    try f.run("dcObserve('" ++ name ++ "');");
    try f.drain();
    const result = try f.eval("JSON.stringify(dcFinish())");
    defer f.engine.freeValue(result);
    try f.balanced();
    return f.engine.toString(result);
}
fn both(comptime name: []const u8) !void {
    const expected = try capture(name, true); defer std.testing.allocator.free(expected);
    const actual = try capture(name, false); defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "native diagnostics core original inactive shape and callable descriptors" { try both("shape"); }
test "native diagnostics core inactive methods and actual rest application" { try both("inactive"); }
test "native diagnostics core canonical string symbol and raw constructor registry identity" { try both("registry"); }
test "native diagnostics core actual typed invalid channel name errors" { try both("name-errors"); }
test "native diagnostics core original shallow hasInstance and subclass semantics" { try both("instanceof"); }
test "native diagnostics core prototype transitions retain shared classes" { try both("transitions"); }
test "native diagnostics core duplicate subscribers balance actual weak reference counts" { try both("duplicates"); }
test "native diagnostics core failed subscription retains source active transition and typed errors" { try both("invalid-subscription"); }
test "native diagnostics core public functions resolve live channel methods and getters" { try both("public-forward"); }
test "native diagnostics core subscriber receiver argument identity and ignored results" { try both("subscriber-call"); }
test "native diagnostics core publish snapshot survives unsubscribe mutation" { try both("snapshot-remove"); }
test "native diagnostics core publish snapshot excludes newly subscribed callback" { try both("snapshot-add"); }
test "native diagnostics core publish uses live optional length and Number coercion" { try both("live-length"); }
test "native diagnostics core active borrowed publish accepts nullish subscriber snapshot" { try both("null-snapshot"); }
test "native diagnostics core subscriber errors defer exact reason and continue" { try both("subscriber-error"); }
test "native diagnostics core name getter errors follow original deferred catch" { try both("name-getter-error"); }
test "native diagnostics core nextTick getter failure escapes the source catch" { try both("next-tick-callee"); }
test "native diagnostics core nextTick live callee preserves receiver callback and reentry" { try both("next-tick-reentry"); }
test "native diagnostics core store-only activation default transform and inactive transition" { try both("stores-only"); }
test "native diagnostics core replacing a store transform does not increment its strong count" { try both("store-replacement"); }
test "native diagnostics core store nesting reverses insertion order and publishes inside context" { try both("store-order"); }
test "native diagnostics core runStores rest array does not consult public iterator" { try both("rest-call"); }
test "native diagnostics core transform errors skip that store and continue through deferred binding" { try both("transform-error"); }
test "native diagnostics core noncallable transform produces actual VM TypeError and continuation" { try both("noncallable-transform"); }
test "native diagnostics core store run errors escape without entering transform catch" { try both("store-error"); }
test "native diagnostics core store run getter resolves after completed transform" { try both("store-method-live"); }
test "native diagnostics core store entries for-of caches actual next" { try both("entries-next-cache"); }
test "native diagnostics core store entries use indexed values without destructuring iterator" { try both("entries-indexed"); }
test "native diagnostics core store iterator next failure does not close" { try both("iterator-next-error"); }
test "native diagnostics core store entry failure closes once and preserves original throw" { try both("iterator-body-error"); }
test "native diagnostics core iterator close error cannot replace original entry failure" { try both("iterator-close-error"); }
test "native diagnostics core borrowed store methods preserve live operations and reference order" { try both("generic-store-ops"); }
test "native diagnostics core captured primordials survive public prototype poisoning" { try both("primordial-poison"); }
test "native diagnostics core activation prototype and assignment traps retain source order" { try both("prototype-set-order"); }
test "native diagnostics core publish local retirement matches original try-block scopes" { try both("message-lifetime"); }
test "native diagnostics core final entry stays alive through transforms publish and target call" { try both("entry-lifetime"); }
test "native diagnostics core catch reason outlives immediate nextTick callback disposal" { try both("catch-lifetime"); }
test "native diagnostics core actual pending reason outranks native successful return" { try both("pending-reason"); }
test "native diagnostics core successful store Get survives a later transform getter and IteratorClose" { try both("store-get-lifetime"); }
test "native diagnostics core nested subscriber slice arguments retire before assignment setter" { try both("slice-argument-lifetime"); }

test "native diagnostics core cached acquisition preserves identity and rejects changed actual inputs" {
    var f: Fixture = undefined; try f.init(false, true); defer f.deinit();
    const again = try owner.acquire(f.engine, f.inputs()); defer f.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, again, f.subject));
    var changed = f.inputs(); changed.weak_reference = f.trigger;
    try std.testing.expectError(error.DiagnosticsChannelCoreInputConflict, owner.acquire(f.engine, changed));
    try std.testing.expect(!f.engine.native_module_values.contains("node:diagnostics_channel"));
    try std.testing.expect(!f.engine.native_module_values.contains("diagnostics_channel"));
    try f.balanced();
}
test "native diagnostics core missing real inputs and collection bootstrap publish no registry" {
    var f: Fixture = undefined; try f.init(false, false); defer f.deinit();
    var missing = f.inputs(); missing.trigger_uncaught_exception = c.pi_js_undefined();
    try std.testing.expectError(error.ActualDiagnosticsChannelInputsRequired, owner.acquire(f.engine, missing));
    try std.testing.expect(!f.engine.native_module_values.contains(cache_key));
    const removed = f.engine.native_module_values.fetchRemove("\x00native.internal.SafeFinalizationRegistry").?;
    defer f.engine.native_module_values.putAssumeCapacity("\x00native.internal.SafeFinalizationRegistry", removed.value);
    try std.testing.expectError(error.BootstrappedDiagnosticsChannelSafeCollectionsRequired, owner.acquire(f.engine, f.inputs()));
    try std.testing.expect(!f.engine.native_module_values.contains(cache_key));
    try f.balanced();
}
test "native diagnostics core channel retention follows actual weak registry subscription counts" {
    var f: Fixture = undefined; try f.init(false, true); defer f.deinit();
    try f.run(
        \\globalThis.keep=()=>{};{const channel=D.channel("retained");channel.marker=53;
        \\channel.subscribe(keep);globalThis.weakChannel=new WeakRef(channel);}
    );
    f.engine.finishJob(); c.JS_RunGC(f.engine.runtime); try f.drain();
    try f.check("weakChannel.deref().marker===53&&D.channel('retained')===weakChannel.deref()");
    try f.run("D.channel('retained').unsubscribe(keep)");
    f.engine.finishJob(); c.JS_RunGC(f.engine.runtime); try f.drain();
    try f.check("weakChannel.deref()===undefined&&D.hasSubscribers('retained')===false");
    try f.balanced();
}
fn scopeOn(raw: ?*anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?)); f.scope_active = true;
}
fn scopeOff(raw: ?*anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?)); f.scope_active = false;
}
test "native diagnostics core real nextTick preserves the actual captured native async scope" {
    var f: Fixture = undefined; try f.init(false, true); defer f.deinit();
    const token = try async_scope.create(f.engine, &f, scopeOn, scopeOff);
    defer f.engine.freeValue(token);
    {
        const guard = async_scope.enter(f.engine, token); defer guard.restore();
        try f.run("globalThis.dcError={tag:'scope'};D.channel('scope').subscribe(()=>{throw dcError});D.channel('scope').publish(1)");
    }
    try std.testing.expect(!f.scope_active);
    try f.drain();
    try std.testing.expectEqual(@as(usize, 1), f.report_count);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, f.scopes[0], token));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, f.origins[0], c.JS_NewBool(f.engine.context, false)));
    try std.testing.expect(!f.scope_active);
    try f.balanced();
}
fn expectFatal(f: *Fixture, source: []const u8) !void {
    try std.testing.expectError(error.JavaScriptException, f.eval(source));
    f.emit_fatal = false;
    const reason = try f.takeReason(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, f.first_fatal));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 0), f.report_count);
    try std.testing.expect(f.engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), f.engine.native_exception_diagnostics_suppressed);
}
test "native diagnostics core current native fatal cannot become a deferred subscriber error" {
    var f: Fixture = undefined; try f.init(false, true); defer f.deinit();
    try f.run("globalThis.after=0;const fatalChannel=D.channel('fatal');fatalChannel.subscribe(()=>dcFatal());fatalChannel.subscribe(()=>after++);");
    try expectFatal(&f, "try{fatalChannel.publish(1)}catch(e){after=99}");
    try f.check("after===0");
}
test "native diagnostics core subscriber retirement fatal stops before the next indexed Get" {
    var f: Fixture = undefined; try f.init(false, true); defer f.deinit();
    try f.run(
        \\globalThis.after=0;const retirementChannel=D.channel('retire');retirementChannel.subscribe(()=>{});
        \\retirementChannel._subscribers={length:2,get 0(){return dcMessageProbe()},get 1(){after++;return ()=>{}}};
    );
    f.emit_fatal = true;
    try expectFatal(&f, "try{retirementChannel.publish(1)}catch(e){after=99}");
    try std.testing.expectEqual(@as(usize, 1), f.message_calls);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try f.check("after===0");
}

test "native diagnostics core cross-engine nested acquisition cannot publish two same-engine registries" {
    var first: Fixture = undefined; try first.init(false, false); defer first.deinit();
    var second: Fixture = undefined; try second.init(false, false); defer second.deinit();
    first.partner = &second; second.partner = &first;
    try first.publish("ProcessRecord", first.engine.native_module_values.get("node:process").?);
    try second.publish("ProcessRecord", second.engine.native_module_values.get("node:process").?);
    try first.run("Object.defineProperty(ProcessRecord,'default',{configurable:true,get(){dcCrossAcquire();return P}})");
    try second.run("Object.defineProperty(ProcessRecord,'default',{configurable:true,get(){dcCrossAcquire();return P}})");
    try first.createSubject(false);
    try std.testing.expect(first.cross_error == null);
    try std.testing.expect(second.cross_error.? == error.DiagnosticsChannelCoreReentry);
    const again = try owner.acquire(first.engine, first.inputs()); defer first.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(first.engine.context, first.subject, again));
    try first.balanced(); try second.balanced();
}
