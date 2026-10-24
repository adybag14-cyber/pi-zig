//! Original resolver and actual authenticated native producer controls.
//! Auth/frontend/physical fixture is copied byte-for-byte from accepted Manager.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const gpa = std.testing.allocator;
const defaults_owner = @import("extensions/native_sdk_settings_defaults.zig");
const event_owner = @import("extensions/native_sdk_project_trust_event.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-project-trust-resolution-observer.mjs");
const resolution_key = "pi-private:actual-sdk-project-trust-resolution";
const defaults_key = "pi-private:actual-sdk-settings-defaults";
const event_key = "pi-private:actual-sdk-project-trust-event";

fn expose(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn run(s: *v.Scope, source: []const u8) !void {
    _ = try v.own(s, try s.engine.eval(source, "actual-trust-resolution-control.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn runModule(engine: *em.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-trust-resolution-observer.mjs"));
}
fn expect(s: *v.Scope, source: []const u8) !void {
    const value = try v.own(s, try s.engine.eval(source, "actual-trust-resolution-oracle.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, value, c.JS_NewBool(s.engine.context, true)));
}
fn brand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context)); return c.pi_js_undefined();
}
fn promisePending(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_PromiseState(context, argv[0]) == c.JS_PROMISE_PENDING));
}
fn pendingNormal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    const reason = c.JS_GetPropertyStr(context, global, "__trPendingReason");
    c.JS_FreeValue(context, global); _ = c.JS_Throw(context, reason);
    return c.JS_NewInt32(context, 17);
}
fn providers(s: *v.Scope, f: *ActualTrustApplication.Fixture, disk: *Disk) !void {
    const manager = try v.own(s, try f.owner().createProjectTrustManager());
    try expose(s, "__trManager", manager);
    try expose(s, "__trDefaults", try v.own(s, try defaults_owner.create(s.engine)));
    try expose(s, "__trEvent", try v.own(s, try event_owner.create(s.engine)));
    inline for (.{
        .{ "__trFS", "node:fs" }, .{ "__trPath", "node:path" },
        .{ "__trConfig", "pi-native:sdk-configuration-native-zig" },
    }) |row| try expose(s, row[0], s.engine.native_module_values.get(row[1]) orelse return error.ActualTrustResolverProviderRequired);
    try expose(s, "__trRoot", try v.text(s, disk.root));
    try expose(s, "__trRuntime", f.owner().runtime_imports);
    try expose(s, "__trHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
    try expose(s, "__trIsAsync", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, brand, "__trIsAsync", 1))));
    try expose(s, "__trGC", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, collect, "__trGC", 0))));
    try expose(s, "__trPromisePending", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, promisePending, "__trPromisePending", 1))));
    try expose(s, "__trPendingNative", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, pendingNormal, "__trPendingNative", 0))));
    try expose(s, "__trSourceFactory", try v.own(s, try s.engine.eval(
        @embedFile("extensions/fixtures/sdk-project-trust-resolution-original.mjs"),
        "original-project-trust-factory.js", c.JS_EVAL_TYPE_GLOBAL)));
    try run(s,
        \\globalThis.__trCwd=__trPath.join(__trRoot,'project','child');
        \\globalThis.__trAgent=__trPath.join(__trRoot,'agent');
        \\globalThis.__trFile=__trPath.join(__trAgent,'trust.json');
        \\__trFS.mkdirSync(__trPath.join(__trCwd,__trConfig.CONFIG_DIR_NAME),{recursive:true});
        \\__trFS.writeFileSync(__trPath.join(__trCwd,__trConfig.CONFIG_DIR_NAME,'settings.json'),'actual trust resource\n','utf-8');
        \\globalThis.__trStore=new __trManager.ProjectTrustStore(__trAgent);
    );
    try run(s, observer);
}
fn sourceModuleBody(s: *v.Scope) !c.JSValue {
    const config = try v.global(s, "__trConfig");
    const app_name = try v.get(s, config, "APP_NAME");
    const config_dir = try v.get(s, config, "CONFIG_DIR_NAME");
    const manager = try v.global(s, "__trManager");
    const get_options = try v.get(s, manager, "getProjectTrustOptions");
    const resources = try v.get(s, manager, "hasTrustRequiringProjectResources");
    return v.duplicate(s, try v.call(s, try v.global(s, "__trSourceFactory"), c.pi_js_undefined(),
        &.{ app_name, config_dir, try v.global(s, "__trEvent"), try v.global(s, "__trDefaults"), get_options, resources }));
}
fn start(s: *v.Scope, f: *ActualTrustApplication.Fixture, native: bool) !c.JSValue {
    const module = try v.own(s, if (native) try f.owner().createProjectTrustResolver() else
        try h.expression(s.engine, sourceModuleBody, .{}));
    try expose(s, "__trModule", module);
    try expose(s, "__trSubject", try v.get(s, module, "resolveProjectTrusted"));
    return module;
}
fn clean(engine: *em.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime before: []const u8, comptime arguments: []const u8) !void {
    inline for (.{ false, true }) |native| {
        var disk = try Disk.init(); defer disk.deinit();
        var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
        var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
        try providers(&s, &f, &disk);
        if (before.len != 0) try run(&s, before);
        _ = try start(&s, &f, native);
        try runModule(f.engine, "await " ++ name ++ "(__trSubject" ++ arguments ++ ");");
        try clean(f.engine);
    }
}
fn noPartial(engine: *em.Engine) !void {
    try std.testing.expect(!engine.native_module_values.contains(resolution_key));
    try std.testing.expect(!engine.native_module_values.contains(defaults_key));
    try std.testing.expect(!engine.native_module_values.contains(event_key));
}

const Disk = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    fn init() !Disk {
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try temporary.dir.realPath(std.testing.io, &buffer);
        return .{ .temporary = temporary, .root = try gpa.dupe(u8, buffer[0..count]) };
    }
    fn path(self: *Disk, relative: []const u8) ![]u8 {
        return std.fs.path.join(gpa, &.{ self.root, relative });
    }
    fn directory(self: *Disk, relative: []const u8) !void {
        try self.temporary.dir.createDirPath(std.testing.io, relative);
    }
    fn write(self: *Disk, relative: []const u8) !void {
        if (std.fs.path.dirname(relative)) |directory_name| try self.directory(directory_name);
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = relative, .data = "actual trust resource\n" });
    }
    fn deinit(self: *Disk) void {
        gpa.free(self.root);
        self.temporary.cleanup();
    }
};
const ActualTrustApplication = struct {
    const auth = @import("extensions/native_sdk_auth_runtime_owner.zig");
    const capture = @import("extensions/native_child_process_frontend_inputs.zig");
    const internal = @import("extensions/native_node_internal_builtin_require.zig");
    const Frontend = @import("extensions/native_stdio_frontend.zig").Frontend;
    const Fixture = struct {
        environment: std.process.Environ.Map,
        engine: *v.em.Engine,
        frontend: Frontend,
        require: c.JSValue,
        actual: ?auth.Owner = null,

        fn init(self: *Fixture) !void {
            self.actual = null;
            self.environment = .init(std.testing.allocator);
            errdefer self.environment.deinit();
            self.engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 1_000_000 });
            errdefer self.engine.deinit();
            try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(self.engine, std.testing.io, &self.environment, &.{"actual-application-print-owner"});
            self.require = try internal.acquire(self.engine, .{ .bindings = &.{
                .{ .id = "util", .module_name = "node:util" }, .{ .id = "stream", .module_name = "node:stream" },
                .{ .id = "process", .module_name = "node:process" }, .{ .id = "timers", .module_name = "node:timers" },
            } });
            errdefer self.engine.freeValue(self.require);
            try self.frontend.init(self.engine, std.testing.io);
            errdefer {
                if (self.engine.native_env_deinit) |close| close(self.engine);
                self.frontend.deinit();
            }
            // This control's actual bootstrap explicitly has permission disabled.
            // The production method receives no policy and cannot infer a default.
            var inputs = try capture.capture(self.engine, &self.frontend, .{ .internal_require = self.require, .permission = .disabled });
            var actual = createAuth(self.engine, &inputs) catch |err| {
                var failed = v.owned.Completion.initVoid(self.engine, err);
                inputs.retireInto(&failed);
                try failed.finishVoid();
                unreachable;
            };
            var selected = v.owned.Completion.initVoid(self.engine, {});
            inputs.retireInto(&selected);
            selected.finishVoid() catch |err| {
                var failed = v.owned.Completion.initVoid(self.engine, err);
                actual.retireInto(&failed);
                try failed.finishVoid();
                unreachable;
            };
            self.actual = actual;
        }
        fn owner(self: *Fixture) *auth.Owner {
            return if (self.actual) |*actual| actual else unreachable;
        }
        fn deinit(self: *Fixture) void {
            if (self.actual) |*actual| {
                if (actual.live) actual.deinit() catch {};
            }
            self.actual = null;
            // The physical frontend and its descriptor owners remain alive through
            // every owner operation. Cached JS roots do not own this native pointer.
            if (self.engine.native_env_deinit) |close| close(self.engine);
            self.frontend.deinit();
            self.engine.freeValue(self.require);
            self.engine.deinit();
            self.environment.deinit();
        }
    };
    fn createAuth(engine: *v.em.Engine, inputs: *capture.Owned) !auth.Owner {
        const url = try engine.checked(c.JS_NewString(engine.context, "file:///C:/Users/adyba/pi-zig/upstream/pi/packages/coding-agent/src/config.ts"));
        defer engine.freeValue(url); // Primitive, so retirement cannot run guest code.
        return auth.create(engine, .{ .frontend = try inputs.view(engine), .config_module_url = url });
    }

    const Behavior = enum { retire_owner, pending_ordinary, pending_fatal };
    const Probe = struct {
        engine: *em.Engine,
        owner: *auth.Owner,
        platform: c.JSValue,
        filesystem: c.JSValue,
        reason: c.JSValue,
        behavior: Behavior,
        platform_reads: usize = 0,
        filesystem_reads: usize = 0,
    };
    fn finalizeProbe(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
        c.JS_FreeValueRT(runtime, probe.platform);
        c.JS_FreeValueRT(runtime, probe.filesystem);
        c.JS_FreeValueRT(runtime, probe.reason);
        probe.engine.gpa.destroy(probe);
    }
    fn markProbe(runtime: ?*c.JSRuntime, holder: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
        c.JS_MarkValue(runtime, probe.platform, marker);
        c.JS_MarkValue(runtime, probe.filesystem, marker);
        c.JS_MarkValue(runtime, probe.reason, marker);
    }
    fn readPlatform(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
        probe.platform_reads += 1;
        switch (probe.behavior) {
            .retire_owner => probe.owner.deinit() catch |err| return @import("extensions/native_sdk.zig").fail(probe.engine, err),
            .pending_ordinary => { _ = c.JS_Throw(context, c.JS_DupValue(context, probe.reason)); },
            .pending_fatal => {
                _ = probe.engine.throwNativeOutOfMemoryFatal();
                const reason = c.JS_GetException(context);
                if (c.JS_IsUndefined(probe.reason)) probe.reason = c.JS_DupValue(context, reason);
                _ = c.JS_Throw(context, reason);
            },
        }
        return c.JS_DupValue(context, probe.platform);
    }
    fn readFilesystem(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
        const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
        probe.filesystem_reads += 1;
        return c.JS_DupValue(context, probe.filesystem);
    }
    fn getter(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, function: c.JSValue) !void {
        const atom = c.JS_NewAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, object, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0)
            return @import("extensions/native_js_values.zig").capture(engine);
        _ = try engine.checked(c.pi_js_undefined());
    }
    fn installProbe(s: *v.Scope, actual: *auth.Owner, behavior: Behavior) !*Probe {
        const engine = s.engine;
        const platform = try v.get(s, actual.runtime_imports, "platform");
        const filesystem = try v.get(s, platform, "filesystem");
        const reason = if (behavior == .pending_fatal) c.pi_js_undefined() else try v.own(s, try engine.checked(c.JS_NewError(engine.context)));
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Actual trust provider input probe", .finalizer = finalizeProbe, .gc_mark = markProbe };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const holder = try v.own(s, try engine.checked(c.JS_NewObjectClass(engine.context, class)));
        const probe = try engine.gpa.create(Probe);
        probe.* = .{ .engine = engine, .owner = actual, .platform = c.JS_DupValue(engine.context, platform),
            .filesystem = c.JS_DupValue(engine.context, filesystem), .reason = c.JS_DupValue(engine.context, reason), .behavior = behavior };
        _ = c.JS_SetOpaque(holder, probe);
        var roots = [_]c.JSValue{holder};
        const platform_get = try v.own(s, try engine.checked(c.JS_NewCFunctionData2(engine.context, readPlatform, "get actual platform", 0, 0, roots.len, &roots)));
        const filesystem_get = try v.own(s, try engine.checked(c.JS_NewCFunctionData2(engine.context, readFilesystem, "get actual filesystem", 0, 0, roots.len, &roots)));
        try getter(engine, actual.runtime_imports, "platform", platform_get);
        try getter(engine, platform, "filesystem", filesystem_get);
        return probe;
    }
    fn expectForeign(s: *v.Scope, actual: *auth.Owner, name: []const u8) !void {
        const count = s.engine.native_module_values.count();
        try std.testing.expectError(error.JavaScriptException, actual.createProjectTrustPaths());
        const reason = s.engine.captured_exception orelse return error.RequiredForeignTrustOwnerRejection;
        const message = try v.get(s, reason, "message");
        const included = try v.call(s, try v.get(s, message, "includes"), message, &.{try v.text(s, name)});
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, included, c.JS_NewBool(s.engine.context, true)));
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, try v.global(s, "__trustForeignReads"), c.JS_NewInt32(s.engine.context, 0)));
        try std.testing.expectEqual(count, s.engine.native_module_values.count());
        try std.testing.expect(!s.engine.native_module_values.contains("pi-private:actual-sdk-project-trust-paths"));
    }
    fn foreign(s: *v.Scope) !c.JSValue {
        return v.own(s, try s.engine.eval(
            \\globalThis.__trustForeignReads=0;
            \\new Proxy({}, {get(){__trustForeignReads++;throw Error("foreign trust carrier must not be read")}})
        , "actual-trust-foreign-carrier.js", c.JS_EVAL_TYPE_GLOBAL));
    }
    fn verifyPending(comptime fatal: bool) !void {
        var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
        var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
        const probe = try installProbe(&s, fixture.owner(), if (fatal) .pending_fatal else .pending_ordinary);
        const count = s.engine.native_module_values.count();
        const generation = s.engine.native_allocation_generation;
        const suppression = s.engine.native_exception_diagnostics_suppressed;
        const invocation = s.engine.native_fatal_invocation;
        try std.testing.expectError(error.JavaScriptException, fixture.owner().createProjectTrustPaths());
        const caught = s.engine.captured_exception orelse return error.RequiredActualTrustOwnerFailure;
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, caught, probe.reason));
        try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
        try std.testing.expectEqual(@as(usize, 0), probe.filesystem_reads);
        try std.testing.expectEqual(count, s.engine.native_module_values.count());
        try std.testing.expectEqual(suppression, s.engine.native_exception_diagnostics_suppressed);
        try std.testing.expectEqual(invocation, s.engine.native_fatal_invocation);
        try std.testing.expect(c.JS_IsUncatchableError(caught) == fatal);
        if (fatal) try std.testing.expect(s.engine.native_allocation_generation -% generation != 0);
    }
};


test "native project trust resolution actual AsyncFunction shape and physical ask policy" {
    try both("observeResolutionShape", "", "");
}
test "native project trust resolution defined override is reread before every other input" {
    try both("observeResolutionOverride", "", "");
}
test "native project trust resolution absent override is read once then reaches actual policy" {
    try both("observeResolutionMissingOverride", "", "");
}
test "native project trust resolution no-resource branch precedes extension Store and UI inputs" {
    try both("observeResolutionNoResources",
        "globalThis.__trNoResourceCalls=0;__trManager.hasTrustRequiringProjectResources=function(){__trNoResourceCalls++;return false;};", "");
}
test "native project trust resolution original extension event input Get order and handler receiver" {
    try both("observeResolutionExtensionOrder", "", "");
}
test "native project trust resolution all extension errors are reported before the decision is read" {
    try both("observeResolutionReportsBeforeDecision", "", "");
}
test "native project trust resolution strict yes and strict remember persist actual positive trust" {
    try both("observeResolutionRemember", "", ",true");
}
test "native project trust resolution any decided non-yes extension value persists false" {
    try both("observeResolutionRemember", "", ",false");
}
test "native project trust resolution truthy remember does not create a trust record" {
    try both("observeResolutionRememberStrict", "", "");
}
test "native project trust resolution empty truthy extension result still introduces original Await" {
    try both("observeResolutionEmptyExtensionAwait", "", ",true");
}
test "native project trust resolution absent extension input reaches Store before caller continuation" {
    try both("observeResolutionEmptyExtensionAwait", "", ",false");
}
test "native project trust resolution nullish optional reporter skips template conversion" {
    try both("observeResolutionOptionalReport", "", "");
}
test "native project trust resolution noncallable optional reporter converts arguments before rejection" {
    try both("observeResolutionNoncallableReport", "", "");
}
test "native project trust resolution reporter throw closes its error iterator preserving first reason" {
    try both("observeResolutionReportClose", "", "");
}
test "native project trust resolution failed next does not invoke its own IteratorClose" {
    try both("observeResolutionErrorStep", "", ",false");
}
test "native project trust resolution failed iterator value Get does not invoke its own return" {
    try both("observeResolutionErrorStep", "", ",true");
}
test "native project trust resolution persisted positive trust precedes defaults and UI" {
    try both("observeResolutionStorePriority", "", ",true");
}
test "native project trust resolution persisted denial precedes defaults and UI" {
    try both("observeResolutionStorePriority", "", ",false");
}
test "native project trust resolution only null Store result falls through to policy" {
    try both("observeResolutionStoreUndefined", "", "");
}
test "native project trust resolution Store receiver and method precede repeated cwd Get" {
    try both("observeResolutionStoreGetOrder", "", "");
}
test "native project trust resolution shared default remains live and nullish-only" {
    try both("observeResolutionDefaultLive", "", "");
}
test "native project trust resolution unknown policy is not coerced and falls to live UI availability" {
    try both("observeResolutionUnknownPolicy", "", "");
}
test "native project trust resolution actual session-only choices retain exact prompt and avoid save" {
    try both("observeResolutionSessionChoices", "", "");
}
test "native project trust resolution selected trust writes actual Store and releases lock" {
    try both("observeResolutionPhysicalSave", "", ",false");
}
test "native project trust resolution selected parent trust uses actual parent and child deletion" {
    try both("observeResolutionPhysicalSave", "", ",true");
}
test "native project trust resolution undefined UI selection denies without saving" {
    try both("observeResolutionCancel", "", ",false");
}
test "native project trust resolution unmatched UI label denies without saving" {
    try both("observeResolutionCancel", "", ",true");
}
test "native project trust resolution UI rejection crosses both actual AsyncFunctions unchanged" {
    try both("observeResolutionUiRejection", "", "");
}
test "native project trust resolution select receiver and template conversion precede labels map" {
    try both("observeResolutionPromptOrder", "prepareResolutionPromptOrder();", "");
}
test "native project trust resolution separate selection helper preserves both Await job boundaries" {
    try both("observeResolutionLayers", "prepareResolutionLayers();", "");
}
test "native project trust resolution update length method second updates and trusted Get preserve order" {
    try both("observeResolutionSaveOrder", "prepareResolutionSaveOrder();", "");
}
test "native project trust resolution escaped find arrow retains actual selected lexical binding" {
    try both("observeResolutionEscapedFind", "prepareResolutionEscapedFind();", ",__trHooks");
}
test "native project trust resolution captures genuine named imports once in original order" {
    try both("observeResolutionNamedCaptures", "prepareResolutionNamedCaptures();", "");
}
test "native project trust resolution ordinary private DATA stays ordinary across both Await layers" {
    try both("observeResolutionPrivateRejection", "", ",__trHooks");
}
test "native project trust resolution nested live UI invocation keeps independent original state" {
    try both("observeResolutionReentry", "", "");
}
test "native project trust resolution abandoned nested suspension releases actual receiver and arguments once" {
    try both("observeResolutionAbandonedControl", "", ",__trHooks");
}
test "native project trust resolution actual pending exception beats successful native selection return" {
    var disk = try Disk.init(); defer disk.deinit();
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try providers(&s, &f, &disk); _ = try start(&s, &f, true);
    try runModule(f.engine, "await observeResolutionPendingNormal(__trSubject);");
    try clean(f.engine);
}
fn nativeFatal(comptime reporter: bool) !void {
    var disk = try Disk.init(); defer disk.deinit();
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try providers(&s, &f, &disk); _ = try start(&s, &f, true);
    const hooks = try v.global(&s, "__trHooks");
    const original = try v.get(&s, hooks, "record");
    try std.testing.expectError(error.JavaScriptException, runModule(f.engine,
        if (reporter) "await observeResolutionFatal(__trSubject,__trHooks,true);" else
            "await observeResolutionFatal(__trSubject,__trHooks,false);"));
    try retirement.verifyRecordedActualNativeFatal(f.engine, original);
    try retirement.verifyNoVisits(original, .{ 2, 3 });
    try std.testing.expect(f.engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), f.engine.native_exception_diagnostics_suppressed);
}
test "native project trust resolution genuine selection fatal bypasses both async catch paths" {
    try nativeFatal(false);
}
test "native project trust resolution actual reporter fatal skips guest error IteratorClose" {
    try nativeFatal(true);
}

test "native project trust resolution complete shared settings value matches original literal and stays mutable" {
    const engine = try em.Engine.init(gpa, .{}); defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const value = try v.own(&s, try defaults_owner.create(engine));
    try expose(&s, "__sdActual", value);
    try expose(&s, "__sdOriginal", try v.own(&s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-settings-defaults-original.mjs"),
        "original-settings-defaults.js", c.JS_EVAL_TYPE_GLOBAL)));
    try expect(&s,
        \\(()=>{const visit=(a,b)=>{const ak=Reflect.ownKeys(a),bk=Reflect.ownKeys(b);
        \\if(JSON.stringify(ak)!==JSON.stringify(bk)||Object.getPrototypeOf(a)!==Object.prototype)return false;
        \\for(const k of ak){const x=Object.getOwnPropertyDescriptor(a,k),y=Object.getOwnPropertyDescriptor(b,k);
        \\if(x.writable!==y.writable||x.enumerable!==y.enumerable||x.configurable!==y.configurable)return false;
        \\if(x.value&&typeof x.value==='object'){if(!visit(x.value,y.value))return false;}
        \\else if(!Object.is(x.value,y.value))return false;}return true;};
        \\return visit(__sdActual,__sdOriginal)&&__sdActual.sessionShareDestination==='auto'&&
        \\__sdActual.retry.maxAgentDelayMs===60000&&__sdActual.retry.provider.maxRetryDelayMs===60000;})()
    );
    try run(&s, "__sdActual.defaultProjectTrust='never';__sdActual.retry.provider.maxRetryDelayMs=1234;");
    const again = try v.own(&s, try defaults_owner.create(engine));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, again));
    try expect(&s, "__sdActual.defaultProjectTrust==='never'&&__sdActual.retry.provider.maxRetryDelayMs===1234");
    try clean(engine);
}
test "native project trust resolution settings literal ignores global constructors and inherited setters" {
    const engine = try em.Engine.init(gpa, .{}); defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    try run(&s,
        \\globalThis.__sdObject=Object;globalThis.__sdJSON=JSON;globalThis.__sdSetterCalls=0;
        \\Object.defineProperty(Object.prototype,'transport',{configurable:true,set(){__sdSetterCalls++;throw Error('inherited setter');}});
        \\globalThis.Object=function(){throw Error('foreign Object constructor')};
        \\globalThis.JSON={parse(){throw Error('foreign JSON parser')}};
    );
    try expose(&s, "__sdActual", try v.own(&s, try defaults_owner.create(engine)));
    try run(&s, "globalThis.Object=__sdObject;globalThis.JSON=__sdJSON;delete Object.prototype.transport;");
    try expect(&s, "__sdSetterCalls===0&&Object.hasOwn(__sdActual,'transport')&&__sdActual.transport==='auto'");
    try clean(engine);
}
test "native project trust resolution settings owners are independent between actual Engines" {
    const first_engine = try em.Engine.init(gpa, .{}); defer first_engine.deinit();
    const second_engine = try em.Engine.init(gpa, .{}); defer second_engine.deinit();
    var first: v.Scope = .{ .engine = first_engine }; defer first.deinit();
    var second: v.Scope = .{ .engine = second_engine }; defer second.deinit();
    try expose(&first, "__sd", try v.own(&first, try defaults_owner.create(first_engine)));
    try expose(&second, "__sd", try v.own(&second, try defaults_owner.create(second_engine)));
    try run(&first, "__sd.defaultProjectTrust='never';__sd.retry.maxAgentDelayMs=1;");
    try expect(&second, "__sd.defaultProjectTrust==='ask'&&__sd.retry.maxAgentDelayMs===60000");
    try clean(first_engine); try clean(second_engine);
}
test "native project trust resolution authenticated module is shared and its captured exports outlive host handle" {
    var disk = try Disk.init(); defer disk.deinit();
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try providers(&s, &f, &disk); const module = try start(&s, &f, true);
    try run(&s,
        \\for(const key of ['APP_NAME','CONFIG_DIR_NAME'])Object.defineProperty(__trConfig,key,
        \\{configurable:true,get(){throw Error('warm module must not recapture named imports')}});
    );
    const again = try v.own(&s, try f.owner().createProjectTrustResolver());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, module, again));
    try expect(&s, "Object.keys(__trModule).join()==='resolveProjectTrusted'");
    try f.owner().deinit();
    try std.testing.expectError(error.ActualSdkAuthOwnerRetired, f.owner().createProjectTrustResolver());
    try runModule(f.engine, "trAssert(await __trSubject(trOptions({defaultProjectTrust:'always'}))===true,'retained actual providers');");
    try clean(f.engine);
}
test "native project trust resolution all inputs remain rooted when actual carrier getter retires owner" {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const probe = try ActualTrustApplication.installProbe(&s, f.owner(), .retire_owner);
    const module = try v.own(&s, try f.owner().createProjectTrustResolver());
    try expose(&s, "__resolver", try v.get(&s, module, "resolveProjectTrusted"));
    try std.testing.expect(!f.owner().live);
    try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
    try std.testing.expectEqual(@as(usize, 1), probe.filesystem_reads);
    try std.testing.expect(f.engine.native_module_values.contains(resolution_key));
    try std.testing.expect(f.engine.native_module_values.contains(defaults_key));
    try std.testing.expect(f.engine.native_module_values.contains(event_key));
    try runModule(f.engine, "if(await __resolver({trustOverride:true})!==true)throw Error('retained resolver');");
    try clean(f.engine);
}
test "native project trust resolution rejects foreign runtime platform and configuration before publication" {
    inline for (.{
        .{ "runtime", "ActualSdkTrustRuntimeNamespaceChanged" },
        .{ "platform", "ActualSdkTrustPlatformNamespaceChanged" },
        .{ "configuration", "ActualSdkTrustConfigurationNamespaceChanged" },
    }) |row| {
        var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
        var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
        const foreign = try ActualTrustApplication.foreign(&s);
        if (comptime std.mem.eql(u8, row[0], "runtime")) {
            const previous = f.owner().runtime_imports;
            f.owner().runtime_imports = c.JS_DupValue(s.engine.context, foreign);
            s.engine.freeValue(previous);
        } else try v.put(&s, f.owner().runtime_imports, row[0], foreign);
        const count = f.engine.native_module_values.count();
        try std.testing.expectError(error.JavaScriptException, f.owner().createProjectTrustResolver());
        const reason = f.engine.captured_exception orelse return error.ActualResolverForeignReasonRequired;
        const message = try v.get(&s, reason, "message");
        const included = try v.call(&s, try v.get(&s, message, "includes"), message, &.{try v.text(&s, row[1])});
        try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, included, c.JS_NewBool(s.engine.context, true)));
        try std.testing.expectEqual(count, f.engine.native_module_values.count());
        try expect(&s, "__trustForeignReads===0");
        try noPartial(f.engine);
    }
}
fn pendingResolver(comptime fatal: bool) !void {
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const probe = try ActualTrustApplication.installProbe(&s, f.owner(), if (fatal) .pending_fatal else .pending_ordinary);
    const count = f.engine.native_module_values.count();
    const generation = f.engine.native_allocation_generation;
    const suppression = f.engine.native_exception_diagnostics_suppressed;
    const invocation = f.engine.native_fatal_invocation;
    try std.testing.expectError(error.JavaScriptException, f.owner().createProjectTrustResolver());
    const reason = f.engine.captured_exception orelse return error.ActualResolverCarrierReasonRequired;
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason, probe.reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason) == fatal);
    if (fatal) try std.testing.expect(f.engine.native_allocation_generation -% generation != 0);
    try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
    try std.testing.expectEqual(@as(usize, 0), probe.filesystem_reads);
    try std.testing.expectEqual(count, f.engine.native_module_values.count());
    try std.testing.expectEqual(suppression, f.engine.native_exception_diagnostics_suppressed);
    try std.testing.expectEqual(invocation, f.engine.native_fatal_invocation);
    try noPartial(f.engine);
}
test "native project trust resolution actual pending carrier wins normal returned owner" {
    try pendingResolver(false);
}
test "native project trust resolution actual fatal carrier survives all owned root cleanup" {
    try pendingResolver(true);
}
test "native project trust resolution failed named capture preserves exact reason and permits clean retry" {
    var disk = try Disk.init(); defer disk.deinit();
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try providers(&s, &f, &disk);
    try run(&s,
        \\globalThis.__trCaptureReason={};globalThis.__trLaterReads=0;
        \\globalThis.__trNameDescriptor=Object.getOwnPropertyDescriptor(__trConfig,'APP_NAME');
        \\const directory=__trConfig.CONFIG_DIR_NAME;
        \\Object.defineProperty(__trConfig,'APP_NAME',{configurable:true,get(){throw __trCaptureReason}});
        \\Object.defineProperty(__trConfig,'CONFIG_DIR_NAME',{configurable:true,get(){__trLaterReads++;return directory}});
    );
    const reason = try v.global(&s, "__trCaptureReason");
    const count = f.engine.native_module_values.count();
    try std.testing.expectError(error.JavaScriptException, f.owner().createProjectTrustResolver());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason,
        f.engine.captured_exception orelse return error.ActualResolverNamedReasonRequired));
    try std.testing.expectEqual(count, f.engine.native_module_values.count());
    try std.testing.expect(!f.engine.native_module_values.contains(resolution_key));
    try expect(&s, "__trLaterReads===0");
    try run(&s, "Object.defineProperty(__trConfig,'APP_NAME',__trNameDescriptor);");
    _ = try start(&s, &f, true);
    try expect(&s, "__trLaterReads===1&&typeof __trSubject==='function'");
    try clean(f.engine);
}
threadlocal var active_resolution_fixture: ?*ActualTrustApplication.Fixture = null;
threadlocal var resolution_reentry_count: usize = 0;
fn reenterResolver(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const f = active_resolution_fixture orelse return error.ActualResolverReentryFixtureRequired;
    if (engine != f.engine) return error.ActualResolverReentryEngineRequired;
    resolution_reentry_count += 1;
    try std.testing.expect(!engine.native_module_values.contains(resolution_key));
    return f.owner().createProjectTrustResolver();
}
test "native project trust resolution cold named capture reentry cannot publish partial exports" {
    var disk = try Disk.init(); defer disk.deinit();
    var f: ActualTrustApplication.Fixture = undefined; try f.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    try providers(&s, &f, &disk);
    active_resolution_fixture = &f; defer active_resolution_fixture = null; resolution_reentry_count = 0;
    try expose(&s, "__trReenter", try v.own(&s, try v.function.create(f.engine, "reenterResolver", 0, reenterResolver, &.{})));
    try run(&s,
        \\globalThis.__trReentryRejected=false;const appName=__trConfig.APP_NAME;
        \\Object.defineProperty(__trConfig,'APP_NAME',{configurable:true,get(){
        \\try{__trReenter()}catch(error){__trReentryRejected=error instanceof TypeError&&
        \\error.message.includes('ActualProjectTrustResolutionCreationReentry');}return appName;}});
    );
    _ = try start(&s, &f, true);
    try std.testing.expectEqual(@as(usize, 1), resolution_reentry_count);
    try expect(&s, "__trReentryRejected&&Object.keys(__trModule).join()==='resolveProjectTrusted'");
    try clean(f.engine);
}

test "native project trust resolution mutable cwd Store and optional reporter are reread after event Await" {
    try both("observeResolutionLiveExtension", "", "");
}
test "native project trust resolution selected updates retain original cwd but save uses live Store after Await" {
    try both("observeResolutionLiveSelection", "", "");
}
