//! Standalone expected-exit controls for the actual corrupted async-stack path.
//! Each process owns a genuine Engine, native option configuration and aliased
//! Environment. Unselected queue/fatal-hook operations fail explicitly; this
//! fixture makes no claim that the complete Node bootstrap is installed.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const checks = @import("extensions/native_node_callback_checks.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const binding = @import("extensions/native_node_options_binding.zig");
const callable = @import("extensions/native_node_function.zig");

const Selected = struct {
    arguments: []const []const u8 = &.{},
    native_abort: bool = false,
    vm_abort: bool = false,
    corrupt: bool = true,
    mutate_record: bool = false,
    replace_process: bool = false,
};
fn select(name: []const u8) !Selected {
    if (std.mem.eql(u8, name, "control-default")) return .{ .corrupt = false };
    if (std.mem.eql(u8, name, "control-latched")) return .{
        .arguments = &.{ "--abort-on-uncaught-exception", "--no-abort-on-uncaught-exception" },
        .native_abort = true, .corrupt = false,
    };
    if (std.mem.eql(u8, name, "corrupt-default")) return .{};
    if (std.mem.eql(u8, name, "corrupt-positive")) return .{
        .arguments = &.{"--abort-on-uncaught-exception"}, .native_abort = true, .vm_abort = true,
    };
    if (std.mem.eql(u8, name, "corrupt-underscored")) return .{
        .arguments = &.{"--abort_on_uncaught_exception"}, .native_abort = true, .vm_abort = true,
    };
    if (std.mem.eql(u8, name, "corrupt-latched")) return .{
        .arguments = &.{ "--abort-on-uncaught-exception", "--no-abort-on-uncaught-exception" },
        .native_abort = true,
    };
    if (std.mem.eql(u8, name, "corrupt-negative")) return .{
        .arguments = &.{"--no-abort-on-uncaught-exception"},
    };
    if (std.mem.eql(u8, name, "corrupt-mixed")) return .{
        .arguments = &.{"--abort_on-uncaught_exception"}, .vm_abort = true,
    };
    if (std.mem.eql(u8, name, "corrupt-record-mutation")) return .{ .mutate_record = true };
    if (std.mem.eql(u8, name, "corrupt-replaced-process")) return .{ .replace_process = true };
    return error.UnknownNativeCorruptionProbe;
}
fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedNativeCorruptionProbeOperation;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = checks.fail,
    .fail_corrupted_async_stack = checks.corruptedStack,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};
var active_environment: ?*callbacks.Environment = null;
fn corrupt(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const environment = active_environment orelse
        return callable.failure(engine, error.NativeCorruptionProbeEnvironmentRequired, 0);
    _ = environment.popAsyncContext(99) catch |err|
        return callable.failure(engine, err, 0);
    return callable.failure(engine, error.UnexpectedNativeCorruptionReturn, 0);
}
fn initialize(s: *a.Scope, output: *?*callbacks.Environment, selected: Selected) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const process = try s.get(global, "process");
    const allocation = try s.beforeAllocation();
    const symbol = try s.checkedAllocation(c.JS_NewSymbol(
        s.engine.context, "node:resource_symbol", false), allocation);
    const environment = try callbacks.Environment.create(s.engine, .{
        .provider_names = providers.names(false),
        .resource_symbol = symbol,
        .process_object = process,
        .async_context_frame = false,
        .operations = operations,
    });
    // The caller owns this actual Environment before any later setup work.
    output.* = environment;
    if (selected.mutate_record) {
        var pair = try binding.create(s.engine);
        defer {
            s.boundary.release(&pair.values);
            s.boundary.release(&pair.embedder);
        }
        const incoming = pair.values;
        pair.values = c.pi_js_undefined();
        const values = try s.own(incoming);
        const record = try s.call(values, c.pi_js_undefined(), &.{});
        try s.define(record, "--abort-on-uncaught-exception", a.boolean(s, true), c.JS_PROP_C_W_E);
    }
    if (selected.replace_process) {
        const replacement = try s.object();
        const flags = try s.object();
        try s.define(flags, "--abort-on-uncaught-exception", a.boolean(s, true), c.JS_PROP_C_W_E);
        try s.define(replacement, "options", flags, c.JS_PROP_C_W_E);
        try s.put(global, "process", replacement);
    }
    // This exercises the real intrinsic aliased ID stack and original pop
    // check. No test-produced expected ID is substituted inside the adapter.
    try environment.pushAsyncContext(.{ .async_id = 17, .trigger_async_id = 3 }, null);
    if (environment.executionAsyncId() != 17 or environment.triggerAsyncId() != 3 or
        environment.field(.stack_length).* != 1 or environment.field(.check).* != 1)
        return error.UnexpectedNativeCorruptionProbeState;
    return c.pi_js_undefined();
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedOneNativeCorruptionProbe;
    const selected = try select(args[1]);
    var process_environment: std.process.Environ.Map = .init(init.gpa);
    defer process_environment.deinit();
    const engine = try em.Engine.init(init.gpa, .{ .node_options = .{
        .features = .{ .strip_types = true, .quic = false },
        .exec_arguments = selected.arguments,
    } });
    defer engine.deinit();
    try @import("extensions/native_process.zig").install(
        engine, init.io, &process_environment, &.{"native-node-corruption-probe"});
    const options = engine.node_options orelse return error.NativeCorruptionProbeOptionsRequired;
    if (options.values.abort_on_uncaught_exception != selected.native_abort or
        options.vm_abort_on_uncaught_exception != selected.vm_abort)
        return error.UnexpectedNativeCorruptionProbeOptions;
    var environment: ?*callbacks.Environment = null;
    defer if (environment) |owner| {
        active_environment = null;
        owner.cleanupRealmAfterIoJoin() catch @panic("native corruption probe realm cleanup failed");
        owner.disarm() catch @panic("native corruption probe environment disarm failed");
        owner.release();
    };
    const initialized = try a.expression(engine, initialize, .{ &environment, selected });
    engine.freeValue(initialized);
    if (options.values.abort_on_uncaught_exception != selected.native_abort or
        options.vm_abort_on_uncaught_exception != selected.vm_abort)
        return error.UnexpectedNativeCorruptionProbeOptionMutation;
    if (!selected.corrupt) {
        if (try environment.?.popAsyncContext(17)) return error.UnexpectedNativeCorruptionProbeStack;
        if (environment.?.executionAsyncId() != 0 or environment.?.triggerAsyncId() != 0 or
            environment.?.field(.stack_length).* != 0) return error.UnexpectedNativeCorruptionProbeRestore;
        return;
    }
    active_environment = environment;
    try engine.bindFunction("actualNativeCorruption", corrupt, 0);
    const result = try engine.eval(
        "try { actualNativeCorruption(); throw new Error('UNEXPECTED normal return'); }" ++
        " catch (error) { throw new Error('UNEXPECTED guest catch'); }",
        "native-node-corruption-probe.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    return error.UnexpectedNativeCorruptionProbeContinuation;
}
