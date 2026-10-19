//! Nineteen authored controls over genuine Node internal/url path helpers.
//! Thirteen observers also run against pinned Node; no Source capture or native
//! execution is implied by this install-only root. No physical IO is started.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const paths = @import("extensions/native_node_file_url_paths.zig");

const Probe = struct {
    engine: *a.v.em.Engine,
    holder_class: c.JSClassID = 0,
    freed: u32 = 0,
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
    const value = c.JS_NewObjectClass(context, probe.holder_class);
    if (c.JS_IsException(value)) return value;
    _ = c.JS_SetOpaque(value, probe);
    return value;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_NewUint32(context, active_probe.?.freed);
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = a.v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, value);
    return value;
}
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    owner: ?c.JSValue = null,
    probe: Probe,
    fn init(self: *Fixture) !void { return self.initMode(true); }
    fn initMode(self: *Fixture, capture_url: bool) !void {
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        errdefer self.engine.deinit();
        self.owner = null;
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-file-url-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        if (capture_url) {
            self.owner = try paths.acquire(self.engine);
        } else {
            const prepared = try @import("extensions/native_node_argument_bootstrap.zig").prepare(self.engine);
            prepared.deinit(self.engine);
        }
        errdefer if (self.owner) |owner| self.engine.freeValue(owner);
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{ .class_name = "Actual file URL predicate temporary", .finalizer = releaseHolder };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0) return error.OutOfMemory;
        if (self.owner) |owner| {
            var scope = a.Scope.init(self.engine);
            _ = try scope.finish(installView(&scope, owner));
        }
        try self.engine.bindFunction("actualUrlPredicateHolder", makeHolder, 0);
        try self.engine.bindFunction("actualUrlFreedCount", freedCount, 0);
        try self.engine.bindFunction("actualUrlPrivateData", privateData, 0);
        try self.engine.bindFunction("actualUrlFlaggedData", flaggedData, 0);
    }
    fn installView(s: *a.Scope, owner: c.JSValue) !c.JSValue {
        const view = try s.object();
        inline for (.{ "isURL", "fileURLToPath", "toPathIfFileURL", "URL", "platform" }) |name|
            try s.put(view, name, try s.get(owner, name));
        const actual_errors = try s.get(owner, "errors");
        const errors_view = try s.object();
        inline for (.{
            .{ "ERR_INVALID_ARG_TYPE", "invalid_arg_type" },
            .{ "ERR_INVALID_URL_SCHEME", "invalid_url_scheme" },
            .{ "ERR_INVALID_FILE_URL_PATH", "invalid_file_url_path" },
            .{ "ERR_INVALID_FILE_URL_HOST", "invalid_file_url_host" },
        }) |pair| try s.put(errors_view, pair[0], try s.get(actual_errors, pair[1]));
        try s.put(view, "errors", errors_view);
        try s.put(view, "inspectModule", try s.get(actual_errors, "internal_inspect"));
        try s.put(view, "kEmptyObject", try s.get(owner, "empty"));
        try s.put(view, "marker", try s.get(actual_errors, "marker"));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.put(global, "actualFileUrl", view);
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        self.probe.fatal_on_release = false;
        self.engine.freeValue(self.probe.first);
        if (self.owner) |owner| self.engine.freeValue(owner);
        self.engine.deinit();
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{ @embedFile("extensions/fixtures/native-node-file-url-observer.mjs"), "\n", tail });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-file-url-observer.mjs");
        self.engine.freeValue(result);
    }
    fn value(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
};

fn observe(comptime name: []const u8) !void {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(name ++ "(actualFileUrl);");
}
test "native actual file URL structural predicate preserves short circuit reads" { try observe("observeUrlStructure"); }
test "native actual file URL toPath retains non URL identity and ordinary abrupt values" { try observe("observeUrlIdentity"); }
test "native actual file URL options precede path and protocol is read again" { try observe("observeUrlReadOrder"); }
test "native actual file URL toPath performs its separate structural gate" { try observe("observeUrlRepeatedGate"); }
test "native actual file URL nullish platform selection and truthy option do not coerce" { try observe("observeUrlWindowsChoice"); }
test "native actual file URL retains actual URL constructor and original decoder" { try observe("observeUrlCapturedIntrinsics"); }
test "native actual file URL throws genuine argument scheme host and input-bearing path errors" { try observe("observeUrlFailures"); }
test "native actual file URL encoded separator check precedes actual URI decoding" { try observe("observeUrlEncodedSeparators"); }
test "native actual file URL UNC uses genuine domain Unicode and IPv6 host parsing" { try observe("observeUrlUNC"); }
test "native actual file URL Windows replacement uses its genuine private RegExp realm" { try observe("observeUrlPrivateRegex"); }
test "native actual file URL ordinary functions admit structural primitive Symbols" { try observe("observeUrlSymbolAndShapes"); }
test "native actual file URL string error uses live formatter and preselected superclass" { try observe("observeUrlHostClass"); }
test "native actual file URL function messages retain repeated reads and eager coercion" { try observe("observeUrlFunctionMessages"); }

test "native actual file URL completed owner shares actual error marker URL and empty object" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const again = try paths.acquire(fixture.engine); defer fixture.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, again, fixture.owner.?));
    var s = a.Scope.init(fixture.engine);
    _ = try s.finish(verifyOwner(&s, fixture.owner.?));
    try fixture.run(
        \\urlPathAssert(typeof actualFileUrl.marker === "symbol", "existing real Node error marker");
        \\urlPathAssert(Object.isFrozen(actualFileUrl.kEmptyObject) && Object.getPrototypeOf(actualFileUrl.kEmptyObject) === null, "same genuine empty owner");
        \\urlPathAssert(new actualFileUrl.errors.ERR_INVALID_URL_SCHEME("file")[actualFileUrl.marker] === true, "actual marker getter on genuine class");
    );
}
fn verifyOwner(s: *a.Scope, owner: c.JSValue) !c.JSValue {
    const system = try s.own(a.duplicate(s.engine, try @import("extensions/native_node_system_errors.zig").registry(s.engine)));
    const errors = try s.get(owner, "errors");
    try std.testing.expect(s.equal(try s.get(errors, "marker"), try s.get(system, "marker")));
    try std.testing.expect(s.equal(try s.get(owner, "URL"), s.engine.native_url_constructor.?));
    const empty = try s.own(try @import("extensions/native_node_internal_empty_object.zig").acquire(s.engine));
    try std.testing.expect(s.equal(try s.get(owner, "empty"), empty));
    const regex_owner = try s.own(try @import("extensions/native_node_internal_regex.zig").acquire(s.engine));
    try std.testing.expect(s.equal(try s.get(owner, "regex_owner"), regex_owner));
    return c.pi_js_undefined();
}
test "native actual file URL predicate retires before next read while windows local survives body" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(
        \\const input = {
        \\  get href() { return actualUrlPredicateHolder(); },
        \\  get protocol() { urlPathAssert(actualUrlFreedCount() === 1, "href predicate retired before protocol"); return "file:"; }
        \\};
        \\urlPathAssert(actualFileUrl.isURL(input) === true, "predicate continues after normal release");
        \\const options = {get windows() { return actualUrlPredicateHolder(); }};
        \\const path = {href:"selected", protocol:"file:", hostname:"",
        \\  get pathname() { urlPathAssert(actualUrlFreedCount() === 1, "const windows remains live in actual path body"); return "/C:/selected"; }};
        \\urlPathAssert(actualFileUrl.fileURLToPath(path, options) === "C:\\selected", "real body uses truthy windows local");
        \\urlPathAssert(actualUrlFreedCount() === 2, "windows local retires at actual function exit");
    );
    try std.testing.expectEqual(@as(u32, 2), fixture.probe.freed);
    try fixture.engine.checkNativeEntry();
}
test "native actual file URL predicate finalizer fatal stops later protocol and guest catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run("globalThis.actualUrlProgress = {href:0, protocol:0, caught:0};");
    const progress = try fixture.value("actualUrlProgress"); defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_on_release = true;
    const result = fixture.run(
        \\const input = {
        \\  get href() { actualUrlProgress.href++; return actualUrlPredicateHolder(); },
        \\  get protocol() { actualUrlProgress.protocol++; return "file:"; }
        \\};
        \\try { actualFileUrl.isURL(input); } catch { actualUrlProgress.caught++; }
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualUrlPathReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.probe.first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // Retained own numeric data only; no post-fatal guest lookup or evaluation.
    inline for (.{ .{ "href", @as(u32, 1) }, .{ "protocol", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
test "native actual file URL same getter private DATA throw remains ordinary" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedUrlPathData = undefined;
        \\const input = {get href() { savedUrlPathData = actualUrlPrivateData(); throw savedUrlPathData; }};
        \\urlPathAssert(urlPathThrown(() => actualFileUrl.fileURLToPath(input)) === savedUrlPathData, "ordinary private getter DATA");
    );
    const value = try fixture.value("savedUrlPathData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual file URL successful flagged predicate value remains DATA" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedUrlPathData = undefined;
        \\let protocol = 0;
        \\const input = {
        \\  get href() { return savedUrlPathData = actualUrlFlaggedData(); },
        \\  get protocol() { protocol++; return "file:"; }
        \\};
        \\urlPathAssert(actualFileUrl.isURL(input) === true && protocol === 1, "successful flagged truthy DATA permits the next getter");
    );
    const value = try fixture.value("savedUrlPathData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}

test "native actual file URL new error families reuse original argument bootstrap primordials" {
    var fixture: Fixture = undefined; try fixture.initMode(false); defer fixture.deinit();
    // Complete the genuine argument/inspector owner first. The three URL
    // error families have not been acquired, and no replacement providers exist.
    try fixture.run(
        \\globalThis.actualUrlSavedApply = Object.getOwnPropertyDescriptor(Reflect, "apply");
        \\globalThis.actualUrlSavedUnshift = Object.getOwnPropertyDescriptor(Array.prototype, "unshift");
        \\Object.defineProperty(Reflect, "apply", {configurable:true, get() { throw Error("late Reflect.apply snapshot"); }});
        \\Object.defineProperty(Array.prototype, "unshift", {configurable:true, get() { throw Error("late Array.unshift snapshot"); }});
    );
    const errors = try @import("extensions/native_node_file_url_errors.zig").acquire(fixture.engine);
    defer fixture.engine.freeValue(errors);
    try fixture.run(
        \\Object.defineProperty(Reflect, "apply", actualUrlSavedApply);
        \\Object.defineProperty(Array.prototype, "unshift", actualUrlSavedUnshift);
        \\delete globalThis.actualUrlSavedApply;
        \\delete globalThis.actualUrlSavedUnshift;
    );
    fixture.owner = try paths.acquire(fixture.engine);
    var s = a.Scope.init(fixture.engine);
    _ = try s.finish(Fixture.installView(&s, fixture.owner.?));
    try fixture.run(
        \\const host = new actualFileUrl.errors.ERR_INVALID_FILE_URL_HOST("preserved");
        \\urlPathAssert(host.message === 'File URL host must be "localhost" or empty on preserved', "actual retained formatter/rest path");
        \\const scheme = new actualFileUrl.errors.ERR_INVALID_URL_SCHEME("file");
        \\urlPathAssert(scheme.message === "The URL must be of scheme file", "actual retained ReflectApply in function-message path");
    );
    try fixture.engine.checkNativeEntry();
}
