//! Actual public print/JSON bodies with genuine native platform, stdio, child,
//! configuration, shell and stdout owners. Tests replace the guest stdout.write
//! property before first guard capture, so the test IPC stream remains intact.
//! These are authored controls; build/metadata/runtime qualification is separate.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const public_print = @import("extensions/native_public_print_mode.zig");
const json_event = @import("extensions/native_public_json_event.zig");
const output_guard = @import("extensions/native_sdk_output_guard.zig");
const streams = @import("extensions/native_process_streams.zig");
const Frontend = @import("extensions/native_stdio_frontend.zig").Frontend;
const capture = @import("extensions/native_child_process_frontend_inputs.zig");
const child = @import("extensions/native_node_child_process_public.zig");
const internal = @import("extensions/native_node_internal_builtin_require.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const config_module_url = "file:///C:/Users/adyba/pi-zig/upstream/pi/packages/coding-agent/src/config.ts";
const output_fields = .{
    .{ "takeOverStdout", "take_over_stdout" }, .{ "restoreStdout", "restore_stdout" },
    .{ "isStdoutTakenOver", "is_stdout_taken_over" }, .{ "writeRawStdout", "write_raw_stdout" },
    .{ "waitForRawStdoutBackpressure", "wait_for_raw_stdout_backpressure" }, .{ "flushRawStdout", "flush_raw_stdout" },
};
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn installed(engine: *v.em.Engine, name: []const u8) !c.JSValue {
    return engine.native_module_values.get(name) orelse error.RequiredActualPrintPlatformOwner;
}
fn releaseBundle(completion: *v.owned.Completion, bundle: child.Bundle) void {
    inline for (.{ "node", "cross_spawn", "net" }) |name| completion.release(@field(bundle, name));
}
fn createBundle(engine: *v.em.Engine, inputs: *capture.Owned) !child.Bundle {
    return child.create(engine, try inputs.view(engine));
}
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *v.em.Engine,
    frontend: Frontend,
    require: c.JSValue,
    bundle: ?child.Bundle = null,
    fn init(self: *Fixture, native: bool) !void {
        self.bundle = null;
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 1_000_000 });
        errdefer self.engine.deinit();
        try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(self.engine, std.testing.io, &self.environment, &.{"actual-public-print-controls"});
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
        var inputs = try capture.capture(self.engine, &self.frontend, .{ .internal_require = self.require, .permission = .disabled });
        const bundle = createBundle(self.engine, &inputs) catch |err| {
            var failure = v.owned.Completion.initVoid(self.engine, err);
            inputs.retireInto(&failure); try failure.finishVoid(); unreachable;
        };
        var completed = v.owned.Completion.initVoid(self.engine, {});
        inputs.retireInto(&completed);
        completed.finishVoid() catch |err| {
            var failure = v.owned.Completion.initVoid(self.engine, err);
            releaseBundle(&failure, bundle); try failure.finishVoid(); unreachable;
        };
        self.bundle = bundle;
        errdefer bundle.deinit(self.engine);
        // Same actual stdio lease remains live for child, shell and guard.
        try std.testing.expect(streams.ownsLease(self.engine, self.frontend.lease.?));
        const observer = try self.engine.eval(
            \\globalThis.printWrites=[];globalThis.printErrors=[];globalThis.printWriteFailure=undefined;
            \\process.stdout.write=function(chunk,callback){printWrites.push(String(chunk));if(typeof callback==="function")callback(printWriteFailure);return true};
            \\console.error=(...values)=>{printErrors.push(values)};
        , "actual-print-output-observer.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(observer);
        var s: v.Scope = .{ .engine = self.engine };
        try v.owned.finishVoid(&s, self.prepare(&s, native));
    }
    fn prepare(self: *Fixture, s: *v.Scope, native: bool) !void {
        const platform = try v.own(s, try @import("extensions/native_sdk_filesystem_namespaces.zig").createPlatform(self.engine));
        const process = try v.global(s, "process");
        const configuration = try v.own(s, try @import("extensions/native_sdk_configuration_production.zig").create(self.engine, .{
            .process = process, .os = try installed(self.engine, "node:os"), .url = try installed(self.engine, "node:url"),
            .paths = try v.get(s, platform, "paths"), .filesystem = try v.get(s, platform, "filesystem"),
            .path_utilities = try v.get(s, platform, "pathUtilities"), .module_url = try v.text(s, config_module_url), .user_agent_runtime = .native_zig,
        }));
        const shell = try v.own(s, try @import("extensions/native_sdk_shell_production.zig").create(self.engine, .{
            .process = process, .paths = try v.get(s, platform, "paths"), .filesystem = try v.get(s, platform, "filesystem"),
            .child_process = self.bundle.?.node, .configuration = configuration,
        }));
        const output = try output_guard.create(self.engine, process, self.frontend.lease.?);
        var prepared: v.Scope = .{ .engine = self.engine };
        var completion = v.owned.Completion.initVoid(self.engine, prepareModules(&prepared, output, shell, native));
        completion.releaseScope(&prepared);
        inline for (std.meta.fields(output_guard.Exports)) |field| completion.release(@field(output, field.name));
        try completion.finishVoid();
    }
    fn deinit(self: *Fixture) void {
        // No child is spawned in these controls. Real Hub teardown still owns
        // any descriptor capabilities captured while constructing the graph.
        if (self.engine.native_env_deinit) |close| close(self.engine);
        if (self.bundle) |bundle| { self.bundle = null; bundle.deinit(self.engine); }
        self.frontend.deinit();
        self.engine.freeValue(self.require);
        self.engine.deinit();
        self.environment.deinit();
    }
};
fn prepareModules(s: *v.Scope, output: output_guard.Exports, shell: c.JSValue, native: bool) !void {
    const output_namespace = try v.object(s);
    inline for (output_fields) |field| try v.put(s, output_namespace, field[0], @field(output, field[1]));
    const native_json = try v.own(s, try json_event.create(s.engine));
    const json_factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/public-json-event-c268-source.mjs"), "actual-json-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const source_json = try v.call(s, json_factory, c.pi_js_undefined(), &.{});
    const native_mode = try v.own(s, try public_print.create(s.engine, .{ .output = output, .shell = shell }));
    const print_factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/public-print-mode-c268-source.mjs"), "actual-print-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const source_mode = try v.call(s, print_factory, c.pi_js_undefined(), &.{ output_namespace, shell, source_json });
    try publish(s, "actualPrintOutput", output_namespace);
    try publish(s, "actualPrintShell", shell);
    try publish(s, "nativePrint", native_mode);
    try publish(s, "sourcePrint", source_mode);
    try publish(s, "selectedPrint", if (native) native_mode else source_mode);
    try publish(s, "nativePrintJson", native_json);
    try publish(s, "sourcePrintJson", source_json);
    try publish(s, "selectedJson", if (native) native_json else source_json);
    try publish(s, "printHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/public-print-mode-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    const namespace = try engine.evalModule(source, "actual-public-print-observer.mjs"); engine.freeValue(namespace);
}
fn read(engine: *v.em.Engine, name: [*:0]const u8) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, readBody(&s, name));
}
fn readBody(s: *v.Scope, name: [*:0]const u8) !c.JSValue { return v.duplicate(s, try v.global(s, name)); }
test "Public print actual genuine AF shape and retained native owner identities" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    try run(fixture.engine,
        \\for(const api of[sourcePrint,nativePrint]){
        \\ const fn=api.runPrintMode;if(fn.name!=="runPrintMode"||fn.length!==2||Object.prototype.toString.call(fn)!=="[object AsyncFunction]"||Object.hasOwn(fn,"prototype"))throw Error("Actual runPrintMode metadata");
        \\ if(Object.keys(api).join()!=="runPrintMode")throw Error("Actual print export set");
        \\}
        \\if(typeof actualPrintShell.killTrackedDetachedChildren!=="function"||actualPrintShell.killTrackedDetachedChildren.length!==0)throw Error("Actual shell owner");
        \\actualPrintShell.killTrackedDetachedChildren();
    );
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const process = try v.global(&s, "process");
    const output = try output_guard.create(fixture.engine, process, fixture.frontend.lease.?); defer output.deinit(fixture.engine);
    const shell = try v.global(&s, "actualPrintShell");
    const repeated = try v.own(&s, try public_print.create(fixture.engine, .{ .output = output, .shell = shell }));
    try std.testing.expect(v.equal(&s, repeated, try v.global(&s, "nativePrint")));
    try std.testing.expect(v.equal(&s, shell, try installed(fixture.engine, "pi-native:sdk-shell")));
}
test "Public print actual serial prompts images text and signal cleanup" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintText();"); }
}
test "Public print actual JSON header projection and agent backpressure" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintJson();"); }
}
test "Public print actual command actions Await adoption and live session rebinding" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintActions();"); }
}
test "Public print actual captured rebind TDZ and closed callback lifetime" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintTdz();"); }
}
test "Public print actual setup failure remains outside catch and finally" {
    inline for (.{ false, true }) |native| {
        inline for (.{ "session", "set-rebind" }) |which| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try run(fixture.engine, "await observePrintSetupFailure('" ++ which ++ "');");
        }
    }
}
test "Public print actual first prompt DATA IteratorClose and next failure" {
    inline for (.{ false, true }) |native| {
        inline for (.{ "true", "false" }) |next_throws| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try run(fixture.engine, "await observePrintPromptClose(" ++ next_throws ++ ");");
        }
    }
}
test "Public print actual cleanup dispose and flush rejection precedence" {
    inline for (.{ false, true }) |native| {
        inline for (.{ "cleanup", "dispose", "flush" }) |which| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try run(fixture.engine, "await observePrintFinalFailure('" ++ which ++ "');");
        }
    }
}
test "Public print actual assistant error aborted and length diagnostics" {
    inline for (.{ false, true }) |native| {
        inline for (.{ "error", "aborted", "length" }) |which| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try run(fixture.engine, "await observePrintStatus('" ++ which ++ "');");
        }
    }
}
test "Public print actual loop head survives next done and dispose Await" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintMessageLocals();"); }
}
test "Public print actual closed signal captures retain original slots through next" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintSignalLocals();"); }
}
test "Public print actual signal closures invoke the real empty shell owner and dispose once" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintSignalExit();"); }
}
test "Public print actual live process receiver retirement before later getters" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintProcessRetirement();"); }
}
test "Public print actual same-operation private DATA remains ordinary" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "await observePrintPrivateData();"); }
}
test "Public print actual current native B bypasses guest catch and finally" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const hooks = try read(fixture.engine, "printHooks"); defer fixture.engine.freeValue(hooks);
    const observed = try fixture.engine.checked(c.JS_GetPropertyStr(fixture.engine.context, hooks, "record")); defer fixture.engine.freeValue(observed);
    try std.testing.expectError(error.JavaScriptException, run(fixture.engine, "await observePrintCurrentFatal();"));
    try retirement.verifyRecordedActualNativeFatal(fixture.engine, observed);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), fixture.engine.native_exception_diagnostics_suppressed);
}
test "Public print actual JSON ordinary identity exclusion and diagnostics" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "observeJsonProjection();"); }
}
test "Public print actual JSON repeated getters coercion rest and symbol order" {
    inline for (.{ false, true }) |native| { var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit(); try run(fixture.engine, "observeJsonLiveOrder();"); }
}
