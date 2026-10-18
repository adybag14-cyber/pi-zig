//! Executable controls over the real native process, Stream, timers, OS,
//! internal builtin loader, stdio lease, public child driver and live waiter.
//! Authored only: install-only build and runtime qualification are separate.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const factory = @import("extensions/native_child_process_frontend_inputs.zig");
const public = @import("extensions/native_node_child_process_public.zig");
const internal = @import("extensions/native_node_internal_builtin_require.zig");
const Scope = @import("extensions/native_node_socket_scope.zig").Scope;
const controls = @import("native_child_process_frontend_inputs_controls.zig");
const waiter = @import("extensions/native_wait_for_child_process.zig");
const live = @import("native_live_child_waiter_controls.zig");
const boundary = @import("native_live_child_waiter_boundary_controls.zig");
const Frontend = @import("extensions/native_stdio_frontend.zig").Frontend;

const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *js.Engine,
    frontend: Frontend = undefined,
    require: c.JSValue,
    fn init(self: *Fixture) !void {
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        errdefer self.engine.deinit();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-actual-child-control"});
        // The real OS owner installs the genuine Stream owner against this
        // exact process before frontend capture; no replacement Stream inputs.
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.require = try internal.acquire(self.engine, .{ .bindings = &.{
            .{ .id = "util", .module_name = "node:util" },
            .{ .id = "stream", .module_name = "node:stream" },
            .{ .id = "process", .module_name = "node:process" },
            .{ .id = "timers", .module_name = "node:timers" },
        } });
        errdefer self.engine.freeValue(self.require);
        // util is a lazy admission, not a fabricated completed module. These
        // controls exercise successful real spawn and do not claim its absent
        // error-name provider ready; actual Errno failures remain a separate gate.
        try self.frontend.init(self.engine, std.testing.io);
    }
    fn host(self: *Fixture) factory.Host { return .{ .internal_require = self.require, .permission = .disabled }; }
    fn deinit(self: *Fixture) void {
        // The real native Hub cancels/joins precisely its owned children and
        // descriptors on every exit, including an actual fatal getter. No guest
        // kill/restoration callback is used during this cleanup.
        if (self.engine.native_env_deinit) |close| close(self.engine);
        self.frontend.deinit();
        self.engine.freeValue(self.require);
        self.engine.deinit();
        self.environment.deinit();
    }
    fn bundle(self: *Fixture) !public.Bundle {
        var inputs = try factory.capture(self.engine, &self.frontend, self.host());
        defer inputs.deinit() catch @panic("actual child control input retirement failed");
        return public.create(self.engine, try inputs.view(self.engine));
    }
    fn spawn(self: *Fixture, bundle_value: public.Bundle) !c.JSValue {
        var s: Scope = .{ .engine = self.engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
        const args = try s.array();
        const command = if (builtin.os.tag == .windows) "cmd.exe" else if (builtin.os.tag == .linux) "/bin/sh" else return error.UnsupportedActualChildControlPlatform;
        const parameters: []const []const u8 = if (builtin.os.tag == .windows)
            &.{ "/d", "/s", "/c", "echo child-out&&echo child-err 1>&2" }
        else
            &.{ "-c", "printf 'child-out\\n'; printf 'child-err\\n' >&2" };
        for (parameters, 0..) |parameter, index| try s.index(args, @intCast(index), try s.text(parameter));
        const options = try s.object(); const stdio = try s.array();
        inline for (.{ "ignore", "pipe", "pipe" }, 0..) |mode, index| try s.index(stdio, index, try s.text(mode));
        try s.put(options, "stdio", stdio);
        try s.put(options, "shell", c.pi_js_bool(self.engine.context, 0));
        try s.put(options, "windowsHide", c.pi_js_bool(self.engine.context, 1));
        return c.JS_DupValue(self.engine.context, try s.invoke(bundle_value.node, "spawn", &.{try s.text(command), args, options}));
    }
    fn observe(self: *Fixture, child: c.JSValue) !c.JSValue {
        var s: Scope = .{ .engine = self.engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
        const caller = try s.own(try self.engine.eval(
            \\(function(child) {
            \\  let stdout = '', stderr = '';
            \\  child.stdout.on('data', data => { stdout += data.toString(); });
            \\  child.stderr.on('data', data => { stderr += data.toString(); });
            \\  return new Promise(resolve => child.once('close', code => resolve({code, stdout, stderr})));
            \\})
        , "actual-native-child-close-observer.js", c.JS_EVAL_TYPE_GLOBAL));
        return c.JS_DupValue(self.engine.context, try s.call(caller, c.pi_js_undefined(), &.{child}));
    }
    fn finish(self: *Fixture, observed: c.JSValue) !void {
        const row = try self.engine.awaitValueOnly(observed); defer self.engine.freeValue(row);
        var s: Scope = .{ .engine = self.engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
        try std.testing.expect(s.equal(try s.get(row, "code"), c.JS_NewInt32(self.engine.context, 0)));
        const ending = if (builtin.os.tag == .windows) "\r\n" else "\n";
        try std.testing.expect(s.equal(try s.get(row, "stdout"), try s.text("child-out" ++ ending)));
        try std.testing.expect(s.equal(try s.get(row, "stderr"), try s.text("child-err" ++ ending)));
        try self.frontend.runUntilIdle();
        try std.testing.expect(!@import("extensions/native_env_io.zig").hasReferenced(self.engine));
        try std.testing.expect(self.engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
    }
};

test "native actual child frontend captures the real graph and rejects stale lease" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try controls.actualGraph(fixture.engine, &fixture.frontend, fixture.host());
}
test "native actual child frontend incoming pending stops before capture effects" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try controls.actualIncomingPending(fixture.engine, &fixture.frontend, fixture.host());
}
test "native actual child frontend retirement preserves ordinary completion identity" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try controls.actualOwnedCompletionRetirement(fixture.engine, &fixture.frontend, fixture.host());
}
test "native actual child frontend public namespace reuses canonical Socket and process" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const first = try fixture.bundle(); defer first.deinit(fixture.engine);
    const second = try fixture.bundle(); defer second.deinit(fixture.engine);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first.node, second.node));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first.net, second.net));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first.cross_spawn, second.cross_spawn));
    var s: Scope = .{ .engine = fixture.engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    const child = try s.construct(try s.get(first.node, "ChildProcess"), &.{});
    try std.testing.expect(c.JS_IsUndefined(try s.get(child, "pid")));
    try std.testing.expect(c.JS_IsFunction(fixture.engine.context, try s.get(try s.get(child, "_handle"), "onexit")));
}
test "native actual child waiter has Source ordinary constructor metadata" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try live.verifyOrdinaryMetadata(fixture.engine);
}
test "native actual child waiter settles after real native stdout stderr and exit" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const bundle = try fixture.bundle(); defer bundle.deinit(fixture.engine);
    const child = try fixture.spawn(bundle); defer fixture.engine.freeValue(child);
    const observed = try fixture.observe(child); defer fixture.engine.freeValue(observed);
    var s: Scope = .{ .engine = fixture.engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    const wait = try s.own(try waiter.create(fixture.engine));
    const pending = try s.call(wait, c.pi_js_undefined(), &.{child});
    const code = try fixture.engine.awaitValueOnly(pending); defer fixture.engine.freeValue(code);
    try std.testing.expect(s.equal(code, c.JS_NewInt32(fixture.engine.context, 0)));
    try fixture.finish(observed);
}
test "native actual child waiter retires initial null probe before next stream getter" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const bundle = try fixture.bundle(); defer bundle.deinit(fixture.engine);
    const child = try fixture.spawn(bundle); defer fixture.engine.freeValue(child);
    const observed = try fixture.observe(child); defer fixture.engine.freeValue(observed);
    const pending = try boundary.verifyInitialNullProbeBeforeNextActualGetter(fixture.engine, child); defer fixture.engine.freeValue(pending);
    const result = try fixture.engine.awaitValueOnly(pending); defer fixture.engine.freeValue(result);
    try fixture.finish(observed);
}
test "native actual child waiter retires discarded once result and callee before stderr" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const bundle = try fixture.bundle(); defer bundle.deinit(fixture.engine);
    const child = try fixture.spawn(bundle); defer fixture.engine.freeValue(child);
    const observed = try fixture.observe(child); defer fixture.engine.freeValue(observed);
    const pending = try boundary.verifyDiscardedOnceBeforeNextActualGetter(fixture.engine, child); defer fixture.engine.freeValue(pending);
    const result = try fixture.engine.awaitValueOnly(pending); defer fixture.engine.freeValue(result);
    try fixture.finish(observed);
}
test "native actual child waiter preserves same getter private throw as Promise DATA" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const bundle = try fixture.bundle(); defer bundle.deinit(fixture.engine);
    const child = try fixture.spawn(bundle); defer fixture.engine.freeValue(child);
    const observed = try fixture.observe(child); defer fixture.engine.freeValue(observed);
    try boundary.verifyPrivateDataCreatedThenThrownInActualGetter(fixture.engine, child);
    try fixture.finish(observed);
}
test "native actual child waiter forwards historical flagged user event through then catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const bundle = try fixture.bundle(); defer bundle.deinit(fixture.engine);
    const child = try fixture.spawn(bundle); defer fixture.engine.freeValue(child);
    const observed = try fixture.observe(child); defer fixture.engine.freeValue(observed);
    try live.verifyFlaggedDataThroughActualChild(fixture.engine, child);
    try fixture.finish(observed);
}
test "native actual child waiter actual getter fatal escapes live Promise and owner retires" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const bundle = try fixture.bundle(); defer bundle.deinit(fixture.engine);
    const child = try fixture.spawn(bundle); defer fixture.engine.freeValue(child);
    try live.verifyFatalFromActualChildGetter(fixture.engine, child);
    // The exact native owner is closed by Fixture.deinit; no guest operations
    // or fake completed child are substituted after the actual fatal producer.
}
