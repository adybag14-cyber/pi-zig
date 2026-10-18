//! Actual public RPC controls with genuine native platform, stdio, child,
//! configuration, shell and stdout owners. Tests replace the guest stdout.write
//! property before first guard capture, so the test IPC stream remains intact.
//! These are authored controls; build/metadata/runtime qualification is separate.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
pub const public_rpc = @import("extensions/native_public_rpc_mode.zig");
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
    return engine.native_module_values.get(name) orelse error.RequiredActualRpcPlatformOwner;
}
fn releaseBundle(completion: *v.owned.Completion, bundle: child.Bundle) void {
    inline for (.{ "node", "cross_spawn", "net" }) |name| completion.release(@field(bundle, name));
}
fn createBundle(engine: *v.em.Engine, inputs: *capture.Owned) !child.Bundle {
    return child.create(engine, try inputs.view(engine));
}
pub const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *v.em.Engine,
    frontend: Frontend,
    require: c.JSValue,
    bundle: ?child.Bundle = null,
    pub fn init(self: *Fixture, native: bool) !void {
        self.bundle = null;
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 1_000_000 });
        errdefer self.engine.deinit();
        try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(self.engine, std.testing.io, &self.environment, &.{"actual-public-rpc-controls"});
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
            \\globalThis.rpcWrites=[];globalThis.rpcErrors=[];globalThis.rpcRawWriteControl=undefined;
            \\process.stdout.write=function(chunk,callback){const text=String(chunk);rpcWrites.push(text);if(rpcRawWriteControl)return rpcRawWriteControl(text,callback);if(typeof callback==="function")callback();return true};
            \\console.error=(...values)=>{rpcErrors.push(values)};
            \\process.stdin.pause();
        , "actual-rpc-output-observer.js", c.JS_EVAL_TYPE_GLOBAL);
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
    pub fn deinit(self: *Fixture) void {
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
    // The actual paused stdin is driven by its real EventEmitter in these
    // controls; no test acquires the process IPC pipe as a physical reader.
    try @import("extensions/native_tui.zig").install(s.engine);
    const themes = try v.own(s, try @import("extensions/native_public_theme.zig").create(s.engine));
    const theme = try v.get(s, themes, "theme");
    const output_namespace = try v.object(s);
    inline for (output_fields) |field| try v.put(s, output_namespace, field[0], @field(output, field[1]));
    const native_json = try v.own(s, try json_event.create(s.engine));
    const json_factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/public-json-event-c268-source.mjs"), "actual-rpc-json-event-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const source_json = try v.call(s, json_factory, c.pi_js_undefined(), &.{});
    const native_jsonl = try v.own(s, try @import("extensions/native_public_rpc_jsonl.zig").create(s.engine));
    const decoder_namespace = try installed(s.engine, "node:string_decoder");
    const decoder_imports = try v.object(s);
    try v.put(s, decoder_imports, "StringDecoder", try v.get(s, decoder_namespace, "StringDecoder"));
    try publish(s, "__rpcJsonlImports", decoder_imports);
    const source_jsonl = try v.own(s, try s.engine.evalModule(@embedFile("extensions/fixtures/public-rpc-jsonl-c268-source.mjs"), "actual-rpc-mode-jsonl-source.mjs"));
    const crypto = try v.object(s);
    try v.put(s, crypto, "randomUUID", try v.own(s, try @import("extensions/native_node_crypto_uuid_binding.zig").create(s.engine)));
    const imports = try v.object(s);
    inline for (.{ .{ "crypto", crypto }, .{ "output", output_namespace }, .{ "shell", shell }, .{ "theme", themes }, .{ "json", source_json }, .{ "jsonl", source_jsonl } }) |entry| try v.put(s, imports, entry[0], entry[1]);
    try publish(s, "__rpcSourceDependencies", imports);
    const source_mode = try v.own(s, try s.engine.evalModule(@embedFile("extensions/fixtures/public-rpc-mode-c268-source.mjs"), "actual-rpc-mode-source.mjs"));
    const native_mode = try v.own(s, try public_rpc.create(s.engine, .{ .output = output, .shell = shell, .theme = theme }));
    try publish(s, "actualRpcOutput", output_namespace);
    try publish(s, "actualRpcShell", shell);
    try publish(s, "actualRpcTheme", theme);
    try publish(s, "nativeRpc", native_mode);
    try publish(s, "sourceRpc", source_mode);
    try publish(s, "selectedRpc", if (native) native_mode else source_mode);
    try publish(s, "actualRpcJson", native_json);
    try publish(s, "actualRpcJsonl", native_jsonl);
    try publish(s, "rpcHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
pub fn run(engine: *v.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/public-rpc-mode-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    const namespace = try engine.evalModule(source, "actual-public-rpc-observer.mjs");
    engine.freeValue(namespace);
}
pub fn both(tail: []const u8) !void {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined;
        try fixture.init(native);
        defer fixture.deinit();
        try run(fixture.engine, tail);
    }
}
