//! Twenty-three authored controls over the genuine classic fs.realpathSync owner.
//! Sixteen observers also target pinned Node v24.13. Seven native controls use
//! actual finalizers/DATA/stat buffers. This is an install-only test target;
//! physical IO and reference capture require Root's separate runtime grants.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const classic = @import("extensions/native_node_fs_realpath_classic.zig");
const stat_values = @import("extensions/native_node_fs_stat_values.zig");
const callable = @import("extensions/native_node_module_callable.zig");
const source = @embedFile("extensions/fixtures/native-node-classic-realpath-observer.mjs");
const gpa = std.testing.allocator;
const io = std.testing.io;

// Use the public Windows API's existing unprivileged-create request. The
// pinned std.Io implementation writes a reparse tag without that request.
// This neither grants a privilege nor changes Developer Mode; a denied
// request remains a failing physical-link prerequisite for these controls.
extern "kernel32" fn CreateSymbolicLinkW(
    link: [*:0]const u16,
    target: [*:0]const u16,
    flags: u32,
) callconv(.winapi) std.os.windows.BOOLEAN;

const Probe = struct {
    engine: *a.v.em.Engine,
    class: c.JSClassID = 0,
    freed: u32 = 0,
    visits: [3]u32 = .{0} ** 3,
    fatal_on_release: bool = false,
    first: c.JSValue,
};
var active_probe: ?*Probe = null;
fn releaseHolder(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.freed += 1;
    if (probe.fatal_on_release) {
        _ = probe.engine.throwNativeOutOfMemoryFatal();
        const reason = c.JS_GetException(probe.engine.context);
        if (c.JS_IsUndefined(probe.first)) probe.first = c.JS_DupValue(probe.engine.context, reason);
        _ = c.JS_Throw(probe.engine.context, reason);
    }
}
fn makeHolder(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = active_probe.?;
    const value = c.JS_NewObjectClass(context, probe.class);
    if (c.JS_IsException(value)) return value;
    _ = c.JS_SetOpaque(value, probe);
    return value;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_NewUint32(context, active_probe.?.freed);
}
fn visit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    var position: u32 = 0;
    if (argc != 1 or c.JS_ToUint32(context, &position, argv[0]) < 0 or position >= 3)
        return c.JS_ThrowInternalError(context, "Invalid actual classic control visit");
    active_probe.?.visits[position] += 1;
    return c.pi_js_undefined();
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = a.v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, result);
    return result;
}

const Fixture = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    probe: Probe,
    fn symlink(self: *Fixture, target: []const u8, name: []const u8, directory: bool) !void {
        if (@import("builtin").os.tag != .windows)
            return self.temporary.dir.symLink(io, target, name, .{ .is_directory = directory });
        const link_path = try std.fs.path.join(gpa, &.{ self.root, name });
        defer gpa.free(link_path);
        const link_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, link_path);
        defer gpa.free(link_w);
        const target_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, target);
        defer gpa.free(target_w);
        const flags: u32 = 0x2 | @as(u32, @intFromBool(directory));
        if (CreateSymbolicLinkW(link_w.ptr, target_w.ptr, flags) != .FALSE) return;
        const status = std.os.windows.GetLastError();
        std.debug.print("Actual classic symlink {s} failed with Win32 {d}\n", .{ name, @intFromEnum(status) });
        return error.ActualClassicSymbolicLinkCreationFailed;
    }
    fn init(self: *Fixture) !void {
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        try self.temporary.dir.createDirPath(io, "dir/nested");
        try self.temporary.dir.writeFile(io, .{ .sub_path = "dir/file.txt", .data = "classic\n" });
        try self.temporary.dir.writeFile(io, .{ .sub_path = "dir/nested/end.txt", .data = "end\n" });
        var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try self.temporary.dir.realPath(io, &path);
        self.root = try gpa.dupe(u8, path[0..count]);
        errdefer gpa.free(self.root);
        const absolute_file = try std.fs.path.join(gpa, &.{ self.root, "dir", "file.txt" });
        defer gpa.free(absolute_file);
        // These are the test's own physical links, all within its fresh
        // contained directory. No external file, listener or process is used.
        try self.symlink(if (@import("builtin").os.tag == .windows) "dir\\file.txt" else "dir/file.txt", "relative-file", false);
        try self.symlink(absolute_file, "absolute-file", false);
        try self.symlink("relative-file", "chain-file", false);
        try self.symlink("dir", "directory-link", true);
        try self.symlink("directory-link", "second-directory", true);
        try self.symlink("missing-target", "broken-link", false);
        try self.symlink("loop-b", "loop-a", false);
        try self.symlink("loop-a", "loop-b", false);
        self.environment = .init(gpa);
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{ .interrupt_budget = 4_000_000 });
        errdefer self.engine.deinit();
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/timers.zig").install(self.engine, io);
        try @import("extensions/native_process.zig").install(self.engine, io, &self.environment, &.{"native-classic-realpath-control"});
        try @import("extensions/node_path.zig").install(self.engine, io);
        try @import("extensions/node_url.zig").install(self.engine);
        try @import("extensions/native_node_os.zig").install(self.engine);
        const actual_process = (try self.engine.requireBuiltin("node:process")) orelse return error.ActualClassicProcessRequired;
        defer self.engine.freeValue(actual_process);
        try @import("extensions/node_fs.zig").installWithStreams(self.engine, io, actual_process);
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.class);
        const definition: c.JSClassDef = .{ .class_name = "Actual classic cache equality operand", .finalizer = releaseHolder };
        if (c.JS_NewClass(self.engine.runtime, self.probe.class, &definition) < 0) return error.OutOfMemory;
        var s = a.Scope.init(self.engine);
        _ = try s.finish(self.installView(&s));
        try self.engine.bindFunction("actualClassicHolder", makeHolder, 0);
        try self.engine.bindFunction("actualClassicFreed", freedCount, 0);
        try self.engine.bindFunction("actualClassicVisit", visit, 1);
        try self.engine.bindFunction("actualClassicPrivateData", privateData, 0);
        try self.engine.bindFunction("actualClassicFlaggedData", flaggedData, 0);
    }
    fn installView(self: *Fixture, s: *a.Scope) !c.JSValue {
        const fs = try s.own((try s.engine.requireBuiltin("node:fs")) orelse return error.ActualClassicFsRequired);
        const paths = try s.own((try s.engine.requireBuiltin("node:path")) orelse return error.ActualClassicPathsRequired);
        const actual = try s.get(fs, "realpathSync");
        try classic.requireInstalled(s.engine, actual);
        const repeated = try s.own(try classic.create(s.engine, fs, paths));
        try std.testing.expect(s.equal(actual, repeated));
        const captured = try callable.capturedRoots(s.engine, actual);
        try std.testing.expectEqual(@as(usize, 1), captured.len);
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const view = try s.object();
        const namespace = s.engine.native_module_values.get("node:fs") orelse return error.ActualClassicNamespaceRequired;
        try s.put(view, "fs", fs);
        try s.put(view, "paths", paths);
        try s.put(view, "realpath", actual);
        try s.put(view, "namedRealpath", try s.get(namespace, "realpathSync"));
        try s.put(view, "nativeOriginal", try s.get(captured[0], "native"));
        try s.put(view, "root", try s.text(self.root));
        try s.put(view, "platform", try s.get(process, "platform"));
        try s.put(view, "URL", try s.get(global, "URL"));
        const helper_owner = try s.own(try @import("extensions/native_node_fs_path_bootstrap.zig").prepare(s.engine));
        try s.put(view, "Buffer", try s.get(helper_owner, "Buffer"));
        try s.put(view, "key", try s.get(helper_owner, "realpathCacheKey"));
        try s.put(global, "actualClassic", view);
        const buffers = try s.own(try stat_values.acquire(s.engine));
        try s.put(global, "actualClassicNumericStats", stat_values.numeric(buffers));
        try s.put(global, "actualClassicBigintStats", stat_values.bigint(buffers));
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        self.probe.fatal_on_release = false;
        self.engine.freeValue(self.probe.first);
        self.engine.deinit();
        active_probe = null;
        self.environment.deinit();
        gpa.free(self.root);
        self.temporary.cleanup();
    }
    fn run(self: *Fixture, tail: []const u8) !c.JSValue {
        const body = try std.mem.concat(gpa, u8, &.{ source, "\n", tail });
        defer gpa.free(body);
        return self.engine.eval(body, "actual-node-classic-realpath-control.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn runExpected(self: *Fixture, comptime name: []const u8, tail: []const u8) !c.JSValue {
        return self.run(tail) catch |err| {
            std.debug.print("Actual classic realpath {s}: {s}; captured={s}\n",
                .{ name, @errorName(err), self.engine.last_error orelse "no captured diagnostic" });
            return err;
        };
    }
    fn observe(self: *Fixture, comptime name: []const u8) !void {
        const result = try self.runExpected(name, name ++ "(actualClassic);");
        self.engine.freeValue(result);
        try self.clean();
    }
    fn clean(self: *Fixture) !void {
        try std.testing.expect(self.engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
        try std.testing.expect(!c.JS_IsJobPending(self.engine.runtime));
    }
};
fn observe(comptime name: []const u8) !void {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.observe(name);
}
test "native actual classic realpath published CJS and named owner identities" {
    try observe("observeClassicShape");
}
test "native actual classic realpath walks files directories and resolved input" {
    try observe("observeClassicPlain");
}
test "native actual classic realpath resolves relative absolute and chained file links" {
    try observe("observeClassicFileLinks");
}
test "native actual classic realpath restarts through linked directory suffixes" {
    try observe("observeClassicDirectoryLinks");
}
test "native actual classic realpath keeps options URL Buffer and default coercion order" {
    try observe("observeClassicPathInputs");
}
test "native actual classic realpath options failure precedes conversion and resolve" {
    try observe("observeClassicOptionFailure");
}
test "native actual classic realpath truthy cached DATA bypasses OS and encoding" {
    try observe("observeClassicTruthyCache");
}
test "native actual classic realpath consumes the live actual path resolve owner" {
    try observe("observeClassicLiveResolve");
}
test "native actual classic realpath hard cache equality has exact lookup order" {
    try observe("observeClassicCacheOrder");
}
test "native actual classic realpath cached link restarts the remaining walk" {
    try observe("observeClassicCachedLink");
}
test "native actual classic realpath encoding rereads and receiver selection stay live" {
    try observe("observeClassicEncoding");
}
test "native actual classic realpath uses actual Buffer path encodings" {
    try observe("observeClassicBuiltinEncoding");
}
test "native actual classic realpath retains raw ENOENT path syscall and intrinsic Error" {
    try observe("observeClassicNativeErrors");
}
test "native actual classic realpath followed stat reports actual link loops" {
    try observe("observeClassicLinkLoop");
}
test "native actual classic realpath retains original string collection and regex primordials" {
    try observe("observeClassicCapturedIntrinsics");
}
test "native actual classic realpath final cache failure precedes encoding" {
    try observe("observeClassicCacheSetFailure");
}
test "native actual classic realpath cache equality retires its sole holder before next read" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const result = try fixture.runExpected("cache equality holder retirement", "observeClassicCacheRetirement(actualClassic);");
    fixture.engine.freeValue(result);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    try std.testing.expectEqual([3]u32{ 1, 1, 0 }, fixture.probe.visits);
    try fixture.clean();
}
test "native actual classic realpath cache equality retirement B prevents next read and catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    fixture.probe.fatal_on_release = true;
    const attempted = fixture.run("observeClassicCacheRetirement(actualClassic);");
    if (attempted) |value| {
        fixture.engine.freeValue(value);
        return error.ExpectedActualClassicRetirementFatal;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    try std.testing.expectEqual([3]u32{ 1, 0, 0 }, fixture.probe.visits);
    const reason = fixture.engine.captured_exception orelse return error.ExpectedActualClassicFatalReason;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual classic realpath same-operation private DATA remains ordinary" {
    try observe("observeClassicPrivateThrow");
}
test "native actual classic realpath successful flagged cache DATA stays a returned value" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const value = try fixture.runExpected("flagged cache DATA", "observeClassicFlaggedCache(actualClassic);");
    defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(value) != 0);
    try fixture.clean();
}
test "native actual classic realpath and public metadata share the actual stat buffers" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const value = try fixture.runExpected("shared stat buffers", "observeClassicSharedStatBuffers(actualClassic,actualClassicNumericStats,actualClassicBigintStats);");
    fixture.engine.freeValue(value);
    try fixture.clean();
}

test "native actual classic realpath original p argument retires before live resolve getter" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const result = try fixture.runExpected("original p retirement",
        \\const paths = actualClassic.paths, file = paths.join(actualClassic.root,"dir","file.txt");
        \\const original = Object.getOwnPropertyDescriptor(paths,"resolve");
        \\let converted = 0, resolved = 0;
        \\try {
        \\  Object.defineProperty(paths,"resolve",{configurable:true,get(){
        \\    resolved++;
        \\    classicAssert(actualClassicFreed() === 1,"original p argument retired before live resolve getter");
        \\    return original.value;
        \\  }});
        \\  const result = actualClassic.realpath({
        \\    owned:actualClassicHolder(),
        \\    [Symbol.toPrimitive]: function(hint){ converted++; classicAssert(hint === "default","actual p += empty-string default hint"); return file; }
        \\  }, undefined);
        \\  classicAssert(result === file && converted === 1 && resolved === 1,"actual converted path reaches the physical owner");
        \\} finally { Object.defineProperty(paths,"resolve",original); }
    );
    fixture.engine.freeValue(result);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    try fixture.clean();
}
test "native actual classic realpath original p retirement B prevents resolve getter and catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const progress = try fixture.engine.eval(
        "globalThis.actualClassicArgumentProgress = {convert:0,resolve:0,caught:0};",
        "actual-classic-argument-progress.js", c.JS_EVAL_TYPE_GLOBAL);
    defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_on_release = true;
    const attempted = fixture.run(
        \\const paths = actualClassic.paths, file = paths.join(actualClassic.root,"dir","file.txt");
        \\Object.defineProperty(paths,"resolve",{configurable:true,get(){
        \\  actualClassicArgumentProgress.resolve++;
        \\  throw Error("unreachable actual resolve");
        \\}});
        \\try {
        \\  actualClassic.realpath({
        \\    owned:actualClassicHolder(),
        \\    [Symbol.toPrimitive]: function(hint){ actualClassicArgumentProgress.convert++; return file; }
        \\  }, undefined);
        \\} catch { actualClassicArgumentProgress.caught++; }
    );
    if (attempted) |value| {
        fixture.engine.freeValue(value);
        return error.ExpectedActualClassicArgumentRetirementFatal;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    const reason = fixture.engine.captured_exception orelse return error.ExpectedActualClassicArgumentFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    inline for (.{ .{ "convert", @as(u32, 1) }, .{ "resolve", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
