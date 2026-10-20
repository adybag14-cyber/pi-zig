//! Actual native Environment path and SafeGetenv leaf controls.
//! Trace callbacks below observe delegation only; they do not implement stacks.
//! No process.env interceptor, permission policy or Environment bootstrap is used.
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_node_environment_paths.h");
    @cInclude("native_node_options_environment.h");
    @cInclude("native_node_environment_map_test_support.h");
    @cInclude("uv.h");
    @cInclude("limits.h");
});
const Paths = c.PiNodeEnvironmentPaths;
const Map = c.PiNodeEnvironmentMap;
const Span = c.PiNodeEnvironmentPathSpan;
const Trace = c.PiNodeEnvironmentTrace;
const memory_limit: usize = 32 * 1024 * 1024;
const windows = builtin.os.tag == .windows;
const long_value = "actual-native-path-value-" ++ ("v" ** 600);
const long_component = "native-component-" ++ ("p" ** 300);

fn span(bytes: []const u8) Span { return .{ .data = bytes.ptr, .length = bytes.len }; }
fn quietTrace() Trace { return std.mem.zeroes(Trace); }
fn requireEnvironmentAdmission() !void {
    // Exercise the real credentials gate; this fixture neither overrides it
    // nor calls the Map directly as a substitute for an admitted SafeGetenv.
    try std.testing.expect(c.pi_node_options_environment_allowed() != 0);
}
fn set(map: *Map, key: []const u8, value: []const u8) void {
    c.pi_node_environment_map_lock(map);
    defer c.pi_node_environment_map_unlock(map);
    c.pi_node_environment_map_set_locked(map, key.ptr, key.len, value.ptr, value.len);
}

const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    paths_memory: ?*anyopaque = null,
    paths: ?*Paths = null,
    map: ?*Map = null,
    storage: ?[*]u8 = null,
    storage_bytes: usize = 0,
    storage_alignment: std.mem.Alignment = .@"1",
    storage_charged: bool = false,
    before_map_used: usize = 0,

    fn init(self: *Fixture) !void { try self.initArgs(&.{}); }
    fn initArgs(self: *Fixture, args: []const Span) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        self.paths_memory = self.memory;
        c.pi_js_retain_memory_owner(self.paths_memory);
        self.storage_bytes = c.pi_node_environment_paths_storage_size();
        self.storage_alignment = .fromByteUnits(c.pi_node_environment_paths_storage_alignment());
        if (c.pi_js_native_memory_reserve(self.paths_memory, self.storage_bytes) == 0)
            return error.OutOfMemory;
        self.storage_charged = true;
        self.storage = std.heap.c_allocator.rawAlloc(self.storage_bytes,
            self.storage_alignment, @returnAddress()) orelse return error.OutOfMemory;
        self.paths = c.pi_node_environment_paths_construct(self.storage.?,
            self.paths_memory, args.ptr, args.len) orelse return error.MissingNativePaths;
        self.before_map_used = self.used();
        self.map = c.pi_node_environment_map_create(self.memory, self.context) orelse return error.MissingNativeMap;
    }
    fn closeMap(self: *Fixture) void {
        if (self.map) |map| { self.map = null; c.pi_node_environment_map_release(map); }
    }
    fn destroyPaths(self: *Fixture) void {
        if (self.paths) |paths| {
            self.paths = null;
            c.pi_node_environment_paths_destroy(paths);
        }
        if (self.storage) |storage| {
            self.storage = null;
            std.heap.c_allocator.rawFree(storage[0..self.storage_bytes],
                self.storage_alignment, @returnAddress());
        }
        if (self.storage_charged) {
            self.storage_charged = false;
            c.pi_js_native_memory_release(self.paths_memory, self.storage_bytes);
        }
        if (self.paths_memory) |memory| {
            self.paths_memory = null;
            c.pi_js_release_memory_owner(memory);
        }
    }
    fn closeVm(self: *Fixture) void {
        if (self.context) |context| {
            self.context = null;
            while (c.JS_HasException(context))
                c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn releaseCallerMemory(self: *Fixture) void {
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn deinit(self: *Fixture) void {
        self.closeMap();
        self.destroyPaths();
        self.closeVm();
        self.releaseCallerMemory();
    }
    fn used(self: *Fixture) usize {
        return c.pi_js_native_memory_used(self.memory orelse self.paths_memory.?);
    }
    fn resolve(self: *Fixture, parts: []const Span, trace: *const Trace, output: *Capture) void {
        c.pi_node_environment_path_resolve(self.paths.?, self.paths_memory,
            self.context, self.map.?, trace, parts.ptr, parts.len, Capture.receive, output);
    }
    fn getenv(self: *Fixture, key: [*:0]const u8, trace: *const Trace, output: *Capture) c_int {
        return c.pi_node_environment_safe_getenv(self.paths_memory, self.context,
            self.map.?, trace, key, Capture.receive, output);
    }
};
const Capture = struct {
    bytes: [8192]u8 = undefined,
    length: usize = 0,
    calls: usize = 0,
    overflow: bool = false,
    memory: ?*anyopaque = null,
    used_during: usize = 0,
    fn receive(raw: ?*anyopaque, bytes: [*c]const u8, length: usize) callconv(.c) void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.memory != null) self.used_during = c.pi_js_native_memory_used(self.memory);
        if (length > self.bytes.len) { self.overflow = true; return; }
        self.length = length;
        @memcpy(self.bytes[0..length], bytes[0..length]);
    }
    fn expect(self: *const Capture, expected: []const u8) !void {
        try std.testing.expect(!self.overflow);
        try std.testing.expectEqual(@as(usize, 1), self.calls);
        try std.testing.expectEqualStrings(expected, self.bytes[0..self.length]);
    }
};

// An explicit native test observer of the required diagnostic callbacks. No
// actual stack content or production default callback is claimed by this root.
const TraceProbe = struct {
    events: [4]u8 = undefined,
    count: usize = 0,
    overflow: bool = false,
    context: ?*c.JSContext = null,
    trace_to_mutate: ?*Trace = null,
    map_to_replace: ?*Map = null,
    caller_map_to_release: ?*Map = null,
    memory: ?*anyopaque = null,
    used_during: usize = 0,
    fn append(self: *TraceProbe, value: u8) void {
        if (self.count == self.events.len) { self.overflow = true; return; }
        self.events[self.count] = value; self.count += 1;
    }
    fn native(raw: ?*anyopaque) callconv(.c) void {
        const self: *TraceProbe = @ptrCast(@alignCast(raw.?));
        self.append(1);
        if (self.memory != null) self.used_during = c.pi_js_native_memory_used(self.memory);
        if (self.trace_to_mutate) |trace| trace.print_js_stack = 0;
        if (self.map_to_replace) |map| set(map, "selected", "replacement");
        if (self.caller_map_to_release) |map| {
            self.caller_map_to_release = null;
            c.pi_node_environment_map_release(map);
        }
    }
    fn js(raw: ?*anyopaque, context: ?*c.JSContext) callconv(.c) void {
        const self: *TraceProbe = @ptrCast(@alignCast(raw.?));
        self.append(2); self.context = context;
    }
    fn expect(self: *const TraceProbe, expected: []const u8) !void {
        try std.testing.expect(!self.overflow);
        try std.testing.expectEqualSlices(u8, expected, self.events[0..self.count]);
    }
};
fn traced(probe: *TraceProbe, native: bool, js: bool) Trace {
    var result = quietTrace();
    result.print_native_stack = @intFromBool(native);
    result.print_js_stack = @intFromBool(js);
    result.native_stack = TraceProbe.native;
    result.js_stack = TraceProbe.js;
    result.user = probe;
    return result;
}
const ResolveOperation = struct {
    fixture: *Fixture,
    parts: []const Span,
    trace: *const Trace,
    output: Capture = .{},
    called: bool = false,
    fn run(raw: ?*anyopaque) callconv(.c) void {
        const self: *ResolveOperation = @ptrCast(@alignCast(raw.?));
        self.called = true;
        self.fixture.resolve(self.parts, self.trace, &self.output);
    }
};

test "native environment paths captures the actual executable independently of caller argv bytes" {
    var argv0 = ("caller-argv-" ++ ("a" ** 300)).*;
    var second = "mutable-native-argument".*;
    const args = [_]Span{span(&argv0), span(&second)};
    var f: Fixture = .{}; try f.initArgs(&args); defer f.deinit();
    @memset(&argv0, 'x'); @memset(&second, 'y');
    var expected: [2 * c.PATH_MAX]u8 = undefined;
    var length: usize = expected.len;
    try std.testing.expectEqual(@as(c_int, 0), c.uv_exepath(&expected, &length));
    var output: Capture = .{};
    c.pi_node_environment_paths_exec_path(f.paths.?, Capture.receive, &output);
    try output.expect(expected[0..length]);
    try std.testing.expect(!std.mem.eql(u8, output.bytes[0..output.length], &argv0));
}

test "native environment paths reads the actual native working directory" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const capacity = if (windows) c.MAX_PATH * 4 else c.PATH_MAX;
    var expected: [capacity]u8 = undefined;
    var length: usize = expected.len;
    try std.testing.expectEqual(@as(c_int, 0), c.uv_cwd(&expected, &length));
    var output: Capture = .{};
    c.pi_node_environment_paths_cwd(f.paths.?, f.paths_memory, f.context, Capture.receive, &output);
    try output.expect(expected[0..length]);
}

test "native environment paths normalizes absolute dot and parent segments without trace" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var probe: TraceProbe = .{}; const trace = traced(&probe, true, true);
    const input = if (windows) "C:\\alpha\\.\\branch\\..\\beta" else "/alpha/./branch/../beta";
    const expected = if (windows) "C:\\alpha\\beta" else "/alpha/beta";
    const parts = [_]Span{span(input)};
    var output: Capture = .{}; f.resolve(&parts, &trace, &output);
    try output.expect(expected);
    try probe.expect(&.{});
}

test "native environment paths selects the rightmost absolute tail and original drive" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const trace = quietTrace();
    const parts = [_]Span{
        span(if (windows) "C:\\discard\\old" else "/discard/old"),
        span(if (windows) "\\selected" else "/selected"), span("branch"), span(".."), span("leaf"),
    };
    var output: Capture = .{}; f.resolve(&parts, &trace, &output);
    try output.expect(if (windows) "C:\\selected\\leaf" else "/selected/leaf");
}

test "native environment paths retains real UNC device roots or POSIX backslash bytes" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const trace = quietTrace();
    const first = [_]Span{span(if (windows) "\\\\server\\share\\a\\..\\leaf" else "//server/share/a/../leaf")};
    var first_output: Capture = .{}; f.resolve(&first, &trace, &first_output);
    try first_output.expect(if (windows) "\\\\server\\share\\leaf" else "/server/share/leaf");
    const second = [_]Span{span(if (windows) "\\\\?\\C:\\a\\..\\leaf" else "/base/a\\..\\leaf")};
    var second_output: Capture = .{}; f.resolve(&second, &trace, &second_output);
    try second_output.expect(if (windows) "\\\\?\\C:\\leaf" else "/base/a\\..\\leaf");
}

test "native environment paths selects live supplied drive variables only on Windows" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    set(f.map.?, "=Z:", "Z:\\from-map");
    var probe: TraceProbe = .{}; const trace = traced(&probe, true, false);
    var output: Capture = .{};
    if (windows) {
        try requireEnvironmentAdmission();
        const parts = [_]Span{span("Z:child")};
        f.resolve(&parts, &trace, &output);
        try output.expect("Z:\\from-map\\child");
        try probe.expect(&.{1});
    } else {
        const parts = [_]Span{span("/base"), span("Z:child")};
        f.resolve(&parts, &trace, &output);
        try output.expect("/base/Z:child");
        try probe.expect(&.{});
    }
}

test "native environment paths SafeGetenv distinguishes an absent value from an empty string" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    const trace = quietTrace();
    var missing: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 0), f.getenv("missing", &trace, &missing));
    try std.testing.expectEqual(@as(usize, 0), missing.calls);
    set(f.map.?, "empty", "");
    var empty: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 1), f.getenv("empty", &trace, &empty));
    try empty.expect("");
}

test "native environment paths SafeGetenv preserves the actual C string key selection" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    set(f.map.?, "prefix", "plain");
    set(f.map.?, "prefix\x00suffix", "full-span");
    const trace = quietTrace();
    var output: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 1), f.getenv("prefix\x00suffix", &trace, &output));
    try output.expect("plain");
}

test "native environment paths copies the live Map value before native trace reentry" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    set(f.map.?, "selected", long_value);
    var probe: TraceProbe = .{ .map_to_replace = f.map.? };
    const trace = traced(&probe, true, false);
    var first: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 1), f.getenv("selected", &trace, &first));
    try first.expect(long_value); try probe.expect(&.{1});
    const quiet = quietTrace();
    var later: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 1), f.getenv("selected", &quiet, &later));
    try later.expect("replacement");
}

test "native environment paths snapshots trace options before native and JS delegation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    var probe: TraceProbe = .{};
    var trace = traced(&probe, true, true);
    probe.trace_to_mutate = &trace;
    var output: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 0), f.getenv("missing", &trace, &output));
    try probe.expect(&.{1, 2});
    try std.testing.expect(probe.context == f.context);
    try std.testing.expectEqual(@as(c_int, 0), trace.print_js_stack);
    try std.testing.expectEqual(@as(usize, 0), output.calls);
}

test "native environment paths retains both SafeGetenv string copies through trace only" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    set(f.map.?, "copy", long_value);
    const before = f.used();
    var probe: TraceProbe = .{ .memory = f.memory };
    const trace = traced(&probe, true, false);
    var output: Capture = .{ .memory = f.memory };
    try std.testing.expectEqual(@as(c_int, 1), f.getenv("copy", &trace, &output));
    try output.expect(long_value); try probe.expect(&.{1});
    try std.testing.expect(output.used_during > before);
    try std.testing.expectEqual((output.used_during - before) * 2, probe.used_during - before);
    try std.testing.expectEqual(before, f.used());
}

test "native environment paths retries a real native allocation with the original new handler" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const trace = quietTrace();
    const base = if (windows) "C:\\root" else "/root";
    const expected = if (windows) "C:\\root\\" ++ long_component else "/root/" ++ long_component;
    const parts = [_]Span{span(base), span(long_component)};
    var operation: ResolveOperation = .{ .fixture = &f, .parts = &parts, .trace = &trace };
    var observed: c.PiEnvironmentRetryObservation = std.mem.zeroes(c.PiEnvironmentRetryObservation);
    const before = f.used();
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_environment_test_retry(
        f.memory, memory_limit, ResolveOperation.run, &operation, &observed));
    try std.testing.expect(operation.called);
    try operation.output.expect(expected);
    try std.testing.expectEqual(@as(usize, 1), observed.calls);
    try std.testing.expectEqual(memory_limit, observed.first_used);
    try std.testing.expect(observed.reserved != 0);
    try std.testing.expectEqual(before, f.used());
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "native environment paths preserves actual pending identity under the exhausted JS heap" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    set(f.map.?, "heap", long_value);
    const trace = quietTrace();
    for ([_]bool{false, true}) |flagged| {
        const reason = c.JS_NewError(f.context.?);
        defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(!c.JS_IsException(reason));
        if (flagged) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
        var output: Capture = .{};
        var found: c_int = undefined;
        {
            c.JS_SetMemoryLimit(f.runtime.?, 1);
            defer c.JS_SetMemoryLimit(f.runtime.?, 0);
            found = f.getenv("heap", &trace, &output);
        }
        try std.testing.expectEqual(@as(c_int, 1), found);
        try output.expect(long_value);
        try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
        try std.testing.expect(c.JS_HasException(f.context.?));
        const actual = c.JS_GetException(f.context.?);
        defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
        try std.testing.expectEqual(flagged, c.JS_IsUncatchableError(actual));
    }
}

test "native environment paths owns its native strings after runtime and caller retirement" {
    const owners = c.pi_js_native_memory_owners();
    var argv0 = ("retained-argv-" ++ ("a" ** 300)).*;
    const args = [_]Span{span(&argv0)};
    var f: Fixture = .{}; try f.initArgs(&args); defer f.deinit();
    var before: Capture = .{};
    c.pi_node_environment_paths_exec_path(f.paths.?, Capture.receive, &before);
    @memset(&argv0, 'x');
    f.closeMap(); f.closeVm(); f.releaseCallerMemory();
    try std.testing.expect(f.runtime == null and f.context == null and f.memory == null);
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    var after: Capture = .{};
    c.pi_node_environment_paths_exec_path(f.paths.?, Capture.receive, &after);
    try before.expect(after.bytes[0..after.length]);
    try std.testing.expectEqual(@as(usize, 1), after.calls);
    try std.testing.expect(!after.overflow);
    f.destroyPaths();
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

test "native environment paths retains Map through trace and returns a surviving text copy" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try requireEnvironmentAdmission();
    set(f.map.?, "release", long_value);
    const map = f.map.?; f.map = null;
    var probe: TraceProbe = .{ .caller_map_to_release = map };
    defer if (probe.caller_map_to_release) |held| c.pi_node_environment_map_release(held);
    const trace = traced(&probe, true, false);
    var output: Capture = .{};
    try std.testing.expectEqual(@as(c_int, 1),
        c.pi_node_environment_safe_getenv(f.paths_memory, f.context, map,
            &trace, "release", Capture.receive, &output));
    try probe.expect(&.{1});
    try std.testing.expect(probe.caller_map_to_release == null);
    try output.expect(long_value);
    try std.testing.expectEqual(f.before_map_used, f.used());
}
