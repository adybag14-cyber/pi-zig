//! Actual native Process.spawn argument consumption, after the Source prototype
//! has assigned stdio/spawnfile/the SAME spawnargs array. No normalization,
//! spread, cloned argv VM object or ignored options sidecar is performed here.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const frontier = @import("native_child_process_scope.zig");
const Scope = frontier.Scope;
const common = @import("native_child_process_options.zig");
const pipe = @import("native_child_process_pipe_record.zig");
const Environment = @import("native_child_process_environment.zig").Environment;
pub const Inputs = struct {
    pipes: *pipe.Provider,
    // Stable native map ticket only, never a frontend/Engine/stack pointer.
    linux_stdio: ?@import("native_child_process_stdio_linux.zig").Map = null,
    windows_stdio: ?@import("native_child_process_stdio_windows.zig").Map = null,
    stdio_source: ?@import("native_process_streams.zig").Lease = null,
    // Genuine embedding environment acquisition for direct raw spawn with no
    // envPairs. A supplied pair array never calls this provider.
    inherited_environment: ?*const fn (*js.Engine) anyerror!Environment = null,
};
pub const Native = struct {
    config: common.Config,
    records: [3]?pipe.Owned = .{null} ** 3,
    pub fn deinit(self: *Native) void {
        for (&self.records) |*record| if (record.*) |*value| { value.deinit(); record.* = null; };
        self.config.deinit();
    }
};
fn length(scope: *Scope, array: c.JSValue) !u32 { var value: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &value, try scope.get(array, "length")) < 0) return @as(anyerror!u32, js.capture(scope.engine)); try frontier.pending(scope.engine); return value; }
fn element(scope: *Scope, array: c.JSValue, index: u32) !c.JSValue { return scope.getIndex(array, index); }
fn text(engine: *js.Engine, value: c.JSValue) ![]u8 {
    const result = try engine.toString(value); errdefer engine.gpa.free(result);
    try frontier.pending(engine);
    if (std.mem.indexOfScalar(u8, result, 0) != null) return error.NativeSerializedSpawnTextNulUnsupported;
    return result;
}
pub fn consume(engine: *js.Engine, options: c.JSValue, inputs: Inputs) !Native {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try frontier.pending(engine);
    if (inputs.pipes.engine != engine) return error.NativePipeRecordOwner;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const file = try text(engine, try scope.get(options, "file"));
    var result: Native = .{ .config = .{ .gpa = engine.gpa, .environment = .init(engine.gpa), .original_file = file } };
    errdefer result.deinit();
    result.config.spawn_file = try engine.gpa.dupe(u8, file);
    const args = try scope.get(options, "args");
    if (!c.JS_IsArray(args)) return error.NativeProcessSpawnArgsArrayRequired;
    const count = try length(&scope, args);
    if (count == 0) return error.NativeProcessSpawnArgvRequired;
    for (0..count) |index| {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        const argument = try text(engine, try element(&row, args, @intCast(index))); defer engine.gpa.free(argument);
        try result.config.append(argument);
    }
    const cwd = try scope.get(options, "cwd");
    if (!c.JS_IsNull(cwd) and !c.JS_IsUndefined(cwd)) { result.config.cwd = try @import("node_fs_metadata.zig").pathTextNamed(engine, cwd, false, "options.cwd"); try frontier.pending(engine); }
    result.config.options.detached = scope.truthy(try scope.get(options, "detached"));
    result.config.options.windows_hide = scope.truthy(try scope.get(options, "windowsHide"));
    result.config.options.windows_verbatim_arguments = scope.truthy(try scope.get(options, "windowsVerbatimArguments"));
    if ((!c.JS_IsNull(try scope.get(options, "uid")) and !c.JS_IsUndefined(try scope.get(options, "uid"))) or (!c.JS_IsNull(try scope.get(options, "gid")) and !c.JS_IsUndefined(try scope.get(options, "gid")))) return error.RequiredNativeChildCredentialRouting;
    const pairs = try scope.get(options, "envPairs");
    if (c.JS_IsUndefined(pairs)) {
        const acquire = inputs.inherited_environment orelse return error.RequiredActualInheritedNativeEnvironment;
        const actual = try acquire(engine); result.config.environment.deinit(); result.config.environment = actual; try frontier.pending(engine);
    } else {
        if (!c.JS_IsArray(pairs)) return error.NativeProcessEnvironmentPairsArrayRequired;
        const pair_count = try length(&scope, pairs);
        for (0..pair_count) |index| {
            var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
            const pair = try text(engine, try element(&row, pairs, @intCast(index))); defer engine.gpa.free(pair);
            try result.config.environment.appendSerialized(pair);
        }
    }
    const stdio = try scope.get(options, "stdio");
    if (!c.JS_IsArray(stdio)) return error.NativeProcessStdioDescriptorsRequired;
    if (try length(&scope, stdio) != 3) return error.RequiredActualExtendedStdioProvider;
    for (&result.config.options.stdio, 0..) |*mode, index| {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        const descriptor = try element(&row, stdio, @intCast(index));
        const kind = try row.get(descriptor, "type");
        if (row.equal(kind, try row.text("ignore"))) { mode.* = .ignore; continue; }
        if (row.equal(kind, try row.text("inherit")) or row.equal(kind, try row.text("fd"))) {
            const descriptor_number = try row.get(descriptor, "fd");
            if (!c.JS_IsNumber(descriptor_number)) return error.NativeProcessStdioDescriptorNumberRequired;
            var fd: i32 = 0;
            if (c.JS_ToInt32(engine.context, &fd, descriptor_number) < 0) return @as(anyerror!Native, js.capture(engine));
            try frontier.pending(engine);
            if (inputs.stdio_source) |source| if (!@import("native_process_streams.zig").ownsLease(engine, source)) return error.NativeChildFrontendStdioLeaseRetired;
            switch (@import("builtin").os.tag) {
                .linux => result.config.options.linux_stdio[index] = try @import("native_child_process_stdio_linux.zig").acquire(inputs.linux_stdio orelse return error.NativeInheritedStdioRequiresFrontendRouting, fd),
                .windows => result.config.options.windows_stdio[index] = try @import("native_child_process_stdio_windows.zig").acquire(inputs.windows_stdio orelse return error.NativeInheritedStdioRequiresFrontendRouting, fd),
                else => return error.RequiredActualPlatformStdioBorrower,
            }
            mode.* = .inherited; continue;
        }
        const overlapped = row.equal(kind, try row.text("overlapped"));
        if (overlapped and @import("builtin").os.tag != .linux) return error.RequiredActualOverlappedChildHandleProvider;
        if (row.equal(kind, try row.text("wrap"))) return error.RequiredActualWrappedEndpointDuplication;
        if (!row.equal(kind, try row.text("pipe")) and !overlapped) return error.NativeProcessStdioDescriptorType;
        if (row.truthy(try row.get(descriptor, "ipc"))) return error.RequiredGenuineNativeIpcPipeProvider;
        const record = try inputs.pipes.own(try row.get(descriptor, "handle"));
        result.records[index] = record;
        if (record.state.phase != .unbound) return error.NativePipeRecordNotBindable;
        if (row.truthy(try row.get(descriptor, "readable")) != (index == 0) or row.truthy(try row.get(descriptor, "writable")) != (index != 0)) return error.RequiredActualStdioDirectionProvider;
        mode.* = .pipe;
    }
    const native_cwd = try std.process.currentPathAlloc(engine.native_io orelse return error.NativeIoUnavailable, engine.gpa); defer engine.gpa.free(native_cwd);
    const search_cwd = if (result.config.cwd) |directory| if (directory.len == 0) native_cwd else directory else native_cwd;
    result.config.executable = (try common.findExecutableFound(&result.config, file, search_cwd, false)) orelse try common.resolved(engine.gpa, search_cwd, file);
    result.config.options.executable = result.config.executable;
    try frontier.pending(engine);
    return result;
}

test "raw Process options success plus pending stops before later getters and native admission" {
    const Fixture = struct {
        fn file(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const global = c.JS_GetGlobalObject(context); defer c.JS_FreeValue(context, global);
            _ = c.JS_Throw(context, c.JS_GetPropertyStr(context, global, "rawSpawnPendingReason"));
            return c.JS_NewString(context, "/bin/true");
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var provider = try pipe.createProvider(engine); defer provider.deinit();
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, Fixture.file, "raw pending file getter", 0)); defer engine.freeValue(getter);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "rawPendingFileGetter", c.JS_DupValue(engine.context, getter));
    const supplied = try engine.eval("globalThis.rawSpawnPendingReason={toString(){throw Error('must not format')}};globalThis.rawSpawnLaterGetter=0;({get file(){return rawPendingFileGetter()},get args(){rawSpawnLaterGetter++;return ['/bin/true']}})", "raw-spawn-pending-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(supplied);
    try std.testing.expectError(error.JavaScriptException, consume(engine, supplied, .{ .pipes = &provider }));
    const captured = engine.captured_exception.?; engine.captured_exception = null; defer engine.freeValue(captured);
    const actual = try js.get(engine, global, "rawSpawnPendingReason"); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, actual));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    const result = try engine.eval("if(rawSpawnLaterGetter!==0)throw Error('later options getter ran')", "raw-spawn-pending-frontier", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(result);
}
