//! Source-only actual-VM controls for the original Main option/path helpers.
//! Imported namespaces and the SettingsManager are genuine native owners.
//! Pure-function argument records deliberately exercise caller-controlled Gets;
//! no application ModelRuntime or complete production namespace is fabricated.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const gpa = std.testing.allocator;
const helpers = @import("extensions/native_sdk_main_runtime_helpers.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-main-runtime-helpers-observer.mjs");
const original = @embedFile("extensions/fixtures/sdk-main-runtime-helpers-4954-source.mjs");
const cache_key = "pi-private:actual-sdk-main-runtime-helpers";
fn expose(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn run(s: *v.Scope, source: []const u8) !void {
    _ = try v.own(s, try s.engine.eval(source, "actual-main-helper-control.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn expect(s: *v.Scope, source: []const u8) !void {
    const value = try v.own(s, try s.engine.eval(source, "actual-main-helper-oracle.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, value, c.JS_NewBool(s.engine.context, true)));
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context)); return c.pi_js_undefined();
}
fn pendingNormal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    const reason = c.JS_GetPropertyStr(context, global, "__mhPendingReason");
    c.JS_FreeValue(context, global);
    _ = c.JS_Throw(context, reason);
    return c.JS_NewInt32(context, 17);
}
fn providers(s: *v.Scope, fixture: *ActualTrustApplication.Fixture, disk: *Disk) !void {
    const engine = s.engine;
    const models = try v.own(s, try @import("extensions/native_ai_model_values.zig").bindings(engine));
    const cli = try v.own(s, try helpers.cliBindings(engine));
    const resolver = try v.own(s, try @import("extensions/native_sdk_public_model_resolver.zig").create(
        engine, .{ .thinking = try v.get(s, cli, "isValidThinkingLevel") }));
    const managers = try v.own(s, try @import("extensions/native_sdk.zig").managerImports(engine));
    const settings = try v.invoke(s, try v.get(s, managers, "SettingsManager"), "inMemory", &.{});
    try expose(s, "__mhModels", models);
    try expose(s, "__mhCli", cli);
    try expose(s, "__mhResolver", resolver);
    try expose(s, "__mhSettings", settings);
    try expose(s, "__mhPaths", engine.native_module_values.get("pi-private:actual-sdk-path-utilities") orelse return error.ActualMainPathsRequired);
    try expose(s, "__mhNodePath", engine.native_module_values.get("node:path") orelse return error.ActualMainNodePathRequired);
    try expose(s, "__mhRuntimeImports", fixture.owner().runtime_imports);
    try expose(s, "__mhDisk", try v.text(s, disk.root));
    try expose(s, "__mhHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
    try expose(s, "__mhGC", try v.own(s, try engine.checked(c.JS_NewCFunction(engine.context, collect, "__mhGC", 0))));
    try expose(s, "__mhPendingNative", try v.own(s, try engine.checked(c.JS_NewCFunction(engine.context, pendingNormal, "__mhPendingNative", 0))));
    try expose(s, "__mhSourceFactory", try v.own(s, try engine.eval(original, "original-main-helper-factory.js", c.JS_EVAL_TYPE_GLOBAL)));
    try run(s, observer);
}
fn sourceBody(s: *v.Scope) !c.JSValue {
    const equal = try v.get(s, try v.global(s, "__mhModels"), "modelsAreEqual");
    const resolve_model = try v.get(s, try v.global(s, "__mhResolver"), "resolveCliModel");
    const paths = try v.global(s, "__mhPaths");
    const local = try v.get(s, paths, "isLocalPath");
    const resolve_path = try v.get(s, paths, "resolvePath");
    return v.duplicate(s, try v.call(s, try v.global(s, "__mhSourceFactory"), c.pi_js_undefined(),
        &.{equal, resolve_model, local, resolve_path}));
}
fn start(s: *v.Scope, fixture: *ActualTrustApplication.Fixture, source: bool) !c.JSValue {
    const module = try v.own(s, if (source) try h.expression(s.engine, sourceBody, .{}) else
        try fixture.owner().createMainRuntimeHelpers());
    try expose(s, "__mhSubject", module);
    return module;
}
fn clean(engine: *em.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn captureCase(comptime name: []const u8, source: bool) ![]u8 {
    var disk = try Disk.init(); defer disk.deinit();
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    try providers(&s, &fixture, &disk);
    try run(&s, "mhPrepare('" ++ name ++ "');");
    _ = try start(&s, &fixture, source);
    try run(&s, "globalThis.__mhObserved=JSON.stringify(mhObserve('" ++ name ++ "',__mhSubject));");
    const value = try v.global(&s, "__mhObserved");
    try std.testing.expect(c.JS_IsString(value));
    try clean(fixture.engine);
    return fixture.engine.toString(value);
}
fn both(comptime name: []const u8) !void {
    const expected = try captureCase(name, true); defer gpa.free(expected);
    const actual = try captureCase(name, false); defer gpa.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
fn fatal(comptime kind: []const u8) !void {
    var disk = try Disk.init(); defer disk.deinit();
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    try providers(&s, &fixture, &disk);
    _ = try start(&s, &fixture, false);
    const record = try v.get(&s, try v.global(&s, "__mhHooks"), "record");
    try std.testing.expectError(error.JavaScriptException, run(&s, "mhFatal('" ++ kind ++ "',__mhSubject);"));
    if (comptime std.mem.eql(u8, kind, "current")) {
        try retirement.verifyRecordedActualNativeFatal(fixture.engine, record);
    } else if (comptime std.mem.eql(u8, kind, "retirement")) {
        try retirement.verifyActualRetirementFatal(fixture.engine, record, 0);
    } else {
        try retirement.verifyActualCancellationNoGuestClose(fixture.engine, record);
    }
    try retirement.verifyNoVisits(record, .{1,2,3});
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native Main runtime helpers ordinary callable shapes and complete private pair" { try both("shapes"); }
test "native Main runtime helpers empty original options and diagnostics" { try both("empty"); }
test "native Main runtime helpers provider error preserves repeated Gets and exact text" { try both("provider-required"); }
test "native Main runtime helpers actual CLI resolver receives available caller model data" { try both("cli-actual"); }
test "native Main runtime helpers CLI construction preserves property and argument order" { try both("cli-order"); }
test "native Main runtime helpers warning error model and thinking fields are read repeatedly" { try both("cli-repeat"); }
test "native Main runtime helpers explicit CLI thinking keeps original late rereads" { try both("cli-explicit"); }
test "native Main runtime helpers thinking suffix requires actual resolved model" { try both("cli-no-model"); }
test "native Main runtime helpers live global Boolean receives original apiKey and keeps arbitrary result" { try both("boolean-live"); }
test "native Main runtime helpers saved default chooses matching scoped model" { try both("saved-model"); }
test "native Main runtime helpers false saved provider still calls default model getter" { try both("saved-false"); }
test "native Main runtime helpers missing saved model chooses first scoped entry" { try both("saved-missing"); }
test "native Main runtime helpers existing session suppresses selection while preserving scope mapping" { try both("existing-session"); }
test "native Main runtime helpers first scoped entry and thinking are reread" { try both("first-repeat"); }
test "native Main runtime helpers scope length remains live across selection and mapping" { try both("length-live"); }
test "native Main runtime helpers scoped model arrow escapes with original literal field order" { try both("scope-map-escape"); }
test "native Main runtime helpers find callback keeps genuine saved model after normal return" { try both("find-escape"); }
test "native Main runtime helpers find callback keeps genuine saved model after abrupt return" { try both("find-throw-escape"); }
test "native Main runtime helpers captured real named model imports resist later member replacement" { try both("capture-imports"); }
test "native Main runtime helpers option assignment invokes inherited setters" { try both("options-setter"); }
test "native Main runtime helpers all tool exclusion suppresses builtin option and copies tools" { try both("tools-precedence"); }
test "native Main runtime helpers builtin-only tool exclusion remains distinct" { try both("builtin-only"); }
test "native Main runtime helpers array spread uses actual two iterator Gets and repeated tools Get" { try both("spread-order"); }
test "native Main runtime helpers array spread closes next failure preserving original exception" { try both("spread-next-failure"); }
test "native Main runtime helpers array spread closes done getter failure preserving original exception" { try both("spread-done-failure"); }
test "native Main runtime helpers array spread closes value getter failure preserving original exception" { try both("spread-value-failure"); }
test "native Main runtime helpers array spread next acquisition failure has no close" { try both("spread-getnext-failure"); }
test "native Main runtime helpers noniterable second tools Get suppresses later excludes" { try both("spread-noniterable"); }
test "native Main runtime helpers path mapping suppresses only nullish inputs" { try both("path-nullish"); }
test "native Main runtime helpers actual path utilities resolve local and preserve remote inputs" { try both("path-actual"); }
test "native Main runtime helpers path map preserves actual array holes" { try both("path-holes"); }
test "native Main runtime helpers path named functions capture once from actual module" { try both("path-capture"); }
test "native Main runtime helpers live path map receiver and callback order" { try both("path-order"); }
test "native Main runtime helpers path callback retains actual cwd formal after normal return" { try both("path-escape"); }
test "native Main runtime helpers path callback retains actual cwd formal after map throw" { try both("path-throw-escape"); }
test "native Main runtime helpers actual SettingsManager defaults feed scoped selection" { try both("actual-settings"); }
test "native Main runtime helpers resolved local survives until original function terminal" { try both("resolved-lifetime"); }
test "native Main runtime helpers condition temporary retires before next expression" { try both("condition-lifetime"); }
test "native Main runtime helpers Boolean argument lifetime ends before resolver call" { try both("boolean-lifetime"); }
test "native Main runtime helpers actual receiver and extra call argument lifetime" { try both("extra-argument-lifetime"); }
test "native Main runtime helpers saved model cell closes after escaped callback release" { try both("saved-binding-lifetime"); }
test "native Main runtime helpers saved model cell survives abrupt return then releases" { try both("saved-binding-abrupt-lifetime"); }
test "native Main runtime helpers cwd formal cell survives escape without activation leak" { try both("cwd-lifetime"); }
test "native Main runtime helpers actual private native DATA remains ordinary catchable throw" { try both("actual-private-data"); }
test "native Main runtime helpers actual fresh fatal bypasses guest catch" { try fatal("current"); }
test "native Main runtime helpers retirement fatal stops next property" { try fatal("retirement"); }
test "native Main runtime helpers retirement cancellation stops next property" { try fatal("cancelled"); }

fn expectFailure(s: *v.Scope, expected: []const u8) !void {
    const reason = s.engine.captured_exception orelse return error.ActualMainFailureReasonRequired;
    const message = try v.get(s, reason, "message");
    const included = try v.invoke(s, message, "includes", &.{try v.text(s, expected)});
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, included, c.JS_NewBool(s.engine.context, true)));
}
const Foreign = enum { runtime, platform, utilities };
fn verifyForeign(comptime selected: Foreign) !void {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const receiver = fixture.owner();
    const value = try ActualTrustApplication.foreign(&s);
    const original_runtime = receiver.runtime_imports;
    if (selected == .runtime) receiver.runtime_imports = c.JS_DupValue(s.engine.context, value);
    defer if (selected == .runtime) {
        s.engine.freeValue(receiver.runtime_imports);
        receiver.runtime_imports = original_runtime;
    };
    if (selected == .platform) try v.set(&s, receiver.runtime_imports, "platform", value);
    if (selected == .utilities) {
        const platform = try v.get(&s, receiver.runtime_imports, "platform");
        try v.set(&s, platform, "pathUtilities", value);
    }
    const count = s.engine.native_module_values.count();
    try std.testing.expectError(error.JavaScriptException, receiver.createMainRuntimeHelpers());
    try expectFailure(&s, switch (selected) {
        .runtime => "ActualMainRuntimeNamespaceChanged",
        .platform => "ActualMainPlatformNamespaceChanged",
        .utilities => "ActualMainPathUtilitiesChanged",
    });
    try std.testing.expectEqual(count, s.engine.native_module_values.count());
    try std.testing.expect(!s.engine.native_module_values.contains(cache_key));
    try expect(&s, "__trustForeignReads===0");
    try clean(s.engine);
}
fn pendingAssembly(comptime fatal_case: bool) !void {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const probe = try ActualTrustApplication.installProbe(&s, fixture.owner(),
        if (fatal_case) .pending_fatal else .pending_ordinary);
    const count = s.engine.native_module_values.count();
    const generation = s.engine.native_allocation_generation;
    const suppression = s.engine.native_exception_diagnostics_suppressed;
    try std.testing.expectError(error.JavaScriptException, fixture.owner().createMainRuntimeHelpers());
    const reason = s.engine.captured_exception orelse return error.ActualMainPendingReasonRequired;
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason, probe.reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason) == fatal_case);
    try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
    try std.testing.expectEqual(@as(usize, 0), probe.filesystem_reads);
    try std.testing.expectEqual(count, s.engine.native_module_values.count());
    try std.testing.expectEqual(suppression, s.engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!s.engine.native_module_values.contains(cache_key));
    try std.testing.expect(s.engine.native_fatal_invocation == null);
    if (fatal_case) try std.testing.expect(s.engine.native_allocation_generation -% generation != 0);
}
fn reenter(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return helpers.create(engine, roots[0]);
}
test "native Main runtime helpers foreign runtime rejects before guest members" { try verifyForeign(.runtime); }
test "native Main runtime helpers foreign platform rejects before guest members" { try verifyForeign(.platform); }
test "native Main runtime helpers foreign path utilities reject before guest members" { try verifyForeign(.utilities); }
test "native Main runtime helpers pending carrier normal return preserves ordinary exception" { try pendingAssembly(false); }
test "native Main runtime helpers pending carrier normal return preserves genuine fatal" { try pendingAssembly(true); }
test "native Main runtime helpers actual host retirement during carrier getter retains rooted inputs" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const probe = try ActualTrustApplication.installProbe(&s, fixture.owner(), .retire_owner);
    const exports = try v.own(&s, try fixture.owner().createMainRuntimeHelpers());
    try std.testing.expect(!fixture.owner().live);
    try std.testing.expectEqual(@as(usize, 1), probe.platform_reads);
    try std.testing.expectEqual(@as(usize, 0), probe.filesystem_reads);
    try std.testing.expect(c.JS_IsFunction(s.engine.context, try v.get(&s, exports, "buildSessionOptions")));
    try std.testing.expect(c.JS_IsFunction(s.engine.context, try v.get(&s, exports, "resolveCliPaths")));
    try std.testing.expectError(error.ActualSdkAuthOwnerRetired, fixture.owner().createMainRuntimeHelpers());
    try clean(s.engine);
}
test "native Main runtime helpers warm cache preserves genuine imports without rereading named members" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const first = try v.own(&s, try fixture.owner().createMainRuntimeHelpers());
    try expose(&s, "__mhPaths", s.engine.native_module_values.get("pi-private:actual-sdk-path-utilities").?);
    try run(&s,
        \\Object.defineProperty(__mhPaths,"isLocalPath",{configurable:true,get(){throw Error("warm named import read")}});
        \\Object.defineProperty(__mhPaths,"resolvePath",{configurable:true,get(){throw Error("warm named import read")}});
    );
    const second = try v.own(&s, try fixture.owner().createMainRuntimeHelpers());
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, first, second));
    const cli_first = try v.own(&s, try helpers.cliBindings(s.engine));
    const cli_second = try v.own(&s, try helpers.cliBindings(s.engine));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, cli_first, cli_second));
    try clean(s.engine);
}
test "native Main runtime helpers cold same-engine creation reentry publishes only complete pair" {
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const paths = s.engine.native_module_values.get("pi-private:actual-sdk-path-utilities").?;
    try expose(&s, "__mhPaths", paths);
    try expose(&s, "__mhReenter", try v.ordinary(&s, "actualMainReenter", 0, reenter, &.{paths}));
    try run(&s,
        \\globalThis.__mhColdReads=0;globalThis.__mhColdCaught=false;
        \\const savedMainLocal=__mhPaths.isLocalPath;
        \\Object.defineProperty(__mhPaths,"isLocalPath",{configurable:true,get(){
        \\  __mhColdReads++;
        \\  try{__mhReenter();}catch(error){__mhColdCaught=String(error).includes("ActualMainHelpersCreationReentry");}
        \\  return savedMainLocal;
        \\}});
    );
    _ = try v.own(&s, try fixture.owner().createMainRuntimeHelpers());
    try expect(&s, "__mhColdReads===1&&__mhColdCaught");
    try std.testing.expect(s.engine.native_module_values.contains(cache_key));
    try clean(s.engine);
}
test "native Main runtime helpers normal returned getter preserves its actual pending reason" {
    var disk = try Disk.init(); defer disk.deinit();
    var fixture: ActualTrustApplication.Fixture = undefined; try fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    try providers(&s, &fixture, &disk);
    _ = try start(&s, &fixture, false);
    try run(&s, "globalThis.__mhPendingReason={sentinel:true};globalThis.__mhAfterPending=0;");
    const reason = try v.global(&s, "__mhPendingReason");
    try std.testing.expectError(error.JavaScriptException, run(&s,
        \\__mhSubject.buildSessionOptions({
        \\  get provider(){return __mhPendingNative();},
        \\  get model(){__mhAfterPending++;return undefined;}
        \\},[],false,{},__mhSettings);
    ));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason,
        s.engine.captured_exception orelse return error.ActualMainPendingReasonRequired));
    try expect(&s, "__mhAfterPending===0");
    try clean(s.engine);
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

