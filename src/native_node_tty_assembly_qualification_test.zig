//! Candidate actual-module target. SOURCE ONLY: requires the independently
//! closed filesystem dependency packet before build/metadata admission.
//! These controls qualify assembly/event ownership, NOT physical console IO.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const c = em.c;
const deps = @import("extensions/native_node_tty_dependencies.zig");
const frontend = @import("extensions/native_stdio_frontend.zig");
const composition = @import("extensions/native_node_tty_frontend_assembly.zig");
const Actual = @import("extensions/native_node_tty_profile.zig").Frontend;
const Builtins = Actual.Builtins;
const Fixture = struct {
    engine: *em.Engine = undefined,
    front: frontend.Frontend = undefined,
    bootstrap: composition.Bootstrap = undefined,
    front_ready: bool = false,
    bootstrap_ready: bool = false,
    process: ?c.JSValue = null,
    streams: ?c.JSValue = null,
    canonical: *deps.canonical.Bundle = undefined,
    fn init(self: *Fixture) !void {
        if (builtin.os.tag != .windows) return error.SkipZigTest;
        self.* = .{};
        self.engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        errdefer self.deinit();
        var environment = try std.testing.environ.createMap(std.testing.allocator); defer environment.deinit();
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &environment, &.{"native-tty-assembly-control"});
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/commonjs.zig").install(self.engine);
        try @import("extensions/native_node_os.zig").install(self.engine);
        const global = c.JS_GetGlobalObject(self.engine.context); defer self.engine.freeValue(global);
        self.process = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "process"));
        try @import("extensions/native_node_stream.zig").install(self.engine, self.process.?);
        self.streams = (try self.engine.requireBuiltin("node:stream")) orelse return error.RequiredActualClassicStreams;
        try self.front.init(self.engine, std.testing.io); self.front_ready = true;
        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const directory = try std.Io.Dir.cwd().openDir(std.testing.io, ".", .{}); defer directory.close(std.testing.io);
        const length = try directory.realPath(std.testing.io, &path_buffer);
        const filename = try std.fs.path.join(std.testing.allocator, &.{ path_buffer[0..length], "verification", "node-tty-composition-sourceonly-20261017", "original-alias-identity.mjs" }); defer std.testing.allocator.free(filename);
        self.bootstrap = try composition.Bootstrap.capture(self.engine, &self.front, filename); self.bootstrap_ready = true;
        self.canonical = try deps.canonical.acquire(self.engine, self.streams.?, self.process.?);
    }
    fn inputs(self: *const Fixture) Builtins.Inputs {
        return .{ .canonical_socket = &self.canonical.provider, .actual_net = self.canonical.net, .actual_process = self.process.?,
            .physical_filename = self.bootstrap.physical_filename, .primordials = &self.bootstrap.primordials,
            .frontend_mode = self.bootstrap.native_mode, .qualification_admission = false };
    }
    fn deinit(self: *Fixture) void {
        // Stop actual native owners while the real frontend and Engine remain
        // alive. Hub clears its own teardown hook; Engine won't retire twice.
        if (self.engine.native_env_deinit) |stop| stop(self.engine);
        if (self.bootstrap_ready) self.bootstrap.deinit();
        if (self.front_ready) self.front.deinit();
        if (self.streams) |value| self.engine.freeValue(value);
        if (self.process) |value| self.engine.freeValue(value);
        self.engine.deinit();
    }
};

test "native TTY assembly actual frontend canonical namespace and require identities" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    const installed = try Actual.install(&fixture.bootstrap, &fixture.canonical.provider, fixture.canonical.net, false); defer installed.deinit(fixture.engine);
    try @import("native_node_tty_assembly_identity_control.zig").run(Builtins, fixture.engine, fixture.inputs(), true);
}
test "native TTY assembly initializing cache rejects actual getter reentry" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    try @import("native_node_tty_assembly_identity_control.zig").initializationBoundary(Builtins, fixture.engine, fixture.inputs(), false);
}
test "native TTY assembly actual dependency getter failure permits same owner retry" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    try @import("native_node_tty_assembly_identity_control.zig").initializationBoundary(Builtins, fixture.engine, fixture.inputs(), true);
}
test "native TTY assembly raw pending result stops next actual builtin getter" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    try @import("native_node_tty_assembly_event_control.zig").run(Builtins, fixture.engine, fixture.inputs(), true, false);
}
test "native TTY assembly raw owned pending result preserves first ordinary and actual fatal" {
    for ([_]bool{ false, true }) |fatal| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_assembly_event_control.zig").pendingOwned(Builtins, fixture.engine, fixture.inputs(), fatal);
    }
}
test "native TTY assembly temporary finalizers preserve first ordinary and actual fatal" {
    for ([_]bool{ false, true }) |fatal| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_assembly_event_control.zig").run(Builtins, fixture.engine, fixture.inputs(), false, fatal);
    }
}
test "native TTY assembly trusted GPA failure cannot become catchable cleanup error" {
    for ([_]bool{ false, true }) |fatal| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_assembly_event_control.zig").hostOom(Builtins, fixture.engine, fixture.inputs(), fatal);
    }
}
test "native TTY assembly actual OS release getter stays lazy" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    try @import("native_node_tty_assembly_event_control.zig").lazyOs(Builtins, fixture.engine, fixture.inputs());
}
test "native TTY assembly failed immutable publication keeps identity and historical DATA" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    _ = try @import("native_node_tty_assembly_publication_control.zig").run(Builtins, fixture.engine, fixture.inputs(), 0);
}
test "native TTY assembly builtin aliases preserve replaced user loader caller paths" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    const exports = try Builtins.install(fixture.engine, fixture.inputs()); defer exports.deinit(fixture.engine);
    try @import("native_node_tty_builtin_alias_control.zig").loaderReplacement(fixture.engine);
}
test "native TTY assembly alias pending entry does not format reason or mutate map" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    const exports = try Builtins.install(fixture.engine, fixture.inputs()); defer exports.deinit(fixture.engine);
    try @import("native_node_tty_builtin_alias_control.zig").pendingEntry(fixture.engine);
}
test "native TTY assembly alias current fatal is distinct from same flagged historical DATA" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    const exports = try Builtins.create(fixture.engine, fixture.inputs()); defer exports.deinit(fixture.engine);
    try @import("native_node_tty_builtin_alias_control.zig").currentFatalEntry(fixture.engine, exports.tty_exports);
}
test "native TTY assembly alias real GPA failure retries one canonical module" {
    for ([_]usize{ 0, 1, 2 }) |index| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        const exports = try Builtins.create(fixture.engine, fixture.inputs()); defer exports.deinit(fixture.engine);
        try @import("native_node_tty_builtin_alias_control.zig").allocationFailure(fixture.engine, exports.tty_exports, index);
    }
}
test "native TTY assembly aliases preserve actual linked C default relative normalization" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    const exports = try Builtins.create(fixture.engine, fixture.inputs()); defer exports.deinit(fixture.engine);
    try @import("native_node_tty_alias_default_normalizer_control.zig").run(fixture.engine, exports.tty_exports);
}
test "native TTY assembly preserves genuine existing canonical and legacy net records" {
    for ([_]bool{ false, true }) |legacy| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_net_publication_control.zig").preexisting(Builtins, fixture.engine, fixture.inputs(), legacy);
    }
}
test "native TTY assembly refuses an actual other builtin as canonical net" {
    var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
    try @import("native_node_tty_net_publication_control.zig").conflict(Builtins, fixture.engine, fixture.inputs());
}
test "native TTY assembly frontend raw process result protects ordinary and fresh fatal" {
    for ([_]bool{ false, true }) |fatal| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_frontend_process_control.zig").run(Actual, &fixture.bootstrap, &fixture.canonical.provider, fixture.canonical.net, fatal);
    }
}
test "native TTY assembly live net export event stops next field before adopter" {
    for ([_]bool{ false, true }) |fatal| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_net_export_event_control.zig").run(Builtins, fixture.engine, fixture.inputs(), fatal);
    }
}
test "native TTY assembly successful consuming define stops on new captured producer" {
    for ([_]bool{ false, true }) |framed| {
        var fixture: Fixture = .{}; try fixture.init(); defer fixture.deinit();
        try @import("native_node_tty_net_status_event_control.zig").run(Builtins, fixture.engine, fixture.inputs(), framed);
    }
}
